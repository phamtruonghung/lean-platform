# AGENTS.md

Conventions for any agent working in this repository, regardless of which
harness is driving it. This file does not assume you have read anything else
in this repo. If you are a Claude Code agent, also read `CLAUDE.md` at the
repo root for a short addendum.

## 1. What this is

The Platform is one application, one database, for running a manufacturing
plant: it records the work that happens on the floor and reports the numbers
that work produces. The vocabulary — Site, Org Unit, Employee, Account,
Grant, Asset, Work order, Module, Pillar, KPI, Screen, Destination, Shell, and
more — is defined in `CONTEXT.md` at the repo root. Use those words verbatim
in code, tests, commit messages, issue text and UI copy. Every glossary entry
also lists words to `_Avoid_`; do not use those as synonyms even when they
read naturally — a "ticket" is never called that here, it is a Work order or
a CAPA depending on which one it is, and CONTEXT.md's own entry says which.
Decisions behind the shape of the domain and the codebase live in
`docs/adr/`, numbered `0001`–`0013` at the time of writing; read the ones
that touch the area you are about to change.

## 2. Layout

```
lean-platform/
├── CONTEXT.md              the glossary — read before naming anything
├── docs/adr/                numbered decision records, 0001 upward
├── backend/                 Express API
│   ├── src/platform/        shared foundation: db, tokens, logging, health — owns no domain, depends on no Module
│   ├── src/modules/people/  Accounts, Approval, Sites, Org Units, the Employee directory, job roles, skills
│   ├── src/modules/maintenance/  Assets and Work orders
│   ├── migrations/          node-pg-migrate, forward-only (see section 4)
│   ├── scripts/             check-module-boundaries.js, check-syntax.js, lib/
│   └── test/                unit tests (test/*.test.js) and test/integration/
├── frontend/                 Flutter web app
│   └── lib/
│       ├── platform/         Shell, router, theme, DI — the client's own foundation layer
│       ├── people/            People Module's Screens, Blocs, entry point
│       ├── maintenance/       Maintenance Module's Screens, Blocs, entry point
│       └── auth/              sign-in, awaiting-Approval
├── dev/                      local-only edge router config used by docker compose
├── scripts/                   review.sh, setup-deployment.sh (repo root, distinct from backend/scripts)
├── deploy/                    production compose files and deploy.sh
└── docker-compose.yml         local development stack
```

A backend Module is a folder under `src/modules/`; a frontend Module is a
folder under `frontend/lib/`. The two are named to match — `maintenance` and
`maintenance`, `people` and `people` — so a change that touches one side of a
feature has an obvious place to look for the other.

## 3. How to run the checks

All backend commands run from `backend/`. There is no test framework — Node's
built-in `node --test` — and no ESLint; the backend carries no development
dependencies at all, matching the two predecessor apps it replaces.

```bash
cd backend
npm ci

# Lint: the Module-boundary rule (ADR-0006) plus a syntax check.
npm run lint

# Unit tests. No database needed — these cover process shutdown, the two
# Module entry-point export sets, JWT verification against a local JWKS,
# and the Module-boundary rule's own script logic.
npm test
```

Integration tests drive the API over real HTTP against a real Postgres —
this is deliberately the Platform's one test seam (see section 5). Start a
disposable local Postgres and apply the baseline migration before running
them:

```bash
# From the repo root, brings up local Postgres (and the rest of the dev
# stack) on port 5434, matching docker-compose.yml's own default:
docker compose up -d --build

cd backend
DATABASE_URL=postgresql://platform:localdev@127.0.0.1:5434/platform npm run migrate
DATABASE_URL=postgresql://platform:localdev@127.0.0.1:5434/platform npm run test:integration
```

`test:integration` runs with `--test-concurrency=1` on purpose: several
integration files share tables in the same real database (`app_users`, for
instance, is written by `accounts.test.js`, `plant.test.js` and
`approval.test.js`), and running files in parallel — `node --test`'s default
— has raced two files' own cleanup against each other before.

Two integration files, `test/integration/schema.test.js` and
`test/integration/views.test.js`, assert against Postgres directly rather
than over HTTP. This is a named exception, not a precedent to copy: they
exist because there are no endpoints yet over most of the baseline schema.
Once a Module owns a table, its behaviour belongs in an HTTP-level test
instead.

