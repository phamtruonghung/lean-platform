---
status: accepted
---

# The MTU KPI catalogue stays in its own database, and the Platform reaches it through a second pool

Date: 2026-10-30

The MTU line is reviewed every day against a list of KPIs — scrap ratio,
availability, MTTR, output per day and others — each with a Target per grain
(Daily, Weekly, Monthly). That list, its Targets and the daily Review of it live
in schema `kpi` of a second PostgreSQL database, `mtu`, on another host on the
plant LAN, put there by the data-analysis repository's own scripts
(`relats/kpi/sql/0001_kpi_schema.sql`, `0002_kpi_review.sql`, deployed to CT100
by `setup_kpi_ct100.sh`). Power BI reads the same tables: one list of KPIs and
one Target history for both tools. The Platform needs to show that list, let the
right people add a KPI or change a Target, and record the day's Review.

## The decision

**The Platform connects to db `mtu` as the role `lean_app`, through a second
connection pool, and keeps no copy.** `platform/mtu-db.js` is that pool, modelled
on `platform/db.js`: created lazily, with its own error listener, and with a
`statement_timeout` because the host is a second machine on the LAN. A new Module,
`kpi`, owns everything that touches it, mounted at `/api/kpi`.

**`lean_app` can read the schema and append to it, and nothing else.** SELECT on
the tables and views, and three column-level INSERTs: a KPI
(`kpi, title, unit, direction, decimals, value_measure`), a Target
(`kpi_id, grain, valid_from, target, note, app_user`) and a Review
(`kpi_id, review_date, status, observed, note, app_user`). It holds no UPDATE or
DELETE, and the tables refuse them for every role anyway. So every write in the
Module is a plain INSERT, never an upsert; a correction is another row for the
same KPI, grain and date, and the database's own views pick the newest. The
Module follows that grain rather than fighting it: saving the same day's Review
twice is a 201, while a repeated KPI name and a Target repeated with the same KPI,
grain, date and value are each a 409.

**The catalogue is optional.** With `MTU_DATABASE_URL` unset, every `/api/kpi/*`
route answers `503 { "error": "kpi_catalogue_unavailable" }` — after
authentication, so an unauthenticated caller still gets its 401 — and the API
boots and serves everything else. `GET /api/health` reports
`kpi_catalogue: 'configured' | 'unconfigured'`; `/healthz` and `/readyz` do not,
because readiness is about the Platform's own database, and a missing catalogue
must not take an instance out of rotation.

**Authority is the Site's root Org Unit.** The catalogue is shared by every Site
and belongs to no Org Unit, so the routes ask `people.canAct` about the root Org
Unit of the Site named in the request: a Grant of either level to read, an edit
Grant (or an administrator) to write.

## Why not the obvious alternative

The least change would have been a catalogue inside the Platform's own database:
the `kpi_definitions` and `kpi_targets` tables are right there, the pool is
already open, and no second set of credentials is needed. Rejected, because it
makes the second list the whole problem. Power BI would never see a Target
entered in the Platform, and a Target entered in the data-analysis tooling would
never reach the Platform; within a month the two disagree and nobody can say
which is right. The data already has one home, shared with the tool that draws
the charts, and the Platform's job is to be a front door to it.

The other cheap route, a view or foreign table in the Platform's database
pointing at `mtu`, was not taken either: it moves the failure to the wrong place
(a slow or absent remote table would stall queries in the Platform's own
database) and ADR-0007's migrations would then own an object whose other half they
cannot see.

## What goes wrong, and what happens

- **`MTU_DATABASE_URL` unset:** 503 on `/api/kpi/*`, as above. Nothing else is
  affected.
- **The second host is down or unreachable:** the pool's five-second connection
  timeout fails the request with a 500 from the Module's routes (the terminal
  handler logs the cause and never echoes it). People, Maintenance and the rest
  are untouched, because they use the other pool.
- **A query runs too long on the second host:** the ten-second
  `statement_timeout` ends it, so a request is not held open behind a slow
  query. The server enforces it, so it does not cover the host or the network
  dying mid-query (a switch port flapping, the machine losing power): nobody is
  left to enforce it, and the client waits on the TCP connection until the
  operating system gives up. That is a known limit of this decision.

## Modules are code seams, not data seams

ADR-0006 says the Platform's Modules share one schema and one connection pool.
This is the one place that is no longer true, and it is deliberate: the data seam
is drawn in `platform/mtu-db.js`, in the foundation, and nowhere else. The `kpi`
Module still follows the code seam — it requires People's entry point and no
other Module, and nothing under `platform/` requires it.

## What it does not touch

The Platform has its **own** `kpi_definitions`, `kpi_targets` and `kpi_actuals`:
the tier board's numbers, Pillar-based, derived from records People,
Maintenance, Quality, Safety and Production write in the Platform's own
database. They are a **different** set of numbers from the MTU catalogue, with
different meanings and a different owner, and this Module does not read, write
or reconcile them. That is also why the Module exports no `kpiRegistry`: the
board's registry holds the Platform's numbers, and the MTU catalogue has no
Platform records behind it. A later reader tempted to merge the two lists into
one should start by reading this paragraph.

## Consequences

- A new backend Module `src/modules/kpi/` and `platform/mtu-db.js`, one new
  environment variable (`MTU_DATABASE_URL`, documented in `.env.example`; on
  VIProd it is written to `/root/.mtu-kpi/lean_app.env` on CT100), and one new
  field on `GET /api/health`. No migration: the schema is deployed from the
  data-analysis repository, not from `migrations/`.
- The integration test stands the schema up from `test/fixtures/kpi-schema.sql`,
  a verbatim mirror of the two source files. The two must be changed together.
- A Flutter card follows, written against the snake_case API this Module
  exposes.
