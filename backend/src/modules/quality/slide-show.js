/*
 * The slide show's chosen set (issue #418): which Quality issues a supervisor
 * put on the wall, in what order, and the pictures to draw for each.
 *
 * **The choice is a column on the record, not a membership table.** The card
 * asked for `in_slide_show` on the issue itself, and the reason holds up: the
 * person choosing is already in the register or on the record, so choosing is a
 * toggle on the row in front of them rather than a separate booking screen. The
 * order is the second column, `slide_show_position`, written by the Slide show
 * Screen's own picker.
 *
 * **A show is one Site's, exactly like a register.** Both records are filed at
 * an Org Unit and every Org Unit has a Site, so "what is on the wall at this
 * plant" is a filter on `ou.site_id` — and the route in front of this file asks
 * `people.canSeeSite` for that Site, which is the same question the registers
 * ask. An issue nobody may see at that Site cannot appear in its show, because
 * it cannot appear in its registers either.
 *
 * **A slide is one picture, and the overlay repeats per picture.** An issue with
 * three pictures is three consecutive slides: the shop floor wants the detail
 * shots, not one hero image and a promise of more. So the flattened list is
 * built here (issue order, then that issue's own pictures oldest first) rather
 * than in the client, and an issue with no picture yet contributes no slide —
 * it is still *chosen*, and the picker says so.
 *
 * **The order is written, not inferred.** `slide_show_position` is 1..n as the
 * picker left it; a chosen issue that nobody has ordered yet has NULL and sorts
 * after the ordered ones, then by when it was recorded. That is what makes "a
 * new choice appears at the end" true without rewriting every other position.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const images = require('./issue-images');

// The two record kinds, and what a slide needs from each. The selected columns
// line up one for one, so the UNION ALL is a single statement and the mapper
// below is a single shape.
const ISSUE_QUERIES = {
  nonconformance: {
    select: `
      SELECT 'nonconformance' AS kind, qi.id, qi.issue_no AS number, qi.status,
             qi.severity, qi.detected_at AS occurred_at, qi.slide_show_position,
             p.name AS product_name, ou.name AS org_unit_name,
             NULL::text AS party_name`,
    from: `
        FROM quality_issues qi
        JOIN org_units ou ON ou.id = qi.org_unit_id
        LEFT JOIN products p ON p.id = qi.product_id`
  },
  complaint: {
    select: `
      SELECT 'complaint' AS kind, cc.id, cc.complaint_no AS number, cc.status,
             cc.severity, cc.received_at AS occurred_at, cc.slide_show_position,
             p.name AS product_name, ou.name AS org_unit_name,
             c.name AS party_name`,
    from: `
        FROM customer_complaints cc
        JOIN org_units ou ON ou.id = cc.org_unit_id
        LEFT JOIN products p ON p.id = cc.product_id
        JOIN customers c ON c.id = cc.customer_id`
  }
};

function toIssue(row) {
  return {
    kind: row.kind,
    id: String(row.id),
    number: row.number,
    status: row.status,
    severity: row.severity,
    occurredAt: row.occurred_at,
    position: row.slide_show_position === null ? null : Number(row.slide_show_position),
    productName: row.product_name ?? null,
    orgUnitName: row.org_unit_name,
    partyName: row.party_name ?? null,
    images: []
  };
}

/**
 * One Site's chosen issues, in the show's own order, each with its pictures.
 *
 * The order is `slide_show_position` then when the issue was recorded, so a
 * chosen-but-unordered issue lands at the end rather than at the top where it
 * would push yesterday's slides off the wall.
 */
async function listForSite(siteId) {
  if (parseId(siteId) === null) throw notFound('Site');

  const { rows } = await getPool().query(
    `
    SELECT * FROM (
      ${ISSUE_QUERIES.nonconformance.select}
        ${ISSUE_QUERIES.nonconformance.from}
       WHERE qi.in_slide_show AND ou.site_id = $1
      UNION ALL
      ${ISSUE_QUERIES.complaint.select}
        ${ISSUE_QUERIES.complaint.from}
       WHERE cc.in_slide_show AND ou.site_id = $1
    ) chosen
    ORDER BY slide_show_position NULLS LAST, occurred_at, kind, id`,
    [siteId]
  );

  const issues = rows.map(toIssue);
  const byKind = { nonconformance: [], complaint: [] };
  for (const issue of issues) byKind[issue.kind]?.push(issue.id);

  for (const [kind, ids] of Object.entries(byKind)) {
    if (ids.length === 0) continue;
    const withImages = await images.listImagesFor(kind, ids);
    for (const issue of issues) {
      if (issue.kind === kind) issue.images = withImages.get(issue.id) ?? [];
    }
  }

  return issues;
}

