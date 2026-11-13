/*
 * The slide show over HTTP (issue #419).
 *
 *   GET  /sites/:siteId/slide-show            what is on this Site's wall
 *   PUT  /slide-show/:kind/:id                put one issue on it, or take it off
 *   PUT  /sites/:siteId/slide-show/order      the order the wall plays in
 *
 * **Reading a Site's show is reading its registers.** `people.canSeeSite` for the
 * Site, exactly as `GET /sites/:siteId/nonconformances` and
 * `GET /sites/:siteId/complaints` ask it — any Grant, read or write, on any Org
 * Unit of the Site. An issue nobody at that Site may see is in nobody's show,
 * because the show is built from the same rows the register lists (ADR-0009).
 *
 * **Choosing an issue is a change to that issue.** A write Grant reaching the
 * Org Unit it is filed at, the same scope a Disposition or a response needs, and
 * the same refusal sentence when it is not there (403 with People's
 * `OUTSIDE_GRANTED_ORG_UNITS` — the registers' own rule; a record that does not
 * exist is the 404 before it).
 *
 * **Ordering is checked entry by entry.** The picker sends the whole list, and
 * every entry must already be chosen and belong to this Site; one that is not
 * refuses the whole request with a 409 rather than half-writing an order. The
 * write scope is asked per entry for the same reason it is asked per record
 * elsewhere: an Account that may write one issue and not another must not be
 * able to move the second one through this door.
 *
 * **The ADR-0061 retrofit (issues #503 and #535).** The read asks
 * `QLT_SLIDESHOW_DISPLAY`, and both writes ask `QLT_SLIDESHOW_CHOOSE`, which is
 * the code that names the act: choosing an issue and ordering the wall. The code
 * runs in front of the write-scope question each route already asked, which is
 * untouched — the code answers which door, the Grant answers whose issue and
 * which Org Unit.
 *
 * `QLT_SLIDESHOW_DISPLAY` is seeded on ROLE_STANDARD, so the read refuses nobody
 * who could read the show before it. `QLT_SLIDESHOW_CHOOSE` was seeded on
 * ROLE_ADMIN alone, where today any write Grant reaching an issue's Org Unit may
 * put it on the wall — so `1803900000000_quality-write-codes.js` widens it onto
 * every role, and the Team Leader who curates the show keeps doing so. What the
 * widening buys is the door being visible and removable in the Roles Screen.
 */

const express = require('express');
const people = require('../people');
const nonconformances = require('./nonconformances');
const customerComplaints = require('./customer-complaints');
const slideShow = require('./slide-show');
const { ISSUE_KINDS } = require('./issue-images');
const { httpError, notFound, handleError } = require('./errors');

const router = express.Router();

// The two codes this file asks (ADR-0061, issues #503 and #535).
// `QLT_SLIDESHOW_DISPLAY` is seeded on ROLE_STANDARD so the read refuses nobody
// who could read the show before it; `QLT_SLIDESHOW_CHOOSE` is widened onto every
// role by `1803900000000_quality-write-codes.js`, because today's reach is the
// write Grant on the issue, not the role.
const mayReadSlideShow = people.requirePermission('QLT_SLIDESHOW_DISPLAY');
const mayChooseSlideShow = people.requirePermission('QLT_SLIDESHOW_CHOOSE');

const FINDERS = {
  nonconformance: (id) => nonconformances.findNonconformance(id),
  complaint: (id) => customerComplaints.findComplaint(id)
};

async function requireKnownSite(req, res, next) {
  try {
    const site = await people.findSite(req.params.siteId);
    if (!site) throw notFound('Site');
    req.site = site;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function requireSiteVisible(req, res, next) {
  try {
    const allowed = await people.canSeeSite({ account: req.account, siteId: req.site.id });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Resolves one kind/id pair to the record, refusing a record that is not there
// (404) and one the caller may not write (403) with the registers' own sentence.
async function requireWritableIssue(req, res, next) {
  try {
    const find = FINDERS[req.params.kind];
    if (!find) {
      throw httpError(400, `kind must be one of ${Object.keys(ISSUE_KINDS).join(', ')}`);
    }
    const issue = await find(req.params.id);
    if (!issue) throw notFound(ISSUE_KINDS[req.params.kind].label);
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: issue.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.issue = issue;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.get(
  '/sites/:siteId/slide-show',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  mayReadSlideShow,
  async (req, res, next) => {
    try {
      const issues = await slideShow.listForSite(req.site.id);
      return res.json({ siteId: String(req.site.id), issues });
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

router.put(
  '/slide-show/:kind/:id',
  people.authenticate,
  people.requireActive,
  mayChooseSlideShow,
  requireWritableIssue,
  async (req, res, next) => {
    try {
      const choice = await slideShow.setChosen({
        kind: req.params.kind,
        id: req.params.id,
        chosen: req.body ? req.body.chosen : undefined,
        accountId: req.account.id
      });
      return res.json(choice);
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

router.put(
  '/sites/:siteId/slide-show/order',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  mayChooseSlideShow,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      const entries = req.body ? req.body.slides : undefined;
      if (!Array.isArray(entries)) throw httpError(400, 'slides must be a list of { kind, id }');

      // Every entry resolved and scope-checked before anything is written, so a
      // refused entry leaves the wall's order exactly as it was.
      for (const entry of entries) {
        const find = entry && FINDERS[entry.kind];
        if (!find) {
          throw httpError(400, `kind must be one of ${Object.keys(ISSUE_KINDS).join(', ')}`);
        }
        const issue = await find(entry.id);
        if (!issue) throw notFound(ISSUE_KINDS[entry.kind].label);
        const allowed = await people.canAct({
          account: req.account,
          orgUnitId: issue.orgUnitId,
          write: true
        });
        if (!allowed) {
          return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
        }
      }

      const issues = await slideShow.setOrder({
        siteId: req.site.id,
        entries,
        accountId: req.account.id
      });
      return res.json({ siteId: String(req.site.id), issues });
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

module.exports = router;
