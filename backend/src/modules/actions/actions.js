/*
 * The action log (issue #176). `action_items` is a baseline table — the SQDCP
 * schema's own "single action log shared by all five pillars" — and this file
 * is the HTTP-facing service over it. ADR-0032 records why it is a Module of
 * its own rather than a corner of Maintenance.
 *
 * Like assets.js in Maintenance, this file joins `org_units`, `employees` and
 * `sqdcp_pillars` — tables other Modules own — to answer "which Org Unit is
 * this about", "whose name is on it" and "which Pillar does it threaten".
 * That is deliberate and allowed: ADR-0006 makes a Module a code seam, not a
 * data seam, and says in as many words that cross-Module reads are ordinary
 * joins. What does NOT happen here is a lookup or a write of a People record:
 * resolving the Org Unit a caller named, the Employee they assigned, and
 * asking whether they may act there, all happen one layer up in
 * action-routes.js through modules/people's entry point.
 *
 * Like plant.js and assets.js, this file is unaware of who is calling. An
 * orgUnitId reaching createAction is one the caller was already entitled to
 * raise at — and "entitled" is deliberately weaker here than for every other
 * write in the Platform: a Concern is a report rather than a decision, and
 * anyone who can see the Site may raise one at any Org Unit of it, whether or
 * not a Grant reaches that Org Unit (CONTEXT.md's Concern entry, issue #198).
 * The route asks `people.canSeeSite` for that kind and `people.canAct` at the
 * Org Unit for every other one, and says so in its own comment.
 *
 * ## Raising a Concern from a Non-conformance lives here (issue #208)
 *
 * A Non-conformance's cause is answered in the Action log, and the Quality
 * Module is where the Non-conformance is read — so the obvious home for "raise
 * a Concern from this record" is `quality`. It is not where it lives, and the
 * reason is the boundary rather than taste:
 *
 *   - `quality` requires only `people`'s entry point (issue #203's own
 *     acceptance criterion, which `npm run lint`'s boundary checker enforces),
 *     so it cannot call into `actions` at all;
 *   - a Module's entry point "may only expose read-only lookups that return a
 *     value … never a write" (AGENTS.md §4), so even if `quality` could reach
 *     `actions`, `actions` could not offer it a way to create a Concern; and
 *   - what a Concern *is* when it is first written — its number from
 *     `next_document_number`, its title, its `raised_by`, its cycle-1 Plan row
 *     — is this Module's own knowledge. Re-implementing it in `quality` would
 *     be the second implementation of the Action log's rules that ADR-0006's
 *     "a cross-Module write that needs another Module's judgment goes through
 *     that Module's entry point" exists to prevent.
 *
 * So the route, the field validation and the write all stay here, and the
 * Quality Module reads the result by ordinary SQL join when it answers "which
 * Concerns is this Non-conformance part of" — which ADR-0006 allows in as many
 * words, because a Module is a code seam and not a data seam. The link table
 * (`concern_nonconformances`, migration 1800000000000) is this Module's for
 * the same reason: it is the Concern's own record of what it answers, sitting
 * beside the `quality_issue_id` source column that records where the Concern
 * was raised from. What crosses the boundary in the other direction is a read:
 * `listLinkedNonconformances` below joins `quality_issues`, `products`,
 * `defect_codes` and `org_units` the way `assets.js` joins `org_units`, and
 * never writes a Quality row.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// Mirror the CHECK constraint on action_items.action_type (as of migration
// 1799500000000) so a bad value is a 400 with a clear message rather than a raw
// constraint violation. The order is the order a person meets them in: what
// was found wrong, then the measures that answer it, then the kinds that
// answer nothing.
const ACTION_TYPES = [
  'concern',
  'containment',
  'countermeasure',
  'preventive',
  'improvement',
  'routine'
];

// Mirror the CHECK constraint on action_items.status. Also the two sets a
// read filters on: OPEN_STATUSES is what "the register" means by default, and
// is the same predicate `action_items_open_idx` and the baseline's own
// v_open_actions are built on.
const ACTION_STATUSES = ['open', 'in_progress', 'blocked', 'done', 'cancelled'];
const OPEN_STATUSES = ['open', 'in_progress', 'blocked'];

// The four phases of one turn of the cycle, in the order they are worked
// (ADR-0033). Deliberately not a state set on the Action: the Action's own
// status is the coarse five above, and these are what a person reads.
const PHASES = ['plan', 'do', 'check', 'act'];

// The three kinds of work that answer a problem (issue #178). A Concern is the
// thing being answered and a Routine action answers nothing, so neither can be
// raised against one.
const MEASURE_TYPES = ['containment', 'countermeasure', 'preventive'];

// A Check's two verdicts. `not_effective` is the one that keeps the circle a
// circle: it opens the next cycle's Plan rather than the Act.
const CHECK_OUTCOMES = ['effective', 'not_effective'];

// `action_items_priority_check`: 1 is worst. The column's own DEFAULT is 3.
const PRIORITIES = [1, 2, 3, 4, 5];

// The register is a Site's open actions plus, on request, its history — and a
// history is unbounded in a way an open list is not. Past this many rows the
// answer is still honest about being partial (ADR-0026's rule for a bounded
// list, applied to a register rather than to a suggestion list): the response
// says `truncated`, the client says so on screen, and the caller narrows by
// Org Unit, by status or by owner. The limit is deliberately generous — this
// is a management list, not a search — and it exists so that one Site's
// decade of closed concerns can never be a single unbounded response.
const ACTION_LIST_LIMIT = 200;

// Every column the Module hands back, named once — the shape ASSET_COLUMNS and
// WORK_ORDER_COLUMNS already use. The joins are LEFT because an Action's owner
// is optional (a concern nobody has taken yet is a real state the register has
// to render) and because `raised_by` is null for an Account that is not an
// Employee (CONTEXT.md's Account entry: an administrator need not be one).
const ACTION_COLUMNS = `
  ai.id, ai.action_no, ai.title, ai.description, ai.action_type, ai.pillar_code,
  ai.org_unit_id, ai.owner_employee_id, ai.raised_by, ai.raised_at,
  to_char(ai.due_date, 'YYYY-MM-DD') AS due_date, ai.priority, ai.status,
  ai.completed_at, ai.closure_note,
  -- The register's own judgement about today, computed rather than stored: a
  -- row's status says whether it is finished, and this says whether it is
  -- late, which is a fact about the calendar and not about the record.
  (ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE) AS is_overdue,
  CASE WHEN ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE
       THEN (CURRENT_DATE - ai.due_date) END AS days_overdue,
  ai.escalated_to_org_unit_id, ai.escalated_at, ai.source_type,
  -- The Non-conformance this Concern was raised from, if it was raised from
  -- one (issue #208). Read here rather than derived from the link table, so
  -- that "where did this Concern come from" is answerable from the Action's
  -- own row — which is the whole reason the source column exists beside the
  -- join table.
  ai.quality_issue_id,
  ai.created_at, ai.updated_at,
  ou.code AS org_unit_code, ou.name AS org_unit_name, ou.site_id,
  e.display_name AS owner_name,
  rb.display_name AS raised_by_name,
  esc.code AS escalated_to_org_unit_code, esc.name AS escalated_to_org_unit_name,
  op.phase AS open_phase, op.cycle AS open_phase_cycle,
  to_char(op.due_date, 'YYYY-MM-DD') AS open_phase_due_date,
  op.owner_employee_id AS open_phase_owner_id,
  ope.display_name AS open_phase_owner_name,
  -- The CAPA opened on this Action, if one has been (issue #209). Carried on
  -- every row rather than only on the detail read, because whether a Concern
  -- already has an investigation is a fact about the Concern: the Screen that
  -- shows it offers opening one or links to the one it has, and the register's
  -- own row should be able to say so without a second read.
  ai.capa_id, cp.capa_no, cp.status AS capa_status,
  ai.parent_action_item_id,
  par.action_no AS parent_action_no, par.title AS parent_title,
  par.action_type AS parent_action_type, par.status AS parent_status,
  mc.measure_count, mc.countermeasure_count
`;

const ACTION_JOINS = `
  FROM action_items ai
  JOIN org_units ou ON ou.id = ai.org_unit_id
  LEFT JOIN employees e ON e.id = ai.owner_employee_id
  LEFT JOIN employees rb ON rb.id = ai.raised_by
  LEFT JOIN org_units esc ON esc.id = ai.escalated_to_org_unit_id
  -- The phase the Action is waiting on, if any. A lateral join rather than a
  -- second round trip per row: the register's whole point is the next thing
  -- due, and the open phase index is what this reads.
  LEFT JOIN LATERAL (
    SELECT p.phase, p.cycle, p.due_date, p.owner_employee_id
      FROM action_phases p
     WHERE p.action_item_id = ai.id AND p.completed_at IS NULL
     ORDER BY p.cycle ASC
     LIMIT 1
  ) op ON TRUE
  LEFT JOIN employees ope ON ope.id = op.owner_employee_id
  -- The CAPA opened on this Action (issue #209). At most one row, by the
  -- partial unique index action_items_capa_id_once; null for everything that
  -- has not been turned into an investigation, which is most of the log.
  LEFT JOIN capas cp ON cp.id = ai.capa_id
  -- The Concern this Action answers, if it answers one (issue #178).
  LEFT JOIN action_items par ON par.id = ai.parent_action_item_id
  -- How many measures answer this Action, and how many of them are
  -- countermeasures — the register's own "a concern with no countermeasure is
  -- visible without opening it" (issue #179 refuses closing exactly that).
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS measure_count,
           COUNT(*) FILTER (WHERE m.action_type = 'countermeasure') AS countermeasure_count
      FROM action_items m
     WHERE m.parent_action_item_id = ai.id
  ) mc ON TRUE
`;

function toAction(row) {
  return {
    id: row.id,
    actionNo: row.action_no,
    title: row.title,
    description: row.description,
    actionType: row.action_type,
    pillarCode: row.pillar_code,
    orgUnitId: row.org_unit_id,
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    siteId: row.site_id,
    ownerEmployeeId: row.owner_employee_id,
    ownerName: row.owner_name,
    raisedByEmployeeId: row.raised_by,
    raisedByName: row.raised_by_name,
    raisedAt: row.raised_at,
    dueDate: row.due_date,
    isOverdue: row.is_overdue,
    daysOverdue: row.days_overdue,
    priority: row.priority,
    status: row.status,
    completedAt: row.completed_at,
    closureNote: row.closure_note,
    escalatedToOrgUnitId: row.escalated_to_org_unit_id,
    escalatedToOrgUnitCode: row.escalated_to_org_unit_code,
    escalatedToOrgUnitName: row.escalated_to_org_unit_name,
    escalatedAt: row.escalated_at,
    sourceType: row.source_type,
    // The Non-conformance this Action was raised from (issue #208) — null for
    // every Action this Module raises standalone, and for a Concern raised
    // from anything else. It is provenance rather than the link list: a
    // Concern linked to four Non-conformances names all four in `nonconformances`
    // on its detail read, and this names the one it came from.
    sourceNonconformanceId: row.quality_issue_id ?? null,
    // The CAPA opened on this Action (issue #209) — null for every Action but
    // a Concern somebody has opened an investigation on, which is the rule the
    // check constraint `action_items_capa_is_a_concern` keeps. Named rather
    // than nested: a reader of a measure or a register row needs to know that
    // the problem behind it is under investigation, not to receive that
    // investigation here.
    capa: row.capa_id
      ? { id: String(row.capa_id), capaNo: row.capa_no, status: row.capa_status }
      : null,
    parentId: row.parent_action_item_id,
    measureCount: Number(row.measure_count ?? 0),
    countermeasureCount: Number(row.countermeasure_count ?? 0),
    // The phase the Action is waiting on (issue #177) — null for an Action
    // whose cycle is complete.
    openPhase: row.open_phase
      ? {
          phase: row.open_phase,
          cycle: row.open_phase_cycle,
          dueDate: row.open_phase_due_date,
          ownerEmployeeId: row.open_phase_owner_id,
          ownerName: row.open_phase_owner_name
        }
      : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// The detail read (issue #176, grown by #177 and #208). `parent`, `measures`
// and `nonconformances` are part of the shape from the start so that no client
// read has to change when a later issue fills them: an Action that answers
// nothing has an empty measures array and an empty nonconformances array,
// which is not the same thing as a missing field. `phases` carries every cycle
// the Action has been round, oldest first — the record of a Check that failed
// and sent it round again is the point of keeping them (ADR-0033).
function toActionDetail(row, phases = [], measures = [], nonconformances = []) {
  return {
    ...toAction(row),
    // The Concern this answers, named rather than nested: a caller reading a
    // measure needs to know what it is about and to be able to go there, not to
    // receive that Concern's own measures and phases again.
    parent: row.parent_action_item_id
      ? {
          id: row.parent_action_item_id,
          actionNo: row.parent_action_no,
          title: row.parent_title,
          actionType: row.parent_action_type,
          status: row.parent_status
        }
      : null,
    measures,
    phases,
    // What this Concern answers (issue #208): the Non-conformance it was raised
    // from and every occurrence linked to it since, named with the number,
    // Product, Defect code and quantity a reader needs. Empty for every Action
    // that answers no Non-conformance, which is every Action but a Concern
    // raised from one or linked to one.
    nonconformances
  };
}

// The Non-conformances a Concern answers (issue #208), in the shape the
// Concern's own Screen reads: the number a person quotes, what was made wrong
// (Product), why (Defect code) and how much of it. A cross-Module read done as
// an ordinary SQL join — `products`, `defect_codes` and `org_units` are
// Quality's and People's tables, and ADR-0006 makes that a query rather than a
// boundary violation. Nothing here is written: this Module creates no Quality
// row, ever.
const LINKED_NONCONFORMANCE_COLUMNS = `
  qi.id, qi.issue_no, qi.status, qi.severity, qi.detection_point,
  qi.quantity_affected, qi.uom_code, qi.lot_ref, qi.detected_at,
  qi.org_unit_id, ou.name AS org_unit_name,
  qi.product_id, p.code AS product_code, p.name AS product_name,
  qi.defect_code_id, dc.code AS defect_code_code, dc.name AS defect_code_name,
  cn.linked_at,
  -- Whether this is the Non-conformance the Concern was raised from, which is
  -- a different fact from "linked": it is the occurrence that started it, it
  -- is what the source column records, and the service refuses to unlink it.
  (cn.quality_issue_id = ai.quality_issue_id) AS is_source
`;

const LINKED_NONCONFORMANCE_JOINS = `
  FROM concern_nonconformances cn
  JOIN action_items ai ON ai.id = cn.action_item_id
  JOIN quality_issues qi ON qi.id = cn.quality_issue_id
  JOIN org_units ou ON ou.id = qi.org_unit_id
  JOIN products p ON p.id = qi.product_id
  JOIN defect_codes dc ON dc.id = qi.defect_code_id
`;

function toLinkedNonconformance(row) {
  return {
    id: row.id,
    issueNo: row.issue_no,
    status: row.status,
    severity: row.severity,
    detectionPoint: row.detection_point,
    quantityAffected: Number(row.quantity_affected),
    uomCode: row.uom_code,
    lotRef: row.lot_ref ?? null,
    detectedAt: row.detected_at,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    productId: row.product_id,
    productCode: row.product_code,
    productName: row.product_name,
    defectCodeId: row.defect_code_id,
    defectCodeCode: row.defect_code_code,
    defectCodeName: row.defect_code_name,
    // The one it was raised from reads first, then the occurrences gathered
    // later, oldest first: a reader wants the origin before the additions.
    isSource: row.is_source === true,
    linkedAt: row.linked_at
  };
}

/**
 * The Non-conformances one Concern answers (issue #208), each with the number,
 * Product, Defect code and quantity a reader needs — and whether it is the one
 * the Concern was raised from.
 *
 * Any Action may be asked, and a measure answers no Non-conformance at all, so
 * an empty list is a real and common answer rather than a missing field: a
 * Concern raised standalone has none, and the Screen says so.
 *
 * A cross-Module read rather than another Module's lookup, deliberately: what
 * this needs is a join, not Quality's judgment about a record (ADR-0006's own
 * distinction), and going through Quality's entry point for a four-table join
 * would be asking a Module a question it cannot answer about itself.
 */
