/*
 * The Maintenance Module's entry point (issue #56), asserted at the
 * export-set level — the same claim people-entry-point.test.js makes, for
 * the same reason: the boundary checker looks at require paths, not at what
 * an entry point actually hands back.
 *
 * One export until issue #202, which makes the tier board's registry of
 * computable KPIs composable and adds two names:
 *
 *   - kpiRegistry — this Module's own contribution to that registry, the eight
 *     maintenance KPIs keyed by code, each naming how its number is read out
 *     of the baseline's own view. It is read-only data over records this
 *     Module owns, which is what makes it a legitimate export under ADR-0006's
 *     clauses (a value, not a command; domain, not utility), and the test
 *     below pins the eight codes by name so removing one is visible here.
 *   - createBoardRouter — the board's route as a factory, because it is the
 *     one route that has to be handed the registry the application assembles
 *     at src/index.js. src/index.js mounts it beside `router`; nothing else
 *     calls it.
 *
 * `router` still does not carry the board route, deliberately: it is mounted
 * for every other route without a registry threaded through it, and a board
 * whose registry silently defaulted to this Module's own eight would be the
 * thing #202 removes. Adding a fourth name is cheap when a second Module
 * genuinely needs an answer only Maintenance can give; re-exporting an
 * internal so a sibling ticket can skip a layer is what this test exists to
 * make visible.
 *
 * Issue #201 moved the shared floor device and the identification presented on
 * it into the people Module and deliberately changed NOTHING here: this Module
 * is the consumer of that surface, not a provider of it — `work-order-routes.js`
 * and `floor-routes.js` ask `people.findDeviceByCredential`,
 * `people.findValidIdentification` and `people.deviceReachesOrgUnit` through
 * People's entry point, and no other Module asks Maintenance anything about a
 * device. So the floor device contributes no name here, and its not doing so is
 * part of what the set below asserts.
 */

const test = require('node:test');
const assert = require('node:assert');

const maintenance = require('../src/modules/maintenance');

test('the Maintenance Module entry point exposes exactly three names', () => {
  assert.deepStrictEqual(
    Object.keys(maintenance).sort(),
    ['createBoardRouter', 'kpiRegistry', 'router']
  );
});

test('kpiRegistry and createBoardRouter are the two names the tier board needs', () => {
  assert.strictEqual(typeof maintenance.createBoardRouter, 'function');
  assert.strictEqual(typeof maintenance.kpiRegistry, 'object');
  assert.notStrictEqual(maintenance.kpiRegistry, null);
});

// The eight maintenance KPIs, by name. A contribution that dropped one would
// send that KPI back to `no_data` on every board with nothing else to say so,
// which is exactly the failure this assertion makes loud.
test("kpiRegistry holds this Module's eight KPIs, keyed by their codes", () => {
  assert.deepStrictEqual(Object.keys(maintenance.kpiRegistry).sort(), [
    'MNT_BACKLOG',
    'MNT_COST',
    'MNT_MTBF',
    'MNT_MTTR',
    'MNT_PARTS_COST',
    'MNT_PLANNED_RATIO',
    'MNT_PM_COMPLIANCE',
    'MNT_SCHEDULE_COMPLIANCE'
  ]);
});

// Each entry has to name the view and the column the number comes out of, or
// the board has nothing to compute with — the shape kpi-registry.js documents.
test('every registry entry names a view and a way to read its value', () => {
  for (const [code, entry] of Object.entries(maintenance.kpiRegistry)) {
    assert.strictEqual(typeof entry.view, 'string', `${code} names its view`);
    assert.ok(
      entry.ratio !== undefined || typeof entry.valueColumn === 'string',
      `${code} names a value column or a ratio`
    );
    assert.ok('dateColumn' in entry, `${code} says whether it is period-bound`);
    assert.strictEqual(typeof entry.orgUnitColumn, 'string', `${code} names its Org Unit column`);
  }
});
