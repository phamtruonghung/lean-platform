/*
 * Safety observations (issue #230) — the leading indicator, and the reason
 * this Module is worth building rather than a board that counts injuries. A
 * Safety observation records what was seen *before* anything went wrong: a
 * safe act, an unsafe act or an unsafe condition, under one of the schema's
 * ten categories, ranked by the worst credible outcome rather than by what
 * actually happened. Closest prior art is safety-incidents.js — the same
 * Module, the same two-door recording shape, the same production-day filing —
 * and this file follows it closely rather than inventing a second shape.
 *
 * Three things about this file are worth reading before changing it.
 *
 * **An observation has no status, and no migration introduces one** (#223
 * decision 9). It is a fact; the Action raised from it (#231) carries the
 * state, and worst-first ordering by severity potential is the worklist.
 * There is nothing here resembling `safety_incidents.status` or
 * `safety_incident_events` — no ladder to move, nothing to close. Because
 * that Action is the only thing that says an observation was dealt with, an
 * observation with none has to stay findable — `listSafetyObservations`'s own
 * `hasAction` filter, and `getSafetyObservationDetail`'s own `actions` list,
 * exist for exactly that reason.
 *
 * **Every observation names its recorder, and there is no unattributed
 * path.** Two doors record one, and each names a different kind of recorder:
 * a signed-in Account (`actor.accountId`, migration 1801100000000's own
 * `recorded_by_account_id`) or an Employee identified at a registered floor
 * device (`actor.employeeId`, the baseline's own `observer_employee_id`) —
 * the same `{ accountId }` / `{ employeeId }` shape `recordSafetyIncident`
 * gives its own two-door `actor` object. Exactly one of the two is ever set:
 * `safety-observation-routes.js`'s Account door passes `{ accountId }`,
 * `floor-safety-observation-routes.js`'s floor door passes `{ employeeId }`,
 * and neither door can produce a record with neither set — a request that
 * reaches this function at all has already been authenticated by one door or
 * the other. Unlike `safety_incidents.employee_id` (the person *involved*,
 * a separate field from who reported), `safety_observations` carries only one
 * Employee column at all — `observer_employee_id` — because an observation
 * has no injured party to name separately from whoever made it; the same
 * column serves as the floor door's attribution field the way
 * `safety_incidents.reported_by` does for an incident.
 *
 * **The production day and the shift are the database's answer, not this
 * file's.** `safety_observations` has carried the baseline's own
 * `fill_shift_instance` trigger since the schema was written (`SELECT
 * attach_shift_instance('safety_observations', 'observed_at')`), so an insert
 * that supplies only `org_unit_id` and `observed_at` lands in the shift
 * instance that covers that moment, from which the production day (ADR-0017)
 * and the shift's own name are read back. This file resolves neither.
 *
 * There is no read restriction of any kind: unlike an incident's injury
 * classification (ADR-0037), nothing about an observation names a person's
 * health information, so every field is readable by anyone who can see the
 * Site — safety-observation-routes.js's own `respondWith*` helpers exist for
 * symmetry with the incidents file's greppable-answer discipline, not because
 * there is anything to withhold.
 *
 * Mirrors nonconformances.js and safety-incidents.js: no HTTP, no caller
 * awareness. This file's records ARE placed in the Org Unit tree, so its
 * queries join `org_units`; for the optional Employee named as observer, it
 * joins `employees` — the Employee directory is platform-wide and Grant-free
 * by ADR-0009, so naming one is an existence check rather than another
 * Module's judgment. Scope is not this file's business:
 * safety-observation-routes.js and floor-safety-observation-routes.js both ask
 * People before calling anything here.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// The value sets the baseline's own CHECK constraints enforce
// (`safety_observations_observation_type_check`,
// `safety_observations_category_check`,
// `safety_observations_severity_potential_check`). Repeated here so a caller
// gets a sentence naming the field rather than a raw constraint violation, the
// same reasoning safety-incidents.js gives its own repeated sets.
const OBSERVATION_TYPES = ['safe_act', 'unsafe_act', 'unsafe_condition'];

const CATEGORIES = [
  'ppe',
  'machine_guarding',
  'housekeeping',
  'ergonomics',
  'chemical',
  'working_at_height',
  'traffic',
  'energy_isolation',
  'procedure',
  'other'
];

// Worst-first order lives in this array's own position, exactly the reasoning
// safety-incidents.js's own `SEVERITY_LEVELS` comment gives for the ladder:
// the frontend's severity-potential picker renders this same order, and
// `severityPotentialRank` below is built from this array's position rather
// than a second, hand-kept table that could drift from it.
const SEVERITY_POTENTIALS = ['low', 'medium', 'high', 'fatal'];

function requireMembership(field, value, allowed) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw httpError(400, `${field} must be one of ${allowed.join(', ')}`);
  }
}

// The register's own cap, one row past which means "there is more" rather
// than a silently truncated Site — the same shape safety-incidents.js's
// register keeps (ADR-0026).
const SAFETY_OBSERVATION_LIST_LIMIT = 200;

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
  return value.trim();
}

function optionalText(value) {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

// Stop-work is its own flag, never a category or a potential (#230's own
// criterion) — accepted as a real boolean or as the two strings a plain HTML
// form sends, and refused otherwise with a 400 naming the field, the same
// discipline every other known-set field in this Module gets.
function optionalBoolean(field, value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw httpError(400, `${field} must be true or false`);
}

function optionalTimestamp(field, value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' && !(value instanceof Date)) {
    throw httpError(400, `${field} must be a timestamp`);
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw httpError(400, `${field} must be a valid timestamp`);
  }
  return parsed;
}

const SAFETY_OBSERVATION_COLUMNS = `
  so.id, so.observed_at, so.observation_type, so.category,
  so.severity_potential, so.description, so.action_taken, so.is_stop_work,
  so.recorded_by_account_id, au.display_name AS recorded_by_account_name,
  so.observer_employee_id, oe.display_name AS observer_employee_name,
  so.org_unit_id, ou.name AS org_unit_name, ou.path AS org_unit_path,
  ou.site_id, s.code AS site_code, s.name AS site_name,
  so.shift_instance_id,
  -- A production day is a day in the Site's own calendar (ADR-0017), read as
  -- a to_char string never as a JS Date — safety-incidents.js's own
  -- SAFETY_INCIDENT_COLUMNS explains why a Date object is the wrong shape
  -- here.
  to_char(shi.production_date, 'YYYY-MM-DD') AS production_date,
  shi.starts_at AS shift_starts_at, shi.ends_at AS shift_ends_at,
  sd.code AS shift_code, sd.name AS shift_name,
  so.created_at, so.updated_at`;

const SAFETY_OBSERVATION_JOINS = `
  FROM safety_observations so
  JOIN org_units ou ON ou.id = so.org_unit_id
  JOIN sites s ON s.id = ou.site_id
  LEFT JOIN employees oe ON oe.id = so.observer_employee_id
  LEFT JOIN app_users au ON au.id = so.recorded_by_account_id
  LEFT JOIN shift_instances shi ON shi.id = so.shift_instance_id
  LEFT JOIN shift_definitions sd ON sd.id = shi.shift_definition_id`;

function toSafetyObservation(row, { actions = [] } = {}) {
  return {
    id: row.id,
    observedAt: row.observed_at,
    observationType: row.observation_type,
    category: row.category,
    severityPotential: row.severity_potential,
    description: row.description,
    actionTaken: row.action_taken ?? null,
    isStopWork: row.is_stop_work === true,
    recordedByAccountId: row.recorded_by_account_id ?? null,
    recordedByAccountName: row.recorded_by_account_name ?? null,
    observerEmployeeId: row.observer_employee_id ?? null,
    observerEmployeeName: row.observer_employee_name ?? null,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    orgUnitPath: row.org_unit_path,
    siteId: row.site_id,
    siteCode: row.site_code,
    siteName: row.site_name,
    // The production day and the shift, as the baseline's own trigger filed
    // them (ADR-0017). Both are null for a Site with no shift calendar
    // covering that moment.
    shiftInstanceId: row.shift_instance_id,
    productionDate: row.production_date ?? null,
    shiftCode: row.shift_code ?? null,
    shiftName: row.shift_name ?? null,
    shiftStartsAt: row.shift_starts_at ?? null,
    shiftEndsAt: row.shift_ends_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // The Actions raised from this observation, with their own status (issue
    // #231) — empty on a list row and on a plain find, filled in only by
    // `getSafetyObservationDetail`, the same shape `toSafetyIncident` gives
    // its own `events`/`concerns`. Empty is a real state — nothing has been
    // done about it yet, which is exactly what `hasAction=false` finds.
    actions
  };
}

/**
 * The Site's Safety observations, **worst-first** by severity potential
 * (#223's own binding design comment, and #230's own criterion) — the entire
 * reason the field exists, so it is the list's default order rather than an
 * option a caller has to ask for.
 *
 * The tie-break, for two observations tied on potential, is most-recently
 * observed first (`observed_at DESC`), then `id DESC` as a final, total
 * order: the baseline's own `safety_observations_priority_idx` is built on
 * exactly `(severity_potential, observed_at DESC)`, so this query's own order
 * is the index's own shape rather than a second, undocumented opinion about
 * what "worst-first" means for a tie. A safety walk's own worklist is worked
 * newest-to-oldest within one rung, on the reasoning that the most recent
 * report of a given severity is the one least likely to have already been
 * dealt with.
 *
 * Site-wide with no Grant filter, the same rule the Non-conformance log and
 * the Safety incident register already follow (#55, ADR-0009, ADR-0032): Org
 * Unit scope decides where an Account may *act*, not what it may know about.
 * `orgUnitPath` — resolved by the route from a `?orgUnitId=` and handed here
 * as the ltree path — narrows to one area **and everything beneath it**.
 *
 * `from`/`to` are production days, not instants (ADR-0017), for the same
 * reason safety-incidents.js's own range is: a row whose Site had no shift
 * instance covering it falls back to its own observed date rather than being
 * silently excluded from every range.
 */