async function listLinkedNonconformances(actionItemId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${LINKED_NONCONFORMANCE_COLUMNS}
     ${LINKED_NONCONFORMANCE_JOINS}
      WHERE cn.action_item_id = $1
      ORDER BY (cn.quality_issue_id = ai.quality_issue_id) DESC, cn.linked_at, cn.id`,
    [actionItemId]
  );
  return rows.map(toLinkedNonconformance);
}

// The detail read, taken on a connection the caller names — so a write
// mid-transaction answers with the row it just wrote rather than with what the
// pool can see (which, for a write inside an uncommitted transaction, is the
// row before it).
async function readActionDetail(client, actionItemId) {
  const { rows } = await client.query(
    `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
    [actionItemId]
  );
  return toActionDetail(
    rows[0],
    await listPhases(actionItemId, client),
    await listMeasures(actionItemId, client),
    await listLinkedNonconformances(actionItemId, client)
  );
}

// A measure's ordering on a Concern's own Screen: containment first (the thing
// that stops the bleeding, which is what a reader looks for), then the
// countermeasure, then anything preventive, and within a kind the soonest due.
const MEASURE_ORDER = `
  CASE ai.action_type WHEN 'containment' THEN 1 WHEN 'countermeasure' THEN 2 ELSE 3 END,
  ai.due_date ASC NULLS LAST,
  ai.action_no ASC
`;

