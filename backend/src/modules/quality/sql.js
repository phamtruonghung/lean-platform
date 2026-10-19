/*
 * SQL helpers shared by this Module's catalogue listings. A duplicate of
 * People's sql.js definition rather than a require of it: that file is
 * People's own internal, and ADR-0006's third clause keeps it there.
 *
 * The backslash is escaped first, so a literal backslash in the search text
 * does not turn the `%`/`_` escapes added after it into something else; the
 * caller adds the `ESCAPE` clause that makes these three characters special
 * and no others.
 */

function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

module.exports = { escapeLikePattern };
