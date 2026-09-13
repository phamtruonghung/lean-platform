/*
 * The tier board's read service (issue #76). One question — "what are the KPI
 * numbers for this Site's Org Unit and everything beneath it, over this
 * period?" — answered from the baseline's own reporting views.
 *
 * This file never requires '../people'. The Site and the chosen Org Unit are
 * resolved one layer up in board-routes.js through modules/people's entry
 * point, exactly as work-orders.js receives an Asset id it did not resolve.
 * It DOES join `org_units` and `sites` directly — ordinary cross-Module reads,
 * the same as assets.js's own join onto org_units; ADR-0006 makes a Module a
 * code seam, not a data seam.
 *
 * WHY THIS COMPUTES ON READ INSTEAD OF WRITING kpi_actuals
 * --------------------------------------------------------
 * The board reads the views the baseline already ships and aggregates them in
 * SQL per request; it does not materialise rows into `kpi_actuals`. Two
 * reasons:
 *
 *   1. Volume is tiny and correctness is free. The views are the floor data
 *      aggregated — the same bargain the SQDCP catalogue makes — so a read
 *      cannot disagree with the events underneath it. A materialised row is a
 *      second copy of that conclusion, computed at `computed_at` and trusted
 *      forever after; while there is no scheduler to refresh it, a stale
 *      number is worse than a live one.
 *   2. The choice is reversible. `kpi_actuals` already carries `computed_at`
 *      and a `source` of 'derived'/'manual', and `v_sqdcp_board` already reads
 *      it. A later ticket can write these same computed numbers into
 *      `kpi_actuals` on a schedule and have the board read `v_sqdcp_board`
 *      instead, WITHOUT changing this endpoint's request or response shape.
 *      Nothing in this file is a one-way door; that is the point of computing
 *      on read now rather than guessing at a materialisation contract today.
 *
 * No migration and no schema change accompanies this file.
 *
 * THE KPI REGISTRY
 * ----------------
 * `kpi_definitions` names the view a derived KPI comes from (`source_view`)
 * but not the column that holds its value, and the views differ in shape: one
 * is a per-asset average, one a per-org-unit ratio, one a snapshot with no
 * date at all. A small, explicit registry below is therefore the honest
 * mapping, not a general SQL-string engine: each seeded maintenance KPI code
 * is tied to { view, valueColumn | ratio, dateColumn, orgUnitColumn }. A
 * definition whose `source_view` is not reachable through this registry — the
 * whole Safety, Quality and People catalogue, whose Modules do not record work
 * yet — reports `no_data` rather than inventing an answer.
 *
 * THE COST WARNING, REPEATED WHERE IT COULD BE MISSED
 * --------------------------------------------------
 * `MNT_COST` reads `v_maintenance_cost.total_cost`, which includes the
 * maintenance labour cost. That labour is ALREADY inside the plant's
 * `COST_LABOUR` (`v_labour_cost`, costed from attendance — a technician is
 * attendance like anyone else). Summing `MNT_COST` into `COST_LABOUR`
 * double-counts the whole maintenance department. `MNT_PARTS_COST` is the only
 * additive half: the schema has no inventory, so nothing upstream costs a
 * part. This file computes and returns `MNT_COST` as a slice (see
 * v_maintenance_cost's own header in the baseline); it never adds it to
 * anything.
 *
 * PERIODS ARE SITE-LOCAL AND SHIFT-BASED (ADR-0017)
 * ------------------------------------------------
 * A period is resolved from the Site's own timezone and shift calendar, never
 * from the server clock, UTC, or the viewer's timezone. `date` names a
 * production day (the same DATE bucket `shift_instances.production_date` and
 * the reliability views use); omitted, "today" is the production day the
 * Site's shifts currently put us in, falling back to the Site-local calendar
 * date only when no shift covers the moment. The reliability views bucket a
 * stop by the shift that owns it, so filtering them by their own
 * `production_date` is what makes a 05:30 event at a plant whose first shift
 * starts at 06:00 answer under the PREVIOUS production day rather than the
 * calendar date the clock happened to show.
 *
 * TARGETS AND DIRECTION
 * ---------------------
 * The applicable `kpi_targets` row is resolved the way
 * `kpi_actuals_evaluate()` resolves it: the deepest scope whose Org Unit
 * contains the board's Org Unit wins, effective for the period's start — so a
 * line inherits its area's target, then the plant's. `higher_better` and
 * `lower_better` are evaluated without inverting either one: a lower_better
 * KPI at or below target is green and above it moves through its amber ceiling
 * into red; a higher_better KPI at or above target is green and below it moves
 * down through its amber floor into red. No target and no data are distinct
 * states, and neither is a zero.
 */

