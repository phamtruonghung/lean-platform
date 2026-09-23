/*
 * People's contribution to the tier board's KPI registry (issue #251, parent
 * #247, ADR-0040).
 *
 * The registry was made composable by issue #202: each Module's entry point
 * contributes its own entries and src/index.js — where the application composes
 * its Modules — spreads them into the one registry the board is handed. This
 * file is People's share, and it is the whole of the coupling the board costs
 * this Module: nothing in `maintenance`, `quality` or `safety` changes, and no
 * Module requires another (ADR-0006's boundary check is what enforces that).
 * This file requires nothing at all — not even `platform/db` — because both
 * entries below are read by board.js's own generic reader rather than by a
 * query of their own; see "WHY NEITHER ENTRY CARRIES `compute`" below.
 *
 * WHAT EACH ENTRY CLAIMS
 * -----------------------
 * Two codes, the two People-pillar numbers confirmed attendance can answer:
 *
 *   - `PPL_ABSENTEEISM` is the absences whose reason carries
 *     `counts_as_absenteeism` over the scheduled headcount, excluding rows
 *     recorded `not_scheduled`, across the board's period and the chosen Org
 *     Unit subtree. The top and the bottom are each added up over all of it
 *     and divided once — never an average of daily or per-Org-Unit
 *     percentages.
 *   - `PPL_HEADCOUNT` is the average headcount present per confirmed shift
 *     instance, where present is `present`, `late` or `training` — exactly
 *     the three statuses the baseline's own `v_attendance_rate.present_headcount`
 *     counts, never re-spelled into a fourth reading of the same idea.
 *
 * WHAT IS DELIBERATELY LEFT OUT, AND WHY
 * ---------------------------------------
 * `PPL_SKILL_COVERAGE` and `PPL_OVERDUE_ACTIONS` are absent. Neither is a
 * number attendance unblocked, and neither is this ticket's: #251 names
 * exactly the two codes above, both of them the ones #247 opened against as
 * reporting `no_data` for want of a writer to `attendance_records`. Skill
 * coverage reads `v_skill_coverage`, which has had rows since the skills
 * matrix shipped and is a claim a later ticket can make on its own merits;
 * `PPL_OVERDUE_ACTIONS` reads `v_open_actions`, an Actions record rather than
 * a People one, so it is not this Module's to claim at all. `COST_OVERTIME`
 * reads the same `v_attendance_rate` these two entries' own source mirrors,
 * and is likewise absent: it is a Cost-pillar number, and #252 is where the
 * Cost pillar's reading of attendance is decided (`COST_LABOUR` beside it).
 * Claiming a code here because its source happens to be near at hand is how a
 * registry stops matching the Module that owns the record.
 *
 * WHY THE SOURCE IS A DERIVED TABLE RATHER THAN `v_attendance_rate` ITSELF
 * -------------------------------------------------------------------------
 * `maintenance/kpi-registry.js`'s header describes the entry shape board.js
 * reads: `{ view, valueColumn | ratio, dateColumn, orgUnitColumn }`, read as
 * `FROM <view> v`, rolled up the Org Unit tree and narrowed by `dateColumn`
 * when the definition is a period measure. The baseline seeds both of these
 * definitions with `source_view = 'v_attendance_rate'`, and that view very
 * nearly is what these two want — its `absent_headcount`, `scheduled_headcount`
 * and `present_headcount` columns are the exact three quantities below. It is
 * not used, for two reasons that are the whole of this file's SQL:
 *
 *   1. **It cannot tell a confirmed sheet from an unconfirmed one.** The view
 *      predates `attendance_sheets` (issue #249 added that table; the view is
 *      the baseline's) and reads `attendance_records` alone, so a sheet
 *      somebody opened and walked away from counts in it exactly as a
 *      supervisor's confirmed one does. ADR-0040 is explicit that these must
 *      stay different states — "everyone on the roster was absent" and
 *      "nobody has filled this in yet" are both rows recording no presence —
 *      and #251's own criterion says only confirmed sheets count. The derived
 *      table below therefore inner-joins `attendance_sheets` on
 *      `confirmed_at IS NOT NULL`: an unconfirmed sheet contributes nothing to
 *      either number, and a period holding no confirmed sheet at all produces
 *      no rows, which board.js already reports as `no_data` rather than zero.
 *   2. **Its grain is the production day, and `PPL_HEADCOUNT`'s is the shift
 *      instance.** `v_attendance_rate` groups by `(org_unit_id,
 *      production_date)`, so a day running three shifts is one row in it.
 *      `PPL_HEADCOUNT` is seeded `aggregation = 'avg'` and its own
 *      `formula_text` reads "Average headcount present per shift" — board.js
 *      turns that into `AVG(v.present_headcount)`, which means "per row", so
 *      the rows have to BE shift instances or the average silently becomes
 *      per-day. The derived table below adds `si.id` to the grouping, making
 *      one row per confirmed shift instance.
 *
 * Grouping one level finer costs `PPL_ABSENTEEISM` nothing, which is why one
 * derived table serves both: a ratio summed over shift instances and a ratio
 * summed over the days those shift instances roll into are the same number,
 * because summing the numerators and the denominators first is associative.
 * Averaging them would not have been — which is exactly why this file sums and
 * divides once, and says so again below.
 *
 * WHY NEITHER ENTRY CARRIES `compute`, AND HOW THAT DIFFERS FROM THE INJURY RATES
 * --------------------------------------------------------------------------------
 * `safety/kpi-registry.js`'s `SAF_TRIR` and `SAF_LTIFR` read the very same two
 * tables these entries do — `attendance_records` for the quantity,
 * `attendance_sheets` for whether it may be trusted — and they carry board.js's
 * `compute` escape hatch, owning a query of their own. These two do not, and
 * the difference is not a shortcut taken here. It is that the two pairs follow
 * genuinely different rules, for a reason worth stating rather than inheriting:
 *
 *   - **Window.** ADR-0041 gives the injury rates a rolling 12 months ending
 *     at the board period's end, floored at the subtree's first confirmed
 *     shift — a window the `{ view, dateColumn }` shape cannot express, since
 *     a derived subquery never sees `period.end` to reach back from it. These
 *     two use the board's own period, like every other number on the board;
 *     ADR-0041's own Consequences section says so in as many words
 *     ("`PPL_ABSENTEEISM`, `PPL_HEADCOUNT` — stays filed against its own board
 *     period exactly as it already is"). A `dateColumn` is all that takes.
 *   - **What an unconfirmed sheet does.** For an injury rate, one unconfirmed
 *     past shift anywhere in the window blanks the whole number, and it has
 *     to: a rate's denominator is exposure, and an incomplete denominator does
 *     not make the rate a bit less precise, it makes it wrong in a known
 *     direction — hours missing inflates it, and an injury recorded against
 *     the shift whose hours are missing can vanish from the numerator
 *     entirely. Reporting a number nobody can act on as though it were
 *     measured is worse than reporting nothing. Absenteeism is a different
 *     kind of quantity: it is a ratio *of what was recorded*, not an estimate
 *     of a population. A second shift nobody has confirmed yet does not make
 *     the first shift's 2-absences-in-30 untrue; it only means the board is
 *     reporting on one shift rather than two, which is the same thing every
 *     other period measure on this board already does when a record has not
 *     been written yet. So these two need no Site-wide floor, no EXISTS
 *     against `attendance_sheets` blocking the figure, and no rolling window —
 *     an unconfirmed sheet is simply not in the source, and confirming it
 *     later restates the day, the same way every correction in this Platform
 *     restates the production day it falls in (ADR-0040).
 *
 * The consequence is that the generic reader expresses both entries exactly:
 * `PPL_ABSENTEEISM` is seeded `aggregation = 'ratio'`, which board.js already
 * computes as `SUM(numerator) / NULLIF(SUM(denominator), 0) * scale` over the
 * rolled-up, period-filtered rows — sum the top, sum the bottom, divide once,
 * which is the arithmetic #251 asks for and the same rule ADR-0041 sets for
 * the injury rates, reached here without a line of SQL of this file's own.
 * `PPL_HEADCOUNT` is seeded `aggregation = 'avg'` over the shift-instance rows
 * described above. Nothing in this file needs the escape hatch, which is the
 * shape the escape hatch's own comment in board.js asks for: "No existing
 * entry needs this; it exists for the entries that cannot be expressed any
 * other way."
 *
 * FILED BY PRODUCTION DAY, AND ROLLED UP THE ORG UNIT TREE (ADR-0017)
 * --------------------------------------------------------------------
 * `attendance_records` carries no timestamp of its own and needs none: every
 * row names a `shift_instance_id`, and the shift instance carries both the
 * `production_date` it was worked on and the `org_unit_id` it was worked in.
 * The derived table below reads both off `shift_instances` — never off the
 * attendance row's own `org_unit_id`, and never off a calendar date derived
 * from a timestamp and a timezone — which is exactly what `v_attendance_rate`,
 * `v_safety_rates` and `v_labour_cost` all already do with the same table.
 * board.js's own org filter (`v.org_unit_id IN (SELECT id FROM org_units WHERE
 * site_id = $1 AND path <@ $2::ltree)`) is what makes an area's number the sum
 * of its own shifts and every line's beneath it; nothing here has to roll
 * anything up itself.
 *
 * A ZERO IS A REAL MEASUREMENT; NO CONFIRMED SHEET IS NOT
 * ---------------------------------------------------------
 * Both entries carry a `dateColumn`, so a period with no confirmed sheet
 * produces no rows and board.js answers `no_data` — never `0`, and never a
 * headcount averaged over nothing. Once there is one confirmed sheet in the
 * period and subtree, both numbers are real: a shift on which nobody was
 * absent reports `0` absenteeism (a clean shift, not a missing one), and a
 * confirmed shift on which nobody turned up reports a headcount of `0`, which
 * is precisely the state ADR-0040 built `attendance_sheets` to keep
 * distinguishable from "nobody has filled this in".
 *
 * One boundary follows from mirroring `v_attendance_rate`'s own
 * `WHERE ar.attendance_status <> 'not_scheduled'`: a confirmed sheet on which
 * every row is `not_scheduled` — nobody was rostered at all — contributes no
 * row and so reads `no_data` rather than zero. That is the honest answer
 * rather than a gap: there is no scheduled headcount to divide by and no
 * roster to average a presence over, and the baseline's own view has always
 * left such a shift out for the same reason.
 *
 * A CORRECTION RESTATES THE PRODUCTION DAY IT FALLS IN
 * ------------------------------------------------------
 * Nothing here reads a frozen snapshot of a sheet as first recorded. A
 * supervisor correcting a confirmed sheet afterwards — marking someone absent,
 * adding a stand-in, removing a row that was never rostered — moves both of
 * these numbers for the production day the shift was worked on, the next time
 * the board is read for that day, and not for the day of the correction. That
 * is ADR-0040's own rule for a correction, the same one `safety/kpi-registry.js`
 * records for a severity correction: a number is filed against when the work
 * happened, not when someone got around to fixing the record of it. A
 * historical number moving is the record being corrected, not a bug.
 *
 * NO IDENTITY IS READ, AND NONE IS EXPOSED
 * ------------------------------------------
 * The derived table below counts rows; it never selects `employee_id` and
 * never joins `employees`. Who was absent is a fact about a person, and it
 * stays in the attendance sheet the supervisor already holds a Grant to read
 * (issue #249's own Screen) rather than being reachable, one Employee at a
 * time, by differencing a Pillar number.
 */

