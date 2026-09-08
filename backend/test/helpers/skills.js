/*
 * Skill and Employee-skill fixtures shared by directory.test.js and
 * work-orders.test.js — issue #62 put a real employee_skills row in both
 * suites' path, one reading it back through the candidate list, the other
 * through the assign write that (per ADR-0018) must never refuse on the
 * strength of it. Both files were carrying byte-similar copies of the same
 * two inserts, down to the same employee_skills_expiry_valid comment; this
 * is the one definition, imported by both rather than kept in sync by hand.
 *
 * Neither function tracks the id it inserted for its caller — cleanup is
 * each test file's own decision. directory.test.js deletes employee_skills
 * by employee_id (so it never needs the row id back) and skills by id;
 * work-orders.test.js tracks employee_skills.id separately, since its own
 * test.after deletes by that id list instead. `pool` and `uniqueCode` are
 * passed in explicitly rather than imported, since each test file only has
 * a real `pool` once its own test.before has run.
 */

// expires_on must be > assessed_on (CONSTRAINT employee_skills_expiry_valid,
// baseline migration) — so a LAPSED row is assessed_on '2020-01-01',
// expires_on '2021-01-01'. Pass expiresOn explicitly, or the
// employee_skills_set_expiry trigger will derive one from the skill's own
// revalidation_months. assessedOn defaults to CURRENT_DATE via COALESCE at
// the database, not in JS, so a caller that omits it always gets "today".
async function insertEmployeeSkill(pool, { employeeId, skillId, assessedOn, expiresOn }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, assessed_on, expires_on)
     VALUES ($1, $2, 3, COALESCE($3::date, CURRENT_DATE), $4) RETURNING id`,
    [employeeId, skillId, assessedOn ?? null, expiresOn ?? null]
  );
  return row.id;
}

async function insertSkill(pool, uniqueCode, { name = 'Test Skill', revalidationMonths = null } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO skills (code, name, revalidation_months) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SK'), name, revalidationMonths]
  );
  return row;
}

module.exports = { insertSkill, insertEmployeeSkill };
