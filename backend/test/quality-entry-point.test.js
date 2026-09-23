/*
 * The Quality Module's entry point (issue #203), asserted at the export-set
 * level — the same claim people-entry-point.test.js and
 * maintenance-entry-point.test.js make, for the same reason: `npm run lint`'s
 * module boundary checker only ever looks at require *paths*. It proves a
 * Module cannot reach past another Module's entry point; it does not prove
 * that an entry point still hands back what its consumers need, and nothing
 * else in this suite consumes `modules/quality`'s exports at all.
 *
 * Two exports, and the assertion below is what keeps it two. `router` is this
 * Module's routes — the Product catalogue, the Defect code tree and, since
 * issue #205, the Non-conformance log, plus the shared floor device's own door
 * to that log (issue #207) — mounted by src/index.js at
 * `/api/quality`, the documented mount-target special case every Module's
 * `router` is (see index.js's own header for the full justification).
 * `kpiRegistry` is this Module's contribution to the tier board (issue #216),
 * spread into the assembled registry at the same composition point, which is
 * the addition issue #203's header predicted and what the board's own
 * `QUALITY` KPIs needed. Still absent, and deliberately: no lookup about a
 * Product or a Defect code for another Module to call, because nothing outside
 * Quality asks one yet. Both of these are additions to this list, which is what
 * this test exists to make visible — and dropping `router` would take the
 * Module off the wire entirely, while dropping `kpiRegistry` would silently
 * empty the Quality pillar, neither of which anything else here would notice.
 *
 * Needs no database: `getPool()` (platform/db.js) is lazy, so requiring the
 * Module and inspecting its export shape never opens a connection.
 */

const test = require('node:test');
const assert = require('node:assert');

const quality = require('../src/modules/quality');

test('the Quality Module entry point exposes exactly two names', () => {
  assert.deepStrictEqual(Object.keys(quality).sort(), ['kpiRegistry', 'router']);
});

// A router, not a function: src/index.js mounts it with `app.use`, so what
// this pins down is that it is a mountable Express router rather than
// something a caller has to invoke first — the same thing
// maintenance-entry-point.test.js asserts of the two routers there.
//
// The registry is asserted at the level that matters to the board: it is an
// object of entries, each with the four fields board.js reads, and it names
// exactly the Quality codes this Module claims — including the ones it
// deliberately leaves out, which is the half of issue #216 a test can pin
// without a database. What each entry computes is proved over HTTP in
// quality-kpis.test.js.
test('router is a mountable Express router', () => {
  assert.strictEqual(typeof quality.router, 'function');
  assert.strictEqual(typeof quality.router.use, 'function');
  assert.strictEqual(typeof quality.router.handle, 'function');
});

test('kpiRegistry names the Quality KPIs this Module computes, and nothing else', () => {
  assert.deepStrictEqual(Object.keys(quality.kpiRegistry).sort(), [
    'COST_COPQ',
    'COST_SCRAP',
    'QUA_COMPLAINTS',
    'QUA_OPEN_NC',
    'QUA_OVERDUE_CAPA'
  ]);

  // The four fields board.js reads off an entry, plus the one it reads instead
  // of `valueColumn` when the definition aggregates a ratio. This Module
  // contributes no ratio, because every Quality ratio needs a quantity produced
  // and there is no Production Module — which is exactly why the codes below
  // are absent.
  //
  // `dateColumn` is a string for a period measure and `null` for a state, which
  // is the difference board.js acts on: a null column means the source is not
  // narrowed by the period at all, the shape Maintenance's own snapshot KPI
  // (`MNT_BACKLOG`) has. The two counts here are states; the complaints entry
  // is a period measure.
  for (const code of ['QUA_OPEN_NC', 'QUA_OVERDUE_CAPA', 'QUA_COMPLAINTS']) {
    const entry = quality.kpiRegistry[code];
    assert.strictEqual(typeof entry.view, 'string', `${code} names its source`);
    assert.strictEqual(typeof entry.valueColumn, 'string', `${code} names its value column`);
    assert.ok(
      entry.dateColumn === null || typeof entry.dateColumn === 'string',
      `${code} names its date column, or none when it is a state rather than a period measure`
    );
    assert.strictEqual(entry.orgUnitColumn, 'org_unit_id', `${code} is filed at an Org Unit`);
    assert.strictEqual(entry.compute, undefined, `${code} needs no compute escape hatch`);
  }

  // Which of the two readings each of those three is: the counts are states,
  // and the one period measure carries the day its events happened on.
  for (const code of ['QUA_OPEN_NC', 'QUA_OVERDUE_CAPA']) {
    assert.strictEqual(quality.kpiRegistry[code].dateColumn, null, `${code} is a state`);
  }
  assert.strictEqual(typeof quality.kpiRegistry.QUA_COMPLAINTS.dateColumn, 'string');

  // The two Cost entries take board.js's other reading — a `compute` function
  // owning its whole computation — because the generic shape above can only
  // sum what priced and would therefore report a confidently low currency
  // figure for a period the Platform cannot price (issue #258, and
  // quality/kpi-registry.js's own header for the argument). They name no
  // `view`, no `valueColumn` and no `dateColumn`: the period and the subtree
  // are arguments `compute` is handed, not a filter board.js applies for them.
  for (const code of ['COST_COPQ', 'COST_SCRAP']) {
    const entry = quality.kpiRegistry[code];
    assert.strictEqual(typeof entry.compute, 'function', `${code} owns its own computation`);
    assert.strictEqual(entry.view, undefined, `${code} names no source for the generic reader`);
    assert.strictEqual(entry.valueColumn, undefined, `${code} names no value column`);
    assert.strictEqual(entry.dateColumn, undefined, `${code} is not narrowed by board.js`);
  }

  // The production-count KPIs stay unclaimed on purpose: a denominator nothing
  // writes is an invented number, so the board keeps answering `no_data` for
  // them (issue #216's own criterion).
  for (const code of ['QUA_FPY', 'QUA_INT_PPM', 'QUA_CUST_PPM', 'DEL_QUALITY_RATE']) {
    assert.strictEqual(quality.kpiRegistry[code], undefined, `${code} must stay no_data`);
  }
});

