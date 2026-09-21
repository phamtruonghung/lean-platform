/*
 * The Injury type catalogue (issue #224) — what an injury *was*: a cut, a
 * fracture, a burn. One half of the pair a classification draws on, the other
 * being body-parts.js, and both arrive with the classification they serve
 * rather than ahead of it (#223's revised build order, point 4: a near miss is
 * forbidden by the ladder's own CHECK from carrying either, so a catalogue
 * landing before the injury classification delivered nothing to the Module's
 * primary path).
 *
 * `injury_types` is a baseline table (`1756000000000_baseline.js:2297`), seeded
 * there with the plant's own starting list, and this file adds nothing to it —
 * no migration belongs to this ticket. Like `products` and `defect_codes` it
 * carries no `site_id` at all, so ADR-0005's "one catalogue, many plants" is
 * structural rather than a query that happens to omit a filter. That is also
 * why nothing here is Org-Unit scoped — an Injury type is reference data, not
 * a thing placed in the tree — and why the write surface is an
 * administrator's (injury-type-routes.js owns that half).
 *
 * Mirrors quality/products.js exactly: no HTTP, no caller awareness, no other
 * Module. injury-type-routes.js owns authenticate, requireActive, requireAdmin
 * and the 404s.
 *
 * Deactivation, never deletion. A deactivated Injury type is excluded from the
 * choices offered to whoever is classifying (`includeInactive` is what widens
 * the read) while staying perfectly readable on an incident that already
 * carries it — the row is history, and a Safety incident's classification is
 * the kind of history an injury rate is computed from years later.
 *
 * **Nothing in this file is restricted.** ADR-0037 restricts the three
 * structured fields *on an incident* — the identified Employee, the injury
 * type and the body part — because together they are one person's diagnosis.
 * The catalogue itself names nobody: "Fracture" is a word the plant keeps a
 * list of, and any active Account may read the list, exactly as any active
 * Account may read the Product catalogue.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

const INJURY_TYPE_COLUMNS = 'id, code, name, is_active, created_at, updated_at';

function toInjuryType(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A write against `injury_types` can fail for two reasons worth a clean 4xx
// rather than a 500, each named by the constraint Postgres actually reports
// (`injury_types_code_key` for the inline UNIQUE on `code`). Anything else is a
// genuine failure and is rethrown as-is — the shape mapProductWriteError and
// mapSafetyIncidentWriteError keep, so a raw database message, which names
// tables and columns, never reaches a caller.
function mapInjuryTypeWriteError(error) {
  if (error.code === '23505' && error.constraint === 'injury_types_code_key') {
    return httpError(409, 'an Injury type with this code already exists');
  }
  if (error.code === '23514') {
    return httpError(
      400,
      'That Injury type was refused by the database: a field is outside the set of values it accepts'
    );
  }
  return error;
}

// Active Injury types by default, ordered by code — the ordering a person
// scans a catalogue in. `includeInactive` widens to every row, which is what
// the catalogue's own Screen asks for so that a retired type can be reached and
// reactivated, and what a classify dialog deliberately does NOT ask for: a
// deactivated entry is excluded from the choices offered to whoever is
// classifying (issue #224's own criterion) while staying readable on an
// incident that already names it, because the incident reads its own joined
// row rather than this list.
//
// No Org Unit filter and no scope filter: an Injury type is shared reference
// data (ADR-0005), so this is a flat catalogue read whoever is asking.
async function listInjuryTypes({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT ${INJURY_TYPE_COLUMNS} FROM injury_types ${whereClause} ORDER BY code`
  );
  return rows.map(toInjuryType);
}

// Mirrors products.findProduct: a null id and "no such row" are both a 404,
// one query.
async function findInjuryType(id) {
  if (id === null) throw notFound('Injury type');
  const { rows } = await getPool().query(
    `SELECT ${INJURY_TYPE_COLUMNS} FROM injury_types WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Injury type');
  return toInjuryType(rows[0]);
}

async function createInjuryType({ code, name } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO injury_types (code, name)
         VALUES ($1, $2)
         RETURNING ${INJURY_TYPE_COLUMNS}`,
        [code.trim(), name.trim()]
      );
      return toInjuryType(row);
    });
  } catch (error) {
    throw mapInjuryTypeWriteError(error);
  }
}

// The two fields the catalogue's own correction surface owns: the name, and
// whether the type is still in use. The code is refused rather than silently
// ignored — it is what an incident's own report and an export quote, so a
// correction that rewrote it would rewrite history (products.js's own rule for
// its code). An absent key never touches its column, so a one-field PATCH
// cannot blank the other.
const INJURY_TYPE_WRITABLE_COLUMNS = {
  name: 'name',
  isActive: 'is_active'
};

async function updateInjuryType(id, input, accountId) {
  await findInjuryType(id); // 404s if it does not exist.

  const body = input ?? {};

  if (Object.prototype.hasOwnProperty.call(body, 'code')) {
    throw httpError(400, 'code cannot be corrected on an Injury type');
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(INJURY_TYPE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than an UPDATE
    // with an empty SET list (which Postgres would reject outright).
    return findInjuryType(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE injury_types SET ${sets.join(', ')}
          WHERE id = $${params.length}
          RETURNING ${INJURY_TYPE_COLUMNS}`,
        params
      );
      return toInjuryType(row);
    });
  } catch (error) {
    throw mapInjuryTypeWriteError(error);
  }
}

module.exports = {
  listInjuryTypes,
  findInjuryType,
  createInjuryType,
  updateInjuryType
};
