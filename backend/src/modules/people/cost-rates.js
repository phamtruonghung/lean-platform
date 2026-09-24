/*
 * The cost rate catalogue (issue #252) — the money the Platform costs things
 * at: a labour rate per hour, an overtime premium, a machine-downtime rate, an
 * overhead rate and a rework labour rate, each scoped to a Site, an Org Unit,
 * an asset or a cost centre, each with the date it takes effect.
 *
 * `cost_rates` is a baseline table (`1756000000000_baseline.js:2859`) and this
 * file adds nothing to it — no migration belongs to this ticket. Four baseline
 * views already resolve through `resolve_cost_rate` (the asset's own rate, then
 * the nearest ancestor Org Unit with one, then the Site), and nothing has ever
 * written the table, so every cost has resolved to nothing. This is the writing,
 * and nothing else.
 *
 * Maintained as a catalogue, the shape `job_roles`, `injury_types` and
 * `products` already established (ADR-0005's shared catalogue): administrator
 * -only writes, readable by any active Account, nothing deleted. What is
 * different from those three, and is the whole reason this file is longer than
 * `injury-types.js`, is that a cost rate is **versioned**: the table carries its
 * own `effective_from`/`effective_to`, every cost view resolves as of a date,
 * and a labour rate revised in October must not silently rewrite September's
 * cost of poor quality. So a correction that changes an amount for a new period
 * closes the old row and opens a new one (`reviseCostRate`), it never
 * overwrites; the old row stays readable and still resolves for earlier dates.
 *
 * **The overlap rule is the database's, not this file's.** Two rows for one
 * scope and rate type whose effective periods overlap would make
 * `resolve_cost_rate`'s answer depend on row order, and the baseline already
 * forbids it with an EXCLUDE constraint (`cost_rates_no_overlap`). Nothing here
 * re-spells that rule in JavaScript — `23P01` is caught and turned into a clean
 * 400 naming the conflict (`costRateOverlaps`), the same shape
 * `work-order-cost.js`'s `labourOverlaps` keeps for its own exclusion
 * constraint. A raw database message, which names tables and columns, never
 * reaches a caller.
 *
 * **The fallback rule is the database's too.** `resolveCostRate` below calls
 * `resolve_cost_rate(org_unit, asset, rate_type, at)` and returns what it
 * answers. It does not walk the Org Unit tree, and it does not know that an
 * asset beats a line which beats a Site — that lives in exactly one place, and
 * this read exists to make it visible rather than guessed at.
 *
 * It lives in People because People owns the Org Unit and cost-centre
 * vocabulary these rates are scoped by (issue #252's own decision: not a Module
 * of its own for two CRUD surfaces). The joins onto `assets` (Maintenance) and
 * `cost_centers` are ordinary cross-Module SQL, which ADR-0006 allows in so many
 * words — Modules are code seams, not data seams; nothing here requires another
 * Module.
 *
 * No HTTP, no caller awareness: cost-rate-routes.js owns authenticate,
 * requireActive, requireAdmin and the 404s.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// The schema's own four scope types and five rate types, verbatim from
// `cost_rates`' CHECK constraints. Both are chosen from these sets, never typed
// (ADR-0023), and a value outside them is refused here rather than left to the
// CHECK — so a caller is told which field was wrong and what it accepts.
const SCOPE_TYPES = ['site', 'org_unit', 'asset', 'cost_center'];
const RATE_TYPES = [
  'labor_per_hour',
  'overtime_premium_multiplier',
  'machine_downtime_per_hour',
  'overhead_per_hour',
  'rework_labor_per_hour'
];

// What a scope type is called in a refusal, and the table its `scope_id` names.
// `cost_rates.scope_id` is deliberately polymorphic in the baseline — no
// foreign key can point at four tables — so existence is resolved here instead,
// and a rate scoped to something that does not exist (which would resolve to
// nothing, for ever, silently) is refused at the door.
const SCOPES = {
  site: { table: 'sites', label: 'Site' },
  org_unit: { table: 'org_units', label: 'Org Unit' },
  asset: { table: 'assets', label: 'Asset' },
  cost_center: { table: 'cost_centers', label: 'cost centre' }
};

const COST_RATE_COLUMNS = `
  cr.id,
  cr.scope_type,
  cr.scope_id,
  COALESCE(s.name, ou.name, a.name, cc.name) AS scope_name,
  cr.rate_type,
  cr.amount,
  cr.currency,
  to_char(cr.effective_from, 'YYYY-MM-DD') AS effective_from,
  to_char(cr.effective_to, 'YYYY-MM-DD') AS effective_to,
  cr.note,
  cr.created_at,
  cr.updated_at`;

// One join per scope type, each keyed on `scope_type` as well as the id so a
// Site id 7 can never pick up the Org Unit that happens to be id 7.
const COST_RATE_FROM = `
  FROM cost_rates cr
  LEFT JOIN sites s        ON cr.scope_type = 'site'        AND s.id  = cr.scope_id
  LEFT JOIN org_units ou   ON cr.scope_type = 'org_unit'    AND ou.id = cr.scope_id
  LEFT JOIN assets a       ON cr.scope_type = 'asset'       AND a.id  = cr.scope_id
  LEFT JOIN cost_centers cc ON cr.scope_type = 'cost_center' AND cc.id = cr.scope_id`;

function toCostRate(row) {
  return {
    id: row.id,
    scopeType: row.scope_type,
    scopeId: row.scope_id,
    // Null when the scoped record has since been deleted — the row is still
    // history worth reading, so this reports what it can rather than dropping it.
    scopeName: row.scope_name,
    rateType: row.rate_type,
    amount: Number(row.amount),
    currency: row.currency,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function requireChoice(field, value, allowed) {
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// A calendar date, not just a string shaped like one — the same check
// directory.js and skills.js each already keep for their own date fields (this
// Module duplicates it per file on purpose; errors.js is error plumbing, not a
// validation library).
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

// `amount` carries a currency figure for four of the five rate types and a
// dimensionless multiplier for the fifth (1.5 for time-and-a-half) — the
// baseline shares one column deliberately, and the KPI formulas know which is
// which. Only the schema's own `>= 0` is asserted here.
function requireAmount(value) {
  const amount = Number(value);
  if (value === null || value === undefined || value === '' || !Number.isFinite(amount) || amount < 0) {
    throw httpError(400, 'amount must be a number greater than or equal to zero');
  }
  return amount;
}

function normaliseCurrency(value) {
  if (value === undefined || value === null || value === '') return 'USD';
  const currency = String(value).trim().toUpperCase();
  if (currency.length !== 3) {
    throw httpError(400, 'currency must be a three-letter code');
  }
  return currency;
}

// `effective_to` is exclusive and NULL means "still current" — the same reading
// `cost_rates_range_valid` enforces. Checked here so the ordinary mistake gets a
// sentence rather than a mapped constraint violation.
function requirePeriod(effectiveFrom, effectiveTo) {
  if (effectiveTo !== null && effectiveTo <= effectiveFrom) {
    throw httpError(400, 'effectiveTo must be after effectiveFrom');
  }
}

// The scope named on a write must exist. A 404, not a 400: it is the same
// "existence before anything else" shape `createAssignment`'s own orgUnitId
// already has, and `scopeId does not name an existing X` is what a caller can
// act on.
async function requireKnownScope(scopeType, scopeId) {
  const { table, label } = SCOPES[scopeType];
  const { rows } = await getPool().query(`SELECT id FROM ${table} WHERE id = $1`, [scopeId]);
  if (!rows[0]) throw httpError(404, `scopeId does not name an existing ${label}`);
}

// The refusal an overlapping period gets, built after the losing transaction
// has rolled back. `cost_rates_no_overlap` is the schema's own guard against two
// answers for one day, and it fires as 23P01; this names the scope, the rate
// type and the period that was asked for, which is what makes it actionable
// without re-spelling the constraint's rule in JavaScript.
function costRateOverlaps({ scopeType, rateType, effectiveFrom, effectiveTo }) {
  const period = effectiveTo === null ? `${effectiveFrom} onward` : `${effectiveFrom} to ${effectiveTo}`;
  return httpError(
    400,
    `A ${rateType} rate for this ${SCOPES[scopeType].label} already covers part of ${period}. ` +
      'Close that period before opening a new one — two rates for one day would give the cost views two answers.',
    'COST_RATE_PERIOD_OVERLAP'
  );
}

// Every other way a write against `cost_rates` can fail that is worth a clean
// 4xx rather than a 500. 23514 is one of the table's own CHECKs (a negative
// amount, a three-letter currency, a backwards period) — each is already
// refused above with its own sentence, so reaching here means a value this file
// did not think to check, and it is reported as such rather than echoed raw.
// Anything else is a genuine failure and is rethrown as-is.
function mapCostRateWriteError(error) {
  if (error.code === '23514') {
    return httpError(
      400,
      'That cost rate was refused by the database: a field is outside the set of values it accepts'
    );
  }
  return error;
}

// The whole catalogue, history included — a closed period is exactly what makes
// a historical cost reproducible, so nothing is filtered away. Ordered the way a
// person reads it: by rate type, then by scope, then newest period first.
//
// No Org Unit filter and no Grant filter: a cost rate is shared reference data
// (ADR-0005) and reading it is not acting anywhere (ADR-0009). Who may *write*
// one is cost-rate-routes.js's question.
async function listCostRates() {
  const { rows } = await getPool().query(
    `SELECT ${COST_RATE_COLUMNS}
     ${COST_RATE_FROM}
     ORDER BY cr.rate_type, cr.scope_type, cr.scope_id, cr.effective_from DESC`
  );
  return rows.map(toCostRate);
}

// Everything a rate may be scoped to, in one list — the known set a scope is
// chosen from rather than typed (ADR-0023). Four `SELECT`s over four tables,
// each carrying its own scope type, so the client picks a *scope* and the
// `scopeType`/`scopeId` pair falls out of the pick rather than being assembled
// from two independent controls that can disagree.
//
// Retired rows are excluded — a new rate is not set against a decommissioned
// press — while a rate already scoped to one stays perfectly readable, because
// listCostRates resolves its name through its own join rather than through this.
//
// Unbounded, like `GET /api/quality/products` and `GET /api/maintenance/sites/
// :id/assets` already are: this is a catalogue read, and AppSearchField does its
// own bounding at ten rendered suggestions (ADR-0026).
async function listCostRateScopes() {
  const { rows } = await getPool().query(`
    SELECT 'site' AS scope_type, s.id, s.code, s.name, s.name AS site_name
      FROM sites s
     WHERE s.is_active
    UNION ALL
    SELECT 'org_unit', ou.id, ou.code, ou.name, s.name
      FROM org_units ou
      JOIN sites s ON s.id = ou.site_id
     WHERE ou.is_active
    UNION ALL
    SELECT 'asset', a.id, a.code, a.name, s.name
      FROM assets a
      JOIN org_units ou ON ou.id = a.org_unit_id
      JOIN sites s ON s.id = ou.site_id
     WHERE a.is_active
    UNION ALL
    SELECT 'cost_center', cc.id, cc.code, cc.name, s.name
      FROM cost_centers cc
      JOIN sites s ON s.id = cc.site_id
     WHERE cc.is_active
    ORDER BY 1, 5, 4
  `);
  return rows.map((row) => ({
    scopeType: row.scope_type,
    id: row.id,
    code: row.code,
    name: row.name,
    siteName: row.site_name
  }));
}

// Mirrors injury-types.findInjuryType: a null id and "no such row" are both a
// 404, one query.
async function findCostRate(id) {
  if (id === null) throw notFound('Cost rate');
  const { rows } = await getPool().query(
    `SELECT ${COST_RATE_COLUMNS} ${COST_RATE_FROM} WHERE cr.id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Cost rate');
  return toCostRate(rows[0]);
}

async function createCostRate(input, accountId) {
  const { scopeType, scopeId, rateType, amount, currency, effectiveFrom, effectiveTo, note } =
    input ?? {};

  requireChoice('scopeType', scopeType, SCOPE_TYPES);
  requireChoice('rateType', rateType, RATE_TYPES);

  const parsedScopeId = parseId(scopeId);
  if (parsedScopeId === null) {
    throw httpError(400, 'scopeId must be a valid id');
  }
  await requireKnownScope(scopeType, parsedScopeId); // 404s if it names nothing.

  const parsedAmount = requireAmount(amount);
  const parsedCurrency = normaliseCurrency(currency);
  requireDateString('effectiveFrom', effectiveFrom);
  const parsedEffectiveTo = effectiveTo === undefined || effectiveTo === null || effectiveTo === ''
    ? null
    : effectiveTo;
  if (parsedEffectiveTo !== null) requireDateString('effectiveTo', parsedEffectiveTo);
  requirePeriod(effectiveFrom, parsedEffectiveTo);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO cost_rates
             (scope_type, scope_id, rate_type, amount, currency, effective_from, effective_to, note)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING *
         )
         SELECT ${COST_RATE_COLUMNS}
           FROM inserted cr
           LEFT JOIN sites s        ON cr.scope_type = 'site'        AND s.id  = cr.scope_id
           LEFT JOIN org_units ou   ON cr.scope_type = 'org_unit'    AND ou.id = cr.scope_id
           LEFT JOIN assets a       ON cr.scope_type = 'asset'       AND a.id  = cr.scope_id
           LEFT JOIN cost_centers cc ON cr.scope_type = 'cost_center' AND cc.id = cr.scope_id`,
        [
          scopeType,
          parsedScopeId,
          rateType,
          parsedAmount,
          parsedCurrency,
          effectiveFrom,
          parsedEffectiveTo,
          note ?? null
        ]
      );
      return toCostRate(row);
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw costRateOverlaps({
        scopeType,
        rateType,
        effectiveFrom,
        effectiveTo: parsedEffectiveTo
      });
    }
    throw mapCostRateWriteError(error);
  }
}

// What a correction may touch. Scope and rate type are deliberately absent:
// together they are the key `resolve_cost_rate` finds a rate by, so rewriting
// either would silently move a rate to a different place in the tree and change
// what every historical cost view resolves. That is a new rate, not a
// correction — the same rule `injury_types` keeps for its code, which an
// incident's own report quotes.
const COST_RATE_WRITABLE_COLUMNS = {
  amount: 'amount',
  currency: 'currency',
  effectiveFrom: 'effective_from',
  effectiveTo: 'effective_to',
  note: 'note'
};

const COST_RATE_KEY_FIELDS = ['scopeType', 'scopeId', 'rateType'];

// Correcting a rate in place: a mistyped amount, a wrong currency, a period
// that started on the wrong day, and — setting `effectiveTo` — closing it.
// `effectiveTo: null` reopens one. An absent key never touches its column, so a
// one-field PATCH cannot blank the others (the hasOwnProperty idiom every
// catalogue in this Module keeps).
//
// This is not how a new amount is recorded: see reviseCostRate below.
async function updateCostRate(id, input, accountId) {
  const existing = await findCostRate(id); // 404s if it does not exist.
  const body = input ?? {};

  for (const field of COST_RATE_KEY_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(body, field)) {
      throw httpError(
        400,
        `${field} cannot be corrected on a cost rate — create a rate for the new scope instead`
      );
    }
  }

  const sets = [];
  const params = [];
  let effectiveFrom = existing.effectiveFrom;
  let effectiveTo = existing.effectiveTo;

  for (const [key, column] of Object.entries(COST_RATE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'amount') value = requireAmount(value);
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

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than an UPDATE
    // with an empty SET list (which Postgres would reject outright).
    return existing;
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE cost_rates SET ${sets.join(', ')} WHERE id = $${params.length}`,
        params
      );
      const { rows: [row] } = await client.query(
        `SELECT ${COST_RATE_COLUMNS} ${COST_RATE_FROM} WHERE cr.id = $1`,
        [id]
      );
      return toCostRate(row);
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw costRateOverlaps({
        scopeType: existing.scopeType,
        rateType: existing.rateType,
        effectiveFrom,
        effectiveTo
      });
    }
    throw mapCostRateWriteError(error);
  }
}

// A new amount from a given date — the correction that actually happens in a
// plant, and the one the ticket names: the old row is closed (`effective_to` set
// to the day the new one starts) and a new row opened for the same scope and
// rate type. One transaction, so the pair can never be half-applied and leave a
// day with no rate at all; the old row keeps its own id, amount and
// `effective_from`, so a cost view asked for an earlier date still resolves the
// old amount.
//
// The existing row is locked FOR UPDATE first, so two concurrent revisions of
// one rate cannot both read it as still open. The INSERT is still left to the
// EXCLUDE constraint for the case this cannot see (a later period already on
// file) — the rule stays the database's.
async function reviseCostRate(id, input, accountId) {
  const existing = await findCostRate(id); // 404s if it does not exist.
  const { amount, currency, effectiveFrom, note } = input ?? {};

  const parsedAmount = requireAmount(amount);
  const parsedCurrency = currency === undefined ? existing.currency : normaliseCurrency(currency);
  requireDateString('effectiveFrom', effectiveFrom);

  // String comparison on YYYY-MM-DD is calendar comparison, which is why every
  // date in this file stays a string rather than becoming a `Date`.
  if (effectiveFrom <= existing.effectiveFrom) {
    throw httpError(
      400,
      `effectiveFrom must be after ${existing.effectiveFrom}, the day the rate being revised takes effect`
    );
  }
  if (existing.effectiveTo !== null && effectiveFrom >= existing.effectiveTo) {
    throw httpError(
      400,
      `this cost rate already ended on ${existing.effectiveTo}, so there is nothing to revise from ${effectiveFrom}`
    );
  }

  try {
    return await withActor(accountId, async (client) => {
      await client.query('SELECT id FROM cost_rates WHERE id = $1 FOR UPDATE', [id]);
      await client.query('UPDATE cost_rates SET effective_to = $1 WHERE id = $2', [
        effectiveFrom,
        id
      ]);
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO cost_rates
             (scope_type, scope_id, rate_type, amount, currency, effective_from, effective_to, note)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING *
         )
         SELECT ${COST_RATE_COLUMNS}
           FROM inserted cr
           LEFT JOIN sites s        ON cr.scope_type = 'site'        AND s.id  = cr.scope_id
           LEFT JOIN org_units ou   ON cr.scope_type = 'org_unit'    AND ou.id = cr.scope_id
           LEFT JOIN assets a       ON cr.scope_type = 'asset'       AND a.id  = cr.scope_id
           LEFT JOIN cost_centers cc ON cr.scope_type = 'cost_center' AND cc.id = cr.scope_id`,
        [
          existing.scopeType,
          existing.scopeId,
          existing.rateType,
          parsedAmount,
          parsedCurrency,
          effectiveFrom,
          existing.effectiveTo,
          note ?? null
        ]
      );
      const { rows: [closedRow] } = await client.query(
        `SELECT ${COST_RATE_COLUMNS} ${COST_RATE_FROM} WHERE cr.id = $1`,
        [id]
      );
      return { closed: toCostRate(closedRow), opened: toCostRate(row) };
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw costRateOverlaps({
        scopeType: existing.scopeType,
        rateType: existing.rateType,
        effectiveFrom,
        effectiveTo: existing.effectiveTo
      });
    }
    throw mapCostRateWriteError(error);
  }
}

// What the cost views would resolve, asked directly. The fallback rule — the
// asset's own rate, then the nearest ancestor Org Unit with one, then the Site
// — is `resolve_cost_rate`'s, and this calls it rather than re-spelling it:
// four baseline views go through the same function, so an answer here is the
// answer a KPI gets, by construction.
//
// The Org Unit is resolved first so an unknown one is a 404 rather than a null
// amount indistinguishable from "no rate is set".
async function resolveCostRate({ orgUnitId, assetId, rateType, at } = {}) {
  requireChoice('rateType', rateType, RATE_TYPES);

  const parsedOrgUnitId = parseId(orgUnitId);
  if (parsedOrgUnitId === null) {
    throw httpError(400, 'orgUnitId must be a valid Org Unit id');
  }
  const { rows: orgUnitRows } = await getPool().query('SELECT id FROM org_units WHERE id = $1', [
    parsedOrgUnitId
  ]);
  if (!orgUnitRows[0]) throw notFound('Org Unit');

  let parsedAssetId = null;
  if (assetId !== undefined && assetId !== null && assetId !== '') {
    parsedAssetId = parseId(assetId);
    if (parsedAssetId === null) {
      throw httpError(400, 'assetId must be a valid Asset id');
    }
    const { rows: assetRows } = await getPool().query('SELECT id FROM assets WHERE id = $1', [
      parsedAssetId
    ]);
    if (!assetRows[0]) throw notFound('Asset');
  }

  requireDateString('at', at);

  const { rows: [row] } = await getPool().query(
    'SELECT resolve_cost_rate($1, $2, $3, $4::date) AS amount',
    [parsedOrgUnitId, parsedAssetId, rateType, at]
  );

  return {
    orgUnitId: parsedOrgUnitId,
    assetId: parsedAssetId,
    rateType,
    at,
    // Null means the plant has set no rate that reaches here on that day — an
    // honest "nothing", not a zero. #258 is the ticket about what a view does
    // with that; this read simply reports it.
    amount: row.amount === null ? null : Number(row.amount)
  };
}

module.exports = {
  SCOPE_TYPES,
  RATE_TYPES,
  listCostRates,
  listCostRateScopes,
  findCostRate,
  createCostRate,
  updateCostRate,
  reviseCostRate,
  resolveCostRate
};
