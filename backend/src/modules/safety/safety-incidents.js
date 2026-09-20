/*
 * Safety incidents (issue #226) — the Safety Module's first record of real
 * work. A Safety incident is what somebody writes down when something went
 * wrong: when it occurred, what kind of event it was, where it sits on the
 * severity ladder, a description, the Asset involved if there is one, and the
 * immediate action taken. CONTEXT.md's own entry is the definition this file
 * implements, and closest prior art is quality/nonconformances.js — a
 * Non-conformance is the same shape of record (recorded at an Org Unit,
 * Site-scoped number, production-day filing, a filtered register, a detail),
 * and this file follows it closely rather than inventing a second shape.
 *
 * Four things about this file are worth reading before changing it.
 *
 * **The number comes from the Platform's own document numbering.**
 * `next_document_number('SI', siteCode, year)` — the same function a Work
 * order, a Request, a PM schedule, an Action and a Non-conformance receive
 * their numbers from — gives a Site-scoped, year-stamped, zero-padded
 * sequence: SI-HCM-2026-00001. The baseline's `safety_incidents.incident_no`
 * column carries a DEFAULT of its own (a plain, unscoped
 * `safety_incidents_no_seq`), which this file deliberately does not use —
 * `nonconformances.js`'s own header explains why an unscoped sequence is the
 * wrong number in a database that can hold more than one plant. The write
 * names `incident_no` explicitly rather than letting the DEFAULT fire.
 *
 * **Every incident names its reporter, and there is no anonymous path.**
 * ADR-0036 decided this the opposite way from the baseline's own comment
 * above `safety_incidents`, and migration 1800800000000 turned the decision
 * into a CHECK (`safety_incidents_not_anonymous`) rather than leaving it
 * advisory. This slice's one door is a signed-in Account —
 * `recordIncident`'s `actor` is `{ accountId }`, the shape
 * `nonconformances.js` gives its own two-door `actor` object, kept here even
 * though the floor device (issue #227, the shared terminal's own Employee
 * identification) is not built yet, so that ticket adds a second actor shape
 * rather than reshaping this one. `is_anonymous` is never set from a caller;
 * the column's own default (`FALSE`) is left to fire.
 *
 * **The production day and the shift are the database's answer, not this
 * file's.** `safety_incidents` has carried the baseline's
 * `fill_shift_instance` trigger since the schema was written (`SELECT
 * attach_shift_instance('safety_incidents', 'occurred_at')`), so an insert
 * that supplies only `org_unit_id` and `occurred_at` lands in the shift
 * instance that covers that moment, from which the production day (ADR-0017)
 * and the shift's own name are read back. This file resolves neither.
 *
 * **Recordability is the database's own derived fact, and the ladder's
 * consistency is checked here first.** `is_recordable` is `GENERATED ALWAYS`
 * from `severity_level` and is only ever read back, never written. But a
 * caller who gets the ladder wrong — lost-time days on a rung that never lost
 * time, days at all on the no-injury rung — deserves a 400 naming the field,
 * not the baseline's own CHECK violation (`safety_incidents_near_miss_no_injury`,
 * `safety_incidents_lost_time_consistent`) surfacing as a raw constraint
 * error; `requireLadderConsistency` below is that check, done before the
 * INSERT, with the database's CHECKs left in place as the backstop for a race
 * this file's own check cannot see.
 *
 * No injury type and no body part are accepted here — issue #224 is the
 * ticket that adds that classification, and its own read restriction. This
 * file's near-miss rung (`near_miss`, spelled that way in the schema, meaning
 * **no injury** — CONTEXT.md's own Severity level entry) is validated only
 * against the two day counts it can see: `lostTimeDays` and `restrictedDays`.
 *
 * Mirrors nonconformances.js: no HTTP, no caller awareness. Unlike products.js
 * and defect-codes.js, this file's records ARE placed in the Org Unit tree, so
 * its queries join `org_units` (and, for the optional Asset, `assets` — a
 * cross-Module read done as an ordinary SQL join, which ADR-0006's "code
 * seams, not data seams" rule allows explicitly — and for the optional
 * Employee involved, `employees`, the same kind of read: the Employee
 * directory is platform-wide and Grant-free by ADR-0009, so naming one is an
 * existence check rather than another Module's judgment). Scope is not this
 * file's business: safety-incident-routes.js asks People before calling
 * anything here.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

function requireMembership(field, value, allowed) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw httpError(400, `${field} must be one of ${allowed.join(', ')}`);
  }
}

// The value sets the baseline's own CHECK constraints enforce
// (`safety_incidents_incident_type_check`, `safety_incidents_severity_level_check`,
// `safety_incidents_status_check`). Repeated here so a caller gets a sentence
// naming the field rather than a raw constraint violation, the same reasoning
// nonconformances.js gives its own repeated sets.
const INCIDENT_TYPES = [
  'injury',
  'near_miss',
  'property_damage',
  'environmental',
  'fire',
  'ergonomic',
  'security'
];

// The severity ladder, in ladder order — no injury through fatality. Order
// matters here: the frontend's severity picker renders this same order rather
// than alphabetically (the binding design comment on #223), and
// `SEVERITY_RANK` below is built from this array's own position rather than a
// second, hand-kept table that could drift from it.
const SEVERITY_LEVELS = [
  'near_miss',
  'first_aid',
  'medical_treatment',
  'restricted_work',
  'lost_time',
  'fatality'
];

// Recordable and up — mirrors the baseline's own GENERATED expression for
// `is_recordable` exactly (`severity_level IN ('medical_treatment',
// 'restricted_work', 'lost_time', 'fatality')`). Used only to explain a 400 in
// a caller's own words; the database's generated column is what a caller
// actually reads back, never this list.
const RECORDABLE_LEVELS = ['medical_treatment', 'restricted_work', 'lost_time', 'fatality'];

// The severities that may carry lost-time days — the baseline's own
// `safety_incidents_lost_time_consistent` CHECK, repeated here for the same
// reason as the sets above.
const LOST_TIME_LEVELS = ['lost_time', 'fatality'];

const SEVERITY_RANK = Object.fromEntries(SEVERITY_LEVELS.map((level, index) => [level, index]));

function severityRank(level) {
  return SEVERITY_RANK[level] ?? -1;
}

// The register's own cap, one row past which means "there is more" rather
// than a silently truncated Site — the same shape nonconformances.js's own
// list keeps (ADR-0026).
const SAFETY_INCIDENT_LIST_LIMIT = 200;

// A required, non-empty string. Trimmed on the way in, so a field sent as
// whitespace is refused rather than silently accepted.
function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
  return value.trim();
}

// An optional free-text field: trimmed where it carries something, null where
// it does not — the same rule nonconformances.js follows for its own optional
// text fields.
function optionalText(value) {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

// A count of days: zero or a positive integer, accepted as a number or as a
// numeric string (a form sends text). Anything else — a word, a negative, a
// fraction, NaN, Infinity — is a 400 naming the field. Absent is treated as
// zero, matching the baseline column's own `NOT NULL DEFAULT 0`.
function optionalNonNegativeInteger(field, value) {
  if (value === undefined || value === null || value === '') return 0;
  const number = typeof value === 'string' ? Number(value.trim()) : value;
  if (typeof number !== 'number' || !Number.isFinite(number) || !Number.isInteger(number) || number < 0) {
    throw httpError(400, `${field} must be a whole number of days, or zero`);
  }
  return number;
}

// A required timestamp: parsed, and refused with a 400 naming the field
// rather than reaching Postgres as a malformed literal.
function requireTimestamp(field, value) {
  if (typeof value !== 'string' && !(value instanceof Date)) {
    throw httpError(400, `${field} is required and must be a timestamp`);
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw httpError(400, `${field} must be a valid timestamp`);
  }
  return parsed;
}

// An optional timestamp: null when absent, the same 400 as the required form
// when it is present but unparseable.
function optionalTimestamp(field, value) {
  if (value === undefined || value === null || value === '') return null;
  return requireTimestamp(field, value);
}

/**
 * Ladder consistency, checked before the database sees it (issue #226's own
 * criterion): a caller gets a 400 naming the field, not a constraint
 * violation.
 *
 *   - No lost-time days and no restricted days on the no-injury rung
 *     (`near_miss`) — nobody was hurt, so nothing was lost. No injury type and
 *     no body part either, but those two are never accepted as input in this
 *     slice (issue #224's own scope), so there is nothing to check for them
 *     here: they are always null on the row this file writes.
 *   - Lost-time days only at `lost_time` or `fatality` — the baseline's own
 *     `safety_incidents_lost_time_consistent` CHECK, said as a sentence a
 *     caller can act on.
 *   - `reportedAt` not earlier than `occurredAt` — the baseline's own
 *     `safety_incidents_reported_after_occurred` CHECK, checked the same way.
 *
 * Deliberately asks no question about `incident_type` and `severity_level`
 * together: #223 decision 3 keeps the two independent on purpose (a fire that
 * hurt nobody is type `fire` on the ladder's `near_miss` rung, exactly where a
 * genuine near miss also sits), so no rule here ties them.
 */
