/*
 * The Customer catalogue (issue #214) — the customer list a complaint belongs
 * to, and the record an incoming complaint names.
 *
 * `customers` is a baseline table and this file adds nothing to it. Its own
 * comment in the baseline is the design: "Deliberately minimal. This is not a
 * CRM — they exist so a complaint has someone to belong to." So there is a code
 * a person quotes, a name, an optional contact email and whether the Customer
 * is still traded with — and nothing else. No address, no account manager, no
 * industry code: none of them would be read by anything this Platform does.
 *
 * `customers.code` is UNIQUE in the baseline, which is what makes a duplicate a
 * 409 from the database rather than a check this file races: two callers
 * creating the same Customer at once are refused by the index, and this file
 * maps that refusal to a sentence a caller can act on. Like `products` and
 * `job_roles`, the catalogue is shared by every Site (ADR-0005) — a Customer
 * belongs to the company, not to a plant — so nothing here is Org-Unit scoped
 * and the write surface is an administrator's (customer-routes.js owns that
 * half).
 *
 * Mirrors products.js exactly: this file knows nothing about HTTP or about who
 * is calling. It accepts ids it is handed and assumes the caller already
 * checked what needed checking; customer-routes.js owns authenticate,
 * requireActive, requireAdmin and the 404s.
 *
 * Deactivation, never deletion — products.js's own reasoning, and the same one
 * here: a Customer that has complained is history that a
 * `customer_complaints` row still points at.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Postgres's own LIKE/ILIKE escape rules, copied from products.js's definition
// rather than shared with it: each file in this Module keeps its own private
// helpers (errors.js's header argues why the duplication is the seam).
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

const CUSTOMER_COLUMNS = `c.id, c.code, c.name, c.contact_email, c.is_active, c.created_at, c.updated_at`;

function toCustomer(row) {
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

// The two refusals a write against `customers` raises, each named by the
// constraint Postgres actually reports: `customers_code_key` for the inline
// UNIQUE on `code`, and any CHECK the table carries. Anything else is a genuine
// failure and is rethrown as-is, the shape mapProductWriteError keeps.
function mapCustomerWriteError(error) {
  if (error.code === '23505' && error.constraint === 'customers_code_key') {
    return httpError(409, 'a Customer with this code already exists');
  }
  if (error.code === '23514') {
    return httpError(400, 'That Customer was refused by the database: a field is outside the set of values it accepts');
  }
  return error;
}

// An optional text field, read the way the route's own body carries it: absent
// means "leave it", an explicit null or an empty string means "clear it" — the
// same distinction products.js draws between a field the caller did not send
// and one they sent as nothing. Returns `undefined` for "not sent".
function optionalContactEmail(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') throw httpError(400, 'contactEmail must be text');
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

// Active Customers by default, ordered by name — the order a person scans a
// customer list in, unlike the code-ordered catalogues. `includeInactive`
// widens to every Customer, so a deactivated row can be reached and
// reactivated (products.js's own idiom).
//
// `search` matches code OR name, the two things a caller has to hand when they
// are looking for the Customer a complaint came from — which is every active
// Account's read, not an administrator's (issue #214's own criterion). There is
// no Org Unit filter and no scope filter: a Customer is shared reference data
// (ADR-0005), the same flat read listProducts is.
async function listCustomers({ search, includeInactive } = {}) {
  const conditions = [];
  const params = [];

  if (!includeInactive) {
    conditions.push('c.is_active = TRUE');
  }

  const term = typeof search === 'string' ? search.trim() : '';
  if (term !== '') {
    params.push(`%${escapeLikePattern(term)}%`);
    conditions.push(
      `(c.code ILIKE $${params.length} ESCAPE '\\' OR c.name ILIKE $${params.length} ESCAPE '\\')`
    );
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const { rows } = await getPool().query(
    `SELECT ${CUSTOMER_COLUMNS}
       FROM customers c
       ${whereClause}
      ORDER BY c.name, c.id`,
    params
  );
  return rows.map(toCustomer);
}

// Mirrors findProduct: a null id and "no such row" are both a 404, one query —
// and the same 404 is what a complaint's own read gives an unknown Customer.
async function findCustomer(id) {
  if (id === null) throw notFound('Customer');
  const { rows } = await getPool().query(
    `SELECT ${CUSTOMER_COLUMNS} FROM customers c WHERE c.id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Customer');
  return toCustomer(rows[0]);
}

async function createCustomer({ code, name, contactEmail } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  const email = optionalContactEmail(contactEmail) ?? null;

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO customers (code, name, contact_email)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [code.trim(), name.trim(), email]
      );
      // Re-read through the same projection as every other answer, so a
      // created Customer and a listed one can never carry different fields.
      const { rows: [created] } = await client.query(
        `SELECT ${CUSTOMER_COLUMNS} FROM customers c WHERE c.id = $1`,
        [row.id]
      );
      return toCustomer(created);
    });
  } catch (error) {
    throw mapCustomerWriteError(error);
  }
}

// The three fields the catalogue's own correction surface owns. `code` is
// refused rather than silently ignored: it is what a complaint quotes and what
// a person searches by, so it is not a field a correction may quietly rewrite.
// An absent key never touches its column (products.js's own hasOwnProperty
// idiom), so a one-field PATCH cannot blank the others.
const CUSTOMER_WRITABLE_COLUMNS = {
  name: 'name',
  contactEmail: 'contact_email',
  isActive: 'is_active'
};

const CUSTOMER_REFUSED_COLUMNS = ['code'];

async function updateCustomer(id, input, accountId) {
  await findCustomer(id); // 404s if it does not exist.

  const body = input ?? {};

  for (const key of CUSTOMER_REFUSED_COLUMNS) {
    if (Object.prototype.hasOwnProperty.call(body, key)) {
      throw httpError(400, `${key} cannot be corrected on a Customer`);
    }
  }

  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(CUSTOMER_WRITABLE_COLUMNS)) {
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
    return findCustomer(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE customers SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING id`,
        params
      );
      const { rows: [updated] } = await client.query(
        `SELECT ${CUSTOMER_COLUMNS} FROM customers c WHERE c.id = $1`,
        [row.id]
      );
      return toCustomer(updated);
    });
  } catch (error) {
    throw mapCustomerWriteError(error);
  }
}

module.exports = {
  listCustomers,
  findCustomer,
  createCustomer,
  updateCustomer
};
