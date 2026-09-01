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

The Flutter version is pinned in the base image in `frontend/Dockerfile`, and
`frontend/pubspec.lock` pins what it resolves. When CI arrives it will pin the
same Flutter version a second time, and the two must agree — if they drift, CI
passes against a toolchain that never builds the image.

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

```bash
cd backend

# Needs no database: shutdown, and the Module boundary rule.
npm test

# Needs a database. Point it at one and drive the API over HTTP.
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

**A failed deploy leaves the previous version serving.** The k3s platform got
that from Helm's `--atomic`; Compose has no equivalent, so `deploy.sh` does it
by hand: it pulls before touching anything running, starts the new tag, waits
for every container to report healthy, and on failure restores the tag it
recorded last time. A rollback never pulls — the previous images are already on
the box, and an unreachable registry is one of the things that makes a deploy
fail in the first place.

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

- **No schema.** The squashed baseline lands separately, along with the deploy
  step that runs migrations before a new version takes traffic. Until then
  `src/platform/db.js` sets no type parsers: how BIGINT and NUMERIC cross the
  wire is a decision about tables that do not exist yet.
- **No CI.** Nothing runs `npm test` or `npm run lint` automatically, so the
  Module boundary rule is enforced only by someone running it. That lands with
  the deployment pipeline.
- **No authentication.** Sign-in through Supabase Auth lands with the People
  Module.
- **Fonts are fetched from a public CDN.** `--no-web-resources-cdn` keeps
  CanvasKit local, but Flutter still fetches Roboto from `fonts.gstatic.com`.
  On a private deployment that request can fail, and the app then renders with
  no text at all. Bundling the font belongs with the first real screens.
