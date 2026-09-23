/*
 * Quality's contribution to the tier board's KPI registry (issue #216).
 *
 * The registry was made composable by issue #202: each Module's entry point
 * contributes its own entries and src/index.js — where the application composes
 * its Modules — spreads them into the one registry the board is handed. This
 * file is Quality's half, and it is the whole of the coupling the board costs
 * either Module: nothing in `maintenance` changes, and neither Module requires
 * the other (ADR-0006's boundary check is what enforces that).
 *
 * WHAT EACH ENTRY CLAIMS, AND WHAT IS DELIBERATELY LEFT OUT
 * --------------------------------------------------------
 * Five codes, which are every Quality-pillar number this Platform's own records
 * can answer today:
 *
 *   - `QUA_OPEN_NC` counts the Non-conformances that are open or contained and
 *     not cancelled, at the chosen Org Unit and everything beneath it.
 *   - `QUA_OVERDUE_CAPA` counts the CAPAs past their due date, or whose
 *     effectiveness check has fallen due — the same two clauses
 *     `actions.js`'s own CAPA register uses (`CAPA_CHECK_OVERDUE` plus the due
 *     date), with the same live-status condition: a closed investigation is not
 *     a worklist.
 *   - `QUA_COMPLAINTS` counts the customer complaints received in the period,
 *     excluding those rejected as unfounded — the definition's own formula, and
 *     the same filter the baseline's `v_quality_ppm` applies.
 *   - `COST_COPQ` and `COST_SCRAP` read the baseline's own
 *     `v_cost_of_poor_quality`: the scrap half is quantity x the standard cost
 *     in force on the day the defect was found, and the rework half is rework
 *     minutes x the resolved labour rate, both of them from recorded
 *     Dispositions. That view's own header carries the arithmetic; nothing is
 *     recomputed here — but a Disposition the Platform cannot put a price on
 *     makes the whole period `no_data` rather than a currency figure missing
 *     that price (issue #258, and this file's own "AN UNPRICED COST IS NOT A
 *     ZERO" section below).
 *
 * `QUA_FPY`, `QUA_INT_PPM`, `QUA_CUST_PPM` and `DEL_QUALITY_RATE` are
 * deliberately absent, and their absence is the point rather than an omission:
 * every one of them is a ratio against quantity produced, and there is no
 * Production Module — `production_counts` is written by nothing on this branch.
 * A number computed on a denominator that does not exist would be an invented
 * number, which is what this ticket's parent settles against; the board keeps
 * reporting `no_data` for them, as it did before.
 *
 * WHY AN ENTRY'S SOURCE IS SOMETIMES SQL RATHER THAN A VIEW NAME
 * --------------------------------------------------------------
 * `maintenance/kpi-registry.js`'s header describes the shape: each entry ties a
 * KPI code to `{ view, valueColumn | ratio, dateColumn, orgUnitColumn }`, and
 * board.js reads it as `FROM <view> v`, rolls the matching rows up the Org Unit
 * tree the way the definition's `aggregation` says, and filters them by
 * `dateColumn` when the definition is a period measure. For Maintenance every
 * source is a baseline reporting view, and the two Cost entries here read one
 * too — through a `compute` function of their own rather than through that
 * generic shape, for the reason the "AN UNPRICED COST IS NOT A ZERO" section
 * below gives. The two Quality *counts* cannot be, and the reason is the shape
 * the counts have: what the board rolls up is one row per Org Unit — a count of
 * that Org Unit's own records — and no baseline view carries a per-Org-Unit row
 * for either, the Quality pillar's own views being the production-count ones
 * this Module does not claim. So those two entries name a derived table — a
 * subquery in the `view` slot, which is the same thing board.js means by "view":
 * something aliased `v` with the columns the entry names. It is computed on read
 * like every other number on the board, it lives in this Module's own
 * contribution, and it changes nothing in `maintenance`.
 *
 * A SNAPSHOT HAS NO PERIOD, AND ROLLS UP BY SUMMING
 * ------------------------------------------------
 * Open Non-conformances and overdue CAPAs are states rather than period
 * measures: there is no "open Non-conformances for last Tuesday". Both entries
 * therefore carry `dateColumn: null`, so their rows are not narrowed by the
 * period at all and a board for any period reports the state as it stands —
 * exactly how Maintenance's own snapshot KPI (`MNT_BACKLOG`) behaves. What
 * makes that roll up is the aggregation: the rows are per-Org-Unit counts, so
 * SUM over the chosen Org Unit and everything beneath it IS the subtree total.
 * The baseline seeds both of these definitions with `aggregation = 'last'`,
 * which board.js reads as "one row's value" and which cannot roll anything up —
 * so migration 1800600000000 corrects that one metadata value for these two
 * codes, and its own header argues why that is the whole of the change. The
 * three period measures below are untouched by it: complaints and both Cost
 * entries are `sum` over dated rows already.
 *
 * A ZERO IS A MEASUREMENT, AND NO ROWS ARE NOT
 * --------------------------------------------
 * Both snapshot tables are LEFT JOINs out of `org_units`, so an Org Unit with
 * nothing open reports `0` — a real answer, and the one a quiet plant wants on
 * its board — rather than disappearing into `no_data`. The period measures
 * (complaints, and both Cost entries) keep the views' own behaviour: a period
 * with no events reports `no_data`, exactly as `MNT_COST` does for a month with
 * no work.
 *
 * AN UNPRICED COST IS NOT A ZERO (issue #258)
 * -------------------------------------------
 * `v_cost_of_poor_quality` prices its two halves through two lookups, each
 * wrapped in the view's own `COALESCE(..., 0)`: the scrap half multiplies the
 * Disposition's quantity by `product_standard_cost(product_id, cost_date)`, and
 * the rework half multiplies rework minutes by `resolve_cost_rate(...,
 * 'rework_labor_per_hour', ...)` falling back to `'labor_per_hour'`. Nothing in
 * this Platform writes `product_costs` or `cost_rates` — there is no route, no
 * service, no Screen and no import for either, and building one is issue #252,
 * deliberately not depended on here. So on a Site that records scrap and rework
 * faithfully, both lookups resolve to nothing, the view's `COALESCE` turns each
 * into `0`, and the board would report a currency figure of `0` for a period
 * that in fact cost real money. That zero would be presented exactly like a
 * measured number — green against any `lower_better` target, on a Pillar whose
 * whole job is to be acted on.
 *
 * That is the failure `safety/kpi-registry.js` and this file's own header
 * already refuse for a missing denominator, in the same words: a number
 * computed on a price that does not exist is an invented number, and the
 * board's contract is to answer `no_data` instead. So: **where a recorded
 * Disposition cannot be priced, the KPI reports `no_data`.**
 *
 * NOTHING RECORDED IS NOT THE SAME AS NOTHING PRICEABLE
 * ------------------------------------------------------
 * The two states are kept apart deliberately. A period with no Disposition and
 * no claim at all produces no row in the view, and the answer is unchanged from
 * before this ticket — `no_data`, from an absence of rows, exactly as
 * `QUA_COMPLAINTS` and `MNT_COST` answer for a quiet period. A period whose
 * rows exist but cannot be priced is a different sentence — "this cost money
 * and the Platform cannot say how much" — and it answers `no_data` too, but for
 * the reason below rather than by accident of there being nothing to add up.
 * Neither state is ever widened into the other: a quiet period is not turned
 * into a blocked one, and a blocked one is not quietly turned into `0`.
 *
 * A Disposition that could not have cost anything is not unpriced. `rework` is
 * the only type carrying `rework_minutes` (the baseline's own
 * `quality_dispositions_rework_only` CHECK), and a rework of zero minutes
 * contributes `0 * rate` whatever the rate turns out to be — there is nothing
 * to look up, so a missing labour rate does not block it. A `scrap` row always
 * has `quantity > 0` (the table's own CHECK), so it always needs a standard
 * cost; one whose Non-conformance names no Product, or whose Product has no
 * `product_costs` row in force on the cost date, is unpriced. The claims and
 * supplier-recovery halves of `total_copq` are recorded currency amounts on
 * `customer_complaints` and `supplier_ncrs` rather than anything resolved
 * through a rate, so they are never unpriced and never block.
 *
 * Each code is blocked only by what its own value is made of. `COST_SCRAP` is
 * the scrap slice, so only an unpriced `scrap` row blocks it; `COST_COPQ` is
 * the whole, so an unpriced `scrap` OR an unpriced `rework` row blocks it. A
 * period with priced scrap and an unpriceable rework therefore still reports a
 * scrap cost and reports `no_data` for the cost of poor quality, which is the
 * honest pair of answers: the slice is known, the whole is not.
 *
 * A PARTIALLY PRICED PERIOD IS `no_data`, NOT A FLOOR (issue #258)
 * ----------------------------------------------------------------
 * The choice issue #258 leaves open is what a period reports when some of its
 * rows price and some do not: `no_data` for the whole period, or the sum of
 * only what resolved. **This registry reports `no_data` for the whole period.**
 *
 * The precedent is ADR-0041's "Why not drop unconfirmed shifts from the
 * window", and the reasoning transfers without strain. There, a shift inside
 * the window with no confirmed sheet makes `SAF_TRIR`/`SAF_LTIFR` `no_data`
 * outright, because dropping it is not neutral — it produces "a wrong number
 * reported as a right one", and "a rate computed by quietly leaving out the
 * parts that are inconvenient is worse than no rate at all". A cost summed over
 * only the rows that happened to price is the same act with the same failure
 * direction, and a worse one for being currency: it is always low, never high,
 * so it cannot even be recognised as wrong by looking at it. The board offers
 * no way to say "at least this much" — `value` is a number and `status` is a
 * closed vocabulary (`green`/`amber`/`red`/`no_target`/`no_data`), so a partial
 * sum arrives indistinguishable from a complete one and is scored against the
 * KPI's `lower_better` target as if it were the whole cost. A plant whose
 * Products are half-priced would read a green Cost Pillar it had earned none
 * of, and nothing on the board would hint that the other half was missing. A
 * blank asks the question; a confidently low currency figure answers it wrongly.
 *
 * The obvious counter — that a floor is better than nothing, since some cost is
 * visibly worse than zero cost — is rejected for the same reason ADR-0041
 * rejects its own: the floor is not labelled as a floor anywhere it is read,
 * and an unlabelled floor is just a wrong number. The remedy for `no_data` here
 * is to price the Products and the rates (#252), which is a fixable, visible
 * state; the remedy for a plausible wrong number is nobody noticing for a year.
 *
 * WHY THESE TWO CARRY `compute` RATHER THAN `{ view, valueColumn }`
 * -----------------------------------------------------------------
 * The generic reader in board.js aggregates the source's rows as `SUM(v.<col>)`
 * over the subtree and the period, and `SUM` skips NULLs. So a derived table
 * that left an unpriced row's value NULL would express *exactly the option
 * rejected above* — price only what resolves — and could not express this one:
 * "any unpriced row anywhere in the subtree and the period blocks the whole
 * number" is an EXISTS over a different grain (one Disposition) than the grain
 * the board rolls up (one Org Unit per cost date), and a subquery in the `view`
 * slot cannot see the period or the subtree it is about to be filtered by in
 * order to test it. This is the same shape of limit `safety/kpi-registry.js`
 * records for its unconfirmed-shift rule, and board.js's `compute` escape hatch
 * is the documented answer to it. The board's request and response shape does
 * not change, this Module still contributes only entries, and nothing in
 * `maintenance` moves.
 *
 * And the baseline view is not touched. No migration accompanies this file:
 * `v_cost_of_poor_quality` is shared — `COST_DOWNTIME` and `COST_LABOUR` will
 * want their own reading of the same `COALESCE(..., 0)` problem, and
 * `views.test.js` asserts the view as it stands — so the distinction between a
 * zero and an unpriced row belongs in the KPI's own entry, which is the only
 * place that knows which slice of the view it is answering for.
 */

