/*
 * Shift handovers (issue #333, ADR-0054): the SQL, the row shapes and the
 * domain refusals for opening a draft and reading a Section's day.
 *
 * This file requires no other Module. The Section, the shift instance and the
 * author's Account are other Modules' rows, read here by ordinary SQL against
 * the one shared schema (ADR-0006's "code seams, not data seams"); whether the
 * caller may act at the Section is handover-routes.js's question, asked of
 * People's entry point before anything here is called.
 *
 * What this slice does not do yet, each on its own later ticket: write lines,
 * submit (and so compute the snapshot), acknowledge, amend. A draft opened here
 * therefore always reads back with three empty line lists and no snapshot.
 */

const { getPool } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// The Org Unit level a Shift handover is recorded at (CONTEXT.md's Section).
const SECTION_UNIT_TYPE = 'section';

const HANDOVER_COLUMNS = `
  h.id, h.handover_no, h.site_id, h.org_unit_id, h.shift_instance_id,
  to_char(h.production_date, 'YYYY-MM-DD') AS production_date,
  h.status, h.version, h.supersedes_id, h.superseded_at,
  h.submitted_at, h.submitted_by_account_id, author.display_name AS author_display_name,
  h.acknowledged_at, h.acknowledged_by_account_id, h.acknowledgement_note,
  h.late, h.joint_walk_done, h.critical_items, h.deviation_reason, h.change_points_none,
  h.oee, h.availability, h.performance, h.quality,
  h.planned_production_minutes, h.run_minutes, h.unplanned_downtime_minutes,
  h.top_loss_reason_id, h.top_loss_minutes,
  h.unclassified_downtime_minutes, h.unclassified_stop_count,
  h.good_quantity, h.reject_quantity, h.rework_quantity, h.planned_quantity,
  h.performance_suspect, h.open_stop_count, h.open_quality_issue_count, h.safety_event_count,
  h.created_at, h.updated_at
`;

// The author is named only once the handover is submitted: a draft has an
// editor, not an author, and anyone with the Section's edit Grant may be it.
const HANDOVER_FROM = `
  shift_handovers h
  LEFT JOIN app_users author
         ON author.id = h.submitted_by_account_id AND h.submitted_at IS NOT NULL
`;

function toNumber(value) {
  return value === null || value === undefined ? null : Number(value);
}

function toHandover(row) {
  return {
    id: row.id,
    handoverNo: row.handover_no,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    shiftInstanceId: row.shift_instance_id,
    productionDate: row.production_date,
    status: row.status,
    version: row.version,
    supersedesId: row.supersedes_id,
    supersededAt: row.superseded_at,
    submittedAt: row.submitted_at,
    submittedByAccountId: row.submitted_by_account_id,
    authorDisplayName: row.author_display_name ?? null,
    acknowledgedAt: row.acknowledged_at,
    acknowledgedByAccountId: row.acknowledged_by_account_id,
    acknowledgementNote: row.acknowledgement_note,
    late: row.late,
    jointWalkDone: row.joint_walk_done,
    criticalItems: row.critical_items,
    deviationReason: row.deviation_reason,
    changePointsNone: row.change_points_none,
    // Written once at submit and never recomputed (ADR-0054); every field is
    // null on a draft.
    snapshot: {
      oee: toNumber(row.oee),
      availability: toNumber(row.availability),
      performance: toNumber(row.performance),
      quality: toNumber(row.quality),
      plannedProductionMinutes: toNumber(row.planned_production_minutes),
      runMinutes: toNumber(row.run_minutes),
      unplannedDowntimeMinutes: toNumber(row.unplanned_downtime_minutes),
      topLossReasonId: row.top_loss_reason_id,
      topLossMinutes: toNumber(row.top_loss_minutes),
      unclassifiedDowntimeMinutes: toNumber(row.unclassified_downtime_minutes),
      unclassifiedStopCount: row.unclassified_stop_count,
      goodQuantity: toNumber(row.good_quantity),
      rejectQuantity: toNumber(row.reject_quantity),
      reworkQuantity: toNumber(row.rework_quantity),
      plannedQuantity: toNumber(row.planned_quantity),
      performanceSuspect: row.performance_suspect,
      openStopCount: row.open_stop_count,
      openQualityIssueCount: row.open_quality_issue_count,
      safetyEventCount: row.safety_event_count
    },
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function toShiftInstance(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    productionDate: row.production_date,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.status
  };
}

const SHIFT_INSTANCE_COLUMNS = `
  si.id, si.site_id, si.org_unit_id,
  to_char(si.production_date, 'YYYY-MM-DD') AS production_date,
  si.starts_at, si.ends_at, si.status
`;

// Any Org Unit, whatever its level — the route needs to tell "no such Org
// Unit" (404) apart from "not a Section" (400), so the level is not filtered
// here.
async function findOrgUnit(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT id, site_id, code, name, unit_type FROM org_units WHERE id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  const row = rows[0];
  return { id: row.id, siteId: row.site_id, code: row.code, name: row.name, unitType: row.unit_type };
}

async function findShiftInstance(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SHIFT_INSTANCE_COLUMNS} FROM shift_instances si WHERE si.id = $1`,
    [id]
  );
  return rows[0] ? toShiftInstance(rows[0]) : null;
}

// The handover's own row, without its lines — enough for a route to ask
// whether the caller may see it.
async function findHandover(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${HANDOVER_COLUMNS} FROM ${HANDOVER_FROM} WHERE h.id = $1`,
    [id]
  );
  return rows[0] ? toHandover(rows[0]) : null;
}

