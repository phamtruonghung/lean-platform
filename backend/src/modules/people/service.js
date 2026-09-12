/*
 * Resolving a verified identity to an Account, the bootstrap that breaks
 * the circle Approval would otherwise require (issue #6), and — issue #8 —
 * Approval itself: the queue of Accounts awaiting it, admitting one (role
 * and Org Unit grants set in the same act), rejecting one, and deactivating
 * an admitted Account without deleting it. See CONTEXT.md's Account/
 * Approval definitions.
 *
 * `app_users` is the Account table (see the baseline's own comment on why it
 * is not `employees`); `external_subject` is the Supabase provider subject
 * `src/platform/tokens.js` resolves a token to. This module is the one place
 * that column is ever read or written — platform code stays ignorant of what
 * an Account is, per ADR-0006.
 *
 * `approval_status` (migrations/1788295040758_account-approval-status.js) is
 * the decision an administrator has made, if any; `is_active` is whether the
 * Account may act right now. The two move together but are not the same
 * column — see that migration's own header for the full state mapping this
 * file's writes below are each one step of.
 */

const { getPool, withActor } = require('../../platform/db');
const { ROLES } = require('./authorization');
const { httpError, parseId } = require('./errors');

function notFoundAccount() {
  return httpError(404, 'Account not found');
}

function toAccount(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    role: row.role,
    externalSubject: row.external_subject,
    isActive: row.is_active,
    approvalStatus: row.approval_status,
    employeeId: row.employee_id,
    // When this Account came into existence, which for a pending one is when
    // it started waiting — the Approval queue's own "how long has this person
    // been waiting" (issue #40). Same `createdAt` name every other row shape
    // in this Module uses (plant.js, directory.js, skills.js, job-roles.js).
    createdAt: row.created_at
  };
}

const ACCOUNT_COLUMNS =
  'id, email, display_name, role, external_subject, is_active, approval_status, employee_id, created_at';

// Same columns, `app_users.`-qualified — needed only by listPendingAccounts,
// whose suggestedEmployee join (below) introduces a second table with its own
// `id` column: an unqualified ACCOUNT_COLUMNS would make every bare column
// name ambiguous the moment that join is present, the same reason
// directory.js's EMPLOYEE_COLUMNS_QUALIFIED exists.
const ACCOUNT_COLUMNS_QUALIFIED = ACCOUNT_COLUMNS
  .split(', ')
  .map((column) => `app_users.${column}`)
  .join(', ');

// The values `approval_status` may take, per the column's own CHECK
// (migrations/1788295040758_account-approval-status.js).
const APPROVAL_STATUSES = ['pending', 'approved', 'rejected'];

// The optional `expectedApprovalStatus` precondition both approveAccount and
// rejectAccount below accept, in the one place its two halves are spelled
// out: the value check (a 400, before any transaction opens) and the
// comparison against the row this transaction has already locked FOR UPDATE
// (a 409). See rejectAccount's own comment for what sending it buys a
// caller acting on a queue it read earlier.
// Issue #119: a machine-readable code alongside this 409's message.
// approveAccount can answer 409 for this reason or for one of
// requireLinkableEmployee's three Employee-link refusals below, and a caller
// (approval_queue_bloc.dart's isEmployeeLinkRefusal) needs to tell them apart
// without matching on either message's own wording, which is free to reword.
// Distinct from every one of requireLinkableEmployee's three codes below.
const APPROVAL_STATUS_CHANGED = 'APPROVAL_STATUS_CHANGED';

function requireKnownApprovalStatus(expectedApprovalStatus) {
  if (expectedApprovalStatus !== undefined && !APPROVAL_STATUSES.includes(expectedApprovalStatus)) {
    throw httpError(400, `expectedApprovalStatus must be one of: ${APPROVAL_STATUSES.join(', ')}`);
  }
}

