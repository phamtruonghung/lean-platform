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

// The Non-conformances a Concern answers (issues #208, #212), in the shape the
// Concern's own Screen reads and the CAPA report renders: the number a person
// quotes, what was made wrong (Product), why (Defect code), how much of it, and
// — since #212 — how the product was dealt with. A cross-Module read done as an
// ordinary SQL join — `products`, `defect_codes` and `org_units` are Quality's
// and People's tables, and ADR-0006 makes that a query rather than a boundary
// violation. Nothing here is written: this Module creates no Quality row, ever.
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

function toLinkedNonconformance(row, dispositions = []) {
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
    // How the product was dealt with (issue #212) — every Disposition recorded
    // against this occurrence, oldest first. An empty array is "nothing has
    // been decided about this product yet", which is what the CAPA report's own
    // section says rather than a missing field, the same rule `measures` and
    // `nonconformances` themselves follow.
    dispositions,
    // The one it was raised from reads first, then the occurrences gathered
    // later, oldest first: a reader wants the origin before the additions.
    isSource: row.is_source === true,
    linkedAt: row.linked_at
  };
}

// The only value `quality_dispositions.disposition_type` carries for a
// Concession — the baseline's own, and the one Disposition that accepts product
// as it is rather than dealing with it. Named here rather than reached for
// through Quality's entry point for the reason the SQL above is a join: it is a
// value in a shared schema, not a judgement about a record.
const USE_AS_IS_DISPOSITION_TYPE = 'use_as_is';

// The Dispositions on the Non-conformances a Concern answers (issue #212) —
// what the CAPA report has to show beside each occurrence it lists: how the
// product was dealt with, how much of it, who decided it and when.
//
// The column list and the keys are Quality's own `listDispositions` verbatim,
// copied rather than shared (ADR-0006's third clause — this Module's `errors.js`
// is duplicated for the same reason), because the two reads describe one set of
// rows: a report that disagreed with the record's own Screen about a
// Disposition would be a second answer to one question. It is a SQL join for
// the reason the joins above it are: this needs the rows, not Quality's
// judgement about them.
const LINKED_DISPOSITION_COLUMNS = `
  qd.id, qd.quality_issue_id, qd.disposition_type, qd.quantity, qd.uom_code,
  qd.rework_minutes, qd.decided_at, qd.approval_ref, qd.notes,
  qd.decided_by_account_id, dau.display_name AS decided_by_account_name,
  qd.decided_by, e.display_name AS decided_by_employee_name`;

const LINKED_DISPOSITION_JOINS = `
  FROM quality_dispositions qd
  LEFT JOIN app_users dau ON dau.id = qd.decided_by_account_id
  LEFT JOIN employees e ON e.id = qd.decided_by`;

function toLinkedDisposition(row) {
  return {
    id: row.id,
    dispositionType: row.disposition_type,
    // A Concession is a Disposition to use the product as it is, said as a
    // boolean the way Quality's own read says it: the report labels it
    // "Concession" and nothing else needs to compare the wire value.
    isConcession: row.disposition_type === USE_AS_IS_DISPOSITION_TYPE,
    quantity: row.quantity === null || row.quantity === undefined ? null : Number(row.quantity),
    uomCode: row.uom_code,
    reworkMinutes:
      row.rework_minutes === null || row.rework_minutes === undefined
        ? null
        : Number(row.rework_minutes),
    decidedAt: row.decided_at,
    reference: row.approval_ref ?? null,
    note: row.notes ?? null,
    decidedByAccountId: row.decided_by_account_id ?? null,
    decidedByAccountName: row.decided_by_account_name ?? null,
    decidedByEmployeeId: row.decided_by ?? null,
    decidedByEmployeeName: row.decided_by_employee_name ?? null
  };
}

/**
 * The Dispositions of the Non-conformances a read has just gathered (issue
 * #212), grouped by the Non-conformance each belongs to.
 *
 * One query for the whole set rather than one per occurrence, the shape
 * `listPhasesForActions` takes for the same reason: a Concern answering four
 * occurrences would otherwise be four more round trips to render one report.
 */
