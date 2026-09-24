/*
 * The product standard cost catalogue (issue #252) — what one unit of a Product
 * is costed at, and from when. The other half of the pair cost-rates.js opens:
 * `product_standard_cost(product_id, at)` is what the baseline's cost-of-poor
 * -quality view prices scrap with, and nothing has ever written the table it
 * reads, so every scrapped unit has been costed at nothing.
 *
 * `product_costs` is a baseline table (`1756000000000_baseline.js:1090`) and
 * this file adds nothing to it — no migration belongs to this ticket.
 *
 * Everything cost-rates.js's header says about shape applies here unchanged:
 * administrator-only writes, readable by any active Account, nothing deleted,
 * and history kept through the table's own `effective_from`/`effective_to`
 * rather than overwritten, so a cost reported for March stays what it was in
 * March. The overlap rule is the database's — `product_costs_no_overlap`, an
 * EXCLUDE constraint over (product, period) — and `23P01` is turned into a
 * clean 400 naming the conflict rather than re-spelled here.
 *
 * It is a shorter file than cost-rates.js for one reason: a product cost's key
 * is the Product alone, where a cost rate's is a polymorphic scope and a rate
 * type, so there is no scope resolution to do.
 *
 * `products` is the Quality Module's table and is joined directly, which
 * ADR-0006 allows in so many words: Modules are code seams, not data seams, and
 * a cross-Module *read* is an ordinary SQL join. Nothing here requires another
 * Module. The catalogue lives in People with its sibling because the two are
 * one job — the money the Platform costs things at — and splitting them would
 * leave scrap unpriced while rework is priced (issue #252's own decision).
 *
 * No HTTP, no caller awareness: product-cost-routes.js owns authenticate,
 * requireActive, requireAdmin and the 404s.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

const PRODUCT_COST_COLUMNS = `
  pc.id,
  pc.product_id,
  p.code AS product_code,
  p.name AS product_name,
  pc.standard_cost,
  pc.currency,
  to_char(pc.effective_from, 'YYYY-MM-DD') AS effective_from,
  to_char(pc.effective_to, 'YYYY-MM-DD') AS effective_to,
  pc.note,
  pc.created_at,
  pc.updated_at`;

const PRODUCT_COST_FROM = `
  FROM product_costs pc
  JOIN products p ON p.id = pc.product_id`;

function toProductCost(row) {
  return {
    id: row.id,
    productId: row.product_id,
    productCode: row.product_code,
    productName: row.product_name,
    standardCost: Number(row.standard_cost),
    currency: row.currency,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// The same calendar-date check cost-rates.js keeps, for the same reason — see
// that file's own comment on why this Module duplicates it per file.
function requireDateString(field, value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw httpError(400, `${field} must be a YYYY-MM-DD date`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw httpError(400, `${field} must be a valid calendar date`);
  }
}

function requireStandardCost(value) {
  const cost = Number(value);
  if (value === null || value === undefined || value === '' || !Number.isFinite(cost) || cost < 0) {
    throw httpError(400, 'standardCost must be a number greater than or equal to zero');
  }
  return cost;
}

function normaliseCurrency(value) {
  if (value === undefined || value === null || value === '') return 'USD';
  const currency = String(value).trim().toUpperCase();
  if (currency.length !== 3) {
    throw httpError(400, 'currency must be a three-letter code');
  }
  return currency;
}

function requirePeriod(effectiveFrom, effectiveTo) {
  if (effectiveTo !== null && effectiveTo <= effectiveFrom) {
    throw httpError(400, 'effectiveTo must be after effectiveFrom');
  }
}

async function requireKnownProduct(productId) {
  const { rows } = await getPool().query('SELECT id FROM products WHERE id = $1', [productId]);
  if (!rows[0]) throw httpError(404, 'productId does not name an existing Product');
}

// The refusal an overlapping period gets — `product_costs_no_overlap`'s own
// 23P01, named rather than echoed. See cost-rates.js's costRateOverlaps.
function productCostOverlaps({ effectiveFrom, effectiveTo }) {
  const period = effectiveTo === null ? `${effectiveFrom} onward` : `${effectiveFrom} to ${effectiveTo}`;
  return httpError(
    400,
    `A standard cost for this Product already covers part of ${period}. ` +
      'Close that period before opening a new one — two costs for one day would give the cost views two answers.',
    'PRODUCT_COST_PERIOD_OVERLAP'
  );
}

function mapProductCostWriteError(error) {
  if (error.code === '23514') {
    return httpError(
      400,
      'That standard cost was refused by the database: a field is outside the set of values it accepts'
    );
  }
  return error;
}

// The whole catalogue, history included — see listCostRates for why nothing is
// filtered away. Ordered by Product code, then newest period first.
async function listProductCosts() {
  const { rows } = await getPool().query(
    `SELECT ${PRODUCT_COST_COLUMNS}
     ${PRODUCT_COST_FROM}
     ORDER BY p.code, pc.effective_from DESC`
  );
  return rows.map(toProductCost);
}

// The Products a standard cost may be recorded against — the known set the
// catalogue's own form picks from rather than typing an id (ADR-0023). Active
// rows only: a cost is not newly recorded against a Product the plant has
// retired, while a cost already on one stays readable through listProductCosts'
// own join.
//
// This is deliberately a narrow projection of `products` on People's side rather
// than a call into Quality: ADR-0006's "Modules are code seams, not data seams"
// is what already lets this file join `products` for the catalogue's own rows,
// and a cross-Module *read* is an ordinary SQL join. Nothing here requires
// another Module, and Quality's own `GET /api/quality/products` — a wider row
// shape, with its own write surface beside it — is untouched.
async function listCostableProducts() {
  const { rows } = await getPool().query(
    `SELECT id, code, name FROM products WHERE is_active ORDER BY code`
  );
  return rows.map((row) => ({ id: row.id, code: row.code, name: row.name }));
}

async function findProductCost(id) {
  if (id === null) throw notFound('Product standard cost');
  const { rows } = await getPool().query(
    `SELECT ${PRODUCT_COST_COLUMNS} ${PRODUCT_COST_FROM} WHERE pc.id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Product standard cost');
  return toProductCost(rows[0]);
}

async function createProductCost(input, accountId) {
  const { productId, standardCost, currency, effectiveFrom, effectiveTo, note } = input ?? {};

  const parsedProductId = parseId(productId);
  if (parsedProductId === null) {
    throw httpError(400, 'productId must be a valid Product id');
  }
  await requireKnownProduct(parsedProductId); // 404s if it names nothing.

  const parsedCost = requireStandardCost(standardCost);
  const parsedCurrency = normaliseCurrency(currency);
  requireDateString('effectiveFrom', effectiveFrom);
  const parsedEffectiveTo =
    effectiveTo === undefined || effectiveTo === null || effectiveTo === '' ? null : effectiveTo;
  if (parsedEffectiveTo !== null) requireDateString('effectiveTo', parsedEffectiveTo);
  requirePeriod(effectiveFrom, parsedEffectiveTo);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO product_costs
             (product_id, standard_cost, currency, effective_from, effective_to, note)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING *
         )
         SELECT ${PRODUCT_COST_COLUMNS}
           FROM inserted pc
           JOIN products p ON p.id = pc.product_id`,
        [
          parsedProductId,
          parsedCost,
          parsedCurrency,
          effectiveFrom,
          parsedEffectiveTo,
          note ?? null
        ]
      );
      return toProductCost(row);
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw productCostOverlaps({ effectiveFrom, effectiveTo: parsedEffectiveTo });
    }
    throw mapProductCostWriteError(error);
  }
}

// The Product is absent on purpose: it is the key `product_standard_cost` finds
// a cost by, so rewriting it would move a whole price history onto a different
// Product. That is a new cost, not a correction — the same rule cost-rates.js
// keeps for a rate's scope.
const PRODUCT_COST_WRITABLE_COLUMNS = {
  standardCost: 'standard_cost',
  currency: 'currency',
  effectiveFrom: 'effective_from',
  effectiveTo: 'effective_to',
  note: 'note'
};

async function updateProductCost(id, input, accountId) {
  const existing = await findProductCost(id); // 404s if it does not exist.
  const body = input ?? {};

  if (Object.prototype.hasOwnProperty.call(body, 'productId')) {
    throw httpError(
      400,
      'productId cannot be corrected on a standard cost — record a cost against the other Product instead'
    );
  }

  const sets = [];
  const params = [];
  let effectiveFrom = existing.effectiveFrom;
  let effectiveTo = existing.effectiveTo;

  for (const [key, column] of Object.entries(PRODUCT_COST_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'standardCost') value = requireStandardCost(value);
    if (key === 'currency') value = normaliseCurrency(value);
    if (key === 'effectiveFrom') {
      requireDateString('effectiveFrom', value);
      effectiveFrom = value;
    }
    if (key === 'effectiveTo') {
      value = value === null || value === '' ? null : value;
      if (value !== null) requireDateString('effectiveTo', value);
      effectiveTo = value;
    }
    if (key === 'note' && value !== null) value = String(value);

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  requirePeriod(effectiveFrom, effectiveTo);

  if (sets.length === 0) return existing;

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE product_costs SET ${sets.join(', ')} WHERE id = $${params.length}`,
        params
      );
      const { rows: [row] } = await client.query(
        `SELECT ${PRODUCT_COST_COLUMNS} ${PRODUCT_COST_FROM} WHERE pc.id = $1`,
        [id]
      );
      return toProductCost(row);
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw productCostOverlaps({ effectiveFrom, effectiveTo });
    }
    throw mapProductCostWriteError(error);
  }
}

// A new cost from a given date: the old row is closed and a new one opened, in
// one transaction. See reviseCostRate for the full reasoning — it is the same
// act, on the table `product_standard_cost` reads.
async function reviseProductCost(id, input, accountId) {
  const existing = await findProductCost(id); // 404s if it does not exist.
  const { standardCost, currency, effectiveFrom, note } = input ?? {};

  const parsedCost = requireStandardCost(standardCost);
  const parsedCurrency = currency === undefined ? existing.currency : normaliseCurrency(currency);
  requireDateString('effectiveFrom', effectiveFrom);

  if (effectiveFrom <= existing.effectiveFrom) {
    throw httpError(
      400,
      `effectiveFrom must be after ${existing.effectiveFrom}, the day the standard cost being revised takes effect`
    );
  }
  if (existing.effectiveTo !== null && effectiveFrom >= existing.effectiveTo) {
    throw httpError(
      400,
      `this standard cost already ended on ${existing.effectiveTo}, so there is nothing to revise from ${effectiveFrom}`
    );
  }

  try {
    return await withActor(accountId, async (client) => {
      await client.query('SELECT id FROM product_costs WHERE id = $1 FOR UPDATE', [id]);
      await client.query('UPDATE product_costs SET effective_to = $1 WHERE id = $2', [
        effectiveFrom,
        id
      ]);
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO product_costs
             (product_id, standard_cost, currency, effective_from, effective_to, note)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING *
         )
         SELECT ${PRODUCT_COST_COLUMNS}
           FROM inserted pc
           JOIN products p ON p.id = pc.product_id`,
        [
          existing.productId,
          parsedCost,
          parsedCurrency,
          effectiveFrom,
          existing.effectiveTo,
          note ?? null
        ]
      );
      const { rows: [closedRow] } = await client.query(
        `SELECT ${PRODUCT_COST_COLUMNS} ${PRODUCT_COST_FROM} WHERE pc.id = $1`,
        [id]
      );
      return { closed: toProductCost(closedRow), opened: toProductCost(row) };
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw productCostOverlaps({ effectiveFrom, effectiveTo: existing.effectiveTo });
    }
    throw mapProductCostWriteError(error);
  }
}

// Deliberately no `resolveProductCost` to match cost-rates.js's
// `resolveCostRate`. That read exists because `resolve_cost_rate` implements a
// *fallback rule* — asset, then ancestor Org Unit, then Site — which is
// genuinely invisible from the catalogue and would otherwise be guessed at.
// `product_standard_cost` has no fallback: it is the one row for that Product
// covering that day, which the catalogue below already shows. Issue #252 asks
// for a resolution read of a rate and nothing more.

module.exports = {
  listProductCosts,
  listCostableProducts,
  findProductCost,
  createProductCost,
  updateProductCost,
  reviseProductCost
};