const { getPool } = require('../../platform/db');
const { notFound } = require('./errors');

// The five pillars are a fixed catalogue in the baseline; the board always
// returns all of them, whether or not anything reports under them yet.
const DEFINITIONS_SQL = `
  SELECT p.code                    AS pillar_code,
         p.name                    AS pillar_name,
         p.sort_order              AS pillar_sort_order,
         kd.id                     AS kpi_definition_id,
         kd.code                   AS kpi_code,
         kd.name                   AS kpi_name,
         kd.unit,
         kd.aggregation,
         kd.direction,
         kd.calculation_type,
         kd.source_view,
         kd.decimal_places,
         kd.formula_text,
         kd.sort_order             AS kpi_sort_order
    FROM sqdcp_pillars p
    LEFT JOIN kpi_definitions kd
      ON kd.pillar_code = p.code
     AND kd.is_active
   ORDER BY p.sort_order, kd.sort_order, kd.code
`;

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
  // See THE COST WARNING above: total_cost is a SLICE of COST_LABOUR, never an
  // addition to it. Only parts_cost is new money against the plant.
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

// Mirrors kpi_actuals_evaluate() in the baseline, exactly, so a read board's
// status agrees with the status a materialised row would carry. Computed on
// the raw value, never on a rounded one: a value that rounds up to its target
// is still below it.
function evaluateStatus(value, target, direction) {
  if (value === null) return 'no_data';
  if (!target) return 'no_target';

  const targetValue = Number(target.target_value);
  if (direction === 'higher_better') {
    if (value >= targetValue) return 'green';
    const lower = target.lower_threshold === null ? null : Number(target.lower_threshold);
    if (lower !== null && value >= lower) return 'amber';
    return 'red';
  }

  if (value <= targetValue) return 'green';
  const upper = target.upper_threshold === null ? null : Number(target.upper_threshold);
  if (upper !== null && value <= upper) return 'amber';
  return 'red';
}

// The production day the Site is in right now, for a board asked for with no
// date. Prefers the shift instance actually covering this moment; a Site with
// no shift calendar falls back to its local calendar date rather than to UTC.
async function currentProductionDate(siteId) {
  const { rows: [row] } = await getPool().query(
    `SELECT COALESCE(
              (SELECT to_char(si.production_date, 'YYYY-MM-DD')
                 FROM shift_instances si
                WHERE si.site_id = $1
                  AND si.status <> 'cancelled'
                  AND si.starts_at <= now()
                  AND si.ends_at > now()
                ORDER BY si.production_date, si.starts_at
                LIMIT 1),
              to_char(now() AT TIME ZONE s.timezone, 'YYYY-MM-DD')
            ) AS production_date
       FROM sites s
      WHERE s.id = $1`,
    [siteId]
  );
  return row.production_date;
}