async function listDispositionsForIssues(qualityIssueIds, client = null) {
  if (qualityIssueIds.length === 0) return {};
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${LINKED_DISPOSITION_COLUMNS}
     ${LINKED_DISPOSITION_JOINS}
      WHERE qd.quality_issue_id = ANY($1::bigint[])
      ORDER BY qd.decided_at, qd.id`,
    [qualityIssueIds.map(String)]
  );
  const byIssue = {};
  for (const row of rows) {
    const key = String(row.quality_issue_id);
    if (!byIssue[key]) byIssue[key] = [];
    byIssue[key].push(toLinkedDisposition(row));
  }
  return byIssue;
}

/**
 * The Non-conformances one Concern answers (issue #208), each with the number,
 * Product, Defect code and quantity a reader needs, the Dispositions recorded
 * against it (issue #212), and whether it is the one the Concern was raised
 * from.
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
  const dispositions = await listDispositionsForIssues(
    rows.map((row) => row.id),
    client
  );
  return rows.map((row) => toLinkedNonconformance(row, dispositions[String(row.id)] ?? []));
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

    // The Concern is closed, so the investigation opened on it is waiting on
    // its effectiveness check (issue #211, ADR-0034).
    if (status === 'done' && action.action_type === 'concern') {
      await beginCapaEffectivenessWait(client, actionItemId);
    }

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

// Every value `capas.status` admits, in the baseline's own order (issue #211).
// The register's `?status=` is validated against this rather than against the
// open/closed split above: a caller narrowing a list to `verifying` is asking a
// real question, and `status=verified` is a typo worth a 400 (ADR-0023's rule
// read the way the action log reads its own enums).
const CAPA_STATUSES = [
  'open',
  'containment',
  'root_cause',
  'actions',
  'verifying',
  'closed',
  'cancelled'
];

// How many investigations one read of the CAPA list answers with. The Action
// register's own 200, for the same reason: a list that could be unbounded is a
// list the client cannot promise to have rendered, and one row past the limit
// is what makes "there is more" a fact rather than a guess.
const CAPA_LIST_LIMIT = 200;

// The one definition of "this CAPA's effectiveness check is overdue" (issue
// #211), named once because three places say it: the row's own field, the
// register's `?overdue=true` filter, and the order the register reads in.
//
// A date is set when the Concern closes and cleared when a check is recorded,
// so the first clause is "the check is due" and the second is "and the day has
// passed". The third is what keeps a closed investigation out of the overdue
// list: an effective check leaves the due date where it was, because that is
// the date the check was judged against, and a closed CAPA is not a worklist.
const CAPA_CHECK_OVERDUE =
  "(c.effectiveness_check_due_at IS NOT NULL AND c.effectiveness_check_due_at < CURRENT_DATE " +
  "AND c.status NOT IN ('closed', 'cancelled'))";

// The delay a CAPA is opened with, in days, and the bounds the schema's own
// CHECK enforces (migration 1800300000000). Exported for the same reason
// `CAPA_METHOD` is: the Module's own values are what its callers and its tests
// name, rather than a literal scattered through both.
const CAPA_EFFECTIVENESS_DELAY_DAYS = { default: 30, min: 0, max: 365 };


// The CAPA's two 5 Why chains (issue #210), in the order a person reasons them:
// why the problem happened, then why it was not detected. The values mirror the
// CHECK migration 1800200000000 adds to `capa_root_causes.chain`, and the order
// is the order the chains are read in — see CAPA_CHAIN_ORDER below.
//
// Deliberately *not* named `problem`/`detection`: ADR-0034's own words are "why
// it happened" and "why it was not detected", and 8D's names for those two
// chains are occurrence and escape.
const CAPA_CHAINS = ['occurrence', 'escape'];

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
  c.effectiveness_check_delay_days,
  to_char(c.effectiveness_check_due_at, 'YYYY-MM-DD') AS effectiveness_check_due_at,
  ${CAPA_CHECK_OVERDUE} AS effectiveness_check_overdue,
  c.effectiveness_verified_at, c.effectiveness_note,
  c.effectiveness_verified_by_account_id,
  verifier.display_name AS effectiveness_verified_by_name,
  c.created_at, c.updated_at
`;

const CAPA_JOINS = `
  FROM capas c
  JOIN org_units ou ON ou.id = c.org_unit_id
  LEFT JOIN employees lead ON lead.id = c.team_lead_employee_id
  LEFT JOIN app_users verifier ON verifier.id = c.effectiveness_verified_by_account_id
`;

function toCapa(row, { teamMembers = [], whys = [], causes = [], concern = null } = {}) {
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
    // The two 5 Why chains (issue #210), both of them, in the order they are
    // reasoned and each in its own order. One flat list rather than two named
    // ones: a Why already says which chain it is in, and a caller that wants
    // one chain filters on the field it already has. `occurrence` comes first
    // — you work out what went wrong before you ask why nobody caught it.
    whys,
    // The fishbone (issue #213): the candidate causes, in the 6M's own order
    // and each category in the order its causes were recorded. BESIDE the two
    // chains rather than mixed into them — one flat list, like `whys`, because
    // a cause already says which category it is in and what its verdict is. A
    // team reasons on this list first, then starts a chain from the cause it
    // confirmed.
    causes,
    openedAt: row.opened_at,
    dueDate: row.due_date,
    status: row.status,
    closedAt: row.closed_at,
    // The effectiveness check (issue #211): how long after the Concern closes
    // it falls due, the date that rule produced at the last closure, whether
    // it is overdue, and what was recorded when it was answered. The date is
    // null while the Concern is open — there is nothing due yet — and is
    // cleared again by a check that did not hold, because the next one becomes
    // due when the Concern closes again.
    effectivenessCheckDelayDays: row.effectiveness_check_delay_days,
    effectivenessCheckDueAt: row.effectiveness_check_due_at,
    effectivenessCheckOverdue: row.effectiveness_check_overdue === true,
    // The Account that recorded it, named rather than reduced to an id: the
    // report a customer or an auditor reads has to say who decided the fix
    // held, and an administrator need not be an Employee (see the migration's
    // header for why this is a second column rather than the baseline's own).
    effectivenessVerifiedBy: row.effectiveness_verified_by_account_id
      ? {
          accountId: String(row.effectiveness_verified_by_account_id),
          name: row.effectiveness_verified_by_name
        }
      : null,
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

// The `why` half of `capa_root_causes` (issue #210) — the fishbone half
// (`verdict`, `evidence_note`, `category`) is #213's and is not read here.
const WHY_COLUMNS = `
  r.id, r.chain, r.sequence, r.statement, r.is_root,
  r.created_at, r.updated_at
`;

// Which chain reads first: why the problem happened, then why it was not
// detected. A CASE rather than `ORDER BY chain`, which would sort `escape`
// ahead of `occurrence` and read the reasoning backwards.
const CAPA_CHAIN_ORDER = "CASE r.chain WHEN 'occurrence' THEN 1 ELSE 2 END";

function toWhy(row) {
  return {
    id: String(row.id),
    chain: row.chain,
    sequence: row.sequence,
    statement: row.statement,
    // Where the chain stopped. At most one per chain, which the partial unique
    // index `capa_root_causes_one_root_per_chain` makes true (migration
    // 1800200000000) rather than merely intended.
    isRoot: row.is_root,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

/**
 * The two 5 Why chains on one CAPA, read in one query and in order (issue
 * #210) — why the problem happened, then why it was not detected.
 *
 * The order is a fact about the investigation rather than a rendering choice,
 * so it is written once here. Within a chain `sequence` is the whole answer,
 * with `id` breaking a tie two rows should never have: the service keeps a
 * chain's positions contiguous from 1, and this is the order that guarantee is
 * for.
 */
async function listCapaWhys(capaId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${WHY_COLUMNS}
       FROM capa_root_causes r
      WHERE r.capa_id = $1 AND r.cause_type = 'why'
      ORDER BY ${CAPA_CHAIN_ORDER}, r.sequence ASC, r.id ASC`,
    [capaId]
  );
  return rows.map(toWhy);
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
    whys: await listCapaWhys(capaId, client),
    causes: await listCapaCauses(capaId, client),
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
 * The CAPA list: every investigation on the Platform, worst first (issue #211).
 *
 * Which is not "every CAPA at a Site", and that is deliberate. A CAPA's own
 * read is `/api/actions/capas/:id` with no Site in the address — a CAPA is
 * identified by its own number (`CA-HCM-2026-00001`), an auditor quotes the
 * number and not the plant — and the collection beside that read keeps the same
 * scope, so the list and the record it lists cannot be two different sizes.
 * ADR-0009's asymmetry is what makes it safe: an Org Unit decides where an
 * Account may *act*, never what it may know about, so this is a platform-wide
 * read for every approved Account, exactly as the CAPA's own detail read is.
 *
 * `orgUnitPath` narrows it by *area* — one Org Unit and everything beneath it,
 * the ltree walk the Action register and the Non-conformance register both use
 * — and never by entitlement. `status` is the investigation's own state, and
 * `overdue` is the question this ticket exists for: which checks have fallen
 * due and not been recorded. All three are read filters over an already-visible
 * list, so all three are the server's work rather than the client's: a filter
 * that narrowed the client's own copy would silently disagree with `truncated`
 * the moment the list is capped.
 *
 * One row past the limit, so "there is more" is a fact rather than a guess —
 * `listActionsAtSite`'s own shape, and the reason the count matters here is the
 * same: a capped list must not read as the whole Platform.
 */
async function listCapas({ orgUnitPath = null, status = null, overdue = false } = {}) {
  const conditions = [];
  const params = [];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`c.status = $${params.length}`);
  }
  if (overdue) {
    conditions.push(CAPA_CHECK_OVERDUE);
  }

  const { rows } = await getPool().query(
    `SELECT ${CAPA_COLUMNS}
     ${CAPA_JOINS}
     ${conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : ''}
     ORDER BY ${CAPA_CHECK_OVERDUE} DESC,
              c.effectiveness_check_due_at ASC NULLS LAST,
              c.opened_at DESC
     LIMIT ${CAPA_LIST_LIMIT + 1}`,
    params
  );

  const truncated = rows.length > CAPA_LIST_LIMIT;
  return {
    capas: rows.slice(0, CAPA_LIST_LIMIT).map((row) => toCapa(row)),
    truncated
  };
}

/**
 * Just enough of a CAPA for a route to ask its two questions (issue #209):
 * does it exist (404), and which Org Unit does it sit at, so Quality authority
 * can be asked there (403).
 *
 * The Org Unit is the CAPA's own, which follows its Concern's (see
 * escalateAction) — so what a caller needs authority at is where the
 * investigation currently lives, not where it was filed.
 *
 * It also carries the team's Employee ids (issue #210), because the write gate
 * for a CAPA's root causes is "edit access at its Org Unit **or a place on its
 * team**" — and both halves of that are facts about this row, read once rather
 * than in a query of the route's own. `teamEmployeeIds` is the lead first and
 * then the members, which is the same set `Capa.team` names on the client: the
 * lead is on the team, they are just the one whose name is on the row.
 *
 * `teamLeadEmployeeId` is carried apart from that set (issue #211) because the
 * effectiveness check needs to ask a question the set cannot answer: whether
 * the Account recording the check *is* the team lead's. "The team lead cannot
 * verify their own fix" is a rule about one Employee, and a caller who is on
 * the team as a member is exactly who may record it.
 */
async function findCapa(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT c.id, c.capa_no, c.status, c.org_unit_id, ou.site_id,
            c.team_lead_employee_id,
            ARRAY(SELECT m.employee_id FROM capa_team_members m WHERE m.capa_id = c.id)
              AS team_member_ids
       FROM capas c
       JOIN org_units ou ON ou.id = c.org_unit_id
      WHERE c.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  const memberIds = rows[0].team_member_ids ?? [];
  return {
    id: rows[0].id,
    capaNo: rows[0].capa_no,
    status: rows[0].status,
    orgUnitId: rows[0].org_unit_id,
    siteId: rows[0].site_id,
    teamLeadEmployeeId:
      rows[0].team_lead_employee_id === null
        ? null
        : String(rows[0].team_lead_employee_id),
    teamEmployeeIds: [
      ...(rows[0].team_lead_employee_id === null
        ? []
        : [String(rows[0].team_lead_employee_id)]),
      ...memberIds.map(String)
    ]
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
 * The one refusal every write to an open CAPA's own record makes, in one place
 * (issue #210): the CAPA exists, and it is not closed.
 *
 * `FOR UPDATE`, because the status this decides on must not change under the
 * write that follows it — the same lock `updateCapa` takes on this row, and
 * the reason the 409 is not a route's business: a route that read the status
 * would be a second read racing this one.
 */
async function lockOpenCapa(client, capaId) {
  const { rows: [capa] } = await client.query(
    'SELECT id, status FROM capas WHERE id = $1 FOR UPDATE',
    [capaId]
  );
  if (!capa) throw notFound('CAPA');
  if (CLOSED_CAPA_STATUSES.includes(capa.status)) {
    throw httpError(409, `this CAPA is ${capa.status}, so nothing about it can be changed`);
  }
  return capa;
}

/**
 * Changes what an open CAPA carries about itself (issue #209): the team lead,
 * the team, the problem description, and — since #211 — how long after its
 * Concern closes the effectiveness check falls due. Nothing else, and
 * deliberately so: the method, the number and the status are not a caller's to
 * set, and the effectiveness fields themselves belong to the check
 * `recordEffectivenessCheck` records.
 *
 * A partial update rather than a replacement document: a field the caller did
 * not send is left alone, `null` on the lead clears it (a CAPA may lose its
 * lead, which is a real state — the team lead departs), and a member list
 * *replaces* the team, because that is what a form holding the whole team
 * means when it is saved. The one refusal is the CAPA's own status: an
 * investigation that is closed or cancelled is a record, not a worklist.
 *
 * **The delay (issue #211) is the one field whose change is deliberately not
 * retroactive.** It governs the due date written at the *next* closure; a CAPA
 * already waiting on its check keeps the date it was given, because that is the
 * date the check is judged against. The ticket's own wording fixes both halves
 * — "adjustable on the CAPA", and "the check's due date is *set* when the
 * Concern closes" — and migration 1800300000000 argues why the stored date wins
 * over one derived on read. A caller changing it therefore changes a number and
 * not a fact, which is why this needs no lock beyond the one every write here
 * already takes.
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
  const setsDelay = body.effectivenessCheckDelayDays !== undefined;

  if (setsProblemStatement && body.problemStatement !== null && typeof body.problemStatement !== 'string') {
    throw httpError(400, 'problemStatement must be text');
  }
  if (setsTeamMembers && !Array.isArray(body.teamMemberEmployeeIds)) {
    throw httpError(400, 'teamMemberEmployeeIds must be a list of Employee ids');
  }
  if (
    setsDelay &&
    (!Number.isInteger(body.effectivenessCheckDelayDays) ||
      body.effectivenessCheckDelayDays < CAPA_EFFECTIVENESS_DELAY_DAYS.min ||
      body.effectivenessCheckDelayDays > CAPA_EFFECTIVENESS_DELAY_DAYS.max)
  ) {
    throw httpError(
      400,
      'effectivenessCheckDelayDays must be a whole number of days from ' +
        `${CAPA_EFFECTIVENESS_DELAY_DAYS.min} to ${CAPA_EFFECTIVENESS_DELAY_DAYS.max}`
    );
  }

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    if (setsProblemStatement) {
      const written = body.problemStatement === null ? '' : body.problemStatement.trim();
      await client.query('UPDATE capas SET problem_statement = $2 WHERE id = $1', [
        capaId,
        written === '' ? null : written
      ]);
    }

    if (setsDelay) {
      await client.query(
        'UPDATE capas SET effectiveness_check_delay_days = $2 WHERE id = $1',
        [capaId, body.effectivenessCheckDelayDays]
      );
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

// ---------------------------------------------------------------------------
// The 5 Why chains on a CAPA (issue #210, ADR-0034)
//
// A CAPA's team reasons its way to the two root causes it needs with two
// chains: **occurrence** (why the problem happened) and **escape** (why it was
// not detected). ADR-0034's sentence is that a CAPA "adds the team, the
// problem description, the root-cause analysis, the effectiveness
// verification", and this is the root-cause analysis: one row per Why, in the
// order the team reasoned them, each chain ending in at most one Why marked as
// its confirmed root cause — which is the fact #211 refuses to close a CAPA
// without.
//
// Three rules shape every write below:
//
//   - **The chain is the sequence's scope.** A Why is added at the next
//     position of *its* chain, and removing one renumbers its chain so the
//     positions stay 1..n with no gap. A gap is not merely untidy: "the third
//     Why" is how a person refers to one, and a chain that reads 1, 2, 4 has
//     two answers to which Why is third.
//   - **At most one confirmed root cause per chain**, and marking a second
//     *replaces* the first rather than refusing (the ticket's own words). The
//     replacement is two statements in one transaction, and the partial unique
//     index `capa_root_causes_one_root_per_chain` is the backstop for a writer
//     that does not come through here (migration 1800200000000).
//   - **A closed investigation is a record.** Every one of these writes asks
//     `lockOpenCapa` first, so a closed or cancelled CAPA is a 409 — the same
//     refusal `updateCapa` makes, in the same words.
//
// The fishbone half of `capa_root_causes` (`category`, `verdict`,
// `evidence_note`) is deliberately not touched: #213 records candidate causes
// and their verdicts, and its rows are `cause_type = 'fishbone'`, which every
// query here filters out.
// ---------------------------------------------------------------------------

/**
 * A Why's statement, which is the only thing it says (issue #210). Required,
 * and required to say something: an empty Why is a chain that appears to have a
 * step and does not, which is worse than a shorter chain. The column is NOT
 * NULL for the same reason.
 */
function requireWhyStatement(value) {
  if (typeof value !== 'string') {
    throw httpError(400, 'statement must be text');
  }
  const said = value.trim();
  if (said === '') {
    throw httpError(400, 'a Why must have a statement');
  }
  return said;
}

/**
 * A chain's Whys in their own order, locked — the list a move or a removal
 * renumbers from (issue #210).
 *
 * `sequence` is the order and `id` breaks a tie (two rows at one position are
 * a state this service never writes, and reading one the old image left behind
 * is better than an arbitrary order). Locked because the write that follows is
 * computed from this list: two callers moving a Why at once must serialise on
 * the chain rather than each renumber from the list they read.
 */
async function orderedWhyIds(client, capaId, chain) {
  const { rows } = await client.query(
    `SELECT r.id
       FROM capa_root_causes r
      WHERE r.capa_id = $1 AND r.cause_type = 'why' AND r.chain = $2
      ORDER BY r.sequence ASC, r.id ASC
      FOR UPDATE`,
    [capaId, chain]
  );
  return rows.map((row) => String(row.id));
}

/**
 * Writes positions 1..n onto the Whys in the order given (issue #210). One
 * statement, and only the rows whose position actually changed — a chain is
 * short and this is a single round trip either way, but a statement that
 * rewrites every row would touch nine rows to move one.
 *
 * `unnest` with two arrays is what makes it one statement: the pairs are the
 * whole input, and there is no window between the rows being numbered and the
 * numbers landing. Nothing here takes a lock of its own — the caller has
 * already read the chain `FOR UPDATE`, which is what makes the ids it passes
 * the chain's own current members.
 */
async function renumberWhyChain(client, orderedIds) {
  if (orderedIds.length === 0) return;
  await client.query(
    `UPDATE capa_root_causes r
        SET sequence = v.sequence
       FROM unnest($1::bigint[], $2::smallint[]) AS v(id, sequence)
      WHERE r.id = v.id AND r.sequence <> v.sequence`,
    [orderedIds, orderedIds.map((_, index) => index + 1)]
  );
}

/**
 * Adds a Why to one of a CAPA's two chains (issue #210), at the next position
 * of that chain.
 *
 * The position is computed inside the transaction rather than accepted from
 * the caller, and the `FOR UPDATE` on the CAPA above is what makes it safe:
 * "the next position" is `MAX(sequence) + 1` of this chain, and two Whys added
 * at once must not both be told they are third.
 *
 * The chain is checked here rather than in the route because the set of chains
 * is this file's knowledge, the same way `actionType` is (ACTION_TYPES): a
 * `chain` that is neither of the two is a 400 naming them, not a raw check
 * constraint violation.
 *
 * The answer is the whole CAPA as it now reads, like every other write in this
 * slice: a caller that has just added a Why wants the chain it is in, and the
 * client's Screen is already showing the investigation the row belongs to.
 */
async function addCapaWhy(capaId, { chain, statement } = {}, accountId) {
  if (!CAPA_CHAINS.includes(chain)) {
    throw httpError(400, `chain must be one of: ${CAPA_CHAINS.join(', ')}`);
  }
  const said = requireWhyStatement(statement);

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    await client.query(
      `INSERT INTO capa_root_causes (capa_id, cause_type, chain, sequence, statement)
       VALUES ($1, 'why', $2,
               COALESCE((SELECT MAX(r.sequence) + 1
                           FROM capa_root_causes r
                          WHERE r.capa_id = $1 AND r.cause_type = 'why' AND r.chain = $2),
                        1),
               $3)`,
      [capaId, chain, said]
    );

    return readCapaDetail(client, capaId);
  });
}

/**
 * Changes one Why on an open CAPA (issue #210): what it says, where it sits in
 * its chain, and whether it is the chain's confirmed root cause.
 *
 * A partial update, the shape `updateCapa` takes: a field the caller did not
 * send is left alone, and a body that names none of the three is a 400 rather
 * than a silent no-op. Three fields, three rules:
 *
 *   - **`statement`** — the Why revised. The row is NOT NULL, so an empty one
 *     is a 400 rather than a cleared field: a Why nobody can say is a Why
 *     nobody reasoned, and the chain is the record of the reasoning.
 *   - **`sequence`** — the Why moved to another position of its own chain,
 *     with the rest of the chain renumbered around it so the positions stay
 *     contiguous. A position outside the chain (0, or past its end + 1) is a
 *     400: unlike adding, there is no next position to infer from a number
 *     that is not a position. A Why never moves between chains — that would be
 *     a different finding, and the honest way to say it is to remove the Why
 *     and add it to the chain it belongs in.
 *   - **`isRoot`** — the chain's conclusion. `true` marks this Why and, in the
 *     same transaction, unmarks whatever was marked before it, so "marking a
 *     second replaces the first" is one fact and not a state with two roots.
 *     `false` undoes it, and a chain with no root is a chain still being
 *     reasoned — which is exactly the state #211 refuses to close on.
 *
 * The lock order is the CAPA, then the Why, then the chain. Every write here
 * takes them in that order, so two of them cannot meet each other halfway.
 */
async function updateCapaWhy(capaId, whyId, input, accountId) {
  // Total like findAction: a malformed id is "no such Why" rather than a
  // BIGINT parameter Postgres would refuse to parse.
  if (parseId(whyId) === null) throw notFound('Why');

  const body = input ?? {};
  const setsStatement = body.statement !== undefined;
  const setsSequence = body.sequence !== undefined;
  const setsRoot = body.isRoot !== undefined;

  if (!setsStatement && !setsSequence && !setsRoot) {
    throw httpError(400, 'send a statement, a position or a root-cause mark — there is nothing to change otherwise');
  }
  if (setsStatement) {
    requireWhyStatement(body.statement);
  }
  if (setsSequence && (!Number.isInteger(body.sequence) || body.sequence < 1)) {
    throw httpError(400, 'sequence must be a whole position in the chain, counting from 1');
  }
  if (setsRoot && typeof body.isRoot !== 'boolean') {
    throw httpError(400, 'isRoot must be true or false');
  }

  // Validated once, above, and carried into the transaction rather than
  // re-checked inside it: the same value either way, and a reader of the write
  // below should be reading the statement, not its rules.
  const said = setsStatement ? body.statement.trim() : null;

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    const { rows: [why] } = await client.query(
      `SELECT r.id, r.chain
         FROM capa_root_causes r
        WHERE r.id = $1 AND r.capa_id = $2 AND r.cause_type = 'why'
        FOR UPDATE`,
      [whyId, capaId]
    );
    if (!why) throw notFound('Why');

    if (setsStatement) {
      await client.query('UPDATE capa_root_causes SET statement = $2 WHERE id = $1', [
        why.id,
        said
      ]);
    }

    if (setsSequence) {
      const ids = await orderedWhyIds(client, capaId, why.chain);
      const others = ids.filter((id) => id !== String(why.id));
      if (body.sequence > others.length + 1) {
        throw httpError(
          400,
          `sequence must be a position in this chain: 1 to ${others.length + 1}`
        );
      }
      const moved = [...others];
      moved.splice(body.sequence - 1, 0, String(why.id));
      await renumberWhyChain(client, moved);
    }

    if (setsRoot) {
      if (body.isRoot) {
        // Unmarked first: the partial unique index is checked per statement, so
        // marking before unmarking would collide with the root already there.
        await client.query(
          `UPDATE capa_root_causes
              SET is_root = FALSE
            WHERE capa_id = $1 AND cause_type = 'why' AND chain = $2
              AND is_root AND id <> $3`,
          [capaId, why.chain, why.id]
        );
        await client.query('UPDATE capa_root_causes SET is_root = TRUE WHERE id = $1', [
          why.id
        ]);
      } else {
        await client.query('UPDATE capa_root_causes SET is_root = FALSE WHERE id = $1', [
          why.id
        ]);
      }
    }

    return readCapaDetail(client, capaId);
  });
}

/**
 * Removes a Why from an open CAPA (issue #210) and closes the gap it leaves.
 *
 * The row goes: a Why "that turned out wrong" (#200's own words) is not part
 * of the reasoning any more, and leaving it in place marked as withdrawn would
 * make every reader of the chain decide which rows count. The chain's positions
 * are renumbered from its remaining rows in their own order, so the Whys after
 * the one removed move up by one and the chain still reads 1..n.
 *
 * If the Why removed was the chain's confirmed root cause, the chain now has
 * none — there is nothing to promote and nothing to guess: which remaining Why
 * is the root is a decision the team makes again, and marking one is the very
 * next thing this API offers.
 */
async function removeCapaWhy(capaId, whyId, accountId) {
  if (parseId(whyId) === null) throw notFound('Why');

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    const { rows: [removed] } = await client.query(
      `DELETE FROM capa_root_causes
        WHERE id = $1 AND capa_id = $2 AND cause_type = 'why'
        RETURNING chain`,
      [whyId, capaId]
    );
    if (!removed) throw notFound('Why');

    await renumberWhyChain(client, await orderedWhyIds(client, capaId, removed.chain));

    return readCapaDetail(client, capaId);
  });
}

// ---------------------------------------------------------------------------
// The fishbone — candidate causes by 6M category (issue #213, ADR-0034)
//
// A team does not open an investigation holding its root cause. It opens one
// holding a list of things it suspects, and the fishbone is where that list is
// kept: each candidate cause filed under exactly one of Ishikawa's 6M
// categories, and each marked `candidate` — still to be looked at — or
// `confirmed` / `ruled_out`, with the evidence written down beside the verdict.
// The chains are what the team does with a confirmed one: a chain's first Why
// may be started **from** a cause the evidence backed, which is the whole point
// of deciding between them.
//
// These rows are the *other* half of `capa_root_causes`, the half #210's own
// section above filters out of every query it makes: `cause_type = 'fishbone'`
// where a Why is `cause_type = 'why'`. The table carries both because they are
// one thing said twice — a list of causes — and the schema's own constraints
// already separate them: `chain` is NOT NULL exactly for a Why
// (`capa_root_causes_chain_is_a_why`), a fishbone row must name a category
// (`capa_root_causes_fishbone_has_category`), and `is_root` is a Why's
// (`capa_root_causes_root_is_a_why`) because a candidate's answer is its own
// `verdict` rather than a second way of saying "this is the one".
//
// **`verdict` and `evidence_note` were added by #210's migration
// (1800200000000) and written by nobody until now.** That is why this ticket
// adds no migration of its own: every column it needs already exists, the 6M
// set is already a CHECK on `category` in the baseline, and the categories are
// mirrored here as this file's own vocabulary (`CAPA_CAUSE_CATEGORIES`) exactly
// as `CAPA_CHAINS` mirrors the chain's.
//
// **Three rules, and where each lives.**
//
//   - **One category, from the 6M set.** A `category` outside it is a 400
//     naming the six, because the set is this file's knowledge the same way the
//     chains are — not a raw 23514 from a CHECK whose message names a table.
//   - **A verdict is paid for with evidence.** Choosing `confirmed` or
//     `ruled_out` requires the evidence note *in the same request*: the note is
//     the evidence for *that* verdict, and every note this table holds lives
//     beside a decision. Going back to `candidate` clears it, because a cause
//     under review again has nothing for the evidence to be about.
//   - **A chain starts from a confirmed cause, once.** `startCapaWhyFromCause`
//     below writes the chain's first Why from the cause the team confirmed —
//     the fishbone and the chains connect, per the spec's own story — and a
//     cause that is still `candidate` or has been `ruled_out` is a 409, as is a
//     chain that has already started.
//
// **How the link between a cause and its chain is recorded: it is not.** The
// chain's first Why *is* the cause's own statement, written at `sequence = 1`
// of the chain, and that is the whole convention — the ticket's own
// "`sequence = 1` convention", and the schema decision the Module spec records
// ("add the chain for why rows, and a verdict plus evidence note for fishbone
// rows"; it names no link column). A `cause_id` column would be a migration,
// and a one-way door, for a fact nothing reads: the report names the confirmed
// causes and the chains that began with them, and there is no question in this
// Module that needs "which cause did this Why come from" answered months later.
// The day one exists, the column and the migration come together.
//
// **And what this half does not do.** It touches no `why` row: every statement
// below filters `cause_type = 'fishbone'`, so a Why id handed to these
// addresses is a plain 404 rather than a second way to write a chain. Every
// write takes `lockOpenCapa` first, so a closed investigation refuses all of
// them in the same words the chains use.
// ---------------------------------------------------------------------------

// The 6M categories a candidate cause is filed under, in the order an Ishikawa
// diagram is drawn and the order `listCapaCauses` reads them in. The values
// mirror the `capa_root_causes.category` CHECK the baseline already carries —
// the set exists in the schema, so this is the service's copy of it for the 400
// rather than a second enforcement, exactly as `CAPA_CHAINS` mirrors the chain's.
const CAPA_CAUSE_CATEGORIES = [
  'man',
  'machine',
  'method',
  'material',
  'measurement',
  'environment'
];

// What may be said about a candidate cause, mirroring
// `capa_root_causes.verdict_check` (migration 1800200000000): it is a candidate
// until somebody looks, and then it is either confirmed or ruled out. There is
// deliberately no fourth value for "superseded" — a cause the team no longer
// believes in is removed, the same way a Why that turned out wrong is.
const CAPA_CAUSE_VERDICTS = ['candidate', 'confirmed', 'ruled_out'];

// A fishbone's branches in the 6M's own order rather than alphabetically, which
// would read machine, man, method … and put the categories in an order nobody
// draws them in. A CASE for the same reason `CAPA_CHAIN_ORDER` is one.
const CAPA_CAUSE_CATEGORY_ORDER = `CASE r.category
  WHEN 'man' THEN 1
  WHEN 'machine' THEN 2
  WHEN 'method' THEN 3
  WHEN 'material' THEN 4
  WHEN 'measurement' THEN 5
  ELSE 6
END`;

const CAUSE_COLUMNS = `
  r.id, r.category, r.sequence, r.statement, r.verdict, r.evidence_note,
  r.created_at, r.updated_at
`;

/**
 * A candidate cause's statement, which is the only thing it says (issue #213).
 * Required, and required to say something, for the reason a Why is: an empty
 * cause is a branch that appears to hold a suspicion and does not.
 */
function requireCauseStatement(value) {
  if (typeof value !== 'string') {
    throw httpError(400, 'statement must be text');
  }
  const said = value.trim();
  if (said === '') {
    throw httpError(400, 'a candidate cause must have a statement');
  }
  return said;
}

function toCause(row) {
  return {
    id: String(row.id),
    category: row.category,
    // The branch's position among its own category's causes, so the order the
    // team wrote them in survives a read. It is not a chain's `sequence`: a
    // cause never moves, and the positions are not renumbered when one is
    // removed, because "the third cause under Machine" is not a phrase anybody
    // uses (a Why's position is).
    sequence: row.sequence,
    statement: row.statement,
    // A cause with no verdict recorded is a candidate: `candidate` is the state
    // a new cause is in, and the column's only writer is this service.
    verdict: row.verdict ?? 'candidate',
    // The evidence for that verdict, and null on a candidate — the field and
    // the verdict travel together (see the section header).
    evidenceNote: row.evidence_note,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

/**
 * One CAPA's candidate causes, read in the 6M's own order and each category in
 * the order its causes were recorded (issue #213).
 *
 * The order is a fact about the diagram rather than a rendering choice, so it
 * is written once here — the fishbone reads the way it is drawn, top to bottom,
 * and a Screen that sorted them itself would be the second place that decides.
 */
async function listCapaCauses(capaId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${CAUSE_COLUMNS}
       FROM capa_root_causes r
      WHERE r.capa_id = $1 AND r.cause_type = 'fishbone'
      ORDER BY ${CAPA_CAUSE_CATEGORY_ORDER}, r.sequence ASC, r.id ASC`,
    [capaId]
  );
  return rows.map(toCause);
}

/**
 * Records a candidate cause under one 6M category on an open CAPA (issue
 * #213), as a `candidate` — the state before anybody has looked.
 *
 * The position is the next one *within its own category*, computed inside the
 * transaction rather than accepted from the caller: a fishbone is six lists,
 * not one, and "the next branch of Machine" is `MAX(sequence) + 1` of that
 * category. `lockOpenCapa` is what makes that safe against a second caller
 * adding one at the same moment, the same lock `addCapaWhy` takes.
 *
 * The verdict is written rather than defaulted: the column has no default
 * (migration 1800200000000 is additive and gave it none), and a cause whose
 * verdict the schema left null would read as undecided for a reason that is
 * about the writer and not about the cause.
 */
async function addCapaCause(capaId, { category, statement } = {}, accountId) {
  if (!CAPA_CAUSE_CATEGORIES.includes(category)) {
    throw httpError(400, `category must be one of: ${CAPA_CAUSE_CATEGORIES.join(', ')}`);
  }
  const said = requireCauseStatement(statement);

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    await client.query(
      `INSERT INTO capa_root_causes
         (capa_id, cause_type, category, sequence, statement, verdict)
       VALUES ($1, 'fishbone', $2,
               COALESCE((SELECT MAX(r.sequence) + 1
                           FROM capa_root_causes r
                          WHERE r.capa_id = $1 AND r.cause_type = 'fishbone'
                            AND r.category = $2),
                        1),
               $3, 'candidate')`,
      [capaId, category, said]
    );

    return readCapaDetail(client, capaId);
  });
}

/**
 * Changes one candidate cause on an open CAPA (issue #213): which category it
 * is filed under, what it says, and the verdict with the evidence for it.
 *
 * A partial update, the shape `updateCapaWhy` takes: a field the caller did not
 * send is left alone, and a body that names none of the four is a 400 rather
 * than a silent no-op. Four fields, four rules:
 *
 *   - **`category`** — the cause moved to another of the six. Unlike a Why,
 *     which never moves between chains, a cause genuinely may be re-filed: the
 *     team argues about whether a worn jig is Machine or Method, and the
 *     answer changing is the fishbone working rather than a second cause. A
 *     category that is not one of the six is a 400 naming them.
 *   - **`statement`** — what the cause says, revised. NOT NULL in the schema,
 *     so an empty one is a 400 rather than a cleared field.
 *   - **`verdict`** — `candidate`, `confirmed` or `ruled_out`. Choosing one of
 *     the two decisions **requires the evidence note in the same request**: the
 *     note is the evidence for that verdict, and it is the rule this ticket
 *     states as a 400. Choosing `candidate` again clears the note — the cause
 *     is under review once more, and its old evidence belongs to the decision
 *     that was unmade.
 *   - **`evidenceNote`** — the evidence of a decision already made, edited.
 *     Only a decided cause has one, so a note on a body that also, or only,
 *     says this cause is a `candidate` is a 400: there is no verdict for it to
 *     be the evidence of.
 *
 * The lock order is the CAPA, then the cause — the order every write in this
 * slice takes them in.
 */
async function updateCapaCause(capaId, causeId, input, accountId) {
  // Total like findAction: a malformed id is "no such cause" rather than a
  // BIGINT parameter Postgres would refuse to parse.
  if (parseId(causeId) === null) throw notFound('candidate cause');

  const body = input ?? {};
  const setsCategory = body.category !== undefined;
  const setsStatement = body.statement !== undefined;
  const setsVerdict = body.verdict !== undefined;
  const setsNote = body.evidenceNote !== undefined;

  if (!setsCategory && !setsStatement && !setsVerdict && !setsNote) {
    throw httpError(
      400,
      'send a category, a statement, a verdict or an evidence note — there is nothing to change otherwise'
    );
  }
  if (setsCategory && !CAPA_CAUSE_CATEGORIES.includes(body.category)) {
    throw httpError(400, `category must be one of: ${CAPA_CAUSE_CATEGORIES.join(', ')}`);
  }
  if (setsStatement) {
    requireCauseStatement(body.statement);
  }
  if (setsVerdict && !CAPA_CAUSE_VERDICTS.includes(body.verdict)) {
    throw httpError(400, `verdict must be one of: ${CAPA_CAUSE_VERDICTS.join(', ')}`);
  }
  if (setsNote && (typeof body.evidenceNote !== 'string' || body.evidenceNote.trim() === '')) {
    throw httpError(400, 'an evidence note must say what the evidence was');
  }
  // Deciding a cause is paid for with its evidence, in the same request.
  if (setsVerdict && body.verdict !== 'candidate' && !setsNote) {
    throw httpError(
      400,
      `a cause cannot be ${body.verdict} without the evidence: send an evidenceNote saying what it was`
    );
  }

  // Validated once, above, and carried into the transaction rather than
  // re-checked inside it: the same values either way, and a reader of the write
  // below should be reading the change, not its rules.
  const said = setsStatement ? body.statement.trim() : null;
  const note = setsNote ? body.evidenceNote.trim() : null;

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    const { rows: [cause] } = await client.query(
      `SELECT r.id, COALESCE(r.verdict, 'candidate') AS verdict
         FROM capa_root_causes r
        WHERE r.id = $1 AND r.capa_id = $2 AND r.cause_type = 'fishbone'
        FOR UPDATE`,
      [causeId, capaId]
    );
    if (!cause) throw notFound('candidate cause');

    const verdict = setsVerdict ? body.verdict : cause.verdict;
    if (verdict === 'candidate' && setsNote) {
      throw httpError(400, 'a candidate has no verdict for an evidence note to be the evidence of');
    }

    if (setsCategory) {
      await client.query('UPDATE capa_root_causes SET category = $2 WHERE id = $1', [
        causeId,
        body.category
      ]);
    }
    if (setsStatement) {
      await client.query('UPDATE capa_root_causes SET statement = $2 WHERE id = $1', [
        causeId,
        said
      ]);
    }
    if (setsVerdict) {
      // The verdict and the evidence for it land together: a decision whose
      // note is missing is not a state this table may hold, which is why
      // `candidate` clears the note in the same statement that writes it.
      await client.query(
        `UPDATE capa_root_causes
            SET verdict = $2, evidence_note = $3
          WHERE id = $1`,
        [causeId, verdict, verdict === 'candidate' ? null : note]
      );
    } else if (setsNote) {
      await client.query('UPDATE capa_root_causes SET evidence_note = $2 WHERE id = $1', [
        causeId,
        note
      ]);
    }

    return readCapaDetail(client, capaId);
  });
}