function requireApprovalStatusUnchanged(current, expectedApprovalStatus) {
  if (expectedApprovalStatus !== undefined && current.approval_status !== expectedApprovalStatus) {
    throw httpError(
      409,
      `This Account is no longer ${expectedApprovalStatus} — another administrator has already dealt with it.`,
      APPROVAL_STATUS_CHANGED
    );
  }
}

// Issue #53: the three admin-only writes below can each end the acting
// administrator's own access — approveAccount by demoting them away from
// `admin`, rejectAccount and setAccountActive by setting is_active FALSE. A
// sole administrator doing any of the three to their own Account locks every
// administrator out of the Platform with nobody left able to reverse it.
//
// Refused unconditionally, not only when it would leave zero administrators.
// A "last administrator" count would have to run inside these transactions,
// which lock only the *target* row — two administrators self-demoting at once
// would each see the other still live under READ COMMITTED and both pass, so
// the permissive rule needs a new population-wide advisory lock (the device
// createAccountForSubject uses for the bootstrap) to be correct at all. A pure
// comparison, made before any transaction opens, cannot race with anything.
// The cost is that offboarding yourself is somebody else's act, which is a
// reasonable process to require. See ADR-0013.
//
// Both ids are BIGINT-as-string throughout (errors.js's parseId returns a
// string; db.js registers no pg type parser, so a bigint column comes back as
// a string too) — String() on both is belt-and-braces against that changing.
const SELF_ACTION_REFUSED =
  'An administrator cannot approve, reject or deactivate their own Account — another administrator has to do it.';

function refuseSelfAction(id, actingAccountId) {
  if (actingAccountId != null && String(actingAccountId) === String(id)) {
    throw httpError(403, SELF_ACTION_REFUSED);
  }
}

