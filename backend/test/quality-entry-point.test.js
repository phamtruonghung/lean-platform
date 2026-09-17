/*
 * The Quality Module's entry point (issue #203), asserted at the export-set
 * level — the same claim people-entry-point.test.js and
 * maintenance-entry-point.test.js make, for the same reason: `npm run lint`'s
 * module boundary checker only ever looks at require *paths*. It proves a
 * Module cannot reach past another Module's entry point; it does not prove
 * that an entry point still hands back what its consumers need, and nothing
 * else in this suite consumes `modules/quality`'s exports at all.
 *
 * One export, and the assertion below is what keeps it one. `router` is this
 * Module's routes — the Product catalogue, the Defect code tree and, since
 * issue #205, the Non-conformance log, plus the shared floor device's own door
 * to that log (issue #207) — mounted by src/index.js at
 * `/api/quality`, the documented mount-target special case every Module's
 * `router` is (see index.js's own header for the full justification). Issue
 * #203 adds no lookup about a Product or a Defect code for another Module to
 * call, because nothing outside Quality asks one yet, and no KPI registry
 * contribution, because a catalogue is not a number; issue #205 adds neither
 * either, for its own reasons index.js's header gives. A future slice that
 * starts publishing Quality numbers adds the KPI contribution; a sibling
 * Module that needs a Quality answer adds the lookup. Both are additions to
 * this list, which is what this test exists to make visible — and dropping
 * `router` would take the Module off the wire entirely, which nothing else
 * here would notice.
 *
 * Needs no database: `getPool()` (platform/db.js) is lazy, so requiring the
 * Module and inspecting its export shape never opens a connection.
 */

const test = require('node:test');
const assert = require('node:assert');

const quality = require('../src/modules/quality');

test('the Quality Module entry point exposes exactly one name', () => {
  assert.deepStrictEqual(Object.keys(quality).sort(), ['router']);
});

// A router, not a function: src/index.js mounts it with `app.use`, so what
// this pins down is that it is a mountable Express router rather than
// something a caller has to invoke first — the same thing
// maintenance-entry-point.test.js asserts of the two routers there.
test('router is a mountable Express router', () => {
  assert.strictEqual(typeof quality.router, 'function');
  assert.strictEqual(typeof quality.router.use, 'function');
  assert.strictEqual(typeof quality.router.handle, 'function');
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

test('the router carries the Product, Defect code, Non-conformance and floor paths, and nothing else', () => {
  assert.deepStrictEqual(declaredRoutes(quality.router).sort(), [
    'GET /defect-codes',
    'GET /floor/defect-codes',
    'GET /floor/products',
    'GET /nonconformances/:id',
    'GET /products',
    'GET /sites/:siteId/nonconformances',
    'PATCH /defect-codes/:id',
    'PATCH /nonconformances/:id',
    'PATCH /products/:id',
    'POST /defect-codes',
    'POST /floor/nonconformances',
    'POST /nonconformances/:id/cancel',
    'POST /nonconformances/:id/concession',
    'POST /nonconformances/:id/dispositions',
    'POST /nonconformances/:id/lower-severity',
    'POST /nonconformances/:id/quantity',
    'POST /nonconformances/:id/reopen',
    'POST /products',
    'POST /sites/:siteId/nonconformances'
  ]);
});
