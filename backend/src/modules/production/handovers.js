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
 * Submit (issue #334) seals a draft and writes its snapshot once; see
 * submitHandover below. Machine status lines (issue #335) are written to a
 * draft one Asset at a time and checked for completeness at submit. What is
 * still not done, each on its own later ticket: change points, actions,
 * acknowledge, amend. A handover therefore reads back with its machine lines
 * and two empty line lists.
 */

const { getPool, withActor } = require('../../platform/db');
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

// Why a sealed snapshot holds a null where a reader might expect a number. It
// reads the stored columns only — it labels the nulls submit wrote, it does not
// recompute anything — and each null has exactly one cause, so the label is
// fixed by the record. A draft has no snapshot and so no gaps.
const MINUTE_FIELDS = ['plannedProductionMinutes', 'runMinutes', 'unplannedDowntimeMinutes'];
const COUNT_FIELDS = ['goodQuantity', 'rejectQuantity', 'reworkQuantity', 'performance', 'quality'];

function toSnapshotGaps(row) {
  if (row.submitted_at === null || row.submitted_at === undefined) return [];
  const gaps = [];
  const add = (fields, reason) => {
    for (const field of fields) gaps.push({ field, reason });
  };
  if (row.run_minutes === null) {
    add([...MINUTE_FIELDS, 'availability', 'performance', 'oee'], 'no assets in the section');
  } else {
    if (Number(row.planned_production_minutes) === 0) add(['availability', 'oee'], 'no planned production minutes');
    if (Number(row.run_minutes) === 0) add(['performance', 'oee'], 'no run minutes');
  }
  if (row.good_quantity === null) {
    add([...COUNT_FIELDS, 'oee'], 'no production counts');
  } else if (row.quality === null) {
    add(['quality', 'oee'], 'no counted quantity');
  }
  return gaps;
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
    snapshotGaps: toSnapshotGaps(row),
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

// A Machine status line's state and abnormality type: the CHECK constraints on
// `shift_handover_machine_lines`, mirrored so a bad value is a 400 naming the
// set rather than a raw constraint violation. The seven abnormality types are
// TPM's (docs/research/shift-handover.md §2).
const MACHINE_STATES = [
  'running', 'running_manual', 'idle', 'down', 'maintenance', 'cleaning', 'changeover', 'isolated'
];
const NORMAL_RUNNING_STATES = ['running', 'running_manual'];
const ABNORMALITY_TYPES = [
  'minor_flaw', 'unfulfilled_basic_condition', 'inaccessible_place', 'contamination_source',
  'quality_defect_source', 'unnecessary_item', 'unsafe_place'
];

const MACHINE_LINE_COLUMNS = `
  ml.id, ml.asset_id, a.code AS asset_code, a.name AS asset_name,
  a.org_unit_id AS asset_org_unit_id, au.name AS asset_org_unit_name,
  ml.state, ml.abnormality_type, ml.note,
  ml.downtime_event_id, ml.quality_issue_id, ml.work_order_id,
  ml.watch_note, ml.walked, ml.created_at, ml.updated_at
`;

function toMachineLine(row) {
  return {
    id: row.id,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.asset_org_unit_id,
    orgUnitName: row.asset_org_unit_name,
    state: row.state,
    abnormalityType: row.abnormality_type,
    note: row.note,
    downtimeEventId: row.downtime_event_id,
    qualityIssueId: row.quality_issue_id,
    workOrderId: row.work_order_id,
    watchNote: row.watch_note,
    walked: row.walked,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
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

// The snapshot submit writes, as one statement over the shift instance ($2)
// and the Section ($3). Each CTE is one block of the paper form's numbers.
//
// `oee_sum` is the roll-up, not an average of ratios: minutes and quantities
// are summed over the Section's `v_shift_oee` rows first and the ratios taken
// once, with a zero denominator leaving that factor (and so OEE) NULL.
//
// `counted` asks `production_counts` directly whether the shift counted
// anything on the Section's assets. `v_shift_oee` reports a shift with no
// counts as 0 good of 0 — and 0 theoretical minutes — which is "nobody
// counted", not "made nothing", so without counts the quantities, performance,
// quality and OEE are stored NULL.
//
// `stops` attributes downtime exactly as `v_shift_downtime` does — any event
// on an Org Unit in the Section's subtree whose span overlaps the shift
// window, clipped to it, an open stop running to `ends_at` — so the top loss
// and the unclassified minutes are cut from the same minutes OEE was.
// `downtime_events.shift_instance_id` is not used: it names the shift a stop
// started in, and a stop carried over from the previous shift is still this
// shift's loss and this shift's open stop.
const SNAPSHOT_SQL = `
  WITH si AS (
    SELECT si.id, si.starts_at, si.ends_at, section.path
      FROM shift_instances si, org_units section
     WHERE si.id = $2 AND section.id = $3
  ),
  oee_sum AS (
    SELECT sum(v.planned_production_minutes) AS planned_production_minutes,
           sum(v.run_minutes) AS run_minutes,
           sum(v.unplanned_downtime_minutes) AS unplanned_downtime_minutes,
           sum(v.theoretical_minutes) AS theoretical_minutes,
           sum(v.good_quantity) AS good_quantity,
           sum(v.reject_quantity) AS reject_quantity,
           sum(v.rework_quantity) AS rework_quantity,
           sum(v.total_quantity) AS total_quantity
      FROM si
      JOIN v_shift_oee v ON v.shift_instance_id = si.id
      JOIN assets a ON a.id = v.asset_id
      JOIN org_units au ON au.id = a.org_unit_id AND au.path <@ si.path
  ),
  counted AS (
    SELECT EXISTS (
      SELECT 1
        FROM si
        JOIN production_counts pc ON pc.shift_instance_id = si.id
        JOIN assets a ON a.id = pc.asset_id
        JOIN org_units au ON au.id = a.org_unit_id AND au.path <@ si.path
    ) AS has_counts
  ),
  ratios AS (
    SELECT o.*, c.has_counts AS counted,
           CASE WHEN o.planned_production_minutes > 0
                THEN o.run_minutes / o.planned_production_minutes END AS availability,
           CASE WHEN c.has_counts AND o.run_minutes > 0
                THEN o.theoretical_minutes / o.run_minutes END AS performance,
           CASE WHEN c.has_counts AND o.total_quantity > 0
                THEN o.good_quantity / o.total_quantity END AS quality
      FROM oee_sum o, counted c
  ),
  stops AS (
    SELECT de.downtime_reason_id, de.ended_at,
           EXTRACT(epoch FROM LEAST(COALESCE(de.ended_at, si.ends_at), si.ends_at)
                              - GREATEST(de.started_at, si.starts_at)) / 60.0 AS minutes
      FROM si
      JOIN downtime_events de
        ON tstzrange(de.started_at, COALESCE(de.ended_at, now()), '[)')
           && tstzrange(si.starts_at, si.ends_at, '[)')
      JOIN org_units deu ON deu.id = de.org_unit_id AND deu.path <@ si.path
  ),
  -- The top loss is the classified reason with the most minutes; unclassified
  -- minutes have their own two columns. On a tie the earlier reason id wins:
  -- an arbitrary but stable answer, because a "top loss" that changed between
  -- two reads of the same rows would be worse than one that is merely
  -- arbitrary.
  top_loss AS (
    SELECT downtime_reason_id, sum(minutes) AS minutes
      FROM stops
     WHERE downtime_reason_id IS NOT NULL
     GROUP BY downtime_reason_id
     ORDER BY sum(minutes) DESC, downtime_reason_id
     LIMIT 1
  )
  SELECT r.planned_production_minutes,
         r.run_minutes,
         r.unplanned_downtime_minutes,
         CASE WHEN r.counted THEN r.good_quantity END AS good_quantity,
         CASE WHEN r.counted THEN r.reject_quantity END AS reject_quantity,
         CASE WHEN r.counted THEN r.rework_quantity END AS rework_quantity,
         r.availability, r.performance, r.quality,
         r.availability * r.performance * r.quality AS oee,
         -- The view's own rule, over the summed minutes.
         r.run_minutes > 0 AND r.theoretical_minutes > r.run_minutes AS performance_suspect,
         (SELECT sum(pr.planned_quantity) FROM production_runs pr WHERE pr.shift_instance_id = $2)
           AS planned_quantity,
         (SELECT downtime_reason_id FROM top_loss) AS top_loss_reason_id,
         (SELECT minutes FROM top_loss) AS top_loss_minutes,
         (SELECT COALESCE(sum(minutes), 0) FROM stops WHERE downtime_reason_id IS NULL)
           AS unclassified_downtime_minutes,
         (SELECT count(*) FROM stops WHERE downtime_reason_id IS NULL) AS unclassified_stop_count,
         (SELECT count(*) FROM stops WHERE ended_at IS NULL) AS open_stop_count,
         (SELECT count(*) FROM quality_issues qi
           WHERE qi.shift_instance_id = $2 AND qi.status IN ('open', 'contained'))
           AS open_quality_issue_count,
         (SELECT count(*) FROM safety_incidents sinc WHERE sinc.shift_instance_id = $2)
           + (SELECT count(*) FROM safety_observations so WHERE so.shift_instance_id = $2)
           AS safety_event_count,
         now() > (SELECT ends_at FROM si) + interval '30 minutes' AS late
    FROM ratios r
`;

// The handover's row, locked for the rest of the transaction, refused unless
// it is still a draft. Every write to a draft and its lines takes this lock
// first, so a line written while a submit is running waits for the submit,
// then reads 'submitted' and is refused — a sealed handover never gains a line.
async function lockDraft(client, id) {
  const { rows: [handover] } = await client.query(
    'SELECT id, status, org_unit_id, shift_instance_id FROM shift_handovers WHERE id = $1 FOR UPDATE',
    [id]
  );
  if (!handover) throw notFound('Shift handover');
  if (handover.status !== 'draft') {
    throw httpError(409, `This handover is ${handover.status}, not a draft`, 'HANDOVER_NOT_DRAFT');
  }
  return handover;
}

// The Section's active Assets: every Asset whose Org Unit sits in the
// Section's subtree ($1), by `org_units.path`.
const SECTION_ASSETS_SQL = `
  SELECT a.id, a.code, a.name, a.org_unit_id, au.name AS org_unit_name
    FROM assets a
    JOIN org_units au ON au.id = a.org_unit_id
    JOIN org_units section ON section.id = $1
   WHERE a.is_active AND au.path <@ section.path
`;

// Submit's completeness rules (issue #335, ADR-0054): every active Asset in
// the Section has a Machine status line, and every line that is not normal
// running carries a note and a reference to the record that explains it. A
// draft is filled progressively, so the reference is asked for here and not
// when the line is written. The refusal lists everything missing at once, so
// one round trip tells the Team Leader the whole of what is left.
async function requireComplete(client, handover) {
  const { rows: missingAssets } = await client.query(
    `SELECT s.id, s.code, s.name
       FROM (${SECTION_ASSETS_SQL}) s
      WHERE NOT EXISTS (
              SELECT 1 FROM shift_handover_machine_lines ml
               WHERE ml.handover_id = $2 AND ml.asset_id = s.id)
      ORDER BY s.code, s.id`,
    [handover.org_unit_id, handover.id]
  );

  const { rows: lineRows } = await client.query(
    `SELECT a.id, a.code, a.name,
            ml.note IS NULL OR btrim(ml.note) = '' AS missing_note,
            ml.downtime_event_id IS NULL AND ml.quality_issue_id IS NULL
              AND ml.work_order_id IS NULL AS missing_reference
       FROM shift_handover_machine_lines ml
       JOIN assets a ON a.id = ml.asset_id
      WHERE ml.handover_id = $1
        AND ml.state <> ALL($2::text[])
      ORDER BY a.code, a.id`,
    [handover.id, NORMAL_RUNNING_STATES]
  );
  const incompleteLines = lineRows
    .filter((row) => row.missing_note || row.missing_reference)
    .map((row) => ({
      id: row.id,
      code: row.code,
      name: row.name,
      missing: [
        ...(row.missing_note ? ['note'] : []),
        ...(row.missing_reference ? ['reference'] : [])
      ]
    }));

  if (missingAssets.length === 0 && incompleteLines.length === 0) return;

  const parts = [];
  if (missingAssets.length > 0) {
    parts.push(`no machine status line for ${missingAssets.map((asset) => asset.code).join(', ')}`);
  }
  if (incompleteLines.length > 0) {
    parts.push(
      incompleteLines.map((line) => `${line.code} is missing its ${line.missing.join(' and ')}`).join('; ')
    );
  }
  const error = httpError(409, `This handover cannot be submitted: ${parts.join('; ')}`, 'INCOMPLETE_HANDOVER');
  error.details = { missingAssets, incompleteLines };
  throw error;
}

// Submitting a draft: the snapshot is computed once and written with the
// author, the time and the late flag in the same UPDATE, inside a transaction
// that holds the handover's row lock from the status check to the write — so
// a second submit racing this one waits, then reads 'submitted' and is
// refused, and a submit that fails anywhere leaves the draft exactly as it
// was. Nothing recomputes these columns afterwards (ADR-0054): not a trigger,
// not a read, not a refresh. `now()` is the database's clock and is fixed for
// the transaction, so `submitted_at` and `late` agree with each other.
//
// Late is recorded, never refused: a handover written 40 minutes after the
// shift is still the handover.
async function submitHandover({ id, account }) {
  await withActor(account.id, async (client) => {
    const handover = await lockDraft(client, id);
    await requireComplete(client, handover);

    const { rows: [shiftInstance] } = await client.query(
      'SELECT id FROM shift_instances WHERE id = $1',
      [handover.shift_instance_id]
    );
    if (!shiftInstance) throw notFound('Shift instance');

    await client.query(
      `UPDATE shift_handovers h
          SET status = 'submitted',
              submitted_at = now(),
              submitted_by_account_id = $4,
              late = s.late,
              oee = s.oee,
              availability = s.availability,
              performance = s.performance,
              quality = s.quality,
              planned_production_minutes = s.planned_production_minutes,
              run_minutes = s.run_minutes,
              unplanned_downtime_minutes = s.unplanned_downtime_minutes,
              top_loss_reason_id = s.top_loss_reason_id,
              top_loss_minutes = s.top_loss_minutes,
              unclassified_downtime_minutes = s.unclassified_downtime_minutes,
              unclassified_stop_count = s.unclassified_stop_count,
              good_quantity = s.good_quantity,
              reject_quantity = s.reject_quantity,
              rework_quantity = s.rework_quantity,
              planned_quantity = s.planned_quantity,
              performance_suspect = s.performance_suspect,
              open_stop_count = s.open_stop_count,
              open_quality_issue_count = s.open_quality_issue_count,
              safety_event_count = s.safety_event_count
         FROM (${SNAPSHOT_SQL}) s
        WHERE h.id = $1`,
      [handover.id, handover.shift_instance_id, handover.org_unit_id, account.id]
    );
  });

  return getHandoverDetail(id);
}

// A blank note is no note: stored NULL, so "is there a note" has one answer.
function blankToNull(value) {
  if (value === undefined || value === null) return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

// A referenced record must explain *this* machine on *this* shift: a downtime
// event of the line's Asset in the handover's shift instance, a quality issue
// raised against the line's Asset (one with no Asset explains no machine), a
// Work order that exists. Linked by id, never copied (ADR-0054).
async function requireReferences(client, { handover, asset, line }) {
  const outside = (message) => httpError(400, message, 'REFERENCE_OUTSIDE_HANDOVER');

  if (line.downtimeEventId !== null) {
    const { rows: [event] } = await client.query(
      'SELECT asset_id, shift_instance_id FROM downtime_events WHERE id = $1',
      [line.downtimeEventId]
    );
    if (!event) throw notFound('Downtime event');
    if (event.asset_id !== asset.id) {
      throw outside(`That downtime event is on another Asset, not ${asset.code}`);
    }
    if (event.shift_instance_id !== handover.shift_instance_id) {
      throw outside('That downtime event belongs to another shift instance, not this handover\'s');
    }
  }

  if (line.qualityIssueId !== null) {
    const { rows: [issue] } = await client.query(
      'SELECT asset_id FROM quality_issues WHERE id = $1',
      [line.qualityIssueId]
    );
    if (!issue) throw notFound('Quality issue');
    if (issue.asset_id === null) {
      throw outside(`That quality issue names no Asset, so it cannot explain ${asset.code}`);
    }
    if (issue.asset_id !== asset.id) {
      throw outside(`That quality issue is on another Asset, not ${asset.code}`);
    }
  }

  if (line.workOrderId !== null) {
    const { rows: [workOrder] } = await client.query(
      'SELECT id FROM work_orders WHERE id = $1',
      [line.workOrderId]
    );
    if (!workOrder) throw notFound('Work order');
  }
}

// Writing one Asset's Machine status line on a draft: the whole line, replaced
// (a field left out is cleared). The route has checked the body's shape and
// the caller's scope; what is checked here is the line against the handover.
// A note is required the moment the state is not normal running — the only
// person who knows why is the one writing the line — but the reference is
// asked for at submit, because the downtime event or Work order may not have
// been raised yet when the line is first filled in.
async function putMachineLine({ id, assetId, line, account }) {
  await withActor(account.id, async (client) => {
    const handover = await lockDraft(client, id);

    if (!MACHINE_STATES.includes(line.state)) {
      throw httpError(400, `state must be one of: ${MACHINE_STATES.join(', ')}`);
    }
    if (line.abnormalityType !== null && !ABNORMALITY_TYPES.includes(line.abnormalityType)) {
      throw httpError(400, `abnormalityType must be one of: ${ABNORMALITY_TYPES.join(', ')}`);
    }

    const { rows: [asset] } = await client.query(
      `SELECT a.id, a.code, au.path <@ section.path AS in_section
         FROM assets a
         JOIN org_units au ON au.id = a.org_unit_id
         JOIN org_units section ON section.id = $2
        WHERE a.id = $1`,
      [assetId, handover.org_unit_id]
    );
    if (!asset) throw notFound('Asset');
    if (!asset.in_section) {
      throw httpError(400, `Asset ${asset.code} is not in this handover's section`, 'ASSET_NOT_IN_SECTION');
    }

    const note = blankToNull(line.note);
    if (note === null && !NORMAL_RUNNING_STATES.includes(line.state)) {
      throw httpError(400, `${asset.code} is ${line.state}: a note saying why is required`, 'NOTE_REQUIRED');
    }
    if (note === null && line.abnormalityType !== null) {
      throw httpError(
        400,
        `${asset.code} has an abnormality (${line.abnormalityType}): a note describing it is required`,
        'NOTE_REQUIRED'
      );
    }

    await requireReferences(client, { handover, asset, line });

    await client.query(
      `INSERT INTO shift_handover_machine_lines
         (handover_id, asset_id, state, abnormality_type, note,
          downtime_event_id, quality_issue_id, work_order_id, watch_note, walked)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (handover_id, asset_id) DO UPDATE
         SET state = EXCLUDED.state,
             abnormality_type = EXCLUDED.abnormality_type,
             note = EXCLUDED.note,
             downtime_event_id = EXCLUDED.downtime_event_id,
             quality_issue_id = EXCLUDED.quality_issue_id,
             work_order_id = EXCLUDED.work_order_id,
             watch_note = EXCLUDED.watch_note,
             walked = EXCLUDED.walked`,
      [handover.id, asset.id, line.state, line.abnormalityType, note,
        line.downtimeEventId, line.qualityIssueId, line.workOrderId,
        blankToNull(line.watchNote), line.walked]
    );
  });

  return getHandoverDetail(id);
}

// Removing one Asset's line from a draft; 404 when that Asset has none.
async function deleteMachineLine({ id, assetId, account }) {
  await withActor(account.id, async (client) => {
    const handover = await lockDraft(client, id);
    const { rowCount } = await client.query(
      'DELETE FROM shift_handover_machine_lines WHERE handover_id = $1 AND asset_id = $2',
      [handover.id, assetId]
    );
    if (rowCount === 0) throw notFound('Machine status line');
  });

  return getHandoverDetail(id);
}

// A Section's active Assets, the machines a handover owes a line for.
async function listSectionAssets(section) {
  requireSection(section);
  const { rows } = await getPool().query(`${SECTION_ASSETS_SQL} ORDER BY a.code, a.id`, [section.id]);
  return {
    section: { id: section.id, code: section.code, name: section.name },
    assets: rows.map((row) => ({
      id: row.id,
      code: row.code,
      name: row.name,
      orgUnitId: row.org_unit_id,
      orgUnitName: row.org_unit_name
    }))
  };
}

// One handover as the detail Screen reads it: the record, its Section and
// shift instance, and its three line lists — machine lines ordered by Asset
// code, change points and actions empty until the slices that write them.
async function getHandoverDetail(id) {
  const handover = await findHandover(id);
  if (!handover) throw notFound('Shift handover');

  const [{ rows: [section] }, shiftInstance, { rows: lineRows }] = await Promise.all([
    getPool().query('SELECT id, code, name FROM org_units WHERE id = $1', [handover.orgUnitId]),
    findShiftInstance(handover.shiftInstanceId),
    getPool().query(
      `SELECT ${MACHINE_LINE_COLUMNS}
         FROM shift_handover_machine_lines ml
         JOIN assets a ON a.id = ml.asset_id
         JOIN org_units au ON au.id = a.org_unit_id
        WHERE ml.handover_id = $1
        ORDER BY a.code, a.id`,
      [handover.id]
    )
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
    machineLines: lineRows.map(toMachineLine),
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
  submitHandover,
  putMachineLine,
  deleteMachineLine,
  getHandoverDetail,
  getSectionDay,
  listSectionAssets
};
