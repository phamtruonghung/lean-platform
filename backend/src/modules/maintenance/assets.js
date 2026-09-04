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
const { httpError, notFound, parseId } = require('./errors');

// Fixed lock key for pg_advisory_xact_lock, taken by setAssetParent AND
// setAssetActive before either does anything else (issue #61). The name
// reads as naming the invariant the lock protects, not either function on
// its own: no active Asset has a retired parent, and no retired Asset has
// active parts. That invariant spans both operations, so both take the same
// lock.
//
// setAssetParent's own half: two re-parents that are each individually
// acyclic against the snapshot they read can still commit into a cycle — A
// made a part of B, and B made a part of A, racing concurrently, neither
// seeing the other's uncommitted write. Locking against that with
// `FOR UPDATE` does not work here: the cycle check below is a recursive CTE
// (`assets` has no ltree path the way `org_units` does — see the baseline's
// own comment on why — so ancestry is walked, not indexed), and Postgres
// accepts `FOR UPDATE` against a recursive CTE reference syntactically but
// silently locks nothing.
//
// setAssetActive's own half (review fix for issue #61): its "still has
// active parts" check locks the rows that are ALREADY children with
// `FOR UPDATE`, but a concurrent setAssetParent can make a new row a child
// mid-check — that row held no lock, because it was not a child when the
// retire looked. Taking this same advisory lock first serialises the two
// functions against each other, closing that race.
//
// The lock is Platform-wide, not scoped to a Site: `assets.parent_id` carries
// no same-Site constraint, so a chain can in principle cross Sites, which
// rules out a narrower per-Site lock as unsound. That is an acceptable cost
// — re-parenting and retiring are rare human actions, not a hot path — and it
// is the same idiom service.js's own account-bootstrap lock uses (`hashtext`
// turns a fixed string into a fixed integer key without this file having to
// pick and remember an arbitrary number by hand).
const ASSET_REPARENT_LOCK_KEY = 'assets_reparent';

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
// about). Deactivated Assets are out by default (user story 11); issue #61's
// `includeRetired` is the deliberate way to include them — a caller has to
// ask for a retired machine by name, it is never mixed silently into the
// register everyone sees by default.
async function listAssetsAtSite(siteId, { includeRetired = false } = {}) {
  const activeClause = includeRetired ? '' : 'AND a.is_active';
  const { rows } = await getPool().query(
    `SELECT ${ASSET_COLUMNS}
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE ou.site_id = $1 ${activeClause}
      ORDER BY ou.name, a.code`,
    [siteId]
  );
  return rows.map(toAsset);
}

