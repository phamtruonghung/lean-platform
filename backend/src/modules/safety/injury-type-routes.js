/*
 * The Injury type catalogue over HTTP (issue #224), mounted by index.js under
 * `/api/safety` beside safety-incident-routes.js and body-part-routes.js. See
 * injury-types.js's header for what the catalogue is and why it carries no
 * Site.
 *
 * Two access rules, deliberately different — the same asymmetry
 * product-routes.js and defect-code-routes.js already draw for the Quality
 * Module's own catalogues:
 *
 *   - `GET /injury-types` is open to any active Account, deactivated rows
 *     excluded unless `?includeInactive=true` is asked for by name. An Injury
 *     type is shared reference data (ADR-0005), and whoever classifies an
 *     injury needs the list as a set of choices (ADR-0023). It names nobody,
 *     so ADR-0037's restriction — which is about three fields on an *incident*
 *     — has nothing to say here.
 *   - Creating, correcting and deactivating one are the administrator's. There
 *     is no Org Unit to scope a catalogue write by, so the scope half of
 *     "existence before scope" is the role check.
 *
 * `requireAdmin` is defined here rather than imported from People: People's
 * entry point deliberately does not export `requireAdmin`/`isAdmin` (see
 * people/index.js's own "deliberately NOT exported" list), so a Module outside
 * it carries its own copy — matching product-routes.js's and
 * defect-code-routes.js's, and People's own refusal sentence word for word.
 *
 * Existence before scope on every write (AGENTS.md §6): the Injury type named
 * in the URL is resolved first — a 404 naming it, malformed id included — and
 * only then is `requireAdmin` asked, so the same address answers 404 for a
 * type that is not there and 403 for one that is.
 */

const express = require('express');
const people = require('../people');
const injuryTypes = require('./injury-types');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// The Injury type named in the URL must exist before anything else — a clean
// 404, even for an administrator, and even for a malformed id (`parseId`
// answers null for anything that is not a positive integer, and
// findInjuryType is total: null and "no such row" are the same 404).
async function requireKnownInjuryType(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Injury type');
    req.injuryType = await injuryTypes.findInjuryType(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The catalogue. Active rows only unless the caller asks for the retired ones
// by exact string 'true' — never a stray or malformed value, which would
// silently widen the list past "in use" (product-routes.js's own
// includeInactive reasoning).
router.get('/injury-types', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    res.json({ injuryTypes: await injuryTypes.listInjuryTypes({ includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// An Injury type is created with its code and its name. A code that is
// already taken is a 409, and that clash is the one refusal this route can
// raise with no Injury type to name — which is why it is mapped in the
// service rather than resolved here.
router.post(
  '/injury-types',
  people.authenticate,
  people.requireActive,
  requireAdmin,
  async (req, res, next) => {
    try {
      const injuryType = await injuryTypes.createInjuryType(req.body ?? {}, req.account.id);
      res.status(201).json({ injuryType });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting one: its name, and whether it is still in use. Deactivating and
// reactivating ride in the same correction rather than a verb of their own —
// there is no delete here (injury-types.js's own header). Its code is refused
// by the service rather than silently ignored.
router.patch(
  '/injury-types/:id',
  people.authenticate,
  people.requireActive,
  requireKnownInjuryType,
  requireAdmin,
  async (req, res, next) => {
    try {
      const injuryType = await injuryTypes.updateInjuryType(
        req.injuryType.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ injuryType });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
