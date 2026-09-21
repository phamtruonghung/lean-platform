/*
 * The Body part catalogue (issue #224) — *where* on the body an injury was: a
 * hand, an eye, the back, each filed under the region it belongs to. The other
 * half of the pair a classification draws on; see injury-types.js's own header
 * for everything the two share, which is nearly everything.
 *
 * `body_parts` is a baseline table (`1756000000000_baseline.js:2310`), seeded
 * there, and this file adds nothing to it — no migration belongs to this
 * ticket. No `site_id`, so ADR-0005's shared catalogue is structural.
 *
 * One field this catalogue has that the Injury type catalogue does not:
 * `region`, from the known set the baseline's own CHECK enforces. It is a
 * value with a known set, so it is chosen and never typed (ADR-0023), and the
 * set is repeated here so a caller gets a sentence naming the field rather
 * than a raw constraint violation — the same reasoning defect-codes.js gives
 * its own repeated sets. The column carries a DEFAULT of `'other'`, which this
 * file leaves to fire when a caller says nothing.
 *
 * **Nothing in this file is restricted.** ADR-0037 restricts the three
 * structured fields *on an incident*; a list of the parts of a body names
 * nobody, and any active Account may read it.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// The set the baseline's own CHECK enforces on `body_parts.region`. Repeated
// here so a caller gets a sentence naming the field rather than a constraint
// violation: the set is the database's, and a change to one must change both,
// which is why it is named as mirroring the CHECK rather than presented as
// this file's own decision.
const BODY_PART_REGIONS = ['head', 'trunk', 'upper_limb', 'lower_limb', 'multiple', 'other'];

function requireMembership(field, value, allowed) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw httpError(400, `${field} must be one of ${allowed.join(', ')}`);
  }
}

const BODY_PART_COLUMNS = 'id, code, name, region, is_active, created_at, updated_at';

function toBodyPart(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    region: row.region,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapBodyPartWriteError(error) {
  if (error.code === '23505' && error.constraint === 'body_parts_code_key') {
    return httpError(409, 'a Body part with this code already exists');
  }
  if (error.code === '23514') {
    return httpError(
      400,
      'That Body part was refused by the database: a field is outside the set of values it accepts'
    );
  }
  return error;
}

// Active Body parts by default, ordered by region and then by code — a
// catalogue whose rows group naturally, and the order a person picking one
// reads it in. `includeInactive` widens to every row, for the reason
// listInjuryTypes gives: the Screen reaches a retired row to reactivate it, and
// a classify dialog deliberately does not ask for it.
async function listBodyParts({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT ${BODY_PART_COLUMNS} FROM body_parts ${whereClause} ORDER BY region, code`
  );
  return rows.map(toBodyPart);
}

async function findBodyPart(id) {
  if (id === null) throw notFound('Body part');
  const { rows } = await getPool().query(
    `SELECT ${BODY_PART_COLUMNS} FROM body_parts WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Body part');
  return toBodyPart(rows[0]);
}

async function createBodyPart({ code, name, region } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  if (region !== undefined) requireMembership('region', region, BODY_PART_REGIONS);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO body_parts (code, name, region)
         VALUES ($1, $2, COALESCE($3, 'other'))
         RETURNING ${BODY_PART_COLUMNS}`,
        [code.trim(), name.trim(), region ?? null]
      );
      return toBodyPart(row);
    });
  } catch (error) {
    throw mapBodyPartWriteError(error);
  }
}

// The three fields the catalogue's own correction surface owns: the name, the
// region it is filed under, and whether it is still in use. The code is
// refused rather than silently ignored, for the reason injury-types.js gives
// its own.
const BODY_PART_WRITABLE_COLUMNS = {
  name: 'name',
  region: 'region',
  isActive: 'is_active'
};

async function updateBodyPart(id, input, accountId) {
  await findBodyPart(id); // 404s if it does not exist.

  const body = input ?? {};

  if (Object.prototype.hasOwnProperty.call(body, 'code')) {
    throw httpError(400, 'code cannot be corrected on a Body part');
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(BODY_PART_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'region') requireMembership('region', value, BODY_PART_REGIONS);
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    return findBodyPart(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE body_parts SET ${sets.join(', ')}
          WHERE id = $${params.length}
          RETURNING ${BODY_PART_COLUMNS}`,
        params
      );
      return toBodyPart(row);
    });
  } catch (error) {
    throw mapBodyPartWriteError(error);
  }
}

module.exports = {
  BODY_PART_REGIONS,
  listBodyParts,
  findBodyPart,
  createBodyPart,
  updateBodyPart
};