// The null-returning form (issue #61: asset-routes.js's requireAssetWriteScope
// resolves an id straight off req.params, the same shape findOrgUnit/findSite
// already solved this problem for in People). Total on purpose, mirroring
// those two exactly: a raw, possibly-malformed id reaching Postgres as a
// BIGINT parameter raises SQLSTATE 22P02, which carries no `.status`, so an
// unhandled 500 would come back where every People route answers a clean
// 404. parseId staying on this side of the call keeps the property honest —
// "not a real id" and "no such Asset" get the same answer.
async function findAsset(id) {
  if (parseId(id) === null) return null;
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

// Deactivation, not deletion — the same shape as People's own
// setOrgUnitActive, re-read through ASSET_COLUMNS/mapAssetWriteError.
//
// One rule People's precedent has no counterpart for, and it is a deliberate
// domain decision (issue #61), not an oversight: retiring an Asset that still
// has active children is refused with 409 rather than carried out. A machine
// is not scrapped while its parts are still recorded as fitted to it. The two
// alternatives were both worse — cascading the retirement to every child
// would retire a gearbox that is in fact only being removed and refitted
// elsewhere, silently destroying a record the plant still needs; leaving the
// children active underneath a retired parent produces a register where a
// component is visible while the machine it belongs to is not. Refusing
// makes the operator deal with the parts explicitly, either retiring them
// too or re-parenting them first.
//
// Reinstating (isActive: true) is refused too, but for the opposite reason:
// bringing a machine back into service while ITS OWN parent is retired would
// produce the identical bad state — an active Asset visible under a machine
// this register says is gone. Retire-with-active-children, attach-to-a-
// retired-parent (setAssetParent, below) and this reinstate check together
// make the invariant hold in both directions: an active Asset never has a
// retired parent, and a retired Asset never has active parts.
//
// The child check (and the parent check on reinstate) run inside the same
// transaction as the update, with `FOR UPDATE` on the rows they read, so a
// concurrent write against one of those specific rows cannot slip in behind
// this check and invalidate it before COMMIT. The ASSET_REPARENT_LOCK_KEY
// advisory lock is taken first, before either check, for a race `FOR UPDATE`
// alone cannot close: a concurrent setAssetParent can make a row a child of
// this Asset mid-check, and that row held no lock because it was not yet a
// child when the SELECT ran. See ASSET_REPARENT_LOCK_KEY's own comment.
async function setAssetActive(id, isActive, accountId) {
  const asset = await findAsset(id);
  if (!asset) throw notFound('Asset');

  return withActor(accountId, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [ASSET_REPARENT_LOCK_KEY]);

    if (!isActive) {
      const { rows: children } = await client.query(
        `SELECT id FROM assets WHERE parent_id = $1 AND is_active FOR UPDATE`,
        [asset.id]
      );
      if (children.length > 0) {
        throw httpError(409, 'this Asset still has parts fitted to it');
      }
    } else if (asset.parentId !== null) {
      const { rows: [parentRow] } = await client.query(
        `SELECT is_active FROM assets WHERE id = $1 FOR UPDATE`,
        [asset.parentId]
      );
      if (parentRow && !parentRow.is_active) {
        throw httpError(409, "this Asset's parent has been retired");
      }
    }

    try {
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE assets SET is_active = $1 WHERE id = $2 RETURNING *
         )
         SELECT ${ASSET_COLUMNS}
           FROM updated a
           JOIN org_units ou ON ou.id = a.org_unit_id`,
        [isActive, asset.id]
      );
      return toAsset(row);
    } catch (error) {
      throw mapAssetWriteError(error);
    }
  });
}

// Nests an Asset under another (parentId a real Asset id) or detaches it back
// to top-level (parentId null) — issue #61. Refusals are checked in a fixed
// order, existence before scope before shape, each its own clean 4xx:
//
//   1. The Asset itself does not exist -> 404.
//   2. parentId is provided but malformed -> 400.
//   3. The proposed parent does not exist -> 404, worded distinctly from #1.
//   4. The proposed parent has been retired -> 409: see the invariant this
//      shares with setAssetActive's own comment — an active Asset never has
//      a retired parent, and a retired Asset never has active parts.
//   5. The proposed parent IS the Asset -> 400 (self-parent; the baseline's
//      own `assets_parent_not_self` CHECK would catch this too, but only as
//      a raw constraint violation, not this message).
//   6. The proposed parent is a DESCENDANT of the Asset -> 400: nesting it
//      there would create a cycle.
//
// #6 is detected by walking ANCESTORS of the proposed parent, not
// descendants of this Asset: the proposed parent is a fixed single row, so
// walking upward from it is bounded by the tree's depth (a handful of
// levels, per the baseline's own comment on why Assets get no ltree column);
// walking downward from this Asset to enumerate every descendant is not
// bounded the same way and answers a bigger question than the one being
// asked. If the Asset's own id shows up among the proposed parent's
// ancestors, the proposed parent is one of the Asset's own parts. The walk
// carries an explicit `depth` and stops at 64 — far beyond the "handful of
// levels" this tree is expected to have — so a cycle reaching this function
// by any path OTHER than this one (a manual fix, a restored dump, a future
// writer that forgets the lock) cannot spin unboundedly while this function
// is holding the Platform-wide advisory lock below. A depth counter is used
// rather than PG14's `CYCLE` clause so this does not depend on server
// version.
//
// See ASSET_REPARENT_LOCK_KEY's own comment for why an advisory lock is
// taken first, before any of the above runs.
async function setAssetParent(id, parentId, accountId) {
  const asset = await findAsset(id);
  if (!asset) throw notFound('Asset');

  let parentIdValue = null;
  if (parentId !== null) {
    parentIdValue = parseId(parentId);
    if (parentIdValue === null) throw httpError(400, 'parentId must be a valid Asset id');
  }

  return withActor(accountId, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [ASSET_REPARENT_LOCK_KEY]);

    let newLevel = asset.assetLevel;

    if (parentIdValue !== null) {
      const { rows: [parentRow] } = await client.query(
        'SELECT id, is_active FROM assets WHERE id = $1',
        [parentIdValue]
      );
      if (!parentRow) throw notFound('Parent Asset');
      if (!parentRow.is_active) throw httpError(409, 'that Asset has been retired');

      if (String(parentIdValue) === String(asset.id)) {
        throw httpError(400, 'an Asset cannot be part of itself');
      }

      const { rows: ancestorRows } = await client.query(
        `WITH RECURSIVE ancestors AS (
           SELECT id, parent_id, 0 AS depth FROM assets WHERE id = $1
           UNION ALL
           SELECT a.id, a.parent_id, anc.depth + 1
             FROM assets a
             JOIN ancestors anc ON a.id = anc.parent_id
            WHERE anc.depth < 64
         )
         SELECT id FROM ancestors WHERE id = $2`,
        [parentIdValue, asset.id]
      );
      if (ancestorRows.length > 0) {
        throw httpError(400, 'an Asset cannot be part of one of its own parts');
      }

      // Fix F (issue #61 review): a nested Asset must not still report
      // itself as a top-level 'machine'. Only the 'machine' default is
      // promoted, and only to 'component' — 'assembly' is a mid-level
      // designation someone recorded on purpose, and this route has no way
      // to derive depth from a parent link, so an existing 'assembly' or
      // 'component' is left exactly as it was.
      if (asset.assetLevel === 'machine') {
        newLevel = 'component';
      }
    } else {
      // Detaching back to top-level: always 'machine', regardless of what it
      // was recorded as while nested.
      newLevel = 'machine';
    }

    try {
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE assets SET parent_id = $1, asset_level = $2 WHERE id = $3 RETURNING *
         )
         SELECT ${ASSET_COLUMNS}
           FROM updated a
           JOIN org_units ou ON ou.id = a.org_unit_id`,
        [parentIdValue, newLevel, asset.id]
      );
      return toAsset(row);
    } catch (error) {
      throw mapAssetWriteError(error);
    }
  });
}

module.exports = {
  ASSET_TYPES,
  CRITICALITIES,
  listAssetsAtSite,
  findAsset,
  createAsset,
  setAssetActive,
  setAssetParent
};