const { getPool } = require('../../platform/db');

// One row per Org Unit: how many Non-conformances are open or contained there.
// `quality_issues.status`'s own set is the baseline's — `open`, `contained`,
// `dispositioned`, `closed`, `cancelled` — and "open and contained,
// non-cancelled" is the ticket's own sentence, which `cancelled` being outside
// the pair already satisfies. The LEFT JOIN is what lets a quiet Org Unit say
// `0` rather than vanish from the source.
const OPEN_NONCONFORMANCES = `(
  SELECT ou.id                  AS org_unit_id,
         COUNT(qi.id)::numeric  AS open_count
    FROM org_units ou
    LEFT JOIN quality_issues qi
      ON qi.org_unit_id = ou.id
     AND qi.status IN ('open', 'contained')
   GROUP BY ou.id
)`;

// One row per Org Unit: how many CAPAs are past their due date, or have an
// effectiveness check that has fallen due and not been recorded. The status
// condition is the one `actions.js` states for its own register: a closed or
// cancelled investigation is not a worklist, and an effective check leaves the
// due date where it was.
const OVERDUE_CAPAS = `(
  SELECT ou.id                  AS org_unit_id,
         COUNT(c.id)::numeric   AS overdue_count
    FROM org_units ou
    LEFT JOIN capas c
      ON c.org_unit_id = ou.id
     AND c.status NOT IN ('closed', 'cancelled')
     AND (
       c.due_date < CURRENT_DATE
       OR (c.effectiveness_check_due_at IS NOT NULL
           AND c.effectiveness_check_due_at < CURRENT_DATE)
     )
   GROUP BY ou.id
)`;

