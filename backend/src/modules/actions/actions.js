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
 * write in the Platform: *raising a Concern needs only a read Grant reaching
 * its Org Unit*, because a concern is a report rather than a decision. The
 * route asks `canAct` with `write: false` and says so in its own comment.
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
  ai.created_at, ai.updated_at,
  ou.code AS org_unit_code, ou.name AS org_unit_name, ou.site_id,
  e.display_name AS owner_name,
  rb.display_name AS raised_by_name,
  esc.code AS escalated_to_org_unit_code, esc.name AS escalated_to_org_unit_name,
  op.phase AS open_phase, op.cycle AS open_phase_cycle,
  to_char(op.due_date, 'YYYY-MM-DD') AS open_phase_due_date,
  op.owner_employee_id AS open_phase_owner_id,
  ope.display_name AS open_phase_owner_name,
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

// The detail read (issue #176, grown by #177). `parent` and `measures` are part
// of the shape from the start so that no client read has to change when issue
// #178 fills them: an Action that answers nothing has an empty measures array,
// which is not the same thing as a missing field. `phases` carries every cycle
// the Action has been round, oldest first — the record of a Check that failed
// and sent it round again is the point of keeping them (ADR-0033).
function toActionDetail(row, phases = [], measures = []) {
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
    phases
  };
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
    await listMeasures(rows[0].id)
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
  { raisedBy = null } = {}
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
            owner_employee_id, due_date, priority, raised_by)
         VALUES
           (next_document_number('AC', (SELECT code FROM site), EXTRACT(YEAR FROM now())::int),
            $1, $2, $3, $4, $5, $6, $7::date, $8, $9)
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
          raisedBy
        ]
      );

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
  createAction,
  createMeasure,
  completePhase,
  cancelAction,
  escalationTargets,
  escalateAction
};