/**
 * Puts one issue in the show, or takes it out.
 *
 * **An issue with no picture cannot go on the wall.** The card's own lean
 * default: a slide is a picture, so choosing an issue that has none would book
 * a blank screen into the loop. The refusal is a 409 naming the fix rather than
 * a silent no-op, and it is checked here rather than at the picker because a
 * record's pictures can arrive after it was chosen — and be removed after too,
 * which is why the read below still tolerates a chosen issue with none.
 *
 * Taking it out clears the position too: an issue that is not chosen has no
 * place in an order, and leaving a stale one would make it jump to the front if
 * it were chosen again.
 */
async function setChosen({ kind, id, chosen, accountId }) {
  const column = issueColumn(kind);
  if (parseId(id) === null) throw notFound('Quality issue');
  if (typeof chosen !== 'boolean') throw httpError(400, 'chosen must be true or false');

  return withActor(accountId, async (client) => {
    if (chosen) {
      const { rows: [counted] } = await client.query(
        `SELECT count(*)::int AS pictures FROM quality_issue_images WHERE ${column.column} = $1`,
        [id]
      );
      if (counted.pictures === 0) {
        throw httpError(
          409,
          'add a picture to this issue first: a slide without one is a blank screen on the wall'
        );
      }
    }
    const { rows: [row] } = await client.query(
      `UPDATE ${column.table}
          SET in_slide_show = $2,
              slide_show_position = CASE WHEN $2 THEN slide_show_position ELSE NULL END
        WHERE id = $1
        RETURNING id, in_slide_show, slide_show_position`,
      [id, chosen]
    );
    if (!row) throw notFound(column.label);
    return {
      kind,
      id: String(row.id),
      inSlideShow: row.in_slide_show,
      position: row.slide_show_position === null ? null : Number(row.slide_show_position)
    };
  });
}

/**
 * Writes the order the show plays in: position 1 is the first slide.
 *
 * Every entry must already be chosen and belong to [siteId] — the order is a
 * statement about this Site's wall, and moving something that is not on it
 * would be a silent no-op the caller could not see. Any other entry refuses the
 * whole request, because a half-written order is a wall that jumps mid-round.
 */
async function setOrder({ siteId, entries, accountId }) {
  if (parseId(siteId) === null) throw notFound('Site');
  if (!Array.isArray(entries)) throw httpError(400, 'slides must be a list of { kind, id }');
  if (entries.length === 0) throw httpError(400, 'slides must name at least one issue');

  const seen = new Set();
  const prepared = entries.map((entry, index) => {
    if (typeof entry !== 'object' || entry === null) {
      throw httpError(400, `slides[${index}] must be an object with a kind and an id`);
    }
    const column = issueColumn(entry.kind);
    if (parseId(entry.id) === null) {
      throw httpError(400, `slides[${index}].id must be an id`);
    }
    const key = `${entry.kind}:${entry.id}`;
    if (seen.has(key)) throw httpError(400, `slides[${index}] repeats an issue already in the list`);
    seen.add(key);
    return { kind: entry.kind, id: String(entry.id), column, position: index + 1 };
  });

  await withActor(accountId, async (client) => {
    for (const entry of prepared) {
      const { rowCount } = await client.query(
        `UPDATE ${entry.column.table} AS issue
            SET slide_show_position = $3
           FROM org_units ou
          WHERE issue.id = $1
            AND ou.id = issue.org_unit_id
            AND ou.site_id = $2
            AND issue.in_slide_show`,
        [entry.id, siteId, entry.position]
      );
      if (rowCount === 0) {
        throw httpError(409, `${entry.column.label} ${entry.id} is not in this Site's slide show`);
      }
    }
  });

  return listForSite(siteId);
}

function issueColumn(kind) {
  const entry = images.ISSUE_KINDS[kind];
  if (!entry) throw httpError(400, `kind must be one of ${Object.keys(images.ISSUE_KINDS).join(', ')}`);
  return entry;
}

module.exports = {
  listForSite,
  setChosen,
  setOrder
};