/**
 * Removes a candidate cause from an open CAPA (issue #213).
 *
 * The row goes, for the reason a Why goes: a cause the team has established
 * cannot be it — "that is not what we are looking at" — is not part of the
 * reasoning any more, and leaving it in place marked as withdrawn would put
 * every reader of the fishbone in the position of deciding which branches
 * count. The category's remaining positions are left as they are: they are the
 * order the causes were recorded in, not a chain whose third step anybody
 * quotes, and renumbering them would be a rule invented for tidiness.
 *
 * A cause whose verdict is `confirmed` may be removed like any other. Nothing
 * hangs off the row — a Why started from a cause keeps its own statement and
 * its own place in its chain (see this section's header on why there is no link
 * column), so there is nothing here to cascade and nothing to refuse.
 */
async function removeCapaCause(capaId, causeId, accountId) {
  if (parseId(causeId) === null) throw notFound('candidate cause');

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    const { rows: [removed] } = await client.query(
      `DELETE FROM capa_root_causes
        WHERE id = $1 AND capa_id = $2 AND cause_type = 'fishbone'
        RETURNING id`,
      [causeId, capaId]
    );
    if (!removed) throw notFound('candidate cause');

    return readCapaDetail(client, capaId);
  });
}

/**
 * Starts one of a CAPA's two 5 Why chains from a confirmed candidate cause
 * (issue #213) — the one door between the fishbone and the chains, and the
 * reason the fishbone is worth keeping at all: the team reasons about a list of
 * suspects, decides which one the evidence supports, and the chain it then
 * builds begins with that cause rather than beside it.
 *
 * The Why written is the chain's **first**, at `sequence = 1`, and its
 * statement is the cause's own unless the caller phrases it differently — a Why
 * IS a cause written as a question's answer, so the confirmed cause's sentence
 * is what the chain starts from, and a team that wants to say it another way
 * may. That this is the first Why is the whole convention: there is no
 * `cause_id` column recording where a chain came from (this section's header
 * argues why), and the consequence is the rule below.
 *
 * Three refusals, in the order a caller meets them:
 *
 *   - the cause must be one of **this** CAPA's fishbone rows — anything else,
 *     a Why's id included, is a 404 rather than a second way to write a chain;
 *   - it must be **confirmed** (409). A `candidate` is still a suspicion and a
 *     `ruled_out` one is a suspicion the evidence killed; starting a chain from
 *     either would make the fishbone's verdicts decorative, and the ticket's
 *     own words are that this is refused.
 *   - the **chain must not have started** (409). A chain has exactly one first
 *     Why, and which cause it began from is decided once; a chain that already
 *     has Whys is one somebody has been reasoning in, and the honest way to add
 *     to it is `addCapaWhy`.
 */
