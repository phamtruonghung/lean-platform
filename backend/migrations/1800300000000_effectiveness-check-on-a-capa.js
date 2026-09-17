/**
 * The effectiveness check on a CAPA (issue #211, ADR-0034).
 *
 * A CAPA closes only when the investigation is finished and the fix has held.
 * The baseline already carries the fields that say so — `effectiveness_check_
 * due_at`, `effectiveness_verified_at`, `effectiveness_note` — and two of them
 * are wrong or missing for the act this ticket records. The Module spec (#200)
 * names exactly two additions, and this migration adds exactly those: **the
 * verifying Account** and **an effectiveness-check delay in days, default 30**.
 *
 * **1. The verifying Account is a new column, and the old one is left alone.**
 * The baseline's `effectiveness_verified_by` references `employees`, and the
 * person who decides that a fix held is whoever holds Quality authority at the
 * CAPA's Org Unit (ADR-0035) — an Account, which CONTEXT.md is explicit need
 * not be an Employee at all. Repointing that foreign key would be the tidier
 * schema and a contract change at the same time: an image from before this
 * migration writes an Employee id into that column, and against a key that
 * referenced `app_users` every such row would be refused. ADR-0007's expand-now
 * rule forbids it, so `effectiveness_verified_by` keeps its key, nothing in the
 * Module writes it, and `effectiveness_verified_by_account_id` is the column
 * this slice writes. A later ticket that wants the old column gone can drop it
 * once no image writes it — contracting is a separate, later decision.
 *
 * **2. The delay is stored on the CAPA, defaulted to 30.** "The check becomes
 * due a set number of days later (30 by default, adjustable on the CAPA)": the
 * number belongs to the investigation, not to a platform setting, because two
 * CAPAs opened the same week can reasonably be verified on different cadences.
 * `NOT NULL DEFAULT 30` makes the default the schema's own statement rather
 * than something a service function has to remember, and the range CHECK is a
 * backstop for the service's own 400: a negative delay is a date in the past,
 * and a four-digit one is a typo that would put a check due decades after the
 * person who wrote it has retired. Zero is legal on purpose — "verify this the
 * day the Concern closes" is a real instruction for a high-severity problem.
 *
 * **3. The due date is *stored*, set at the moment the Concern closes — and
 * that is a decision, not an accident.** The ticket leaves this open (a stored
 * date and a date derived on read from the closure time plus the delay differ
 * in exactly one case), so the argument belongs here. The baseline already
 * carries `effectiveness_check_due_at` as a DATE column and already indexes it,
 * which is the schema saying where the fact lives. More importantly the two
 * readings disagree the moment the delay is changed *after* the Concern closed,
 * and the ticket's own sentence settles which one is wanted: the delay "can be
 * changed while the CAPA is open", and "the check's due date is *set* when the
 * Concern closes". Setting is an act with a time; a derived date would move
 * under the caller's feet every time somebody revised the number behind it, and
 * the date a check was judged against — the date an auditor asks about — would
 * no longer be recoverable. So: the delay governs the *next* closure, the date
 * written at a closure stands, and `capa-effectiveness.test.js` pins exactly
 * that (a delay changed after the closure leaves the due date where it was).
 * The alternative — derive it on read, `completed_at::date + delay` — is the
 * one this file rejects, and it is worth being plain about what it buys: a
 * single statement instead of two, at the price of a fact that changes after
 * the fact.
 *
 * **Why the write is the service's and not a trigger.** The due date is set by
 * `completePhase` in `actions.js`, in the same transaction that closes the
 * Concern, and there is no trigger here. ADR-0033 already fixes this shape for
 * the thing the due date is a consequence of: "every phase completion writes
 * the status that phase implies, in the same transaction, inside one service
 * function". A trigger would also fire for a writer that never came through the
 * service, and that is the argument *for* one — but the Concern's closure is a
 * service transition with two 409s and a lock of its own (nothing closes a
 * Concern unverified), and a derived cross-table write hidden in the schema
 * would be the one part of that transition a reader of `completePhase` could
 * not see. The invariant the schema does own is stated as a constraint, as in
 * every other case in this database: see `capas_eightd_needs_verification`,
 * which this slice had to satisfy rather than add.
 *
 * **What is deliberately NOT tightened.** `capas_eightd_needs_verification`
 * ("an 8D that was never verified is a 7D") requires
 * `effectiveness_verified_at IS NOT NULL` for a closed 8D and is left exactly
 * as it is. Requiring the *Account* alongside it would be refused by rows
 * written before this column existed, and would refuse `capa-whys.test.js`'s
 * own `insertClosedCapa` fixture — a test arranging a closed investigation that
 * no request on the branch could produce. Nothing in this Module closes a CAPA
 * without writing both, so the weaker constraint costs nothing and the stronger
 * one would be a contract change disguised as tidiness.
 *
 * **No new index.** The baseline's own `capas_verification_due_idx` — on
 * `effectiveness_check_due_at WHERE status = 'verifying'` — was written for
 * precisely this read, and it becomes live the moment this slice sets a CAPA to
 * `verifying` when its Concern closes. The register's overdue filter rides on
 * it; a second index over the same column would be a second one-way door for a
 * list of investigations, which is a small set by nature.
 *
 * `capas` already carries the deny-all RLS floor (ADR-0004): this migration
 * adds columns to an existing table and creates none, so there is nothing to
 * enable. Nothing is backfilled either — no version of this codebase has ever
 * written a `capas` row except the two this Module's own slices create, and
 * every row it created takes the 30-day default, which is the value the ticket
 * names. Every change here is additive, so the image this migration replaces
 * keeps running against it unchanged (ADR-0007).
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // The Account that recorded the check (1). Nullable: a CAPA whose fix has
  // not been verified yet has no verifier, and every row written before this
  // column existed is in exactly that state.
  pgm.sql(
    'ALTER TABLE capas ADD COLUMN effectiveness_verified_by_account_id BIGINT REFERENCES app_users (id)'
  );

  // The delay in days between the Concern closing and the check falling due
  // (2). The default is the ticket's own number and the schema's, so a row
  // written outside the service is a 30-day investigation rather than a NULL
  // the overdue read has to guess about.
  pgm.sql(
    'ALTER TABLE capas ADD COLUMN effectiveness_check_delay_days SMALLINT NOT NULL DEFAULT 30'
  );
  pgm.sql(`
    ALTER TABLE capas
      ADD CONSTRAINT capas_effectiveness_delay_days_range
        CHECK (effectiveness_check_delay_days BETWEEN 0 AND 365)
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The constraint goes before the column it names.
  pgm.sql('ALTER TABLE capas DROP CONSTRAINT capas_effectiveness_delay_days_range');
  pgm.sql('ALTER TABLE capas DROP COLUMN effectiveness_check_delay_days');
  pgm.sql('ALTER TABLE capas DROP COLUMN effectiveness_verified_by_account_id');
};
