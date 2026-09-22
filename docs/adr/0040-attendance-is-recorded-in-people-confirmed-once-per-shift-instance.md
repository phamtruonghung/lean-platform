---
status: accepted
---

# Attendance is recorded in People, confirmed once per shift instance

Date: 2026-09-22

Issue #247 named the gap: `SAF_TRIR`, `SAF_LTIFR`, `PPL_ABSENTEEISM` and
`PPL_HEADCOUNT` all report `no_data` for the same reason — nothing in the
Platform knows who worked which shift, or for how long. The baseline already
carries the tables and views this needs — `attendance_records`,
`v_attendance_rate`, `v_safety_rates`, `v_labour_cost` — but nothing writes a
row to `attendance_records`, so every view built on it returns none. The
plants this is for have no time-and-attendance or payroll system; hours are
known only from the shift plan and a supervisor's knowledge of who turned up.
This ADR records decisions 1–6 of #247: where attendance lives, whose hours
count, how a sheet is pre-filled, what confirmation is, who may act, and how
a confirmed sheet is corrected. Decisions 7–9 — the injury-rate arithmetic
itself — are ADR-0041's. Issue #248 is documentation only: nothing here
changes code, and #249 is where the schema below is actually built.

## The decision

**Attendance is recorded in People, not entered by hand and not imported.**
Hours are recorded against a shift instance in the `people` Module, never
typed in by a supervisor as a total per Org Unit and never imported from a
payroll system — the plants this serves have neither. Attendance is a
`people` capability that Safety, Cost and People all read from, the same way
Assignment already is; it is not Safety's to own even though two of its four
consumers are Safety KPIs.

**Every Employee's hours count, whatever their employment type.** A sheet
counts every Employee in the Directory — `permanent`, `temporary`, `agency`,
`contractor` or `apprentice` alike — because the convention this Platform
already follows is to count the people whose work is supervised day to day,
not the people on one particular payroll. This is the same boundary
ADR-0037 already draws for who can be *named* on an incident: an Employee
record is what makes a person identifiable to the plant at all, so someone
with none can be neither named on an incident nor counted in the hours an
incident rate divides by.

**A sheet is pre-filled from the roster, corrected by exception.** A sheet
starts with every active Employee whose `default_crew_id` names the shift
instance's crew; when the shift has no crew, it falls back to the Employees
whose `default_org_unit_id` is the shift's Org Unit. Each row starts
`present`, with `scheduled_minutes = worked_minutes =
duration_minutes − break_minutes` taken from the shift definition —
`shift_definitions.break_minutes` is time nobody worked, and
`planned_production_minutes` is machine time and plays no part here, exactly
as it plays no part in `v_shift_oee`'s own reading of the same row. A normal
shift is confirmed with the roster untouched; the supervisor's own work is
marking the exceptions — an absence with a reason, a late arrival, an early
finish, overtime — adding a stand-in drawn from the Directory, and removing
anyone who was never actually rostered.

**Confirmation is its own record, never inferred.** A new `attendance_sheets`
table holds one row per shift instance, carrying `confirmed_at` and
`confirmed_by_account_id`. Nothing about a shift is read as confirmed because
rows exist for it: "everyone on the roster was absent" and "nobody has
filled this sheet in yet" are both a sheet with rows recording no presence,
and they have to stay distinguishable, which only an explicit confirmation
record can do.

**Recording needs an edit Grant, and nothing more.** Anyone holding an edit
Grant reaching the shift's Org Unit may record, confirm or correct its
sheet. No new authority is added for this — attendance is an operational
fact about a shift the supervisor already runs, not a judgment call the way
Safety authority (ADR-0039) or Quality authority (ADR-0035) gate one, and
#223 already settled the same question for recording a Safety incident or
observation: that needs only an edit Grant too.

**A confirmed sheet is corrected under the same Grant, audited.** The Grant
that could confirm it can correct it afterwards, and every correction is
recorded with `attach_audit`, the same mechanism every other write in this
Platform is audited with. A correction restates the production day the shift
fell in — the same rule #223 sets for a severity correction, and for the
same reason: a number is filed against when the work happened, not against
when someone got around to fixing the record of it, so a corrected shift's
hours move on the board the next time that day is read, not on the day of
the correction.

## Why not a supervisor entering hours as a total

Rejected: a single number per Org Unit per shift cannot answer any of the
four KPIs this exists for. `PPL_HEADCOUNT` and `PPL_ABSENTEEISM` need to know
*who*, not just *how many* — a headcount is a count of Employees, and an
absenteeism rate needs to know which of them were expected and were not
there. A total also cannot be corrected by exception: there is no roster
behind it to mark one person late against, only a figure someone would have
to re-derive by hand every time it was wrong. And a number typed once a
shift, with no row behind it naming who it describes, cannot be joined back
to `safety_incidents` to name who was on shift when an injury happened —
the very thing an injury rate's exposure hours have to represent.

## Why not a payroll import

Rejected as a fit for what this ticket serves: the plants this is for have
no time-and-attendance or payroll system in the first place, so an importer
would have nothing to read from — #247's own problem statement says so
plainly. Building one on spec, for a feed that does not exist at a single
one of these plants, would be work aimed at no reader, and it would still
leave every plant with no time-and-attendance system unable to record
attendance at all, which is the actual gap #247 opened against. Nothing
here forecloses an import arriving later for a plant that does run payroll
through a system with an API — it would write the same `attendance_sheets`
and per-Employee rows this ADR describes, the same way any two writers of
one fact already coexist elsewhere in this Platform — but it is not what
today's four `no_data` KPIs are waiting on.

## Consequences

`attendance_records` — present in the baseline schema since ADR-0003, and
already read by `v_attendance_rate`, `v_safety_rates` and `v_labour_cost` —
gains its first writer once #249 ships; the four `no_data` KPIs this ADR
exists for begin reporting real numbers the day a Site's supervisors start
confirming sheets, not before. `attendance_sheets` is a table #249 adds; it
does not exist yet, and nothing here migrates it. Correcting a confirmed
sheet moves `worked_hours` on `v_labour_cost` and `v_safety_rates` for a
past production day exactly as a severity correction already moves
`SAF_INCIDENTS`' own numbers for one — a historical figure changing is the
record being corrected, not a bug, and #249 inherits that shape rather than
inventing a different one for attendance.

What #249 still has to settle: the exact vocabulary a correction uses for
"left early" or "added as a stand-in" against `attendance_records`' existing
`attendance_status` values, and how a stand-in drawn from outside the
roster is recorded against a sheet that started without them. Neither
changes who may act or what a confirmed sheet means, so neither is decided
here.
