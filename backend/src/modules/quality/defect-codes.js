/*
 * The Defect code catalogue (issue #203) — the tree of things that can be
 * wrong with a Product or a Process, and the other half of the Quality
 * Module's first slice. Every later Quality record names one of these:
 * `quality_issues.defect_code_id` is a NOT NULL foreign key into this table,
 * and its `default_severity` is what seeds a Non-conformance's severity before
 * anyone judges the individual event.
 *
 * `defect_codes` is a baseline table, seeded with the plant's own starting
 * tree by the baseline migration, and this file adds nothing to it. It is a
 * TREE (`parent_id` references this same table) but deliberately not an ltree
 * one — the baseline gives it no `path` column — so the hierarchy is read by
 * the client from each row's `parentId`, and this file's one piece of tree
 * logic is the cycle refusal below. Like `products`, it carries no `site_id`:
 * one catalogue shared by every Site (ADR-0005).
 *
 * Mirrors job-roles.js/products.js: no HTTP, no caller awareness, no other
 * Module. defect-code-routes.js owns authenticate/requireActive/requireAdmin
 * and the 404s that precede them.
 *
 * Deactivation, never deletion, and more strongly here than anywhere: a
 * deactivated Defect code is what an old Non-conformance still points at.
 * Deactivating a parent deliberately does NOT cascade to its children —
 * deactivation is not a statement about the tree's shape, and a customer-
 * facing category that stops being used while one of its codes stays in use
 * is a real case the plant has.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// The two value sets the baseline's own CHECK constraints enforce
// (`defect_codes_defect_category_check`, `defect_codes_default_severity_check`).
// Repeated here so a caller gets a sentence naming the field rather than a raw
// constraint violation: the sets are the database's, and a change to one must
// change both, which is why they are named as mirroring the CHECK rather than
// presented as this file's own decision.
const DEFECT_CATEGORIES = ['product', 'process', 'material', 'documentation', 'packaging'];
const SEVERITIES = ['minor', 'major', 'critical'];

function requireMembership(field, value, allowed) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw httpError(400, `${field} must be one of ${allowed.join(', ')}`);
  }
}

const DEFECT_CODE_COLUMNS = `
  id, parent_id, code, name, defect_category, default_severity, is_active, created_at, updated_at`;

function toDefectCode(row) {
  return {
    id: row.id,
    parentId: row.parent_id,
    code: row.code,
    name: row.name,
    category: row.defect_category,
    defaultSeverity: row.default_severity,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A write can fail for two reasons worth a clean 4xx. The `code` UNIQUE
// constraint is `defect_codes_code_key` (the same inline-UNIQUE naming
// job-roles.js documents); `parent_id`'s foreign key is resolved explicitly
// before any write, so a 23503 reaching here means a parent removed between
// that read and this write — mapped to the same 404 the explicit lookup
// raises rather than leaking a database message. Anything else is a genuine
// failure and is rethrown as-is.
function mapDefectCodeWriteError(error) {
  if (error.code === '23505' && error.constraint === 'defect_codes_code_key') {
    return httpError(409, 'a Defect code with this code already exists');
  }
  if (error.code === '23503') {
    return notFound('Defect code');
  }
  if (error.code === '23514') {
    return httpError(400, 'That Defect code was refused by the database: a field is outside the set of values it accepts');
  }
  return error;
}

// Active codes by default, ordered by code; `includeInactive` widens to the
// whole tree, deactivated rows included, which is what the catalogue's own
// Screen asks for so that a retired code can be reached and reactivated.
//
// A FLAT list rather than a nested one: each row names its own `parentId`, and
// the client builds the tree from that. Nesting here would have to invent an
// answer for a row whose parent was filtered out (a deactivated parent with an
// active child, which this catalogue deliberately allows), and the shape a
// caller can render is the same either way. Any active Account may read it —
// a Defect code is reference data, and a later slice needs it as a choice
// (ADR-0023) for whoever is recording what went wrong.
async function listDefectCodes({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT ${DEFECT_CODE_COLUMNS} FROM defect_codes ${whereClause} ORDER BY code`
  );
  return rows.map(toDefectCode);
}

// Mirrors plant.getOrgUnit: a null id and "no such row" are both a 404.
async function findDefectCode(id) {
  if (id === null) throw notFound('Defect code');
  const { rows } = await getPool().query(
    `SELECT ${DEFECT_CODE_COLUMNS} FROM defect_codes WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Defect code');
  return toDefectCode(rows[0]);
}

// Resolves a proposed parent, and refuses a link that would make the tree
// cyclic — issue #203's own acceptance criterion. The walk goes UP from the
// proposed parent, exactly as assets.js's setAssetParent does and for the same
// reason: the parent is one fixed row, so walking its ancestors is bounded by
// the tree's depth, where walking down from the code being edited to enumerate
// its descendants answers a bigger question than the one asked. If the edited
// code's own id appears among the proposed parent's ancestors, the proposed
// parent is the code itself or one of its own children.
//
// Two refusals, in this order: self-parent first (a clean sentence rather than
// the baseline's own `defect_codes.parent_id` self-reference being explained
// as a cycle), then the descendant case. 400 rather than 409:
// asset-routes.js/assets.js answer the identical question the same way
// ('an Asset cannot be part of itself'), a cycle being a malformed request
// rather than a clash with something that already exists.
//
// The depth counter stops the walk at 64 — far beyond the handful of levels
// this tree is expected to have — so a cycle that already exists by some other
// path (a manual fix, a restored dump) cannot spin here. PG14's `CYCLE` clause
// would be the other way to bound it; a counter is used so this does not
// depend on server version, the same choice assets.js records.
async function resolveParent(client, { id, parentId }) {
  if (parentId === null || parentId === undefined) return null;

  const { rows: [parent] } = await client.query(
    'SELECT id FROM defect_codes WHERE id = $1',
    [parentId]
  );
  if (!parent) throw notFound('Parent Defect code');

  if (String(parent.id) === String(id)) {
    throw httpError(400, 'a Defect code cannot be its own parent');
  }

  const { rows: ancestorRows } = await client.query(
    `WITH RECURSIVE ancestors AS (
       SELECT id, parent_id, 0 AS depth FROM defect_codes WHERE id = $1
       UNION ALL
       SELECT p.id, p.parent_id, anc.depth + 1
         FROM defect_codes p
         JOIN ancestors anc ON p.id = anc.parent_id
        WHERE anc.depth < 64
     )
     SELECT id FROM ancestors WHERE id = $2`,
    [parentId, id]
  );
  if (ancestorRows.length > 0) {
    throw httpError(400, 'a Defect code cannot be moved beneath one of its own codes');
  }

  return parent.id;
}

async function createDefectCode({ code, name, category, defaultSeverity, parentId } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  if (category !== undefined) requireMembership('category', category, DEFECT_CATEGORIES);
  if (defaultSeverity !== undefined) requireMembership('defaultSeverity', defaultSeverity, SEVERITIES);

  // A malformed parentId is the caller's request shape, and is refused as one
  // before any query runs — the same 400 assets.js's setAssetParent gives.
  let parentIdValue = null;
  if (parentId !== undefined && parentId !== null) {
    parentIdValue = parseParentId(parentId);
    if (parentIdValue === null) throw httpError(400, 'parentId must be a valid Defect code id');
  }

  try {
    return await withActor(accountId, async (client) => {
      // Existence of the proposed parent before the write. No cycle walk: a
      // brand-new row has no descendants, so nothing it is placed under can
      // already be beneath it.
      if (parentIdValue !== null) {
        const { rows: [parent] } = await client.query(
          'SELECT id FROM defect_codes WHERE id = $1',
          [parentIdValue]
        );
        if (!parent) throw notFound('Parent Defect code');
      }

      const { rows: [row] } = await client.query(
        `INSERT INTO defect_codes (code, name, defect_category, default_severity, parent_id)
         VALUES ($1, $2, COALESCE($3, 'product'), COALESCE($4, 'minor'), $5)
         RETURNING ${DEFECT_CODE_COLUMNS}`,
        [code.trim(), name.trim(), category ?? null, defaultSeverity ?? null, parentIdValue]
      );
      return toDefectCode(row);
    });
  } catch (error) {
    throw mapDefectCodeWriteError(error);
  }
}

// The fields the catalogue's own correction surface owns: the name, the
// category, the default severity, where the code sits in the tree, and whether
// it is still in use. `code` is refused rather than silently ignored — it is
// what a Non-conformance's report and an audit finding quote, so a correction
// that rewrote it would rewrite history (products.js's own rule for its code).
// An absent key never touches its column, so a one-field PATCH cannot blank
// the others.
const DEFECT_CODE_WRITABLE_COLUMNS = {
  name: 'name',
  category: 'defect_category',
  defaultSeverity: 'default_severity',
  isActive: 'is_active'
};

async function updateDefectCode(id, input, accountId) {
  await findDefectCode(id); // 404s if it does not exist.

  const body = input ?? {};

  if (Object.prototype.hasOwnProperty.call(body, 'code')) {
    throw httpError(400, 'code cannot be corrected on a Defect code');
  }

  const touchesParent = Object.prototype.hasOwnProperty.call(body, 'parentId');
  let parentIdValue;
  if (touchesParent) {
    parentIdValue = body.parentId === null ? null : parseParentId(body.parentId);
    if (parentIdValue === null && body.parentId !== null) {
      throw httpError(400, 'parentId must be a valid Defect code id, or null to detach it');
    }
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(DEFECT_CODE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'category') requireMembership('category', value, DEFECT_CATEGORIES);
    if (key === 'defaultSeverity') requireMembership('defaultSeverity', value, SEVERITIES);
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (!touchesParent && sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than an UPDATE
    // with an empty SET list (which Postgres would reject outright).
    return findDefectCode(id);
  }

  try {
    return await withActor(accountId, async (client) => {
      // The parent link is resolved (and refused if it would make a cycle)
      // inside the same transaction as the write, so no concurrent re-parent
      // can slip between the check and the UPDATE.
      if (touchesParent) {
        const resolved = await resolveParent(client, { id, parentId: parentIdValue });
        params.push(resolved);
        sets.push(`parent_id = $${params.length}`);
      }

      if (sets.length === 0) {
        const { rows: [unchanged] } = await client.query(
          `SELECT ${DEFECT_CODE_COLUMNS} FROM defect_codes WHERE id = $1`,
          [id]
        );
        return toDefectCode(unchanged);
      }

      params.push(id);
      const { rows: [row] } = await client.query(
        `UPDATE defect_codes SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING ${DEFECT_CODE_COLUMNS}`,
        params
      );
      return toDefectCode(row);
    });
  } catch (error) {
    throw mapDefectCodeWriteError(error);
  }
}

// Local to this file, deliberately: `errors.js`'s `parseId` answers "is this a
// positive integer id" for a URL segment, and this needs exactly the same
// answer for a body field. It is spelled here rather than reached for across
// the Module's own files so that the one place a Defect code id's shape is
// decided is this file.
function parseParentId(value) {
  if (value === undefined || value === null) return null;
  const str = String(value).trim();
  return /^[1-9][0-9]*$/.test(str) ? str : null;
}

module.exports = {
  DEFECT_CATEGORIES,
  SEVERITIES,
  listDefectCodes,
  findDefectCode,
  createDefectCode,
  updateDefectCode
};