function requireLadderConsistency({ severityLevel, lostTimeDays, restrictedDays, occurredAt, reportedAt }) {
  if (severityLevel === 'near_miss') {
    if (lostTimeDays > 0) {
      throw httpError(400, 'lostTimeDays must be 0 on the near_miss rung: nobody was hurt');
    }
    if (restrictedDays > 0) {
      throw httpError(400, 'restrictedDays must be 0 on the near_miss rung: nobody was hurt');
    }
  }

  if (lostTimeDays > 0 && !LOST_TIME_LEVELS.includes(severityLevel)) {
    throw httpError(
      400,
      `lostTimeDays may only be recorded at ${LOST_TIME_LEVELS.join(' or ')} severity`
    );
  }

  if (reportedAt !== null && reportedAt.getTime() < occurredAt.getTime()) {
    throw httpError(400, 'reportedAt cannot be earlier than occurredAt');
  }
}

// `safety_incidents` is read every time through this one projection, so a row
// that was just recorded and a row read back from the register can never
// carry different fields. The joins are all to-one or to-none (the Asset, the
// Employee and the shift instance are all optional), so no row is ever
// multiplied or dropped by them.
const SAFETY_INCIDENT_COLUMNS = `
  si.id, si.incident_no, si.status, si.incident_type, si.severity_level,
  si.is_recordable, si.occurred_at, si.reported_at, si.description,
  si.immediate_action, si.lost_time_days, si.restricted_days,
  si.recorded_by_account_id, au.display_name AS recorded_by_account_name,
  si.reported_by, rep.display_name AS reported_by_name,
  si.investigation_due_at, si.closed_at,
  si.created_at, si.updated_at,
  si.org_unit_id, ou.name AS org_unit_name, ou.path AS org_unit_path,
  ou.site_id, s.code AS site_code, s.name AS site_name,
  si.asset_id, a.code AS asset_code, a.name AS asset_name,
  si.employee_id, e.display_name AS employee_name,
  si.shift_instance_id,
  -- A DATE read as a to_char string, never as a JS Date: a production day is
  -- a day in the Site's own calendar (ADR-0017), and a Date object would be
  -- re-serialised as an instant at the server's midnight and read back a day
  -- out by anyone in another time zone. nonconformances.js reads its own
  -- production day the same way.
  to_char(shi.production_date, 'YYYY-MM-DD') AS production_date,
  shi.starts_at AS shift_starts_at, shi.ends_at AS shift_ends_at,
  sd.code AS shift_code, sd.name AS shift_name`;