async function findAccountBySubject(subject) {
  const { rows } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS} FROM app_users WHERE external_subject = $1`,
    [subject]
  );
  return rows[0] ? toAccount(rows[0]) : null;
}

function displayNameFor({ name, email, subject }) {
  if (name && name.trim()) return name.trim();
  if (email) return email.split('@')[0];
  return subject;
}

// Creates the Account for a subject seen for the first time. Runs with no
// acting Account (withActor(null, ...)) — per db.js's own comment, the
// request that creates its own Account has no one else to record as its
// author.
//
// The very first Account created on an empty database is the one exception
// to "starts inactive": it is activated immediately, as an administrator,
// and granted every Site that exists at that moment — see the file header
// on app_user_org_units in the baseline for why granting a Site's root Org
// Unit(s) covers everything beneath it. This is what breaks Approval's own
// circle: an administrator has to already exist to approve the first person,
// so the first person is exempted from needing one.
async function createAccountForSubject({ subject, email, name }) {
  if (!email) {
    const error = new Error('token carries no email; cannot create an Account without one');
    error.status = 400;
    throw error;
  }

  return withActor(null, async (client) => {
    // Two people signing in for the very first time, concurrently, would
    // otherwise both see count = 0 under ordinary READ COMMITTED and both
    // become administrator — a transaction-scoped advisory lock serializes
    // the count-then-insert instead of widening this transaction's isolation
    // level for every write it makes. The key is arbitrary but fixed, so
    // every concurrent caller contends for the same lock.
    await client.query("SELECT pg_advisory_xact_lock(hashtext('app_users_bootstrap'))");

    const { rows: [{ n }] } = await client.query('SELECT count(*)::int AS n FROM app_users');
    const isFirstAccount = n === 0;

    const { rows: [inserted] } = await client.query(
      `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING ${ACCOUNT_COLUMNS}`,
      [
        email,
        displayNameFor({ name, email, subject }),
        isFirstAccount ? 'admin' : 'operator',
        subject,
        // Every Account but the first starts inactive (the column's own
        // default, per migrations/1788279276376 — passed explicitly here
        // only so the bootstrap's TRUE reads as deliberate next to it, not
        // because the value would otherwise differ.
        isFirstAccount,
        // Same reasoning, for approval_status (default 'pending' per
        // migrations/1788295040758): the bootstrap Account is exempted from
        // Approval altogether (the file header's "breaks Approval's own
        // circle"), so it is the one Account ever created already
        // 'approved', explicitly, right where that word should be visible.
        isFirstAccount ? 'approved' : 'pending'
      ]
    );

    if (isFirstAccount) {
      await client.query(
        `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
         SELECT $1, ou.id, TRUE FROM org_units ou WHERE ou.parent_id IS NULL`,
        [inserted.id]
      );
    }

    return toAccount(inserted);
  });
}

// The one place "is this subject's Account there yet, and if not, create it"
// happens — called from the authenticate middleware on every request, which
// is what makes first sign-in the moment an Account is created rather than a
// separate sign-up endpoint (there is no session for the API to issue;
// Supabase Auth already issued one).
async function resolveAccountForIdentity({ subject, email, name }) {
  const existing = await findAccountBySubject(subject);
  if (existing) return existing;
  return createAccountForSubject({ subject, email, name });
}

// Every Account's Grants, in one query rather than one per Account. Issue
// #36's accounts-management Screen shows what each Account currently holds,
// and an administrator correcting one has to see the whole existing set
// before replacing it (approveAccount below replaces, never merges) — so a
// row's Grants travel with the row rather than needing a second endpoint.
//
// The Org Unit's own name and its Site's are carried, not just the ids: an
// id is not something an administrator can recognise. Ancestor names are
// deliberately NOT resolved — `org_units.path` is a chain of ids, not names
// (see plant.js's own header), so a breadcrumb would need a second recursive
// join for something the Site name already disambiguates well enough.
async function listGrantsByAccount() {
  const { rows } = await getPool().query(
    `SELECT auo.app_user_id,
            auo.org_unit_id,
            auo.can_write,
            ou.parent_id,
            ou.code,
            ou.name,
            ou.unit_type,
            ou.site_id,
            s.name AS site_name
       FROM app_user_org_units auo
       JOIN org_units ou ON ou.id = auo.org_unit_id
       JOIN sites s ON s.id = ou.site_id
      ORDER BY auo.app_user_id, s.name, ou.name`
  );

  const byAccount = new Map();
  for (const row of rows) {
    const grants = byAccount.get(row.app_user_id) ?? [];
    grants.push({
      orgUnitId: row.org_unit_id,
      parentId: row.parent_id,
      code: row.code,
      name: row.name,
      unitType: row.unit_type,
      siteId: row.site_id,
      siteName: row.site_name,
      canWrite: row.can_write
    });
    byAccount.set(row.app_user_id, grants);
  }
  return byAccount;
}

// `toAccount` is deliberately not forked to carry `grants` — it runs on every
// authenticated request across four other endpoints (see #43's own reasoning
// for orgUnitScope on GET /me), so the extra field is added here, in the one
// listing that needs it, and nowhere else.
async function listAccounts() {
  const { rows } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS} FROM app_users ORDER BY created_at`
  );
  const grantsByAccount = await listGrantsByAccount();
  return rows.map((row) => ({ ...toAccount(row), grants: grantsByAccount.get(row.id) ?? [] }));
}

// ---------------------------------------------------------------------------
// Approval (issue #8) — an administrator admitting a person to the Platform
// and deciding which Org Units they may work in (CONTEXT.md's own
// definition). Every route calling into this section already sat behind
// authorization.js's requireAdmin before it got here; nothing below checks
// the *caller's* role again — only the *target* Account's own state.
// ---------------------------------------------------------------------------

