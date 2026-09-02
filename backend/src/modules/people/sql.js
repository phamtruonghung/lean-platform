/*
 * Small SQL helpers shared across this Module's files that would otherwise
 * need to require each other. `escapeLikePattern` started life inside
 * directory.js (issue #9's Employee search); plant.js needed the exact same
 * helper for issue #35's Org Unit search, but plant.js cannot `require
 * ('./directory')` — directory.js already requires plant.js (getOrgUnit),
 * and that would make the two files circular. This file sits below both.
 */

// Postgres's own LIKE/ILIKE escape rules: `\` must be escaped first, so a
// literal backslash in the search text does not turn the `%`/`_` escapes
// added after it into something else. The `ESCAPE '\'` clause is what makes
// these three characters, and only these three, special in the pattern this
// function builds.
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

module.exports = { escapeLikePattern };