const SAFETY_INCIDENT_JOINS = `
  FROM safety_incidents si
  JOIN org_units ou ON ou.id = si.org_unit_id
  JOIN sites s ON s.id = ou.site_id
  LEFT JOIN assets a ON a.id = si.asset_id
  LEFT JOIN employees e ON e.id = si.employee_id
  LEFT JOIN employees rep ON rep.id = si.reported_by
  LEFT JOIN app_users au ON au.id = si.recorded_by_account_id
  LEFT JOIN shift_instances shi ON shi.id = si.shift_instance_id
  LEFT JOIN shift_definitions sd ON sd.id = shi.shift_definition_id`;

function toSafetyIncident(row) {
  return {
    id: row.id,
    incidentNo: row.incident_no,
    status: row.status,
    incidentType: row.incident_type,
    severityLevel: row.severity_level,
    // Derived by the database, never accepted from a caller (issue #226's own
    // criterion) — this is always the GENERATED column's own answer.
    isRecordable: row.is_recordable === true,
    occurredAt: row.occurred_at,
    reportedAt: row.reported_at,
    description: row.description,
    immediateAction: row.immediate_action ?? null,
    lostTimeDays: row.lost_time_days,
    restrictedDays: row.restricted_days,
    recordedByAccountId: row.recorded_by_account_id ?? null,
    recordedByAccountName: row.recorded_by_account_name ?? null,
    reportedBy: row.reported_by ?? null,
    reportedByName: row.reported_by_name ?? null,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    orgUnitPath: row.org_unit_path,
    siteId: row.site_id,
    siteCode: row.site_code,
    siteName: row.site_name,
    assetId: row.asset_id,
    assetCode: row.asset_code ?? null,
    assetName: row.asset_name ?? null,
    employeeId: row.employee_id,
    employeeName: row.employee_name ?? null,
    // The production day and the shift, as the baseline's own trigger filed
    // them (ADR-0017). Both are null for a Site with no shift calendar
    // covering that moment.
    shiftInstanceId: row.shift_instance_id,
    productionDate: row.production_date ?? null,
    shiftCode: row.shift_code ?? null,
    shiftName: row.shift_name ?? null,
    shiftStartsAt: row.shift_starts_at ?? null,
    shiftEndsAt: row.shift_ends_at ?? null,
    investigationDueAt: row.investigation_due_at ?? null,
    closedAt: row.closed_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

/**
 * The Site's Safety incidents, newest first, narrowed by any of the filters
 * issue #226 asks for.
 *
 * Site-wide with no Grant filter, the same rule the Non-conformance log
 * already follows (#55, ADR-0009, ADR-0032): Org Unit scope decides where an
 * Account may *act*, not what it may know about. `orgUnitPath` — resolved by
 * the route from a `?orgUnitId=` and handed here as the ltree path — narrows
 * to one area **and everything beneath it**, the same `<@` walk
 * `nonconformances.js`'s own register does.
 *
 * `from`/`to` are production days, not instants (ADR-0017), for the same
 * reason nonconformances.js's own range is: a row whose Site had no shift
 * instance covering it falls back to its own occurred date rather than being
 * silently excluded from every range.
 */
async function listSafetyIncidents(
  siteId,
  {
    orgUnitPath = null,
    status = null,
    incidentType = null,
    severityLevel = null,
    isRecordable = null,
    from = null,
    to = null,
    limit = SAFETY_INCIDENT_LIST_LIMIT
  } = {}
) {
  const conditions = ['ou.site_id = $1'];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`si.status = $${params.length}`);
  }
  if (incidentType !== null) {
    params.push(incidentType);
    conditions.push(`si.incident_type = $${params.length}`);
  }
  if (severityLevel !== null) {
    params.push(severityLevel);
    conditions.push(`si.severity_level = $${params.length}`);
  }
  if (isRecordable !== null) {
    params.push(isRecordable);
    conditions.push(`si.is_recordable = $${params.length}`);
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`COALESCE(shi.production_date, si.occurred_at::date) >= $${params.length}::date`);
  }
  if (to !== null) {
    params.push(to);
    conditions.push(`COALESCE(shi.production_date, si.occurred_at::date) <= $${params.length}::date`);
  }

  const { rows } = await getPool().query(
    `SELECT ${SAFETY_INCIDENT_COLUMNS}
     ${SAFETY_INCIDENT_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY si.occurred_at DESC, si.id DESC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    incidents: rows.slice(0, limit).map(toSafetyIncident),
    truncated
  };
}

// The null-returning form, mirroring findNonconformance/findAsset: a
// malformed id resolves to null rather than reaching Postgres as a BIGINT
// parameter.
async function findSafetyIncident(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SAFETY_INCIDENT_COLUMNS} ${SAFETY_INCIDENT_JOINS} WHERE si.id = $1`,
    [id]
  );
  return rows[0] ? toSafetyIncident(rows[0]) : null;
}

