/*
 * Small SQL helpers shared across this Module's files that would otherwise
 * need to require each other. `escapeLikePattern` started life inside
 * directory.js (issue #9's Employee search); plant.js needed the exact same
 * helper for issue #35's Org Unit search, but plant.js cannot `require
 * ('./directory')` — directory.js already requires plant.js (getOrgUnit),
 * and that would make the two files circular. This file sits below both.
 *
 * `QUALIFICATION_IS_CURRENT_SQL` started life inside skills.js (issue #11,
 * `listQualifiedEmployees`'s own predicate). directory.js needs the exact
 * same expression for `listAssigneeCandidates` (issue #62), but directory.js
 * cannot `require('./skills')`: skills.js already requires directory.js (for
 * `getEmployee`, in recordEmployeeSkill), and a directory.js -> skills.js
 * require would close that into a cycle — confirmed empirically, not assumed:
 * whichever of the two files Node loads first leaves the other with
 * `undefined` for the value it destructured at require time, since a
 * circular require hands back the partial (not-yet-fully-assigned)
 * module.exports of whichever file is still mid-load. Living here instead
 * keeps both call sites importing the one definition, never copying it.
 */

// Postgres's own LIKE/ILIKE escape rules: `\` must be escaped first, so a
// literal backslash in the search text does not turn the `%`/`_` escapes
// added after it into something else. The `ESCAPE '\'` clause is what makes
// these three characters, and only these three, special in the pattern this
// function builds.
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

// The one definition of "a qualification is current" — the exact predicate
// v_skill_coverage uses for qualified_headcount (baseline migration), so this
// file, that view, skills.js's listQualifiedEmployees and directory.js's
// listAssigneeCandidates can never quietly disagree about what lapsed
// means. directory.js negates it for its own `isLapsed`; a second literal
// copy of this expression anywhere in this Module is a bug.
const QUALIFICATION_IS_CURRENT_SQL = (alias) =>
  `(${alias}.expires_on IS NULL OR ${alias}.expires_on > employee_today(${alias}.employee_id))`;

// One definition of an Employee's resolved Org Unit and crew, shared by the
// Assessment assignment (assessments.js) and the crew picker's headcount
// (plant.js), so a count shown never disagrees with who `assign` creates.
// "Current" is provably single (`employee_assignments_no_overlap` is an
// `EXCLUDE USING gist`), so the lateral's `LIMIT 1` never picks between two
// rows. The resolver is the repo's own (`directory.js`, `leave-requests.js`):
// the current assignment's Org Unit, else the Employee's default.
const RESOLVED_EMPLOYEES_SQL = `
  SELECT e.id AS employee_id, e.display_name, e.is_active,
         COALESCE(ca.org_unit_id, e.default_org_unit_id) AS org_unit_id,
         CASE WHEN ca.employee_id IS NOT NULL THEN ca.crew_id ELSE e.default_crew_id END AS crew_id
    FROM employees e
    LEFT JOIN LATERAL (
      SELECT ea.employee_id, ea.org_unit_id, ea.crew_id
        FROM employee_assignments ea
       WHERE ea.employee_id = e.id
         AND ea.effective_from <= employee_today(ea.employee_id)
         AND (ea.effective_to IS NULL OR ea.effective_to > employee_today(ea.employee_id))
       LIMIT 1
    ) ca ON TRUE
`;

module.exports = { escapeLikePattern, QUALIFICATION_IS_CURRENT_SQL, RESOLVED_EMPLOYEES_SQL };
