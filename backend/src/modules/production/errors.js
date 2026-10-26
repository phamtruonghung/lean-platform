/*
 * Error plumbing for the Production Module — this Module's own copy, on
 * purpose. ADR-0006's third clause ("domain, not utility") keeps People's
 * httpError/notFound/parseId/handleError on People's side of the boundary, and
 * People's index.js header names the sibling files as the intended
 * alternative. Byte-similar to the copies in people/, maintenance/, actions/,
 * quality/ and safety/ by design: the duplication is the seam, not an
 * oversight. Issue #333 is the Module that earned this one.
 */

// `code` is optional — see modules/people/errors.js's own comment on
// httpError for the full reasoning; mirrored here so the Modules'
// generic error plumbing stays byte-similar rather than drifting the moment
// one of them gains a capability the others have no current call site for.
function httpError(status, message, code) {
  const error = new Error(message);
  error.status = status;
  if (code !== undefined) error.code = code;
  return error;
}

function notFound(what) {
  return httpError(404, `${what} not found`);
}

function parseId(value) {
  if (value === undefined || value === null) return null;
  const str = String(value).trim();
  return /^[1-9][0-9]*$/.test(str) ? str : null;
}

function handleError(error, res, next) {
  if (error.status) {
    const body = { message: error.message };
    if (error.code !== undefined) body.code = error.code;
    return res.status(error.status).json(body);
  }
  return next(error);
}

module.exports = { httpError, notFound, parseId, handleError };