// One row per Org Unit per production day on which a complaint was received, so
// the definition's own `sum` adds the period up. `plant_date` is the baseline's
// own ADR-0017 helper — the day the Site was in when the complaint arrived —
// which is what makes a complaint received at 23:30 belong to the shift that
// owns that moment rather than to the UTC date. A rejected complaint is
// excluded, the baseline's `v_quality_ppm` and the definition's formula text
// agreeing on it.
const COMPLAINTS_RECEIVED = `(
  SELECT cc.org_unit_id AS org_unit_id,
         plant_date(cc.org_unit_id, cc.received_at) AS production_date,
         COUNT(*)::numeric AS complaint_count
    FROM customer_complaints cc
   WHERE cc.org_unit_id IS NOT NULL
     AND cc.status <> 'rejected'
   GROUP BY cc.org_unit_id, plant_date(cc.org_unit_id, cc.received_at)
)`;

// A `scrap` Disposition the Platform cannot put a price on: `quantity > 0` is
// the table's own CHECK, so every scrap row needs a standard cost in force on
// its cost date, and a Non-conformance naming no Product resolves none either.
const UNPRICED_SCRAP = "d.disposition_type = 'scrap' AND d.standard_cost IS NULL";

// A `rework` Disposition that cost labour nobody has a rate for. Zero minutes
// is excluded on purpose: `0 * rate` is `0` whatever the rate is, so there is
// nothing to look up and nothing to block — see this file's header, "NOTHING
// RECORDED IS NOT THE SAME AS NOTHING PRICEABLE".
const UNPRICED_REWORK =
  "d.disposition_type = 'rework' AND d.rework_minutes > 0 AND d.labour_rate IS NULL";

