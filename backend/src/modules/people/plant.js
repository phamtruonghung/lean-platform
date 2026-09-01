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

// Mirrors the CHECK constraint on org_units.unit_type in the baseline.
// Validated here too so a bad value comes back as a 400 with a clear
// message instead of a raw constraint-violation error.
const UNIT_TYPES = ['area', 'department', 'line', 'cell', 'work_center'];

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function notFound(what) {
  return httpError(404, `${what} not found`);
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Route params, query strings and JSON bodies all carry an id as *some*
// primitive, but ids are BIGINT, which `db.js` deliberately leaves
// unparsed (see that file's own header) — `pg` hands one back as a decimal
// string, not a `number`, since a `number` cannot hold every int64. Coercing
// through `Number` here would make an id compared against a row's own id
// (e.g. "is this Org Unit's parent at the same Site") silently false —
// `52 !== "52"` — so this validates and returns a string, never a number,
// which is also what keeps a route param and a column value the same type
// wherever this module compares the two.
function parseId(value) {
  if (value === undefined || value === null) return null;
  const str = String(value).trim();
  return /^[1-9][0-9]*$/.test(str) ? str : null;
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

async function getSite(id) {
  if (id === null) throw notFound('Site');
  const { rows } = await getPool().query(
    `SELECT ${SITE_COLUMNS} FROM sites WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Site');
  return toSite(rows[0]);
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

async function getOrgUnit(id) {
  if (id === null) throw notFound('Org Unit');
  const { rows } = await getPool().query(
    `SELECT ${ORG_UNIT_COLUMNS} FROM org_units WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Org Unit');
  return toOrgUnit(rows[0]);
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
  parseId,
  createSite,
  listSites,
  getSite,
  createOrgUnit,
  listOrgUnits,
  getOrgUnit,
  getOrgUnitSubtree,
  setOrgUnitActive
};