**Expected skips on a stock Postgres.** `test/integration/rls.test.js`
checks that the Supabase-provisioned roles `anon` and `authenticated` hold no
privileges. The role-existence half of that check always runs and always
passes (there is nothing to hold a grant, so the count is trivially zero on
any Postgres); the half that actually attempts a `SELECT` under `SET ROLE
anon` / `SET ROLE authenticated` calls `t.skip(...)` with an explicit reason
when the role does not exist, because `SET ROLE` to a role that is not there
is an error, not something the test can meaningfully assert on. Both
CI (`postgres:17-alpine`) and local `docker compose` (`postgres:16-alpine`)
lack these roles, so you will see these two skips reported, by name, on every
local and CI run — that is expected, not a broken test. This is the only
skip pattern found in the integration suite; do not assume other tests skip
without checking their own `t.skip` calls.

Frontend commands need Flutter. **There is no Flutter binary on this host.**
CI and `frontend/Dockerfile` both pin `3.44.0` (`ghcr.io/cirruslabs/flutter`
is the image `frontend/Dockerfile`'s build stage uses; CI's `flutter-action`
pins the same version number). Run Flutter commands through that image:

```bash
# From the repo root. Work against a COPY, never the real frontend/ — see below.
rm -rf /tmp/frontend-check && cp -r frontend /tmp/frontend-check
docker run --rm -v /tmp/frontend-check:/app -w /app \
  ghcr.io/cirruslabs/flutter:3.44.0 \
  bash -c "flutter pub get && flutter analyze && flutter test"
rm -rf /tmp/frontend-check
```

**Do this against a COPY of `frontend/`, never a bind-mount of the real
directory.** Running `flutter pub get` against a live bind-mount of
`frontend/` rewrites `pubspec.lock` to match whatever the container's SDK
resolves, and that rewrite can silently break the SDK's own compile the next
time a real build runs against the committed lockfile. Copy the directory
first (`cp -r frontend frontend-copy`), run the container against the copy,
and discard the copy afterward. If `pubspec.lock` in the real `frontend/`
ever changes as a side effect anyway, restore it with `git checkout --
frontend/pubspec.lock` before doing anything else.

## 4. Hard rules

These get work rejected. Each is a decision recorded in an ADR, not a matter
of house style.

- **A Module never reaches past another Module's entry point.** Enforced by
  `backend/scripts/check-module-boundaries.js`, run as part of `npm run
  lint`. Precisely, on every relative `require`/`import` inside
  `src/modules/<name>/`: reaching into `src/modules/<other>/` is only allowed
  if the resolved target is `src/modules/<other>` itself or
  `src/modules/<other>/index.js` — anything deeper is a violation. Separately,
  no file under `src/platform/` may resolve into `src/modules/` at all, in
  either direction: the foundation must not depend on what is built on it.
  (ADR-0006.) A Module's entry point itself may only expose read-only
  lookups that return a value (never throw an HTTP-carrying `Error`) about a
  record that Module owns — not generic utility code, and never a write.
- **Migrations are forward-only, and are a deploy step, not something an
  application boots into.** `deploy.sh` runs the new image's migrations
  before anything running is touched, and a failed deploy rolls the image
  back — never the schema. There is no automatic `down` anywhere. Every
  migration must be safe for the version it replaces to keep running against
  it (expand now, contract later). (ADR-0007.)
- **Do not change the schema unless the ticket says to.** A migration is a
  one-way door in production; adding one outside the ticket's scope is not a
  drive-by improvement here.
- **Org Unit scope decides where an Account may act, not who it may know
  about.** The Employee directory and the Asset register are both readable
  platform-wide by any approved Account, with no Grant filtering — only a
  write needs a Grant reaching the relevant Org Unit. Do not add a scope
  filter to a read surface just because a write nearby has one; that is a
  deliberate asymmetry, not an inconsistency to "fix". (ADR-0009.)
- **Modules are code seams, not data seams.** People, Maintenance and
  whatever follows share one schema and one Postgres connection pool.
  Cross-Module reads are ordinary SQL joins (Maintenance's `assets.js` joins
  `org_units` directly); a cross-Module write or lookup that needs another
  Module's judgment goes through that Module's entry point instead.
  (ADR-0006.)

## 5. The two test seams, and only two

The Platform has exactly two test seams. Do not invent a third — reaching
into a service function or a Bloc to check its return value or its internal
state tests the implementation, not the behaviour a caller can see.

**Backend: HTTP against a real API, with a real database.** A test starts
the app (`require('../../src/index')`), issues real HTTP requests against
its listening socket, and asserts on the HTTP response — status code and
body — exactly as a real client would. Where a request needs a real-looking
Supabase JWT, `backend/test/helpers/jwks.js` stands up a genuine local
`node:http` server serving a genuine JWKS document for a locally generated
RSA key pair, and signs tokens with the private half — `src/platform/tokens.js`
has no test-only code path, so this exercises its actual signature
verification and HTTP fetch, not a stub of it. The prior art to copy is
`backend/test/integration/plant.test.js`: it points `SUPABASE_JWKS_URL` at
the local JWKS server in `test.before()`, inserts its own `app_users` rows
directly (rather than truncating a table other files share), and cleans up
everything it inserted in `test.after()`. A new integration test file should
follow that same shape rather than reinventing account setup.