async function startCapaWhyFromCause(capaId, causeId, { chain, statement } = {}, accountId) {
  if (!CAPA_CHAINS.includes(chain)) {
    throw httpError(400, `chain must be one of: ${CAPA_CHAINS.join(', ')}`);
  }
  if (parseId(causeId) === null) throw notFound('candidate cause');
  const said =
    statement === undefined || statement === null ? null : requireWhyStatement(statement);

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    const { rows: [cause] } = await client.query(
      `SELECT r.id, r.statement, COALESCE(r.verdict, 'candidate') AS verdict
         FROM capa_root_causes r
        WHERE r.id = $1 AND r.capa_id = $2 AND r.cause_type = 'fishbone'
        FOR UPDATE`,
      [causeId, capaId]
    );
    if (!cause) throw notFound('candidate cause');
    if (cause.verdict !== 'confirmed') {
      throw httpError(
        409,
        `only a confirmed cause can start a chain, and this one is ${cause.verdict}`
      );
    }

    const { rows: [started] } = await client.query(
      `SELECT r.id
         FROM capa_root_causes r
        WHERE r.capa_id = $1 AND r.cause_type = 'why' AND r.chain = $2
        LIMIT 1`,
      [capaId, chain]
    );
    if (started) {
      throw httpError(
        409,
        `${chain} has already been started, so its first Why is written: a chain begins once`
      );
    }

    await client.query(
      `INSERT INTO capa_root_causes (capa_id, cause_type, chain, sequence, statement)
       VALUES ($1, 'why', $2, 1, $3)`,
      [capaId, chain, said ?? cause.statement]
    );

    return readCapaDetail(client, capaId);
  });
}

