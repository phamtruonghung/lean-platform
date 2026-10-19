#!/usr/bin/env node
/*
 * Sets one existing Account's password (issue #280), creating its row in
 * `account_credentials` if it has none, so the deployment's first
 * administrator can sign in once AUTH_PASSWORD_MODE=local. Everything after
 * that happens through the change flow of #270.
 *
 *   printf '%s' "$PW" | DATABASE_URL=postgresql://... node dev/set-a-password.mjs <email> [--force]
 *
 * Runbook (README, Deployment, "The first administrator's password"):
 *
 *   read -s -p 'New password: ' PW && printf '%s' "$PW" | node dev/set-a-password.mjs <email>
 *
 * The password comes from stdin only, never argv (shell history, process
 * lists) or the environment. It is stored as temporary: must_change_password
 * is set. An existing credential is refused unless --force is passed. Only the
 * email and the time are printed; the password and its hash never are.
 *
 * Why not the load script (dev/seed-relats-vietnam.mjs): it owns the plant
 * roster and stays idempotent against it. An administrator is deployment
 * furniture, not plant data; folding one in would re-set the administrator's
 * password on every load. This script adds no migration and changes no schema.
 */

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// The backend is CommonJS and owns the node_modules where `pg` lives. Resolving
// from its package.json makes `./src/...` and `pg` resolve exactly as the API's
// own code does.
const here = path.dirname(fileURLToPath(import.meta.url));
const backendRequire = createRequire(path.join(here, '..', 'backend', 'package.json'));
const { hashSecret } = backendRequire('./src/platform/secrets');
const { MIN_PASSWORD_LENGTH } = backendRequire('./src/modules/people/passwords');
const pg = backendRequire('pg');

const USAGE = 'Usage: printf \'%s\' "$PW" | DATABASE_URL=... node dev/set-a-password.mjs <email> [--force]';
const MASKED_FORM = "read -s -p 'New password: ' PW && printf '%s' \"$PW\" | node dev/set-a-password.mjs <email>";

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const positional = [];
  let force = false;
  for (const arg of argv) {
    if (arg === '--force') force = true;
    else if (arg.startsWith('-')) fail(`Unknown option ${arg.split('=')[0]}.\n${USAGE}`);
    else positional.push(arg);
  }
  if (positional.length !== 1) fail(`Exactly one email is expected, and the password goes on stdin, not the command line.\n${USAGE}`);
  return { email: positional[0].trim(), force };
}

async function readPassword() {
  if (process.stdin.isTTY) {
    fail(`Refusing to read a password typed in the clear. Use the masked form:\n  ${MASKED_FORM}`);
  }
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const firstLine = Buffer.concat(chunks).toString('utf8').split('\n')[0];
  return firstLine.replace(/\r$/, '');
}

async function main() {
  const { email, force } = parseArgs(process.argv.slice(2));
  if (!process.env.DATABASE_URL) fail('DATABASE_URL is required.');
  const password = await readPassword();
  if (password.length < MIN_PASSWORD_LENGTH) fail(`The password must be at least ${MIN_PASSWORD_LENGTH} characters.`);

  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
  try {
    // `app_users.email` is CITEXT, so this match ignores case.
    const { rows: [account] } = await pool.query(
      `SELECT u.id, u.email, (e.id IS NOT NULL AND e.is_active) AS has_active_employee,
              EXISTS (SELECT 1 FROM account_credentials c WHERE c.app_user_id = u.id) AS has_credential
         FROM app_users u
         LEFT JOIN employees e ON e.id = u.employee_id
        WHERE u.email = $1`,
      [email]
    );
    if (!account) fail(`No Account has the email ${email}.`);
    const alreadyHasOne = `${account.email} already has a password; nothing was changed. Re-run with --force to replace it. Once signed in, the change flow (#270) is the normal way.`;
    if (account.has_credential && !force) fail(alreadyHasOne);

    // is_enabled is not written: a new row defaults to enabled, and a --force
    // overwrite must not silently re-enable a credential someone disabled.
    // Without --force the conflict clause is DO NOTHING, so a credential that
    // appeared since the check above is never overwritten (no row is returned).
    const onConflict = force
      ? 'DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change_password = TRUE'
      : 'DO NOTHING';
    const { rows: [written] } = await pool.query(
      `INSERT INTO account_credentials (app_user_id, password_hash, must_change_password)
       VALUES ($1, $2, TRUE)
       ON CONFLICT (app_user_id) ${onConflict}
       RETURNING updated_at`,
      [account.id, await hashSecret(password)]
    );
    if (!written) fail(alreadyHasOne);
    console.log(`Password set for ${account.email} at ${written.updated_at.toISOString()}. It is temporary (must_change_password): this only makes the first sign-in possible — change it through #270's change flow.`);
    if (!account.has_active_employee) {
      console.error(
        `WARNING: ${account.email} is not linked to an active Employee. The password is set, but sign-in will still be refused until the Account is linked to an active Employee.`
      );
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`FAILED: ${error.message}`);
  process.exit(1);
});
