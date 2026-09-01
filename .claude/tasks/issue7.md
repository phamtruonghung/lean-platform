# Task: Issue #7 — Sites and the Org Unit tree

Repo: /root/lean-platform (branch feat/sites-org-tree). You ARE the
implementer — work directly and autonomously, do NOT spawn subagents and do NOT
background any task. Reason carefully and follow the repo's existing
conventions. If you get stuck on the same error for two attempts, step back,
re-read the relevant schema/tests, and change approach rather than thrashing.

## Context you MUST read first
- `CONTEXT.md` at repo root — vocab is binding (Site, Org Unit definitions).
- `CLAUDE.md`, `docs/agents/issue-tracker.md`, `docs/agents/implementation-agents.md`.
- `backend/src/index.js`, `backend/src/platform/*`, `backend/src/modules/people/*`
  for the existing module layout, the authenticate/requireActive middleware (from
  #6, already merged to main), the module-boundary convention (`npm run lint`), and
  how the People module is mounted under `/api/people`.
- `backend/migrations/1756000000000_baseline.js` — the `sites` and `org_units`
  tables already exist (sites: id/code/name/timezone/country_code/is_active +
  timezone validation trigger; org_units: id/site_id/parent_id/code/name/
  unit_type CHECK in area/department/line/cell/work_center/path LTREE/sort_order/
  is_active + path compute/move subtree triggers). `app_user_org_units` grants a
  user an org_unit. Read these definitions carefully — most of the data model
  is already there; you build the HTTP surface over it, in `backend/src/modules`.
  Per CONTEXT, a grant on a Site's root covers everything beneath it (LTREE path).

## Where it goes
Issue #6 created `backend/src/modules/people/` (service.js, routes.js,
middleware.js, index.js) mounted at `/api/people`. This issue's surface —
Sites and the Org Unit tree — is People-domain, so it belongs in that same
module: add the routes to the existing People router (or a second router
imported by people/index.js), and the Sites/Org Unit service logic in that
module. Follow the existing file style closely (header comment explaining the
design, camelCase JSON, `toX` row mappers, `withActor(accountId, fn)` for
writes).

## The seam, and how to verify
One test seam: HTTP against the running API with a real PostgreSQL (see
backend/test/integration/accounts.test.js + test/helpers/jwks.js for the exact
pattern: start a test JWKS, set SUPABASE_JWKS_URL/ISSUER, require src/index,
boot on port 0, real fetch). You must add integration tests to
backend/test/integration/ following that file's structure, including logging in
as the bootstrap admin (use the jwks helper to sign an admin token — remember
the FIRST account on an empty DB becomes admin, so truncate app_users/clean up
like accounts.test.js does, or reuse its approach).

A local Postgres is at postgresql://platform:localdev@127.0.0.1:5434/platform
(all migrations already applied — re-run `npm run migrate` if you add one).
Set DATABASE_URL before tests. If you add a new migration, follow the exact
conventions of the existing ones (design-explaining header, pgm.sql blocks).

Note: the time-zone criterion ("anything resolving a shift or a production day
uses the Site's time zone, never the server clock") — the schema stores a TZ
per Site and shifts/production days are NOT built yet (they are other modules).
Deliver the Sites endpoints that carry the timezone through the API and a test
proving a Site round-trips its timezone, and document in the code/README what
future time-attribution must read (the Site's timezone, not the server clock).
Do not invent shift/production-day endpoints that aren't in this issue's scope.

## Acceptance criteria (from the issue)
- An administrator creates a Site with a code, a name and a time zone
- An administrator builds a Site's Org Unit tree across every unit type:
  area, department, line, cell and work centre
- The tree can be browsed from a Site down to a work centre
- Everything beneath a given Org Unit is retrievable in a single request
- An Org Unit can be deactivated without being deleted, and records referencing
  it stay readable
- Anything resolving a shift or a production day uses the Site's time zone,
  never the server clock

Role/scope enforcement (only admin creates Sites/Org Units) is issue #8's —
but you SHOULD already gate writes behind `authenticate` + `requireActive` since
those exist and a non-admin creating Sites would be scope creep you can control
with the existing middleware. Reads (browsing the tree) are open to any active
Account. State the assumption if you choose otherwise.

## Deliverables
Real code + real passing integration tests (verifiable on this machine) +
`.env.example`/README updates if configuration changes. When done, report:
files changed, exact verification commands you ran and their real output, what
remains, and any assumptions you made. Do NOT commit — leave the working tree
dirty for review.