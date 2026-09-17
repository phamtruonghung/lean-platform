/**
 * The response a customer complaint is closed with (issue #214).
 *
 * `customer_complaints` is a baseline table and this slice uses it as it
 * stands, with one exception: the ticket's own acceptance criteria end with
 * "closes the complaint with its response ... closing without one is refused",
 * and the baseline has nowhere to put a response. It carries
 * `first_response_at` — the *moment* a customer first heard back, which its own
 * comment explains is kept apart from `closed_at` because customers judge the
 * two separately — `description`, which is the complaint as the customer made
 * it, and an audit trail, which is a record of changes rather than a place to
 * write a sentence. So one nullable column is added: `response_note`, what the
 * plant said back, written in the same statement that closes the complaint.
 *
 * **Why a column rather than a Constraint-only answer or a second table.** The
 * alternative considered and rejected was recording the response as a
 * Disposition-like event of its own (`customer_complaint_responses`), the shape
 * the Non-conformance log uses for quantity changes. That shape earns its keep
 * where a record gathers *many* events over time and the history is the point;
 * a complaint is answered once, and the ticket names one closure with one note.
 * A second table would add a join, an RLS obligation and a one-way door to hold
 * a single sentence, and it would let a closed complaint carry no response
 * anyway — the very state the criterion refuses.
 *
 * **`customer_complaints_closed_has_response` mirrors the baseline's own
 * `customer_complaints_closed_has_time`.** That constraint requires `closed_at`
 * for a complaint in `closed` *or* `rejected`, on the reading that both are
 * states the record finishes in, and a note is owed in both: rejecting a
 * customer's complaint is a decision that needs a reason written down at least
 * as much as answering it does. The route this slice adds writes only `closed`,
 * and always with a note — the constraint is the rule for a writer that does
 * not come through the service, stated where every other invariant in this
 * database is stated. The baseline's own statuses (`investigating`,
 * `responded`) are untouched and need no note: a complaint still being worked
 * has not answered anybody yet.
 *
 * **Expand-safe (ADR-0007).** A nullable column and a constraint that is
 * vacuously true for every row that exists: no version of this codebase before
 * this migration writes `customer_complaints` at all — this Module is the
 * table's first writer — so nothing an older image does can be refused by the
 * new CHECK, and an older image reading the table is unaffected by a column it
 * does not select. Nothing is back-filled, because there is nothing to
 * back-fill: no row anywhere is in a state the new rule would refuse.
 *
 * `customer_complaints` already carries the deny-all RLS floor (ADR-0004, from
 * the baseline's own sweep) and this migration creates no table, so there is no
 * RLS obligation of its own here.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // What the plant said back. Nullable: a complaint that is still open has not
  // answered anybody, and that is a real and common state.
  pgm.sql('ALTER TABLE customer_complaints ADD COLUMN response_note TEXT');

  // A complaint that finished with a reply to the customer has one written
  // down. Mirrors `customer_complaints_closed_has_time`, which pairs the same
  // two statuses for the closure timestamp.
  pgm.sql(`
    ALTER TABLE customer_complaints
      ADD CONSTRAINT customer_complaints_closed_has_response
        CHECK (status NOT IN ('closed', 'rejected') OR response_note IS NOT NULL)
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The constraint goes before the column it names,
  // and the responses written to it are not recoverable, which is why the `up`
  // is a one-way door.
  pgm.sql('ALTER TABLE customer_complaints DROP CONSTRAINT customer_complaints_closed_has_response');
  pgm.sql('ALTER TABLE customer_complaints DROP COLUMN response_note');
};
