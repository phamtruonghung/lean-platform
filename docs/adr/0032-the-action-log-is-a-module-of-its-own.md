---
status: accepted
---

# The action log is a Module of its own

Date: 2026-09-15

Issue #175, and the six tickets behind it (#176–#181). The Platform records its
work — Work orders, Requests, Downtime, the tier board's numbers — and nothing
about the management of it. `action_items` has been in the schema since the
baseline (ADR-0003) and no code has ever written or read a row of it:
`grep -rn action_items backend/src frontend/lib dev scripts` finds nothing,
while the baseline's own comment on `v_open_actions` names "the screen the
action_items table exists for". This ADR records why that screen and the log
behind it are a Module rather than a fifth Destination group's worth of Screens
inside the Module that happens to be nearby, and what the words are.

## The decision

There is a fourth Module: **Actions**, at `backend/src/modules/actions/` and
`frontend/lib/actions/`, mounted at `/api/actions`, with its own `errors.js`,
its own entry point, its own Destination group in the Shell, and the log's words
in `CONTEXT.md` (Action, Concern, Containment, Countermeasure, Action phase).

## Why not inside Maintenance

The nearest counter-precedent is a decision the other way, and it is argued
against rather than ignored. ADR-0028 kept Part and Store inside Maintenance
rather than giving inventory a Module of its own, on the grounds that parts and
stores *are the shelves a maintenance job draws from* — inventory is
maintenance's own work, done with maintenance's own tools, for maintenance's own
jobs. That reasoning does not carry to an Action, and the same ADR's shape
exposes why: it was a decision about a Module's *domain*, and an Action's domain
is the whole plant's.

Two facts in the baseline say so. `capas`' own header — since an Action and a
CAPA are the same log, one level apart — says the investigation "belongs to no
one Module and is owned by none", because which Module a problem surfaced in and
which Module does the fixing are independent of each other. And `action_items`
carries `pillar_code` referencing all five SQDCP pillars: the log is the plant's
answer to a red number under Safety, Quality, Cost, Delivery *and* People, not
maintenance's answer to a machine.

The rejected alternative was to put Actions inside Maintenance beside the tier
board, which is already there and already reads across every Pillar. That works
until a second Module wants to write the log — which is the point of it — and
then Maintenance owns a table that Quality, Safety and the tier meeting all
write through, and every one of them has to reach through Maintenance's entry
point to do it. ADR-0006's rule is that a Module is a code seam, not a data
seam, and "what does this Site owe" is a seam Maintenance does not own.

## The boundary, exactly

Actions reaches People's entry point for `authenticate`, `requireActive`,
`canAct`, `findSite`, `findOrgUnit`, `findEmployee` and the shared
`OUTSIDE_GRANTED_ORG_UNITS` wording — the same seven Maintenance uses, no new
export. It reads `org_units`, `employees` and `sqdcp_pillars` by ordinary SQL
join, which ADR-0006 explicitly allows. It writes nothing outside its own table
and the phase table #177 adds, and it exports nothing but its own router.

## What the words are, and why two of them changed

`action_items.action_type` accepted `containment`, `corrective`, `preventive`,
`improvement` and `task`. Two of the five named something `CONTEXT.md` forbids on
the row they described: `corrective` is what the CAPA entry tells a reader not to
call a CAPA ("Corrective action (that is one half of it)"), and `task` is what
the Work order entry reserves for *a step inside a work order* — while the row
this column describes is neither a CAPA nor a step of a job.

So the type list became `concern | containment | countermeasure | preventive |
improvement | routine`, in one forward-only migration that swaps the constraint
and rewrites any existing row in the same transaction. Nothing writes the table
today, so this is a constraint swap rather than a data migration; the rewrite is
what makes it safe wherever rows do exist. `concern` is added because the thing
found wrong is the log's subject and nothing named it: without it, a concern
would have to borrow `corrective` or `task` and the vocabulary would be a
comment rather than a constraint.

Mapping the two values at the edge instead — keep `corrective` in the database,
render "Countermeasure" — was rejected for the reason the two values changed at
all: the mismatch would live in prose, a query and a screen would describe the
same row with different words, and the next session would find `corrective` in
the schema and write it into a filter.

## The read is Site-wide; the writes are branch-scoped

`GET /api/actions/sites/:siteId/actions` sits behind `authenticate` and
`requireActive` and nothing else — no role check, no Grant filter, no per-row
`canAct` — which is the rule the Work order list, the Asset register and the tier
board already follow (#55, ADR-0009). The rejected alternative, filtering the
register by the caller's own Grants, would give every supervisor a different tier
meeting list; the whole point of the log is that it is the same list for
everybody in the room. `?orgUnitId=` narrows it by *area*, never by entitlement.

Writes are branch-scoped as every other write in the Platform is, with one
deliberate exception: **raising a Concern needs only a Grant somewhere in the
Site it is raised at — it does not have to reach the Org Unit named**, because a
concern is a report rather than a decision and the floor is where concerns are
found: the operator granted on Line 2 who finds a defect that came from Line 1
raises it at Line 1 (issue #198, CONTEXT.md's Concern entry, which is the rule
this ADR now records rather than the weaker one it first did). The test is the
one GET /sites already filters by — any Grant, read or write, on any Org Unit
within the Site — so an Account holding no Grant anywhere in the Site is still
refused, and only the Concern kind is opened up: raising a Containment,
Countermeasure, Preventive, Improvement or Routine action still needs a Grant
reaching the Org Unit it is raised at, as every other write does. Requests work
the same way they always did ("raising needs only a read Grant reaching the
Asset's Org Unit"). Everything that changes an Action afterwards — completing a
phase, adding a measure, escalating, cancelling — needs a write Grant reaching
it.

## The group in the sidebar

The Shell gains a group: **Actions**, ordered between Maintenance and Insights,
so the sidebar reads Home, People, Maintenance, Actions, Insights,
Administration — the groups where a person does the work, then the groups where
the plant is read about. Its Destinations are offered to every admitted Account,
which is the same shape Home, the Directory and My requests already use, because
anyone on the floor may raise a Concern.

## Consequences

A second Module means a second `errors.js`, byte-similar to the other two on
purpose (ADR-0006's "domain, not utility"), and a boundary the lint checks for
free: nothing in `modules/actions` may reach past `modules/people`'s entry point,
and nothing in `platform/` may reach into it at all.

The word *task* is now spent twice over as an avoided term: it names a step
inside a Work order, and it is not the Action type either.

## What this does not settle

Whether an Action should be raisable from a red KPI on the tier board. The
column exists (`action_items.kpi_actual_id`) and nothing can fill it, because
`board.js` computes every number on read and writes no `kpi_actuals` rows — so
there is nothing for the Action to point at. Either the board materialises on a
schedule or the Action carries the KPI definition instead, and both are a
decision with reporting consequences in front of it rather than a side effect of
this one.

Whether a Maintenance Work order can be raised from a Concern. The column exists
(`action_items.work_order_id`) and stays unwritten: ADR-0006 lets a Module's
entry point expose questions and never commands, so Maintenance cannot export
"raise a work order" for Actions to call, and the flow needs either two client
calls with a link back or a new seam.