**Frontend: a widget test with the network faked at the wire.** A test pumps
`PlatformApp` with a fake `http.Client` and a fake `AuthGateway`, drives the
UI through `WidgetTester` — tapping, scrolling, filling fields — and asserts
on what renders: text, widget presence, a `Key`. It never inspects a Bloc's
state object directly. The prior art is `frontend/test/harness.dart` (the
shared `FakeWire`, which answers scripted JSON for every route the app calls
and records every request so a test can assert what was — and was not —
sent, plus `FakeAuthGateway` and the `pumpApp`/`tapIn` helpers) together with
`frontend/test/approval_queue_test.dart`, which shows the pattern in use: pump
the app to an address, act on it, assert on rendered text and on `FakeWire`'s
recorded requests.

The standard behind both seams is the same: **a test asserts what a caller
observes through the same door a real client uses** — an HTTP response for
the backend, rendered widget/UI state for the frontend — never a service
function's return value directly, and never a Bloc's internal state.

## 6. Backend module shape

Within `src/modules/<name>/`, a Module that owns HTTP routes splits its
domain logic from its routing in a fixed pattern — see `assets.js` /
`asset-routes.js` and `work-orders.js` / `work-order-routes.js` in
`maintenance/` for the shape to copy:

- **`<domain>.js`** (e.g. `assets.js`) owns SQL, row-shape mapping, and
  domain validation of a record's own fields (a required string, an
  enum membership, a numeric range). It never requires another Module and
  is unaware of who is calling — it accepts ids it is handed and assumes the
  caller already checked what needed checking. Domain errors it raises are
  plain `Error`s carrying `.status`, built with this Module's own
  `httpError`/`notFound` from its own `errors.js`.
- **`<domain>-routes.js`** (e.g. `asset-routes.js`) owns the Express router
  for that domain: request-shape validation (which fields were sent, whether
  two mutually exclusive fields were sent together), calling into
  `modules/people`'s entry point for cross-Module questions (`findSite`,
  `findOrgUnit`, `canAct`), and mapping a thrown error to an HTTP response
  via `handleError(error, res, next)`.
- **`errors.js`** is duplicated per Module on purpose, not shared —
  ADR-0006's "domain, not utility" clause keeps `httpError`/`notFound`/
  `parseId`/`handleError` out of any cross-Module entry point. Byte-similar
  files in two Modules are the seam working as intended, not duplication to
  clean up.
- **Error mapping**: a service function throws `httpError(status, message)`
  or `notFound('Thing')`; a route's `catch` block calls
  `handleError(error, res, next)`, which responds with `error.status` if the
  error carries one and otherwise forwards to Express's own error handler.
  Postgres constraint violations (`error.code`, e.g. `'23505'` unique,
  `'23514'` check, `'23503'` foreign key) are mapped to a clean 4xx inside
  the service file (`mapAssetWriteError`, `mapWorkOrderWriteError`) before
  they ever reach a route — a raw database error message is never echoed to
  a caller, since it names tables and columns.
- **Org Unit scope check ordering**: a write route resolves *existence*
  first — the named Org Unit or Asset must be found, or the response is a
  404 — and only then asks `people.canAct({ account, orgUnitId, write: true
  })` for *scope*, returning 403 with `people.OUTSIDE_GRANTED_ORG_UNITS` if
  it is refused. This order is deliberate, not incidental: `canAct` returns
  `true` for role `admin` before it even checks whether the Org Unit id is
  null, so checking scope before existence would turn an administrator's
  typo into a raw 500 rather than a clean 404. Follow this order — existence,
  then scope — for every new write route. `write: true` must always be
  passed explicitly to `canAct`; it defaults to `false`, so a caller that
  drops it silently authorises the write for a read-only Grant with no error
  anywhere to notice.

## 7. Frontend shape

- **State management is `bloc`, not `Cubit`.** Every Screen-driving state
  machine gets an explicit event type and state type dispatched through a
  `Bloc`. This is deliberate ceremony, accepted so that a small Screen's
  state machine and a complex one's read the same way. (ADR-0012.)
- **`go_router`, so every Screen has an address.** Screens are reached by
  route, and the sign-in / awaiting-Approval / signed-in-and-active branching
  is expressed once as a router-level `redirect`, not per-Screen widget-tree
  logic. (ADR-0012.)
