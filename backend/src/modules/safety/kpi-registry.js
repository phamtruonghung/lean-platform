/*
 * Safety's contribution to the tier board's KPI registry (issue #232, parent
 * #223 decisions 3 and 5).
 *
 * The registry was made composable by issue #202: each Module's entry point
 * contributes its own entries and src/index.js — where the application composes
 * its Modules — spreads them into the one registry the board is handed. This
 * file is Safety's half, and it is the whole of the coupling the board costs
 * either Module: nothing in `maintenance` or `quality` changes, and no Module
 * requires another (ADR-0006's boundary check is what enforces that).
 *
 * WHAT EACH ENTRY CLAIMS, AND WHAT IS DELIBERATELY LEFT OUT
 * --------------------------------------------------------
 * Three codes, which are every Safety-pillar number this Platform's own
 * records can answer today:
 *
 *   - `SAF_INCIDENTS` counts the Safety incidents that caused something — an
 *     injury or property damage — excluding `incident_type = 'near_miss'`, at
 *     the chosen Org Unit and everything beneath it.
 *   - `SAF_NEARMISS` counts `incident_type = 'near_miss'` in the period —
 *     what kind of event it was, never `severity_level`.
 *   - `SAF_OBSERVATIONS` counts the Safety observations recorded in the
 *     period.
 *
 * `SAF_TRIR` and `SAF_LTIFR` are deliberately absent, and their absence is the
 * point rather than an omission: both are rates per worked hour, and
 * `v_safety_rates` drives off a worked-hours CTE built from
 * `attendance_records`, which nothing in the Platform writes — `hours` in that
 * view's own WITH clause has no rows to select, so the view itself returns
 * none, whether or not a Safety incident exists to join against it. Quality
 * settled the identical question the identical way for `QUA_FPY` and the PPM
 * codes (`quality/kpi-registry.js`'s own header): a rate computed on a
 * denominator that does not exist is an invented number. board.js's own
 * `computeRegistryKpi` reports `no_data` for any KPI code this registry does
 * not name, so leaving both codes out of the object below — rather than
 * pointing them at a source that would return nothing anyway — is what makes
 * that the whole of how they stay `no_data`. Exposure hours are #233.
 *
 * TWO SEEDED DEFINITIONS WERE WRONG TOGETHER, AND THIS DEPARTS FROM ONE OF THEM
 * ------------------------------------------------------------------------------
 * `SAF_INCIDENTS`'s seeded `formula_text` reads "All incidents recorded, at
 * any severity," and the baseline's own `v_safety_rates.incident_count` counts
 * every row in `safety_incidents` regardless of `incident_type` — near misses
 * included. Taken literally alongside `SAF_NEARMISS` (`higher_better`, "near
 * misses reported"), one near-miss report would move both numbers on the board
 * at once, in opposite directions: `SAF_INCIDENTS` is `lower_better`, so the
 * same report that makes the culture metric look better makes the incident
 * count look worse. A plant that succeeds at near-miss reporting would watch
 * its incident count climb for reporting well. This ticket departs from the
 * seeded formula: `SAF_INCIDENTS` here excludes `incident_type = 'near_miss'`,
 * counting only incidents that caused something — an injury or property
 * damage — so the two numbers can never move against each other from the same
 * report (#223 decision 3). `SAF_NEARMISS` counts the same field,
 * `incident_type = 'near_miss'`, never `severity_level` — a damage-only fire
 * sits on `severity_level`'s no-injury rung (`near_miss`, per decision 3's own
 * naming) but is `incident_type = 'fire'`, so it counts toward `SAF_INCIDENTS`
 * and never toward `SAF_NEARMISS`.
 *
 * WHY AN ENTRY'S SOURCE IS A DERIVED TABLE RATHER THAN A VIEW NAME
 * -----------------------------------------------------------------
 * `maintenance/kpi-registry.js`'s header describes the shape board.js reads:
 * each entry ties a KPI code to `{ view, valueColumn | ratio, dateColumn,
 * orgUnitColumn }`, and board.js reads it as `FROM <view> v`, rolls the
 * matching rows up the Org Unit tree the way the definition's `aggregation`
 * says, and filters them by `dateColumn` when the definition is a period
 * measure. All three entries here are period counts of this Module's own
 * records — one row per Org Unit per production day — and no baseline view
 * carries that shape for either table, `v_safety_rates` being the per-rate
 * view this Module deliberately does not claim. So each entry names a derived
 * table — a subquery in the `view` slot, the same thing `quality/kpi-
 * registry.js`'s two counts do and the same thing board.js means by "view":
 * something aliased `v` with the columns the entry names. It is computed on
 * read like every other number on the board, it lives in this Module's own
 * contribution, and it changes nothing in `maintenance` or `quality`.
 *
 * FILED BY PRODUCTION DAY, NEVER BY THE CALENDAR (ADR-0017)
 * -----------------------------------------------------------
 * `safety_incidents` and `safety_observations` are both in the eleven tables
 * `attach_shift_instance` covers (ADR-0017's own list), so every row already
 * carries a `shift_instance_id` filled in by the same `fill_shift_instance`
 * trigger the baseline attaches everywhere else — the "one place that cannot
 * forget" ADR-0017 argues for. Each derived table below joins `shift_instances`
 * and groups by its `production_date`, exactly as the baseline's own
 * `v_safety_rates` already does for the same two tables, rather than deriving
 * a second, weaker notion of "today" from `occurred_at`/`observed_at` and a
 * timezone. A row whose trigger left `shift_instance_id` null — a Site with no
 * shift pattern configured, ADR-0017's own open question — is not counted by
 * any of these three entries, the same silence `v_safety_rates` already
 * carries for such a row.
 *
 * NO INJURY DETAIL IS READ, AND NONE IS EXPOSED
 * ------------------------------------------------
 * Every derived table below is `COUNT(*)` over `org_unit_id` and a production
 * day; none selects `employee_id`, `injury_type_id` or `body_part_id`. The
 * #224 read restriction on those three columns (ADR-0037) governs what a
 * caller of `safety-incident-routes.js` may read about one incident; it has
 * nothing to gate here; because this file never reads them, a caller who may
 * not read who was hurt still sees the right number on the board.
 *
 * A ZERO IS NOT REPORTED HERE — THESE ARE PERIOD MEASURES
 * ----------------------------------------------------------
 * All three entries carry a `dateColumn`, so a period with no matching row
 * reports `no_data`, exactly as `QUA_COMPLAINTS` and both Cost entries do:
 * there is no LEFT JOIN out of `org_units` widening a quiet period into a
 * measured zero. That is a deliberate difference from `QUA_OPEN_NC` and
 * `QUA_OVERDUE_CAPA`, which are snapshots with no period at all — a Safety
 * incident count has a period ("incidents this shift"), a snapshot state does
 * not ("open Non-conformances this shift" is not a sentence), so the two
 * pillars' entries are shaped differently on purpose.
 *
 * A CORRECTED SEVERITY RESTATES THE PERIOD THE INCIDENT OCCURRED IN
 * ---------------------------------------------------------------------
 * `safety-incidents.js`'s own severity-change route lets a first-aid case
 * later recorded as lost-time be corrected with a note (#223 decision 5), and
 * the row's `org_unit_id`, `occurred_at` and therefore `shift_instance_id` do
 * not move when that happens — only `severity_level` does. Since
 * `SAF_INCIDENTS` and `SAF_NEARMISS` key off `incident_type`, not
 * `severity_level`, a severity correction never moves either of these two
 * counts (it would move `SAF_TRIR`/`SAF_LTIFR`'s `recordable_count`, were they
 * on the board). It is recorded here because it is the general shape every
 * count in this registry takes: nothing here is filed against a frozen
 * snapshot of the incident as first recorded, so any correction to a past
 * incident — severity or otherwise — restates the production day it occurred
 * on, the next time the board is read for that day, rather than the day the
 * correction was made. A historical number moving is the record being
 * corrected, not a bug.
 */

