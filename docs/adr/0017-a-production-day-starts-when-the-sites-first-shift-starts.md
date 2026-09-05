---
status: accepted
---

# A production day starts when the Site's first shift starts

Date: 2026-09-05

Issue #76, the tier board. Every KPI on that board is reported for a period,
and something has to decide when a day begins before any of those periods
can be drawn. Three shapes were on the table: midnight-to-midnight in the
Site's own local time; the start of the Site's own first shift; midnight UTC
everywhere, the same instant for every Site regardless of where it sits on
the map.

## The decision

The Site's shift pattern defines the day. A production day begins when the
Site's first shift begins, not at midnight. A stoppage at 05:30, at a Site
where mornings begin at 06:00, counts against the previous production day,
not the calendar date the clock on the wall would print at the moment it
happened.

This ratifies a commitment CONTEXT.md's own "Site" entry already made: Sites
"each keep its own shift pattern and its own local time, so a production day
means something different at each." This ADR does not introduce that idea;
it makes the tier board answer to it rather than deriving its own, quieter
answer to the same question.

## The schema already decided this, broadly

This is not a new mechanism invented for the tier board. The baseline
schema's `fill_shift_instance` trigger function (`backend/migrations/1756000000000_baseline.js:937`)
is the piece that actually does the work — `attach_shift_instance` (line 965)
is a helper that installs a `BEFORE INSERT` trigger calling it, one per event
table, not the trigger itself. `fill_shift_instance`'s own header comment
(lines 927-930) is the schema's clearest statement of why this exists at
all, and it already uses the term this ADR is naming:

> Attached to every event table, so a caller that supplies only a timestamp
> and an org unit still lands in the right production day. The API could do
> this itself, but the whole schema's reporting rests on the bucket being
> right, and "the one place that cannot forget" is the database.

That comment predates this ADR and predates CONTEXT.md's "Production day"
glossary entry; it is not this ADR introducing new vocabulary, it is this
ADR putting a name on a phrase the schema was already relying on unnamed.
`meter_readings` carries a second, table-specific statement of the same
principle, worth keeping because it says concretely what gets resolved:
"A reading taken at 05:55 belongs to the night shift, not to whatever the
calendar date says. The trigger resolves that from the org unit and the
timestamp, so nobody has to pick a shift from a dropdown." The same trigger
function is attached, via `attach_shift_instance`, to `production_runs`,
`production_counts`, `downtime_events`, `quality_issues`,
`safety_incidents`, `safety_observations`, `measurements`,
`maintenance_requests`, `work_orders` and `work_order_labour` — eleven
tables in total. Every Pillar the tier board reports already has its
underlying events bucketed this way before this ADR is written.

This is also the central argument for why the board itself must not
re-derive a period boundary. The schema's own comment gives the reason
directly: the whole schema's reporting rests on the bucket being right, and
the database is "the one place that cannot forget." A JavaScript
aggregation computing its own notion of "today" is a second implementation
of a decision the schema already made once, correctly, at the one place
guaranteed not to skip it — an API handler can forget, a report script can
forget, a trigger fired on every insert cannot. What is being decided here
is not whether the plant records a shift-based day — it already does,
broadly and consistently, using the phrase "production day" to describe
it — but whether the board that reports on top of those events is required
to agree with it rather than re-deriving a weaker answer for "today."

## Consequences

A period boundary is a per-Site question, and no aggregation may answer it
any other way. Computing "today," "this shift," or any period end from the
server's clock, from the viewer's own timezone, or from UTC is not a
shortcut that happens to be slightly wrong — it is answering a different
question than the one the schema already answers per row, and it will
disagree with the very tables it is supposedly summarising.

A UTC boundary is the most dangerous of the three rejected shapes precisely
because it fails quietly. It does not error, and it does not look wrong on
screen: every row gets a day, every bar on the chart gets a value, the
totals still add up. It simply misfiles work across midnight, attributing a
05:30 stoppage to the day after the shift that actually owned it, and with
several Sites in different time zones the size and direction of that error
differs per Site — one plant drifts one way, a plant eight hours away drifts
a different amount at a different local hour. A wrong number that looks
right is worse than a missing one: a missing number gets noticed and chased,
a silently wrong one gets reported up the tier board and trusted.

## What this does not settle

`fill_shift_instance` has more than one way of leaving `shift_instance_id`
null, and both open questions here are the concrete consequence of that
rather than an abstract gap. If the row itself already arrived with
`shift_instance_id` set, the function returns immediately (`IF
NEW.shift_instance_id IS NOT NULL THEN RETURN NEW; END IF;`, lines 946-948).
If the row is missing the timestamp or org unit it needs even to attempt a
lookup, it also returns immediately, before calling `shift_instance_at` at
all (`IF v_at IS NULL OR v_org IS NULL THEN RETURN NEW; END IF;`, lines
954-956) — that is a malformed row, not a Site question.

A Site with no shift pattern configured shows up differently: the row has a
perfectly good timestamp and org unit, `shift_instance_at` is called, and it
is `shift_instance_at` itself that returns null, by design — its own comment
says it "Returns NULL when nothing covers that moment (an unplanned Saturday,
say), which the caller must handle rather than guessing." `fill_shift_instance`
does not handle it; it assigns the null straight through
(`NEW.shift_instance_id := shift_instance_at(v_org, v_at);`, line 958) and the
insert proceeds. Whether that Site should instead fall back to a calendar
day, or be blocked from reporting until a shift pattern exists, is not this
ADR's call. Neither is what an aggregation should do with a row that reaches
it this way — the function's own comment already flags this as something a
caller must handle, and the caller here has not. Both are the ticket's
decision to make, not a gap this ADR is pretending not to have.