- **Feature-first directories mirror the backend's Module seam.**
  `frontend/lib/platform/` is the client's own foundation layer (Shell,
  theme, routing, the HTTP client wiring in `platform_app.dart`/`main.dart`)
  that every Module sits beneath — the same role `src/platform/` plays on the
  backend. `frontend/lib/people/` and `frontend/lib/maintenance/` are Modules,
  each owning its own Blocs, Screens and — where a second Module needs
  something the first owns — its own entry point (`lib/people/people.dart`,
  the client equivalent of `modules/people/index.js`, `export`s only what
  Maintenance actually consumes, e.g. `OrgUnitPickerBloc`). (ADR-0012,
  ADR-0006.)
- **Shell / Destination / Screen**, per CONTEXT.md's own entries: a *Screen*
  is a full destination with its own address that a person can bookmark or
  link to (sign-in, the Directory, the Approval queue) — a dialog or a panel
  inside one is not a Screen. A *Destination* is an entry in the Shell's
  sidebar, naming what a person does there rather than the Module behind it
  — every Destination is a Screen, but sign-in and awaiting-Approval are
  Screens reached without ever being offered as Destinations. The *Shell* is
  the persistent chrome (sidebar, brand header, account footer) that stays
  put while Screens change beneath it.
- **A value with a known set is chosen, never typed.** A field backed by a
  Postgres `DATE` renders a date picker and its text field is read-only;
  optional ones carry an explicit clear affordance, because blank has
  meaning. A timezone is chosen from the list the database validates against,
  never typed. A search box suggests records as the user types and reports
  the pick to its caller. When the list behind such a control cannot be
  fetched, it shows `FailureState` and blocks submission rather than falling
  back to free text. The shared widgets are
  `frontend/lib/widgets/app_date_field.dart` and `app_search_field.dart`;
  build on them rather than hand-rolling another `TextField`. (ADR-0023.)

- **Public static `Key` accessors for testing.** A widget that a test needs
  to find or act on exposes a `static ValueKey<String>` method or field
  rather than a test constructing an ad hoc `Key` inline — see
  `AssetsScreen.rowKey(id)`, `.retireKey(id)`, `.nestKey(id)` and
  `ApprovalQueueScreen.rejectKey(id)`, `.admitKey(id)` in
  `frontend/lib/maintenance/assets_screen.dart` and
  `frontend/lib/people/approval_queue_screen.dart`. Follow this pattern for
  any new interactive row or button a test will need to target.

## 8. Workflow

**Branch naming**, taken from actual branches in this repo:
`<type>/<kebab-case-description>`, where `<type>` is one of `feat`, `fix`,
`chore`, `docs`, or (rarely) `revert` — e.g. `feat/raise-a-work-order`,
`fix/prevent-admin-self-lockout`, `chore/shared-test-harness`,
`docs/maintenance-vocabulary`. The description names the change, not the
issue number.

**Commit messages** follow Conventional-Commits-style types
(`feat:`/`fix:`/`chore:`/`docs:`) with a lowercase, sentence-style summary,
then a body of full paragraphs explaining what changed and why — not a
bullet changelog — then a trailing `Closes #N` line. A real example from this
repo's history:

```
feat: raise a work order, and see the list

The first real work the Platform records. A supervisor raises a job against
an Asset with a summary, a kind of work and a priority, and reads the open
work across the whole Site.
[...]
Closes #57
```

**Claim an issue before starting work**: `gh issue edit <number>
--add-assignee @me`. `docs/agents/issue-tracker.md` documents this exact
command under its Wayfinding operations section ("Claim: `gh issue edit <n>
--add-assignee @me`, the session's first write") — treat it as the first
write of any ticket you pick up, not only when running the wayfinder
workflow it was written for.

## 9. Definition of done

- `cd backend && npm run lint` passes.
- `cd backend && npm test` passes (unit tests, no database).
- `cd backend && npm run test:integration` passes against a migrated local
  Postgres (the two `rls.test.js` role skips noted in section 3 are expected,
  not a failure).
- `flutter analyze` and `flutter test`, run via the pinned
  `ghcr.io/cirruslabs/flutter:3.44.0` image against a **copy** of `frontend/`,
  both pass.
- Every acceptance criterion in the ticket is covered by a test you can point
  to by name — not merely "the feature works when I tried it".
- No schema migration was added unless the ticket explicitly calls for one.
- New code, tests, commits and any UI copy use `CONTEXT.md`'s glossary terms,
  not a word listed under that term's `_Avoid_`.
- The branch is pushed and a pull request is open against `main`.