function toPhase(row) {
  return {
    id: row.id,
    actionItemId: row.action_item_id,
    cycle: row.cycle,
    phase: row.phase,
    ownerEmployeeId: row.owner_employee_id,
    ownerName: row.owner_name,
    dueDate: row.due_date,
    completedAt: row.completed_at,
    outcome: row.outcome,
    note: row.note
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

function requireMemberOf(field, value, allowed) {
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
}

// A DATE with no time, strictly — the same parse board-routes.js applies to its
// own date parameter, and for the same reason: the regex alone would let
// 2026-13-40 through to Postgres, where `::date` raises a SQLSTATE with no
// `.status` and the caller would see a 500 for what is plainly a bad request.
function parseDateOnly(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

// Postgres' own constraint names, mapped to messages this Module wrote. The
// same shape assets.js's mapAssetWriteError uses, and the same rule
// src/index.js's terminal handler states: `error.message` is never echoed,
// because a database error string names tables and columns.
function mapActionWriteError(error) {
  if (error.code === '23503') {
    return httpError(400, 'that is not a valid reference');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Action');
  }
  if (error.code === 'P0001') {
    return httpError(400, error.message);
  }
  return error;
}

// The five Pillars, in the catalogue's own order — what the raise form offers
// as "which Pillar does this threaten". Read from the catalogue rather than
// restated here: sqdcp_pillars is seeded by the baseline, and a second copy of
// its codes in this file is the drift the join exists to avoid.
async function listPillars() {
  const { rows } = await getPool().query(
    'SELECT code, name, description, sort_order FROM sqdcp_pillars ORDER BY sort_order'
  );
  return rows.map((row) => ({
    code: row.code,
    name: row.name,
    description: row.description,
    sortOrder: row.sort_order
  }));
}

/**
 * The Site's action log — open by default, history on request (issue #176).
 *
 * Site-wide with no Grant filter, per ADR-0032: `?orgUnitId=` narrows the list
 * to one *area* and everything beneath it, never to what the caller is
 * granted. A supervisor who can see only their own line's concerns cannot plan
 * around the line beside theirs, and a tier meeting whose members each hold a
 * different list is not a tier meeting.
 *
 * Ordering is fixed rather than a parameter, and it is the order the register
 * is read for: what is overdue first (worst overdue first), then what is due
 * soonest, then priority, then whatever was raised most recently.
 */
async function listActionsAtSite(
  siteId,
  {
    orgUnitPath = null,
    status = null,
    actionType = null,
    ownerEmployeeId = null,
    pillarCode = null,
    escalatedToOrgUnitId = null,
    includeHistory = false
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
    conditions.push(`ai.status = $${params.length}`);
  }
  if (actionType !== null) {
    params.push(actionType);
    conditions.push(`ai.action_type = $${params.length}`);
  }
  if (ownerEmployeeId !== null) {
    params.push(ownerEmployeeId);
    conditions.push(`ai.owner_employee_id = $${params.length}`);
  }
  if (pillarCode !== null) {
    params.push(pillarCode);
    conditions.push(`ai.pillar_code = $${params.length}`);
  }
  // What was handed up to one Org Unit — the plant manager's own queue
  // (issue #180). A convenience filter over an already-visible register, the
  // same rule `ownerEmployeeId` keeps: it narrows by *area of responsibility*,
  // never by entitlement.
  if (escalatedToOrgUnitId !== null) {
    params.push(escalatedToOrgUnitId);
    conditions.push(`ai.escalated_to_org_unit_id = $${params.length}`);
  }
  if (!includeHistory) {
    conditions.push(`ai.status IN ('open', 'in_progress', 'blocked')`);
  }

  // One row past the limit, so "there is more" is a fact rather than a guess.
  const { rows } = await getPool().query(
    `SELECT ${ACTION_COLUMNS}
     ${ACTION_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY (ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE) DESC,
              ai.due_date ASC NULLS LAST,
              ai.priority ASC,
              ai.raised_at DESC
     LIMIT ${ACTION_LIST_LIMIT + 1}`,
    params
  );

  const truncated = rows.length > ACTION_LIST_LIMIT;
  return {
    actions: rows.slice(0, ACTION_LIST_LIMIT).map(toAction),
    truncated
  };
}

// The null-returning form, mirroring findAsset/findOrgUnit exactly: a
// malformed id resolves to null rather than reaching Postgres as a BIGINT
// parameter (SQLSTATE 22P02, no `.status`, so an unhandled 500 where every
// other route answers a clean 404).
async function findAction(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
    [id]
  );
  return rows[0] ? toAction(rows[0]) : null;
}

async function getActionDetail(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return toActionDetail(
    rows[0],
    await listPhases(rows[0].id),
    await listMeasures(rows[0].id),
    // What this Concern answers (issue #208). Read on every detail read, the
    // same way its measures are: the Screen that shows a Concern shows the
    // occurrences behind it.
    await listLinkedNonconformances(rows[0].id)
  );
}

/**
 * The Actions answering one Concern, in the order a person reads them.
 *
 * A measure is an Action in its own right, so each row carries its own status
 * and the phase it is waiting on: "the containment is done and the
 * countermeasure is still being worked" is a sentence this read has to make
 * possible.
 */
async function listMeasures(actionItemId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS}
      WHERE ai.parent_action_item_id = $1
      ORDER BY ${MEASURE_ORDER}`,
    [actionItemId]
  );
  return rows.map(toAction);
}

/**
 * Every phase of every cycle the Action has been round, oldest first, in the
 * order a person works them. Read from the page's own connection where a
 * transition is mid-transaction, so the caller sees the row it just wrote.
 */
async function listPhases(actionItemId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT p.id, p.action_item_id, p.cycle, p.phase, p.owner_employee_id,
            e.display_name AS owner_name,
            to_char(p.due_date, 'YYYY-MM-DD') AS due_date,
            p.completed_at, p.outcome, p.note
       FROM action_phases p
       LEFT JOIN employees e ON e.id = p.owner_employee_id
      WHERE p.action_item_id = $1
      ORDER BY p.cycle ASC,
               CASE p.phase WHEN 'plan' THEN 1 WHEN 'do' THEN 2
                            WHEN 'check' THEN 3 ELSE 4 END`,
    [actionItemId]
  );
  return rows.map(toPhase);
}

/**
 * Raises one Action (issue #176).
 *
 * Every field is validated here rather than in the route, because each is a
 * fact about the record's own fields — AGENTS.md §6's division, the same one
 * assets.js's createAsset follows. What is NOT validated here is anything
 * about another Module's record: the Org Unit's existence, its Site, and the
 * caller's entitlement to raise at it are action-routes.js's business, and the
 * Employee named as owner is resolved through People's entry point there.
 *
 * The number is the Site's own, through the baseline's `next_document_number`
 * — `AC-<site>-<year>-00001`, the shape a Work order's own number already has
 * — rather than the column's global DEFAULT, so a concern quoted in a meeting
 * reads like the job beside it. The DEFAULT stays as the fallback for a row
 * written outside a request (a seed, a future integration).
 *
 * `raised_by` is the caller's own Employee link where they have one and null
 * where they do not: CONTEXT.md's Account entry is explicit that an
 * administrator need not be an Employee, and the Request's own create path
 * writes the same expression. `created_by`/`updated_by` are the baseline's
 * trigger's business (`app.user_id`), not a route's.
 */