// ---------------------------------------------------------------------------
// The effectiveness check, and closing a CAPA (issue #211, ADR-0034)
//
// "The step every plant skips" — the baseline's own header on
// `effectiveness_verified_at`, which is "the field that separates a CAPA system
// from a list of good intentions", and the argument it makes is that skipping
// it is why the same problem comes back nine months later with a new number on
// it. ADR-0033 recorded the same rule one level down at the Action (`nothing
// closes unverified`); this is the CAPA's own, and the two meet here: a CAPA
// closes only when its investigation is finished *and* the fix has held, and a
// check that did not hold sends the Concern round again rather than closing
// anything.
//
// The life of the fact, in order, because the order is the whole design:
//
//   1. The Concern closes (its Act completes) — `beginCapaEffectivenessWait`
//      runs in that same transaction, sets the CAPA to `verifying` and writes
//      the date the check falls due: the day the Concern closed plus the
//      CAPA's own delay in days. The baseline's `capas_verification_due_idx`
//      is the index for exactly this read and becomes live here.
//   2. A holder of Quality authority at the CAPA's Org Unit who is **not the
//      team lead's Account** records the check, with a note and a verdict
//      (`recordEffectivenessCheck` below).
//   3. `effective` closes the CAPA — 8D's D8 — but only when both chains have
//      a confirmed root cause: the investigation has to have finished before
//      the fix is judged to have held, or the verdict is a coin toss. The due
//      date stays where it is, because it is the date the check was judged
//      against.
//   4. `not_effective` records the same three facts, reopens the Concern into
//      its next PDCA cycle (ADR-0033's own circle) and leaves the CAPA open.
//
// **Why the due date is cleared on a `not_effective` check.** The check is due
// *when the Concern is closed*, and a check that did not hold reopens it. There
// is therefore nothing due any more — the next one becomes due when the Concern
// closes again, and is set again with a fresh delay. Keeping the old date would
// leave the CAPA reading as overdue throughout the second round, which is
// exactly backwards: nobody can verify a fix whose countermeasures are still
// being rewritten. The verdict itself is not lost — `effectiveness_verified_at`
// is overwritten by the next check, and `effectiveness_note` with it, because
// the field says what the *last* check found; the rounds of the Concern's own
// phases are where "this took three goes" is read.
//
// **Why the CAPA's own status moves.** `verifying` is `closed`'s opposite
// number in the baseline's CHECK — the fix is in, nobody has proved it held,
// and a person has to decide something — and it is the one value of the seven
// that means precisely what step 1 produces. `actions` is where a check that
// did not hold puts it back: the countermeasures are being worked again, and
// the Concern's new Plan is the evidence. The client already carries both
// labels and their tones (`capaStatuses`), which is the schema's vocabulary
// being read rather than a state machine invented for this ticket.
//
// **What is deliberately not here.** No `capa_steps` row is written for the
// verification: ADR-0034 rejected "a CAPA owns its own 8D steps", and D8 is
// this table's own field. No phase is added to the *CAPA* either — a CAPA has
// no PDCA of its own, the Concern does — and no second close is possible: an
// effective check leaves `closed`, which `lockOpenCapa` refuses to touch again.
// ---------------------------------------------------------------------------

