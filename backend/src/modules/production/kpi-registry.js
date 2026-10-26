/*
 * Production's contribution to the tier board's KPI registry (issue #340,
 * spec #332, ADR-0054): the two numbers that make the Shift handover a
 * process rather than a virtue. Exported through this Module's entry point as
 * `kpiRegistry` and spread into the one registry at src/index.js, exactly as
 * Maintenance's, Quality's, Safety's and People's are; nothing in another
 * Module changes, and board.js still knows no KPI by name.
 *
 * READ LIVE, NOT FROZEN
 * ---------------------
 * A handover freezes the numbers it showed at submit (ADR-0054). These two are
 * not those numbers: they are counts over the handovers themselves, computed
 * on read like every other board entry, so an acknowledgement recorded a
 * minute ago is already in them.
 *
 * WHAT EACH ENTRY CLAIMS
 * -----------------------
 *   - `PRO_HANDOVER_COMPLETION` is acknowledged handovers / shift instances
 *     that have ended, x 100, over the sections in the board's Org Unit
 *     subtree and the shift instances whose `production_date` falls in the
 *     period. "Ended" is `ends_at < now()` at read time: a shift still running
 *     has had no chance to be handed over, so it is not held against the
 *     section. A cancelled shift instance was never worked and is out of the
 *     denominator. The numerator is drawn from the same shift instances, so
 *     the ratio cannot pass 100. No ended shift instance is `no_data`, never
 *     0 or 100.
 *   - `PRO_HANDOVER_ACK_MINUTES` is the median of minutes from the shift
 *     instance's `starts_at` to the handover's `acknowledged_at`, over the
 *     acknowledged handovers of the same sections and period — the same
 *     latency the Section's day shows beside each shift (handovers.js,
 *     getSectionDay). The median, not the mean: one handover acknowledged the
 *     next morning would otherwise outweigh a week of prompt ones. None
 *     acknowledged is `no_data`.
 *
 * Only a live version counts (`superseded_at IS NULL`, one per Section per
 * shift instance by `shift_handovers_live_unique`). An amendment of an
 * acknowledged handover is a new, unacknowledged version (handovers.js,
 * amendHandover), so the shift drops out of both numerators until the incoming
 * Team Leader accepts the correction — the record they accepted is no longer
 * the record that stands.
 *
 * Both entries carry `compute` (board.js's computeRegistryKpi) rather than
 * `{ view, ratio | valueColumn }`: the generic reader has neither a median nor
 * a `now()` cut on its denominator. Each is handed `{ siteId, orgUnit, period
 * }`; `orgUnit` is null for a whole-Site board, which reads every section at
 * the Site, the way the other Modules' entries treat it.
 */

const { getPool } = require('../../platform/db');

// The shift instances a board's subtree and period put in play: those of the
// sections at the Site, under the chosen Org Unit when there is one, filed by
// their own production day (ADR-0017), and never a cancelled one. A handover
// is recorded only at a section and only against that section's own shift
// instances (handovers.js, requireSection and openHandover), so a shift
// instance elsewhere in the tree could never have one.
const SECTION_SHIFTS = `
  SELECT si.id, si.starts_at, si.ends_at
    FROM shift_instances si
    JOIN org_units ou ON ou.id = si.org_unit_id
   WHERE ou.site_id = $1
     AND ou.unit_type = 'section'
     AND ($2::ltree IS NULL OR ou.path <@ $2::ltree)
     AND si.status <> 'cancelled'
     AND si.production_date BETWEEN $3::date AND $4::date
`;

// The live, acknowledged handover of each of those shift instances.
const ACKNOWLEDGED = `
  SELECT s.id AS shift_instance_id, s.starts_at, s.ends_at, h.acknowledged_at
    FROM section_shifts s
    JOIN shift_handovers h ON h.shift_instance_id = s.id
   WHERE h.superseded_at IS NULL
     AND h.status = 'acknowledged'
`;

function params({ siteId, orgUnit, period }) {
  return [siteId, orgUnit ? orgUnit.path : null, period.start, period.end];
}

async function computeCompletion(ctx) {
  const { rows: [row] } = await getPool().query(
    `WITH section_shifts AS (${SECTION_SHIFTS}),
          acknowledged AS (${ACKNOWLEDGED})
     SELECT (SELECT COUNT(*) FROM section_shifts WHERE ends_at < now())::int AS ended,
            (SELECT COUNT(*) FROM acknowledged WHERE ends_at < now())::int AS acknowledged`,
    params(ctx)
  );
  if (row.ended === 0) return null;
  return (row.acknowledged * 100) / row.ended;
}

async function computeAcknowledgementMinutes(ctx) {
  const { rows: [row] } = await getPool().query(
    `WITH section_shifts AS (${SECTION_SHIFTS}),
          acknowledged AS (${ACKNOWLEDGED})
     SELECT percentile_cont(0.5) WITHIN GROUP (
              ORDER BY EXTRACT(epoch FROM acknowledged_at - starts_at) / 60.0
            ) AS median_minutes
       FROM acknowledged`,
    params(ctx)
  );
  return row.median_minutes === null ? null : Number(row.median_minutes);
}

const KPI_REGISTRY = {
  PRO_HANDOVER_COMPLETION: { compute: computeCompletion },
  PRO_HANDOVER_ACK_MINUTES: { compute: computeAcknowledgementMinutes }
};

module.exports = KPI_REGISTRY;
