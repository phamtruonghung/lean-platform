/*
 * The Body part catalogue over HTTP (issue #224), mounted by index.js under
 * `/api/safety` beside injury-type-routes.js. See that file's header for the
 * two access rules this mirrors exactly — an open read for any active Account,
 * an administrator's write — and body-parts.js's for the catalogue itself.
 *
 * The one thing this file says that its sibling does not: a Body part's
 * `region` is a value with a known set, so an unknown one is a 400 naming the
 * field, raised by body-parts.js rather than left to the baseline's own CHECK.
 */

const express = require('express');
const people = require('../people');
const bodyParts = require('./body-parts');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

async function requireKnownBodyPart(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Body part');
    req.bodyPart = await bodyParts.findBodyPart(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The catalogue, ordered by region and then by code. `regions` rides along on
// the same answer so a form can offer the known set without a second address
// of its own — the set is the baseline's CHECK, not a table, so there is
// nothing else to read it from.
router.get('/body-parts', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    res.json({
      bodyParts: await bodyParts.listBodyParts({ includeInactive }),
      regions: bodyParts.BODY_PART_REGIONS
    });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A Body part is created with its code, its name and the region it is filed
// under. The region is optional — the column's own `'other'` default fires
// when a caller says nothing — and an unknown one is a 400 from body-parts.js.
router.post(
  '/body-parts',
  people.authenticate,
  people.requireActive,
  requireAdmin,
  async (req, res, next) => {
    try {
      const bodyPart = await bodyParts.createBodyPart(req.body ?? {}, req.account.id);
      res.status(201).json({ bodyPart });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting one: its name, its region, and whether it is still in use. Its
// code is refused by the service rather than silently ignored.
router.patch(
  '/body-parts/:id',
  people.authenticate,
  people.requireActive,
  requireKnownBodyPart,
  requireAdmin,
  async (req, res, next) => {
    try {
      const bodyPart = await bodyParts.updateBodyPart(
        req.bodyPart.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ bodyPart });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