// The two catalogues and the Non-conformance log are this Module's surface
// today, and they are asserted by the *paths* the router itself declares —
// walked through the child routers it mounts, since a mounted router is a
// middleware layer rather than a route, and read off the router's own stack
// rather than by making a request (which is what the HTTP-level integration
// file is for). A ticket that moves one of these addresses without moving its
// Screen fails here first, without a database.
//
// The register is Site-shaped (`/sites/:siteId/nonconformances`) because the
// only entitlement question it asks is whether the caller can see that Site —
// the shape the action log already uses — while one record is read and changed
// by its own address, and the affected quantity has an address of its own
// because appending to a record's history is a different act from correcting a
// field on it.
//
// Issue #206's five addresses are here for the same reason, and they are five
// rather than one because each is refused differently: `/dispositions` needs
// the write Grant recording needs, `/concession`, `/lower-severity`, `/reopen`
// and `/cancel` each need Quality authority at the record's Org Unit
// (ADR-0035), and the state each refuses on is its own (a Concession more than
// what is undecided, a reopen of something not closed, a change to a cancelled
// record). Folding any of them into the PATCH above would produce one route
// asking two different permission questions, which is the shape ADR-0019 and
// ADR-0035 both argue against.
//
// Issue #207's three are the shared floor device's own door, and their
// `/floor/` segment is what says so: a device presents a credential and an
// individual identification instead of a bearer token, so the two catalogues
// it must choose from and the recording it makes are their own addresses
// rather than a second kind of caller on the Account-facing ones. Note what is
// absent here: no `/floor/nonconformances/:id/concession`, no lowering, no
// reopen and no cancel — the four acts that need Quality authority are not
// reachable from a device at all, which is the criterion the list below is
// also the assertion for.
// Issue #214's nine are the Customer list and the customer complaint surface:
// two catalogue routes over a table the baseline carries, the register per Site
// (the same shape the Non-conformance register takes, because both are filed at
// an Org Unit and read by whoever can see the Site), one complaint's own read,
// and the three writes a reader makes from it — closing it with its response,
// recording the Non-conformance that controls the complained-of product, and
// linking one that already exists. Note what is absent: no
// `/complaints/:id/reopen` and no delete, because a complaint that was answered
// is a record of what was said rather than a state to move back out of.
//
// Issue #215's ten are the same surface turned outward, in the same
// vocabulary: the Supplier catalogue's two writes and its read, the register
// per Site, one NCR's own read, and the four writes a reader makes from it —
// the disposition and the cost recovered, the close, recording the
// Non-conformance at `incoming`, and linking one that exists. Two acts rather
// than the complaint's one closure because a supplier NCR has two questions
// behind it that a complaint does not: what happens to the material, and what
// the Supplier owes for it.
function declaredRoutes(router) {
  const declared = [];
  for (const layer of router.stack) {
    if (layer.route) {
      for (const method of Object.keys(layer.route.methods)) {
        declared.push(`${method.toUpperCase()} ${layer.route.path}`);
      }
    } else if (layer.handle && layer.handle.stack) {
      declared.push(...declaredRoutes(layer.handle));
    }
  }
  return declared;
}

test('the router carries the Product, Defect code, Non-conformance, Customer, complaint, Supplier, supplier NCR and floor paths, and nothing else', () => {
  assert.deepStrictEqual(declaredRoutes(quality.router).sort(), [
    'GET /complaints/:id',
    'GET /customers',
    'GET /defect-codes',
    'GET /floor/defect-codes',
    'GET /floor/products',
    'GET /nonconformances/:id',
    'GET /products',
    'GET /sites/:siteId/complaints',
    'GET /sites/:siteId/nonconformances',
    'GET /sites/:siteId/supplier-ncrs',
    'GET /supplier-ncrs/:id',
    'GET /suppliers',
    'PATCH /customers/:id',
    'PATCH /defect-codes/:id',
    'PATCH /nonconformances/:id',
    'PATCH /products/:id',
    'PATCH /suppliers/:id',
    'POST /complaints/:id/link',
    'POST /complaints/:id/nonconformance',
    'POST /complaints/:id/respond',
    'POST /customers',
    'POST /defect-codes',
    'POST /floor/nonconformances',
    'POST /nonconformances/:id/cancel',
    'POST /nonconformances/:id/concession',
    'POST /nonconformances/:id/dispositions',
    'POST /nonconformances/:id/lower-severity',
    'POST /nonconformances/:id/quantity',
    'POST /nonconformances/:id/reopen',
    'POST /products',
    'POST /sites/:siteId/complaints',
    'POST /sites/:siteId/nonconformances',
    'POST /sites/:siteId/supplier-ncrs',
    'POST /supplier-ncrs/:id/close',
    'POST /supplier-ncrs/:id/disposition',
    'POST /supplier-ncrs/:id/link',
    'POST /supplier-ncrs/:id/nonconformance',
    'POST /suppliers'
  ]);
});
