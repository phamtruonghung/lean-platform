/*
 * Error plumbing shared across the People Module — a Module internal
 * (ADR-0006): index.js does not re-export this file, since no other Module
 * needs it. Pulled out of plant.js and service.js, which each defined their
 * own byte-identical httpError, and out of the five separate copies of the
 * same res.status(error.status).json(...)-or-next(error) funnel that used to
 * live in authorization.js, plant-routes.js and routes.js.
 *
 * parseId lives here too, not in plant.js — service.js was reaching into
 * plant.js just to borrow it, which is unnecessary coupling between two
 * concerns (Account id parsing, Org Unit id parsing) that happen to use the
 * same rule but belong to neither file more than the other.
 */

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function notFound(what) {
  return httpError(404, `${what} not found`);
}

// Route params, query strings and JSON bodies all carry an id as *some*
// primitive, but ids are BIGINT, which `db.js` deliberately leaves unparsed
// (see that file's own header) — `pg` hands one back as a decimal string,
// not a `number`, since a `number` cannot hold every int64. Coercing through
// `Number` here would make an id compared against a row's own id (e.g. "is
// this Org Unit's parent at the same Site") silently false — `52 !== "52"`
// — so this validates and returns a string, never a number, which is also
// what keeps a route param and a column value the same type wherever this
// Module compares the two.
function parseId(value) {
  if (value === undefined || value === null) return null;
  const str = String(value).trim();
  return /^[1-9][0-9]*$/.test(str) ? str : null;
}

// A domain error carries its own status (httpError above) and is the
// expected shape for a bad request, a missing id, or a conflict; anything
// else is a genuine failure and goes to the app's own unhandled-error
// handler via next() rather than being answered here.
function handleError(error, res, next) {
  if (error.status) {
    return res.status(error.status).json({ message: error.message });
  }
  return next(error);
}

// The 403 body every Org Unit/Site scope refusal shares — authorization.js's
// requireOrgUnitScope and requireSiteScope, and plant-routes.js's
// requireOrgUnitCreateScope.
const OUTSIDE_GRANTED_ORG_UNITS = "Outside the caller's granted Org Units";

module.exports = { httpError, notFound, parseId, handleError, OUTSIDE_GRANTED_ORG_UNITS };
