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
 * advisory. Two doors record an incident, and each names a different kind of
 * reporter: a signed-in Account (`actor.accountId`, `recorded_by_account_id`)
 * or an Employee identified at a registered floor device (`actor.employeeId`,
 * `reported_by`, issue #227) — the same `{ accountId }` / `{ employeeId }`
 * shape `nonconformances.js` gives its own two-door `actor` object. Exactly
 * one of the two is ever set: `safety-incident-routes.js`'s Account door
 * passes `{ accountId }`, `floor-safety-incident-routes.js`'s floor door
 * passes `{ employeeId }`, and neither door can produce a record with
 * neither set — a request that reaches this function at all has already been
 * authenticated by one door or the other. `is_anonymous` is never set from a
 * caller; the column's own default (`FALSE`) is left to fire.
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
 * **Issue #224 — the injury classification, and what this file does and does
 * not know about who may read it.** Three more fields are written here now:
 * the identified Employee (`employee_id`, which this file already accepted),
 * the Injury type and the Body part (`injury_type_id`, `body_part_id`, both
 * baseline columns with no migration in this ticket at all). They are set at
 * recording and corrected afterwards through `classifySafetyIncident` below,
 * and the near-miss rung is validated against all three of them as well as
 * against the two day counts — the baseline's own
 * `safety_incidents_near_miss_no_injury` CHECK said as a sentence naming the
 * field, exactly as the day counts already were.
 *
 * ADR-0037 restricts who may READ those fields back, and this file holds only
 * the *row shape* half of that: `withoutInjuryDetails` below takes an already
 * serialised incident and returns it with the restricted keys deleted —
 * **deleted, not nulled**, because a null would tell a reader there is
 * something here they cannot see about a specific field, and the ADR's rule is
 * absence. It takes no Account and asks no question; who may read a given
 * incident is safety-incident-routes.js's, the same division AGENTS.md §6 fixes
 * for every other caller-aware decision in this Module.
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
 *
 * **Issue #228 — making a recorded incident answerable.** Five more things
 * live here, added by migration 1800900000000 and this ticket: setting or
 * changing the investigation due date, moving the status ladder, recording
 * what the injury cost, correcting the severity, and closing. Every one of
 * the last four writes a row to `safety_incident_events` in the same
 * transaction as its own UPDATE — `writeIncidentEvent` below, called the same
 * way `nonconformances.js`'s `writeCorrection` is. `routes.js` asks People
 * about the edit Grant or the Safety authority each of these five needs
 * *before* calling in here (AGENTS.md §6); this file assumes the caller
 * already checked what needed checking and only enforces what is a fact about
 * the record itself: the ladder, the note, the days.
 *
 * **"The days settled" is answered by this table, not a new column.** Closing
 * an incident above the no-injury rung is refused (409) until the lost-time
 * and restricted days have been recorded at least once, zero being an
 * acceptable answer — see migration 1800900000000's own header for why that
 * is asked of `safety_incident_events` (has a `days` row ever been written
 * for this incident?) rather than a second column on `safety_incidents` that
 * cannot tell "recorded as zero" from "never looked at".
 *
 * **A severity correction is accepted on a closed incident.** #223 decision 5
 * is the reason: a January first-aid case upgraded to lost-time in March
 * restates January's own numbers, and March is routinely after the incident
 * that made it has long since closed. Every other change below refuses a
 * closed incident (moving its status, recording its days, closing it again);
 * changing its severity does not.
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

// The status ladder, in order (issue #228). `open` is never a move's own
// target — nothing moves *back* to it — and `closed` is reached only through
// `closeSafetyIncident`, never through `moveSafetyIncidentStatus`: closing has
// its own rules (Safety authority, a note, the days settled) that the
// ordinary ladder move does not ask, so it is not one of the targets that
// move accepts. `STATUSES` is every value the column's own CHECK allows, used
// to validate a caller's `?status=` filter; `STATUS_MOVE_TARGETS` is the
// narrower set `moveSafetyIncidentStatus` accepts as a destination.
const STATUSES = ['open', 'investigating', 'actions_pending', 'closed'];
const STATUS_MOVE_TARGETS = ['investigating', 'actions_pending'];

// The one legal next step from each status, for the ordinary ladder move.
// `actions_pending` and `closed` have no entry: there is nowhere the ordinary
// move can take an incident already at `actions_pending` (only closing can),
// and nothing ever moves once it is `closed`.
const NEXT_STATUS = {
  open: 'investigating',
  investigating: 'actions_pending'
};

// The event kinds `safety_incident_events` accepts (migration 1800900000000,
// widened by 1801000000000 to add `classification` for issue #224's history
// criterion) — repeated here for the same reason INCIDENT_TYPES is repeated
// from the baseline's own CHECK.
const EVENT_KINDS = ['severity', 'status', 'days', 'closure', 'classification'];

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

// A required count of days (issue #228's own days-recording act): unlike
// `optionalNonNegativeInteger`, an absent value is a 400 rather than a silent
// zero. Recording the days is a deliberate act — "zero being an answer" only
// holds when zero was actually said, not when the field was left out — so
// this function exists specifically to not default the way the recording
// form's own field does.
function requireNonNegativeInteger(field, value) {
  if (value === undefined || value === null || value === '') {
    throw httpError(400, `${field} is required`);
  }
  const number = typeof value === 'string' ? Number(value.trim()) : value;
  if (typeof number !== 'number' || !Number.isFinite(number) || !Number.isInteger(number) || number < 0) {
    throw httpError(400, `${field} must be a whole number of days, or zero`);
  }
  return number;
}

// The note a severity change or a closure is taken with (issue #228). Both
// require one — a change with no reason on it is the row an auditor cannot
// use — and `reason` names which act refused it, so the 400 reads as a
// sentence rather than a field name alone.
function requireChangeNote(body, reason) {
  const note = optionalText(body.note);
  if (note === null) throw httpError(400, `note is required: say why ${reason}`);
  return note;
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
 *   - No lost-time days, no restricted days, no injury type and no body part
 *     on the no-injury rung (`near_miss`) — nobody was hurt, so there was
 *     nothing to classify and nothing was lost. All four halves of the
 *     baseline's own `safety_incidents_near_miss_no_injury` CHECK, each said
 *     as a sentence naming its own field (issue #224's own criterion: "an
 *     injury type or body part on the no-injury rung is a 400 naming the
 *     field"). The identified Employee is deliberately NOT one of them: that
 *     CHECK does not forbid naming who was involved in a near miss, and a
 *     report that says who was nearly hurt is a report worth keeping.
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
function requireLadderConsistency({
  severityLevel,
  lostTimeDays,
  restrictedDays,
  occurredAt,
  reportedAt,
  injuryTypeId = null,
  bodyPartId = null
}) {
  if (severityLevel === 'near_miss') {
    if (lostTimeDays > 0) {
      throw httpError(400, 'lostTimeDays must be 0 on the near_miss rung: nobody was hurt');
    }
    if (restrictedDays > 0) {
      throw httpError(400, 'restrictedDays must be 0 on the near_miss rung: nobody was hurt');
    }
    if (injuryTypeId !== null) {
      throw httpError(400, 'injuryTypeId cannot be set on the near_miss rung: nobody was injured');
    }
    if (bodyPartId !== null) {
      throw httpError(400, 'bodyPartId cannot be set on the near_miss rung: nobody was injured');
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
  -- The three fields ADR-0037 restricts, each read with the catalogue row it
  -- names so a reader who may see them needs no second request. They are
  -- SELECTed on every read path without exception: the restriction is applied
  -- to the serialised object by withoutInjuryDetails, never by building a
  -- second, narrower query -- two projections of one table is how a field ends
  -- up restricted on the detail and not on the register.
  si.employee_id, e.display_name AS employee_name,
  si.injury_type_id, it.code AS injury_type_code, it.name AS injury_type_name,
  si.body_part_id, bp.code AS body_part_code, bp.name AS body_part_name,
  bp.region AS body_part_region,
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
  LEFT JOIN injury_types it ON it.id = si.injury_type_id
  LEFT JOIN body_parts bp ON bp.id = si.body_part_id
  LEFT JOIN app_users au ON au.id = si.recorded_by_account_id
  LEFT JOIN shift_instances shi ON shi.id = si.shift_instance_id
  LEFT JOIN shift_definitions sd ON sd.id = shi.shift_definition_id`;

function toSafetyIncident(row, { events = [], concerns = [] } = {}) {
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
    // The injury classification (issue #224) — the identified Employee, the
    // Injury type and the Body part, each with the catalogue row's own code
    // and name so a reader needs no second request. A deactivated catalogue
    // entry still joins here: it is excluded from the choices a classifier is
    // offered, never from an incident that already names it.
    //
    // Every one of these keys is deleted again by `withoutInjuryDetails` for a
    // caller ADR-0037 withholds them from. They are built here unconditionally
    // because this function knows nothing about who is asking (AGENTS.md §6).
    employeeId: row.employee_id,
    employeeName: row.employee_name ?? null,
    injuryTypeId: row.injury_type_id ?? null,
    injuryTypeCode: row.injury_type_code ?? null,
    injuryTypeName: row.injury_type_name ?? null,
    bodyPartId: row.body_part_id ?? null,
    bodyPartCode: row.body_part_code ?? null,
    bodyPartName: row.body_part_name ?? null,
    bodyPartRegion: row.body_part_region ?? null,
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
    updatedAt: row.updated_at,
    // The event history (issue #228): empty on a list row and on a plain
    // find, filled in only by getSafetyIncidentDetail — the same shape
    // toNonconformance gives its own quantityChanges/dispositions/corrections.
    events,
    // The Concern raised from this incident, if one has been (issue #229) —
    // read from the Actions Module's own table by ordinary SQL join
    // (ADR-0006's "code seams, not data seams"), the same way `toNonconformance`
    // reads its own `concerns`. Empty on a list row and on a plain find, filled
    // in only by `getSafetyIncidentDetail`; empty is a real state — nothing is
    // being done about the cause yet — not a missing field.
    concerns
  };
}

// The keys ADR-0037 restricts, named once. They carry three facts — who the
// record names as hurt, what the injury was, and where on the body — and the
// display halves (`employeeName`, the two catalogue codes and names, the body
// part's region) are in the list for the obvious reason: withholding an
// injured person's id while returning their display name would defend nothing,
// and neither would withholding an Injury type's id while naming it.
//
// Everything else stays: severity level, incident type, description, immediate
// action, lost-time and restricted days, status, the event history, who
// recorded it and when. ADR-0037 states that as a limit on what the
// restriction protects rather than as a caveat attached to something broader —
// `description` and `immediate_action` are free text a person writes whatever
// they write into, and no gate is placed on them here or anywhere.
const RESTRICTED_INJURY_KEYS = [
  'employeeId',
  'employeeName',
  'injuryTypeId',
  'injuryTypeCode',
  'injuryTypeName',
  'bodyPartId',
  'bodyPartCode',
  'bodyPartName',
  'bodyPartRegion'
];

/**
 * One already-serialised incident with the restricted keys **deleted** (issue
 * #224, ADR-0037).
 *
 * Deleted, not nulled, and the difference is the whole decision: a null tells
 * a reader "there is something here about this particular field that you may
 * not see", which is a smaller disclosure than the value but a disclosure all
 * the same, and it makes "not classified yet" and "not mine to see"
 * indistinguishable for the reader who IS allowed to see. Absence is the rule
 * the ADR states; an authorised reader looking at an unclassified incident
 * gets these keys present and null, and that is exactly how the two cases stay
 * apart.
 *
 * Takes no Account, asks no question and runs no query — who may read a given
 * incident is safety-incident-routes.js's decision (AGENTS.md §6: this file is
 * unaware of who is calling). This is the row-shape half and nothing else,
 * which is why it is safe to call it unconditionally, as the floor door does.
 *
 * The event history is filtered too. `safety_incident_events` carries its
 * values as generic TEXT, so a `classification` row (migration 1801000000000
 * widened the table's `kind` CHECK for it; `classifySafetyIncident` writes
 * one) would hand a Site-wide reader the very values the keys above were just
 * removed for. The whole row is dropped rather than its two value fields
 * blanked, for the same reason the keys are deleted rather than nulled.
 */
function withoutInjuryDetails(incident) {
  const stripped = { ...incident };
  for (const key of RESTRICTED_INJURY_KEYS) delete stripped[key];
  if (Array.isArray(stripped.events)) {
    stripped.events = stripped.events.filter((event) => event.kind !== 'classification');
  }
  return stripped;
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

// The Site's incidents whose investigation is overdue (issue #228): past
// `investigation_due_at` and not `closed`, for an Org Unit and everything
// beneath it. Readable by anyone who can see the Site — the same weaker
// question the register itself asks — because this is a worklist, not a
// decision surface. `investigation_due_at IS NOT NULL` is deliberate: an
// incident nobody has ever given a deadline has nothing to be overdue against,
// and listing it here would bury the incidents that actually missed one.
// `safety_incidents_open_idx` (the baseline's own partial index on
// `(org_unit_id, investigation_due_at) WHERE status <> 'closed'`) is exactly
// this query's own shape.
async function listOverdueSafetyIncidents(siteId, { orgUnitPath = null, limit = SAFETY_INCIDENT_LIST_LIMIT } = {}) {
  const conditions = [
    'ou.site_id = $1',
    "si.status <> 'closed'",
    'si.investigation_due_at IS NOT NULL',
    'si.investigation_due_at < now()'
  ];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }

  const { rows } = await getPool().query(
    `SELECT ${SAFETY_INCIDENT_COLUMNS}
     ${SAFETY_INCIDENT_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY si.investigation_due_at ASC, si.id ASC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    incidents: rows.slice(0, limit).map((row) => toSafetyIncident(row)),
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

// One row of the event history, with whoever made the change named (issue
// #228) — an Account or an identified Employee, mirroring the incident's own
// two-actor shape (`recordedByAccountName`/`reportedByName`). Only an Account
// has ever written one in this slice (`changedByEmployeeName` is always null
// today), but the projection reads both, the same way `SAFETY_INCIDENT_COLUMNS`
// reads both of the incident's own actor columns whether or not the floor door
// is the one that filled them.
const SAFETY_INCIDENT_EVENT_COLUMNS = `
  sie.id, sie.safety_incident_id, sie.kind, sie.previous_value, sie.new_value,
  sie.note, sie.changed_at,
  sie.changed_by_account_id, cau.display_name AS changed_by_account_name,
  sie.changed_by_employee_id, cae.display_name AS changed_by_employee_name`;

const SAFETY_INCIDENT_EVENT_JOINS = `
  FROM safety_incident_events sie
  LEFT JOIN app_users cau ON cau.id = sie.changed_by_account_id
  LEFT JOIN employees cae ON cae.id = sie.changed_by_employee_id`;

function toSafetyIncidentEvent(row) {
  return {
    id: row.id,
    kind: row.kind,
    previousValue: row.previous_value,
    newValue: row.new_value,
    note: row.note ?? null,
    changedByAccountId: row.changed_by_account_id ?? null,
    changedByAccountName: row.changed_by_account_name ?? null,
    changedByEmployeeId: row.changed_by_employee_id ?? null,
    changedByEmployeeName: row.changed_by_employee_name ?? null,
    changedAt: row.changed_at
  };
}

async function listSafetyIncidentEvents(safetyIncidentId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${SAFETY_INCIDENT_EVENT_COLUMNS}
     ${SAFETY_INCIDENT_EVENT_JOINS}
     WHERE sie.safety_incident_id = $1
     ORDER BY sie.changed_at, sie.id`,
    [safetyIncidentId]
  );
  return rows.map(toSafetyIncidentEvent);
}

// One row in the history, in the same transaction as the UPDATE that made it
// true (issue #228) — a change that lands with no row saying who made it and
// when is the state this table exists to prevent, the same discipline
// `nonconformances.js`'s own `writeCorrection` keeps. `kind` is one of
// `EVENT_KINDS`; the caller picks it, this function does not infer it.
async function writeIncidentEvent(client, {
  safetyIncidentId,
  kind,
  previousValue,
  newValue,
  accountId = null,
  employeeId = null,
  note = null
}) {
  await client.query(
    `INSERT INTO safety_incident_events (
       safety_incident_id, kind, previous_value, new_value, note,
       changed_by_account_id, changed_by_employee_id
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [safetyIncidentId, kind, previousValue, newValue, note, accountId, employeeId]
  );
}

// Has this incident's days ever been recorded (issue #228)? Answered by
// asking the history rather than a column on `safety_incidents` — see
// migration 1800900000000's own header for why. Used only by
// `closeSafetyIncident`'s own 409, and only for a severity above the
// no-injury rung.
async function hasSettledDays(safetyIncidentId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT 1 FROM safety_incident_events WHERE safety_incident_id = $1 AND kind = 'days' LIMIT 1`,
    [safetyIncidentId]
  );
  return rows.length > 0;
}

// The Concern raised from this incident, if one has been (issue #229) — read
// from the Actions Module's own `action_items` table by ordinary SQL join,
// the mirror of `quality/nonconformances.js`'s own `CONCERN_COLUMNS` and
// `listConcerns`. `ai.safety_incident_id` is the whole of the relationship:
// unlike a Non-conformance's Concern, there is no link table here, because
// nothing in #229's own acceptance criteria asks for a second incident to be
// gathered onto an existing Concern.
const CONCERN_COLUMNS = `
  ai.id, ai.action_no, ai.title, ai.action_type, ai.status, ai.priority,
  to_char(ai.due_date, 'YYYY-MM-DD') AS due_date,
  (ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE) AS is_overdue,
  ai.raised_at, ai.org_unit_id, ou.name AS org_unit_name,
  e.display_name AS owner_name`;

const CONCERN_JOINS = `
  FROM action_items ai
  JOIN org_units ou ON ou.id = ai.org_unit_id
  LEFT JOIN employees e ON e.id = ai.owner_employee_id`;

function toConcern(row) {
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

async function listConcernsForIncident(safetyIncidentId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${CONCERN_COLUMNS}
     ${CONCERN_JOINS}
     WHERE ai.safety_incident_id = $1
     ORDER BY ai.raised_at, ai.id`,
    [safetyIncidentId]
  );
  return rows.map(toConcern);
}

// The detail read: the incident together with its event history (issue
// #228) and the Concern raised from it, if one has been (issue #229) — the
// order a person reads a record's own story in, the same choice
// `getNonconformanceDetail` makes for its own histories.
async function getSafetyIncidentDetail(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SAFETY_INCIDENT_COLUMNS} ${SAFETY_INCIDENT_JOINS} WHERE si.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return toSafetyIncident(rows[0], {
    events: await listSafetyIncidentEvents(rows[0].id),
    concerns: await listConcernsForIncident(rows[0].id)
  });
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

// The Injury type and the Body part named on a classification, if either is.
// Existence checks only — both catalogues are shared by every Site (ADR-0005)
// and carry no Org Unit, so there is no scope question to ask about them, the
// same shape `resolveEmployee` above has.
//
// A DEACTIVATED entry is accepted here on purpose. Deactivation removes an
// entry from the choices a classifier is offered (the catalogue read the
// dialog makes excludes it), not from the record: an incident already carrying
// a retired Injury type must stay correctable in its other fields, and
// re-stating the value it already holds must not become a 400. The catalogue's
// own list is where "still offered" is decided; this is only "does it exist".
// `code` is read alongside `id` (not just an existence check) so
// `classifySafetyIncident` can encode a `classification` event's new value
// without a second query — see that function's own doc comment.
async function resolveInjuryType(injuryTypeId) {
  const { rows } = await getPool().query('SELECT id, code FROM injury_types WHERE id = $1', [
    injuryTypeId
  ]);
  if (!rows[0]) throw notFound('Injury type');
  return rows[0];
}

async function resolveBodyPart(bodyPartId) {
  const { rows } = await getPool().query('SELECT id, code FROM body_parts WHERE id = $1', [
    bodyPartId
  ]);
  if (!rows[0]) throw notFound('Body part');
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
 * Record a Safety incident (issue #226, #227).
 *
 * `actor` is `{ accountId }` or `{ employeeId }` — the two doors this Module
 * has, the same shape `nonconformances.js`'s own two-door `actor` already
 * uses. The Account door (`safety-incident-routes.js`) passes `accountId`; the
 * floor door (`floor-safety-incident-routes.js`, issue #227) passes the
 * identified Employee's id as `employeeId` — the *reporter*, written to
 * `reported_by`. This is a different id from `body.employeeId` (the local
 * `employeeId` variable below), which is issue #224's field for the Employee
 * *involved* in the incident and always comes from the request body, never
 * from the actor. Not validated for existence here: the floor route only ever
 * reaches this function with `req.technician.id`, already resolved from a real
 * identification, the same trust `nonconformances.js` places in its own
 * `actor.employeeId`.
 *
 * The route has already resolved the Org Unit and answered the scope question
 * (`people.canAct({ …, write: true })` on the Account door,
 * `people.deviceReachesOrgUnit` on the floor door) and parsed the Asset id;
 * everything that is a fact about the record itself is decided here.
 * `is_anonymous` is never set — the column's own `FALSE` default is left to
 * fire, and migration 1800800000000's CHECK is the backstop that makes that
 * the only value the row can ever hold.
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
  const reporterEmployeeId = actor.employeeId ?? null;

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

  // The injury classification at the moment of recording (issue #224). The
  // route has already asked People for Safety authority reaching this Org Unit
  // when any of the three is present — see safety-incident-routes.js — so what
  // is left here is the shape of the ids and the ladder they have to agree
  // with. No `classification` event is written for naming it at record time,
  // the same choice `changeSafetyIncidentSeverity` makes for the severity
  // named on the very same INSERT — an event records a *change* to an
  // already-recorded incident, and there is nothing to compare a brand-new
  // row's classification against.
  const injuryTypeId = body.injuryTypeId === undefined || body.injuryTypeId === null
    ? null
    : parseId(body.injuryTypeId);
  if (body.injuryTypeId !== undefined && body.injuryTypeId !== null && injuryTypeId === null) {
    throw httpError(400, 'injuryTypeId must be a valid Injury type id');
  }

  const bodyPartId = body.bodyPartId === undefined || body.bodyPartId === null
    ? null
    : parseId(body.bodyPartId);
  if (body.bodyPartId !== undefined && body.bodyPartId !== null && bodyPartId === null) {
    throw httpError(400, 'bodyPartId must be a valid Body part id');
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
    reportedAt,
    injuryTypeId,
    bodyPartId
  });

  const { rows: [orgUnit] } = await getPool().query(
    'SELECT id, path FROM org_units WHERE id = $1',
    [orgUnitId]
  );
  if (!orgUnit) throw notFound('Org Unit');

  if (assetId !== null) await resolveAssetAtOrgUnit(assetId, orgUnit.path);
  if (employeeId !== null) await resolveEmployee(employeeId);
  if (injuryTypeId !== null) await resolveInjuryType(injuryTypeId);
  if (bodyPartId !== null) await resolveBodyPart(bodyPartId);

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
         incident_type, severity_level, employee_id, injury_type_id,
         body_part_id, lost_time_days,
         restricted_days, description, immediate_action,
         recorded_by_account_id, reported_by
       )
       VALUES ($1, $2, $3, $4, COALESCE($5::timestamptz, now()), $6, $7, $8, $9,
               $10, $11, $12, $13, $14, $15, $16)
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
        injuryTypeId,
        bodyPartId,
        lostTimeDays,
        restrictedDays,
        description,
        immediateAction,
        accountId,
        reporterEmployeeId
      ]
    );
    return row.id;
  });

  return getSafetyIncidentDetail(String(id));
}

/**
 * Set or change the investigation due date (issue #228).
 *
 * The route has already asked People for an edit Grant reaching the
 * incident's Org Unit — the same standing recording itself needs, and no
 * more, because setting a deadline is not the judgement Safety authority
 * exists for. Accepted on an incident that is not yet `closed`: the deadline
 * is what keeps an *open* investigation honest, and a closed incident has
 * nothing left to be overdue against — refused with a 409 naming that rather
 * than silently accepting a date nothing will ever read. `null` clears it,
 * which is "changed" too: a due date set in error should be removable, not
 * only replaceable with another date.
 *
 * Not written to `safety_incident_events`: issue #228's own list of what the
 * history keeps is severity, status, days and closure, and a due date is
 * none of those.
 */
async function setInvestigationDueDate(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  if (existing.status === 'closed') {
    throw httpError(409, 'this Safety incident is closed; its investigation due date cannot be changed');
  }

  const body = input ?? {};
  const investigationDueAt = optionalTimestamp('investigationDueAt', body.investigationDueAt);

  await withActor(accountId, async (client) => {
    await client.query('UPDATE safety_incidents SET investigation_due_at = $1 WHERE id = $2', [
      investigationDueAt === null ? null : investigationDueAt.toISOString(),
      id
    ]);
  });

  return getSafetyIncidentDetail(id);
}

/**
 * Move an incident's status one step along the ladder (issue #228):
 * `open -> investigating -> actions_pending`. `closed` is never a target
 * here — `closeSafetyIncident` is the only way to reach it, because closing
 * needs Safety authority, a note and the days settled, none of which this
 * ordinary move asks for, and offering `closed` as a value here would let a
 * caller reach it without any of the three.
 *
 * The route has asked for an edit Grant reaching the Org Unit, the same
 * standing recording itself needs — issue #223's own story (31) gives this to
 * a supervisor, not to a holder of Safety authority specifically.
 *
 * A move that is not the ladder's own next step — sideways, backwards, two
 * steps at once, or attempted from `closed` — is refused with a 409: the
 * record's own state is what refuses it, not a malformed request, so it is
 * not a 400.
 */
async function moveSafetyIncidentStatus(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  const body = input ?? {};
  requireMembership('status', body.status, STATUS_MOVE_TARGETS);

  const next = NEXT_STATUS[existing.status];
  if (next === undefined || next !== body.status) {
    throw httpError(
      409,
      `this Safety incident is ${existing.status}; the ladder is open -> investigating -> actions_pending -> closed, and closing has its own address`
    );
  }

  await withActor(accountId, async (client) => {
    await client.query('UPDATE safety_incidents SET status = $1 WHERE id = $2', [
      body.status,
      id
    ]);
    await writeIncidentEvent(client, {
      safetyIncidentId: existing.id,
      kind: 'status',
      previousValue: existing.status,
      newValue: body.status,
      accountId
    });
  });

  return getSafetyIncidentDetail(id);
}

/**
 * Correct an incident's severity level (issue #228).
 *
 * The route has asked for Safety authority reaching the Org Unit — 403 before
 * this function is ever called — and this function requires the note that
 * goes with it: a correction with no reason on it is the row an auditor
 * cannot use, the same requirement `nonconformances.js`'s own
 * `lowerSeverity` makes of its note.
 *
 * Deliberately not restricted to a closed or an open incident: #223 decision
 * 5 is that correcting a severity restates the period the incident occurred
 * in, and the correction routinely comes *after* the incident that needs it
 * has long since closed — a January first-aid case upgraded to lost-time in
 * March. Every other write in this file refuses a closed incident; this one
 * does not, on purpose.
 *
 * Ladder consistency is asked again with the incident's own current days
 * (`requireLadderConsistency`, the same function `recordSafetyIncident`
 * calls — issue #228's own instruction to reuse it rather than write a second
 * copy): a severity correction that would leave the record's own days
 * inconsistent with its new rung is refused the same 400 a caller recording
 * the incident from scratch would get.
 */
async function changeSafetyIncidentSeverity(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  const body = input ?? {};
  requireMembership('severityLevel', body.severityLevel, SEVERITY_LEVELS);
  const note = requireChangeNote(body, 'the severity level is being changed');

  if (body.severityLevel === existing.severityLevel) {
    throw httpError(409, `this Safety incident is already ${existing.severityLevel}; a change records a difference`);
  }

  requireLadderConsistency({
    severityLevel: body.severityLevel,
    lostTimeDays: existing.lostTimeDays,
    restrictedDays: existing.restrictedDays,
    occurredAt: new Date(existing.occurredAt),
    reportedAt: new Date(existing.reportedAt)
  });

  await withActor(accountId, async (client) => {
    await client.query('UPDATE safety_incidents SET severity_level = $1 WHERE id = $2', [
      body.severityLevel,
      id
    ]);
    await writeIncidentEvent(client, {
      safetyIncidentId: existing.id,
      kind: 'severity',
      previousValue: existing.severityLevel,
      newValue: body.severityLevel,
      note,
      accountId
    });
  });

  return getSafetyIncidentDetail(id);
}

/**
 * Record what the injury cost (issue #228): the lost-time and restricted
 * days. Both are required on every call — `requireNonNegativeInteger`, not
 * the recording form's own `optionalNonNegativeInteger` — because this is the
 * act that "settles" the days (see `hasSettledDays` and migration
 * 1800900000000's own header): a caller who sends only one of the two has not
 * said what the other one is, and defaulting it to zero silently would be
 * this function deciding a number the caller never stated.
 *
 * The route has asked for Safety authority reaching the Org Unit. Ladder
 * consistency is asked again with the incident's own current severity —
 * `requireLadderConsistency`, reused rather than duplicated, issue #228's own
 * instruction: no days on the no-injury rung, lost-time days only at
 * `lost_time` or `fatality`.
 *
 * Recording the same numbers again is not refused: unlike
 * `nonconformances.js`'s quantity, which only ever grows, "the days" can
 * legitimately be re-confirmed at the value they already were — that is what
 * "zero being an answer" means the second time as much as the first.
 */
async function recordSafetyIncidentDays(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  if (existing.status === 'closed') {
    throw httpError(409, 'this Safety incident is closed; its days cannot be changed');
  }

  const body = input ?? {};
  const lostTimeDays = requireNonNegativeInteger('lostTimeDays', body.lostTimeDays);
  const restrictedDays = requireNonNegativeInteger('restrictedDays', body.restrictedDays);

  requireLadderConsistency({
    severityLevel: existing.severityLevel,
    lostTimeDays,
    restrictedDays,
    occurredAt: new Date(existing.occurredAt),
    reportedAt: new Date(existing.reportedAt)
  });

  await withActor(accountId, async (client) => {
    await client.query(
      'UPDATE safety_incidents SET lost_time_days = $1, restricted_days = $2 WHERE id = $3',
      [lostTimeDays, restrictedDays, id]
    );
    await writeIncidentEvent(client, {
      safetyIncidentId: existing.id,
      kind: 'days',
      previousValue: `lostTimeDays=${existing.lostTimeDays},restrictedDays=${existing.restrictedDays}`,
      newValue: `lostTimeDays=${lostTimeDays},restrictedDays=${restrictedDays}`,
      accountId
    });
  });

  return getSafetyIncidentDetail(id);
}

/**
 * Classify the injury (issue #224): the identified Employee, the Injury type
 * and the Body part — the three structured fields ADR-0037 restricts.
 *
 * The route has asked People for **Safety authority** reaching the incident's
 * Org Unit (`canAct({ …, safety: true })`, ADR-0039) before this function is
 * ever called, so a 403 never reaches here. Naming who was hurt and what the
 * injury was is a judgement about a person, not a piece of work on the record,
 * which is why it takes the same standing as correcting a severity rather than
 * the edit Grant recording itself needs.
 *
 * **An absent key never touches its column; an explicit `null` clears it.**
 * The same `hasOwnProperty` contract `updateProduct` and `updateDefectCode`
 * keep, and here it is load-bearing rather than tidy: a classification is
 * three independent facts, arrived at at different moments — who was hurt is
 * known immediately, what the injury was often only after a clinic visit — so
 * a form that sends one of them must not blank the other two, and a mistaken
 * body part must be removable rather than only replaceable.
 *
 * Ladder consistency is asked again with the incident's own current severity —
 * `requireLadderConsistency`, the same function `recordSafetyIncident` calls,
 * reused rather than copied (issue #224's own instruction, the same one #228
 * gave): an injury type or a body part on the no-injury rung is a 400 naming
 * the field, never the baseline's own `safety_incidents_near_miss_no_injury`
 * CHECK surfacing as a raw constraint error. The days are passed through
 * unchanged so a classification cannot be refused for a day count it is not
 * touching.
 *
 * **Accepted on a closed incident**, unlike moving its status or recording its
 * days, and for the reason `changeSafetyIncidentSeverity` is: a classification
 * is a statement about what happened, not a step in an investigation, and what
 * the clinic finally called the injury routinely arrives after the record it
 * belongs to has been closed. Refusing it would leave a plant's own medical
 * record permanently wrong to protect a status.
 *
 * **Written to `safety_incident_events` as its own `classification` kind**
 * (migration 1801000000000, which widened the table's `kind` CHECK for
 * exactly this — issue #224's own history criterion). A dedicated fifth kind
 * rather than reusing one of the original four: `hasSettledDays` derives "the
 * days were settled" from the presence of a `days` row, so a misfiled kind
 * would quietly change when an incident may be closed, and `severity`/
 * `status`/`closure` are each statements about a different fact than who was
 * hurt and what the injury was.
 *
 * **The encoding**, following the same one-generic-TEXT-pair-per-row choice
 * migration 1800900000000 made for the `days` kind
 * (`lostTimeDays=<n>,restrictedDays=<n>`): a `classification` row's
 * `previous_value`/`new_value` is
 * `employeeId=<id|none>,injuryType=<code|none>,bodyPart=<code|none>` — the
 * Employee by id (it carries no code of its own), the Injury type and Body
 * part by their catalogue `code` rather than their id, since a code is what a
 * reader of this history actually recognises, the same way `severity`/
 * `status` rows hold the enum word itself rather than a rank number. `none`
 * marks a field that is unset, not absent from the string, so a reader is
 * never left wondering whether a comma-separated value was cut short.
 *
 * An event is written only when the encoded value actually changed — a
 * classify call that only names fields already holding those exact values
 * (including the 400 case above, which never reaches this far) writes
 * nothing, so the history stays a record of changes and not of every touch.
 */
async function classifySafetyIncident(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  const body = input ?? {};
  const touches = (key) => Object.prototype.hasOwnProperty.call(body, key);

  if (!touches('employeeId') && !touches('injuryTypeId') && !touches('bodyPartId')) {
    throw httpError(
      400,
      'name at least one of employeeId, injuryTypeId or bodyPartId, or null to clear it'
    );
  }

  // Each field's proposed value: what the body says where it says anything,
  // and what the record already holds where it does not.
  function proposed(key, current, what) {
    if (!touches(key)) return current;
    if (body[key] === null || body[key] === '') return null;
    const parsed = parseId(body[key]);
    if (parsed === null) throw httpError(400, `${key} must be a valid ${what} id, or null to clear it`);
    return parsed;
  }

  const employeeId = proposed('employeeId', existing.employeeId, 'Employee');
  const injuryTypeId = proposed('injuryTypeId', existing.injuryTypeId, 'Injury type');
  const bodyPartId = proposed('bodyPartId', existing.bodyPartId, 'Body part');

  requireLadderConsistency({
    severityLevel: existing.severityLevel,
    lostTimeDays: existing.lostTimeDays,
    restrictedDays: existing.restrictedDays,
    occurredAt: new Date(existing.occurredAt),
    reportedAt: new Date(existing.reportedAt),
    injuryTypeId,
    bodyPartId
  });

  // Existence before the write, in the same order every other route in this
  // Platform resolves it, and only for the fields that actually changed — a
  // correction that leaves a field alone must not start failing because the
  // catalogue entry it has always held was deleted out from under it. The
  // Injury type's and Body part's `code`, captured here rather than
  // re-queried below, is what the `classification` event's new value encodes.
  let injuryTypeCode = existing.injuryTypeCode;
  let bodyPartCode = existing.bodyPartCode;
  if (employeeId !== null && employeeId !== existing.employeeId) await resolveEmployee(employeeId);
  if (injuryTypeId !== existing.injuryTypeId) {
    injuryTypeCode = injuryTypeId === null ? null : (await resolveInjuryType(injuryTypeId)).code;
  }
  if (bodyPartId !== existing.bodyPartId) {
    bodyPartCode = bodyPartId === null ? null : (await resolveBodyPart(bodyPartId)).code;
  }

  const encodeClassification = (employee, injuryType, bodyPart) =>
    `employeeId=${employee ?? 'none'},injuryType=${injuryType ?? 'none'},bodyPart=${bodyPart ?? 'none'}`;
  const previousValue = encodeClassification(
    existing.employeeId,
    existing.injuryTypeCode,
    existing.bodyPartCode
  );
  const newValue = encodeClassification(employeeId, injuryTypeCode, bodyPartCode);
  const changed = previousValue !== newValue;

  await withActor(accountId, async (client) => {
    await client.query(
      `UPDATE safety_incidents
          SET employee_id = $1, injury_type_id = $2, body_part_id = $3
        WHERE id = $4`,
      [employeeId, injuryTypeId, bodyPartId, id]
    );
    if (changed) {
      await writeIncidentEvent(client, {
        safetyIncidentId: existing.id,
        kind: 'classification',
        previousValue,
        newValue,
        accountId
      });
    }
  });

  return getSafetyIncidentDetail(id);
}

/**
 * Close an incident (issue #228) — the judgement of someone accountable for
 * the place, per #223 decision 4.
 *
 * The route has asked for Safety authority reaching the Org Unit (403 before
 * this function runs). Three more things are asked here, in the order #228's
 * own acceptance criterion states them:
 *
 *   - A closure note (400) — the same requirement a severity change makes of
 *     its own note, and for the same reason.
 *   - Already-closed is a 409, not a second closure: the closing time the
 *     first close set would otherwise be silently overwritten.
 *   - The days settled (409) for any rung above the no-injury one —
 *     `hasSettledDays`, which asks `safety_incident_events` rather than a
 *     column, so that LTIFR's numerator is never left blank without a
 *     `days` event on record to say it was actually looked at.
 *
 * **Never refused because a Concern raised from the incident is open.** #223
 * decision 4 states this in so many words, the same shape #200 settled for a
 * Non-conformance and its own Concern: this function asks nothing about the
 * Action log at all, and there is no query here that could refuse for that
 * reason even by accident.
 */
async function closeSafetyIncident(id, input, accountId) {
  const existing = await findSafetyIncident(id);
  if (!existing) throw notFound('Safety incident');

  if (existing.status === 'closed') {
    throw httpError(409, 'this Safety incident is already closed');
  }

  const body = input ?? {};
  const note = requireChangeNote(body, 'this Safety incident is being closed');

  if (existing.severityLevel !== 'near_miss') {
    const settled = await hasSettledDays(existing.id);
    if (!settled) {
      throw httpError(
        409,
        'the lost-time and restricted days must be recorded before closing a Safety incident above the near_miss rung'
      );
    }
  }

  await withActor(accountId, async (client) => {
    await client.query(
      `UPDATE safety_incidents SET status = 'closed', closed_at = now() WHERE id = $1`,
      [id]
    );
    await writeIncidentEvent(client, {
      safetyIncidentId: existing.id,
      kind: 'closure',
      previousValue: existing.status,
      newValue: 'closed',
      note,
      accountId
    });
  });

  return getSafetyIncidentDetail(id);
}

module.exports = {
  INCIDENT_TYPES,
  SEVERITY_LEVELS,
  RECORDABLE_LEVELS,
  STATUSES,
  STATUS_MOVE_TARGETS,
  EVENT_KINDS,
  RESTRICTED_INJURY_KEYS,
  withoutInjuryDetails,
  listSafetyIncidents,
  listOverdueSafetyIncidents,
  findSafetyIncident,
  getSafetyIncidentDetail,
  recordSafetyIncident,
  setInvestigationDueDate,
  moveSafetyIncidentStatus,
  changeSafetyIncidentSeverity,
  classifySafetyIncident,
  recordSafetyIncidentDays,
  closeSafetyIncident
};
