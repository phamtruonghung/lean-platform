/*
 * The Product catalogue (issue #203) — the first slice of the Quality Module,
 * and the catalogue every later Quality record will point at: a Non-conformance
 * names the Product it was found on, and the Quality Issues view already joins
 * `products` to report scrap by part.
 *
 * `products` is a baseline table and this file adds nothing to it. ADR-0005's
 * "one catalogue, many plants" is structural here as it is for `job_roles`:
 * `products` carries no `site_id` at all, so the catalogue is shared by every
 * Site by construction rather than by a query that happens to omit a filter.
 * That is also why nothing in this file is Org-Unit scoped — a Product is
 * reference data, not a thing placed in the tree — and why the write surface
 * is an administrator's (product-routes.js owns that half).
 *
 * Mirrors job-roles.js/plant.js exactly: this file knows nothing about HTTP or
 * about who is calling. It accepts ids it is handed and assumes the caller
 * already checked what needed checking; product-routes.js owns authenticate,
 * requireActive, requireAdmin and the 404s.
 *
 * The unit of measure a Product is measured in is a baseline reference value
 * (`units_of_measure`, seeded by the baseline migration) and is CHOSEN, never
 * typed (ADR-0023): the form reads the list the plant uses and reports the
 * pick, and this file refuses a code that is not in the table with a clean
 * 400 rather than letting the foreign key fail as a 500.
 *
 * Deactivation, never deletion — job-roles.js's own reasoning, and stronger
 * here: a Product that has been built, shipped and found defective is history
 * that a Defect code and a future Non-conformance still point at.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Postgres's own LIKE/ILIKE escape rules, copied from
// modules/people/sql.js's definition rather than required from it: that file
// is People's own internal, and ADR-0006's third clause keeps it there. The
// duplication is the same seam errors.js is a fourth copy of. `\` is escaped
// first, so a literal backslash in the search text does not turn the `%`/`_`
// escapes added after it into something else; the caller adds the
// `ESCAPE '\'` clause that makes these three characters special and no others.
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

// `uom_name` is joined rather than left to the client so that a catalogue row
// can say what a Product is measured in without a second read — the same thing
// inventory.js's own part listing does for `uom_code`. Every row is one
// `products` row joined to exactly one `units_of_measure` row (`uom_code` is
// NOT NULL and a foreign key), so the join never multiplies or drops a Product.
const PRODUCT_COLUMNS = `
  p.id, p.code, p.name, p.uom_code, u.name AS uom_name,
  p.is_active, p.created_at, p.updated_at`;

function toProduct(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    uomCode: row.uom_code,
    uomName: row.uom_name,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A write against `products` can fail for three reasons this file turns into a
// clean 4xx rather than a 500, each named by the constraint Postgres actually
// reports (`products_code_key` for the inline UNIQUE on `code`; the foreign key
// from `uom_code` to `units_of_measure`; the CHECK on `product_type`, which
// this Module never writes but a future writer of the column would). Anything
// else is a genuine failure and is rethrown as-is, the same shape
// mapJobRoleWriteError/mapAssetWriteError keep.
function mapProductWriteError(error) {
  if (error.code === '23505' && error.constraint === 'products_code_key') {
    return httpError(409, 'a Product with this code already exists');
  }
  if (error.code === '23503') {
    return httpError(400, 'uomCode must be a unit of measure the plant uses');
  }
  if (error.code === '23514') {
    return httpError(400, 'That Product was refused by the database: a field is outside the set of values it accepts');
  }
  return error;
}

// Active Products by default, ordered by code — a catalogue read, and the
// ordering a person scans a parts list in. `includeInactive` widens to every
// Product, which is what the catalogue's own Screen asks for so that a
// deactivated row can be reached and reactivated (job-roles.js's own idiom).
//
// `search` matches code OR name, the two things a caller has to hand when they
// are looking for a Product to record against. There is no Org Unit filter and
// no scope filter: a Product is shared reference data (ADR-0005), so this is a
// flat catalogue read whoever is asking — the same openness
// job-roles.js's listJobRoles has, and for the same reason.
async function listProducts({ search, includeInactive } = {}) {
  const conditions = [];
  const params = [];

  if (!includeInactive) {
    conditions.push('p.is_active = TRUE');
  }

  const term = typeof search === 'string' ? search.trim() : '';
  if (term !== '') {
    params.push(`%${escapeLikePattern(term)}%`);
    conditions.push(
      `(p.code ILIKE $${params.length} ESCAPE '\\' OR p.name ILIKE $${params.length} ESCAPE '\\')`
    );
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const { rows } = await getPool().query(
    `SELECT ${PRODUCT_COLUMNS}
       FROM products p
       JOIN units_of_measure u ON u.code = p.uom_code
       ${whereClause}
      ORDER BY p.code`,
    params
  );
  return rows.map(toProduct);
}

// Mirrors plant.getOrgUnit/directory.getEmployee: a null id and "no such row"
// are both a 404, one query.
async function findProduct(id) {
  if (id === null) throw notFound('Product');
  const { rows } = await getPool().query(
    `SELECT ${PRODUCT_COLUMNS}
       FROM products p
       JOIN units_of_measure u ON u.code = p.uom_code
      WHERE p.id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Product');
  return toProduct(rows[0]);
}

async function createProduct({ code, name, uomCode } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  requireNonEmptyString('uomCode', uomCode);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO products (code, name, uom_code)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [code.trim(), name.trim(), uomCode.trim()]
      );
      // Re-read through the same projection as every other answer, so a
      // created Product and a listed one can never carry different fields.
      const { rows: [created] } = await client.query(
        `SELECT ${PRODUCT_COLUMNS}
           FROM products p
           JOIN units_of_measure u ON u.code = p.uom_code
          WHERE p.id = $1`,
        [row.id]
      );
      return toProduct(created);
    });
  } catch (error) {
    throw mapProductWriteError(error);
  }
}

// The two fields the catalogue's own correction surface owns: the name, and
// whether the Product is still in use. Everything else is refused rather than
// silently ignored — a code is what a Defect record, a report and a
// non-conformance label quote, and `uom_code` decides how a quantity is read,
// so neither is a field a correction may quietly rewrite. An absent key never
// touches its column (updateJobRole's own hasOwnProperty idiom), so a
// one-field PATCH cannot blank the other.
const PRODUCT_WRITABLE_COLUMNS = {
  name: 'name',
  isActive: 'is_active'
};

const PRODUCT_REFUSED_COLUMNS = ['code', 'uomCode'];

async function updateProduct(id, input, accountId) {
  await findProduct(id); // 404s if it does not exist.

  const body = input ?? {};

  for (const key of PRODUCT_REFUSED_COLUMNS) {
    if (Object.prototype.hasOwnProperty.call(body, key)) {
      throw httpError(400, `${key} cannot be corrected on a Product`);
    }
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(PRODUCT_WRITABLE_COLUMNS)) {
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
    return findProduct(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE products SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING id`,
        params
      );
      const { rows: [updated] } = await client.query(
        `SELECT ${PRODUCT_COLUMNS}
           FROM products p
           JOIN units_of_measure u ON u.code = p.uom_code
          WHERE p.id = $1`,
        [row.id]
      );
      return toProduct(updated);
    });
  } catch (error) {
    throw mapProductWriteError(error);
  }
}

module.exports = {
  listProducts,
  findProduct,
  createProduct,
  updateProduct
};