async function createAction(
  {
    orgUnitId,
    title,
    description = null,
    actionType = 'concern',
    pillarCode = null,
    ownerEmployeeId = null,
    dueDate = null,
    priority = 3
  },
  accountId,
  { raisedBy = null, qualityIssueId = null } = {}
) {
  requireNonEmptyString('title', title);
  requireMemberOf('actionType', actionType, ACTION_TYPES);

  if (description !== null && typeof description !== 'string') {
    throw httpError(400, 'description must be text');
  }

  let due = null;
  if (dueDate !== null && dueDate !== undefined) {
    due = parseDateOnly(dueDate);
    if (due === null) throw httpError(400, 'dueDate must be a valid YYYY-MM-DD date');
  }

  const priorityValue = typeof priority === 'string' ? Number(priority) : priority;
  if (!PRIORITIES.includes(priorityValue)) {
    throw httpError(400, `priority must be one of: ${PRIORITIES.join(', ')}`);
  }

  if (pillarCode !== null) {
    const pillars = await listPillars();
    if (!pillars.some((pillar) => pillar.code === pillarCode)) {
      throw httpError(400, `pillarCode must be one of: ${pillars.map((p) => p.code).join(', ')}`);
    }
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [inserted] } = await client.query(
        `WITH site AS (
           SELECT s.code AS code FROM sites s
            WHERE s.id = (SELECT site_id FROM org_units WHERE id = $1)
         )
         INSERT INTO action_items
           (action_no, org_unit_id, title, description, action_type, pillar_code,
            owner_employee_id, due_date, priority, raised_by, quality_issue_id)
         VALUES
           (next_document_number('AC', (SELECT code FROM site), EXTRACT(YEAR FROM now())::int),
            $1, $2, $3, $4, $5, $6, $7::date, $8, $9, $10)
         RETURNING id`,
        [
          orgUnitId,
          title.trim(),
          description,
          actionType,
          pillarCode,
          ownerEmployeeId,
          due,
          priorityValue,
          raisedBy,
          qualityIssueId
        ]
      );

      // The Non-conformance it was raised from is also a link, in the same
      // transaction as the row that names it as its source (issue #208). Two
      // writes rather than one because they are two facts: the source column
      // is provenance ("where did this Concern come from") and the link table
      // is what the Concern answers ("every occurrence of this problem"). A
      // reader of either record asks one of them, and neither is derived from
      // the other.
      if (qualityIssueId !== null) {
        await client.query(
          `INSERT INTO concern_nonconformances (action_item_id, quality_issue_id)
           VALUES ($1, $2)`,
          [inserted.id, qualityIssueId]
        );
      }

      // Born with its cycle-1 Plan (issue #177). An Action with no Plan is a
      // wish, and the Plan's own owner and due date are the Action's — copied
      // here rather than left to a second write, so no phase exists without
      // both.
      await client.query(
        `INSERT INTO action_phases (action_item_id, cycle, phase, owner_employee_id, due_date)
         SELECT id, 1, 'plan', owner_employee_id, due_date
           FROM action_items WHERE id = $1`,
        [inserted.id]
      );

      const { rows } = await client.query(
        `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
        [inserted.id]
      );
      return toAction(rows[0]);
    });
  } catch (error) {
    throw mapActionWriteError(error);
  }
}

/**
 * Raises one measure against the Concern it answers (issue #178).
 *
 * Two refusals live here rather than in the route, because they are facts about
 * the parent row: it must exist (404) and it must be a Concern (400) — a
 * measure answers a Concern and nothing else, which is also what makes a
 * measure of a measure impossible. Both are read under `FOR UPDATE`, so the
 * parent cannot change between the check and the insert.
 *
 * The measure is a whole Action of its own: its own number from its own Org
 * Unit's Site sequence, its own cycle-1 Plan, its own owner and due date. The
 * only thing that makes it a measure is `parent_action_item_id`.
 *
 * `orgUnitId` defaults to the Concern's own Org Unit, which is where a
 * countermeasure on a line normally sits — and it is deliberately NOT read from
 * the parent as a rule: a measure may be raised wherever its work happens (a
 * store, a supplier's line), which is why raising one needs a write Grant at
 * the measure's own Org Unit and not at the Concern's.
 */
async function createMeasure(
  parentActionItemId,
  {
    actionType,
    title,
    description = null,
    orgUnitId = null,
    ownerEmployeeId = null,
    dueDate = null,
    priority = 3
  },
  accountId,
  { raisedBy = null } = {}
) {
  requireNonEmptyString('title', title);
  requireMemberOf('actionType', actionType, MEASURE_TYPES);

  let due = null;
  if (dueDate !== null && dueDate !== undefined) {
    due = parseDateOnly(dueDate);
    if (due === null) throw httpError(400, 'dueDate must be a valid YYYY-MM-DD date');
  }

  const priorityValue = typeof priority === 'string' ? Number(priority) : priority;
  if (!PRIORITIES.includes(priorityValue)) {
    throw httpError(400, `priority must be one of: ${PRIORITIES.join(', ')}`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [parent] } = await client.query(
        `SELECT id, action_type, parent_action_item_id, org_unit_id
           FROM action_items WHERE id = $1 FOR UPDATE`,
        [parentActionItemId]
      );
      if (!parent) throw notFound('Concern');
      // One refusal, not two. The one-level rule — "a measure is never
      // answered by another measure" — is a consequence of this check rather
      // than a second branch beside it: only a Concern may be answered, and a
      // Concern has no parent by construction, because the only writer that
      // sets `parent_action_item_id` sets it to the three measure types and a
      // Concern is not one of them. A separate "the parent must not have a
      // parent" check would be unreachable code with a message nobody could
      // ever read.
      if (parent.action_type !== 'concern') {
        throw httpError(400, 'a measure answers a Concern, and that Action is not one');
      }

      const targetOrgUnitId = orgUnitId ?? parent.org_unit_id;

      const { rows: [inserted] } = await client.query(
        `WITH site AS (
           SELECT s.code AS code FROM sites s
            WHERE s.id = (SELECT site_id FROM org_units WHERE id = $1)
         )
         INSERT INTO action_items
           (action_no, org_unit_id, title, description, action_type,
            owner_employee_id, due_date, priority, raised_by, parent_action_item_id)
         VALUES
           (next_document_number('AC', (SELECT code FROM site), EXTRACT(YEAR FROM now())::int),
            $1, $2, $3, $4, $5, $6::date, $7, $8, $9)
         RETURNING id`,
        [
          targetOrgUnitId,
          title.trim(),
          description,
          actionType,
          ownerEmployeeId,
          due,
          priorityValue,
          raisedBy,
          parent.id
        ]
      );

      await client.query(
        `INSERT INTO action_phases (action_item_id, cycle, phase, owner_employee_id, due_date)
         SELECT id, 1, 'plan', owner_employee_id, due_date
           FROM action_items WHERE id = $1`,
        [inserted.id]
      );

      const { rows } = await client.query(
        `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
        [inserted.id]
      );
      return toAction(rows[0]);
    });
  } catch (error) {
    throw mapActionWriteError(error);
  }
}

/**
 * Advances one Action's cycle by completing its open phase (issue #177).
 *
 * One route, one phase, one note — and this function is the whole state
 * machine, which ADR-0019 argues belongs here rather than in the route or in a
 * new CHECK constraint: whether `plan → do` is a legal move is a fact about an
 * Action, and the guard is a `SELECT … FOR UPDATE` inside the transaction, so
 * two callers racing the same phase serialize and the loser reads the
 * now-current phase and gets its 409.
 *
 * What completing each phase does:
 *
 *   plan            → opens the Do; the Action becomes `in_progress`
 *   do              → opens the Check
 *   check effective → opens the Act
 *   check not_effective → opens the NEXT cycle's Plan, and the Action stays
 *                     `in_progress`: the circle is the point, and the round
 *                     that failed is kept as the evidence that another was
 *                     needed
 *   act             → closes the Action (`done`) — issue #179 adds the two
 *                     refusals that guard this step
 *
 * A note is required on every completion. A phase marked complete with no
 * evidence is the "list of good intentions" the baseline's own CAPA header
 * names, and this Module exists to refuse it. `outcome` is required on a Check
 * and refused everywhere else: on a Check it is the verdict, and on the other
 * three phases there is nothing it could mean.
 */
