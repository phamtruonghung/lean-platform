/*
 * Pictures of a Quality issue, and the Site's slide show (issue #419) — over
 * HTTP, against a real database and a local session. The scaffolding is
 * the one `customer-complaints.test.js` establishes.
 *
 * **One test per door, and each refusal proved rather than assumed**, which is
 * what the card's own criteria ask for:
 *
 *   - a picture stored against a Non-conformance and one against a complaint,
 *     read back as bytes at its own address and as metadata in the list;
 *   - the upload refused for a body that is not an image (400), one whose
 *     declared type disagrees with its bytes (400), a plain-text Content-Type
 *     (415), a picture over a 1600 px edge (413) and one over 5 MiB (413) —
 *     five different mistakes and five different sentences;
 *   - a reader with no Grant on the Site refused (403), a reader who may see the
 *     Site but holds only a *read* Grant refused the upload and the delete (403),
 *     and a record that is not there a 404 before any of that is asked;
 *   - remove: 204, then the picture is gone from the list, then 404 for the
 *     second attempt;
 *   - the slide show: choosing a Non-conformance and a complaint, the order the
 *     picker writes, an issue chosen without a picture still listed (with an
 *     empty `images`), a Site's show holding only its own records, and a
 *     re-order refused when it names an issue that is not in the show.
 *
 * "The chosen set respects org-unit scope" is asserted from both ends: an
 * Account with no Grant on the Site cannot read the show at all (403), and a
 * record filed at another Site is in that other Site's show rather than this
 * one — so the wall shows what the register behind it shows, and nothing else.
 *
 * Needs a database with every migration applied, including
 * 1803300000000_quality-issue-images-and-slide-show.js. Set DATABASE_URL first
 * (see the README's Tests section).
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
const insertedCustomerCodes = [];

let codeCounter = 0;
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('ssacct');
  const name = displayName ?? `Slide Show Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, quality_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.quality ?? false]
    );
  }

  return { id: account.id, displayName: name, token: await authHeader(subject) };
}

async function insertSite({ name = 'Slide Show Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SSS'), name, 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Slide Show Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SSOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function createProduct(adminToken) {
  const code = uniqueCode('SSP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Product ${code}`, uomCode: 'EA' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode(adminToken) {
  const code = uniqueCode('SSD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Defect ${code}`, category: 'product', defaultSeverity: 'major' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

async function createCustomer(adminToken) {
  const code = uniqueCode('SSCUST-');
  const response = await fetch(`${base}/api/quality/customers`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Customer ${code}` })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedCustomerCodes.push(code);
  return body.customer;
}

// ---------------------------------------------------------------------------
// A picture, built here rather than checked in: the route reads the header, and
// a synthetic header can state any size exactly.
// ---------------------------------------------------------------------------

function pngBuffer(width, height) {
  const buffer = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.writeUInt32BE(13, 8);
  buffer.write('IHDR', 12, 'ascii');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

// ---------------------------------------------------------------------------
// The addresses this file drives
// ---------------------------------------------------------------------------

async function listImages(token, kindPath, issueId) {
  const response = await fetch(`${base}/api/quality/${kindPath}/${issueId}/images`, {
    headers: token
  });
  return json(response);
}

async function uploadImage(token, kindPath, issueId, buffer, { type = 'image/png', caption } = {}) {
  const query = caption === undefined ? '' : `?caption=${encodeURIComponent(caption)}`;
  const response = await fetch(`${base}/api/quality/${kindPath}/${issueId}/images${query}`, {
    method: 'POST',
    headers: { ...token, 'content-type': type },
    body: buffer
  });
  return json(response);
}

async function readImage(token, kindPath, issueId, imageId) {
  const response = await fetch(`${base}/api/quality/${kindPath}/${issueId}/images/${imageId}`, {
    headers: token
  });
  return { status: response.status, type: response.headers.get('content-type'), bytes: Buffer.from(await response.arrayBuffer()) };
}

async function removeImage(token, kindPath, issueId, imageId) {
  const response = await fetch(`${base}/api/quality/${kindPath}/${issueId}/images/${imageId}`, {
    method: 'DELETE',
    headers: token
  });
  return { status: response.status };
}

async function readSlideShow(token, siteId) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/slide-show`, { headers: token });
  return json(response);
}

async function choose(token, kind, issueId, chosen) {
  const response = await fetch(`${base}/api/quality/slide-show/${kind}/${issueId}`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ chosen })
  });
  return json(response);
}

async function order(token, siteId, slides) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/slide-show/order`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ slides })
  });
  return json(response);
}

async function recordNonconformance(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordComplaint(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/complaints`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

let adminToken;

// A Site with an area and a line under it, a quality engineer granted on the
// area (so everything beneath is theirs), a Product, a Defect code and a
// Customer — all created through the API where an address exists for it.
async function makeGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Assembly' });
  const line = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line 2' });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: area.id, write: true }]
  });
  const reader = await insertAccount({
    displayName: 'Read-only Supervisor',
    grants: [{ orgUnitId: area.id, write: false }]
  });

  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);
  const customer = await createCustomer(adminToken);

  return { site, area, line, engineer, reader, product, defectCode, customer };
}

async function makeNonconformance(ground) {
  const recorded = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    quantity: 12,
    detectionPoint: 'in_process',
    description: 'Flash on the mating face.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.nonconformance;
}

async function makeComplaint(ground) {
  const recorded = await recordComplaint(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    customerId: ground.customer.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    quantity: 4,
    description: 'The customer reports four parts that will not seat.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.complaint;
}

test.before(async () => {
  process.env.BACKEND_PORT = '0';

  ({ server } = require('../../src/index'));
  ({ closePool } = require('../../src/platform/db'));
  pool = require('../../src/platform/db').getPool();

  if (!server.listening) {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
  }
  base = `http://127.0.0.1:${server.address().port}`;

  const admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
  adminToken = admin.token;
});

test.after(async () => {
  // Pictures first: they point at both records with plain foreign keys, so they
  // have to go before either table's rows. Then the records, then the fixtures
  // they were made from, hardest descendant first — a rejected cleanup hangs the
  // file on the framework's timeout and cancels every file behind it.
  await pool.query(
    `DELETE FROM quality_issue_images
      WHERE quality_issue_id IN (
              SELECT id FROM quality_issues
               WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1)))
         OR customer_complaint_id IN (
              SELECT id FROM customer_complaints
               WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1)))`,
    [insertedSiteIds]
  );
  await pool.query(
    `DELETE FROM customer_complaints
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query(
    `DELETE FROM quality_issues
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM customers WHERE code = ANY($1)', [insertedCustomerCodes]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// 1. A picture on each record kind
// ---------------------------------------------------------------------------

test('a picture is stored against a Non-conformance and served back at its own address', async () => {
  const ground = await makeGround();
  const nonconformance = await makeNonconformance(ground);
  const picture = pngBuffer(1600, 900);

  const uploaded = await uploadImage(ground.engineer.token, 'nonconformances', nonconformance.id, picture, {
    caption: '  Flash on the mating face, near the locating lug  '
  });
  assert.strictEqual(uploaded.status, 201, JSON.stringify(uploaded.body));
  const image = uploaded.body.image;
  assert.strictEqual(image.contentType, 'image/png');
  // Read from the file's own IHDR, not from anything the caller said.
  assert.deepStrictEqual([image.width, image.height, image.bytes], [1600, 900, picture.length]);
  assert.strictEqual(image.caption, 'Flash on the mating face, near the locating lug');

  const listed = await listImages(ground.engineer.token, 'nonconformances', nonconformance.id);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  assert.deepStrictEqual(listed.body.images.map((row) => row.id), [image.id]);

  const served = await readImage(ground.engineer.token, 'nonconformances', nonconformance.id, image.id);
  assert.strictEqual(served.status, 200);
  assert.strictEqual(served.type, 'image/png');
  assert.ok(served.bytes.equals(picture), 'the bytes served are the bytes stored');

  // The record's own read carries the flag the register row draws its toggle
  // from, and a record nobody chose is off the show.
  const record = await json(
    await fetch(`${base}/api/quality/nonconformances/${nonconformance.id}`, {
      headers: ground.engineer.token
    })
  );
  assert.strictEqual(record.body.nonconformance.inSlideShow, false);
});

test('a picture is stored against a customer complaint too', async () => {
  const ground = await makeGround();
  const complaint = await makeComplaint(ground);

  const uploaded = await uploadImage(
    ground.engineer.token,
    'complaints',
    complaint.id,
    pngBuffer(800, 600)
  );
  assert.strictEqual(uploaded.status, 201, JSON.stringify(uploaded.body));
  assert.strictEqual(uploaded.body.image.contentType, 'image/png');

  const listed = await listImages(ground.reader.token, 'complaints', complaint.id);
  assert.strictEqual(listed.status, 200);
  assert.strictEqual(listed.body.images.length, 1);
  // No caption sent is no caption, not an empty string.
  assert.strictEqual(listed.body.images[0].caption, null);
});

// ---------------------------------------------------------------------------
// 2. The upload's five refusals
// ---------------------------------------------------------------------------

test('the upload refuses a non-image, a mismatched type, a plain-text type, an over-large edge and an over-large body', async () => {
  const ground = await makeGround();
  const nonconformance = await makeNonconformance(ground);
  const path = ['nonconformances', nonconformance.id];

  const notAnImage = await uploadImage(
    ground.engineer.token,
    ...path,
    Buffer.from('this is not a picture, it is a sentence', 'utf8')
  );
  assert.strictEqual(notAnImage.status, 400);
  assert.match(notAnImage.body.message, /not a JPEG, PNG or WebP/);

  const wrongType = await uploadImage(ground.engineer.token, ...path, pngBuffer(400, 300), {
    type: 'image/jpeg'
  });
  assert.strictEqual(wrongType.status, 400);
  assert.match(wrongType.body.message, /image\/png/);

  const textBody = await uploadImage(ground.engineer.token, ...path, pngBuffer(400, 300), {
    type: 'text/plain'
  });
  assert.strictEqual(textBody.status, 415);
  assert.match(textBody.body.message, /image\/jpeg, image\/png, image\/webp/);

  const tooBigEdge = await uploadImage(ground.engineer.token, ...path, pngBuffer(1601, 900));
  assert.strictEqual(tooBigEdge.status, 413);
  assert.match(tooBigEdge.body.message, /1601x900/);

  const oversized = Buffer.alloc(5242881);
  pngBuffer(100, 100).copy(oversized, 0);
  const tooHeavy = await uploadImage(ground.engineer.token, ...path, oversized);
  assert.strictEqual(tooHeavy.status, 413);
  assert.match(tooHeavy.body.message, /5242881/);

  // Nothing was stored by any of the five.
  const listed = await listImages(ground.engineer.token, ...path);
  assert.deepStrictEqual(listed.body.images, []);
});

// ---------------------------------------------------------------------------
// 3. Scope: reading is the register's, writing is the record's
// ---------------------------------------------------------------------------

test('a reader outside the Site is refused, and a read Grant may look but not add', async () => {
  const ground = await makeGround();
  const nonconformance = await makeNonconformance(ground);
  const path = ['nonconformances', nonconformance.id];

  // A read Grant on the area reaches the line and the Site: the register's rule.
  const readable = await listImages(ground.reader.token, ...path);
  assert.strictEqual(readable.status, 200, JSON.stringify(readable.body));

  const refusedWrite = await uploadImage(ground.reader.token, ...path, pngBuffer(400, 300));
  assert.strictEqual(refusedWrite.status, 403);
  assert.strictEqual(refusedWrite.body.message, "Outside the caller's granted Org Units");

  // No Grant anywhere: the Site is not visible, so neither are its records.
  const outsider = await insertAccount({ displayName: 'No Grant At All' });
  const refusedRead = await listImages(outsider.token, ...path);
  assert.strictEqual(refusedRead.status, 403);

  // A record that is not there is a 404 before any scope question is asked.
  const missing = await listImages(ground.engineer.token, 'nonconformances', '999999999');
  assert.strictEqual(missing.status, 404);
  const missingUpload = await uploadImage(ground.engineer.token, 'nonconformances', '999999999', pngBuffer(10, 10));
  assert.strictEqual(missingUpload.status, 404);
});

// ---------------------------------------------------------------------------
// 4. Remove
// ---------------------------------------------------------------------------

test('a picture is removed, and a second removal is a 404', async () => {
  const ground = await makeGround();
  const nonconformance = await makeNonconformance(ground);
  const path = ['nonconformances', nonconformance.id];

  const uploaded = await uploadImage(ground.engineer.token, ...path, pngBuffer(640, 480));
  assert.strictEqual(uploaded.status, 201);

  const removed = await removeImage(ground.engineer.token, ...path, uploaded.body.image.id);
  assert.strictEqual(removed.status, 204);
  assert.deepStrictEqual((await listImages(ground.engineer.token, ...path)).body.images, []);

  const again = await removeImage(ground.engineer.token, ...path, uploaded.body.image.id);
  assert.strictEqual(again.status, 404);

  // A read-only Grant is refused the delete as well as the upload.
  const readOnlyUpload = await uploadImage(ground.engineer.token, ...path, pngBuffer(640, 480));
  const refused = await removeImage(ground.reader.token, ...path, readOnlyOnly(readOnlyUpload).id);
  assert.strictEqual(refused.status, 403);
});

// The upload above is asserted successful first; this keeps the failure message
// readable if it ever is not.
function readOnlyOnly(uploaded) {
  assert.strictEqual(uploaded.status, 201, JSON.stringify(uploaded.body));
  return uploaded.body.image;
}

// ---------------------------------------------------------------------------
// 5. The slide show
// ---------------------------------------------------------------------------

test('choosing issues builds a Site show in the order the picker writes', async () => {
  const ground = await makeGround();
  const nonconformance = await makeNonconformance(ground);
  const complaint = await makeComplaint(ground);

  // An issue with no picture cannot go on the wall: the card's own lean
  // default, refused with the sentence that names the fix.
  const early = await choose(ground.engineer.token, 'nonconformance', nonconformance.id, true);
  assert.strictEqual(early.status, 409);
  assert.match(early.body.message, /add a picture to this issue first/);

  // Two pictures on the Non-conformance, one on the complaint.
  const first = await uploadImage(ground.engineer.token, 'nonconformances', nonconformance.id, pngBuffer(1200, 800), {
    caption: 'Flash, wide shot'
  });
  const second = await uploadImage(ground.engineer.token, 'nonconformances', nonconformance.id, pngBuffer(900, 1200), {
    caption: 'Flash, close up'
  });
  const onComplaint = await uploadImage(ground.engineer.token, 'complaints', complaint.id, pngBuffer(1600, 1000));
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));
  assert.strictEqual(second.status, 201, JSON.stringify(second.body));
  assert.strictEqual(onComplaint.status, 201, JSON.stringify(onComplaint.body));

  const chosen = await choose(ground.engineer.token, 'nonconformance', nonconformance.id, true);
  assert.strictEqual(chosen.status, 200, JSON.stringify(chosen.body));
  assert.strictEqual(chosen.body.inSlideShow, true);

  let show = await readSlideShow(ground.reader.token, ground.site.id);
  assert.strictEqual(show.status, 200, JSON.stringify(show.body));
  assert.deepStrictEqual(show.body.issues.map((row) => row.number), [nonconformance.issueNo]);

  await choose(ground.engineer.token, 'complaint', complaint.id, true);

  show = await readSlideShow(ground.reader.token, ground.site.id);
  assert.strictEqual(show.body.issues.length, 2);
  // The complaint was chosen second and has no position yet, so it comes after
  // the ordered ones, then by when it was recorded.
  const [firstIssue, secondIssue] = show.body.issues;
  assert.strictEqual(firstIssue.kind, 'nonconformance');
  assert.strictEqual(firstIssue.images.length, 2);
  assert.deepStrictEqual(
    firstIssue.images.map((image) => image.caption),
    ['Flash, wide shot', 'Flash, close up']
  );
  assert.strictEqual(secondIssue.kind, 'complaint');
  assert.strictEqual(secondIssue.partyName, ground.customer.name);
  assert.strictEqual(secondIssue.images.length, 1);

  // The picker's own write: the complaint first, then the Non-conformance.
  // Ordering is a change to both records, so it needs the write Grant too —
  // proved first with the read-only caller.
  const refusedReorder = await order(ground.reader.token, ground.site.id, [
    { kind: 'complaint', id: complaint.id }
  ]);
  assert.strictEqual(refusedReorder.status, 403);

  const reordered = await order(ground.engineer.token, ground.site.id, [
    { kind: 'complaint', id: complaint.id },
    { kind: 'nonconformance', id: nonconformance.id }
  ]);
  assert.strictEqual(reordered.status, 200, JSON.stringify(reordered.body));
  assert.deepStrictEqual(reordered.body.issues.map((row) => row.kind), ['complaint', 'nonconformance']);
  assert.deepStrictEqual(reordered.body.issues.map((row) => row.position), [1, 2]);

  // An issue that is not in the show cannot be ordered into it.
  const stranger = await makeNonconformance(ground);
  const refused = await order(ground.engineer.token, ground.site.id, [
    { kind: 'nonconformance', id: stranger.id }
  ]);
  assert.strictEqual(refused.status, 409);
  assert.match(refused.body.message, /not in this Site's slide show/);

  // Taking an issue off the wall clears its place in the order.
  const taken = await choose(ground.engineer.token, 'complaint', complaint.id, false);
  assert.strictEqual(taken.body.inSlideShow, false);
  assert.strictEqual(taken.body.position, null);
  show = await readSlideShow(ground.reader.token, ground.site.id);
  assert.deepStrictEqual(show.body.issues.map((row) => row.kind), ['nonconformance']);

  // A picture removed after the issue was chosen leaves the choice standing and
  // the issue with nothing to show — the Screen's own "chosen, no picture" case
  // rather than a silent un-choose nobody asked for.
  await choose(ground.engineer.token, 'complaint', complaint.id, true);
  await removeImage(ground.engineer.token, 'complaints', complaint.id, onComplaint.body.image.id);
  show = await readSlideShow(ground.reader.token, ground.site.id);
  const complaintAgain = show.body.issues.find((row) => row.kind === 'complaint');
  assert.deepStrictEqual(complaintAgain.images, []);
});

test("a Site's show holds only its own records, and is refused to a reader with no Grant", async () => {
  const here = await makeGround();
  const elsewhere = await makeGround();

  const mine = await makeNonconformance(here);
  const theirs = await makeNonconformance(elsewhere);
  // Each needs a picture before it can be chosen (see the 409 above).
  await uploadImage(here.engineer.token, 'nonconformances', mine.id, pngBuffer(800, 600));
  await uploadImage(elsewhere.engineer.token, 'nonconformances', theirs.id, pngBuffer(800, 600));
  await choose(here.engineer.token, 'nonconformance', mine.id, true);
  await choose(elsewhere.engineer.token, 'nonconformance', theirs.id, true);

  const showHere = await readSlideShow(here.reader.token, here.site.id);
  assert.strictEqual(showHere.status, 200);
  assert.deepStrictEqual(showHere.body.issues.map((row) => row.id), [mine.id]);

  const showThere = await readSlideShow(elsewhere.reader.token, elsewhere.site.id);
  assert.deepStrictEqual(showThere.body.issues.map((row) => row.id), [theirs.id]);

  // Another Site's show is not this Site's, even to an administrator: the
  // address is the Site, and an unknown Site is a 404.
  const noSuchSite = await readSlideShow(adminToken, '999999999');
  assert.strictEqual(noSuchSite.status, 404);

  const outsider = await insertAccount({ displayName: 'No Grant At All' });
  const refused = await readSlideShow(outsider.token, here.site.id);
  assert.strictEqual(refused.status, 403);
  assert.strictEqual(refused.body.message, "Outside the caller's granted Org Units");

  // And choosing an issue needs a write Grant, not merely a read one.
  const refusedChoice = await choose(here.reader.token, 'nonconformance', mine.id, false);
  assert.strictEqual(refusedChoice.status, 403);
});
