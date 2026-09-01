/*
 * Resolving a verified identity to an Account, and the bootstrap that breaks
 * the circle Approval would otherwise require (issue #6, CONTEXT.md's
 * Account/Approval definitions).
 *
 * `app_users` is the Account table (see the baseline's own comment on why it
 * is not `employees`); `external_subject` is the Supabase provider subject
 * `src/platform/tokens.js` resolves a token to. This module is the one place
 * that column is ever read or written — platform code stays ignorant of what
 * an Account is, per ADR-0006.
 */

const { getPool, withActor } = require('../../platform/db');

function toAccount(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    role: row.role,
    externalSubject: row.external_subject,
    isActive: row.is_active,
    employeeId: row.employee_id
  };
}

const ACCOUNT_COLUMNS = 'id, email, display_name, role, external_subject, is_active, employee_id';

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
      `INSERT INTO app_users (email, display_name, role, external_subject, is_active)
       VALUES ($1, $2, $3, $4, $5)
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
        isFirstAccount
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

module.exports = { resolveAccountForIdentity, findAccountBySubject, listAccounts };