async function completePhase(actionItemId, phase, { note, outcome = null }, accountId) {
  requireMemberOf('phase', phase, PHASES);
  requireNonEmptyString('note', note);

  if (phase === 'check') {
    requireMemberOf('outcome', outcome, CHECK_OUTCOMES);
  } else if (outcome !== null && outcome !== undefined) {
    throw httpError(400, 'outcome is only recorded on a Check');
  }

  return withActor(accountId, async (client) => {
    const { rows: [action] } = await client.query(
      'SELECT id, action_type, status FROM action_items WHERE id = $1 FOR UPDATE',
      [actionItemId]
    );
    if (!action) throw notFound('Action');
    if (action.status === 'done') {
      throw httpError(409, 'this Action is closed, so no phase of it can be completed');
    }
    if (action.status === 'cancelled') {
      throw httpError(409, 'this Action was cancelled, so no phase of it can be completed');
    }

    const { rows: [open] } = await client.query(
      `SELECT cycle, phase FROM action_phases
        WHERE action_item_id = $1 AND completed_at IS NULL
        ORDER BY cycle ASC
        LIMIT 1
        FOR UPDATE`,
      [actionItemId]
    );
    if (!open) {
      throw httpError(409, 'this Action has no open phase');
    }
    if (open.phase !== phase) {
      throw httpError(409, `this Action is waiting on its ${open.phase} phase, not its ${phase}`);
    }

    // Nothing closes a Concern unproven (issue #179, ADR-0033). Two refusals,
    // and they are the Concern's own: a measure's Act is not held to either,
    // because a Containment answers a Concern and has no countermeasures of
    // its own — holding it to the same rule would make containment work
    // unclosable.
    //
    // Both are read under `FOR UPDATE`, so a measure raised between the check
    // and the write cannot slip under a Concern that has already been judged.
    if (phase === 'act' && action.action_type === 'concern') {
      const { rows: measures } = await client.query(
        `SELECT action_no, title, action_type, status
           FROM action_items
          WHERE parent_action_item_id = $1
          FOR UPDATE`,
        [actionItemId]
      );

      // Outstanding work first, and deliberately: when a countermeasure is
      // half-done both rules are true, and "AC-… is still open" names the work
      // somebody has to finish, where "no countermeasure that held" would send
      // the reader looking for one they already have.
      const outstanding = measures.filter((measure) =>
        OPEN_STATUSES.includes(measure.status)
      );
      if (outstanding.length > 0) {
        // The numbers first — a reader wants to know *which* — and then the
        // step, because a measure is an Action of its own whose cycle is run
        // exactly as this one's is, and nothing on the Screen they came from
        // says so (issue #183: the sentence named the problem and stopped).
        throw httpError(
          409,
          `this Concern still has ${outstanding.length} open ` +
            `${outstanding.length === 1 ? 'measure' : 'measures'}: ` +
            outstanding.map((measure) => measure.action_no).join(', ') +
            '. A measure closes when its own cycle reaches its Act, so open each one and ' +
            'complete its phases'
        );
      }

      // Nothing open, then: is anything behind this that actually fixed it? A
      // Containment alone is not an answer — the Concern was contained, never
      // answered — which is why this counts countermeasures rather than
      // measures.
      const closed = measures.some(
        (measure) => measure.action_type === 'countermeasure' && measure.status === 'done'
      );
      if (!closed) {
        throw httpError(
          409,
          'this Concern has no countermeasure that held, so it cannot be closed'
        );
      }
    }

    await client.query(
      `UPDATE action_phases
          SET completed_at = now(), note = $3, outcome = $4
        WHERE action_item_id = $1 AND cycle = $2 AND phase = $5`,
      [actionItemId, open.cycle, note.trim(), phase === 'check' ? outcome : null, phase]
    );

    const next = nextPhase(open, outcome);
    if (next) {
      await client.query(
        `INSERT INTO action_phases (action_item_id, cycle, phase, owner_employee_id, due_date)
         SELECT id, $2, $3, owner_employee_id, due_date
           FROM action_items WHERE id = $1`,
        [actionItemId, next.cycle, next.phase]
      );
    }

    const status = phase === 'act' ? 'done' : 'in_progress';
    await client.query(
      `UPDATE action_items
          SET status = $2,
              completed_at = CASE WHEN $2 = 'done' THEN now() ELSE completed_at END
        WHERE id = $1`,
      [actionItemId, status]
    );

    const { rows } = await client.query(
      `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
      [actionItemId]
    );
    return toActionDetail(rows[0], await listPhases(actionItemId, client));
  });
}

// Which phase completing this one opens, if any. A Check that found the
// countermeasure did not hold opens the next round rather than the Act: that
// single line is what makes this a circle (ADR-0033).
function nextPhase(open, outcome) {
  switch (open.phase) {
    case 'plan':
      return { cycle: open.cycle, phase: 'do' };
    case 'do':
      return { cycle: open.cycle, phase: 'check' };
    case 'check':
      return outcome === 'effective'
        ? { cycle: open.cycle, phase: 'act' }
        : { cycle: open.cycle + 1, phase: 'plan' };
    default:
      return null;
  }
}

/**
 * Calls one Action off (issue #179).
 *
 * The opposite rule from closing, on purpose: a `reason` is optional, because
 * undoing a mistake should not demand prose (`cancelWorkOrder`'s own argument),
 * and cancelling writes no evidence — it withdraws a claim. It is written to
 * `closure_note`, COALESCEd, so cancelling without a reason never wipes a note
 * that was already there; `action_items_done_has_time` makes the timestamp
 * mandatory with the status, which is the database's backstop rather than the
 * primary defence.
 *
 * One refusal beyond "already ended", and it is this Module's own discipline
 * rather than a rule the ticket asked for: a Concern with a measure still open
 * cannot be called off, because that would leave live work pointing at a
 * decision that it was never a problem. Those measures are cancelled on their
 * own, or the Concern is closed properly.
 */
async function cancelAction(actionItemId, { reason = null } = {}, accountId) {
  return withActor(accountId, async (client) => {
    const { rows: [action] } = await client.query(
      'SELECT id, action_type, status FROM action_items WHERE id = $1 FOR UPDATE',
      [actionItemId]
    );
    if (!action) throw notFound('Action');
    if (action.status === 'done') {
      throw httpError(409, 'this Action is closed, so it cannot be cancelled');
    }
    if (action.status === 'cancelled') {
      throw httpError(409, 'this Action was already cancelled');
    }

    if (action.action_type === 'concern') {
      const { rows: outstanding } = await client.query(
        `SELECT action_no FROM action_items
          WHERE parent_action_item_id = $1 AND status = ANY($2)
          FOR UPDATE`,
        [actionItemId, OPEN_STATUSES]
      );
      if (outstanding.length > 0) {
        // The way out of *this* refusal is not running the measure: cancelling
        // it is enough, which is the sentence a reader needs here.
        throw httpError(
          409,
          `this Concern still has ${outstanding.length} open ` +
            `${outstanding.length === 1 ? 'measure' : 'measures'}: ` +
            outstanding.map((measure) => measure.action_no).join(', ') +
            '. Run each one to its Act, or cancel it if it is not going to be done, and then ' +
            'this Concern can be called off'
        );
      }
    }

    await client.query(
      `UPDATE action_items
          SET status = 'cancelled',
              completed_at = now(),
              closure_note = COALESCE($2, closure_note)
        WHERE id = $1`,
      [actionItemId, reason === null ? null : String(reason).trim() || null]
    );

    const { rows } = await client.query(
      `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
      [actionItemId]
    );
    return toActionDetail(rows[0], await listPhases(actionItemId, client), await listMeasures(actionItemId, client));
  });
}

// A link could be refused by the database for one reason this file turns into
// a clean 409 rather than a 500: the uniqueness constraint that makes "the
// same Non-conformance twice on the same Concern" a rule rather than a
// duplicate row. The service does not check first and insert second — that is
// the race the constraint exists for — so the constraint is where the refusal
// is read from.
function mapConcernLinkWriteError(error) {
  if (error.code === '23505' && error.constraint === 'concern_nonconformances_once') {
    return httpError(409, 'this Non-conformance is already linked to this Concern');
  }
  if (error.code === '23503') {
    return httpError(404, 'Non-conformance not found');
  }
  return error;
}

/**
 * The Non-conformance a Concern is about to be raised from (issue #208) — the
 * four facts the route needs to ask its scope question and this file needs to
 * file the Concern: the record's own id and number, the Org Unit it sits at,
 * and the Site that Org Unit is in.
 *
 * Read as an ordinary SQL join rather than through Quality's entry point,
 * because what is being asked is a fact about a row this Platform shares a
 * database with rather than Quality's judgment about it (ADR-0006's own
 * distinction). Total, like findAction: a malformed id resolves to null rather
 * than reaching Postgres as a BIGINT parameter.
 */
async function findNonconformanceForConcern(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT qi.id, qi.issue_no, qi.status, qi.org_unit_id, ou.site_id
       FROM quality_issues qi
       JOIN org_units ou ON ou.id = qi.org_unit_id
      WHERE qi.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return {
    id: rows[0].id,
    issueNo: rows[0].issue_no,
    status: rows[0].status,
    orgUnitId: rows[0].org_unit_id,
    siteId: rows[0].site_id
  };
}

/**
 * Raises a Concern from a Non-conformance (issue #208).
 *
 * The Concern is the Action log's own record and is created by the Action
 * log's own rules — the same `createAction` a Concern raised from the register
 * goes through, with the Non-conformance named as its source. Nothing about
 * raising a Concern changes here: the title is required, the type is
 * `concern`, the number is the Site's own, and the cycle-1 Plan is its own.
 * What this adds is the two facts that make it a Concern *from* something: the
 * `quality_issue_id` source column and the link row, written in one
 * transaction.
 *
 * It lands at the Non-conformance's own Org Unit, and that is the whole of the
 * address: a caller naming a different Org Unit would be filing the problem
 * somewhere the problem is not. The route asks `people.canSeeSite` about the
 * Non-conformance's Site — the rule #198 fixed for raising a Concern, which is
 * the weakest of People's questions on purpose, because a Concern is a report
 * rather than a decision.
 *
 * A cancelled Non-conformance is refused with a 409: it was recorded in error
 * and withdrawn, and a problem-solving exercise raised from a row that says
 * "this never happened" is a record nobody can act on. Nothing refuses a
 * *second* Concern from the same Non-conformance, deliberately: the source
 * column records the Non-conformance a Concern came from, not the Concern a
 * Non-conformance must have — a record that turns out to need two separate
 * pieces of work is two Concerns, and the link table already says so.
 */
async function raiseConcernFromNonconformance(
  nonconformanceId,
  input,
  accountId,
  { raisedBy = null } = {}
) {
  const nonconformance = await findNonconformanceForConcern(nonconformanceId);
  if (!nonconformance) throw notFound('Non-conformance');
  if (nonconformance.status === 'cancelled') {
    throw httpError(
      409,
      'this Non-conformance was cancelled, so no Concern can be raised from it'
    );
  }

  const body = input ?? {};
  const action = await createAction(
    {
      orgUnitId: nonconformance.orgUnitId,
      title: body.title,
      description: body.description ?? null,
      actionType: 'concern',
      pillarCode: body.pillarCode ?? null,
      ownerEmployeeId: body.ownerEmployeeId ?? null,
      dueDate: body.dueDate ?? null,
      priority: body.priority ?? 3
    },
    accountId,
    { raisedBy, qualityIssueId: nonconformance.id }
  );

  // The detail read, so the answer carries the Non-conformance it was just
  // raised from rather than an empty list the caller would have to re-read.
  return getActionDetail(action.id);
}

