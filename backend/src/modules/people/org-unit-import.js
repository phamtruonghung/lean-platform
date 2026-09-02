/*
 * Bulk Org Unit import (issue #12, CONTEXT.md's Site/Org Unit definitions).
 * HTTP-unaware, like plant.js — the route lives in plant-routes.js, next to
 * the other Org Unit routes it shares a prefix and a scope machinery with.
 *
 * "From a file" (the issue's own words) is a JSON body of rows, over the
 * existing HTTP surface — not a multipart upload or a CSV parser. A JSON
 * array of objects already has no ambiguity about types (an integer
 * sortOrder is not a quoted string, a null parentCode is not the string
 * "null"), which is exactly what a hand-edited CSV cannot promise, and it
 * costs nothing beyond what every other write route here already does:
 * `express.json()`. See docs/adr/0011 for the fuller decision record.
 *
 * The crux of the format: a file has no database ids, so a row cannot name
 * its parent by one. Rows instead reference each other by `code` — either
 * another row in the same payload (building several levels of a new branch
 * in one call) or an Org Unit that already exists at this Site (attaching
 * new rows under a branch that is already there). `code` is already unique
 * per Site (the baseline's own `org_units_code_unique`), so it is a name a
 * spreadsheet can carry without ever seeing an id.
 *
 * Every row is validated before anything is applied (issue #12 criteria 3
 * and 4): validateRows below never stops at the first bad row, and collects
 * every reason a row is invalid — a missing field, a duplicate code, an
 * unresolvable parentCode, a cycle — so a failed import's response can name
 * every offending row in one pass rather than making the spreadsheeter fix
 * one row, resubmit, and discover the next. Only once every row passes
 * structural validation is scope decided (criterion 5), and only once scope
 * passes for every row does applyImport open the one transaction that
 * inserts them all, parents before children. A row is never partially
 * applied, and neither is a payload: any failure at any stage leaves the
 * database exactly as it was.
 *
 * Deliberately does NOT call plant.createOrgUnit per row: that function opens
 * its own transaction on every call (see its own site), which would commit
 * each row as it goes and leave a half-built plant behind on the row that
 * fails. This file reuses plant.js's own column mapping and write-error
 * translation (ORG_UNIT_COLUMNS, toOrgUnit, mapOrgUnitWriteError, UNIT_TYPES
 * — exported from plant.js for exactly this file) and inserts every row
 * itself, inside one withActor transaction.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');
const authorization = require('./authorization');
const { UNIT_TYPES, ORG_UNIT_COLUMNS, toOrgUnit, mapOrgUnitWriteError } = require('./plant');

// The 422 shape (issue #12 criterion 4): a message plus one entry per
// offending row, `row` being the 0-based index in the submitted `orgUnits`
// array so the spreadsheeter can find the line. Distinct from httpError's
// plain `{ message }` shape — plant-routes.js's route handler checks for
// `error.errors` before falling back to the generic handleError.
function validationError(errors) {
  const error = new Error('The import contains invalid rows');
  error.status = 422;
  error.errors = errors;
  return error;
}

function addError(errors, row, code, field, message) {
  errors.push({ row, code, field, message });
}

// Envelope shape only — 400, not 422, per the issue's own distinction: a
// missing/malformed `orgUnits` is not a row to report on, it is a request
// that never named any rows at all.
function requireEnvelope(body) {
  const orgUnits = body?.orgUnits;
  if (!Array.isArray(orgUnits) || orgUnits.length === 0) {
    throw httpError(400, 'orgUnits (a non-empty array) is required');
  }
  return orgUnits;
}

// A functional graph (each row has at most one payload parent) can only
// cycle back on itself, never fork, so following each row's parent pointer
// for at most `n` steps is enough to find every cycle — including a row that
// parents itself, which is a cycle of length one. Returns the set of row
// indexes that are members of some cycle.
function findCycleMembers(parentIndex, n) {
  const state = new Array(n).fill(0); // 0 = unvisited, 1 = on the current walk, 2 = resolved
  const cycle = new Set();

  for (let start = 0; start < n; start += 1) {
    if (state[start] !== 0) continue;

    const path = [];
    let cur = start;
    while (cur !== undefined && state[cur] === 0) {
      state[cur] = 1;
      path.push(cur);
      cur = parentIndex[cur];
    }
    if (cur !== undefined && state[cur] === 1) {
      const firstInCycle = path.indexOf(cur);
      for (let i = firstInCycle; i < path.length; i += 1) cycle.add(path[i]);
    }
    for (const i of path) state[i] = 2;
  }

  return cycle;
}

// Structural validation (issue #12 criteria 3 and 4): every row, every
// reason, collected in one pass — never fail fast. Returns
// `{ parentIndex, externalParentByRow }`, the two pieces applyImport and the
// scope check need to know how each row relates to the rest of the payload,
// once every row is known to be individually and mutually valid. Throws
// validationError (422) the moment any error was collected, with nothing
// having touched the database beyond the one read below.
async function validateRows(siteId, orgUnits) {
  const errors = [];
  const n = orgUnits.length;

  // Field-level checks, and a code -> [row indexes] map for the
  // within-payload duplicate check below. Only a row with a well-formed code
  // participates as a possible parent target later — an invalid code cannot
  // be pointed at.
  const codesByValue = new Map();
  for (let i = 0; i < n; i += 1) {
    const row = orgUnits[i];
    const code = row?.code;
    const rawCode = typeof code === 'string' ? code : null;

    if (typeof code !== 'string' || code.trim() === '') {
      addError(errors, i, rawCode, 'code', 'code is required');
    } else {
      const trimmed = code.trim();
      if (!codesByValue.has(trimmed)) codesByValue.set(trimmed, []);
      codesByValue.get(trimmed).push(i);
    }

    if (typeof row?.name !== 'string' || row.name.trim() === '') {
      addError(errors, i, rawCode, 'name', 'name is required');
    }

    if (typeof row?.unitType !== 'string' || !UNIT_TYPES.includes(row.unitType)) {
      addError(errors, i, rawCode, 'unitType', `unitType must be one of: ${UNIT_TYPES.join(', ')}`);
    }

    if (row?.sortOrder !== undefined && !Number.isInteger(row.sortOrder)) {
      addError(errors, i, rawCode, 'sortOrder', 'sortOrder must be an integer');
    }

    if (row?.parentCode !== undefined && row?.parentCode !== null && typeof row.parentCode !== 'string') {
      addError(errors, i, rawCode, 'parentCode', 'parentCode must be a string or null');
    }
  }

  // Duplicate code within the payload: every row sharing a code is named,
  // not just the second one onward, since the spreadsheeter needs to see
  // both to know which to change.
  for (const [code, indexes] of codesByValue) {
    if (indexes.length > 1) {
      for (const i of indexes) {
        addError(errors, i, code, 'code', `code "${code}" is used by more than one row in this import`);
      }
    }
  }

  // Every Org Unit already at this Site, by code — one read, used for both
  // the "code already exists" check and resolving a parentCode against an
  // existing Org Unit rather than another payload row.
  const { rows: existingRows } = await getPool().query(
    'SELECT id, code FROM org_units WHERE site_id = $1',
    [siteId]
  );
  const existingByCode = new Map(existingRows.map((row) => [row.code, row]));

  for (const [code, indexes] of codesByValue) {
    if (existingByCode.has(code)) {
      for (const i of indexes) {
        addError(errors, i, code, 'code', `code "${code}" already exists at this Site`);
      }
    }
  }

  // parentCode resolution: another payload row (internal — parentIndex),
  // an existing Org Unit at this Site (external — externalParentByRow), or
  // neither, which is itself a row-level error.
  const parentIndex = new Array(n).fill(undefined);
  const externalParentByRow = new Array(n).fill(undefined);

  for (let i = 0; i < n; i += 1) {
    const row = orgUnits[i];
    const parentCode = typeof row?.parentCode === 'string' ? row.parentCode.trim() : null;
    if (parentCode === null || parentCode === '') continue; // root row — no parent to resolve.

    if (codesByValue.has(parentCode)) {
      // The first row using this code, deterministically — if the code is
      // itself a duplicate, that is already reported above independently of
      // this resolution.
      [parentIndex[i]] = codesByValue.get(parentCode);
    } else if (existingByCode.has(parentCode)) {
      externalParentByRow[i] = existingByCode.get(parentCode);
    } else {
      addError(
        errors,
        i,
        typeof row?.code === 'string' ? row.code : null,
        'parentCode',
        `parentCode "${parentCode}" matches no row in this import and no existing Org Unit at this Site`
      );
    }
  }

  // Cycles among payload rows, self-parenting included (see
  // findCycleMembers's own header for why the same check catches both).
  for (const i of findCycleMembers(parentIndex, n)) {
    const row = orgUnits[i];
    addError(
      errors,
      i,
      typeof row?.code === 'string' ? row.code : null,
      'parentCode',
      'parentCode forms a cycle with another row in this import'
    );
  }

  if (errors.length > 0) throw validationError(errors);

  return { parentIndex, externalParentByRow };
}

// Issue #12 criterion 5 (and its [b]): scope is decided per row, once
// structural validation has already passed, and the WHOLE import is refused
// if any row fails — nothing applied, the same "all or nothing" as an
// invalid row. A root row (no parentCode at all) needs the administrator
// role, the same rule plant-routes.js's requireOrgUnitCreateScope applies to
// POST /sites/:siteId/org-units. A row parented to an existing Org Unit
// needs write scope on that Org Unit. A row parented to another payload row
// inherits whatever the chain it sits in ultimately anchors on — resolved by
// walking parentIndex up to its root, which structural validation has
// already guaranteed is cycle-free.
async function requireImportScope(account, orgUnits, parentIndex, externalParentByRow) {
  const n = orgUnits.length;
  const anchors = new Array(n).fill(undefined);

  function anchorFor(i) {
    if (anchors[i] !== undefined) return anchors[i];
    let anchor;
    if (parentIndex[i] !== undefined) {
      anchor = anchorFor(parentIndex[i]);
    } else if (externalParentByRow[i] !== undefined) {
      anchor = { type: 'orgUnit', orgUnitId: externalParentByRow[i].id };
    } else {
      anchor = { type: 'root' };
    }
    anchors[i] = anchor;
    return anchor;
  }

  const canActCache = new Map();
  for (let i = 0; i < n; i += 1) {
    const anchor = anchorFor(i);
    if (anchor.type === 'root') {
      if (!authorization.isAdmin(account)) {
        throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
      }
    } else {
      if (!canActCache.has(anchor.orgUnitId)) {
        canActCache.set(
          anchor.orgUnitId,
          authorization.canAct({ account, orgUnitId: anchor.orgUnitId, write: true })
        );
      }
      // eslint-disable-next-line no-await-in-loop
      if (!(await canActCache.get(anchor.orgUnitId))) {
        throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
      }
    }
  }
}

// Parents before children: a row with an internal parent is visited only
// after that parent, which is what lets applyImport look up the parent's
// freshly-created id when it inserts a child. Cycle-free by the time this
// runs (validateRows already threw otherwise), so this always terminates.
function topologicalOrder(parentIndex, n) {
  const order = [];
  const state = new Array(n).fill(0); // 0 = unvisited, 1 = visited

  function visit(i) {
    if (state[i] === 1) return;
    if (parentIndex[i] !== undefined) visit(parentIndex[i]);
    state[i] = 1;
    order.push(i);
  }

  for (let i = 0; i < n; i += 1) visit(i);
  return order;
}

async function importOrgUnits({ siteId, body, account }) {
  const orgUnits = requireEnvelope(body);
  const { parentIndex, externalParentByRow } = await validateRows(siteId, orgUnits);
  await requireImportScope(account, orgUnits, parentIndex, externalParentByRow);

  const order = topologicalOrder(parentIndex, orgUnits.length);

  return withActor(account.id, async (client) => {
    const createdIdByRow = new Array(orgUnits.length).fill(undefined);
    const created = [];

    for (const i of order) {
      const row = orgUnits[i];
      let parentId = null;
      if (parentIndex[i] !== undefined) {
        parentId = createdIdByRow[parentIndex[i]];
      } else if (externalParentByRow[i] !== undefined) {
        parentId = externalParentByRow[i].id;
      }
      const sortOrderValue = Number.isInteger(row.sortOrder) ? row.sortOrder : 0;

      let insertedRow;
      try {
        // eslint-disable-next-line no-await-in-loop
        const { rows: [inserted] } = await client.query(
          `INSERT INTO org_units (site_id, parent_id, code, name, unit_type, sort_order)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING ${ORG_UNIT_COLUMNS}`,
          [siteId, parentId, row.code.trim(), row.name.trim(), row.unitType, sortOrderValue]
        );
        insertedRow = inserted;
      } catch (error) {
        throw mapOrgUnitWriteError(error);
      }

      createdIdByRow[i] = insertedRow.id;
      created.push(toOrgUnit(insertedRow));
    }

    return created;
  });
}

module.exports = { importOrgUnits };
