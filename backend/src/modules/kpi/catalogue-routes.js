/*
 * The KPI catalogue and its Targets over HTTP (ADR-0055). Mounted by index.js
 * under `/api/kpi`.
 *
 * Who may act: the catalogue belongs to no Org Unit, so authority is asked about
 * the Site's root Org Unit (site-context.js's header says why) with
 * `people.canAct`: a read Grant of either level is enough to read, an edit
 * Grant (or an administrator) to write. `write: true` is spelled out on every
 * POST because it defaults to FALSE, and a write that forgot it would be
 * authorised by any read Grant with no error anywhere to notice.
 *
 * **The ADR-0061 retrofit (issue #513).** Both reads now also ask
 * `INS_KPI_CATALOGUE_DISPLAY` — the code `destinations.dart` names the KPI
 * catalogue Destination with, and the seed (migration 1803400000000) carries it
 * on exactly the four roles `ModuleRoles.kpi` offers that Screen to:
 * supervisor, engineer, manager and administrator. So no role the sidebar
 * admits there is refused, and the code does not replace the question above:
 * `canAct` still runs inside the handler and still decides *where* the Account
 * may ask. A tier board or a catalogue read is a Grant question, and a role
 * code is not a Grant.
 *
 * The two writes are gated by `INS_KPI_CATALOGUE_CHANGE` since the ADR-0061
 * retrofit's phase 2d, and the migration that ships with that slice is what
 * makes it narrowing-free: the seed declared the code on ROLE_ADMIN alone while
 * the catalogue Screen is offered to supervisor, engineer, manager and
 * administrator and enables its "Add KPI" affordance for any Account holding a
 * write Grant anywhere (`canWrite`, router.dart passes `/me`'s
 * `orgUnitScope.canWriteSomewhere`). `1804100000000_kpi-catalogue-write-roles.js`
 * seeds the code onto those three roles, so every role the Screen offers the
 * writes to keeps them; an operator-role Account with a write Grant loses them,
 * which is the declared narrowing the retrofit's other migrations also accept
 * (a code is a visible authority, and an administrator can add it to a role in
 * the Roles Screen). `canAct` still runs inside the handler and still decides
 * *where* the caller may ask.
 *
 * Order, the one AGENTS.md section 6 fixes: existence, then scope, then the
 * catalogue. The Site is resolved (404) and the request's own ids and shapes
 * checked (400) before `canAct` is asked, because `canAct` answers true for an
 * administrator before it looks at the Org Unit; db `mtu` is touched last.
 * Before all of that, when the catalogue is not configured, every route answers
 * 503 (site-context.js's requireCatalogueConfigured) — after the caller has
 * been authenticated and authorised, so an unauthenticated caller still gets
 * its 401 and a caller without the code its 403, and neither learns anything
 * about the catalogue's configuration.
 *
 * Query parameters and bodies are snake_case, exactly as the client card is
 * written against them, unlike the older routes' camelCase.
 */

const express = require('express');
const people = require('../people');
const catalogue = require('./catalogue');
const {
  requireCatalogueConfigured, requireScope, resolveSiteContext, parseDateOnly
} = require('./site-context');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// The catalogue Screen's own code (ADR-0061, issue #513). Seeded on exactly the
// four roles `ModuleRoles.kpi` offers that Screen to.
const mayReadCatalogue = people.requirePermission('INS_KPI_CATALOGUE_DISPLAY');

// The writes' code (ADR-0061, phase 2d): "add a KPI or change its Targets",
// exactly the two routes below. Seeded on ROLE_ADMIN alone by 1803400000000 and
// widened onto supervisor, engineer and manager by
// `1804100000000_kpi-catalogue-write-roles.js` — the three roles the Screen is
// offered to — so gating the writes takes them from no role the Screen admits.
const mayChangeCatalogue = people.requirePermission('INS_KPI_CATALOGUE_CHANGE');

// The catalogue as it reads on one day: every KPI, its three grains' Targets and
// that day's judgement. `date` defaults to the Site's own today.
router.get(
  '/catalogue',
  people.authenticate,
  people.requireActive,
  mayReadCatalogue,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const context = await resolveSiteContext(req.query.site_id);
      let reviewDate = context.siteToday;
      if (req.query.date !== undefined) {
        reviewDate = parseDateOnly(req.query.date);
        if (reviewDate === null) throw httpError(400, 'date must be a valid YYYY-MM-DD date');
      }

      await requireScope(req.account, context.rootOrgUnitId, { write: false });

      const kpis = await catalogue.listCatalogue({ reviewDate });
      res.json({ site_id: Number(context.site.id), review_date: reviewDate, kpis });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Adding a KPI. The body's values are checked by the catalogue (a KPI's own
// fields); a duplicate name is its 409. `INS_KPI_CATALOGUE_CHANGE` answers
// which door; `requireScope({ write: true })` still answers which Site.
router.post(
  '/catalogue',
  people.authenticate,
  people.requireActive,
  mayChangeCatalogue,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const context = await resolveSiteContext(body.site_id);

      await requireScope(req.account, context.rootOrgUnitId, { write: true });

      const kpiId = await catalogue.addKpi({
        kpi: body.kpi,
        title: body.title,
        unit: body.unit,
        direction: body.direction,
        decimals: body.decimals,
        valueMeasure: body.value_measure
      });
      res.status(201).json({ kpi_id: kpiId });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One KPI's Targets: in force today per grain, and the whole history. Reached
// from a catalogue row, so it asks the catalogue Screen's code too.
router.get(
  '/targets',
  people.authenticate,
  people.requireActive,
  mayReadCatalogue,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const context = await resolveSiteContext(req.query.site_id);
      const kpiId = parseId(req.query.kpi_id);
      if (kpiId === null) throw httpError(400, 'kpi_id must be a valid KPI id');

      await requireScope(req.account, context.rootOrgUnitId, { write: false });

      const targets = await catalogue.listTargets({ kpiId });
      if (!targets) throw notFound('KPI');
      res.json(targets);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Appending a Target (a change or a correction). `target: null` is "no target
// from that date on", so the field must be present but may be null. The same
// code, for the same reason, as the POST above.
router.post(
  '/targets',
  people.authenticate,
  people.requireActive,
  mayChangeCatalogue,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const context = await resolveSiteContext(body.site_id);
      const kpiId = parseId(body.kpi_id);
      if (kpiId === null) throw httpError(400, 'kpi_id must be a valid KPI id');
      if (typeof body.grain !== 'string') throw httpError(400, 'grain is required');
      const validFrom = parseDateOnly(body.valid_from);
      if (validFrom === null) throw httpError(400, 'valid_from must be a valid YYYY-MM-DD date');
      if (body.target === undefined) throw httpError(400, 'target is required (a number, or null for no target)');

      await requireScope(req.account, context.rootOrgUnitId, { write: true });

      const targetId = await catalogue.addTarget({
        kpiId,
        grain: body.grain,
        validFrom,
        target: body.target,
        note: body.note,
        appUser: req.account.displayName
      });
      res.status(201).json({ target_id: targetId });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
