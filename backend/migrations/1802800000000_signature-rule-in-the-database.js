/**
 * The rule that holds a kept Signature, kept in the database (issue #326,
 * ADR-0053). ADR-0052 closes the administrator's door the moment an Employee
 * can set their own mark: an administrator may set a Signature only for an
 * Employee who holds no Account. This migration makes that rule a trigger on
 * `employee_signatures` instead of a check the application makes first.
 *
 * ## The rule
 *
 * A *kept, current* row (`kept` and `superseded_at IS NULL`) for an Employee
 * who holds an Account must have been set by that Employee's own Account. A
 * row with no setter (`set_by_account_id` NULL — the shared floor device may
 * apply a stored Signature but never create one, ADR-0052) is refused the
 * same way. A stroke drawn for one act (`kept = FALSE`) and a row being
 * superseded (`superseded_at` set) are never refused: neither is a mark the
 * Employee is being given.
 *
 * ## Why a check before the write cannot hold it
 *
 * `signatures.requireNoAccount` reads `app_users` in its own statement and the
 * write that follows runs in a later transaction. Nothing serialises the two
 * against the act that links an Account to the Employee, so an Account linked
 * between the read and the write leaves an administrator-set mark on an
 * Employee who can now set their own. The rule is a cross-table fact, so it
 * cannot be a CHECK; it is a trigger, and a trigger that only reads is still
 * racy for the same reason, which is why it takes a lock first.
 *
 * ## Why the `employees` row lock is the right primitive
 *
 * Both writers of `app_users.employee_id` — Approval and `setAccountEmployee`
 * — already `SELECT ... FOR UPDATE` the Employee's row in
 * `requireLinkableEmployee` before they link. The trigger takes the same lock
 * on the same row, so a signature write and a link of the same Employee wait
 * for each other and whichever commits second sees the first: the write sees
 * the Account, or the link waits until the mark has committed. Nothing in
 * Approval changed and no new lock type exists; the lock is load-bearing, not
 * decoration, and it is taken before the rule is read.
 *
 * The message raised is deliberately generic (SQLSTATE `23514`, the shape
 * `stock_movements_refuse_negative` set); `signatures.js` turns it into the
 * same sentence `requireNoAccount` gives. The application's check stays: it
 * produces the wording in the ordinary case, and this trigger is the rule that
 * holds. Neither is a duplicate of the other.
 *
 * ## The one case deliberately unchanged
 *
 * A mark written *before* a link is legitimate at that instant, and linking an
 * Account afterwards does not touch it. The Employee's own PUT /me/signature
 * supersedes it, exactly as ADR-0052 says.
 *
 * The function is named for the property it enforces rather than for the
 * refusal, because what it refuses depends on who set the row.
 *
 * Backward-compatible per ADR-0007: the outgoing image writes through the same
 * routes, and the only writes this refuses are the ones it should already have.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE FUNCTION employee_signatures_require_a_person_who_can_hold_it() RETURNS TRIGGER AS $$
    BEGIN
      -- The load-bearing line, taken before anything is read: the same row lock
      -- requireLinkableEmployee takes before it links an Account, so this write
      -- and a link of the same Employee cannot interleave. Without it the
      -- EXISTS below reads a snapshot that a link may be about to change.
      PERFORM 1 FROM employees WHERE id = NEW.employee_id FOR UPDATE;

      IF NEW.kept AND NEW.superseded_at IS NULL THEN
        IF EXISTS (SELECT 1 FROM app_users a WHERE a.employee_id = NEW.employee_id)
           AND NOT EXISTS (
             SELECT 1 FROM app_users a
              WHERE a.id = NEW.set_by_account_id AND a.employee_id = NEW.employee_id
           )
        THEN
          RAISE EXCEPTION 'a Signature for an Employee with an Account is set by that Account'
            USING ERRCODE = '23514';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  // Postgres grants EXECUTE to PUBLIC at CREATE FUNCTION time; rls.test.js
  // holds every routine in `public` to none (deny-all floor, ADR-0004).
  pgm.sql('REVOKE EXECUTE ON FUNCTION employee_signatures_require_a_person_who_can_hold_it() FROM PUBLIC');

  pgm.sql(`
    CREATE TRIGGER employee_signatures_who_can_hold_it
      BEFORE INSERT OR UPDATE OF employee_id, kept, superseded_at, set_by_account_id
      ON employee_signatures
      FOR EACH ROW EXECUTE FUNCTION employee_signatures_require_a_person_who_can_hold_it()
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('DROP TRIGGER IF EXISTS employee_signatures_who_can_hold_it ON employee_signatures');
  pgm.sql('DROP FUNCTION IF EXISTS employee_signatures_require_a_person_who_can_hold_it()');
};