// The Employee link (issue #115, ADR-0022): email matching produces a
// *suggestion*, never a write of its own — `employees_work_email_key`
// (directory.js's own header) is a case-insensitive UNIQUE index on
// work_email, so "exactly one Employee's work_email matches" is already a
// schema guarantee, not something this query has to count for itself. A
// match is suppressed back to null, not surfaced as a suggestion an
// administrator cannot act on, when the Employee has Departed
// (`e.is_active = FALSE`, CONTEXT.md's own Departed entry) or is already
// linked to a different Account (`app_users.employee_id` is UNIQUE) — the
// ticket's own framing, "a suggestion an administrator cannot act on is
// worse than none". This is a plain SQL join against `employees`, not a call
// into directory.js: the two files are domains within the same Module (see
// this file's own header and AGENTS.md section 6), the same way directory.js
// already joins org_units and job_roles directly rather than calling into
// plant.js/job-roles.js for a read.
const SUGGESTED_EMPLOYEE_JOIN = `
       LEFT JOIN LATERAL (
         SELECT e.id, e.employee_no, e.display_name
           FROM employees e
          WHERE e.is_active = TRUE
            AND e.work_email IS NOT NULL
            AND lower(e.work_email) = lower(app_users.email)
            AND NOT EXISTS (
                  SELECT 1 FROM app_users linked WHERE linked.employee_id = e.id
                )
       ) suggested ON TRUE`;

function toSuggestedEmployee(row) {
  return row.suggested_employee_id
    ? {
        id: row.suggested_employee_id,
        employeeNo: row.suggested_employee_no,
        displayName: row.suggested_employee_display_name
      }
    : null;
}