// The detail read: today the same projection as the list and
// findSafetyIncident, and its own function anyway (mirroring
// getNonconformanceDetail) so a later ticket that adds sub-records —
// classification, corrections, a linked Concern — has one place to add them
// without reshaping the register's own row.
async function getSafetyIncidentDetail(id) {
  return findSafetyIncident(id);
}

// The Asset, if one is named, must sit at the Org Unit the incident is
// recorded at or beneath it — issue #226's own criterion, and the exact rule
// nonconformances.js's resolveAssetAtOrgUnit already enforces for the same
// reason.
async function resolveAssetAtOrgUnit(assetId, orgUnitPath) {
  const { rows } = await getPool().query(
    `SELECT a.id, a.code, a.name, ou.path AS org_unit_path
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE a.id = $1`,
    [assetId]
  );
  if (!rows[0]) throw notFound('Asset');
  if (!rows[0].org_unit_path.startsWith(orgUnitPath)) {
    throw httpError(400, 'the Asset named does not sit at that Org Unit or beneath it');
  }
  return rows[0];
}

// The Employee involved, if one is named. The Employee directory is
// platform-wide and Grant-free (ADR-0009), so this is an existence check
// rather than a scope question — no Org Unit constraint, unlike the Asset
// above.
async function resolveEmployee(employeeId) {
  const { rows } = await getPool().query(
    'SELECT id, display_name FROM employees WHERE id = $1',
    [employeeId]
  );
  if (!rows[0]) throw notFound('Employee');
  return rows[0];
}

