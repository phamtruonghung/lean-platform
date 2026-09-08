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
  `(${alias}.expires_on IS NULL OR ${alias}.expires_on > CURRENT_DATE)`;

module.exports = { escapeLikePattern, QUALIFICATION_IS_CURRENT_SQL };