// One row per CONFIRMED shift instance: how many people were scheduled on it,
// how many of them were present, and how many were absent for a reason that
// counts toward absenteeism. The three quantities are `v_attendance_rate`'s
// own `scheduled_headcount`, `present_headcount` and `absent_headcount`
// columns, spelled the same way and reading the same columns — the departures
// from that view are the inner join onto a confirmed `attendance_sheets` row
// and the shift-instance grain, both argued in this file's header.
//
// `counts_as_absenteeism` is the catalogue's own flag, and it is what excludes
// annual leave and training from the numerator while leaving both of them in
// the denominator: someone on annual leave was scheduled and is not at work,
// and a rate that dropped them from the bottom as well as the top would report
// a plant running on a skeleton crew as fully attended. The baseline's
// `absence_reasons` seed is where the flag is set (`HOL` and `TRAIN` are
// `FALSE`, `SICK` and `UNEX` are `TRUE`), and that table's own comment gives
// the reason it is separate from `is_planned`: "Training and annual leave are
// both planned, but only one of them belongs in the absenteeism rate."
//
// `not_scheduled` rows are excluded outright, the same `WHERE` clause the
// baseline's view carries: someone the sheet records as not rostered for this
// shift is neither scheduled nor absent from it.
const CONFIRMED_ATTENDANCE = `(
  SELECT si.org_unit_id                                          AS org_unit_id,
         si.production_date                                      AS production_date,
         si.id                                                   AS shift_instance_id,
         COUNT(*)::numeric                                       AS scheduled_headcount,
         COUNT(*) FILTER (
           WHERE ar.attendance_status IN ('present', 'late', 'training')
         )::numeric                                              AS present_headcount,
         COUNT(*) FILTER (WHERE ab.counts_as_absenteeism)::numeric AS absent_headcount
    FROM attendance_records ar
    JOIN shift_instances si ON si.id = ar.shift_instance_id
    JOIN attendance_sheets sh
      ON sh.shift_instance_id = si.id
     AND sh.confirmed_at IS NOT NULL
    LEFT JOIN absence_reasons ab ON ab.id = ar.absence_reason_id
   WHERE ar.attendance_status <> 'not_scheduled'
   GROUP BY si.org_unit_id, si.production_date, si.id
)`;

