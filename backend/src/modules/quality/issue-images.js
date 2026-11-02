/*
 * A picture of a Quality issue (issue #419) — the storage half, for both record
 * kinds that can carry one: a Non-conformance and a customer complaint.
 *
 * **One table, two parents.** `quality_issue_images` holds exactly one of
 * `quality_issue_id` / `customer_complaint_id`, which the table's own CHECK
 * states. This file's `ISSUE_KINDS` is that same pair, spelled once for the
 * routes and for the queries: the kind is the only thing the two shapes differ
 * by, so every statement here is one of two column names chosen from a map
 * rather than a second copy of the file.
 *
 * **Bytes are read only when they are served.** The list and the slide show read
 * metadata (id, type, size, caption); `readImageBytes` is the one query that
 * selects the `bytea`, and it does so for one row by its own id. A register that
 * lists six thumbnails therefore reads six small rows, and the browser fetches
 * each picture from its own address — which is also what lets the client cache
 * them and what keeps a 4 MB picture out of a JSON response.
 *
 * **No delete of an audit trail is offered.** An image row is deleted when the
 * person who put it there removes it, and `attach_audit` records the delete like
 * every other table's. The card asks for upload, replace and remove; "replace" is
 * remove-then-upload from the caller's point of view, and the audit trail is
 * what keeps that honest.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { readImageFile, readCaption } = require('./image-file');

// The two records that may carry a picture, and the column each one is filed on.
// A closed set: a kind outside it is a caller's mistake and the routes say so.
const ISSUE_KINDS = {
  nonconformance: { column: 'quality_issue_id', table: 'quality_issues', label: 'Non-conformance' },
  complaint: { column: 'customer_complaint_id', table: 'customer_complaints', label: 'Customer complaint' }
};

function requireKind(kind) {
  const entry = ISSUE_KINDS[kind];
  if (!entry) throw httpError(400, `kind must be one of ${Object.keys(ISSUE_KINDS).join(', ')}`);
  return entry;
}

// A picture as the register and the slide show read it: everything a thumbnail
// or a caption needs, and no bytes.
const IMAGE_COLUMNS = `
  id, quality_issue_id, customer_complaint_id,
  content_type, image_bytes, width, height, caption,
  created_at, updated_at`;

function toImage(row) {
  return {
    id: String(row.id),
    kind: row.quality_issue_id === null ? 'complaint' : 'nonconformance',
    contentType: row.content_type,
    width: row.width,
    height: row.height,
    bytes: row.image_bytes,
    caption: row.caption ?? null,
    createdAt: row.created_at
  };
}

/**
 * Stores one picture against one issue.
 *
 * [buffer] is the request body exactly as it arrived, [declaredType] its
 * `Content-Type`. The format, the width and the height are read from the bytes
 * themselves (`image-file.js`), never taken from the caller — so the row's
 * `content_type`, `width` and `height` are facts about the stored file rather
 * than a claim about it.
 */
async function addImage({ kind, issueId, buffer, declaredType, caption, accountId }) {
  const { column } = requireKind(kind);
  if (parseId(issueId) === null) throw notFound('Quality issue');

  const file = readImageFile(buffer, declaredType);
  const note = readCaption(caption);

  return withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `INSERT INTO quality_issue_images
         (${column}, content_type, image, image_bytes, width, height, caption)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING ${IMAGE_COLUMNS}`,
      [issueId, file.contentType, buffer, file.bytes, file.width, file.height, note]
    );
    return toImage(row);
  });
}

/** Every picture of one issue, oldest first — the order the slide show plays them. */
async function listImages({ kind, issueId }) {
  const { column } = requireKind(kind);
  if (parseId(issueId) === null) throw notFound('Quality issue');
  const { rows } = await getPool().query(
    `SELECT ${IMAGE_COLUMNS}
       FROM quality_issue_images
      WHERE ${column} = $1
      ORDER BY created_at, id`,
    [issueId]
  );
  return rows.map(toImage);
}

async function findByAddress({ kind, issueId, imageId }) {
  const { column } = requireKind(kind);
  if (parseId(issueId) === null || parseId(imageId) === null) throw notFound('Picture');
  const { rows: [row] } = await getPool().query(
    `SELECT ${IMAGE_COLUMNS}
       FROM quality_issue_images
      WHERE id = $1 AND ${column} = $2`,
    [imageId, issueId]
  );
  if (!row) throw notFound('Picture');
  return row;
}

/** One picture with its bytes, for the address that serves it. */
async function readImageBytes({ kind, issueId, imageId }) {
  const { column } = requireKind(kind);
  if (parseId(issueId) === null || parseId(imageId) === null) throw notFound('Picture');
  const { rows: [row] } = await getPool().query(
    `SELECT id, content_type, image, image_bytes, updated_at
       FROM quality_issue_images
      WHERE id = $1 AND ${column} = $2`,
    [imageId, issueId]
  );
  if (!row) throw notFound('Picture');
  return {
    contentType: row.content_type,
    bytes: row.image,
    etag: `"${row.id}-${row.image_bytes}-${new Date(row.updated_at).getTime()}"`
  };
}

/** Removes one picture. 404 for one that is not there or not this issue's. */
async function removeImage({ kind, issueId, imageId, accountId }) {
  const row = await findByAddress({ kind, issueId, imageId });
  await withActor(accountId, async (client) => {
    await client.query('DELETE FROM quality_issue_images WHERE id = $1', [row.id]);
  });
  return toImage(row);
}

/**
 * Every picture of these issues, grouped by issue id, oldest first.
 *
 * One query for a whole Site's slide show, rather than one per chosen issue:
 * the show is a read the wall repeats all day, and it is the one place where
 * "the register's six rows" becomes "the Site's twelve".
 */
async function listImagesFor(kind, issueIds) {
  const { column } = requireKind(kind);
  const grouped = new Map();
  if (issueIds.length === 0) return grouped;
  const { rows } = await getPool().query(
    `SELECT ${IMAGE_COLUMNS}
       FROM quality_issue_images
      WHERE ${column} = ANY($1::bigint[])
      ORDER BY created_at, id`,
    [issueIds]
  );
  for (const row of rows) {
    const key = String(row[column]);
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(toImage(row));
  }
  return grouped;
}

/**
 * How many pictures each of these issues has, in one query — what the Slide
 * show Screen needs to say "chosen, but no picture yet" without fetching every
 * picture of every chosen issue.
 */
async function countImages(kind, issueIds) {
  const { column } = requireKind(kind);
  if (issueIds.length === 0) return new Map();
  const { rows } = await getPool().query(
    `SELECT ${column} AS issue_id, count(*)::int AS image_count
       FROM quality_issue_images
      WHERE ${column} = ANY($1::bigint[])
      GROUP BY ${column}`,
    [issueIds]
  );
  return new Map(rows.map((row) => [String(row.issue_id), row.image_count]));
}

module.exports = {
  ISSUE_KINDS,
  addImage,
  listImages,
  listImagesFor,
  readImageBytes,
  removeImage,
  countImages
};
