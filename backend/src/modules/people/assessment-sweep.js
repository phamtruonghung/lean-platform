/*
 * The lazy time transitions of an Attempt (issue #588, spec sections 5.2 and 9).
 *
 * There is no cron, no background worker and no timer anywhere: the two
 * transitions the clock causes are applied by the next person who looks, in
 * an `UPDATE ... WHERE` guarded by the status it moves from, so running one
 * twice, or two at once, writes once.
 *
 *   - `in_progress` -> `submitted` once `now() >= deadline_at`: the saved
 *     Answers are scored first, `submitted_at` is the deadline (not the moment
 *     somebody looked) and `submitted_late` is set.
 *   - `assigned` -> `expired` once the Site's local date (`plant_date`,
 *     ADR-0048, resolved by the database) is past `due_on`. A NULL `due_on`
 *     never expires. `due_on` bounds starting only; a paper started at 23:50 on
 *     the due date keeps its own `deadline_at`.
 *
 * Every sweep is scoped to one Attempt, one Employee or one Assessment, so a
 * read can never become a table-wide write. Each one commits in its own
 * transaction (`withActor(null, ...)`) BEFORE the read or write that asked for
 * it: a refusal that follows must not roll the transition back, or an
 * abandoned paper would never close. The rows a finalise touches are locked
 * `FOR UPDATE` in id order first and the status is re-checked under that lock,
 * so two racing sweeps finalise a row once and the loser sees it already done.
 *
 * Only the database's `now()` counts: no caller supplies a time.
 *
 * This file requires nothing but the pool, so `assessments.js` and
 * `assessment-marking.js` can both use it without requiring each other.
 */

const { withActor } = require('../../platform/db');

// Each scope binds one `bigint[]` as `$1`.
const SCOPES = {
  attempt: 'at.id = ANY($1::bigint[])',
  employee: 'at.employee_id = ANY($1::bigint[])',
  assessment: 'at.assessment_id = ANY($1::bigint[])'
};

// Applies both transitions to the Attempts in one scope. Returns how many rows
// changed, so a list can re-read when the sweep altered what it just fetched.
async function applyTransitions(client, scope, ids) {
  const where = SCOPES[scope];
  let changed = 0;

  // Lock the due rows (re-checking the status once the lock is held), then
  // score and finalise exactly those.
  const { rows: due } = await client.query(
    `SELECT at.id
       FROM assessment_attempts at
      WHERE ${where}
        AND at.status = 'in_progress'
        AND now() >= at.deadline_at
      ORDER BY at.id
      FOR UPDATE OF at`,
    [ids]
  );
  if (due.length > 0) {
    const dueIds = due.map((row) => row.id);
    await client.query(
      `UPDATE assessment_attempt_questions
          SET points = CASE WHEN chosen_option IS NOT NULL
                             AND other_text IS NULL
                             AND chosen_option = correct_option THEN 1 ELSE 0 END
        WHERE attempt_id = ANY($1::bigint[])`,
      [dueIds]
    );
    const { rowCount } = await client.query(
      `UPDATE assessment_attempts at
          SET status = 'submitted',
              submitted_at = at.deadline_at,
              submitted_late = TRUE,
              score = (SELECT COALESCE(sum(q.points), 0)::int
                         FROM assessment_attempt_questions q WHERE q.attempt_id = at.id)
        WHERE at.id = ANY($1::bigint[])
          AND at.status = 'in_progress'`,
      [dueIds]
    );
    changed += rowCount;
  }

  const { rowCount: expired } = await client.query(
    `UPDATE assessment_attempts at
        SET status = 'expired'
       FROM assessments a
      WHERE a.id = at.assessment_id
        AND ${where}
        AND at.status = 'assigned'
        AND a.due_on IS NOT NULL
        AND plant_date(a.org_unit_id, now()) > a.due_on`,
    [ids]
  );
  return changed + expired;
}

async function sweepScope(scope, ids) {
  if (ids.length === 0) return 0;
  return withActor(null, (client) => applyTransitions(client, scope, ids));
}

const sweepAttempt = (attemptId) => sweepScope('attempt', [attemptId]);
const sweepEmployee = (employeeId) => sweepScope('employee', [employeeId]);
const sweepAssessments = (assessmentIds) => sweepScope('assessment', assessmentIds);

module.exports = { sweepAttempt, sweepEmployee, sweepAssessments };
