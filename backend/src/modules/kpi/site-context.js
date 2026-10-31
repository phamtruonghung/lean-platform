/*
 * What every KPI catalogue route needs to know about the Site it was asked
 * about: the Site itself, its root Org Unit, and the Site's local today.
 *
 * `site` comes from People's entry point (`people.findSite`), which answers
 * null for an unknown Site so the route can 404 in this Module's own wording.
 *
 * The other two come from one query on the Platform's own pool. The catalogue
 * has no Org Unit of its own — it is shared by every Site — so authority is
 * asked about the Site's root Org Unit (the `org_units` row with no parent),
 * which is the entry point of ADR-0008's scoped caller: a Grant on the root, or
 * on anything above it, is what `people.canAct` is asked about. Reading
 * `org_units` here is an ordinary cross-Module read of People's own tables,
 * which ADR-0006 allows ("Modules are code seams, not data seams";
 * Maintenance's assets.js joins `org_units` directly). It is the only read of
 * People's tables in this Module; authority itself is still `people.canAct`.
 *
 * "Today" is never computed in JavaScript. `org_unit_today` is ADR-0048's
 * helper: the date at the Site, resolved in the database, so a server in
 * another time zone cannot disagree with the plant about which day it is. A Site
 * with no root Org Unit yet has nothing to hand `org_unit_today`, so the query
 * falls back to `now()` in the Site's own timezone. That is also the case in
 * which a non-administrator is refused: `canAct` answers false for a null Org
 * Unit while an administrator passes it before looking. That is how the Platform
 * already treats an Org Unit-less caller, and this Module does not add a branch
 * of its own for it.
 *
 * The date comes back as text (`YYYY-MM-DD`), cast in SQL: node-postgres turns a
 * `date` into a JavaScript Date at the server's local midnight, which is exactly
 * the JavaScript date handling the paragraph above refuses.
 *
 * The Site's last working day is what a Daily Review read with no date answers:
 * the most recent day before the Site's own today that no `calendar_exceptions`
 * row marks non-working (the same predicate the Shift instance generator uses).
 * Weekends are not skipped: this plant runs seven days, so a Saturday or Sunday
 * is a working day unless an exception row says otherwise.
 *
 * The small pieces every route of both routers shares live here too, so there
 * is one copy of each rather than six: the 503 guard for an unconfigured
 * catalogue, the scope check, the Site resolution and the strict date parser.
 */

const people = require('../people');
const { getPool } = require('../../platform/db');
const { isMtuConfigured } = require('../../platform/mtu-db');
const { httpError, notFound, parseId } = require('./errors');

const OUTSIDE_GRANTED_ORG_UNITS_CODE = 'OUTSIDE_GRANTED_ORG_UNITS';

async function findSiteContext(siteId) {
  const site = await people.findSite(siteId);
  if (!site) return null;

  const { rows: [row] } = await getPool().query(
    `SELECT r.id AS root_org_unit_id,
            COALESCE(org_unit_today(r.id), (now() AT TIME ZONE $2::text)::date)::text AS site_today
       FROM (SELECT 1) AS one
       LEFT JOIN LATERAL (
         SELECT ou.id
           FROM org_units ou
          WHERE ou.site_id = $1 AND ou.parent_id IS NULL
          ORDER BY ou.sort_order, ou.id
          LIMIT 1
       ) r ON TRUE`,
    [site.id, site.timezone]
  );

  return {
    site,
    rootOrgUnitId: row.root_org_unit_id,
    siteToday: row.site_today
  };
}

// The Site's last working day: the most recent date strictly before the Site's
// own today that is not marked non-working in calendar_exceptions, using the
// same predicate the shift generator uses (generate_shift_instances in
// migrations/1756000000000_baseline.js): 'holiday', 'shutdown' and
// 'non_working' make a day non-working; 'maintenance' does not. Weekends are not
// special — this plant runs seven days, so a Saturday or Sunday is a working day
// unless an exception row says otherwise. Resolved in SQL (ADR-0048), bounded at
// 365 days, and falling back to `site_today - 1` when the whole window is
// excepted: a Screen that cannot load is worse than a slightly wrong day.
async function findLastWorkingDay({ site, rootOrgUnitId, siteToday }) {
  const { rows: [row] } = await getPool().query(
    `SELECT COALESCE(
              (SELECT d::date::text
                 FROM generate_series(($1::date - 1), ($1::date - 365), interval '-1 day') AS d
                WHERE NOT EXISTS (
                        SELECT 1 FROM calendar_exceptions ce
                         WHERE ce.site_id = $2
                           AND (ce.org_unit_id IS NULL OR ce.org_unit_id = $3::bigint)
                           AND ce.exception_type IN ('holiday','shutdown','non_working')
                           AND ce.exception_date = d::date)
                ORDER BY d DESC
                LIMIT 1),
              ($1::date - 1)::text) AS last_working_day`,
    [siteToday, site.id, rootOrgUnitId]
  );
  return row.last_working_day;
}

// Mounted after `authenticate` and `requireActive` on every route, so an
// unauthenticated caller still gets its 401, and before anything else, so an
// unconfigured deployment reads as "this catalogue is not set up here" and not
// as a 500 from a Pool that cannot be created (platform/mtu-db.js's header).
function requireCatalogueConfigured(_req, res, next) {
  if (!isMtuConfigured()) {
    return res.status(503).json({
      error: 'kpi_catalogue_unavailable',
      message: 'The KPI catalogue is not set up on this deployment'
    });
  }
  return next();
}

// The exact shape production/handover-routes.js's requireScope refuses with.
// `write` is passed explicitly by every caller because canAct defaults it to
// FALSE, and a write that forgot it would be authorised by any read Grant.
async function requireScope(account, orgUnitId, { write }) {
  const allowed = await people.canAct({ account, orgUnitId, write });
  if (!allowed) {
    throw httpError(403, people.OUTSIDE_GRANTED_ORG_UNITS, OUTSIDE_GRANTED_ORG_UNITS_CODE);
  }
}

// The request's `site_id` resolved to its context, or a 400 (not an id) / 404
// (no such Site). Snake_case, as the client card is written against.
async function resolveSiteContext(value) {
  const siteId = parseId(value);
  if (siteId === null) throw httpError(400, 'site_id must be a valid Site id');
  const context = await findSiteContext(siteId);
  if (!context) throw notFound('Site');
  return context;
}

// A DATE with no time, strictly — copied from production/handover-routes.js's
// parseDateOnly. The regex alone would let 2026-13-40 through to Postgres,
// where `::date` raises a SQLSTATE with no `.status` and the caller would see
// a 500 for what is plainly a bad request.
function parseDateOnly(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

module.exports = {
  findSiteContext,
  findLastWorkingDay,
  requireCatalogueConfigured,
  requireScope,
  resolveSiteContext,
  parseDateOnly
};
