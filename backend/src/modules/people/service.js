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

// The values `approval_status` may take, per the column's own CHECK
// (migrations/1788295040758_account-approval-status.js).
const APPROVAL_STATUSES = ['pending', 'approved', 'rejected'];

// The optional `expectedApprovalStatus` precondition both approveAccount and
// rejectAccount below accept, in the one place its two halves are spelled
// out: the value check (a 400, before any transaction opens) and the
// comparison against the row this transaction has already locked FOR UPDATE
// (a 409). See rejectAccount's own comment for what sending it buys a
// caller acting on a queue it read earlier.
function requireKnownApprovalStatus(expectedApprovalStatus) {
  if (expectedApprovalStatus !== undefined && !APPROVAL_STATUSES.includes(expectedApprovalStatus)) {
    throw httpError(400, `expectedApprovalStatus must be one of: ${APPROVAL_STATUSES.join(', ')}`);
  }
}

function requireApprovalStatusUnchanged(current, expectedApprovalStatus) {
  if (expectedApprovalStatus !== undefined && current.approval_status !== expectedApprovalStatus) {
    throw httpError(
      409,
      `This Account is no longer ${expectedApprovalStatus} — another administrator has already dealt with it.`
    );
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

async function listAccounts() {
  const { rows } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS} FROM app_users ORDER BY created_at`
  );
  return rows.map(toAccount);
}

// ---------------------------------------------------------------------------
// Approval (issue #8) — an administrator admitting a person to the Platform
// and deciding which Org Units they may work in (CONTEXT.md's own
// definition). Every route calling into this section already sat behind
// authorization.js's requireAdmin before it got here; nothing below checks
// the *caller's* role again — only the *target* Account's own state.
// ---------------------------------------------------------------------------

// The Approval queue: every Account nobody has decided about yet. Rejected
// and deactivated Accounts do not belong here — an administrator already
// decided about them, even if that decision was "no" or "not anymore".
async function listPendingAccounts() {
  const { rows } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS} FROM app_users WHERE approval_status = 'pending' ORDER BY created_at`
  );
  return rows.map(toAccount);
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
async function approveAccount(id, { role, grants }, actingAccountId, { expectedApprovalStatus } = {}) {
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

  return withActor(actingAccountId, async (client) => {
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

    const { rows: [updated] } = await client.query(
      `UPDATE app_users
          SET role = $2, approval_status = 'approved', is_active = TRUE
        WHERE id = $1
      RETURNING ${ACCOUNT_COLUMNS}`,
      [id, role]
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

module.exports = {
  resolveAccountForIdentity,
  findAccountBySubject,
  listAccounts,
  listPendingAccounts,
  approveAccount,
  rejectAccount,
  setAccountActive
};