// The Approval queue: every Account nobody has decided about yet. Rejected
// and deactivated Accounts do not belong here — an administrator already
// decided about them, even if that decision was "no" or "not anymore".
//
// `suggestedEmployee` rides along here, not folded into `toAccount`/
// ACCOUNT_COLUMNS: it is a computed fact meaningful only while an Account is
// still pending a decision, the same reasoning that keeps `grants` off
// `toAccount` and local to listAccounts alone (see that function's own
// comment).
async function listPendingAccounts() {
  const { rows } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS_QUALIFIED},
            suggested.id AS suggested_employee_id,
            suggested.employee_no AS suggested_employee_no,
            suggested.display_name AS suggested_employee_display_name
       FROM app_users${SUGGESTED_EMPLOYEE_JOIN}
      WHERE app_users.approval_status = 'pending'
      ORDER BY app_users.created_at`
  );
  return rows.map((row) => ({ ...toAccount(row), suggestedEmployee: toSuggestedEmployee(row) }));
}

// The Employee link's own three refusals (issue #115, ADR-0022), each a
// distinct, specific message rather than one generic "cannot link" — an
// administrator confirming a suggestion, or correcting one, needs to know
// exactly which of the three is wrong. Shared by approveAccount below and
// setAccountEmployee (the PUT /accounts/:id/employee correction route), so
// the two writers of `app_users.employee_id` can never drift onto different
// wording for the same refusal.
//
// `FOR UPDATE` locks the Employee row for the length of the caller's own
// transaction — the same reasoning as the app_users row lock both callers
// already take: two administrators linking the same Employee to two
// different Accounts at once should serialize against each other, not race.
// The UNIQUE constraint on app_users.employee_id (mapAccountWriteError,
// below) is the belt-and-braces backstop if this check and the write still
// straddle a third transaction's commit — the same shape directory.js's
// mapEmployeeWriteError is to employees_work_email_key.
//
// Each of the three refusals below carries its own code (issue #119),
// distinct from the other two and from APPROVAL_STATUS_CHANGED above — the
// messages themselves are unchanged, the code is what lets a caller branch on
// which refusal this is without matching on wording that is free to reword.
const EMPLOYEE_NOT_FOUND = 'EMPLOYEE_NOT_FOUND';
const EMPLOYEE_DEPARTED = 'EMPLOYEE_DEPARTED';
const EMPLOYEE_ALREADY_LINKED = 'EMPLOYEE_ALREADY_LINKED';

async function requireLinkableEmployee(client, employeeId, accountId) {
  const { rows: [employee] } = await client.query(
    'SELECT id, is_active FROM employees WHERE id = $1 FOR UPDATE',
    [employeeId]
  );
  if (!employee) {
    throw httpError(404, 'employeeId does not name an existing Employee', EMPLOYEE_NOT_FOUND);
  }
  if (!employee.is_active) {
    throw httpError(409, 'This Employee has Departed and cannot be linked to an Account', EMPLOYEE_DEPARTED);
  }

  const { rows: [linkedElsewhere] } = await client.query(
    'SELECT id FROM app_users WHERE employee_id = $1 AND id != $2',
    [employeeId, accountId]
  );
  if (linkedElsewhere) {
    throw httpError(409, 'This Employee is already linked to a different Account', EMPLOYEE_ALREADY_LINKED);
  }
}

// The belt-and-braces backstop requireLinkableEmployee's own comment
// describes: app_users.employee_id is UNIQUE at the schema level (the
// baseline's own app_users table), so a race that requireLinkableEmployee's
// pre-check cannot fully close still ends in a clean 409 here rather than a
// raw constraint-violation 500 — the same pattern directory.js's
// mapEmployeeWriteError already follows for employees_work_email_key
// (that file's own header, directory-routes.js:467 at the time of writing).
function mapAccountWriteError(error) {
  if (error.code === '23505' && error.constraint === 'app_users_employee_id_key') {
    return httpError(409, 'This Employee is already linked to a different Account', EMPLOYEE_ALREADY_LINKED);
  }
  return error;
}

// employeeId is optional, and its absence is deliberately NOT the same as
// null: omitted (the key absent from the request body) leaves whatever link
// the Account already holds untouched, so re-approving or correcting an
// Account's role/grants never silently unlinks it; an explicit null clears
// the link, the same "clearing" shape setAccountEmployee's own null case
// uses; a value confirms — or moves — the link to that Employee, after the
// same three checks requireLinkableEmployee runs for both writers.
function parseOptionalEmployeeId(employeeId) {
  if (employeeId === undefined) return undefined;
  if (employeeId === null) return null;
  const parsed = parseId(employeeId);
  if (parsed === null) {
    throw httpError(400, 'employeeId must be a valid Employee id');
  }
  return parsed;
}

// Approving an Account sets its role and grants its Org Units in the same
// act (issue #8's own criterion): one transaction, so a caller can never
// observe a role change with no grants yet, or grants with the old role
// still in place. Grants are validated — every orgUnitId must actually
// exist — before anything is written, and then replace whatever grant set
// the Account held before: an administrator approving a previously-rejected
// Account, or correcting an earlier Approval's grants, should not have to
// first recall and revoke what an earlier act left behind (see the
// paragraph below on why re-approval is allowed at all).
//
// Approving a rejected Account, and rejecting an already-approved one
// (rejectAccount, below), are both allowed rather than refused as invalid
// transitions. `approval_status` records an administrator's most recent
// decision, not a one-way door: circumstances that justified turning
// someone away, or admitting them, can change, and an administrator is
// exactly who this Platform trusts to make that call again. What
// `approval_status` must never do is go stale relative to `is_active` — see
// the migration's own header for the mapping every write in this section
// keeps true.
//
// `employeeId` (issue #115, ADR-0022) confirms the suggestion the Approval
// queue carried, or names a different Employee outright — see
// parseOptionalEmployeeId's own comment for what omitting it, sending null,
// or sending a value each do, and requireLinkableEmployee's for the three
// refusals a value can produce. Written in this same transaction, alongside
// role and grants, for the same "a partial Approval must stay unobservable"
// reason the rest of this function already is one.
async function approveAccount(id, { role, grants, employeeId }, actingAccountId, { expectedApprovalStatus } = {}) {
  refuseSelfAction(id, actingAccountId);
  requireKnownApprovalStatus(expectedApprovalStatus);
  if (!ROLES.includes(role)) {
    throw httpError(400, `role must be one of: ${ROLES.join(', ')}`);
  }
  if (!Array.isArray(grants)) {
    throw httpError(400, 'grants must be an array');
  }

  const parsedGrants = grants.map((grant, index) => {
    const orgUnitId = parseId(grant?.orgUnitId);
    if (orgUnitId === null) {
      throw httpError(400, `grants[${index}].orgUnitId must be a valid Org Unit id`);
    }
    return { orgUnitId, canWrite: grant.canWrite === true };
  });

  const parsedEmployeeId = parseOptionalEmployeeId(employeeId);

  try {
    return await withActor(actingAccountId, async (client) => {
      // Locks the row for the length of this transaction, same reasoning as
      // the bootstrap's advisory lock: two administrators approving the same
      // Account at once should serialize, not race each other's grant writes.
      const { rows: [current] } = await client.query(
        'SELECT approval_status FROM app_users WHERE id = $1 FOR UPDATE',
        [id]
      );
      if (!current) throw notFoundAccount();
      requireApprovalStatusUnchanged(current, expectedApprovalStatus);

      if (parsedGrants.length > 0) {
        const { rows: found } = await client.query(
          'SELECT id FROM org_units WHERE id = ANY($1::bigint[])',
          [parsedGrants.map((grant) => grant.orgUnitId)]
        );
        const foundIds = new Set(found.map((row) => row.id));
        const missing = parsedGrants.filter((grant) => !foundIds.has(grant.orgUnitId));
        if (missing.length > 0) {
          throw httpError(400, `unknown Org Unit id(s): ${missing.map((grant) => grant.orgUnitId).join(', ')}`);
        }
      }

      if (parsedEmployeeId !== undefined && parsedEmployeeId !== null) {
        await requireLinkableEmployee(client, parsedEmployeeId, id);
      }

      const { rows: [updated] } = await client.query(
        parsedEmployeeId === undefined
          ? `UPDATE app_users
                SET role = $2, approval_status = 'approved', is_active = TRUE
              WHERE id = $1
            RETURNING ${ACCOUNT_COLUMNS}`
          : `UPDATE app_users
                SET role = $2, approval_status = 'approved', is_active = TRUE, employee_id = $3
              WHERE id = $1
            RETURNING ${ACCOUNT_COLUMNS}`,
        parsedEmployeeId === undefined ? [id, role] : [id, role, parsedEmployeeId]
      );

      await client.query('DELETE FROM app_user_org_units WHERE app_user_id = $1', [id]);
      for (const grant of parsedGrants) {
        // Sequential, not Promise.all: same connection, one transaction — the
        // pg client does not support concurrent queries on a single client.
        // eslint-disable-next-line no-await-in-loop
        await client.query(
          `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
           VALUES ($1, $2, $3)`,
          [id, grant.orgUnitId, grant.canWrite]
        );
      }

      return toAccount(updated);
    });
  } catch (error) {
    throw mapAccountWriteError(error);
  }
}

// Rejecting an Account sets it inactive with a reason a deactivation alone
// does not carry — see the state mapping in the migration's own header, and
// approveAccount's comment above on why this is allowed regardless of the
// Account's current approval_status.
//
// `expectedApprovalStatus` is an optional precondition, and the default —
// omitting it — keeps the unconditional behaviour above exactly as it was.
// It exists for a caller acting on a *list* it read earlier: two
// administrators working the Approval queue at the same time would otherwise
// have the slower one silently overwrite the faster one's decision, so an
// Account just approved would be rejected again by a click aimed at a row
// that had already moved. Sending the status the caller believed the Account
// held turns that into a 409 it can report and re-read from, rather than an
// invisible, wrong write. The row is locked FOR UPDATE first, so the check
// and the write cannot straddle another transaction's commit.
async function rejectAccount(id, actingAccountId, { expectedApprovalStatus } = {}) {
  refuseSelfAction(id, actingAccountId);
  requireKnownApprovalStatus(expectedApprovalStatus);

  return withActor(actingAccountId, async (client) => {
    const { rows: [current] } = await client.query(
      'SELECT approval_status FROM app_users WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (!current) throw notFoundAccount();
    requireApprovalStatusUnchanged(current, expectedApprovalStatus);

    const { rows: [updated] } = await client.query(
      `UPDATE app_users
          SET approval_status = 'rejected', is_active = FALSE
        WHERE id = $1
      RETURNING ${ACCOUNT_COLUMNS}`,
      [id]
    );
    if (!updated) throw notFoundAccount();
    return toAccount(updated);
  });
}

// Deactivation (and reactivation), not deletion — issue #8's own criterion,
// the same shape as plant.js's setOrgUnitActive for an Org Unit. Restricted
// to Accounts an administrator has already approved: a pending Account has
// no role or grants yet to reactivate into, and a rejected Account's
// is_active is already FALSE for a reason this route does not carry —
// approveAccount is the deliberate way back in for either.
async function setAccountActive(id, isActive, actingAccountId) {
  refuseSelfAction(id, actingAccountId);
  return withActor(actingAccountId, async (client) => {
    const { rows: [current] } = await client.query(
      'SELECT approval_status FROM app_users WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (!current) throw notFoundAccount();
    if (current.approval_status !== 'approved') {
      throw httpError(
        400,
        'Only an approved Account can be activated or deactivated here — use the approval or rejection endpoint instead.'
      );
    }

    const { rows: [updated] } = await client.query(
      `UPDATE app_users SET is_active = $2 WHERE id = $1 RETURNING ${ACCOUNT_COLUMNS}`,
      [id, isActive]
    );
    return toAccount(updated);
  });
}

// The correction route (issue #115, ADR-0022): sets or clears
// app_users.employee_id outside of Approval, for a suggestion an
// administrator missed, an Employee record created after the Account, or a
// mistaken link. `employeeId: null` clears the link; any other value goes
// through the same requireLinkableEmployee checks approveAccount's own
// employeeId uses, so the two writers of this column never disagree about
// what makes an Employee linkable.
//
// refuseSelfAction runs as this function's first statement, before
// employeeId is even looked at — exactly the shape ADR-0013 mandates
// (service.js's other three self-action guards, above) and ADR-0022 extends
// to this write: an administrator asserting "this is the Employee I am" is
// exactly the kind of identity claim ADR-0013's rule already refuses,
// regardless of which particular write carries it.
async function setAccountEmployee(id, employeeId, actingAccountId) {
  refuseSelfAction(id, actingAccountId);

  const parsedEmployeeId = employeeId === null ? null : parseId(employeeId);
  if (parsedEmployeeId === null && employeeId !== null) {
    throw httpError(400, 'employeeId must be a valid Employee id, or null to clear the link');
  }

  try {
    return await withActor(actingAccountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT id FROM app_users WHERE id = $1 FOR UPDATE',
        [id]
      );
      if (!current) throw notFoundAccount();

      if (parsedEmployeeId !== null) {
        await requireLinkableEmployee(client, parsedEmployeeId, id);
      }

      const { rows: [updated] } = await client.query(
        `UPDATE app_users SET employee_id = $2 WHERE id = $1 RETURNING ${ACCOUNT_COLUMNS}`,
        [id, parsedEmployeeId]
      );
      return toAccount(updated);
    });
  } catch (error) {
    throw mapAccountWriteError(error);
  }
}

module.exports = {
  resolveAccountForIdentity,
  findAccountBySubject,
  listAccounts,
  listPendingAccounts,
  approveAccount,
  rejectAccount,
  setAccountActive,
  setAccountEmployee,
  SELF_ACTION_REFUSED
};