// code -> how to read it. Both entries name the one derived table above — see
// this file's header for why it is a derived table rather than
// `v_attendance_rate`, and why one source serves both grains. `ratio` is the
// shape board.js reads for a `ratio`/`rate` definition and `valueColumn` the
// shape it reads for every other aggregation, exactly as Maintenance's and
// Quality's own entries are; neither carries `compute`, and this file's header
// argues why that is a difference from `SAF_TRIR`/`SAF_LTIFR` rather than an
// oversight.
const KPI_REGISTRY = {
  // Seeded `aggregation = 'ratio'`, so board.js computes
  // `SUM(absent_headcount) / NULLIF(SUM(scheduled_headcount), 0) * 100` over
  // every confirmed shift instance in the period and subtree: sum the top, sum
  // the bottom, divide once. `scale: 100` because the definition's unit is
  // `%`; the same 100 `v_attendance_rate.absenteeism_percent` applies to its
  // own per-day division.
  PPL_ABSENTEEISM: {
    view: CONFIRMED_ATTENDANCE,
    ratio: { numerator: 'absent_headcount', denominator: 'scheduled_headcount', scale: 100 },
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  // Seeded `aggregation = 'avg'`, so board.js computes
  // `AVG(present_headcount)` — one row per confirmed shift instance, which is
  // what makes this "per shift" rather than "per day" (this file's header).
  PPL_HEADCOUNT: {
    view: CONFIRMED_ATTENDANCE,
    valueColumn: 'present_headcount',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  }
};

module.exports = KPI_REGISTRY;