/**
 * Puts a CAPA whose Concern has just closed into the state where its
 * effectiveness check is due (issue #211) — step 1 of this section's own
 * account, and the only place a due date is ever set.
 *
 * The date is the day the Concern closed plus the CAPA's own delay, written
 * **now and not derived on read**, which is the decision the ticket leaves open
 * and migration 1800300000000 argues in full: "set when the Concern closes"
 * means an act with a time, and a derived date would move under a caller the
 * moment somebody revised the delay behind it — the date a check was judged
 * against has to survive the number that produced it.
 *
 * Called from `completePhase` inside the transaction that closes the Concern,
 * which is the only door that closes one: `action_items.status` cannot become
 * `done` any other way, because the phase log is what decides it (ADR-0033).
 * A Concern with no CAPA updates nothing — the subselect resolves `capa_id` to
 * null and no row matches — so this is a no-op for the overwhelming majority of
 * the log.
 *
 * The `NOT IN ('closed', 'cancelled')` guard is for a CAPA that somebody
 * closed and whose Concern then somehow closed again: an investigation that is
 * over must not be dragged back into `verifying` by its own subject moving.
 */
async function beginCapaEffectivenessWait(client, concernId) {
  await client.query(
    `UPDATE capas c
        SET status = 'verifying',
            effectiveness_check_due_at =
              (SELECT ai.completed_at::date FROM action_items ai WHERE ai.id = $1)
              + c.effectiveness_check_delay_days
      WHERE c.id = (SELECT ai.capa_id FROM action_items ai WHERE ai.id = $1)
        AND c.status NOT IN ('closed', 'cancelled')`,
    [concernId]
  );
}

