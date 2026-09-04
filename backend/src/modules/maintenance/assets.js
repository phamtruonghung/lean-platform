/*
 * The Asset register (issue #56). `assets` is a baseline table; this file is
 * the HTTP-facing service over it.
 *
 * It joins `org_units` — People's table — to answer "which Org Unit does this
 * machine sit at" and "which Site is it in". That is deliberate and allowed:
 * ADR-0006 makes a Module a code seam, not a data seam, and says in as many
 * words that cross-Module reads are ordinary joins. What does NOT happen here
 * is a lookup or a write of a People record: resolving the Org Unit a caller
 * named, and asking whether they may act there, both happen one layer up in
 * asset-routes.js through modules/people's entry point.
 *
 * Like plant.js in People, this file is unaware of who is calling. An
 * orgUnitId reaching createAsset is one the caller was already entitled to
 * place an Asset at.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError } = require('./errors');

// Mirror the CHECK constraints on assets.asset_type / assets.criticality in
// the baseline, so a bad value is a 400 with a clear message rather than a
// raw constraint violation.
const ASSET_TYPES = ['machine', 'cell', 'tool', 'utility', 'vehicle', 'other'];
const CRITICALITIES = ['low', 'medium', 'high', 'critical'];

// org_unit_code/org_unit_name come from the join, so every Asset this Module
// hands back carries where it sits (issue #56, user story 2) — including the
// one just created, which is why createAsset inserts and re-reads in one
// statement rather than using a bare RETURNING.
const ASSET_COLUMNS = `
  a.id, a.org_unit_id, a.code, a.name, a.asset_type, a.criticality,
  a.is_constraint, a.is_active, a.parent_id, a.asset_level,
  a.created_at, a.updated_at,
  ou.code AS org_unit_code, ou.name AS org_unit_name, ou.site_id
`;

function toAsset(row) {
  return {
    id: row.id,
    orgUnitId: row.org_unit_id,
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    siteId: row.site_id,
    code: row.code,
    name: row.name,
    assetType: row.asset_type,
    criticality: row.criticality,
    isConstraint: row.is_constraint,
    isActive: row.is_active,
    parentId: row.parent_id,
    assetLevel: row.asset_level,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// `assets_code_unique` is UNIQUE (code) — GLOBAL, not per-Site, unlike
// org_units' own (site_id, code). The message says so rather than implying a
// Site-local clash the caller could resolve by moving the machine.
function mapAssetWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'an Asset with this code already exists');
  }
  // A safety net, mostly unreachable: assetType/criticality are validated in
  // application code above before a query is ever sent. `error.message` is
  // NOT echoed here — src/index.js's terminal handler states the policy: a
  // database error string names tables and columns, and this is Postgres's
  // own check-constraint text, not a message this Module wrote.
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Asset');
  }
  if (error.code === 'P0001') {
    return httpError(400, error.message);
  }
  return error;
}

// Site-wide, never filtered by the caller's Grants (#55, extending ADR-0009's
// reasoning: scope decides where an Account may act, not what it may know
// about). Deactivated Assets are out by default (user story 11); the
// deliberate way to include them is issue #61's.
async function listAssetsAtSite(siteId) {
  const { rows } = await getPool().query(
    `SELECT ${ASSET_COLUMNS}
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE ou.site_id = $1 AND a.is_active
      ORDER BY ou.name, a.code`,
    [siteId]
  );
  return rows.map(toAsset);
}

async function findAsset(id) {
  const { rows } = await getPool().query(
    `SELECT ${ASSET_COLUMNS} FROM assets a JOIN org_units ou ON ou.id = a.org_unit_id WHERE a.id = $1`,
    [id]
  );
  return rows[0] ? toAsset(rows[0]) : null;
}

async function createAsset({ orgUnitId, code, name, assetType, criticality }, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  if (!ASSET_TYPES.includes(assetType)) {
    throw httpError(400, `assetType must be one of: ${ASSET_TYPES.join(', ')}`);
  }
  if (!CRITICALITIES.includes(criticality)) {
    throw httpError(400, `criticality must be one of: ${CRITICALITIES.join(', ')}`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING *
         )
         SELECT ${ASSET_COLUMNS}
           FROM inserted a
           JOIN org_units ou ON ou.id = a.org_unit_id`,
        [orgUnitId, code.trim(), name.trim(), assetType, criticality]
      );
      return toAsset(row);
    });
  } catch (error) {
    throw mapAssetWriteError(error);
  }
}

module.exports = { ASSET_TYPES, CRITICALITIES, listAssetsAtSite, findAsset, createAsset };