async function listSafetyObservations(
  siteId,
  {
    orgUnitPath = null,
    observationType = null,
    category = null,
    severityPotential = null,
    isStopWork = null,
    hasAction = null,
    from = null,
    to = null,
    limit = SAFETY_OBSERVATION_LIST_LIMIT
  } = {}
) {
  const conditions = ['ou.site_id = $1'];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (observationType !== null) {
    params.push(observationType);
    conditions.push(`so.observation_type = $${params.length}`);
  }
  if (category !== null) {
    params.push(category);
    conditions.push(`so.category = $${params.length}`);
  }
  if (severityPotential !== null) {
    params.push(severityPotential);
    conditions.push(`so.severity_potential = $${params.length}`);
  }
  if (isStopWork !== null) {
    params.push(isStopWork);
    conditions.push(`so.is_stop_work = $${params.length}`);
  }
  // Whether an Action has been raised from this observation (issue #231) —
  // an EXISTS/NOT EXISTS against action_items rather than a join, so a row
  // with two Actions raised against it is still counted once. `hasAction:
  // false` is #231's own acceptance criterion: an observation with none has
  // to stay findable, since it carries no status of its own to say so
  // (#223 decision 9).
  if (hasAction !== null) {
    conditions.push(
      hasAction
        ? `EXISTS (SELECT 1 FROM action_items ai WHERE ai.safety_observation_id = so.id)`
        : `NOT EXISTS (SELECT 1 FROM action_items ai WHERE ai.safety_observation_id = so.id)`
    );
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`COALESCE(shi.production_date, so.observed_at::date) >= $${params.length}::date`);
  }
  if (to !== null) {
    params.push(to);
    conditions.push(`COALESCE(shi.production_date, so.observed_at::date) <= $${params.length}::date`);
  }

  const { rows } = await getPool().query(
    `SELECT ${SAFETY_OBSERVATION_COLUMNS}
     ${SAFETY_OBSERVATION_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY array_position(ARRAY['low', 'medium', 'high', 'fatal']::text[], so.severity_potential) DESC,
              so.observed_at DESC, so.id DESC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    observations: rows.slice(0, limit).map(toSafetyObservation),
    truncated
  };
}

// The null-returning form, mirroring findSafetyIncident/findAsset: a
// malformed id resolves to null rather than reaching Postgres as a BIGINT
// parameter.
async function findSafetyObservation(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SAFETY_OBSERVATION_COLUMNS} ${SAFETY_OBSERVATION_JOINS} WHERE so.id = $1`,
    [id]
  );
  return rows[0] ? toSafetyObservation(rows[0]) : null;
}

