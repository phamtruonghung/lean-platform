---
status: accepted
---

# A meter rollover is an explicit act that moves the offset

Date: 2026-09-13

Issue #79, meter-driven PM schedules. A meter is a running count per Asset —
hours run, cycles, units through the press — and a PM schedule may come due on
the accumulated use rather than on elapsed days. The schema already carries
`asset_meters.rollover_offset`, and its own baseline comment states the problem
it exists for: "A replaced hour counter restarts at zero. Without somewhere to
record the offset, the reading history goes backwards and every interval
calculation built on it silently breaks." This ADR settles how that offset is
moved and what a reading is allowed to do.

## The decision

A reading stores what is physically on the counter, and accumulated use is
`reading + rollover_offset`. Every PM due-ness calculation reads that sum,
never the raw reading.

A meter rolling over or being replaced is an **explicit act**, recorded through
its own route (`POST /api/maintenance/meters/:id/rollover`). The act takes the
accumulated use as of the last reading, adds it to `rollover_offset`, and
records the new counter's own starting value — usually zero, but a
partially-used replacement can start higher — as a reading. Accumulated use is
therefore continuous across the reset, and the next reading compares against
the new counter's epoch rather than the old one.

A reading that is lower than the previous one on a **cumulative** meter, with
no such act, is refused with the named code `METER_READING_REGRESSED`. A
counter that goes down is either a mistake or a rollover, and the Platform does
not guess which. A **gauge** meter may go either way: it measures a value, not
a total, and only a cumulative meter can drive a PM schedule.

## Why an inferred rollover was rejected

The obvious shortcut is to notice a reading lower than the last one and treat
it as a rollover automatically: add the old reading to the offset and carry on.
It was rejected because it converts a data-entry mistake into a silent
correction. A technician who types 9,140 where they meant 91,400 — or reads
the wrong display, or reads a different meter — produces exactly the same shape
of input as a genuine replacement. Inference cannot tell the two apart, and the
failure mode is the worst kind: the schedule does not error, it quietly moves
its target, and the next service either never comes due or comes due at the
wrong hour count. The whole schema's reporting rests on readings being the
truth; an act that silently rewrites the meaning of past readings breaks that
trust in a way nobody can see on screen.

Requiring the act also gives the rollover a place to say *why* it happened — a
replacement, a counter wrap, a unit change — which is exactly the note an
engineer reading the history six months later needs.

## Why the act records a reading

The rollover writes the new counter's starting value as an ordinary reading,
rather than only bumping the offset and leaving a gap. Two things fall out of
that. First, accumulated use has a value at the instant of the reset, not only
from the next reading onward, so a schedule that was already due does not
briefly read as not-due. Second, the backward check stays simple: it compares a
reading to the previous reading, and the previous reading after a rollover is
the new counter's own start, so a lower-but-legitimate reading passes while a
genuinely backwards one still fails. The row is honest about what it is — a
person typed the new counter's value, `source = 'manual'`, with a note saying
the counter was reset.

## Consequences

`v_pm_due` in the baseline compares the latest raw reading to `next_due_meter`,
which is wrong once a meter has rolled over. This ADR does not silently change
that view: the API computes due-ness on accumulated use, and a migration to
correct the view is a separate, visible change rather than a drive-by edit to a
baseline object. Until then the view and the API disagree for a rolled-over
meter, and that disagreement is recorded here rather than hidden.

The first target of a newly created meter schedule is one interval past where
the meter stands now (`accumulated use + interval_meter`), mirroring the
calendar branch's "the interval from today". A meter schedule has no lead time
in days: the plant's rate of consumption is unknown, so it comes due the moment
the accumulated use reaches its target rather than being raised early.

## What this does not settle

Whether a rollover should also be recorded as a first-class event with its own
history — who replaced the counter, on whose instruction, with what part — is
left open. `rollover_offset` is a running total, and the audit trail is not
attached to `asset_meters`; a future ticket that needs the replacement as a
record rather than as an arithmetic adjustment can add one without disturbing
the accumulated-use rule this ADR fixes.
