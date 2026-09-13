/*
 * Job plans (issue #74), the reusable description of a recurring job — the
 * steps it takes and what each one needs. Same shape as assets.js and
 * work-orders.js, and the same rule holds: this file never requires
 * '../people' and never resolves or writes a People record. Job plans are an
 * administrator-managed shared catalogue (ADR-0005's shape), NOT Org-Unit
 * scoped: a plan means the same thing wherever it is used, and the write is
 * gated on the administrator role by job-plan-routes.js, not on a Grant.
 *
 * Cross-Module reads are ordinary joins here, exactly as assets.js and
 * work-orders.js already do (ADR-0006): `skills` (People's table) is joined
 * so a task carries its required Skill's NAME rather than an id the caller
 * would have to resolve separately. Nothing here writes a People row.
 *
 * A job plan is deliberately distinct from the work order that carries it out
 * (CONTEXT.md's Job plan): the plan is the instructions, the work order is one
 * particular occasion of following them. `work_order_tasks` is copied from
 * `job_plan_tasks` at raise time (pm-schedules.js), never read through the
 * plan afterward, so a plan revised next year cannot rewrite what a
 * technician was told to do last year.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// Mirrors the CHECK constraint on job_plans.work_type in the baseline, so a
// bad value is a 400 with a clear message rather than a raw constraint
// violation. Deliberately narrower than work_orders.WORK_TYPES: a generated
// job plan describes planned work, so 'corrective' and 'improvement' are not
// offered here.
const JOB_PLAN_WORK_TYPES = ['preventive', 'predictive', 'inspection', 'calibration'];

// Every field a job plan carries, prefixed for the joins below. Mirrors
// ASSET_COLUMNS/WORK_ORDER_COLUMNS' own shape.
const JOB_PLAN_COLUMNS = `
  jp.id, jp.code, jp.name, jp.description, jp.work_type, jp.estimated_hours,
  jp.requires_shutdown, jp.safety_note, jp.is_active
`;

// A task row, carrying the required Skill's name from the join and the
// NUMERIC estimated_hours converted to a Number (node-postgres hands NUMERIC
// back as a string).
const JOB_PLAN_TASK_COLUMNS = `
  t.id, t.job_plan_id, t.step_no, t.instruction, t.skill_id, t.estimated_hours,
  t.records_meter_id,
  s.name AS skill_name,
  am.code AS meter_code, am.name AS meter_name
`;

function toJobPlan(row, tasks) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    description: row.description,
    workType: row.work_type,
    estimatedHours: row.estimated_hours === null ? null : Number(row.estimated_hours),
    requiresShutdown: row.requires_shutdown,
    safetyNote: row.safety_note,
    isActive: row.is_active,
    tasks
  };
}

function toJobPlanTask(row) {
  return {
    id: row.id,
    stepNo: row.step_no,
    instruction: row.instruction,
    skillId: row.skill_id,
    skillName: row.skill_name ?? null,
    estimatedHours: row.estimated_hours === null ? null : Number(row.estimated_hours),
    // The meter a step records a number against, if any (issue #79). Copied
    // onto the Work order task at raise time; null for a step that records no
    // number.
    recordsMeterId: row.records_meter_id ?? null,
    meterCode: row.meter_code ?? null,
    meterName: row.meter_name ?? null
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// `estimatedHours` is optional on both the plan and a task. Present, it must
// be a non-negative number; absent (or null) it is null. A JSON boolean or a
// string is refused rather than coerced, because `Number('')` is 0 and would
// silently record a value nobody meant.
function resolveEstimatedHours(field, value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw httpError(400, `${field} must be a non-negative number`);
  }
  return value;
}

// `requiresShutdown` is optional and defaults false. Anything present that is
// not a JSON boolean is a 400 — a string 'false' is truthy and would silently
// record the opposite of what was meant.
function resolveRequiresShutdown(value) {
  if (value === undefined || value === null) return false;
  if (typeof value !== 'boolean') {
    throw httpError(400, 'requiresShutdown must be a boolean');
  }
  return value;
}

// Domain validation of the task list, done before any query: each task must
// name an instruction and a unique, positive stepNo; a skillId, when given,
// must be a real id. Returns a step-ordered, normalized list so both the
// INSERT and the response agree on order.
function normalizeTasks(tasks) {
  if (tasks === undefined || tasks === null) return [];
  if (!Array.isArray(tasks)) throw httpError(400, 'tasks must be an array');

  const seenStepNos = new Set();
  const normalized = tasks.map((task) => {
    if (task === null || typeof task !== 'object') {
      throw httpError(400, 'each task must be an object');
    }

    const stepNo = task.stepNo;
    if (!Number.isInteger(stepNo) || stepNo < 1) {
      throw httpError(400, 'each task stepNo must be a positive integer');
    }
    if (seenStepNos.has(stepNo)) {
      throw httpError(400, `stepNo ${stepNo} is used more than once`);
    }
    seenStepNos.add(stepNo);

    requireNonEmptyString('each task instruction', task.instruction);

    let skillId = null;
    if (task.skillId !== undefined && task.skillId !== null) {
      skillId = parseId(task.skillId);
      if (skillId === null) {
        throw httpError(400, 'each task skillId must be a valid Skill id');
      }
    }

    // The meter this step records a number against, if any (issue #79). A
    // malformed id is refused here; whether it names a real meter is checked
    // once for the whole plan before the insert.
    let recordsMeterId = null;
    if (task.recordsMeterId !== undefined && task.recordsMeterId !== null) {
      recordsMeterId = parseId(task.recordsMeterId);
      if (recordsMeterId === null) {
        throw httpError(400, 'each task recordsMeterId must be a valid Meter id');
      }
    }

    return {
      stepNo,
      instruction: task.instruction.trim(),
      skillId,
      estimatedHours: resolveEstimatedHours('each task estimatedHours', task.estimatedHours),
      recordsMeterId
    };
  });

  return normalized.sort((a, b) => a.stepNo - b.stepNo);
}

// A backstop, not the primary defence. `job_plans.code` is UNIQUE globally, so
// a clash is a 409 naming the code rather than a raw unique violation. A task
// naming a Skill that does not exist surfaces as 23503; it is mapped to a 404
// naming the Skill, the same "existence" answer an unknown Asset gets, rather
// than Postgres's own message (which names tables and columns).
function mapJobPlanWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'a Job plan with this code already exists');
  }
  if (error.code === '23503') {
    return notFound('Skill');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Job plan');
  }
  return error;
}

// Groups task rows by their job_plan_id, ordered step_no within each plan.
// `db` is either the pool or a transaction client, so the same helper serves
// both a Site-wide read and a re-read inside createJobPlan's transaction.
async function loadTasksByPlan(db, planIds) {
  const byPlan = new Map();
  if (planIds.length === 0) return byPlan;

  const { rows } = await db.query(
    `SELECT ${JOB_PLAN_TASK_COLUMNS}
       FROM job_plan_tasks t
       LEFT JOIN skills s ON s.id = t.skill_id
       LEFT JOIN asset_meters am ON am.id = t.records_meter_id
      WHERE t.job_plan_id = ANY($1::bigint[])
      ORDER BY t.job_plan_id, t.step_no`,
    [planIds]
  );

  for (const row of rows) {
    const key = String(row.job_plan_id);
    if (!byPlan.has(key)) byPlan.set(key, []);
    byPlan.get(key).push(toJobPlanTask(row));
  }
  return byPlan;
}

// one plan + its tasks, on whichever connection is handed in. Null when the
// id names nothing, so callers get a value rather than a thrown 404 (the
// route owns the wording).
async function readJobPlan(db, id) {
  const { rows: [row] } = await db.query(
    `SELECT ${JOB_PLAN_COLUMNS} FROM job_plans jp WHERE jp.id = $1`,
    [id]
  );
  if (!row) return null;
  const tasksByPlan = await loadTasksByPlan(db, [row.id]);
  return toJobPlan(row, tasksByPlan.get(String(row.id)) ?? []);
}

// The shared catalogue in full, or active-only when a caller asks for that by
// name. Readable by any approved Account — it is a shared catalogue (ADR-0005),
// not an Org-Unit-scoped record. Ordered by name then code so the list reads
// the same way twice.
async function listJobPlans({ includeInactive = true } = {}) {
  const activeClause = includeInactive ? '' : 'WHERE jp.is_active';
  const { rows } = await getPool().query(
    `SELECT ${JOB_PLAN_COLUMNS}
       FROM job_plans jp
       ${activeClause}
      ORDER BY jp.name, jp.code`
  );

  const tasksByPlan = await loadTasksByPlan(getPool(), rows.map((row) => row.id));
  return rows.map((row) => toJobPlan(row, tasksByPlan.get(String(row.id)) ?? []));
}

// The null-returning lookup this Module's own routes use before a write, the
// same shape assets.js's findAsset has: total, so a malformed id answers null
// rather than handing Postgres a non-numeric BIGINT and turning a 404 into a
// 500.
async function findJobPlan(id) {
  if (parseId(id) === null) return null;
  return readJobPlan(getPool(), id);
}

// Creates a plan and its tasks in one transaction, so a plan is never half
// written. `code` and `name` are required by the table; `description`,
// `estimatedHours`, `requiresShutdown` and `safetyNote` are the plan's own
// optional fields. The action is gated on the administrator role by
// job-plan-routes.js, before this ever runs.
async function createJobPlan(
  { code, name, description, workType, estimatedHours, requiresShutdown, safetyNote, tasks },
  accountId
) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  if (!JOB_PLAN_WORK_TYPES.includes(workType)) {
    throw httpError(400, `workType must be one of: ${JOB_PLAN_WORK_TYPES.join(', ')}`);
  }
  const resolvedEstimatedHours = resolveEstimatedHours('estimatedHours', estimatedHours);
  const resolvedRequiresShutdown = resolveRequiresShutdown(requiresShutdown);
  const normalizedTasks = normalizeTasks(tasks);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [plan] } = await client.query(
        `INSERT INTO job_plans
           (code, name, description, work_type, estimated_hours, requires_shutdown, safety_note)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          code.trim(),
          name.trim(),
          description ?? null,
          workType,
          resolvedEstimatedHours,
          resolvedRequiresShutdown,
          safetyNote ?? null
        ]
      );

      // A task's meter is checked once for the whole plan, so an unknown one
      // is a clean 404 naming the Meter rather than the foreign key's own
      // error (which names tables and columns, and cannot say which of the
      // two references — Skill or Meter — was at fault).
      const meterIds = [
        ...new Set(normalizedTasks.map((task) => task.recordsMeterId).filter((id) => id !== null))
      ];
      if (meterIds.length > 0) {
        const { rows: found } = await client.query(
          `SELECT id FROM asset_meters WHERE id = ANY($1::bigint[])`,
          [meterIds]
        );
        if (found.length !== meterIds.length) throw notFound('Meter');
      }

      for (const task of normalizedTasks) {
        await client.query(
          `INSERT INTO job_plan_tasks
             (job_plan_id, step_no, instruction, skill_id, estimated_hours, records_meter_id)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [plan.id, task.stepNo, task.instruction, task.skillId, task.estimatedHours, task.recordsMeterId]
        );
      }

      return readJobPlan(client, plan.id);
    });
  } catch (error) {
    throw mapJobPlanWriteError(error);
  }
}

// Deactivation, never deletion: an inactive plan stays readable, and a work
// order already copied from it keeps its copied tasks (job-plan-routes.js's
// own header). Reinstating is the same write with isActive true.
async function setJobPlanActive(id, isActive, accountId) {
  if (typeof isActive !== 'boolean') {
    throw httpError(400, 'isActive (boolean) is required');
  }
  const plan = await findJobPlan(id);
  if (!plan) throw notFound('Job plan');

  try {
    return await withActor(accountId, async (client) => {
      await client.query('UPDATE job_plans SET is_active = $1 WHERE id = $2', [isActive, plan.id]);
      return readJobPlan(client, plan.id);
    });
  } catch (error) {
    throw mapJobPlanWriteError(error);
  }
}

module.exports = {
  JOB_PLAN_WORK_TYPES,
  listJobPlans,
  findJobPlan,
  createJobPlan,
  setJobPlanActive
};
