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
 *     recomputed here.
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
 * source is a baseline reporting view, and for the two Cost entries here it is
 * one too. The two Quality *counts* cannot be, and the reason is the shape the
 * counts have: what the board rolls up is one row per Org Unit — a count of
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
 */

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

// code -> how to read it. `valueColumn` is a column of the source the entry
// names, exactly as Maintenance's own entries are — see this file's header for
// why two of the five sources are derived tables rather than view names, and why
// the two snapshot entries carry no date column.
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
  // The baseline's own cost-of-poor-quality view, used as it stands: scrap at
  // the standard cost in force on the day the defect was found, rework at the
  // resolved labour rate, claims, less supplier recovery. `total_copq` is a
  // whole and `scrap_cost` is a slice of it — never added to it.
  COST_COPQ: {
    view: 'v_cost_of_poor_quality',
    valueColumn: 'total_copq',
    dateColumn: 'cost_date',
    orgUnitColumn: 'org_unit_id'
  },
  COST_SCRAP: {
    view: 'v_cost_of_poor_quality',
    valueColumn: 'scrap_cost',
    dateColumn: 'cost_date',
    orgUnitColumn: 'org_unit_id'
  }
};

module.exports = KPI_REGISTRY;
