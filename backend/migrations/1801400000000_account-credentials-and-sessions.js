/**
 * Signing in with an email and a password held in our own database (issue
 * #268, part of #267).
 *
 * `app_users` carries no password, and `platform/tokens.js` can only verify a
 * Supabase JWT, so a deployment with its own PostgreSQL could not authenticate
 * anybody. This migration stores the two things a local sign-in needs.
 *
 *   - `account_credentials` holds an Account's password, keyed to the Account
 *     it belongs to. Only a salted scrypt hash is stored
 *     (`scrypt$<saltHex>$<keyHex>`, platform/secrets.js), never the password.
 *     `is_enabled` is the "credential off" switch: an administrator can stop a
 *     password working without deleting it. `must_change_password` is stored
 *     now and read by nothing yet; the change-password ticket owns it.
 *
 *   - `account_sessions` is one issued session token. The token is 32 random
 *     bytes handed to the client once; only its SHA-256 is stored, so a copy
 *     of this table is not a set of live logins. `expires_at` bounds it and
 *     `revoked_at` ends it early, which is what logout and an administrator
 *     cutting a device off both set. Rows are never updated otherwise, so the
 *     table carries no `updated_at`.
 *
 * ## Forward-only
 *
 * Per ADR-0007 this only adds tables the outgoing version never reads. `down`
 * exists for local development and node-pg-migrate's own requirement.
 *
 * ## RLS
 *
 * Both tables enable RLS with no policies, ADR-0004's deny-all floor, in this
 * same migration (rls.test.js enforces it).
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE account_credentials (
      app_user_id          BIGINT      PRIMARY KEY REFERENCES app_users (id) ON DELETE CASCADE,
      -- A salted scrypt hash, scrypt$<saltHex>$<keyHex>. Never the password.
      password_hash        TEXT        NOT NULL,
      is_enabled           BOOLEAN     NOT NULL DEFAULT TRUE,
      must_change_password BOOLEAN     NOT NULL DEFAULT FALSE,
      created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  pgm.sql(`
    CREATE TABLE account_sessions (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      app_user_id BIGINT      NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
      -- SHA-256 hex of the opaque token handed to the client. The token itself
      -- is never stored.
      token_hash  TEXT        NOT NULL UNIQUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      expires_at  TIMESTAMPTZ NOT NULL,
      revoked_at  TIMESTAMPTZ
    )
  `);

  pgm.sql('CREATE INDEX account_sessions_app_user_idx ON account_sessions (app_user_id)');

  pgm.sql(`SELECT attach_updated_at('account_credentials')`);

  pgm.sql('ALTER TABLE account_credentials ENABLE ROW LEVEL SECURITY');
  pgm.sql('ALTER TABLE account_sessions ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  pgm.sql('DROP TRIGGER IF EXISTS account_credentials_set_updated_at ON account_credentials');
  pgm.sql('DROP TABLE IF EXISTS account_sessions');
  pgm.sql('DROP TABLE IF EXISTS account_credentials');
};