function requireSection(orgUnit) {
  if (orgUnit.unitType !== SECTION_UNIT_TYPE) {
    throw httpError(
      400,
      `A shift handover is recorded at a section; this Org Unit is a ${orgUnit.unitType}`,
      'NOT_A_SECTION'
    );
  }
}

// Opening a draft. The caller has already resolved both records and asked
// People whether the Account may act at the Section; what is checked here is
// what the two records say about each other. The live-pair index is the final
// word on "one per Section per shift instance" — a second open racing this one
// loses at the database rather than at a read that could be stale.
const HANDOVER_EXISTS_CONSTRAINTS = ['shift_handovers_live_unique', 'shift_handovers_version_unique'];

async function openHandover({ section, shiftInstance }) {
  requireSection(section);
  if (shiftInstance.orgUnitId !== section.id) {
    throw httpError(
      400,
      'That shift instance belongs to another Org Unit, not this section',
      'SHIFT_INSTANCE_NOT_IN_SECTION'
    );
  }

  let id;
  try {
    const { rows } = await getPool().query(
      `INSERT INTO shift_handovers (site_id, org_unit_id, shift_instance_id, production_date)
       SELECT si.site_id, $1, si.id, si.production_date
         FROM shift_instances si
        WHERE si.id = $2
       RETURNING id`,
      [section.id, shiftInstance.id]
    );
    id = rows[0].id;
  } catch (error) {
    // A duplicate open trips whichever of the two pair indexes Postgres checks
    // first — the live one or version 1's — and both mean the same thing here.
    if (error.code === '23505' && HANDOVER_EXISTS_CONSTRAINTS.includes(error.constraint)) {
      throw httpError(
        409,
        'This section already has a handover for that shift instance',
        'HANDOVER_EXISTS'
      );
    }
    throw error;
  }

  return getHandoverDetail(id);
}

// One handover as the detail Screen reads it: the record, its Section and
// shift instance, and its three line lists (empty until the slice that writes
// them).
async function getHandoverDetail(id) {
  const handover = await findHandover(id);
  if (!handover) throw notFound('Shift handover');

  const [{ rows: [section] }, shiftInstance] = await Promise.all([
    getPool().query('SELECT id, code, name FROM org_units WHERE id = $1', [handover.orgUnitId]),
    findShiftInstance(handover.shiftInstanceId)
  ]);

  return {
    ...handover,
    section: { id: section.id, code: section.code, name: section.name },
    shiftInstance: {
      id: shiftInstance.id,
      productionDate: shiftInstance.productionDate,
      startsAt: shiftInstance.startsAt,
      endsAt: shiftInstance.endsAt,
      status: shiftInstance.status
    },
    machineLines: [],
    changePoints: [],
    actions: []
  };
}

// A Section's production day: every shift instance of that day, earliest
// first, each beside its live handover or `null`. The absence is reported, not
// filled (ADR-0054's "derived, never a fake row"). Without a date, the day is
// the Site's own calendar day now, read through the baseline's `plant_date`.
async function getSectionDay(section, date) {
  requireSection(section);

  let productionDate = date;
  if (productionDate === null) {
    const { rows } = await getPool().query(
      `SELECT to_char(plant_date($1, now()), 'YYYY-MM-DD') AS today`,
      [section.id]
    );
    productionDate = rows[0].today;
  }

  const { rows: shiftRows } = await getPool().query(
    `SELECT ${SHIFT_INSTANCE_COLUMNS}
       FROM shift_instances si
      WHERE si.org_unit_id = $1 AND si.production_date = $2::date
      ORDER BY si.starts_at, si.id`,
    [section.id, productionDate]
  );

  const { rows: handoverRows } = await getPool().query(
    `SELECT ${HANDOVER_COLUMNS}
       FROM ${HANDOVER_FROM}
      WHERE h.org_unit_id = $1
        AND h.superseded_at IS NULL
        AND h.shift_instance_id = ANY($2::bigint[])`,
    [section.id, shiftRows.map((row) => row.id)]
  );
  const liveByShift = new Map(handoverRows.map((row) => [row.shift_instance_id, toHandover(row)]));

  return {
    section: { id: section.id, code: section.code, name: section.name },
    productionDate,
    shifts: shiftRows.map((row) => ({
      shiftInstanceId: row.id,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      status: row.status,
      handover: liveByShift.get(row.id) ?? null
    }))
  };
}

module.exports = {
  findOrgUnit,
  findShiftInstance,
  findHandover,
  openHandover,
  getHandoverDetail,
  getSectionDay
};
