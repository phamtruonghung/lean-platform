# Platform

One application for running several manufacturing plants: it records the work
that happens on the floor and reports the numbers that work produces.

It replaces two earlier applications — a people directory and a maintenance
system — which become **Modules** inside it rather than separate deployments.
The vocabulary is defined in [`CONTEXT.md`](./CONTEXT.md) and the decisions
behind the shape of it in [`docs/adr/`](./docs/adr).

Flutter Web frontend, Express API, Supabase Cloud Postgres. The API runs as a
container on a self-hosted LXC behind a reverse proxy; the frontend is served
from the same hostname, so the browser sees one origin and there is no CORS
anywhere in this repository.

```
lean-platform/
├── frontend/        Flutter web app
├── backend/         Express API
│   ├── src/platform/  shared foundation: database, logging, health
│   └── src/modules/   People, then Maintenance, then the Tier Board
├── dev/             Local-only edge router used by docker compose
├── docs/adr/        Decision records
└── docker-compose.yml
```

The Flutter version is pinned in two places that must agree: `FLUTTER_VERSION`
in `.github/workflows/ci.yml` and the base image in `frontend/Dockerfile`. If
they drift, CI passes against a toolchain that never builds the image.
`frontend/pubspec.lock` pins what that toolchain resolves.

## Local development

```bash
docker compose up -d --build
```

Every variable has a local default, so that is the whole thing on a clean
checkout. Copy `.env.example` to `.env` to override them.

Then open <http://localhost:3002>. The edge container mirrors production
routing: `/api/*` goes to the backend, everything else to the Flutter app.

Host ports sit one above `maintenance-management`'s, which sit one above
`employee-management`'s. All three are routinely run side by side.

## Tests

The Platform has **one test seam**: HTTP against the running API, with a real
database. A test drives the app the way a client does and asserts on what a
client can observe. Reaching into a route handler or a service to check that a
function was called tests the implementation, not the behaviour — and the things
that actually break, a route that was never mounted or a pool that cannot reach
Postgres, are invisible from below HTTP.

`test/integration/schema.test.js` and `test/integration/views.test.js` are a
named exception: they assert the baseline migration directly against Postgres
rather than over HTTP, because there are no endpoints over most of that schema
yet — they arrive with the People, Maintenance and Tier Board Modules. Once a
Module owns a table, its behaviour belongs in an HTTP-level test instead.

The integration tier needs the baseline migration applied first; the API's own
health checks do not touch the schema, but these two files do.

```bash
cd backend

# Needs no database: shutdown, and the Module boundary rule.
npm test

# Needs a database with the baseline migration applied.
DATABASE_URL=postgresql://platform:localdev@127.0.0.1:5434/platform npm run migrate

# Drives the API over HTTP, and — for the schema/views exception above —
# queries Postgres directly.
DATABASE_URL=postgresql://platform:localdev@127.0.0.1:5434/platform npm run test:integration
```

Node's built-in test runner, and **no test framework**. The backend carries no
development dependencies, matching its predecessors.

## Deployment

Push to `main` and CI builds both images, publishes them to GHCR tagged with the
commit, and a self-hosted runner on the LXC deploys them. Nothing inbound is
exposed: the runner polls GitHub outbound, so there is no SSH key in this
repository and no port open on the box.

```
deploy/
├── compose.yml         the Platform: backend and frontend, from GHCR
├── caddy.compose.yml   the reverse proxy, deployed once and left alone
├── Caddyfile           one hostname, /api split from everything else
└── deploy.sh           deploys a tag, and puts the old one back if it fails
```

**A failed deploy restores the previous version automatically.** The k3s
platform got that from Helm's `--atomic`; Compose has no equivalent, so
`deploy.sh` does it by hand: it pulls before touching anything running, starts
the new tag, waits for every container to report healthy, and on failure brings
the previous tag back. The rollback passes `--pull never` — the previous images
are already on the box, and an unreachable registry is one of the things that
makes a deploy fail in the first place.

This is a replace-then-check, not a blue/green swap: the new containers take
over first, so there is a window of up to the health timeout during which the
site is down before the old version returns. Removing that window needs two
stacks and a proxy switch, which is more machinery than the plant needs today.

**Migrations run as their own step, before anything running is touched.**
After the pull (if any — see below), `deploy.sh` runs a one-off container from
the *new* backend image — `npm run migrate` against `DATABASE_URL` — before it
starts a single new container. This is what replaces the k3s platform's
pre-upgrade migration Job. A migration failure `die`s right there: no
container has been started or stopped, and whatever was serving before this
run is still serving exactly as it was.

This step runs unconditionally, on every invocation, including `--no-pull`.
That flag means "the images are already on the box", not "this is a
rollback" — a re-deploy of a tag that happens to be local already (after a
runner wipe, an air-gapped push, debugging by hand on the box) still needs its
schema current before it starts. `node-pg-migrate up` against an
already-current schema is a no-op, so running it on every invocation costs one
extra container start and nothing more.

Because migrations land before the new code does, there is a window — this
step plus however long the new containers take to report healthy — during
which the *old* version runs against the *new* schema. Every migration must
therefore be safe for the version it is replacing to run against: add a column
and start filling it in one deploy, drop what nothing reads any more only in a
later deploy once nothing depends on it. **Expand now, contract later** — this
applies to every migration written after this one, not just the baseline.

**A failed deploy rolls the image back, never the schema**
([ADR-0007](./docs/adr/0007-migrations-run-forward-only-as-a-deploy-step.md)).
There is no `node-pg-migrate down` anywhere in this script, and there is not
meant to be one: an automatic schema rollback run under deploy-failure pressure
is more dangerous than the forward state it would undo — it can drop a column
or table the previous version's own queries still reference. The
expand/contract rule above is what makes an image-only rollback *safe* rather
than reckless: because a migration is never a breaking change for the version
it replaces, the previous image can simply keep serving the migrated schema,
which is exactly what rollback asks it to do. Migrations are forward-only; the
only way back from a bad one is a further migration that fixes it forward.
Rollback itself never re-runs the migration step, because it never re-invokes
`deploy.sh` at all — it is inline code at the bottom of the same run that
restores the previous image directly and returns.

The proxy runs as its own Compose project, `platform-edge`. That is not
cosmetic: the application deploy passes `--remove-orphans`, which deletes any
container in *its* project that its compose file does not define — so a shared
project name means the first deploy removes TLS termination.

Images are tagged `sha-<commit>`, never `latest`. A floating tag would make a
rollback meaningless, because the tag it rolls back to may since have moved.

First-time setup — Supabase, DNS, Docker, certificates and the runner — is
walked through by `scripts/setup-deployment.sh`.

## Modules

A **Module** is a functional area that records real work and produces the
measurements KPIs are calculated from. Modules are code seams, not data seams
([ADR-0006](./docs/adr/0006-modules-are-code-seams-not-data-seams.md)): they
share one schema and one process, and a Module never reaches into another
Module's internals — it calls that Module's service.

`npm run lint` enforces this rather than leaving it to review. Shared code the
Modules stand on lives in `src/platform` and is not a Module; the foundation
must not depend on what is built on it.

## Known gaps

This is the walking skeleton. It proves the path from browser to database and
nothing else yet.

- **No authentication.** Sign-in through Supabase Auth lands with the People
  Module.
- **Fonts are fetched from a public CDN.** `--no-web-resources-cdn` keeps
  CanvasKit local, but Flutter still fetches Roboto from `fonts.gstatic.com`.
  On a private deployment that request can fail, and the app then renders with
  no text at all. Bundling the font belongs with the first real screens.