// A period's start and end as YYYY-MM-DD strings. Strings, not Date objects:
// node-postgres parses a DATE into a JS Date at the process's own midnight,
// which is exactly the server-clock trap ADR-0017 forbids.
async function resolvePeriod(site, { periodType, date, shiftInstanceId }) {
  if (periodType === 'shift') {
    // The named shift's own window, expressed in the Site's clock. A caller
    // asking for a shift is asking for that shift, so an id that belongs to
    // another Site — or to nothing — is a clean 404 here, one layer below the
    // route that already proved its format.
    const { rows: [row] } = await getPool().query(
      `SELECT to_char(si.starts_at AT TIME ZONE s.timezone, 'YYYY-MM-DD') AS start_date,
              to_char(si.ends_at   AT TIME ZONE s.timezone, 'YYYY-MM-DD') AS end_date
         FROM shift_instances si
         JOIN sites s ON s.id = si.site_id
        WHERE si.id = $1
          AND si.site_id = $2`,
      [shiftInstanceId, site.id]
    );
    if (!row) throw notFound('Shift instance');
    return { type: 'shift', start: row.start_date, end: row.end_date };
  }

  const base = date ?? await currentProductionDate(site.id);
  const { rows: [row] } = await getPool().query(
    `SELECT to_char($1::date, 'YYYY-MM-DD')                                          AS base_date,
            to_char(date_trunc('week',  $1::date), 'YYYY-MM-DD')                     AS week_start,
            to_char(date_trunc('week',  $1::date) + interval '6 days', 'YYYY-MM-DD') AS week_end,
            to_char(date_trunc('month', $1::date), 'YYYY-MM-DD')                     AS month_start,
            to_char(date_trunc('month', $1::date) + interval '1 month - 1 day',
                    'YYYY-MM-DD')                                                    AS month_end`,
    [base]
  );

  if (periodType === 'week') return { type: 'week', start: row.week_start, end: row.week_end };
  if (periodType === 'month') return { type: 'month', start: row.month_start, end: row.month_end };
  return { type: 'day', start: row.base_date, end: row.base_date };
}

// The Org Unit a Site-wide board resolves its targets against: the Site's root,
// where the one plant-wide target lives. Null when the Site has no root at all
// (which also means no target can have been configured for it).
async function findSiteRootPath(siteId) {
  const { rows: [row] } = await getPool().query(
    `SELECT path
       FROM org_units
      WHERE site_id = $1
        AND parent_id IS NULL
      ORDER BY sort_order, id
      LIMIT 1`,
    [siteId]
  );
  return row ? row.path : null;
}

// Every target that could apply, keyed by KPI definition, resolved in one
// query: DISTINCT ON keeps the deepest scope (the `nlevel ... DESC` matches
// kpi_actuals_evaluate's own ordering), which is the hierarchy inheritance the
// schema documents. `scope.path @> boardPath` means the target's scope is an
// ancestor or the board's own Org Unit.
async function resolveTargets(boardPath, periodType, periodStart) {
  const targets = new Map();
  if (!boardPath) return targets;

  const { rows } = await getPool().query(
    `SELECT DISTINCT ON (kt.kpi_definition_id)
            kt.kpi_definition_id,
            kt.target_value,
            kt.lower_threshold,
            kt.upper_threshold
       FROM kpi_targets kt
       JOIN org_units scope ON scope.id = kt.org_unit_id
      WHERE kt.period_type = $1
        AND kt.effective_from <= $2::date
        AND (kt.effective_to IS NULL OR kt.effective_to > $2::date)
        AND scope.path @> $3::ltree
      ORDER BY kt.kpi_definition_id, nlevel(scope.path) DESC`,
    [periodType, periodStart, boardPath]
  );

  for (const row of rows) targets.set(String(row.kpi_definition_id), row);
  return targets;
}

