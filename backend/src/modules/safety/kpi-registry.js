/*
 * Safety's contribution to the tier board's KPI registry (issues #232 and
 * #233, parent #223 decisions 3 and 5, and #247/ADR-0041 for the two rates).
 *
 * The registry was made composable by issue #202: each Module's entry point
 * contributes its own entries and src/index.js — where the application composes
 * its Modules — spreads them into the one registry the board is handed. This
 * file is Safety's half, and it is the whole of the coupling the board costs
 * either Module: nothing in `maintenance` or `quality` changes, and no Module
 * requires another (ADR-0006's boundary check is what enforces that).
 *
 * WHAT EACH ENTRY CLAIMS
 * -----------------------
 * Five codes, which are every Safety-pillar number this Platform's own
 * records can answer today:
 *
 *   - `SAF_INCIDENTS` counts the Safety incidents that caused something — an
 *     injury or property damage — excluding `incident_type = 'near_miss'`, at
 *     the chosen Org Unit and everything beneath it.
 *   - `SAF_NEARMISS` counts `incident_type = 'near_miss'` in the period —
 *     what kind of event it was, never `severity_level`.
 *   - `SAF_OBSERVATIONS` counts the Safety observations recorded in the
 *     period.
 *   - `SAF_TRIR` and `SAF_LTIFR` are recordable/lost-time incidents per
 *     worked hour, over a rolling 12 months ending at the board period's end
 *     and the chosen subtree — issue #233's own entries, previously absent
 *     because nothing wrote `attendance_records`. Attendance landed in #249;
 *     see this file's own "SAF_TRIR AND SAF_LTIFR" section below for the full
 *     arithmetic and why these two carry `compute` rather than `view`.
 *
 * TWO SEEDED DEFINITIONS WERE WRONG TOGETHER, AND THIS DEPARTS FROM ONE OF THEM
 * ------------------------------------------------------------------------------
 * `SAF_INCIDENTS`'s seeded `formula_text` reads "All incidents recorded, at
 * any severity," and the baseline's own `v_safety_rates.incident_count` counts
 * every row in `safety_incidents` regardless of `incident_type` — near misses
 * included. Taken literally alongside `SAF_NEARMISS` (`higher_better`, "near
 * misses reported"), one near-miss report would move both numbers on the board
 * at once, in opposite directions: `SAF_INCIDENTS` is `lower_better`, so the
 * same report that makes the culture metric look better makes the incident
 * count look worse. A plant that succeeds at near-miss reporting would watch
 * its incident count climb for reporting well. This ticket departs from the
 * seeded formula: `SAF_INCIDENTS` here excludes `incident_type = 'near_miss'`,
 * counting only incidents that caused something — an injury or property
 * damage — so the two numbers can never move against each other from the same
 * report (#223 decision 3). `SAF_NEARMISS` counts the same field,
 * `incident_type = 'near_miss'`, never `severity_level` — a damage-only fire
 * sits on `severity_level`'s no-injury rung (`near_miss`, per decision 3's own
 * naming) but is `incident_type = 'fire'`, so it counts toward `SAF_INCIDENTS`
 * and never toward `SAF_NEARMISS`.
 *
 * WHY AN ENTRY'S SOURCE IS A DERIVED TABLE RATHER THAN A VIEW NAME
 * -----------------------------------------------------------------
 * `maintenance/kpi-registry.js`'s header describes the shape board.js reads:
 * each entry ties a KPI code to `{ view, valueColumn | ratio, dateColumn,
 * orgUnitColumn }`, and board.js reads it as `FROM <view> v`, rolls the
 * matching rows up the Org Unit tree the way the definition's `aggregation`
 * says, and filters them by `dateColumn` when the definition is a period
 * measure. All three entries here are period counts of this Module's own
 * records — one row per Org Unit per production day — and no baseline view
 * carries that shape for either table, `v_safety_rates` being the per-rate
 * view this Module deliberately does not claim. So each entry names a derived
 * table — a subquery in the `view` slot, the same thing `quality/kpi-
 * registry.js`'s two counts do and the same thing board.js means by "view":
 * something aliased `v` with the columns the entry names. It is computed on
 * read like every other number on the board, it lives in this Module's own
 * contribution, and it changes nothing in `maintenance` or `quality`.
 *
 * FILED BY PRODUCTION DAY, NEVER BY THE CALENDAR (ADR-0017)
 * -----------------------------------------------------------
 * `safety_incidents` and `safety_observations` are both in the eleven tables
 * `attach_shift_instance` covers (ADR-0017's own list), so every row already
 * carries a `shift_instance_id` filled in by the same `fill_shift_instance`
 * trigger the baseline attaches everywhere else — the "one place that cannot
 * forget" ADR-0017 argues for. Each derived table below joins `shift_instances`
 * and groups by its `production_date`, exactly as the baseline's own
 * `v_safety_rates` already does for the same two tables, rather than deriving
 * a second, weaker notion of "today" from `occurred_at`/`observed_at` and a
 * timezone. A row whose trigger left `shift_instance_id` null — a Site with no
 * shift pattern configured, ADR-0017's own open question — is not counted by
 * any of these three entries, the same silence `v_safety_rates` already
 * carries for such a row.
 *
 * NO INJURY DETAIL IS READ, AND NONE IS EXPOSED
 * ------------------------------------------------
 * Every derived table below is `COUNT(*)` over `org_unit_id` and a production
 * day; none selects `employee_id`, `injury_type_id` or `body_part_id`.
 * `computeInjuryRate` (SAF_TRIR/SAF_LTIFR) reads the same way: `is_recordable`
 * and `severity_level` off `safety_incidents`, `worked_minutes` off
 * `attendance_records`, and nothing else — no Employee identity from either
 * table. The #224 read restriction on those three columns (ADR-0037) governs
 * what a caller of `safety-incident-routes.js` may read about one incident;
 * it has nothing to gate here; because this file never reads them, a caller
 * who may not read who was hurt still sees the right number on the board.
 *
 * A ZERO IS NOT REPORTED HERE — THESE ARE PERIOD MEASURES
 * ----------------------------------------------------------
 * All three entries carry a `dateColumn`, so a period with no matching row
 * reports `no_data`, exactly as `QUA_COMPLAINTS` and both Cost entries do:
 * there is no LEFT JOIN out of `org_units` widening a quiet period into a
 * measured zero. That is a deliberate difference from `QUA_OPEN_NC` and
 * `QUA_OVERDUE_CAPA`, which are snapshots with no period at all — a Safety
 * incident count has a period ("incidents this shift"), a snapshot state does
 * not ("open Non-conformances this shift" is not a sentence), so the two
 * pillars' entries are shaped differently on purpose.
 *
 * A CORRECTED SEVERITY RESTATES THE PERIOD THE INCIDENT OCCURRED IN
 * ---------------------------------------------------------------------
 * `safety-incidents.js`'s own severity-change route lets a first-aid case
 * later recorded as lost-time be corrected with a note (#223 decision 5), and
 * the row's `org_unit_id`, `occurred_at` and therefore `shift_instance_id` do
 * not move when that happens — only `severity_level` does. Since
 * `SAF_INCIDENTS` and `SAF_NEARMISS` key off `incident_type`, not
 * `severity_level`, a severity correction never moves either of these two
 * counts, but it does restate `SAF_TRIR`/`SAF_LTIFR`'s numerator the next
 * time either is read for a window that still covers that production day —
 * see those two entries' own section below. It is recorded here because it is
 * the general shape every count in this registry takes: nothing here is
 * filed against a frozen snapshot of the incident as first recorded, so any
 * correction to a past incident — severity or otherwise — restates the
 * production day it occurred on, the next time the board is read for that
 * day, rather than the day the correction was made. A historical number
 * moving is the record being corrected, not a bug.
 *
 * SAF_TRIR AND SAF_LTIFR (issue #233, ADR-0041)
 * ----------------------------------------------
 * Both are rates per worked hour, computed over a rolling 12 months ending at
 * the board period's end — whatever the period asked for — rather than the
 * period itself: ADR-0041 argues why (one incident on a 30-person line in a
 * single week produces a TRIR in the hundreds, a number nobody would act on).
 * This is the one pair of numbers on the whole board for which the period
 * asked for is not the window computed over, and neither `{ view, valueColumn
 * | ratio, dateColumn, orgUnitColumn }` — the shape every other entry in this
 * registry and in `maintenance/kpi-registry.js` uses — nor board.js's own
 * `computeRegistryKpi` can express that: the generic reader always filters by
 * `period.start`..`period.end`, and a derived `view` subquery has no way to
 * see `period.end` at all in order to reach back 12 months from it. Nor can
 * the generic reader express `no_data` from an unconfirmed shift: that is not
 * an aggregate over rolled-up rows, it is an EXISTS check against a different
 * relation (`attendance_sheets`) whose answer must block the number entirely,
 * not average into it. So these two entries carry `compute` instead of
 * `view`/`valueColumn`/`ratio` — board.js's own escape hatch for exactly this
 * case (see `computeRegistryKpi`'s comment there) — and own their whole
 * computation below, in `computeInjuryRate`.
 *
 * Sum first, divide once, over the window and the whole subtree (ADR-0041's
 * own decision, rejecting an average of daily or per-Org-Unit rates): every
 * confirmed shift's worked hours are added together, every recordable (for
 * `SAF_TRIR`) or lost-time (for `SAF_LTIFR`) incident against one of those
 * shifts is added together, and the rate is `scale * Σincidents / Σhours`,
 * one division. `SAF_TRIR` reads `safety_incidents.is_recordable`, the
 * baseline's own STORED generated column (`medical_treatment`,
 * `restricted_work`, `lost_time` or `fatality` — CONTEXT.md's own Recordable
 * entry: "medical treatment and worse"), never re-spelling the ladder here.
 * `SAF_LTIFR` reads `severity_level IN ('lost_time', 'fatality')` — the same
 * two rungs `v_safety_rates.lost_time_count` already uses. A near miss sits
 * below both rungs and needs no filter of its own to be excluded from either.
 *
 * The window: no earlier than the Org Unit subtree's own first confirmed
 * shift, and no later than the board period's end, reaching back at most one
 * year (`production_date > period.end - interval '1 year'`, a half-open
 * start so the window holds exactly 365 or 366 days). No confirmed shift
 * anywhere in the subtree at all — the floor query returns no row — is
 * `no_data`: ADR-0041's "Why not a `no_data` rule with no start date"
 * rejects reaching back a full calendar year before any confirmation exists.
 * This floor is scoped to the CHOSEN subtree, deliberately narrower than
 * `people/attendance.js`'s own `listAttendanceToConfirm`, whose floor is
 * Site-wide on purpose (that function's own header explains why: a line that
 * has never confirmed anything must still show up on its Site's worklist).
 * The Site-wide floor is a superset of every subtree floor beneath it, so a
 * shift this computation's own floor would not yet reach can still appear on
 * that worklist — the worklist can never hide a shift that is (or will
 * become, once its Site's own floor opens) a blocker for some subtree's rate;
 * it can only additionally list shifts no subtree's own window has reached
 * yet. The two rules agree in the direction that matters: a shift that blocks
 * a rate is always on the worklist that would surface it.
 *
 * Within the window, any PAST shift instance in the subtree (`ends_at <=
 * now()`, excluding `status = 'cancelled'`, which is never worked and never
 * needs confirming) that still has no confirmed `attendance_sheets` row makes
 * the whole rate `no_data` — an EXISTS check, not a partial sum: ADR-0041's
 * own "Why not drop unconfirmed shifts from the window" rejects leaving such
 * a shift's hours or incidents out silently, since either direction is a
 * wrong number reported as a right one. A shift still in progress or not yet
 * started is not a blocker; only one that has ended and gone unconfirmed is.
 * Both the numerator and the denominator are summed only over CONFIRMED
 * shifts in the window — not a softening of that same rule, but its
 * consequence: a past, unconfirmed shift already forces the whole rate to
 * `no_data` before either sum is read, so nothing confirmed is ever counted
 * on one side and left out of the other, and a shift still open tonight
 * (not yet past, so not yet a blocker) simply is not in either sum yet
 * either, exactly as it is not yet in `v_safety_rates` for the same reason.
 *
 * A ZERO IS A REAL MEASUREMENT HERE — UNLIKE THE THREE ENTRIES ABOVE
 * ---------------------------------------------------------------------
 * "A ZERO IS NOT REPORTED HERE" above is about `SAF_INCIDENTS`,
 * `SAF_NEARMISS` and `SAF_OBSERVATIONS`, whose period would otherwise be
 * indistinguishable from one where nothing was ever recorded — a genuine
 * absence of rows. `SAF_TRIR` and `SAF_LTIFR` are the opposite case: once the
 * window has a floor and no shift inside it is unconfirmed, zero recordable
 * (or lost-time) incidents over a positive number of confirmed hours is a
 * real, reportable `0.0` — a clean window, not a missing one. `no_data` here
 * means only "the window has not opened yet" or "something in it is still
 * unconfirmed," never "nothing happened."
 *
 * THE `no_data` REASON IS NOT CARRIED ON THE BOARD — RECORDED HERE PER THE
 * TICKET'S OWN ESCAPE HATCH, NOT SILENTLY DROPPED
 * -------------------------------------------------------------------------
 * ADR-0041 says an unconfirmed shift should make the rate `no_data` "with the
 * reason given — naming the unconfirmed shift rather than a bare 'no data'."
 * This file's `computeRegistryKpi` return contract (see board.js) is a bare
 * `number | null`, and the wire response for one KPI (`board.js`'s own
 * per-KPI object, `frontend/lib/maintenance/tier_board.dart`'s `BoardKpi`)
 * has no field built to carry a dynamic, per-request explanation: `status` is
 * a closed vocabulary (`green`/`amber`/`red`/`no_target`/`no_data`, no room
 * for free text), and `formulaText` is static per-definition text read once
 * from the `kpi_definitions` seed table — the client's own dartdoc documents
 * it as "the plain-language formula," so repurposing it to sometimes carry a
 * dynamic reason would make that documentation false the moment it happened.
 * Adding a new field would be exactly the response-shape change issue #233's
 * own acceptance criteria say not to make without asking first. So: this
 * entry answers plain `no_data`, with no reason on the wire, and the reason
 * is not lost — it already has a home. `GET /people/attendance-to-confirm`
 * (issue #250) is the worklist of exactly the shifts that would block a rate,
 * and `people/attendance.js`'s own header says so: "a single unconfirmed
 * shift makes the injury rates `no_data`, so this is what keeps that from
 * becoming a permanent blank." A caller who sees `no_data` here and wants to
 * know why finds it there, not in a string on this response. This is a
 * deliberate use of the ticket's own escape hatch ("if a reason cannot be
 * carried without a shape change, record that finding on the ticket rather
 * than widening the board") — recorded here, and on issue #233 itself,
 * because ADR-0041 says "with the reason given" and this implementation does
 * not put one on the board; the ADR and this file are in a known, deliberate
 * tension until a follow-up ticket (if wanted) decides whether the board's
 * shape should widen for it.
 */

