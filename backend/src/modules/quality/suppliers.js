/*
 * The Supplier catalogue (issue #215) — the supplier list a supplier NCR
 * belongs to, and the record an incoming non-conformance names.
 *
 * `suppliers` is a baseline table and this file adds nothing to it. Its own
 * comment in the baseline is the design: "Deliberately minimal. This is not a
 * CRM — they exist so ... an incoming non-conformance has someone to charge."
 * So there is a code a person quotes, a name, an optional contact email and
 * whether the Supplier is still traded with — and nothing else. No address, no
 * account manager, no quality rating: none of them would be read by anything
 * this Platform does.
 *
 * `suppliers.code` is UNIQUE in the baseline, which is what makes a duplicate a
 * 409 from the database rather than a check this file races: two callers
 * creating the same Supplier at once are refused by the index, and this file
 * maps that refusal to a sentence a caller can act on. Like `customers`,
 * `products` and `job_roles`, the catalogue is shared by every Site (ADR-0005)
 * — a Supplier belongs to the company, not to a plant — so nothing here is
 * Org-Unit scoped and the write surface is an administrator's
 * (supplier-routes.js owns that half).
 *
 * Mirrors customers.js exactly, which mirrors products.js before it: this file
 * knows nothing about HTTP or about who is calling. It accepts ids it is handed
 * and assumes the caller already checked what needed checking;
 * supplier-routes.js owns authenticate, requireActive, requireAdmin and the
 * 404s. The two catalogues are deliberately two files rather than one
 * parameterised one: each keeps its own private helpers and its own projection,
 * and the duplication is the seam (errors.js's header argues the same thing).
 *
 * Deactivation, never deletion — the same reasoning as everywhere else: a
 * Supplier that failed an incoming lot is history that a `supplier_ncrs` row
 * still points at.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Postgres's own LIKE/ILIKE escape rules, copied from customers.js's definition
// rather than shared with it: each file in this Module keeps its own private
// helpers (errors.js's header argues why the duplication is the seam).
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

const SUPPLIER_COLUMNS = `s.id, s.code, s.name, s.contact_email, s.is_active, s.created_at, s.updated_at`;

function toSupplier(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    contactEmail: row.contact_email ?? null,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// The two refusals a write against `suppliers` raises, each named by the
// constraint Postgres actually reports: `suppliers_code_key` for the inline
// UNIQUE on `code`, and any CHECK the table carries. Anything else is a genuine
// failure and is rethrown as-is, the shape mapCustomerWriteError keeps.
function mapSupplierWriteError(error) {
  if (error.code === '23505' && error.constraint === 'suppliers_code_key') {
    return httpError(409, 'a Supplier with this code already exists');
  }
  if (error.code === '23514') {
    return httpError(400, 'That Supplier was refused by the database: a field is outside the set of values it accepts');
  }
  return error;
}

// An optional text field, read the way the route's own body carries it: absent
// means "leave it", an explicit null or an empty string means "clear it".
// Returns `undefined` for "not sent".
function optionalContactEmail(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') throw httpError(400, 'contactEmail must be text');
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

// Active Suppliers by default, ordered by name — the order a person scans a
// supplier list in, unlike the code-ordered catalogues. `includeInactive`
// widens to every Supplier, so a deactivated row can be reached and
// reactivated.
//
// `search` matches code OR name, the two things a caller has to hand when they
// are recording a supplier NCR — which is every active Account's read, not an
// administrator's (issue #215's own criterion). There is no Org Unit filter and
// no scope filter: a Supplier is shared reference data (ADR-0005), the same
// flat read listCustomers is.
async function listSuppliers({ search, includeInactive } = {}) {
  const conditions = [];
  const params = [];

  if (!includeInactive) {
    conditions.push('s.is_active = TRUE');
  }

  const term = typeof search === 'string' ? search.trim() : '';
  if (term !== '') {
    params.push(`%${escapeLikePattern(term)}%`);
    conditions.push(
      `(s.code ILIKE $${params.length} ESCAPE '\\' OR s.name ILIKE $${params.length} ESCAPE '\\')`
    );
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const { rows } = await getPool().query(
    `SELECT ${SUPPLIER_COLUMNS}
       FROM suppliers s
       ${whereClause}
      ORDER BY s.name, s.id`,
    params
  );
  return rows.map(toSupplier);
}

// Mirrors findCustomer: a null id and "no such row" are both a 404, one query —
// and the same 404 is what a supplier NCR's own read gives an unknown Supplier.
async function findSupplier(id) {
  if (id === null) throw notFound('Supplier');
  const { rows } = await getPool().query(
    `SELECT ${SUPPLIER_COLUMNS} FROM suppliers s WHERE s.id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Supplier');
  return toSupplier(rows[0]);
}

async function createSupplier({ code, name, contactEmail } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  const email = optionalContactEmail(contactEmail) ?? null;

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO suppliers (code, name, contact_email)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [code.trim(), name.trim(), email]
      );
      // Re-read through the same projection as every other answer, so a
      // created Supplier and a listed one can never carry different fields.
      const { rows: [created] } = await client.query(
        `SELECT ${SUPPLIER_COLUMNS} FROM suppliers s WHERE s.id = $1`,
        [row.id]
      );
      return toSupplier(created);
    });
  } catch (error) {
    throw mapSupplierWriteError(error);
  }
}

// The three fields the catalogue's own correction surface owns. `code` is
// refused rather than silently ignored: it is what a supplier NCR quotes and
// what a person searches by, so it is not a field a correction may quietly
// rewrite. An absent key never touches its column, so a one-field PATCH cannot
// blank the others.
const SUPPLIER_WRITABLE_COLUMNS = {
  name: 'name',
  contactEmail: 'contact_email',
  isActive: 'is_active'
};

const SUPPLIER_REFUSED_COLUMNS = ['code'];

async function updateSupplier(id, input, accountId) {
  await findSupplier(id); // 404s if it does not exist.

  const body = input ?? {};

  for (const key of SUPPLIER_REFUSED_COLUMNS) {
    if (Object.prototype.hasOwnProperty.call(body, key)) {
      throw httpError(400, `${key} cannot be corrected on a Supplier`);
    }
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(SUPPLIER_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'isActive' && typeof value !== 'boolean') {
      throw httpError(400, 'isActive must be a boolean');
    }
    if (key === 'contactEmail') value = optionalContactEmail(value);
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than an UPDATE
    // with an empty SET list (which Postgres would reject outright).
    return findSupplier(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE suppliers SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING id`,
        params
      );
      const { rows: [updated] } = await client.query(
        `SELECT ${SUPPLIER_COLUMNS} FROM suppliers s WHERE s.id = $1`,
        [row.id]
      );
      return toSupplier(updated);
    });
  } catch (error) {
    throw mapSupplierWriteError(error);
  }
}

module.exports = {
  listSuppliers,
  findSupplier,
  createSupplier,
  updateSupplier
};