// The Actions raised from this observation, if any have been (issue #231) —
// read from the Actions Module's own `action_items` table by ordinary SQL
// join (ADR-0006's "code seams, not data seams"), the mirror of
// safety-incidents.js's own `CONCERN_COLUMNS`/`listConcernsForIncident`.
// `ai.safety_observation_id` is the whole of the relationship: an observation
// carries no status of its own (#223 decision 9), so the Actions raised
// against it, and each one's own status, are the only answer to "was this
// dealt with".
const OBSERVATION_ACTION_COLUMNS = `
  ai.id, ai.action_no, ai.title, ai.action_type, ai.status, ai.priority,
  to_char(ai.due_date, 'YYYY-MM-DD') AS due_date,
  (ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE) AS is_overdue,
  ai.raised_at, ai.org_unit_id, ou.name AS org_unit_name,
  e.display_name AS owner_name`;

const OBSERVATION_ACTION_JOINS = `
  FROM action_items ai
  JOIN org_units ou ON ou.id = ai.org_unit_id
  LEFT JOIN employees e ON e.id = ai.owner_employee_id`;

function toObservationAction(row) {
  return {
    id: row.id,
    actionNo: row.action_no,
    title: row.title,
    actionType: row.action_type,
    status: row.status,
    priority: row.priority,
    ownerName: row.owner_name ?? null,
    dueDate: row.due_date ?? null,
    isOverdue: row.is_overdue === true,
    raisedAt: row.raised_at,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name
  };
}