const { getPool } = require('../../platform/db');

// One row per Org Unit per production day: how many Safety incidents that
// caused something — an injury or property damage — were recorded there.
// `incident_type <> 'near_miss'` is the departure from the seeded
// `formula_text` this file's header argues; `severity_level` plays no part; a
// damage-only fire on the no-injury rung is `incident_type = 'fire'`, so it
// counts here.
const INCIDENTS_THAT_CAUSED_SOMETHING = `(
  SELECT sn.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS incident_count
    FROM safety_incidents sn
    JOIN shift_instances si ON si.id = sn.shift_instance_id
   WHERE sn.incident_type <> 'near_miss'
   GROUP BY sn.org_unit_id, si.production_date
)`;

// One row per Org Unit per production day: how many near misses were
// reported. `incident_type = 'near_miss'`, never `severity_level` — the
// severity ladder's own bottom rung happens to share the spelling, but it
// means "no injury" on a record of any kind, and is not what this count reads
// (#223 decision 3).
const NEAR_MISSES_REPORTED = `(
  SELECT sn.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS near_miss_count
    FROM safety_incidents sn
    JOIN shift_instances si ON si.id = sn.shift_instance_id
   WHERE sn.incident_type = 'near_miss'
   GROUP BY sn.org_unit_id, si.production_date
)`;