/**
 * Links a further Non-conformance to an existing Concern (issue #208) — the
 * other half of "one problem answering several occurrences stays one
 * Concern".
 *
 * Three refusals, and each says which one it is. The Action must be a Concern
 * (400): a Containment, a Countermeasure, a Preventive action, an Improvement
 * or a Routine action answers nothing, and only a Concern carries a
 * Non-conformance — the same rule `completePhase` states for measures, said
 * about the other link. A cancelled Non-conformance is refused (409) for the
 * reason `raiseConcernFromNonconformance` gives. Linking the same one twice is
 * refused by the table's own uniqueness constraint and answered as a 409,
 * because checking first and inserting second is the race the constraint
 * exists to close.
 *
 * The Action is locked `FOR UPDATE` for the read that decides all three, so a
 * Concern cannot change kind or end between the check and the write. Whether
 * the caller may change this Concern at all is the route's business
 * (`write: true` at its Org Unit — the Action log's own rule for everything
 * that changes an Action after it is raised), and whether the Non-conformance
 * is one the caller can see is the route's too.
 */
async function linkNonconformance(actionItemId, nonconformanceId, accountId) {
  return withActor(accountId, async (client) => {
    const { rows: [action] } = await client.query(
      'SELECT id, action_type FROM action_items WHERE id = $1 FOR UPDATE',
      [actionItemId]
    );
    if (!action) throw notFound('Action');
    if (action.action_type !== 'concern') {
      throw httpError(400, 'only a Concern answers Non-conformances, and that Action is not one');
    }

    const { rows: [nonconformance] } = await client.query(
      'SELECT id, status FROM quality_issues WHERE id = $1',
      [nonconformanceId]
    );
    if (!nonconformance) throw notFound('Non-conformance');
    if (nonconformance.status === 'cancelled') {
      throw httpError(
        409,
        'this Non-conformance was cancelled, so it cannot be linked to a Concern'
      );
    }

    try {
      await client.query(
        `INSERT INTO concern_nonconformances (action_item_id, quality_issue_id)
         VALUES ($1, $2)`,
        [actionItemId, nonconformanceId]
      );
    } catch (error) {
      throw mapConcernLinkWriteError(error);
    }

    return readActionDetail(client, actionItemId);
  });
}

/**
 * Unlinks a Non-conformance from a Concern (issue #208).
 *
 * The one refusal beyond "there is no such link" (a 404) is the Non-conformance
 * the Concern was raised from, which is a 409: the source column records where
 * the Concern came from, and a Concern whose provenance names a Non-conformance
 * it no longer answers is a contradiction a reader cannot resolve. Unlinking
 * every *other* occurrence is exactly what the act is for — two occurrences
 * turn out to be unrelated problems.
 *
 * Nothing about the Non-conformance itself changes: it keeps its Dispositions,
 * its quantity history and its own number, because this removes a link and
 * never a record.
 */
async function unlinkNonconformance(actionItemId, nonconformanceId, accountId) {
  return withActor(accountId, async (client) => {
    const { rows: [action] } = await client.query(
      'SELECT id, action_type, quality_issue_id FROM action_items WHERE id = $1 FOR UPDATE',
      [actionItemId]
    );
    if (!action) throw notFound('Action');

    if (
      action.quality_issue_id !== null &&
      String(action.quality_issue_id) === String(nonconformanceId)
    ) {
      throw httpError(
        409,
        'the Non-conformance this Concern was raised from cannot be unlinked: the Concern records where it came from'
      );
    }

    const { rowCount } = await client.query(
      `DELETE FROM concern_nonconformances
        WHERE action_item_id = $1 AND quality_issue_id = $2`,
      [actionItemId, nonconformanceId]
    );
    if (rowCount === 0) {
      throw httpError(404, 'that Non-conformance is not linked to this Concern');
    }

    return readActionDetail(client, actionItemId);
  });
}

/**
 * The Org Units an Action may be handed up to (issue #180): the ancestors of
 * the Org Unit it sits at, nearest first, minus the one it is already at.
 *
 * ltree does the walking — `@>` is "is an ancestor of" — rather than a client
 * or a service climbing a parent pointer: the tree is already in the column,
 * and one implementation of that rule beats two. `nlevel` orders them so the
 * nearest superior is the first thing a picker offers, and the Action's own Org
 * Unit is excluded because handing work to the people already holding it is not
 * an escalation.
 *
 * The one it is already escalated to is excluded too, and that is the whole of
 * the "replaces rather than accumulates" rule on the read side: a second
 * escalation overwrites `escalated_to_org_unit_id` on the same row, so there is
 * no list to append to and nothing to remove — only a target that would be a
 * no-op to offer.
 *
 * An empty list is a real answer: the Action sits at the top of its Site and
 * there is nowhere above it to go.
 */
async function escalationTargets(actionItemId) {
  const { rows } = await getPool().query(
    `SELECT ancestor.id, ancestor.code, ancestor.name
       FROM action_items ai
       JOIN org_units own ON own.id = ai.org_unit_id
       JOIN org_units ancestor ON ancestor.path @> own.path
      WHERE ai.id = $1
        AND ancestor.id <> own.id
        AND (ai.escalated_to_org_unit_id IS NULL
             OR ancestor.id <> ai.escalated_to_org_unit_id)
      ORDER BY nlevel(ancestor.path) DESC, ancestor.name ASC`,
    [actionItemId]
  );

  return rows.map((row) => ({
    id: String(row.id),
    code: row.code,
    name: row.name
  }));
}

/**
 * Hands one Action up the tree (issue #180).
 *
 * The row changes in exactly two columns — who has now been told, and when —
 * and nowhere else. That is the decision rather than an unfinished
 * implementation: an escalation is not a handover. The status stays, the open
 * phase stays, the owner stays, because the line still has to run the plan; who
 * has been told is a different question from who is doing the work, and folding
 * the two into one status transition would lose the second answer.
 *
 * **The CAPA follows its Concern (issue #209).** One thing outside this row
 * does change, and it is a consequence of ADR-0034's shape rather than an
 * exception to it: a CAPA is an investigation opened on a Concern and its Org
 * Unit is the Concern's, so when the problem is handed to a higher tier the
 * investigation goes with it. An investigation whose own row still named the
 * line after the plant manager took the problem would be triaged by nobody —
 * and it is *not* an escalation of the CAPA: nothing about the investigation's
 * own status, team or dates moves, and `capas` has no escalation columns to
 * move because an escalation is a fact about the Concern's ownership.
 *
 * The caller's right to act at the *target* is the route's business (ADR-0006 —
 * People is another Module), and so are the existence and ancestry refusals;
 * what happens here is the write, over a row locked for it, with the detail
 * read the caller gets back taken inside the same transaction.
 */
async function escalateAction(actionItemId, orgUnitId, accountId) {
  return withActor(accountId, async (client) => {
    const { rows } = await client.query(
      `UPDATE action_items
          SET escalated_to_org_unit_id = $2,
              escalated_at = now()
        WHERE id = $1
      RETURNING id`,
      [actionItemId, orgUnitId]
    );
    if (rows.length === 0) throw notFound('Action');

    // The investigation moves with the problem it is about. One statement, and
    // a no-op for the overwhelming majority of Actions, which have no CAPA.
    await client.query(
      `UPDATE capas c
          SET org_unit_id = $2
        FROM action_items ai
       WHERE ai.id = $1 AND ai.capa_id = c.id`,
      [actionItemId, orgUnitId]
    );

    const { rows: [row] } = await client.query(
      `SELECT ${ACTION_COLUMNS} ${ACTION_JOINS} WHERE ai.id = $1`,
      [actionItemId]
    );
    return toActionDetail(
      row,
      await listPhases(actionItemId, client),
      await listMeasures(actionItemId, client)
    );
  });
}

// ---------------------------------------------------------------------------
// The CAPA (issue #209, ADR-0034)
//
// A CAPA is a formal investigation opened on an existing Concern, never a
// record of its own that runs beside one: the Concern stays the problem, its
// Containments, Countermeasures and Preventive actions ARE the CAPA's actions
// (recorded in this same log, once), and the CAPA carries only what an
// investigation adds on top — the team, the problem description, and later the
// root-cause chains, the effectiveness check and the report.
//
// That is why `capa_steps` is not written anywhere in this file, and why
// nothing ever will be: ADR-0034 rejected "a CAPA owns its own 8D steps" in as
// many words, because the same fix would then be tracked twice — once as a step
// and once as an Action — and the two would drift, the step marked done while
// the Action's own Check said the countermeasure did not hold. What D1-D8 are
// is answered by the Action log: the Concern for D2, its containments for D3,
// its countermeasures for D5-D6, its preventive actions for D7, and this row's
// team, root causes and effectiveness fields for D1, D4 and the verification.
//
// The primary key space is the CAPA's own (`capas.id`), not the Action log's,
// so every address below is `/api/actions/capas/:id` rather than a second kind
// of `action_items` row. The link that ties the two logs together is the
// Concern's own `capa_id`.
// ---------------------------------------------------------------------------

