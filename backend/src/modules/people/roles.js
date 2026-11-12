/*
 * Roles and the permissions they carry (issue #492, ADR-0061).
 *
 * Three questions this file answers, and nowhere else in the People Module
 * does:
 *
 *   - "Which permission codes does this Account hold right now?" —
 *     effectivePermissions below. Three sources union together: the roles
 *     every Account holds (`app_roles.is_default`), the role that the
 *     Account's own `app_users.role` earns automatically
 *     (`app_roles.legacy_role`), and the roles an administrator assigned it
 *     (`app_user_roles`). An administrator is answered with the whole
 *     catalogue before the union is even asked — see the note above
 *     effectivePermissions for why that short-circuit exists.
 *   - "What does a role carry, and who holds it?" — listRoles/getRole, which
 *     is what the Roles Screen reads and what an administrator edits.
 *   - "Put this person in this group, and press Assign" — assignAccountRoles,
 *     a replace of that Account's explicit assignment in one transaction, so a
 *     half-applied assignment cannot exist.
 *
 * Mirrors job-roles.js exactly: no HTTP here (role-routes.js owns
 * authenticate/requireActive/requirePermission), and writes go through
 * `withActor` so `created_by`/`updated_by` are filled by the database's own
 * trigger rather than by a caller-supplied id.
 *
 * **Permissions are read-only here.** The catalogue comes from
 * `permissions.js` and the migration that seeded `permissions`; nothing in
 * this file creates a code. A code the caller sends that this image does not
 * know is dropped by `knownPermissionCodes` rather than refused — an editor
 * holding a code from a newer release must not make the save fail (see that
 * function's own comment), and the response says what was actually stored.
 *
 * **A role's permission set is replaced, never patched.** `PUT
 * /roles/:id/permissions` sends the whole set because that is what an
 * administrator just did: they opened the list, ticked and unticked, and
 * pressed Save. A patch of additions and removals would need the editor to
 * know what the server holds, and the two would drift the first time two
 * administrators had the Screen open at once.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');
const { knownPermissionCodes } = require('./permissions');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// The columns every role read shares. `holder_count` answers "who does this
// touch" the way an administrator asks it: for a default or automatic role,
// every Account that holds it by virtue of its own `role` (not a row an
// administrator can point at); for an ordinary role, the assignments.
const ROLE_SELECT = `
  SELECT r.id,
         r.code,
         r.name,
         r.description,
         r.is_default,
         r.legacy_role,
         r.is_active,
         r.created_at,
         r.updated_at,
         COALESCE(
           array_agg(DISTINCT rp.permission_code)
             FILTER (WHERE rp.permission_code IS NOT NULL),
           '{}'
         ) AS permission_codes,
         CASE
           WHEN r.is_default THEN (SELECT count(*) FROM app_users)
           WHEN r.legacy_role IS NOT NULL
             THEN (SELECT count(*) FROM app_users u WHERE u.role = r.legacy_role)
           ELSE (SELECT count(*) FROM app_user_roles ur WHERE ur.app_role_id = r.id)
         END::int AS holder_count
  FROM app_roles r
  LEFT JOIN app_role_permissions rp ON rp.app_role_id = r.id
`;

function toRole(row) {
  return {
    id: String(row.id),
    code: row.code,
    name: row.name,
    description: row.description,
    isDefault: row.is_default,
    legacyRole: row.legacy_role,
    isActive: row.is_active,
    permissionCodes: row.permission_codes,
    holderCount: row.holder_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// The order an administrator reads a role list in: the group everyone holds
// first, then the five account-role groups in the order the Accounts Screen
// itself offers them, then whatever an administrator added.
const ROLE_ORDER = `
  ORDER BY r.is_default DESC,
           array_position(ARRAY['operator', 'supervisor', 'engineer', 'manager', 'admin'],
                          r.legacy_role) NULLS LAST,
           r.code
`;

async function listRoles({ includeInactive = false } = {}) {
  const { rows } = await getPool().query(
    `${ROLE_SELECT}
     ${includeInactive ? '' : 'WHERE r.is_active'}
     GROUP BY r.id
     ${ROLE_ORDER}`
  );
  return rows.map(toRole);
}

async function getRole(id) {
  if (id === null) throw notFound('Role');
  const { rows } = await getPool().query(
    `${ROLE_SELECT} WHERE r.id = $1 GROUP BY r.id`,
    [id]
  );
  if (!rows[0]) throw notFound('Role');
  return toRole(rows[0]);
}

// The catalogue, in the sidebar's own order, for the editor to draw. Read from
// the table rather than from `permissions.js` so the Screen shows what this
// database actually holds; `test/integration/roles.test.js` is what proves the
// two agree.
async function listPermissions() {
  const { rows } = await getPool().query(
    `SELECT code, module, label, description, sort_order
       FROM permissions
      ORDER BY sort_order`
  );
  return rows.map((row) => ({
    code: row.code,
    module: row.module,
    label: row.label,
    description: row.description
  }));
}

function mapRoleWriteError(error) {
  if (error.code === '23505' && error.constraint === 'app_roles_code_key') {
    return httpError(409, 'a role with this code already exists');
  }
  if (error.code === '23514' && error.constraint === 'app_roles_code_shape') {
    return httpError(400, 'a role code is 3 to 30 characters: A-Z, 0-9 and underscore');
  }
  if (error.code === '23505' && error.constraint === 'app_roles_one_default') {
    return httpError(409, 'there is already a default role; retire it or make it ordinary first');
  }
  return error;
}

// A role code is typed by an administrator into a request for access, so it is
// normalised once here rather than at every read: upper-case, trimmed. The
// database's own CHECK (app_roles_code_shape) is what refuses a shape that
// cannot be a code — this only spares the caller a 500 for the common typo of
// lower case.
function normaliseCode(code) {
  requireNonEmptyString('code', code);
  return code.trim().toUpperCase();
}

async function createRole({ code, name, description, permissions } = {}, accountId) {
  const normalisedCode = normaliseCode(code);
  requireNonEmptyString('name', name);
  const codes = knownPermissionCodes(permissions);

  let createdId;
  try {
    createdId = await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO app_roles (code, name, description)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [normalisedCode, name.trim(), typeof description === 'string' ? description.trim() : '']
      );

      if (codes.length > 0) {
        await client.query(
          `INSERT INTO app_role_permissions (app_role_id, permission_code)
           SELECT $1, code FROM unnest($2::text[]) AS code`,
          [row.id, codes]
        );
      }

      return String(row.id);
    });
  } catch (error) {
    throw mapRoleWriteError(error);
  }

  // Read after the transaction commits: getRole reads through the pool, which
  // cannot see a row its own uncommitted transaction just wrote.
  return getRole(createdId);
}

const ROLE_WRITABLE_COLUMNS = {
  name: 'name',
  description: 'description',
  isActive: 'is_active'
};

async function updateRole(id, input, accountId) {
  await getRole(id); // 404s if it does not exist.

  const body = input ?? {};
  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(ROLE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'description' && typeof value !== 'string') {
      throw httpError(400, 'description must be a string');
    }
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) return getRole(id);

  params.push(id);
  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE app_roles SET ${sets.join(', ')} WHERE id = $${params.length}`,
        params
      );
    });
  } catch (error) {
    throw mapRoleWriteError(error);
  }

  return getRole(id);
}

// Replace a role's permission set. The delete-then-insert runs in one
// transaction so no reader ever sees the role carrying nothing.
async function setRolePermissions(id, permissions, accountId) {
  await getRole(id); // 404s if it does not exist.
  const codes = knownPermissionCodes(permissions);

  await withActor(accountId, async (client) => {
    await client.query('DELETE FROM app_role_permissions WHERE app_role_id = $1', [id]);
    if (codes.length > 0) {
      await client.query(
        `INSERT INTO app_role_permissions (app_role_id, permission_code)
         SELECT $1, code FROM unnest($2::text[]) AS code`,
        [id, codes]
      );
    }
  });

  return getRole(id);
}

// One Account's view of every role: which it holds automatically (and so
// cannot be given or taken away), which an administrator assigned, and which
// are on offer. This is the shape the Assign dialog draws — a checkbox that
// cannot be unticked for a default or automatic role is the truthful picture
// of "every Account holds this".
async function accountRoles(accountId) {
  const { rows: [account] } = await getPool().query(
    'SELECT id, role FROM app_users WHERE id = $1',
    [accountId]
  );
  if (!account) throw notFound('Account');

  const { rows: assigned } = await getPool().query(
    'SELECT app_role_id FROM app_user_roles WHERE app_user_id = $1',
    [accountId]
  );
  const assignedIds = new Set(assigned.map((row) => String(row.app_role_id)));

  const roles = await listRoles();
  return {
    accountId: String(account.id),
    accountRole: account.role,
    roles: roles.map((role) => ({
      ...role,
      isAutomatic: role.isDefault || role.legacyRole !== null,
      isAssigned: assignedIds.has(role.id)
    }))
  };
}

// The Assign button. `roleIds` is the complete set of explicit assignments
// wanted for this Account — replace, not patch, for the same reason
// setRolePermissions replaces.
//
// A role that an Account already holds automatically is refused rather than
// silently accepted: a row in `app_user_roles` for it would change nothing,
// and answering 200 to a request that did nothing is the kind of quiet lie
// that makes an administrator believe they revoke access by unticking a box
// the server owns.
async function assignAccountRoles(accountId, roleIds, actorId) {
  const { rows: [account] } = await getPool().query(
    'SELECT id, role FROM app_users WHERE id = $1',
    [accountId]
  );
  if (!account) throw notFound('Account');

  if (!Array.isArray(roleIds)) {
    throw httpError(400, 'roleIds must be an array of role ids');
  }

  const wanted = [...new Set(roleIds.map((id) => String(id)))];

  if (wanted.length > 0) {
    const { rows: found } = await getPool().query(
      `SELECT id, code, is_default, legacy_role, is_active
         FROM app_roles
        WHERE id = ANY($1::bigint[])`,
      [wanted]
    );

    const byId = new Map(found.map((row) => [String(row.id), row]));
    for (const id of wanted) {
      const role = byId.get(id);
      if (!role) throw notFound('Role');
      if (role.is_default || role.legacy_role !== null) {
        throw httpError(
          400,
          `${role.code} is held automatically by the Accounts it applies to and is not assignable`
        );
      }
      if (!role.is_active) {
        throw httpError(400, `${role.code} is retired and cannot be assigned`);
      }
    }
  }

  await withActor(actorId, async (client) => {
    await client.query('DELETE FROM app_user_roles WHERE app_user_id = $1', [accountId]);
    if (wanted.length > 0) {
      await client.query(
        `INSERT INTO app_user_roles (app_user_id, app_role_id)
         SELECT $1, id FROM unnest($2::bigint[]) AS id`,
        [accountId, wanted]
      );
    }
  });

  return accountRoles(accountId);
}

// Which roles put this Account where it is — the `roles` half of `/me`, so a
// client can say "you are in Standard and Supervisor" without guessing at the
// union. Same three sources as effectivePermissions, without the
// administrator's short-circuit: an administrator's own stored roles are
// exactly what an administrator set up, and reporting ROLE_ADMIN here is
// truthful even though the check short-circuits.
async function roleCodesForAccount(account) {
  const { rows } = await getPool().query(
    `SELECT DISTINCT r.code
       FROM app_roles r
      WHERE r.is_active
        AND (r.is_default
             OR r.legacy_role = $1
             OR EXISTS (SELECT 1 FROM app_user_roles ur
                         WHERE ur.app_role_id = r.id AND ur.app_user_id = $2))
      ORDER BY r.code`,
    [account.role, account.id]
  );
  return rows.map((row) => row.code);
}

// The effective set, as `{ code, module, label }` ordered the way the sidebar
// groups render.
//
// **An administrator holds every permission, before any role is read.** This
// is the one deliberate short-circuit in the model (SAP's SAP_ALL profile, and
// the reason a mis-edited role cannot lock the last administrator out of the
// Platform). It is stated in ADR-0061 rather than left as a surprise, and it
// is why ROLE_ADMIN's seeded permission list is documentation of the fact
// rather than the mechanism that produces it.
//
// Not cached anywhere: like `canAct`, this reads the tables on every request,
// so an administrator's edit — or an assignment — takes effect on the
// affected Account's very next request rather than at its next sign-in.
async function effectivePermissions(account) {
  if (account.role === 'admin') {
    const { rows } = await getPool().query(
      'SELECT code, module, label FROM permissions ORDER BY sort_order'
    );
    return rows;
  }

  const { rows } = await getPool().query(
    `SELECT code, module, label
       FROM (
         SELECT DISTINCT p.code, p.module, p.label, p.sort_order
           FROM permissions p
           JOIN app_role_permissions rp ON rp.permission_code = p.code
           JOIN app_roles r ON r.id = rp.app_role_id AND r.is_active
          WHERE r.is_default
             OR r.legacy_role = $1
             OR EXISTS (SELECT 1 FROM app_user_roles ur
                         WHERE ur.app_role_id = r.id AND ur.app_user_id = $2)
       ) held
      ORDER BY sort_order`,
    [account.role, account.id]
  );
  return rows;
}

module.exports = {
  listRoles,
  getRole,
  listPermissions,
  createRole,
  updateRole,
  setRolePermissions,
  accountRoles,
  assignAccountRoles,
  roleCodesForAccount,
  effectivePermissions
};
