/*
 * The Defect code catalogue over HTTP (issue #203), mounted by index.js under
 * `/api/quality` beside product-routes.js. See that file's header for the two
 * access rules this mirrors and index.js's for the Module as a whole.
 *
 *   - `GET /defect-codes` is open to any approved Account, deactivated codes
 *     excluded unless `?includeInactive=true` is asked for by name. A Defect
 *     code is reference data shared by every Site (ADR-0005), and a later
 *     slice needs the tree as a set of choices (ADR-0023) for whoever is
 *     recording what went wrong with what. `QLT_DEFECT_CODES_DISPLAY` is seeded
 *     on ROLE_STANDARD, the default group every approved Account carries, so
 *     the read gate refuses nobody who could reach this list before it.
 *   - Creating, correcting and deactivating a code ask
 *     `QLT_DEFECT_CODES_CHANGE`, seeded on ROLE_ADMIN alone — the exact set the
 *     administrator check it replaced admitted, and an administrator answers
 *     every permission true before a role is read (ADR-0061). No Account gains
 *     or loses access; the refusal names the permission rather than the role.
 *
 * Existence before scope on every write (AGENTS.md §6), including the parent a
 * code is placed under: the code named in the URL is resolved first (404), and
 * only then is `QLT_DEFECT_CODES_CHANGE` asked. Inside the service the same
 * order holds for the tree: a proposed parent that does not exist is a 404
 * naming it, and a proposed parent that would make a cycle is a 400 — never a
 * raw foreign key or constraint violation.
 */

const express = require('express');
const people = require('../people');
const defectCodes = require('./defect-codes');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

// The two codes this catalogue asks (ADR-0061, issue #503).
const mayReadDefectCodes = people.requirePermission('QLT_DEFECT_CODES_DISPLAY');
const mayChangeDefectCodes = people.requirePermission('QLT_DEFECT_CODES_CHANGE');

// The code named in the URL must exist before anything else — a clean 404,
// even for an administrator, and even for a malformed id.
async function requireKnownDefectCode(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Defect code');
    req.defectCode = await defectCodes.findDefectCode(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The tree, flat: each row names its own parentId, its category and its
// default severity, and the client assembles the shape. Every active Account
// may read it — see this file's header.
router.get(
  '/defect-codes',
  people.authenticate,
  people.requireActive,
  mayReadDefectCodes,
  async (req, res, next) => {
    try {
      const includeInactive = req.query.includeInactive === 'true';
      res.json({ defectCodes: await defectCodes.listDefectCodes({ includeInactive }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A Defect code is created with its code, its name, its category, its default
// severity and — optionally — the code it sits beneath. Turning the code
// itself (409) and placing it under a code that does not exist (404) or would
// make the tree cyclic (400) are all refusals defect-codes.js owns, because
// each needs a query this route has no business making.
router.post(
  '/defect-codes',
  people.authenticate,
  people.requireActive,
  mayChangeDefectCodes,
  async (req, res, next) => {
    try {
      const defectCode = await defectCodes.createDefectCode(req.body ?? {}, req.account.id);
      res.status(201).json({ defectCode });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting a code: its name, its category, its default severity, where it
// sits in the tree and whether it is still in use. Its code is refused by
// defect-codes.js rather than silently ignored.
router.patch(
  '/defect-codes/:id',
  people.authenticate,
  people.requireActive,
  requireKnownDefectCode,
  mayChangeDefectCodes,
  async (req, res, next) => {
    try {
      const defectCode = await defectCodes.updateDefectCode(req.defectCode.id, req.body ?? {}, req.account.id);
      res.json({ defectCode });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