// What a CAPA's 8D method is, and the one value this Module writes (issue
// #209). The baseline's CHECK accepts `8d`, `5why`, `a3` and `simple`; a CAPA
// opened from the Action log is an 8D by the ADR's own vocabulary ("a CAPA
// system", D1-D8), and a later ticket that opens one from a safety incident
// decides for itself whether that changes.
const CAPA_METHOD = '8d';

// The baseline's `capas_status_check`, split by whether the investigation is
// over: `verifying` is still open — the fix is in and has not yet been proved
// (#211) — and only the last two mean nothing may change any more.
const CLOSED_CAPA_STATUSES = ['closed', 'cancelled'];

// Every column a CAPA is read by, in the order a person reads it: what it is,
// what it is about, whose it is, where it sits and how it is going. The Org
// Unit join is inner (a CAPA is always filed somewhere — the Concern's own)
// and the team-lead join is LEFT, because a CAPA may be opened with no team
// named yet: the judgement is that this problem needs an investigation, and who
// investigates it is a decision somebody makes next.
const CAPA_COLUMNS = `
  c.id, c.capa_no, c.title, c.problem_statement, c.method,
  c.org_unit_id, ou.code AS org_unit_code, ou.name AS org_unit_name, ou.site_id,
  c.team_lead_employee_id, lead.display_name AS team_lead_name,
  c.opened_at, to_char(c.due_date, 'YYYY-MM-DD') AS due_date,
  c.status, c.closed_at,
  to_char(c.effectiveness_check_due_at, 'YYYY-MM-DD') AS effectiveness_check_due_at,
  c.effectiveness_verified_at, c.effectiveness_note,
  c.created_at, c.updated_at
`;

const CAPA_JOINS = `
  FROM capas c
  JOIN org_units ou ON ou.id = c.org_unit_id
  LEFT JOIN employees lead ON lead.id = c.team_lead_employee_id
`;

function toCapa(row, { teamMembers = [], concern = null } = {}) {
  return {
    id: String(row.id),
    capaNo: row.capa_no,
    title: row.title,
    problemStatement: row.problem_statement,
    method: row.method,
    orgUnitId: String(row.org_unit_id),
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    siteId: String(row.site_id),
    // The lead is a role on the investigation and the members are a set, so
    // they are shaped differently on purpose (see the migration's own header).
    teamLead: row.team_lead_employee_id
      ? { employeeId: String(row.team_lead_employee_id), name: row.team_lead_name }
      : null,
    teamMembers,
    openedAt: row.opened_at,
    dueDate: row.due_date,
    status: row.status,
    closedAt: row.closed_at,
    effectivenessCheckDueAt: row.effectiveness_check_due_at,
    effectivenessVerifiedAt: row.effectiveness_verified_at,
    effectivenessNote: row.effectiveness_note,
    // The Concern this investigation is about, as its own detail read gives
    // it — with its measures, each carrying its own phases (issue #209), and
    // the Non-conformances it answers. Null only for a row written outside
    // this service, which the unique index makes impossible for anything
    // opened through the API.
    concern,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

/**
 * The CAPA's team, in the order a person reads a team: alphabetical by name,
 * because there is no seniority here — the lead is the role and everybody else
 * is equally on the team.
 */
async function listCapaTeamMembers(capaId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT m.employee_id, e.display_name AS name, m.created_at
       FROM capa_team_members m
       JOIN employees e ON e.id = m.employee_id
      WHERE m.capa_id = $1
      ORDER BY e.display_name ASC, m.employee_id ASC`,
    [capaId]
  );
  return rows.map((row) => ({
    employeeId: String(row.employee_id),
    name: row.name,
    addedAt: row.created_at
  }));
}

/**
 * Every phase of every cycle the named Actions have been round, grouped by
 * Action — the read the CAPA's own Screen needs and the Concern's detail read
 * does not (issue #209).
 *
 * One query for the whole set rather than one per measure: a Concern with a
 * containment, a countermeasure and a preventive action would otherwise be four
 * round trips to render one page, and the phases are the point of the page.
 */
async function listPhasesForActions(actionItemIds, client = null) {
  if (actionItemIds.length === 0) return {};
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT p.id, p.action_item_id, p.cycle, p.phase, p.owner_employee_id,
            e.display_name AS owner_name,
            to_char(p.due_date, 'YYYY-MM-DD') AS due_date,
            p.completed_at, p.outcome, p.note
       FROM action_phases p
       LEFT JOIN employees e ON e.id = p.owner_employee_id
      WHERE p.action_item_id = ANY($1::bigint[])
      ORDER BY p.cycle ASC,
               CASE p.phase WHEN 'plan' THEN 1 WHEN 'do' THEN 2
                            WHEN 'check' THEN 3 ELSE 4 END`,
    [actionItemIds.map(String)]
  );
  const byAction = {};
  for (const row of rows) {
    const key = String(row.action_item_id);
    if (!byAction[key]) byAction[key] = [];
    byAction[key].push(toPhase(row));
  }
  return byAction;
}

/**
 * The Concern a CAPA was opened on, as its own detail read gives it, with each
 * of its measures carrying its own phases (issue #209).
 *
 * "The Concern's Containments, Countermeasures and Preventive actions ARE the
 * CAPA's actions" is ADR-0034's sentence, and this is where it is made
 * readable: the CAPA's Screen shows the Concern's measures with the phase each
 * one is waiting on and the rounds each has been round, rather than a second
 * list of the same work.
 */
async function readCapaConcern(client, concernId) {
  const concern = await readActionDetail(client, concernId);
  const phases = await listPhasesForActions(
    concern.measures.map((measure) => measure.id),
    client
  );
  return {
    ...concern,
    measures: concern.measures.map((measure) => ({
      ...measure,
      phases: phases[String(measure.id)] ?? []
    }))
  };
}

// The detail read on a connection the caller names, so a write mid-transaction
// answers with the rows it just wrote rather than with what the pool can see.
async function readCapaDetail(client, capaId) {
  const { rows } = await client.query(`SELECT ${CAPA_COLUMNS} ${CAPA_JOINS} WHERE c.id = $1`, [
    capaId
  ]);
  if (!rows[0]) return null;

  // The Concern is found from the link rather than carried on the CAPA row,
  // because the link is the one fact and it lives on the Concern's side
  // (ADR-0034's own shape). At most one row, by the partial unique index.
  const { rows: linked } = await client.query(
    'SELECT id FROM action_items WHERE capa_id = $1',
    [capaId]
  );

  return toCapa(rows[0], {
    teamMembers: await listCapaTeamMembers(capaId, client),
    concern: linked[0] ? await readCapaConcern(client, linked[0].id) : null
  });
}

/**
 * One CAPA's whole read (issue #209), by its own id — what the CAPA's Screen
 * renders, and the answer every write below gives.
 *
 * Total, like findAction: a malformed id resolves to null rather than reaching
 * Postgres as a BIGINT parameter. Unknown ids are the route's 404.
 */
async function getCapaDetail(id) {
  if (parseId(id) === null) return null;
  return readCapaDetail(getPool(), id);
}

/**
 * Just enough of a CAPA for a route to ask its two questions (issue #209):
 * does it exist (404), and which Org Unit does it sit at, so Quality authority
 * can be asked there (403).
 *
 * The Org Unit is the CAPA's own, which follows its Concern's (see
 * escalateAction) — so what a caller needs authority at is where the
 * investigation currently lives, not where it was filed.
 */
async function findCapa(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT c.id, c.capa_no, c.status, c.org_unit_id, ou.site_id
       FROM capas c
       JOIN org_units ou ON ou.id = c.org_unit_id
      WHERE c.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return {
    id: rows[0].id,
    capaNo: rows[0].capa_no,
    status: rows[0].status,
    orgUnitId: rows[0].org_unit_id,
    siteId: rows[0].site_id
  };
}

// Postgres' own constraint names, mapped to messages this Module wrote. The
// same shape mapConcernLinkWriteError takes, and the same rule: a raw database
// message names tables and columns and is never echoed to a caller.
function mapCapaWriteError(error) {
  if (error.code === '23505' && error.constraint === 'action_items_capa_id_once') {
    return httpError(409, 'this Concern already has a CAPA');
  }
  if (error.code === '23514' && error.constraint === 'action_items_capa_is_a_concern') {
    return httpError(400, 'a CAPA is opened on a Concern, and that Action is not one');
  }
  if (error.code === '23505' && error.constraint === 'capa_team_members_once') {
    return httpError(409, 'that Employee is already on this CAPA team');
  }
  return error;
}

/**
 * Opens a CAPA on a Concern (issue #209, ADR-0034).
 *
 * Three refusals, all of them facts about the row this is about and all read
 * under SELECT ... FOR UPDATE so the Concern cannot change under the check:
 *
 *   - the Action must exist (404),
 *   - it must be a Concern (400) — an investigation is opened on a problem, and
 *     a Containment, a Countermeasure, a Preventive action, an Improvement or a
 *     Routine action is not one. The check constraint says the same thing one
 *     layer down; this is the door everybody uses,
 *   - it must not already have a CAPA (409). A Concern has at most one, which
 *     is what `action_items_capa_id_once` enforces; this reads the row first so
 *     that a second open never creates an orphan `capas` row, and the index is
 *     the backstop for the race the check cannot close.
 *
 * What the CAPA is given, and why:
 *
 *   - **its own number, from `next_document_number`** — `CA-<site code>-<year>-
 *     00001`, the same function and the same shape a Work order's `WO-` and a
 *     Concern's `AC-` already take (issue #50: "so that it can be referred to
 *     in reports and audits"). A second numbering scheme for the same platform
 *     is exactly what that reuse is for. The baseline column's own DEFAULT
 *     (global, no Site) stays as the fallback for a row written outside a
 *     request.
 *   - **`method` = 8d and `status` = open** — the investigation is opened, not
 *     started: which phase of the 8D it is in is a statement about its root
 *     causes and its verification, and that is #211's business rather than a
 *     field this route invents a value for.
 *   - **the Concern's Org Unit**, so that "the investigation sits where the
 *     problem does" is true from the first read. It follows the Concern if the
 *     Concern is escalated (see escalateAction) — an investigation whose
 *     problem has been handed to the plant manager but whose own Org Unit still
 *     names the line is one nobody triages.
 *   - **its title from the Concern's** — `capas.title` is NOT NULL and the ADR
 *     says the Concern *is* the problem, so an investigation does not get to
 *     restate it; what an investigation adds is the problem description
 *     (`problem_statement`), D2's own field, which is the caller's to write.
 *   - **its team, if the caller named one** — the lead on the row, the members
 *     as rows. Both are Employees the route has already resolved and checked
 *     as active, because that is People's record and not this Module's.
 *
 * The CAPA, the link on the Concern and the team are written in one
 * transaction: a CAPA and the Concern that answers it are one fact about two
 * rows, and half of it is not a state anything should ever read.
 */
async function openCapa(
  concernId,
  {
    teamLeadEmployeeId = null,
    teamMemberEmployeeIds = [],
    problemStatement = null,
    dueDate = null
  } = {},
  accountId
) {
  if (problemStatement !== null && problemStatement !== undefined && typeof problemStatement !== 'string') {
    throw httpError(400, 'problemStatement must be text');
  }

  let due = null;
  if (dueDate !== null && dueDate !== undefined) {
    due = parseDateOnly(dueDate);
    if (due === null) throw httpError(400, 'dueDate must be a valid YYYY-MM-DD date');
  }

  const members = [...new Set((teamMemberEmployeeIds ?? []).map(String))];

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [concern] } = await client.query(
        `SELECT id, action_type, title, org_unit_id, capa_id
           FROM action_items WHERE id = $1 FOR UPDATE`,
        [concernId]
      );
      if (!concern) throw notFound('Concern');
      if (concern.action_type !== 'concern') {
        throw httpError(400, 'a CAPA is opened on a Concern, and that Action is not one');
      }
      if (concern.capa_id !== null && concern.capa_id !== undefined) {
        throw httpError(409, 'this Concern already has a CAPA');
      }

      const { rows: [created] } = await client.query(
        `WITH site AS (
           SELECT s.code AS code FROM sites s
            WHERE s.id = (SELECT site_id FROM org_units WHERE id = $1)
         )
         INSERT INTO capas
           (capa_no, title, problem_statement, method, org_unit_id,
            team_lead_employee_id, due_date, status)
         VALUES
           (next_document_number('CA', (SELECT code FROM site), EXTRACT(YEAR FROM now())::int),
            $2, $3, $4, $1, $5, $6::date, 'open')
         RETURNING id`,
        [
          concern.org_unit_id,
          concern.title,
          problemStatement === null || problemStatement === undefined
            ? null
            : problemStatement.trim() || null,
          CAPA_METHOD,
          teamLeadEmployeeId,
          due
        ]
      );

      // The link, in the same transaction as the row it points at. A database
      // refusal here is the index or the check constraint, and both are mapped
      // to the messages above rather than echoed.
      try {
        await client.query('UPDATE action_items SET capa_id = $2 WHERE id = $1', [
          concern.id,
          created.id
        ]);
      } catch (error) {
        throw mapCapaWriteError(error);
      }

      if (members.length > 0) {
        try {
          await client.query(
            `INSERT INTO capa_team_members (capa_id, employee_id)
             SELECT $1, employee_id FROM unnest($2::bigint[]) AS employee_id`,
            [created.id, members]
          );
        } catch (error) {
          throw mapCapaWriteError(error);
        }
      }

      return readCapaDetail(client, created.id);
    });
  } catch (error) {
    throw mapCapaWriteError(error);
  }
}