// One row per Org Unit per production day: how many Safety incidents that
// caused something — an injury or property damage — were recorded there.
// `incident_type <> 'near_miss'` is the departure from the seeded
// `formula_text` this file's header argues; `severity_level` plays no part; a
// damage-only fire on the no-injury rung is `incident_type = 'fire'`, so it
// counts here.
const INCIDENTS_THAT_CAUSED_SOMETHING = `(
  SELECT sn.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS incident_count
    FROM safety_incidents sn
    JOIN shift_instances si ON si.id = sn.shift_instance_id
   WHERE sn.incident_type <> 'near_miss'
   GROUP BY sn.org_unit_id, si.production_date
)`;

// One row per Org Unit per production day: how many near misses were
// reported. `incident_type = 'near_miss'`, never `severity_level` — the
// severity ladder's own bottom rung happens to share the spelling, but it
// means "no injury" on a record of any kind, and is not what this count reads
// (#223 decision 3).
const NEAR_MISSES_REPORTED = `(
  SELECT sn.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS near_miss_count
    FROM safety_incidents sn
    JOIN shift_instances si ON si.id = sn.shift_instance_id
   WHERE sn.incident_type = 'near_miss'
   GROUP BY sn.org_unit_id, si.production_date
)`;

// One row per Org Unit per production day: how many Safety observations were
// logged there, the leading indicator beside the two lagging counts above.
const OBSERVATIONS_LOGGED = `(
  SELECT so.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS observation_count
    FROM safety_observations so
    JOIN shift_instances si ON si.id = so.shift_instance_id
   GROUP BY so.org_unit_id, si.production_date
)`;

// code -> how to read it. `valueColumn` is a column of the source the entry
// names, exactly as Maintenance's and Quality's own entries are — see this
// file's header for why every source here is a derived table rather than a
// view name, and why `SAF_TRIR`/`SAF_LTIFR` carry no entry at all.
const KPI_REGISTRY = {
  SAF_INCIDENTS: {
    view: INCIDENTS_THAT_CAUSED_SOMETHING,
    valueColumn: 'incident_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  SAF_NEARMISS: {
    view: NEAR_MISSES_REPORTED,
    valueColumn: 'near_miss_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  SAF_OBSERVATIONS: {
    view: OBSERVATIONS_LOGGED,
    valueColumn: 'observation_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  }
};

module.exports = KPI_REGISTRY;
