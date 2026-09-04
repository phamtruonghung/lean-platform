/*
 * Error plumbing for the Maintenance Module — this Module's own copy, on
 * purpose. ADR-0006's third clause ("domain, not utility") keeps People's
 * httpError/notFound/parseId/handleError on People's side of the boundary,
 * and People's index.js header names this file as the intended alternative.
 * Byte-similar to modules/people/errors.js by design: the duplication is the
 * seam, not an oversight.
 */

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
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
    return res.status(error.status).json({ message: error.message });
  }
  return next(error);
}

module.exports = { httpError, notFound, parseId, handleError };
