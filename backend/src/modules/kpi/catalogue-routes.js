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
 * Order, the one AGENTS.md section 6 fixes: existence, then scope, then the
 * catalogue. The Site is resolved (404) and the request's own ids and shapes
 * checked (400) before `canAct` is asked, because `canAct` answers true for an
 * administrator before it looks at the Org Unit; db `mtu` is touched last.
 * Before all of that, when the catalogue is not configured, every route answers
 * 503 (site-context.js's requireCatalogueConfigured) — after authentication, so
 * an unauthenticated caller still gets its 401.
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

// The catalogue as it reads on one day: every KPI, its three grains' Targets and
// that day's judgement. `date` defaults to the Site's own today.
router.get(
  '/catalogue',
  people.authenticate,
  people.requireActive,
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
// fields); a duplicate name is its 409.
router.post(
  '/catalogue',
  people.authenticate,
  people.requireActive,
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

// One KPI's Targets: in force today per grain, and the whole history.
router.get(
  '/targets',
  people.authenticate,
  people.requireActive,
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
// from that date on", so the field must be present but may be null.
router.post(
  '/targets',
  people.authenticate,
  people.requireActive,
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