async function listActionsForObservation(safetyObservationId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${OBSERVATION_ACTION_COLUMNS}
     ${OBSERVATION_ACTION_JOINS}
     WHERE ai.safety_observation_id = $1
     ORDER BY ai.raised_at, ai.id`,
    [safetyObservationId]
  );
  return rows.map(toObservationAction);
}

// The detail read: the observation together with the Actions raised from it,
// oldest first — the order a person reads a record's own story in, the same
// choice `getSafetyIncidentDetail` makes for its own events and Concerns. Its
// own function, mirroring the list/find pair above, so the register's plain
// row stays cheap: nothing about a walk's whole register needs a per-row
// Actions list, only the one record a reader opens.
async function getSafetyObservationDetail(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SAFETY_OBSERVATION_COLUMNS} ${SAFETY_OBSERVATION_JOINS} WHERE so.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return toSafetyObservation(rows[0], {
    actions: await listActionsForObservation(rows[0].id)
  });
}

// The Site's short code, which nothing here quotes today — observations carry
// no document number of their own, unlike an incident's `SI-` number, since
// #230's own acceptance criteria never asks one of a fact rather than a
// numbered record. Kept out of this file entirely; there is no analogue of
// `findSiteCodeForOrgUnit` here.

/**
 * Record a Safety observation (issue #230).
 *
 * `actor` is `{ accountId }` or `{ employeeId }` — the two doors this Module
 * has, the same shape `recordSafetyIncident`'s own `actor` already uses. The
 * Account door (`safety-observation-routes.js`) passes `accountId`; the floor
 * door (`floor-safety-observation-routes.js`) passes the identified
 * Employee's id as `employeeId`, written to `observer_employee_id` — the only
 * Employee column this table has, since an observation names no injured party
 * separate from whoever made it. Not validated for existence here: the floor
 * route only ever reaches this function with `req.technician.id`, already
 * resolved from a real identification, the same trust
 * `recordSafetyIncident` places in its own `actor.employeeId`.
 *
 * The route has already resolved the Org Unit and answered the scope question
 * (`people.canAct({ …, write: true })` on the Account door,
 * `people.deviceReachesOrgUnit` on the floor door); everything that is a fact
 * about the record itself is decided here.
 *
 * The shift instance and the audit columns are the database's own work —
 * `fill_shift_instance` for the first, the shared audit trigger for the
 * second — so the INSERT names only what a person actually decided.
 */
async function recordSafetyObservation(input, actor = {}) {
  const body = input ?? {};
  const accountId = actor.accountId ?? null;
  const observerEmployeeId = actor.employeeId ?? null;

  const orgUnitId = parseId(body.orgUnitId);
  if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');

  requireMembership('observationType', body.observationType, OBSERVATION_TYPES);
  requireMembership('category', body.category, CATEGORIES);
  requireMembership('severityPotential', body.severityPotential, SEVERITY_POTENTIALS);
  const description = requireNonEmptyString('description', body.description);
  const actionTaken = optionalText(body.actionTaken);
  const isStopWork = optionalBoolean('isStopWork', body.isStopWork, false);
  const observedAt = optionalTimestamp('observedAt', body.observedAt);

  const { rows: [orgUnit] } = await getPool().query('SELECT id FROM org_units WHERE id = $1', [
    orgUnitId
  ]);
  if (!orgUnit) throw notFound('Org Unit');

  const id = await withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `INSERT INTO safety_observations (
         org_unit_id, observed_at, observation_type, category, severity_potential,
         description, action_taken, is_stop_work, observer_employee_id,
         recorded_by_account_id
       )
       VALUES ($1, COALESCE($2::timestamptz, now()), $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id`,
      [
        orgUnitId,
        observedAt === null ? null : observedAt.toISOString(),
        body.observationType,
        body.category,
        body.severityPotential,
        description,
        actionTaken,
        isStopWork,
        observerEmployeeId,
        accountId
      ]
    );
    return row.id;
  });

  return findSafetyObservation(String(id));
}

module.exports = {
  OBSERVATION_TYPES,
  CATEGORIES,
  SEVERITY_POTENTIALS,
  listSafetyObservations,
  findSafetyObservation,
  getSafetyObservationDetail,
  recordSafetyObservation
};
