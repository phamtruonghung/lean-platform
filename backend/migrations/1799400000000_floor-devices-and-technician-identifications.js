/**
 * A shared floor device, and the individual identification a technician
 * presents on it (issue #77, ADR-0016).
 *
 * ADR-0016 decides that the floor-facing surface runs on a shared device whose
 * own identity is scoped to one Org Unit and may only READ within it, and that
 * every WRITE re-confirms who is performing it close to the moment they do it
 * rather than trusting a session established hours earlier. This migration
 * stores exactly the two things that need: the device's registration and the
 * credential a technician presents.
 *
 * ## The three tables, and why each exists
 *
 *   - `floor_devices` registers one shared device against one Org Unit. Its
 *     `credential_hash` is what the device presents to read the work at its
 *     Org Unit and beneath — and it can never authorise a write on its own.
 *     Only the SHA-256 of the credential is stored; the presentable value is
 *     generated once at registration and never again stored or returned.
 *
 *   - `employee_floor_credentials` holds one technician's PIN, keyed to the
 *     Employee it belongs to. It is deliberately keyed to `employees`, NOT to
 *     `app_users`: CONTEXT.md is explicit that most of a plant cannot sign in
 *     at all, so the credential must work for an Employee with no Account.
 *     Only a salted scrypt hash of the PIN is stored. An Employee has at most
 *     one floor credential — hence the UNIQUE on `employee_id`.
 *
 *   - `technician_identifications` is the short-lived link between a device, an
 *     Employee and a single burst of writes. Presenting a PIN to the identify
 *     endpoint exchanges it for an opaque token with an expiry; every write
 *     must carry that token, and the write is attributed to the Employee it
 *     resolves to. The token is stored only as its SHA-256, so the row cannot
 *     itself be replayed as a credential if the table is read. The window is
 *     deliberately short (the service sets it) so "who was at the machine" and
 *     "who the system attributed the action to" cannot drift across a shift
 *     change. Rows here are ephemeral; nothing reads one after it expires.
 *
 * `work_orders.started_by` is the one existing table this migration touches.
 * `completed_by` already exists (and already references `employees`) precisely
 * so a completion can name the Employee who did the work; nothing ever filled
 * it, because every write until now was attributed to an Account and an
 * Account need not be an Employee. The floor surface is the case the column
 * was put there for. `started_by` is added alongside it so a start is recorded
 * against its Employee too, rather than only a completion. Both are nullable
 * and additive: the version this replaces keeps running untouched against the
 * expanded schema (ADR-0007).
 *
 * ## Forward-only
 *
 * Per ADR-0007 this migration only adds tables and one nullable column; the
 * outgoing version reads none of them, so it keeps running against the
 * migrated schema for the window between the schema changing and the new
 * containers passing health. `down` exists only for local development and
 * node-pg-migrate's own requirement; there is no deployed down path.
 *
 * ## RLS and actor columns
 *
 * `1756000000002_deny-all-rls.js` enabled RLS on the tables that existed when
 * it ran and left every later migration its own obligation to do the same, so
 * each table created here enables RLS with no policies — the deny-all floor.
 * `floor_devices` and `employee_floor_credentials` are ordinary editable
 * records and get the baseline's `attach_updated_at`/`attach_actor_columns`/
 * `attach_audit` treatment. `technician_identifications` is append-only, like
 * `stock_movements`, so it carries no `updated_at`/`updated_by` and
 * deliberately gets none of those helpers.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // --------------------------------------------------------------------------
  // floor_devices — one shared device, registered against one Org Unit.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE floor_devices (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id     BIGINT      NOT NULL REFERENCES org_units (id),
      name            TEXT        NOT NULL CHECK (btrim(name) <> ''),
      -- SHA-256 hex of the credential the device presents. The presentable
      -- value is generated once by the service and never stored in the clear.
      credential_hash TEXT        NOT NULL UNIQUE,
      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT
    )
  `);

  pgm.sql('CREATE INDEX floor_devices_org_unit_idx ON floor_devices (org_unit_id)');

  // --------------------------------------------------------------------------
  // employee_floor_credentials — one PIN per Employee, hashed.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE employee_floor_credentials (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id BIGINT      NOT NULL UNIQUE REFERENCES employees (id) ON DELETE CASCADE,
      -- A salted scrypt hash, encoded as scrypt$<saltHex>$<hashHex>. Never the
      -- PIN itself.
      pin_hash    TEXT        NOT NULL,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // technician_identifications — the short-lived, per-burst identification.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE technician_identifications (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      floor_device_id BIGINT      NOT NULL REFERENCES floor_devices (id) ON DELETE CASCADE,
      employee_id     BIGINT      NOT NULL REFERENCES employees (id) ON DELETE CASCADE,
      -- SHA-256 hex of the opaque token handed to the client. The token itself
      -- is never stored.
      token_hash      TEXT        NOT NULL UNIQUE,
      expires_at      TIMESTAMPTZ NOT NULL,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  pgm.sql(`
    CREATE INDEX technician_identifications_expiry_idx
      ON technician_identifications (expires_at)
  `);

  // --------------------------------------------------------------------------
  // work_orders.started_by — who began the work, when it was an Employee.
  // --------------------------------------------------------------------------
  pgm.sql('ALTER TABLE work_orders ADD COLUMN started_by BIGINT REFERENCES employees (id)');

  // --------------------------------------------------------------------------
  // Shared behaviour the rest of the App tables already carry.
  // --------------------------------------------------------------------------
  pgm.sql(`SELECT attach_updated_at('floor_devices')`);
  pgm.sql(`SELECT attach_actor_columns('floor_devices')`);
  pgm.sql(`SELECT attach_updated_at('employee_floor_credentials')`);
  pgm.sql(`SELECT attach_actor_columns('employee_floor_credentials')`);

  // Both editable tables are audited: who registered a device, and whom a
  // credential belongs to, are facts worth a history. The identifications
  // table is append-only and expires on its own, so it is not.
  pgm.sql(`SELECT attach_audit('floor_devices')`);
  pgm.sql(`SELECT attach_audit('employee_floor_credentials')`);

  // --------------------------------------------------------------------------
  // RLS — see this file's own header.
  // --------------------------------------------------------------------------
  pgm.sql('ALTER TABLE floor_devices ENABLE ROW LEVEL SECURITY');
  pgm.sql('ALTER TABLE employee_floor_credentials ENABLE ROW LEVEL SECURITY');
  pgm.sql('ALTER TABLE technician_identifications ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and node-pg-migrate's own requirement. Trigger names are the
  // exact strings the baseline helpers generate (`<table>_set_updated_at`,
  // `zz_<table>_set_actor`, `<table>_audit`).
  pgm.sql('ALTER TABLE work_orders DROP COLUMN IF EXISTS started_by');

  pgm.sql('DROP TRIGGER IF EXISTS employee_floor_credentials_audit ON employee_floor_credentials');
  pgm.sql('DROP TRIGGER IF EXISTS zz_employee_floor_credentials_set_actor ON employee_floor_credentials');
  pgm.sql('DROP TRIGGER IF EXISTS employee_floor_credentials_set_updated_at ON employee_floor_credentials');

  pgm.sql('DROP TRIGGER IF EXISTS floor_devices_audit ON floor_devices');
  pgm.sql('DROP TRIGGER IF EXISTS zz_floor_devices_set_actor ON floor_devices');
  pgm.sql('DROP TRIGGER IF EXISTS floor_devices_set_updated_at ON floor_devices');

  pgm.sql('DROP TABLE IF EXISTS technician_identifications');
  pgm.sql('DROP TABLE IF EXISTS employee_floor_credentials');
  pgm.sql('DROP TABLE IF EXISTS floor_devices');
};
