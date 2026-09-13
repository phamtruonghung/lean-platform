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

pgAdmin, for browsing the local Postgres directly, is at
<http://localhost:5052> — local-development-only, with the local Postgres
connection already pre-registered.

### Reviewing the app locally

`docker compose up` alone leaves the schema unmigrated, since compose has no
equivalent of the migration step `deploy/deploy.sh` runs before starting
production. `./scripts/review.sh` does the equivalent locally — build, wait for
Postgres, migrate, seed the Demo Plant, wait for the app to answer — so a
reviewer gets one command that ends at a stack that is actually usable, at
<http://localhost:3002>, rather than a backend erroring against an empty
database. `./scripts/review.sh help` lists `down`, `reset`, `logs`, `status`,
`seed` and `grant-account` alongside the default `up`.

The seed it applies is `dev/seed-demo.sql` — a versioned, idempotent demo
dataset: a Demo Plant with Org Units, Employees, Assets, a parts catalogue and
stock, meters and PM schedules, work orders and their cost, and the plant's
shifts and production. `./scripts/review.sh seed` re-applies it on demand
without rebuilding. An Account only gains a Grant after signing in, so
`./scripts/review.sh grant-account <email> <org-unit-code> [--write]` gives a
signed-in Account a Grant on a Demo Org Unit — the thing that makes the
Org-Unit-scoped behaviour visible.

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

`test:integration` runs its files with `--test-concurrency=1`: several files
share the same tables in the same real database (`app_users` for
accounts.test.js, plant.test.js and approval.test.js, for instance), and at
least one of them needs sole ownership of its table for the length of its own
run — `node --test`'s default is to run separate files in parallel, which
raced two files' own cleanup against each other before this flag was added.

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

**Nightly maintenance runs inside the database, not on the LXC.**
`sqdcp_maintenance()` — defined in the baseline, scheduled by
`migrations/1756000000001_schedule-maintenance.js` — creates the next three
months of partitions for `measurements` and `audit_log`, then refreshes
`mv_daily_oee`. `pg_cron` runs it at 03:17 UTC every day, inside the Supabase
project itself; there is no CronJob or scheduler process on the LXC, because
none of this depends on the API being up. A fixed UTC time is correct here —
neither partition creation nor rollup refresh is Site-specific, unlike shift
and production-day attribution.

If this stops running, nothing looks broken at first. Inserts keep succeeding
into a `DEFAULT` partition instead of a monthly one, and the tier board keeps
showing whatever `mv_daily_oee` last held — a wrong number, not a missing one.
The partition gap is the expensive half: once a month's rows have landed in
the default partition, that month can no longer get its own partition
(`CREATE TABLE ... PARTITION OF` refuses once matching rows already exist
elsewhere), and recovering means moving rows by hand. Check for it with:

```sql
SELECT status, return_message, start_time, end_time
  FROM cron.job_run_details
 WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'sqdcp-maintenance')
 ORDER BY start_time DESC
 LIMIT 20;
```

A run with `status <> 'succeeded'`, or no run at all for last night, means the
board is stale and partitions may be running out.

The migration that schedules this only installs `pg_cron` where
`pg_available_extensions` says it exists — Supabase Cloud has it, stock
`postgres:17-alpine` (CI, local `docker compose`) does not — and says so with
a `RAISE NOTICE` where it skips. CI cannot exercise the schedule itself for
that reason, so it calls `sqdcp_maintenance()` directly instead (see the
"Maintenance smoke test" step), which is what actually catches a
schema-qualification or partition-window regression before it reaches a
database that would have run it nightly for months before anyone noticed.

**Row Level Security is enabled on every table, with no policies, and a
dedicated read-only role reads through it.**
([ADR-0004](./docs/adr/0004-deny-all-rls-with-two-database-clients.md)). Two
clients reach this database: the API, which connects as `postgres` —
unaffected by deny-all RLS because it owns every table in this schema and
holds `rolbypassrls = true`, not because of any "service role" (Supabase's
`service_role` is `NOLOGIN`; it is a PostgREST-level JWT claim, not a
Postgres login role a `DATABASE_URL` could ever connect as) — and owns every
write; and Power BI, over `powerbi_reader`, created by
`migrations/1756000000002_deny-all-rls.js`, which can `SELECT` everywhere in
`public` and nothing more. See
[`docs/power-bi-connection.md`](./docs/power-bi-connection.md) for the
connection string, the username format, and where the password lives (not
here).

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

## Authentication

Supabase Auth is the identity provider (ADR-0002); this Platform never sees a
password. The Flutter app signs up/in against Supabase directly — password or
Google — and sends the session's JWT to the API as a bearer token on every
request. `backend/src/platform/tokens.js` verifies it against the project's
JWKS and resolves it to a Supabase subject; `backend/src/modules/people`
resolves that subject to an Account (`app_users.external_subject`), creating
one, inactive, on a subject's first sign-in. Every endpoint except an
Account's own status (`GET /api/people/me`) refuses an inactive Account with a
403 and a `status` the Flutter app can distinguish from a real failure —
`"pending_approval"` for an Account nobody has decided about yet,
`"rejected"` for one an administrator turned away, and `"deactivated"` for one
that was approved and later deactivated (`backend/src/modules/people/
middleware.js`'s `statusFor`). The very first Account created on an empty
database is the one exception: it is activated immediately, as an
administrator, granted every Site that exists at that moment. Approval itself
— an administrator admitting an Account, setting its role and granting its
Org Units, or rejecting or deactivating one — and role/Org Unit scope
enforcement on every other route are issue #8. See issues #6 and #8 and
`CONTEXT.md`'s Account/Approval entries.

Configuration — `SUPABASE_JWKS_URL`/`SUPABASE_JWT_ISSUER` for the backend,
`SUPABASE_URL`/`SUPABASE_ANON_KEY` for the frontend — lives in `.env.example`,
with no local default: verifying or issuing a real session needs a real
Supabase project. The test suite does not depend on one — see
`backend/test/helpers/jwks.js`.

## Known gaps

This is the walking skeleton, plus sign-in, plus Approval. It proves the path
from browser to database and lets a person sign up, sign in, wait for
Approval, and — once an administrator approves them — act within the Org
Units they were granted (issue #8).

- **Roboto is bundled; the engine's glyph fallback is not.**
  `frontend/assets/fonts` ships Roboto with the app, served from its own
  origin, so a private deployment with no egress still renders every string
  this interface currently shows. What remains unbundled is the Flutter
  engine's own fallback base URL, `fonts.gstatic.com`, used only for glyphs
  outside the Roboto family — it affects nothing the interface currently
  renders.