/**
 * Reopens a Concern into its next PDCA cycle (issue #211, ADR-0033).
 *
 * The circle ADR-0033 records, arriving from the other direction. When an
 * Action's own Check says `not_effective`, `nextPhase` opens the next cycle's
 * Plan instead of the Act. Here the Action has already closed — its countermeasure
 * held as far as the plant could see — and it is the *verification* two weeks
 * later that found it did not, which is precisely the failure mode the baseline's
 * CAPA header describes ("why the same problem comes back nine months later with
 * a new number on it").
 *
 * So the same two statements that a `not_effective` Check makes, in the same
 * order and the same transaction: a Plan at `MAX(cycle) + 1`, carrying the
 * Concern's own owner and due date (a phase born with neither is a row nothing
 * can triage), and the Action back to `in_progress`. Nothing is written *on* the
 * new Plan's note: a phase's note is what the person who completes it says, and
 * the reason this round exists is already on the CAPA — its `effectiveness_note`
 * and the time it was recorded.
 *
 * `completed_at` is cleared, because the Action is not closed any more, and the
 * record of when it *was* is not lost: cycle N's Act row carries its own
 * completion, in the log that is the whole point of ADR-0033's design.
 */
async function reopenConcernIntoNextCycle(client, concernId) {
  const { rows: [next] } = await client.query(
    `SELECT COALESCE(MAX(cycle), 0) + 1 AS cycle
       FROM action_phases
      WHERE action_item_id = $1`,
    [concernId]
  );

  await client.query(
    `INSERT INTO action_phases (action_item_id, cycle, phase, owner_employee_id, due_date)
     SELECT id, $2, 'plan', owner_employee_id, due_date
       FROM action_items WHERE id = $1`,
    [concernId, next.cycle]
  );

  await client.query(
    `UPDATE action_items SET status = 'in_progress', completed_at = NULL WHERE id = $1`,
    [concernId]
  );
}