// The whole of `COST_COPQ`/`COST_SCRAP`'s reading (issue #258) — see this
// file's header, "AN UNPRICED COST IS NOT A ZERO" and the two sections after
// it, for why these two carry `compute` rather than `{ view, valueColumn }`.
// `ctx` is exactly what board.js's `computeRegistryKpi` hands a `compute`
// entry: `{ siteId, orgUnit, period }`, with `orgUnit` null for a whole-Site
// board — `subtree` below then reads every Org Unit at the Site, matching how
// the generic reader treats a null `orgUnit` for the other three entries here.
//
// The value itself is still `v_cost_of_poor_quality`'s own, summed over the
// same subtree and the same period the generic reader would have used, with
// the same "no rows, or a null sum, is `no_data`" rule: a period nothing
// blocks reads exactly as it read before this ticket. What is added in front
// of it is the EXISTS the generic reader cannot express — the Dispositions
// behind those very rows, re-resolved through the baseline's own two pricing
// functions (never re-implementing what a rate or a standard cost means), with
// the view's `COALESCE(..., 0)` deliberately left off so an unresolved lookup
// stays NULL and can be told from a genuine zero.
async function computeCostOfPoorQuality({ siteId, orgUnit, period }, { valueColumn, unpriced }) {
  const { rows: [row] } = await getPool().query(
    `WITH subtree AS (
       SELECT id FROM org_units
        WHERE site_id = $1 AND ($2::ltree IS NULL OR path <@ $2::ltree)
     ),
     issues AS (
       -- The same bucket v_cost_of_poor_quality files a Non-conformance in:
       -- the shift instance's production day when there is one, plant_date
       -- otherwise (ADR-0017).
       SELECT qi.id, qi.org_unit_id, qi.asset_id, qi.product_id,
              COALESCE(si.production_date, plant_date(qi.org_unit_id, qi.detected_at)) AS cost_date
         FROM quality_issues qi
         LEFT JOIN shift_instances si ON si.id = qi.shift_instance_id
        WHERE qi.org_unit_id IN (SELECT id FROM subtree)
     ),
     dispositions AS (
       -- Every Disposition the period's rows are made of, beside whatever
       -- price it resolves. NULL here is "nothing resolved", which is the one
       -- fact the view's own COALESCE throws away.
       SELECT qd.disposition_type,
              qd.rework_minutes,
              product_standard_cost(i.product_id, i.cost_date) AS standard_cost,
              COALESCE(
                resolve_cost_rate(i.org_unit_id, i.asset_id, 'rework_labor_per_hour', i.cost_date),
                resolve_cost_rate(i.org_unit_id, i.asset_id, 'labor_per_hour', i.cost_date)
              ) AS labour_rate
         FROM quality_dispositions qd
         JOIN issues i ON i.id = qd.quality_issue_id
        WHERE i.cost_date BETWEEN $3::date AND $4::date
     ),
     totals AS (
       SELECT COUNT(*)::int             AS row_count,
              SUM(v.${valueColumn})::numeric AS value
         FROM v_cost_of_poor_quality v
        WHERE v.org_unit_id IN (SELECT id FROM subtree)
          AND v.cost_date BETWEEN $3::date AND $4::date
     )
     SELECT EXISTS (SELECT 1 FROM dispositions d WHERE ${unpriced}) AS unpriced,
            t.row_count,
            t.value
       FROM totals t`,
    [siteId, orgUnit ? orgUnit.path : null, period.start, period.end]
  );

  // A recorded cost nobody can price blocks the whole period — never a floor.
  if (row.unpriced) return null;
  if (row.row_count === 0 || row.value === null) return null;
  return Number(row.value);
}

