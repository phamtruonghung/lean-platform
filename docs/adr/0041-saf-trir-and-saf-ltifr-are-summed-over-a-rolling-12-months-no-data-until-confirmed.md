---
status: accepted
---

# `SAF_TRIR` and `SAF_LTIFR` are summed over a rolling 12 months, `no_data` until the window is confirmed

Date: 2026-09-22

ADR-0040 records where the hours behind these two rates come from. This ADR
records decisions 7–9 of #247: how the rate itself is combined, why its
window is a rolling 12 months rather than the board period, and what makes it
`no_data`. `safety/kpi-registry.js`'s own header already explains why the
board carries no `SAF_TRIR` or `SAF_LTIFR` entry today — both are rates per
worked hour, and `v_safety_rates`' own `hours` CTE has no rows to select,
since nothing writes `attendance_records` yet — and names this decision as
what unblocks them: "Exposure hours are #233." The baseline's own comment on
`v_safety_rates` gives the two conventions this ADR does not reopen: TRIR is
per 200,000 hours (100 full-time equivalents for a year, the OSHA
convention), LTIFR is per 1,000,000 hours (the ILO convention), and both are
carried because which one a plant reports depends on where it is.

## The decision

**Sum the incidents, sum the hours, divide once.** Over the window and the
whole Org Unit subtree, recordable incidents (for `SAF_TRIR`) or lost-time
incidents (for `SAF_LTIFR`) are added up, worked hours are added up, and the
rate is the one division of the two totals — `200000 × Σincidents / Σhours`
for `SAF_TRIR`, `1000000 × Σincidents / Σhours` for `SAF_LTIFR`. A rate is
never averaged — not across the days inside the window, and not across the
Org Units inside the subtree. `v_safety_rates`' own per-production-day `trir`
and `ltifr` columns divide once *per day*, which is the right shape for that
view's own grain but the wrong one to average across a year: averaging 365
daily ratios weights a zero-incident, zero-hours Sunday the same as a
30-person weekday, and answers a different, wrong question from "how many
recordables per 200,000 hours worked here this year."

**The window is a rolling 12 months ending at the board period's end, not
the board period itself.** Every other number on the tier board is filed
against the period it is read for — a shift, a day, a week. `SAF_TRIR` and
`SAF_LTIFR` are the one exception, computed over the 12 months ending at
that period's own end, because the board period is too small a sample for
either rate to mean anything: one incident on a 30-person line in a single
week produces a TRIR in the hundreds, a number nobody would act on and
everybody would argue about instead. `SAF_INCIDENTS` already answers "what
happened this period" as a plain count (its own header, `safety/kpi-
registry.js`); these two rates answer a slower-moving question, over a
window wide enough for the answer to be worth reading.

**The window cannot start before the Org Unit's first confirmed shift, and
an unconfirmed shift inside it makes the rate `no_data`.** The rolling
12 months starts no earlier than the first shift instance at the Org Unit
with a confirmed `attendance_sheets` row, so a Site does not read `no_data`
for a full year after it goes live just because the calendar window reaches
back before attendance was ever recorded there. Within the window, once it
has a start, any past shift instance that still has no confirmed sheet makes
the rate `no_data` for that read, with the reason given — naming the
unconfirmed shift rather than a bare "no data". Leaving that shift's hours
and any incident against it out of the sums would not be silence; it would
be a wrong number reported as a right one, either inflating the rate by
undercounting its denominator or, worse, dropping an injury that happened on
an unconfirmed shift out of the numerator entirely.

## Why not average the rates

Rejected, and rejected specifically over summing the two totals first: an
average of per-day or per-Org-Unit rates treats every period counted as
equally weighted regardless of how many hours or incidents it actually
carried, which is exactly backwards for a rate whose entire point is to be
weighted by exposure. A quiet Org Unit with a handful of hours and a busy
one with thousands would count for the same one vote each in an average,
while summing first counts every hour and every incident once, at its own
weight, the way OSHA's and the ILO's own formulas are defined to.

## Why not drop unconfirmed shifts from the window

Rejected: dropping is not neutral, and it fails in the direction that
matters most. Dropping an unconfirmed shift's hours from the denominator
while any incident recorded against it still counts in the numerator would
inflate the rate; dropping the shift entirely, incident included, would
silently erase an injury from the plant's own record of what happened to
it. Reporting `no_data` instead says plainly that the number is not yet
answerable, which is the honest state — a rate computed by quietly leaving
out the parts that are inconvenient is worse than no rate at all, the same
reasoning `safety/kpi-registry.js`'s own header already gives for refusing
to invent a number on a missing denominator.

## Why not a `no_data` rule with no start date

Rejected: without the first-confirmed-shift floor, the rolling window would
reach back 12 months from the day this ships, land on a stretch of history
nobody was recording attendance for, find every shift in it unconfirmed by
definition, and report `no_data` for a full year at every Site that adopts
this — including one whose supervisors confirm every sheet from day one.
That punishes exactly the plants doing it right, and it gives no one a
reason to believe the rate will ever turn into a number rather than a
permanent placeholder. Anchoring the window's earliest possible start to the
Org Unit's own first confirmed shift is what lets a newly onboarded Site
watch the rate become real within days of adoption, on the strength of its
own confirmed sheets, rather than waiting out a year of a calendar window it
had no way to have filled in advance.

## Consequences

`SAF_TRIR` and `SAF_LTIFR` gain entries in `safety/kpi-registry.js` only once
this window-and-sum arithmetic and the `no_data` reason are implemented — #233
is that ticket, and this ADR is what it is built to. Until then the board
keeps answering `no_data` for both exactly as it does today, for the reason
already named in that file's own header, now joined by this one: even once
`attendance_records` has rows, a `no_data` reader still has to be told
*which* unconfirmed shift is why, not just that the number is missing.
Every other Safety and Cost number that reads `attendance_records` —
`v_labour_cost`, `v_attendance_rate`, `PPL_ABSENTEEISM`, `PPL_HEADCOUNT` —
stays filed against its own board period exactly as it already is; the
rolling window and the `no_data`-with-a-reason rule are specific to these
two rates; the two-Convention split named in the baseline's comment
(`200000` for TRIR, `1000000` for LTIFR) is unchanged.
