/*
 * A Signature (issue #317, CONTEXT.md's Signature, ADR-0052): an Employee's
 * own mark, kept as a small PNG in `employee_signatures`.
 *
 * This file owns the SQL and the validation of the image itself. It never
 * requires another Module and is unaware of who is calling: signature-routes.js
 * resolves the caller's own Employee and hands the id in. The table is
 * append-only - setting a Signature supersedes the previous kept row by
 * stamping `superseded_at`, and removing one does the same; no row is ever
 * rewritten or deleted.
 *
 * The image is validated by this file's own few lines, with no image
 * dependency (ADR-0052): the PNG signature, a well-formed IHDR chunk, a byte
 * ceiling, and a normalised box. The client does the pixel work; the server
 * only refuses what is not a small PNG.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

// 48 KiB. Base64 of this is ~64 KiB, which fits inside the API's existing
// `express.json({ limit: '100kb' })`, so that limit is not raised (ADR-0052).
const MAX_IMAGE_BYTES = 48 * 1024;

// The normalised box: a Signature is a wide, short mark. The client scales
// whatever it is given to fit inside 600 x 300 (and draws on a pad of that
// shape), so the server accepts a PNG whose declared width is 1..600 and
// height is 1..300 and refuses anything outside it.
const MAX_WIDTH = 600;
const MAX_HEIGHT = 300;

const ORIGINS = ['upload', 'on_screen'];

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
// signature (8) + IHDR chunk: length (4) + type (4) + data (13) + crc (4).
const IHDR_END = 8 + 4 + 4 + 13 + 4;

const EMPLOYEE_HAS_ACCOUNT =
  'This Employee holds an Account of their own, so only they can set their Signature';

const NO_SIGNATURE = 'No Signature is kept for this Employee';

function decodeImage(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, 'image is required: send the Signature as a base64 PNG');
  }
  const text = value.trim();
  if (text.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(text)) {
    throw httpError(400, 'image must be a base64 PNG');
  }
  const bytes = Buffer.from(text, 'base64');
  if (bytes.length > MAX_IMAGE_BYTES) {
    throw httpError(400, `image is too large: a Signature is at most ${MAX_IMAGE_BYTES / 1024} KiB`);
  }
  if (
    bytes.length < IHDR_END ||
    !bytes.subarray(0, 8).equals(PNG_SIGNATURE) ||
    bytes.readUInt32BE(8) !== 13 ||
    bytes.toString('latin1', 12, 16) !== 'IHDR'
  ) {
    throw httpError(400, 'image must be a PNG');
  }
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (width < 1 || height < 1 || width > MAX_WIDTH || height > MAX_HEIGHT) {
    throw httpError(
      400,
      `image is ${width} x ${height} pixels: a Signature fits inside ${MAX_WIDTH} x ${MAX_HEIGHT}`
    );
  }
  return bytes;
}

function requireOrigin(value) {
  if (value === undefined || value === null) return 'upload';
  if (!ORIGINS.includes(value)) {
    throw httpError(400, `origin must be one of: ${ORIGINS.join(', ')}`);
  }
  return value;
}

// Keeps `image` as the Employee's current Signature, superseding the one kept
// before it in the same transaction. Returns nothing about the image: the
// caller reads it back through getCurrentSignature.
async function keepSignature(accountId, employeeId, body) {
  const image = decodeImage(body?.image);
  const origin = requireOrigin(body?.origin);
  try {
    return await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE employee_signatures SET superseded_at = now()
          WHERE employee_id = $1 AND kept AND superseded_at IS NULL`,
        [employeeId]
      );
      const { rows } = await client.query(
        `INSERT INTO employee_signatures (employee_id, image, image_bytes, origin, kept, set_by_account_id)
         VALUES ($1, $2, $3, $4, TRUE, $5)
         RETURNING id, origin, image_bytes, created_at`,
        [employeeId, image, image.length, origin, accountId]
      );
      return toSignature(rows[0]);
    });
  } catch (error) {
    if (error.code === '23505') {
      throw httpError(409, 'A Signature was just set for this Employee. Try again.');
    }
    // The database's own rule (migration 1802800000000, ADR-0053): a kept mark
    // for an Employee who holds an Account is set by that Account. This is the
    // rule that holds; requireNoAccount, below, is only the ordinary-case
    // wording ahead of it. Keep both - removing either because it "duplicates"
    // the other reopens the window between the check and the write.
    if (error.code === '23514' && /^a Signature for an Employee with an Account/.test(error.message)) {
      throw httpError(409, EMPLOYEE_HAS_ACCOUNT);
    }
    throw error;
  }
}

// The current Signature's image bytes, or a 404.
async function getCurrentSignature(employeeId) {
  const { rows } = await getPool().query(
    `SELECT image FROM employee_signatures
      WHERE employee_id = $1 AND kept AND superseded_at IS NULL`,
    [employeeId]
  );
  if (rows.length === 0) throw notFound('Signature');
  return rows[0].image;
}

// Supersedes the current Signature; the row stays. 404 when none is kept.
async function removeSignature(accountId, employeeId) {
  const removed = await withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      `UPDATE employee_signatures SET superseded_at = now()
        WHERE employee_id = $1 AND kept AND superseded_at IS NULL`,
      [employeeId]
    );
    return rowCount;
  });
  if (removed === 0) throw notFound('Signature');
}

// An administrator sets a Signature only for an Employee who cannot: one that
// holds no Account. Whether an Employee holds one is `app_users.employee_id`.
// This check gives the wording in the ordinary case; the trigger on
// `employee_signatures` (ADR-0053) is the rule that holds when a link lands
// between this read and the write. Keep both - keepSignature maps the
// trigger's refusal to this same 409.
async function requireNoAccount(employeeId) {
  const { rows } = await getPool().query('SELECT 1 FROM app_users WHERE employee_id = $1 LIMIT 1', [employeeId]);
  if (rows.length > 0) throw httpError(409, EMPLOYEE_HAS_ACCOUNT);
}

// The current Signature's metadata for an administrator: who set it and
// whether they set it for the Employee (`setForEmployee`) or the Employee
// set it themselves (the setter's Account is linked to this Employee).
async function getCurrentSignatureDetails(employeeId) {
  const { rows } = await getPool().query(
    `SELECT s.id, s.origin, s.image_bytes, s.created_at, s.set_by_account_id,
            u.display_name AS set_by_name, u.employee_id AS set_by_employee_id
       FROM employee_signatures s
       LEFT JOIN app_users u ON u.id = s.set_by_account_id
      WHERE s.employee_id = $1 AND s.kept AND s.superseded_at IS NULL`,
    [employeeId]
  );
  if (rows.length === 0) throw notFound('Signature');
  const row = rows[0];
  return {
    ...toSignature(row),
    setByAccountId: row.set_by_account_id === null ? null : String(row.set_by_account_id),
    setByName: row.set_by_name ?? null,
    setForEmployee: String(row.set_by_employee_id) !== String(employeeId)
  };
}

// What a Trainee's answer asks to be signed with: `{ use: 'stored' }`, an
// inline `{ image }`, or nothing. Returns null (nothing), 'stored', or the
// decoded PNG bytes. Pure request-shape and image validation - the same four
// image refusals as keepSignature, because it is the same decodeImage.
function parseApplied(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw httpError(400, 'signature must be { use: "stored" } or { image: <base64 PNG> }');
  }
  const hasUse = value.use !== undefined;
  const hasImage = value.image !== undefined;
  if (hasUse === hasImage) {
    throw httpError(400, 'signature must carry exactly one of use or image');
  }
  if (hasUse) {
    if (value.use !== 'stored') throw httpError(400, 'signature use must be "stored"');
    return 'stored';
  }
  return decodeImage(value.image);
}

// Inside the caller's transaction: the id of the Employee's own current kept
// Signature, or a 400 when they keep none (never a silent no-signature).
async function currentSignatureId(client, employeeId) {
  const { rows } = await client.query(
    `SELECT id FROM employee_signatures
      WHERE employee_id = $1 AND kept AND superseded_at IS NULL`,
    [employeeId]
  );
  if (rows.length === 0) throw httpError(400, 'no Signature kept: draw one now or answer without one');
  return rows[0].id;
}

// Inside the caller's transaction: a one-off row for a stroke drawn for one
// act. Never kept, so never current and it supersedes nothing.
async function insertDrawnSignature(client, accountId, employeeId, image) {
  const { rows } = await client.query(
    `INSERT INTO employee_signatures (employee_id, image, image_bytes, origin, kept, set_by_account_id)
     VALUES ($1, $2, $3, 'on_screen', FALSE, $4)
     RETURNING id`,
    [employeeId, image, image.length, accountId]
  );
  return rows[0].id;
}

function toSignature(row) {
  return {
    id: String(row.id),
    origin: row.origin,
    imageBytes: row.image_bytes,
    createdAt: row.created_at
  };
}

module.exports = {
  MAX_IMAGE_BYTES,
  MAX_WIDTH,
  MAX_HEIGHT,
  NO_SIGNATURE,
  EMPLOYEE_HAS_ACCOUNT,
  requireNoAccount,
  getCurrentSignatureDetails,
  keepSignature,
  parseApplied,
  currentSignatureId,
  insertDrawnSignature,
  getCurrentSignature,
  removeSignature
};