// One row per Org Unit per production day: how many Safety observations were
// logged there, the leading indicator beside the two lagging counts above.
const OBSERVATIONS_LOGGED = `(
  SELECT so.org_unit_id                AS org_unit_id,
         si.production_date            AS production_date,
         COUNT(*)::numeric             AS observation_count
    FROM safety_observations so
    JOIN shift_instances si ON si.id = so.shift_instance_id
   GROUP BY so.org_unit_id, si.production_date
)`;

// `SAF_TRIR`'s severity filter: the baseline's own STORED generated column,
// never re-spelled inline — see this file's header, "SAF_TRIR AND SAF_LTIFR".
const RECORDABLE_CONDITION = 'sn.is_recordable';

// `SAF_LTIFR`'s severity filter: the same two rungs
// `v_safety_rates.lost_time_count` already uses.
const LOST_TIME_CONDITION = "sn.severity_level IN ('lost_time', 'fatality')";

// The whole of SAF_TRIR/SAF_LTIFR's arithmetic (issue #233, ADR-0041) — see
// this file's header, "SAF_TRIR AND SAF_LTIFR", for why this is a `compute`
// function rather than a `{ view, valueColumn | ratio }` entry. `ctx` is
// exactly what board.js's `computeRegistryKpi` hands a `compute` entry:
// `{ siteId, orgUnit, period }`. `orgUnit` is null for a whole-Site board —
// `subtree` below reads every Org Unit at the Site in that case, matching how
// the generic reader treats a null `orgUnit` elsewhere in this registry.
async function computeInjuryRate({ siteId, orgUnit, period }, { scale, severityCondition }) {
  const { rows: [row] } = await getPool().query(
    `WITH subtree AS (
       SELECT id FROM org_units
        WHERE site_id = $1 AND ($2::ltree IS NULL OR path <@ $2::ltree)
     ),
     confirmed_floor AS (
       -- The subtree's own first confirmed shift — the earliest the window
       -- may start. No row at all (no confirmed sheet anywhere in the
       -- subtree, ever) is exactly "the window has not opened yet".
       SELECT MIN(si.starts_at) AS starts_at
         FROM shift_instances si
         JOIN attendance_sheets sh ON sh.shift_instance_id = si.id
        WHERE sh.confirmed_at IS NOT NULL
          AND si.org_unit_id IN (SELECT id FROM subtree)
     ),
     window_shifts AS (
       -- Every shift instance in the subtree, inside the rolling window
       -- (at most one year, ending at the period's own end, never starting
       -- before the subtree's own confirmed floor), excluding a cancelled
       -- shift — never worked, never needing a sheet at all.
       SELECT si.id, si.ends_at, sh.confirmed_at
         FROM shift_instances si
         CROSS JOIN confirmed_floor f
         LEFT JOIN attendance_sheets sh ON sh.shift_instance_id = si.id
        WHERE si.org_unit_id IN (SELECT id FROM subtree)
          AND si.status <> 'cancelled'
          AND si.production_date <= $3::date
          AND si.production_date > ($3::date - interval '1 year')
          AND si.starts_at >= f.starts_at
     )
     SELECT
       (SELECT starts_at FROM confirmed_floor) IS NULL AS no_floor,
       -- Any PAST shift in the window still unconfirmed blocks the whole
       -- rate — ADR-0041's own rule, an EXISTS rather than a partial sum.
       EXISTS (
         SELECT 1 FROM window_shifts w
          WHERE w.ends_at <= now() AND w.confirmed_at IS NULL
       ) AS blocked,
       -- Both sums are over CONFIRMED shifts only — see this file's header
       -- for why that is a consequence of the block above, not a softening
       -- of it.
       (SELECT COALESCE(SUM(ar.worked_minutes), 0)
          FROM attendance_records ar
          JOIN window_shifts w ON w.id = ar.shift_instance_id
         WHERE w.confirmed_at IS NOT NULL) AS worked_minutes,
       (SELECT COUNT(*)
          FROM safety_incidents sn
          JOIN window_shifts w ON w.id = sn.shift_instance_id
         WHERE w.confirmed_at IS NOT NULL AND (${severityCondition})) AS incident_count`,
    [siteId, orgUnit ? orgUnit.path : null, period.end]
  );

  if (row.no_floor || row.blocked) return null;

  const workedHours = Number(row.worked_minutes) / 60;
  // No confirmed hours in the window at all (a floor exists somewhere in the
  // subtree, but nothing confirmed falls inside this particular window) is
  // still `no_data` — a rate has no honest denominator of zero.
  if (workedHours === 0) return null;

  // A zero incident count over positive hours IS a real number here — see
  // this file's header, "A ZERO IS A REAL MEASUREMENT HERE".
  return (scale * Number(row.incident_count)) / workedHours;
}