// One registry KPI over the rows whose Org Unit is in the subtree and whose
// date falls in the period, aggregated the way the definition asks. A view
// outside the registry, or no rows at all, returns null — never 0.
async function computeRegistryKpi(definition, siteId, orgUnit, period) {
  const entry = KPI_REGISTRY[definition.kpi_code];
  if (!entry || definition.calculation_type !== 'derived') return null;

  const params = [siteId];
  const conditions = [];

  let orgFilter = `v.${entry.orgUnitColumn} IN (SELECT id FROM org_units WHERE site_id = $1`;
  if (orgUnit) {
    params.push(orgUnit.path);
    orgFilter += ` AND path <@ $${params.length}::ltree`;
  }
  orgFilter += ')';
  conditions.push(orgFilter);

  if (entry.dateColumn) {
    params.push(period.start);
    const start = `$${params.length}`;
    params.push(period.end);
    const end = `$${params.length}`;
    conditions.push(`v.${entry.dateColumn} BETWEEN ${start}::date AND ${end}::date`);
  }

  let aggregate;
  if (definition.aggregation === 'ratio' || definition.aggregation === 'rate') {
    if (!entry.ratio) return null;
    const { numerator, denominator, scale } = entry.ratio;
    aggregate = `SUM(v.${numerator})::numeric / NULLIF(SUM(v.${denominator}), 0) * ${scale}`;
  } else if (definition.aggregation === 'avg') {
    aggregate = `AVG(v.${entry.valueColumn})`;
  } else if (definition.aggregation === 'count') {
    aggregate = 'COUNT(*)';
  } else if (definition.aggregation === 'last') {
    if (!entry.dateColumn) return null;
    aggregate = `(ARRAY_AGG(v.${entry.valueColumn} ORDER BY v.${entry.dateColumn} DESC NULLS LAST))[1]`;
  } else {
    aggregate = `SUM(v.${entry.valueColumn})`;
  }

  const { rows: [row] } = await getPool().query(
    `SELECT COUNT(*)::int AS row_count, (${aggregate})::numeric AS value
       FROM ${entry.view} v
      WHERE ${conditions.join(' AND ')}`,
    params
  );

  if (row.row_count === 0 || row.value === null) return null;
  return Number(row.value);
}

// The whole board. `site` and `orgUnit` are People records the route already
// resolved (orgUnit null means the whole Site); this function assumes they
// exist and is unaware of who is calling — a read carries no Grant filter
// (ADR-0009), because Org Unit scope decides where an Account may act, not
// what it may know about.
async function getBoard(site, { orgUnit = null, periodType, date = null, shiftInstanceId = null } = {}) {
  const period = await resolvePeriod(site, { periodType, date, shiftInstanceId });
  const { rows } = await getPool().query(DEFINITIONS_SQL);

  const boardPath = orgUnit ? orgUnit.path : await findSiteRootPath(site.id);
  const targets = await resolveTargets(boardPath, periodType, period.start);

  const pillars = [];
  const byCode = new Map();

  for (const row of rows) {
    let pillar = byCode.get(row.pillar_code);
    if (!pillar) {
      pillar = {
        code: row.pillar_code,
        name: row.pillar_name,
        sortOrder: row.pillar_sort_order,
        hasData: false,
        kpis: []
      };
      byCode.set(row.pillar_code, pillar);
      pillars.push(pillar);
    }

    if (row.kpi_definition_id === null) continue;

    const value = await computeRegistryKpi(row, site.id, orgUnit, period);
    const target = targets.get(String(row.kpi_definition_id)) ?? null;

    pillar.kpis.push({
      code: row.kpi_code,
      name: row.kpi_name,
      unit: row.unit,
      direction: row.direction,
      decimalPlaces: row.decimal_places,
      formulaText: row.formula_text,
      value,
      status: evaluateStatus(value, target, row.direction),
      targetValue: target ? Number(target.target_value) : null
    });

    if (value !== null) pillar.hasData = true;
  }

  return {
    site: { id: site.id, name: site.name, timezone: site.timezone },
    orgUnit: orgUnit ? { id: orgUnit.id, name: orgUnit.name, path: orgUnit.path } : null,
    period,
    pillars
  };
}

module.exports = {
  KPI_REGISTRY,
  getBoard,
  evaluateStatus
};