/**
 * Changes what an open CAPA carries about itself (issue #209): the team lead,
 * the team, and the problem description. Nothing else, and deliberately so —
 * the method, the number and the status are not a caller's to set, and the
 * effectiveness fields belong to the check #211 records.
 *
 * A partial update rather than a replacement document: a field the caller did
 * not send is left alone, `null` on the lead clears it (a CAPA may lose its
 * lead, which is a real state — the team lead departs), and a member list
 * *replaces* the team, because that is what a form holding the whole team
 * means when it is saved. The one refusal is the CAPA's own status: an
 * investigation that is closed or cancelled is a record, not a worklist.
 *
 * The Employees are the route's business: every id reaching here has already
 * been parsed and resolved against People's directory, so a departed Employee
 * is refused in the same words every other Action refuses one.
 */
async function updateCapa(capaId, input, accountId) {
  const body = input ?? {};
  const setsProblemStatement = body.problemStatement !== undefined;
  const setsTeamLead = body.teamLeadEmployeeId !== undefined;
  const setsTeamMembers = body.teamMemberEmployeeIds !== undefined;

  if (setsProblemStatement && body.problemStatement !== null && typeof body.problemStatement !== 'string') {
    throw httpError(400, 'problemStatement must be text');
  }
  if (setsTeamMembers && !Array.isArray(body.teamMemberEmployeeIds)) {
    throw httpError(400, 'teamMemberEmployeeIds must be a list of Employee ids');
  }

  return withActor(accountId, async (client) => {
    const { rows: [capa] } = await client.query(
      'SELECT id, status FROM capas WHERE id = $1 FOR UPDATE',
      [capaId]
    );
    if (!capa) throw notFound('CAPA');
    if (CLOSED_CAPA_STATUSES.includes(capa.status)) {
      throw httpError(409, `this CAPA is ${capa.status}, so nothing about it can be changed`);
    }

    if (setsProblemStatement) {
      const written = body.problemStatement === null ? '' : body.problemStatement.trim();
      await client.query('UPDATE capas SET problem_statement = $2 WHERE id = $1', [
        capaId,
        written === '' ? null : written
      ]);
    }

    if (setsTeamLead) {
      await client.query('UPDATE capas SET team_lead_employee_id = $2 WHERE id = $1', [
        capaId,
        body.teamLeadEmployeeId
      ]);
    }

    if (setsTeamMembers) {
      const members = [...new Set(body.teamMemberEmployeeIds.map(String))];
      await client.query('DELETE FROM capa_team_members WHERE capa_id = $1', [capaId]);
      if (members.length > 0) {
        try {
          await client.query(
            `INSERT INTO capa_team_members (capa_id, employee_id)
             SELECT $1, employee_id FROM unnest($2::bigint[]) AS employee_id`,
            [capaId, members]
          );
        } catch (error) {
          throw mapCapaWriteError(error);
        }
      }
    }

    return readCapaDetail(client, capaId);
  });
}

module.exports = {
  ACTION_TYPES,
  ACTION_STATUSES,
  OPEN_STATUSES,
  PRIORITIES,
  MEASURE_TYPES,
  PHASES,
  CHECK_OUTCOMES,
  ACTION_LIST_LIMIT,
  listPillars,
  listActionsAtSite,
  findAction,
  getActionDetail,
  listPhases,
  listMeasures,
  listLinkedNonconformances,
  findNonconformanceForConcern,
  createAction,
  createMeasure,
  raiseConcernFromNonconformance,
  linkNonconformance,
  unlinkNonconformance,
  completePhase,
  cancelAction,
  escalationTargets,
  escalateAction,
  // The CAPA (issue #209): opening one on a Concern, reading one, changing its
  // team and its problem description, and the two facts a route needs to ask
  // its own questions about it.
  CAPA_METHOD,
  findCapa,
  getCapaDetail,
  openCapa,
  updateCapa
};