// code -> how to read it. `valueColumn` is a column of the source the entry
// names, exactly as Maintenance's and Quality's own entries are — see this
// file's header for why every source here is a derived table rather than a
// view name. `SAF_TRIR`/`SAF_LTIFR` are the one pair that carries `compute`
// instead — board.js's own escape hatch for a window and a `no_data` rule the
// `{ view, valueColumn | ratio }` shape cannot express (this file's header,
// "SAF_TRIR AND SAF_LTIFR").
const KPI_REGISTRY = {
  SAF_INCIDENTS: {
    view: INCIDENTS_THAT_CAUSED_SOMETHING,
    valueColumn: 'incident_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  SAF_NEARMISS: {
    view: NEAR_MISSES_REPORTED,
    valueColumn: 'near_miss_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  SAF_OBSERVATIONS: {
    view: OBSERVATIONS_LOGGED,
    valueColumn: 'observation_count',
    dateColumn: 'production_date',
    orgUnitColumn: 'org_unit_id'
  },
  SAF_TRIR: {
    compute: (ctx) => computeInjuryRate(ctx, { scale: 200000, severityCondition: RECORDABLE_CONDITION })
  },
  SAF_LTIFR: {
    compute: (ctx) => computeInjuryRate(ctx, { scale: 1000000, severityCondition: LOST_TIME_CONDITION })
  }
};

module.exports = KPI_REGISTRY;
