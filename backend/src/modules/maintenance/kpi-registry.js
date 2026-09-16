/*
 * Maintenance's contribution to the tier board's KPI registry (issue #202).
 *
 * The registry used to be a constant inside board.js, which meant the board —
 * and therefore every Module's numbers — was Maintenance's to edit. It is
 * composable now: each Module's entry point contributes its own entries
 * (maintenance/index.js exports this file as `kpiRegistry`) and src/index.js
 * assembles the registry where it composes the application's Modules, handing
 * the result to the one route that needs it
 * (`maintenance.createBoardRouter(kpiRegistry)`). Nothing here reaches another
 * Module, and the board's own code knows no KPI by name — a Module can put a
 * number on the board without board.js changing, and without any Module
 * requiring another (ADR-0006).
 *
 * THE SHAPE, AND WHY IT IS AN EXPLICIT MAPPING
 * --------------------------------------------
 * `kpi_definitions` names the view a derived KPI comes from (`source_view`)
 * but not the column that holds its value, and the views differ in shape: one
 * is a per-asset average, one a per-org-unit ratio, one a snapshot with no
 * date at all. A small, explicit registry is therefore the honest mapping, not
 * a general SQL-string engine: each seeded maintenance KPI code is tied to
 * { view, valueColumn | ratio, dateColumn, orgUnitColumn }. A definition whose
 * `source_view` is not in any Module's contribution — the whole Safety,
 * Quality and People catalogue, whose Modules do not record work yet —
 * reports `no_data` rather than inventing an answer.
 *
 * Adding a Maintenance KPI is one entry here and nothing else. Adding another
 * Module's KPI is one entry in that Module's own contribution, spread in at
 * src/index.js: no file in this Module is touched either way.
 */

// code -> how to read it out of its view. `ratio` entries recompute the ratio
// from its numerator and denominator rather than averaging a pre-computed
// percentage, so a week or a subtree is weighted by the underlying counts, not
// by how many rows happened to fall in each bucket.
const KPI_REGISTRY = {
  MNT_PM_COMPLIANCE: {
    view: 'v_pm_compliance',
    dateColumn: 'period_start',
    orgUnitColumn: 'org_unit_id',
    ratio: { numerator: 'pm_on_time', denominator: 'pm_due', scale: 100 }
  },
  MNT_SCHEDULE_COMPLIANCE: {
    view: 'v_maintenance_schedule_compliance',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id',
    ratio: { numerator: 'started_in_window', denominator: 'scheduled_jobs', scale: 100 }
  },
  MNT_MTBF: {
    view: 'v_downtime_mtbf_mttr',
    valueColumn: 'mtbf_hours',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  MNT_MTTR: {
    view: 'v_downtime_mtbf_mttr',
    valueColumn: 'mttr_hours',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  MNT_PLANNED_RATIO: {
    view: 'v_maintenance_planned_ratio',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id',
    ratio: { numerator: 'planned_hours', denominator: 'total_hours', scale: 100 }
  },
  // A snapshot, not a period measure: v_maintenance_backlog has no date
  // column at all, so it is summed over the subtree with no period filter.
  // That is the honest reading — there is no "backlog for last Tuesday".
  MNT_BACKLOG: {
    view: 'v_maintenance_backlog',
    valueColumn: 'backlog_hours',
    dateColumn: null,
    orgUnitColumn: 'org_unit_id'
  },
  // See THE COST WARNING in board.js: total_cost is a SLICE of COST_LABOUR,
  // never an addition to it. Only parts_cost is new money against the plant.
  MNT_COST: {
    view: 'v_maintenance_cost',
    valueColumn: 'total_cost',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  MNT_PARTS_COST: {
    view: 'v_maintenance_cost',
    valueColumn: 'parts_cost',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  }
};

module.exports = KPI_REGISTRY;
