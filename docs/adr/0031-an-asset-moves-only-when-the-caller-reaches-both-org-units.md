---
status: accepted
---

# An Asset moves only when the caller reaches both Org Units

Date: 2026-09-14

Issue #171. `assets.org_unit_id` was write-once: `POST /assets` named it, and
`PATCH /assets/:id` carried three other columns and never this one. A machine
recorded at the wrong Line, or physically moved to another one, could only be
answered by retiring the row and adding a second Asset under a second code —
which the register cannot even do with the same code, since `assets_code_unique`
is UNIQUE (code) platform-wide. One machine became two records. This ADR records
what a placement correction is allowed to be, now that it exists.

## The decision

`PATCH /assets/:id` takes `orgUnitId` as a third single-column operation,
beside `isActive` and `parentId`. A caller needs a write Grant reaching **both**
the Org Unit the Asset is leaving and the Org Unit it is going to. The move
changes that one row: it does not take the Assets nested inside it along, and it
does not touch `is_active`, `parent_id` or `asset_level`.

## Why both Org Units

Every other write on this route answers "may this caller act on this record". A
move is the first that alters two records' worlds: one Org Unit loses a machine
from its register and one gains one, and both changes are visible to people who
never touched the Asset. It is the rule this route already applies to nesting,
where attaching or detaching needs write scope on the parent losing or gaining
the Asset as well as on the Asset itself — being entitled to act on the child is
not enough to alter either parent.

The alternative — scope on the Org Unit the Asset sits at now, and nothing else
— would let a supervisor holding a Grant over Line A hand one of Line A's
machines to a line their Grants never reached: not just a write they were not
granted, but a machine appearing in a register they cannot see. Scoping on the
destination alone is worse.

The cost is accepted: a caller whose Grants cover only one of the two Org Units
cannot move a machine between them, and the refusal they see carries the same
wording every other scope refusal uses. That wording is deliberately vague about
which half refused — naming the Org Unit would tell a caller about an area they
may not be entitled to know exists.

## Why the move stops at one row

A component may already sit at an Org Unit of its own choosing. Nesting never
required a child and its parent to agree, and the baseline carries no constraint
that they do. So a machine moved without its gearbox produces no state the
register could not already hold, and cascading the move to everything nested
inside it would introduce on this route an invariant the nesting route itself
does not keep. If the register should insist that a machine and its parts agree,
that rule belongs to nesting and to the schema, in a ticket that first decides
what to do about the disagreements that already exist.

The same reasoning declines to refuse a retired destination Org Unit.
`POST /assets` already accepts any Org Unit whose id exists and which the caller
may write at, whatever its active state; refusing that placement on the move
route would make the identical state legal once and illegal later, for a reason
no ticket records. If a retired Org Unit should not receive Assets at all, that
is a rule for both doors.

## Where the past does not move

The rows that record what happened keep their own Org Unit. Work orders,
Requests and Downtime events denormalise `org_unit_id` through a trigger that
fires on INSERT or on a change to `asset_id`; a move fires neither, so a Work
order raised while the machine stood on Line A still reads as Line A's work.
Roughly: a machine that walks to another Line does not rewrite last month's
work. The integration test asserts this rather than adding code for it, and the
views that read a record's own Org Unit already take the same reading:
`v_asset_reliability` groups by the Work order's `org_unit_id`, and
`v_shift_downtime` and `v_downtime_pareto` attribute a stop by
`downtime_events.org_unit_id`.

## Where the past still moves

Two rollup views enumerate Assets by their **current** placement rather than
by the Org Unit a record carries: `v_shift_oee` and `v_downtime_mtbf_mttr` both
build their asset set from `assets.org_unit_id` (through the Org Unit
hierarchy, and filtered on `is_active`). So a move *does* restate past numbers
at the Org Unit level: after Press 1 moves from Line A to Line B, the shifts
already recorded on Line A no longer include it in Line A's OEE, and its
historical downtime now counts toward Line B's MTBF and MTTR. The rows did not
move; the attribution did.

This is recorded as a consequence rather than hidden, and it is not corrected
here. The views' question is "how do the machines standing here now perform",
and answering it any other way needs the Asset's placement *as it was* on each
production day — which nothing stores, because until this ticket the placement
could not change. Pinning that attribution is a real question with a real cost
(a placement history on the Asset, or a denormalised Org Unit on the shift-level
rows the views enumerate), and it is left open below rather than decided by
whichever view happened to be looked at first.

An Org Unit's own numbers therefore answer two different questions after a move,
and both are wanted: its **register** is the machines standing there now, and
its **work** is what was done there. A KPI has to say which of the two it means;
`v_downtime_pareto` and `v_shift_downtime` already mean the second.

## Consequences

Placement is correctable, and the correction is one operation per request: a
body naming `orgUnitId` beside `isActive` or `parentId` is refused with a 400,
because those are separate transactions and a compound request could commit one
and fail the other. The empty-body refusal now names all of the operations the
route accepts, rather than the two it used to.

No schema change was needed and no denormalised copy had to be rewritten:
everything that reads an Asset's **current** placement reads the Asset row —
the register's own read, and the two Asset-anchored rollups named above — so
those follow the move immediately, while every view that reads a record's own
Org Unit stays where the work happened. The three denormalising triggers stay
silent by construction.

## What this does not settle

Whether an Asset-anchored rollup should attribute a past period to where the
machine stands now or to where it stood then. The second reading needs placement
to become history — either a placement record on the Asset, or an Org Unit
copied onto the rows the rollups enumerate — and that is a decision for a ticket
that wants it, taken with the reporting consequences in front of it rather than
as a side effect of this one.

Whether a component should be required to sit where its parent sits, which the
schema permits today and this ADR declines to make the move route the first
place to forbid.