// code -> how to read it. `valueColumn` is a column of the source the entry
// names, exactly as Maintenance's own entries are — see this file's header for
// why two of the five sources are derived tables rather than view names, and why
// the two snapshot entries carry no date column. The two Cost entries carry
// `compute` instead of either, board.js's own escape hatch for a `no_data` rule
// the `{ view, valueColumn }` shape cannot express (this file's header, "WHY
// THESE TWO CARRY `compute`").
const KPI_REGISTRY = {
  QUA_OPEN_NC: {
    view: OPEN_NONCONFORMANCES,
    valueColumn: 'open_count',
    dateColumn: null,
    orgUnitColumn: 'org_unit_id'
  },
  QUA_OVERDUE_CAPA: {
    view: OVERDUE_CAPAS,
    valueColumn: 'overdue_count',
    dateColumn: null,
    orgUnitColumn: 'org_unit_id'
  },
  QUA_COMPLAINTS: {
    view: COMPLAINTS_RECEIVED,
    valueColumn: 'complaint_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  // The baseline's own cost-of-poor-quality view, read as it stands: scrap at
  // the standard cost in force on the day the defect was found, rework at the
  // resolved labour rate, claims, less supplier recovery. `total_copq` is a
  // whole and `scrap_cost` is a slice of it — never added to it. The whole is
  // blocked by an unpriced Disposition of either kind; the slice only by an
  // unpriced scrap, because a labour rate is no part of what it reports.
  COST_COPQ: {
    compute: (ctx) => computeCostOfPoorQuality(ctx, {
      valueColumn: 'total_copq',
      unpriced: `(${UNPRICED_SCRAP}) OR (${UNPRICED_REWORK})`
    })
  },
  COST_SCRAP: {
    compute: (ctx) => computeCostOfPoorQuality(ctx, {
      valueColumn: 'scrap_cost',
      unpriced: UNPRICED_SCRAP
    })
  }
};

module.exports = KPI_REGISTRY;
