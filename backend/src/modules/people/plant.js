/*
 * Sites and the Org Unit tree (issue #7, CONTEXT.md's Site/Org Unit
 * definitions). `sites` and `org_units` are baseline tables — see
 * migrations/1756000000000_baseline.js's own header on the physical
 * hierarchy — this file is the HTTP-facing service over them: an
 * administrator describing a plant, and anyone browsing it afterwards.
 *
 * The tree itself is not this file's business logic: `org_units.path` (an
 * LTREE) and the compute/move-subtree triggers in the baseline already do
 * that work. This file only ever reads or writes `path` through the column
 * itself — `path <@ $1::ltree` is what makes "everything beneath this unit"
 * a single indexed query (GiST, see `org_units_path_idx`) instead of a
 * recursive walk in application code.
 *
 * A Site's `timezone` is what every future shift/production-day
 * calculation must resolve time against instead of the server clock (the
 * issue's own time-zone criterion) — shifts and production days are not
 * built yet (later Modules), so this file's job is only to carry the
 * timezone through the API untouched and round-trippable; nothing here
 * resolves a shift or a day.
 *
 * Role and Org Unit scope enforcement (issue #8) lives one layer up, in
 * plant-routes.js, via authorization.js's requireAdmin and
 * requireOrgUnitScope — this file stays unaware of who is calling or what
 * they are scoped to, the same way it stays unaware of HTTP. Every function
 * here still assumes its caller already settled that question; a `siteId`
 * or `orgUnitId` reaching this file is one the caller was already entitled
 * to name.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { escapeLikePattern } = require('./sql');

// Mirrors the CHECK constraint on org_units.unit_type in the baseline.
// Validated here too so a bad value comes back as a 400 with a clear
// message instead of a raw constraint-violation error.
const UNIT_TYPES = ['area', 'department', 'line', 'cell', 'work_center'];

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// ---------------------------------------------------------------------------
// Sites
// ---------------------------------------------------------------------------

const SITE_COLUMNS = 'id, code, name, timezone, country_code, is_active, created_at, updated_at';

function toSite(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    timezone: row.timezone,
    countryCode: row.country_code,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A write against `sites` can fail for two reasons this file turns into a
// clean 4xx rather than a 500: the `code` UNIQUE constraint, and the
// baseline's own `sites_validate_timezone` trigger (RAISE EXCEPTION, which
// Postgres gives the default SQLSTATE P0001) rejecting a name that is not a
// real IANA zone. Anything else is a genuine failure and is rethrown as-is.
function mapSiteWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'a Site with this code already exists');
  }
  if (error.code === 'P0001') {
    return httpError(400, error.message);
  }
  return error;
}

async function createSite({ code, name, timezone, countryCode }, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  requireNonEmptyString('timezone', timezone);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO sites (code, name, timezone, country_code)
         VALUES ($1, $2, $3, $4)
         RETURNING ${SITE_COLUMNS}`,
        [code.trim(), name.trim(), timezone.trim(), countryCode ?? null]
      );
      return toSite(row);
    });
  } catch (error) {
    throw mapSiteWriteError(error);
  }
}

async function listSites() {
  const { rows } = await getPool().query(
    `SELECT ${SITE_COLUMNS} FROM sites ORDER BY code`
  );
  return rows.map(toSite);
}

// The null-returning form, mirroring findOrgUnit below exactly (issue #56):
// what another Module calls through index.js. Total on purpose — anything
// that is not a real id answers null rather than reaching the database,
// because parseId deliberately stays on this side of the boundary
// (ADR-0006 clause 3).
async function findSite(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SITE_COLUMNS} FROM sites WHERE id = $1`,
    [id]
  );
  return rows[0] ? toSite(rows[0]) : null;
}

// This Module's own form: the 404 every route in People already relies on.
async function getSite(id) {
  const site = await findSite(id);
  if (!site) throw notFound('Site');
  return site;
}

// The timezone list a Site's `timezone` is chosen from (issue #123,
// ADR-0023's "a value with a known set is chosen, never typed"). Postgres's
// own pg_timezone_names is the authority `sites_validate_timezone` (the
// baseline migration) already validates against, so this mirrors that query
// rather than shipping a second, driftable list — a bundled or curated set
// could offer a name the trigger then refuses.
//
// posix/ and right/ are excluded: they are duplicates of the canonical zones
// (roughly tripling the list) that the trigger would still accept but that
// nothing should ever offer a person picking a Site's timezone. Everything
// else is kept, INCLUDING legacy aliases (US/Eastern) and the Etc/* zones —
// a Site created earlier may already store one of these, and the list must
// be able to round-trip whatever is already on a row, not just what a new
// Site should be steered toward.
//
// Sorted and fetched whole, no paging or search: ~1,200 rows after
// filtering, changing only when the Postgres version itself changes, so a
// server-side search would add complexity for a list this small and this
// stable — the client filters in memory instead (ADR-0023).
async function listTimezones() {
  const { rows } = await getPool().query(
    `SELECT name FROM pg_timezone_names
      WHERE name NOT LIKE 'posix/%' AND name NOT LIKE 'right/%'
      ORDER BY name`
  );
  return rows.map((row) => row.name);
}

// ---------------------------------------------------------------------------
// Org Units
// ---------------------------------------------------------------------------

const ORG_UNIT_COLUMNS =
  'id, site_id, parent_id, code, name, unit_type, path, sort_order, is_active, created_at, updated_at';

function toOrgUnit(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    parentId: row.parent_id,
    code: row.code,
    name: row.name,
    unitType: row.unit_type,
    path: row.path,
    sortOrder: row.sort_order,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// As mapSiteWriteError above, for org_units: the `(site_id, code)` UNIQUE
// constraint, and the compute-path trigger's own guards (a unit made its
// own parent, or moved under its own descendant — unreachable from create,
// since a brand new row has no descendants yet, but shared with a future
// move/update path).
function mapOrgUnitWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'an Org Unit with this code already exists at this Site');
  }
  if (error.code === 'P0001') {
    return httpError(400, error.message);
  }
  return error;
}

// The null-returning form (issue #59): what another Module calls through
// index.js. A cross-Module lookup hands back a value, never an
// HTTP-status-carrying throw into the caller's own error funnel — ADR-0006.
//
// Total on purpose: anything that is not a real id answers null rather than
// reaching the database, because ADR-0006's third clause deliberately keeps
// `parseId` on this side of the boundary. Without this, a caller passing a
// raw body value straight through — exactly what issue #56 does with
// `orgUnitId` — would hand Postgres a non-numeric BIGINT, and 22P02 carries
// no `.status`, so the consumer's error funnel would answer 500 where every
// People route answers 400. A question asked about a nonsense id has the
// same honest answer as one asked about an id nobody has: no such row.
async function findOrgUnit(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS} FROM org_units WHERE id = $1`,
    [id]
  );
  return rows[0] ? toOrgUnit(rows[0]) : null;
}

// This Module's own form: the 404 every route in People already relies on.
async function getOrgUnit(id) {
  const orgUnit = await findOrgUnit(id);
  if (!orgUnit) throw notFound('Org Unit');
  return orgUnit;
}

// The direct children of a Site's root (parentId omitted) or of a given Org
// Unit (parentId given) — one level at a time, which is what "browsed from
// a Site down to a work centre" means: a client walks down by calling this
// again with each child's id, rather than being handed the whole tree it
// may not need.
async function listOrgUnits(siteId, parentId) {
  await getSite(siteId); // 404s if the Site itself does not exist.

  // `parentId` is either `undefined` (root level) or an already-validated
  // integer — plant-routes.js is the one place that turns a query string
  // into one or the other, since only it knows whether the string was
  // absent or present-but-invalid.
  const params = [siteId];
  let parentClause = 'parent_id IS NULL';
  if (parentId !== undefined) {
    params.push(parentId);
    parentClause = 'parent_id = $2';
  }

  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS} FROM org_units
      WHERE site_id = $1 AND ${parentClause}
      ORDER BY sort_order, name`,
    params
  );
  return rows.map(toOrgUnit);
}

// The rows behind a set of Org Unit ids the caller already chose —
// plant-routes.js is the one caller today, composing "which ids"
// (authorization.grantedEntryPointIds, issue #24 — that module's own
// decision) with "what those ids look like" (this module's column mapping
// and ordering), so a scoped caller's entry points into a Site's tree still
// cost one indexed lookup there and one here, never a row-at-a-time N+1.
// Like listOrgUnits, this file stays unaware of *why* these particular ids
// were asked for or who is asking — an id reaching here is one the caller
// already decided to show. An empty `ids` never reaches Postgres at all:
// there is no caller this file needs to round-trip a query for just to
// learn "nothing".
async function listOrgUnitsByIds(ids) {
  if (ids.length === 0) return [];

  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS} FROM org_units
      WHERE id = ANY($1::bigint[])
      ORDER BY sort_order, name`,
    [ids]
  );
  return rows.map(toOrgUnit);
}

// Everything beneath a given Org Unit, itself included, as one request —
// the issue's own "single request" acceptance criterion. `path <@ $1::ltree`
// is a GiST index lookup (org_units_path_idx), not a recursive query.
// `depth` is relative to the unit asked for (0 for itself), which is what a
// client needs to indent a tree view without recomputing nlevel() itself.
async function getOrgUnitSubtree(id) {
  const target = await getOrgUnit(id);

  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS}, nlevel(path) - nlevel($1::ltree) AS depth
       FROM org_units
      WHERE path <@ $1::ltree
      ORDER BY path`,
    [target.path]
  );
  return rows.map((row) => ({ ...toOrgUnit(row), depth: row.depth }));
}

// `withinOrgUnitIds` is a tree filter, not an authorization concept — the
// same "everything at or beneath this Org Unit" question getOrgUnitSubtree
// asks, widened to a set. Absent (undefined) means no containment filter at
// all; an array restricts results to rows at or beneath one of those units.
// plant-routes.js is the one caller and decides which, per ADR-0008's seam.
const ORG_UNIT_SEARCH_LIMIT = 50;

// Issue #35: search a Site's Org Units by partial, case-insensitive name, in
// one call regardless of depth — path <@ containment (see this file's own
// header) is what makes "everything at or beneath a granted Org Unit" a
// single indexed EXISTS rather than a per-level walk. The scope filter lives
// INSIDE this query, combined with the LIMIT, not applied afterward in JS:
// a post-filter over an unscoped LIMIT'd result would drop a non-
// administrator's real matches whenever they sit past the first
// ORG_UNIT_SEARCH_LIMIT *global* matches. This is grant containment
// (path <@ against every one of the caller's granted Org Units, unioned via
// EXISTS), deliberately not authorization.grantedEntryPointIds's entry-point
// dedup — search asks "is this row inside my reach", not "where does my
// reach begin", so no dedup is wanted or correct here.
async function searchOrgUnits(siteId, { search, withinOrgUnitIds } = {}) {
  await getSite(siteId); // 404s if the Site itself does not exist.

  const term = typeof search === 'string' ? search.trim() : '';
  if (term === '') return { orgUnits: [], truncated: false };
  // A caller restricted to nothing reaches nothing: no round trip needed,
  // the same short-circuit listOrgUnitsByIds makes for an empty id list.
  if (withinOrgUnitIds !== undefined && withinOrgUnitIds.length === 0) {
    return { orgUnits: [], truncated: false };
  }

  const params = [siteId, `%${escapeLikePattern(term)}%`];
  // The same containment predicate answers two questions — which rows match
  // (ou.path <@ a grant) and which ancestors of a match this caller may be
  // shown (a.path <@ a grant, the lateral below, issue #145) — so the grant
  // array is pushed once and both clauses name it by the same positional
  // parameter. A breadcrumb must not become a read the search itself would
  // refuse: a match sits beneath a granted unit, but its ancestry reaches
  // above that grant (ADR-0008), so the ancestors are filtered too.
  let scopeClause = '';
  let ancestorScopeClause = '';
  if (withinOrgUnitIds !== undefined) {
    params.push(withinOrgUnitIds);
    const grantParam = `$${params.length}`;
    scopeClause = `
       AND EXISTS (
             SELECT 1 FROM org_units granted
              WHERE granted.id = ANY(${grantParam}::bigint[])
                AND ou.path <@ granted.path
           )`;
    ancestorScopeClause = `
         AND EXISTS (
               SELECT 1 FROM org_units granted
                WHERE granted.id = ANY(${grantParam}::bigint[])
                  AND a.path <@ granted.path
             )`;
  }
  params.push(ORG_UNIT_SEARCH_LIMIT + 1); // one extra row: the truncation probe.

  // `ancestors` rides along on each match (issue #145, ADR-0024): the hit's
  // own strict ancestors, root-first as `[{id, name}]`, resolved in the same
  // query through a `path <@` GiST lookup per matched row. IDs are cast to
  // text so the wire keeps the string shape every other Org Unit id has
  // (`toOrgUnit`), and an ancestor-free row answers `[]`, never a null.
  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS},
            COALESCE(anc.ancestors, '[]'::json) AS ancestors
       FROM org_units ou
       LEFT JOIN LATERAL (
              SELECT json_agg(
                       json_build_object('id', a.id::text, 'name', a.name)
                       ORDER BY nlevel(a.path)
                     ) AS ancestors
                FROM org_units a
               WHERE ou.path <@ a.path
                 AND a.id <> ou.id
                 ${ancestorScopeClause}
            ) anc ON true
      WHERE ou.site_id = $1
        AND ou.name ILIKE $2 ESCAPE '\\'
        ${scopeClause}
      ORDER BY ou.name, ou.id
      LIMIT $${params.length}`,
    params
  );

  const truncated = rows.length > ORG_UNIT_SEARCH_LIMIT;
  return {
    orgUnits: rows.slice(0, ORG_UNIT_SEARCH_LIMIT).map((row) => ({
      ...toOrgUnit(row),
      ancestors: row.ancestors ?? []
    })),
    truncated
  };
}

async function createOrgUnit(siteId, { parentId, code, name, unitType, sortOrder }, accountId) {
  await getSite(siteId); // 404s if the Site itself does not exist.

  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  if (!UNIT_TYPES.includes(unitType)) {
    throw httpError(400, `unitType must be one of: ${UNIT_TYPES.join(', ')}`);
  }

  let parentIdValue = null;
  if (parentId !== undefined && parentId !== null) {
    const parsedParentId = parseId(parentId);
    if (parsedParentId === null) throw httpError(400, 'parentId must be a valid Org Unit id');
    const parent = await getOrgUnit(parsedParentId); // 404s if it does not exist at all.
    if (parent.siteId !== siteId) {
      throw httpError(400, 'parentId must be an Org Unit at the same Site');
    }
    parentIdValue = parsedParentId;
  }

  const sortOrderValue = Number.isInteger(sortOrder) ? sortOrder : 0;

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO org_units (site_id, parent_id, code, name, unit_type, sort_order)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING ${ORG_UNIT_COLUMNS}`,
        [siteId, parentIdValue, code.trim(), name.trim(), unitType, sortOrderValue]
      );
      return toOrgUnit(row);
    });
  } catch (error) {
    throw mapOrgUnitWriteError(error);
  }
}

// Deactivation, not deletion — the issue's own criterion. Nothing here
// deletes a row or touches what references org_unit_id elsewhere; is_active
// is a flag those other tables' own reads can choose to filter on or not,
// which is what keeps a record naming a now-deactivated Org Unit readable.
async function setOrgUnitActive(id, isActive, accountId) {
  await getOrgUnit(id); // 404s if it does not exist.

  return withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `UPDATE org_units SET is_active = $1 WHERE id = $2 RETURNING ${ORG_UNIT_COLUMNS}`,
      [isActive, id]
    );
    return toOrgUnit(row);
  });
}

module.exports = {
  createSite,
  listSites,
  getSite,
  findSite,
  listTimezones,
  createOrgUnit,
  listOrgUnits,
  listOrgUnitsByIds,
  getOrgUnit,
  findOrgUnit,
  getOrgUnitSubtree,
  searchOrgUnits,
  setOrgUnitActive,
  // Exported for org-unit-import.js (issue #12) only, which inserts rows
  // directly inside its own single transaction rather than calling
  // createOrgUnit per row — see that file's own header for why. Everything
  // else in this Module still reaches Org Units through the functions above.
  UNIT_TYPES,
  ORG_UNIT_COLUMNS,
  toOrgUnit,
  mapOrgUnitWriteError
};