// The Site's short code, which the document number quotes. Read off the Org
// Unit's own Site rather than taken from a caller, so a number can never be
// issued against a Site the record does not sit in.
async function findSiteCodeForOrgUnit(orgUnitId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT s.code
       FROM org_units ou
       JOIN sites s ON s.id = ou.site_id
      WHERE ou.id = $1`,
    [orgUnitId]
  );
  return rows[0] ? rows[0].code : null;
}

/**
 * Record a Safety incident (issue #226).
 *
 * `actor` is `{ accountId }` — the one door this slice has. Kept as an object
 * rather than a bare id so a later door (the floor device, issue #227) can add
 * `{ employeeId }` beside it the way `nonconformances.js`'s own actor already
 * does, without reshaping this function's signature.
 *
 * The route has already resolved the Org Unit and answered the scope question
 * (`people.canAct({ …, write: true })`) and parsed the Asset id; everything
 * that is a fact about the record itself is decided here. `is_anonymous` is
 * never set — the column's own `FALSE` default is left to fire, and migration
 * 1800800000000's CHECK is the backstop that makes that the only value the row
 * can ever hold.
 *
 * The number, the shift instance and the audit columns are all the database's
 * own work — `next_document_number` for the first, `fill_shift_instance` for
 * the second, the shared audit trigger for the third — so the INSERT names
 * only what a person actually decided. `status` starts `open`, the baseline
 * column's own default.
 */
async function recordSafetyIncident(input, actor = {}) {
  const body = input ?? {};
  const accountId = actor.accountId ?? null;

  const orgUnitId = parseId(body.orgUnitId);
  if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');

  const assetId = body.assetId === undefined || body.assetId === null
    ? null
    : parseId(body.assetId);
  if (body.assetId !== undefined && body.assetId !== null && assetId === null) {
    throw httpError(400, 'assetId must be a valid Asset id');
  }

  const employeeId = body.employeeId === undefined || body.employeeId === null
    ? null
    : parseId(body.employeeId);
  if (body.employeeId !== undefined && body.employeeId !== null && employeeId === null) {
    throw httpError(400, 'employeeId must be a valid Employee id');
  }

  requireMembership('incidentType', body.incidentType, INCIDENT_TYPES);
  requireMembership('severityLevel', body.severityLevel, SEVERITY_LEVELS);
  const description = requireNonEmptyString('description', body.description);
  const occurredAt = requireTimestamp('occurredAt', body.occurredAt);
  const reportedAt = optionalTimestamp('reportedAt', body.reportedAt);
  const immediateAction = optionalText(body.immediateAction);
  const lostTimeDays = optionalNonNegativeInteger('lostTimeDays', body.lostTimeDays);
  const restrictedDays = optionalNonNegativeInteger('restrictedDays', body.restrictedDays);

  requireLadderConsistency({
    severityLevel: body.severityLevel,
    lostTimeDays,
    restrictedDays,
    occurredAt,
    reportedAt
  });

  const { rows: [orgUnit] } = await getPool().query(
    'SELECT id, path FROM org_units WHERE id = $1',
    [orgUnitId]
  );
  if (!orgUnit) throw notFound('Org Unit');

  if (assetId !== null) await resolveAssetAtOrgUnit(assetId, orgUnit.path);
  if (employeeId !== null) await resolveEmployee(employeeId);

  const id = await withActor(accountId, async (client) => {
    const siteCode = await findSiteCodeForOrgUnit(orgUnitId, client);
    if (!siteCode) throw notFound('Site');

    const { rows: [numberRow] } = await client.query(
      `SELECT next_document_number('SI', $1, EXTRACT(YEAR FROM now())::int) AS incident_no`,
      [siteCode]
    );

    const { rows: [row] } = await client.query(
      `INSERT INTO safety_incidents (
         incident_no, org_unit_id, asset_id, occurred_at, reported_at,
         incident_type, severity_level, employee_id, lost_time_days,
         restricted_days, description, immediate_action,
         recorded_by_account_id
       )
       VALUES ($1, $2, $3, $4, COALESCE($5::timestamptz, now()), $6, $7, $8, $9,
               $10, $11, $12, $13)
       RETURNING id`,
      [
        numberRow.incident_no,
        orgUnitId,
        assetId,
        occurredAt.toISOString(),
        body.reportedAt ?? null,
        body.incidentType,
        body.severityLevel,
        employeeId,
        lostTimeDays,
        restrictedDays,
        description,
        immediateAction,
        accountId
      ]
    );
    return row.id;
  });

  return getSafetyIncidentDetail(String(id));
}

module.exports = {
  INCIDENT_TYPES,
  SEVERITY_LEVELS,
  RECORDABLE_LEVELS,
  listSafetyIncidents,
  findSafetyIncident,
  getSafetyIncidentDetail,
  recordSafetyIncident
};
