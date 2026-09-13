---
status: accepted
---

# Readings come from a technician; this ticket accepts manual only

Date: 2026-09-13

Issue #79, meter-driven PM schedules. `meter_readings.source` allows five
values — `manual`, `plc`, `scada`, `import`, `api` — and the ticket's own
"Not specced yet" section names the fork: a reading a person types is a small
slice, while ingesting a machine feed is a much larger one carrying the same
replay and de-duplication problems #73 faces with downtime. This ADR records
which side of that line this ticket builds.

## The decision

This ticket implements `manual` only. A technician records a reading by hand,
either standalone against an Asset's meter or while working a Work order task
that names a meter. The API accepts `source = 'manual'` and refuses any other
value with a 400 naming the source; it never relabels an incoming feed as
manual, and it never silently ignores the field.

## Why ingestion is a separate ticket

A machine feed is not "the same reading, arriving automatically." It is a
different problem with a different failure mode.

A feed re-delivers. A PLC or SCADA gateway that loses its connection and
reconnects will replay readings the Platform has already stored, and the same
timestamp may arrive twice with different values as a buffer flushes. Deciding
which of two readings for the same meter at the same moment is authoritative is
a de-duplication rule, not a transport detail. A manual reading has no such
ambiguity: a person typed it once.

A feed needs an identity. A `plc` reading has no `read_by` — there is no
Employee — so the schema has to decide what a source identifies and how one
gateway's readings are kept apart from another's, and from the same gateway
after it is replaced. The baseline `meter_readings` table carries a
`read_by BIGINT REFERENCES employees (id)` that a feed would leave null, which
is fine for a source that has no person, but the question of what does identify
the sender is not answered by any column.

A feed needs backfill and correction semantics. Historical readings arrive
after later ones, and a counter reset seen in a replay has to be reconciled
with the explicit-rollover rule ADR-0029 fixes. Doing that correctly is a body
of work on its own, and #73's downtime ingestion is the precedent for how large
it is.

None of this is a reason to never do it. It is a reason not to do it *here*,
where the goal is to make a schedule come due on accumulated use and prove the
mechanism end to end. `manual` is the smallest slice that exercises every part
of that mechanism — a meter, a reading, a cumulative check, a rollover, a
target — and it is the slice a plant with no telemetry can actually use on day
one.

## Consequences

The `source` column keeps its full enum; this ticket constrains the API, not
the schema. A later ingestion ticket adds writers for the other four values and
its own de-duplication and identity rules without a migration to the column
itself.

A reading recorded while working a Work order task carries no `source` on the
wire at all. It is a technician's own reading by construction, and the route
stamps `manual`; there is no field for a caller to set it otherwise. The
standalone reading route does accept `source`, so the refusal is explicit and
tested rather than implied.

## What this does not settle

The boundary is drawn at the API, not at the database, and that is deliberate:
the de-duplication key, the identity of a feed, and the reconciliation of a
replayed rollover are all open. A future ticket decides them together, because
deciding any one of them alone produces an ingestion path that looks complete
and corrupts accumulated use in exactly the silent way ADR-0029 exists to
prevent.
