/*
 * The job role catalogue (issue #10, CONTEXT.md's Employee definition and
 * ADR-0005's "one catalogue, shared by every Site"). `job_roles` is a
 * baseline table with no `site_id` column at all — the catalogue is
 * plant-wide by construction, not by a query that happens to omit a filter,
 * which is what makes issue #10's first acceptance criterion ("Job roles are
 * defined once and shared by every Site") true without anything further to
 * build here.
 *
 * Mirrors plant.js/directory.js exactly: this file knows nothing about HTTP
 * or about who is calling — job-role-routes.js owns authenticate/
 * requireActive/requireAdmin, the same split those two files document in
 * their own headers.
 *
 * Deactivation, never deletion, following plant.js's setOrgUnitActive and
 * ADR-0009's own Employee-history reasoning: a job role that has been held is
 * history, and `employee_assignments.job_role_id` may still point at a
 * deactivated one.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

const JOB_ROLE_COLUMNS = 'id, code, name, is_active, created_at, updated_at';

function toJobRole(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A write against `job_roles` can fail for one reason this file turns into a
// clean 4xx rather than a 500: the `code` UNIQUE constraint, named
// `job_roles_code_key` (confirmed against the actual error Postgres raises
// for an inline `UNIQUE` column constraint, not assumed). Anything else is a
// genuine failure and is rethrown as-is, same as mapEmployeeWriteError/
// mapSiteWriteError.
function mapJobRoleWriteError(error) {
  if (error.code === '23505' && error.constraint === 'job_roles_code_key') {
    return httpError(409, 'a job role with this code already exists');
  }
  return error;
}

// Active job roles by default, ordered by name — includeInactive widens to
// every job role. Any approved Account needs this list to filter the
// directory by job role (directory-routes.js's own GET /employees), so this
// carries no admin/scope requirement at all; see job-role-routes.js's header.
async function listJobRoles({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT ${JOB_ROLE_COLUMNS} FROM job_roles ${whereClause} ORDER BY name`
  );
  return rows.map(toJobRole);
}

// Mirrors plant.getOrgUnit/directory.getEmployee exactly: null id and "no
// such row" are both a 404, one query. directory.js's createAssignment calls
// this to resolve a jobRoleId the same way it resolves an orgUnitId through
// plant.getOrgUnit.
async function getJobRole(id) {
  if (id === null) throw notFound('Job role');
  const { rows } = await getPool().query(
    `SELECT ${JOB_ROLE_COLUMNS} FROM job_roles WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Job role');
  return toJobRole(rows[0]);
}

async function createJobRole({ code, name } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO job_roles (code, name) VALUES ($1, $2) RETURNING ${JOB_ROLE_COLUMNS}`,
        [code.trim(), name.trim()]
      );
      return toJobRole(row);
    });
  } catch (error) {
    throw mapJobRoleWriteError(error);
  }
}

// input's keys, mapped to their column — code, name and isActive are all
// optional, following updateEmployee's own hasOwnProperty idiom: an absent
// key never touches its column, so a one-field PATCH cannot blank the others.
const JOB_ROLE_WRITABLE_COLUMNS = {
  code: 'code',
  name: 'name',
  isActive: 'is_active'
};

async function updateJobRole(id, input, accountId) {
  await getJobRole(id); // 404s if it does not exist.

  const body = input ?? {};
  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(JOB_ROLE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'code') requireNonEmptyString('code', value);
    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than issuing
    // an UPDATE with an empty SET list (which Postgres would reject outright).
    return getJobRole(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE job_roles SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING ${JOB_ROLE_COLUMNS}`,
        params
      );
      return toJobRole(row);
    });
  } catch (error) {
    throw mapJobRoleWriteError(error);
  }
}

module.exports = {
  listJobRoles,
  getJobRole,
  createJobRole,
  updateJobRole
};
