/*
 * Pictures of a Quality issue over HTTP (issue #419).
 *
 * Four addresses per record kind, and the same four for both, so this file
 * mounts one small set of handlers twice rather than writing them out:
 *
 *   GET    /nonconformances/:id/images            the pictures' own metadata
 *   POST   /nonconformances/:id/images            one picture, as the body
 *   GET    /nonconformances/:id/images/:imageId   the picture itself
 *   DELETE /nonconformances/:id/images/:imageId   remove it
 *
 *   ... and the same under /complaints/:id/images.
 *
 * **Why the body is the picture rather than a multipart form.** The backend
 * carries no multipart parser and Express has none built in; adding `multer` or
 * `busboy` for this one door is a dependency the Platform does not otherwise
 * want, and base64-in-JSON would add a third again to every upload's size and a
 * decode step the client's 5 MiB ceiling then has to be duplicated around. A raw
 * body with its own `Content-Type` is the smallest thing that is still honest:
 * the route reads bytes, the file's own header says what it is
 * (`image-file.js`), and the caption rides in the query string because it is one
 * optional line rather than a document. `express.raw` is scoped to this route
 * and these three types, so the app-wide `express.json({ limit: '100kb' })`
 * never sees a picture and nothing else's body parsing changes.
 *
 * **Reading is the register's rule, writing is the register's rule.** Anyone who
 * can see the record's Site may look at its pictures — the same `canSeeSite` the
 * register and the record's own read ask (ADR-0009: Org Unit scope decides where
 * an Account may act, not what it may know about). Adding or removing one is a
 * change to the record, so it is a write Grant reaching the Org Unit the record
 * is filed at (`canAct({ write: true })`, spelled out because it defaults to
 * false), which is what a Disposition and a response already require.
 *
 * Existence before scope, in the order AGENTS.md §6 fixes: the record (404), then
 * its Site's visibility (403 with People's own sentence), then the write scope.
 *
 * **The ADR-0061 retrofit (issue #503).** Every one of these eight routes asks
 * `people.requirePermission` beside the Grant question it already asked: each
 * read asks the record kind's own `*_DISPLAY` code and each write its
 * `*_RECORD` code, because a picture is part of the record it hangs off. All four
 * codes are seeded on ROLE_STANDARD — the default group every approved Account
 * carries — so no gate here refuses an Account that could reach these addresses
 * before it, and the Grant half is untouched.
 */

const express = require('express');
const people = require('../people');
const nonconformances = require('./nonconformances');
const customerComplaints = require('./customer-complaints');
const images = require('./issue-images');
const { CONTENT_TYPES } = require('./image-file');
const { handleError, notFound } = require('./errors');

const router = express.Router();

// 6 MiB rather than 5: the file's own 5 MiB ceiling is checked in
// `image-file.js` where the refusal can say *why*, and this is only the parser's
// guard against a body nobody should be sending at all.
const rawImage = express.raw({ type: CONTENT_TYPES, limit: '6mb' });

function parseImageBody(req, res, next) {
  rawImage(req, res, (error) => {
    if (error) return handleError(error, res, next);
    return next();
  });
}

// The two record kinds, and what each one needs to be resolved, judged visible
// and judged writable. One table, so the four handlers below are written once.
const MOUNTS = [
  {
    kind: 'nonconformance',
    base: '/nonconformances',
    label: 'Non-conformance',
    // The register's own codes (ADR-0061, issue #503). Both are seeded on
    // ROLE_STANDARD, so neither gate refuses an Account that could reach these
    // pictures before it: a picture is part of the record it is attached to.
    readCode: 'QLT_NONCONFORMANCES_DISPLAY',
    writeCode: 'QLT_NONCONFORMANCES_RECORD',
    find: (id) => nonconformances.findNonconformance(id)
  },
  {
    kind: 'complaint',
    base: '/complaints',
    label: 'Customer complaint',
    readCode: 'QLT_COMPLAINTS_DISPLAY',
    writeCode: 'QLT_COMPLAINTS_RECORD',
    find: (id) => customerComplaints.findComplaint(id)
  }
];

function scopeFor(mount) {
  async function requireIssue(req, _res, next) {
    try {
      const issue = await mount.find(req.params.id);
      if (!issue) throw notFound(mount.label);
      req.issue = issue;
      return next();
    } catch (error) {
      return handleError(error, _res, next);
    }
  }

  async function requireVisible(req, res, next) {
    try {
      const allowed = await people.canSeeSite({ account: req.account, siteId: req.issue.siteId });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }
      return next();
    } catch (error) {
      return handleError(error, res, next);
    }
  }

  async function requireWrite(req, res, next) {
    try {
      const allowed = await people.canAct({
        account: req.account,
        orgUnitId: req.issue.orgUnitId,
        write: true
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }
      return next();
    } catch (error) {
      return handleError(error, res, next);
    }
  }

  return { requireIssue, requireVisible, requireWrite };
}

for (const mount of MOUNTS) {
  const { requireIssue, requireVisible, requireWrite } = scopeFor(mount);
  const mayRead = people.requirePermission(mount.readCode);
  const mayWrite = people.requirePermission(mount.writeCode);

  const list = async (req, res, next) => {
    try {
      const pictures = await images.listImages({ kind: mount.kind, issueId: req.params.id });
      return res.json({ images: pictures });
    } catch (error) {
      return handleError(error, res, next);
    }
  };

  const upload = async (req, res, next) => {
    try {
      const picture = await images.addImage({
        kind: mount.kind,
        issueId: req.params.id,
        buffer: req.body,
        declaredType: req.headers['content-type'],
        caption: req.query.caption,
        accountId: req.account.id
      });
      return res.status(201).json({ image: picture });
    } catch (error) {
      return handleError(error, res, next);
    }
  };

  const read = async (req, res, next) => {
    try {
      const picture = await images.readImageBytes({
        kind: mount.kind,
        issueId: req.params.id,
        imageId: req.params.imageId
      });
      // `private` because the bytes are behind a session, and an hour because a
      // thumbnail that has not changed is not worth a second round trip while a
      // supervisor scrolls the same record.
      return res
        .status(200)
        .set('Content-Type', picture.contentType)
        .set('ETag', picture.etag)
        .set('Cache-Control', 'private, max-age=3600')
        .send(picture.bytes);
    } catch (error) {
      return handleError(error, res, next);
    }
  };

  const remove = async (req, res, next) => {
    try {
      await images.removeImage({
        kind: mount.kind,
        issueId: req.params.id,
        imageId: req.params.imageId,
        accountId: req.account.id
      });
      return res.status(204).send();
    } catch (error) {
      return handleError(error, res, next);
    }
  };

  router.get(
    `${mount.base}/:id/images`,
    people.authenticate,
    people.requireActive,
    requireIssue,
    requireVisible,
    mayRead,
    list
  );

  router.post(
    `${mount.base}/:id/images`,
    people.authenticate,
    people.requireActive,
    requireIssue,
    requireVisible,
    requireWrite,
    mayWrite,
    parseImageBody,
    upload
  );

  router.get(
    `${mount.base}/:id/images/:imageId`,
    people.authenticate,
    people.requireActive,
    requireIssue,
    requireVisible,
    mayRead,
    read
  );

  router.delete(
    `${mount.base}/:id/images/:imageId`,
    people.authenticate,
    people.requireActive,
    requireIssue,
    requireVisible,
    requireWrite,
    mayWrite,
    remove
  );
}

module.exports = router;