/**
 * Records the effectiveness check on a CAPA (issue #211) and does what the
 * verdict implies: closes the investigation, or sends the Concern round again.
 *
 * Four refusals, and each is a fact about the rows this is about, read under
 * locks:
 *
 *   - the CAPA must exist (404) and be open (409) — `lockOpenCapa`, the same
 *     one every other write to a closed investigation takes,
 *   - its Concern must be **closed** (409). A check on a problem whose fix is
 *     still being written is not an early check, it is a check of nothing: the
 *     date the check is due is produced by the closure in the first place,
 *   - `outcome` must be one of the two verdicts and `note` must say something
 *     (400) — a verdict with no evidence is the "list of good intentions" this
 *     step exists to refuse, and the note is the only place the evidence goes,
 *   - `effective` requires **a confirmed root cause in both chains** (409). The
 *     investigation finishes before the fix is judged to have held; otherwise
 *     an `effective` verdict is a guess about a problem nobody has understood
 *     yet. ADR-0034's own sentence — the CAPA's root causes are what make its
 *     verification mean anything.
 *
 * The verdict is not a Partial update and is not idempotent: recording a check
 * answers a question that was open, and the answer is `effective` exactly once
 * for an investigation. A second check on a closed CAPA is the 409 above; a
 * second check after a `not_effective` is the *next* round's check, and is
 * refused until that Concern closes again.
 *
 * The answer is the whole CAPA as it now reads, like every other write in this
 * slice — the caller's Screen is showing the investigation, and it wants the
 * status, the due date and the verifier it just produced.
 */
async function recordEffectivenessCheck(capaId, { outcome, note } = {}, accountId) {
  requireMemberOf('outcome', outcome, CHECK_OUTCOMES);
  requireNonEmptyString('note', note);
  const said = note.trim();

  return withActor(accountId, async (client) => {
    await lockOpenCapa(client, capaId);

    // The Concern, locked: its status decides whether there is anything to
    // check, and a Concern that closes between this read and the write below
    // must not be able to change the answer. At most one row, by
    // `action_items_capa_id_once`; a CAPA that answers no Concern at all
    // (impossible through this API) takes the same refusal, because there is
    // nothing whose effectiveness could be checked either way.
    const { rows: [concern] } = await client.query(
      `SELECT id, status FROM action_items WHERE capa_id = $1 FOR UPDATE`,
      [capaId]
    );
    if (!concern || concern.status !== 'done') {
      throw httpError(
        409,
        "this CAPA's Concern is not closed, so there is nothing to check yet"
      );
    }

    if (outcome === 'effective') {
      const { rows: roots } = await client.query(
        `SELECT r.chain
           FROM capa_root_causes r
          WHERE r.capa_id = $1 AND r.cause_type = 'why' AND r.is_root`,
        [capaId]
      );
      const missing = CAPA_CHAINS.filter(
        (chain) => !roots.some((root) => root.chain === chain)
      );
      if (missing.length > 0) {
        throw httpError(
          409,
          'a CAPA closes effective only when both chains have a confirmed root cause, and ' +
            `this one has none for: ${missing.join(', ')}`
        );
      }

      // `capas_eightd_needs_verification` is satisfied by the timestamp and
      // `capas_closed_has_time` by `closed_at`; the account is written beside
      // them because it is who decided, not because a constraint asks (see the
      // migration's header). The due date is left alone: it is the date this
      // check was judged against.
      await client.query(
        `UPDATE capas
            SET status = 'closed',
                closed_at = now(),
                effectiveness_verified_at = now(),
                effectiveness_verified_by_account_id = $2,
                effectiveness_note = $3
          WHERE id = $1`,
        [capaId, accountId, said]
      );
    } else {
      await client.query(
        `UPDATE capas
            SET status = 'actions',
                effectiveness_check_due_at = NULL,
                effectiveness_verified_at = now(),
                effectiveness_verified_by_account_id = $2,
                effectiveness_note = $3
          WHERE id = $1`,
        [capaId, accountId, said]
      );
      await reopenConcernIntoNextCycle(client, concern.id);
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
  // team, its problem description and its effectiveness delay, and the two
  // facts a route needs to ask its own questions about it.
  CAPA_METHOD,
  CAPA_STATUSES,
  CAPA_EFFECTIVENESS_DELAY_DAYS,
  findCapa,
  getCapaDetail,
  listCapas,
  openCapa,
  updateCapa,
  // ...and its two 5 Why chains (issue #210): adding a Why to one, revising,
  // moving, marking or removing one. `CAPA_CHAINS` is this file's vocabulary of
  // the chains, exported beside `CAPA_METHOD` for the same reason — the
  // Module's own closed sets are what its callers and its tests name, not
  // string literals scattered through them.
  CAPA_CHAINS,
  addCapaWhy,
  updateCapaWhy,
  removeCapaWhy,
  // ...and its fishbone (issue #213): candidate causes by 6M category, the
  // verdict and the evidence behind it, and the one door from a confirmed
  // cause into a chain. `CAPA_CAUSE_CATEGORIES` and `CAPA_CAUSE_VERDICTS` are
  // exported beside `CAPA_CHAINS` for the same reason: the Module's own closed
  // sets are what its callers and its tests name.
  CAPA_CAUSE_CATEGORIES,
  CAPA_CAUSE_VERDICTS,
  addCapaCause,
  updateCapaCause,
  removeCapaCause,
  startCapaWhyFromCause,
  // ...and its effectiveness check (issue #211): recording the verdict that
  // closes the investigation or sends its Concern round again. Where `#210`'s
  // chains are the team's own reasoning, this is the one act a CAPA does not
  // let the team do to itself — see the route's own gate.
  recordEffectivenessCheck
};
