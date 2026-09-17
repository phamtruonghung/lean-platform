/*
 * Non-conformances (issue #205) — the Quality Module's first record of real
 * work, after the two catalogues it was seeded with. A Non-conformance is what
 * an operator or an inspector writes down when product is found not to
 * conform: which Product, which Defect code, where it was detected, how much
 * of it there is, and where in the plant it was found. CONTEXT.md's own entry
 * is the definition this file implements.
 *
 * `quality_issues` is the baseline's table for it and this slice adds almost
 * nothing to the table itself — issue #200's spec names exactly what was
 * missing, and migration 1799900000000 adds it: `recorded_by_account_id`
 * (the baseline's `detected_by` is an Employee, which is the floor device's
 * shape, not a signed-in Account's) and `quality_issue_quantity_changes`, the
 * history of a number that grows as sorting finds more pieces.
 *
 * Four things about this file are worth reading before changing it.
 *
 * **The number comes from the Platform's own document numbering.**
 * `next_document_number('NC', siteCode, year)` — the same function a Work
 * order, a Request, a PM schedule and an Action receive their numbers from —
 * gives a Site-scoped, year-stamped, zero-padded sequence: NC-HCM-2026-00001.
 * The baseline's `quality_issues.issue_no` column carries a DEFAULT of its own
 * (`'NC-' || year || '-' || lpad(nextval('quality_issues_no_seq'))`), which
 * this file deliberately does not use: that sequence is not scoped by Site,
 * so with more than one plant in one database the numbers interleave and
 * NC-2026-00042 does not say which Site issued it — the exact problem
 * `next_document_number`'s own baseline comment is written to avoid, and these
 * numbers end up on containment labels and in audit findings. The write names
 * `issue_no` explicitly rather than letting the DEFAULT fire, and
 * `Nonconformance.issueNo` is asserted in the form
 * `/^NC-[A-Z0-9]+-\d{4}-\d{5}$/` by this Module's own test.
 *
 * **Who recorded it is an Account.** Every Non-conformance this slice records
 * is recorded by a signed-in Account, so `recorded_by_account_id` is always
 * set. The floor-device path (ADR-0016, which would name an Employee through
 * `detected_by` instead) is deliberately not built here — see the issue's own
 * out-of-scope list.
 *
 * **The production day and the shift are the database's answer, not this
 * file's.** `quality_issues` has carried the baseline's
 * `fill_shift_instance` trigger since the schema was written
 * (`SELECT attach_shift_instance('quality_issues', 'detected_at')`), so an
 * insert that supplies only `org_unit_id` and `detected_at` lands in the shift
 * instance that covers that moment, from which the production day (ADR-0017)
 * and the shift's own name are read back. This file resolves neither: a
 * JavaScript answer to "which shift was that" would be the second calendar
 * ADR-0017 refuses, and the trigger is "the one place that cannot forget".
 *
 * **The severity rule is a one-way ratchet in this slice.** A Non-conformance
 * starts at its Defect code's `default_severity`; the recorder may name a
 * higher one at recording time or raise it afterwards, and naming a lower one
 * is refused with a 403 here — not because a lower severity is always wrong,
 * but because lowering it is a Quality-authority decision (ADR-0035) that
 * issue #206 owns. `raiseSeverity`'s own comment says where that lands.
 *
 * Mirrors products.js/defect-codes.js: no HTTP, no caller awareness. Unlike
 * them, this file's records ARE placed in the Org Unit tree, so its queries
 * join `org_units` (and, for the optional Asset, `assets` — a cross-Module
 * read done as an ordinary SQL join, which ADR-0006's "code seams, not data
 * seams" rule allows explicitly). Scope is still not this file's business:
 * nonconformance-routes.js asks People before calling anything here.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// The value sets the baseline's own CHECK constraints enforce
// (`quality_issues_detection_point_check`, `quality_issues_severity_check`,
// `quality_issues_status_check`). Repeated here so a caller gets a sentence
// naming the field rather than a raw constraint violation, exactly as
// defect-codes.js repeats its own two — the sets are the database's, and a
// change to one must change both.
const DETECTION_POINTS = ['incoming', 'in_process', 'final_inspection', 'audit', 'customer'];
const SEVERITIES = ['minor', 'major', 'critical'];
const NONCONFORMANCE_STATUSES = ['open', 'contained', 'dispositioned', 'closed', 'cancelled'];

// The order the three severities sit in, worst last: "may the recorder set
// this one" is a comparison, not a membership test.
const SEVERITY_RANK = { minor: 1, major: 2, critical: 3 };

// The register's own cap, one row past which means "there is more" rather than
// a silently truncated Site. A Non-conformance log is read in periods (a shift,
// a week), so a cap that a real Site's month does not reach is big enough; a
// query the caller narrows is what the filters are for.
const NONCONFORMANCE_LIST_LIMIT = 200;

function severityRank(severity) {
  return SEVERITY_RANK[severity] ?? 0;
}

function requireMembership(field, value, allowed) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw httpError(400, `${field} must be one of ${allowed.join(', ')}`);
  }
}

// A quantity is positive, and is accepted as a number or as a numeric string
// (`'12'`, `12`, `'12.5'`). Anything else — a word, a negative, zero, NaN,
// Infinity — is a 400 naming the field. A string is accepted because a form
// sends text; it is NOT accepted as a way to smuggle a group separator past
// this check (`Number('1,000')` is NaN, which is refused).
function requirePositiveQuantity(field, value) {
  const quantity = typeof value === 'string' ? Number(value.trim()) : value;
  if (typeof quantity !== 'number' || !Number.isFinite(quantity) || quantity <= 0) {
    throw httpError(400, `${field} must be a positive quantity`);
  }
  return quantity;
}

// `quality_issues` is read every time through this one projection, so a row
// that was just recorded and a row read back from the register can never carry
// different fields. The joins are all to-one or to-none (the Asset and the
// shift instance are both optional), so no row is ever multiplied or dropped
// by them. `ou.path` rides along because the Org Unit the record sits at is
// what a caller reads before deciding anything about it, and `s.code` because
// it is what the number quotes.
const NONCONFORMANCE_COLUMNS = `
  qi.id, qi.issue_no, qi.status, qi.detection_point, qi.severity,
  qi.quantity_affected, qi.quantity_dispositioned, qi.uom_code,
  qi.lot_ref, qi.detected_at, qi.detected_by, qi.description,
  qi.immediate_containment, qi.recorded_by_account_id,
  qi.created_at, qi.updated_at,
  qi.org_unit_id, ou.name AS org_unit_name, ou.path AS org_unit_path,
  ou.site_id, s.code AS site_code, s.name AS site_name,
  qi.product_id, p.code AS product_code, p.name AS product_name,
  qi.defect_code_id, dc.code AS defect_code_code, dc.name AS defect_code_name,
  dc.default_severity AS defect_code_default_severity,
  qi.asset_id, a.code AS asset_code, a.name AS asset_name,
  qi.shift_instance_id,
  -- A DATE read as a to_char string, never as a JS Date: a production day is
  -- a day in the Site's own calendar (ADR-0017), and a Date object would be
  -- re-serialised as an instant at the server's midnight and read back a day
  -- out by anyone in another time zone. board.js reads its own production day
  -- the same way.
  to_char(si.production_date, 'YYYY-MM-DD') AS production_date,
  si.starts_at AS shift_starts_at, si.ends_at AS shift_ends_at,
  sd.code AS shift_code, sd.name AS shift_name`;

const NONCONFORMANCE_JOINS = `
  FROM quality_issues qi
  JOIN org_units ou ON ou.id = qi.org_unit_id
  JOIN sites s ON s.id = ou.site_id
  JOIN products p ON p.id = qi.product_id
  JOIN defect_codes dc ON dc.id = qi.defect_code_id
  LEFT JOIN assets a ON a.id = qi.asset_id
  LEFT JOIN shift_instances si ON si.id = qi.shift_instance_id
  LEFT JOIN shift_definitions sd ON sd.id = si.shift_definition_id`;

// One row of the quantity history, with whoever made the change named — an
// Account where the change was made by a signed-in person, an Employee where
// it was made at a floor device. The two are joined rather than left to the
// client because "who increased this" is the whole point of keeping the
// history, and a row saying only "an id" answers it badly.
const QUANTITY_CHANGE_COLUMNS = `
  qc.id, qc.previous_quantity, qc.new_quantity, qc.changed_at, qc.note,
  qc.changed_by_account_id, au.display_name AS changed_by_account_name,
  qc.changed_by_employee_id, e.display_name AS changed_by_employee_name`;

const QUANTITY_CHANGE_JOINS = `
  FROM quality_issue_quantity_changes qc
  LEFT JOIN app_users au ON au.id = qc.changed_by_account_id
  LEFT JOIN employees e ON e.id = qc.changed_by_employee_id`;

// NUMERIC arrives from Postgres as a string ('12.0000'); a quantity is a
// number to every caller of this Module (the client prints it, the tests
// compare it with `12`), so it crosses this boundary as one.
function toQuantity(value) {
  return value === null || value === undefined ? null : Number(value);
}

function toQuantityChange(row) {
  return {
    id: row.id,
    previousQuantity: toQuantity(row.previous_quantity),
    newQuantity: toQuantity(row.new_quantity),
    changedAt: row.changed_at,
    note: row.note,
    changedByAccountId: row.changed_by_account_id,
    changedByAccountName: row.changed_by_account_name ?? null,
    changedByEmployeeId: row.changed_by_employee_id,
    changedByEmployeeName: row.changed_by_employee_name ?? null
  };
}

function toNonconformance(row, quantityChanges = []) {
  return {
    id: row.id,
    issueNo: row.issue_no,
    status: row.status,
    detectionPoint: row.detection_point,
    severity: row.severity,
    quantityAffected: toQuantity(row.quantity_affected),
    quantityDispositioned: toQuantity(row.quantity_dispositioned),
    uomCode: row.uom_code,
    lotRef: row.lot_ref,
    detectedAt: row.detected_at,
    detectedBy: row.detected_by,
    recordedByAccountId: row.recorded_by_account_id,
    description: row.description,
    immediateContainment: row.immediate_containment,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    orgUnitPath: row.org_unit_path,
    siteId: row.site_id,
    siteCode: row.site_code,
    siteName: row.site_name,
    productId: row.product_id,
    productCode: row.product_code,
    productName: row.product_name,
    defectCodeId: row.defect_code_id,
    defectCodeCode: row.defect_code_code,
    defectCodeName: row.defect_code_name,
    defectCodeDefaultSeverity: row.defect_code_default_severity,
    assetId: row.asset_id,
    assetCode: row.asset_code ?? null,
    assetName: row.asset_name ?? null,
    // The production day and the shift, as the baseline's own trigger filed
    // them (ADR-0017). Both are null for a Site with no shift calendar
    // covering that moment — the schema's own comment says a caller must
    // handle that rather than guess, and guessing a calendar day is exactly
    // what the ADR refuses.
    shiftInstanceId: row.shift_instance_id,
    productionDate: row.production_date ?? null,
    shiftCode: row.shift_code ?? null,
    shiftName: row.shift_name ?? null,
    shiftStartsAt: row.shift_starts_at ?? null,
    shiftEndsAt: row.shift_ends_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    quantityChanges
  };
}

// A write against the quantity history can fail for one reason this file turns
// into a clean 409 rather than a 500: the CHECK that refuses anything that is
// not an increase. It should be unreachable — increaseQuantity refuses a
// decrease itself, in a sentence a caller can read — but the constraint is the
// invariant, and a race that reached it would otherwise echo a raw Postgres
// message naming the table and column. The attribution CHECK is a bug rather
// than a caller's mistake (this file always names the Account), so it is left
// to become the genuine failure it is.
function mapQuantityChangeWriteError(error) {
  if (error.code === '23514' && error.constraint === 'quality_issue_quantity_changes_increases') {
    return httpError(409, 'the affected quantity can only be increased');
  }
  return error;
}

/**
 * The Site's Non-conformances, newest first, narrowed by any of the filters
 * issue #205 asks for.
 *
 * Site-wide with no Grant filter, the same rule the Work order list, the Asset
 * register, the action log and the tier board already follow (#55, ADR-0009,
 * ADR-0032): Org Unit scope decides where an Account may *act*, not what it
 * may know about. `orgUnitPath` — resolved by the route from a `?orgUnitId=`
 * and handed here as the ltree path — narrows to one area **and everything
 * beneath it**, which is the "including beneath it" half of the ticket's own
 * criterion and the same `<@` walk actions.js's own register does.
 *
 * `from`/`to` are production days, not instants (ADR-0017). A quality log
 * asked for "the last week" is asking about the days the plant counted, and a
 * row filed against a night shift that began at 22:00 belongs to the
 * production day that shift opened, not to the calendar date its timestamp
 * fell on. A row whose Site had no shift instance covering it — the schema's
 * own documented case — falls back to its own detected date rather than being
 * silently excluded from every range.
 */
async function listNonconformances(
  siteId,
  {
    orgUnitPath = null,
    status = null,
    defectCodeId = null,
    productId = null,
    severity = null,
    from = null,
    to = null,
    limit = NONCONFORMANCE_LIST_LIMIT
  } = {}
) {
  const conditions = ['ou.site_id = $1'];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`qi.status = $${params.length}`);
  }
  if (defectCodeId !== null) {
    params.push(defectCodeId);
    conditions.push(`qi.defect_code_id = $${params.length}`);
  }
  if (productId !== null) {
    params.push(productId);
    conditions.push(`qi.product_id = $${params.length}`);
  }
  if (severity !== null) {
    params.push(severity);
    conditions.push(`qi.severity = $${params.length}`);
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`COALESCE(si.production_date, qi.detected_at::date) >= $${params.length}::date`);
  }
  if (to !== null) {
    params.push(to);
    conditions.push(`COALESCE(si.production_date, qi.detected_at::date) <= $${params.length}::date`);
  }

  // One row past the limit, so "there is more" is a fact rather than a guess —
  // the shape actions.js's own register keeps (ADR-0026: a capped list must
  // say it is capped rather than read as a whole Site).
  const { rows } = await getPool().query(
    `SELECT ${NONCONFORMANCE_COLUMNS}
     ${NONCONFORMANCE_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY qi.detected_at DESC, qi.id DESC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    nonconformances: rows.slice(0, limit).map((row) => toNonconformance(row)),
    truncated
  };
}

// The null-returning form, mirroring findAsset/findAction: a malformed id
// resolves to null rather than reaching Postgres as a BIGINT parameter.
async function findNonconformance(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${NONCONFORMANCE_COLUMNS} ${NONCONFORMANCE_JOINS} WHERE qi.id = $1`,
    [id]
  );
  return rows[0] ? toNonconformance(rows[0]) : null;
}

/**
 * One Non-conformance with its quantity history — what the detail Screen
 * reads, and what every write in this file answers with.
 *
 * The history is part of the record rather than a second read, because the
 * ticket's own criterion says so: "each change is kept with the previous and
 * new quantity, who and when, and is returned with the Non-conformance".
 * Ordered oldest first, which is the order a person reads a running count in.
 */
async function getNonconformanceDetail(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${NONCONFORMANCE_COLUMNS} ${NONCONFORMANCE_JOINS} WHERE qi.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return toNonconformance(rows[0], await listQuantityChanges(rows[0].id));
}

async function listQuantityChanges(qualityIssueId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${QUANTITY_CHANGE_COLUMNS}
     ${QUANTITY_CHANGE_JOINS}
     WHERE qc.quality_issue_id = $1
     ORDER BY qc.changed_at, qc.id`,
    [qualityIssueId]
  );
  return rows.map(toQuantityChange);
}

// The Product a Non-conformance is recorded against: it must exist and it must
// still be in use. Two refusals rather than one, because they are different
// mistakes — a Product that is not there at all is a 404, and one the plant
// has retired is a 409 naming the state that refused it (the same shape
// actions-routes.js gives a departed Employee).
async function resolveActiveProduct(productId) {
  if (parseId(productId) === null) throw httpError(400, 'productId must be a valid Product id');
  const { rows } = await getPool().query(
    'SELECT id, code, name, uom_code, is_active FROM products WHERE id = $1',
    [productId]
  );
  if (!rows[0]) throw notFound('Product');
  if (!rows[0].is_active) {
    throw httpError(409, 'that Product has been retired and a Non-conformance cannot be recorded against it');
  }
  return rows[0];
}

// The Defect code, with its `default_severity` — the value a
// Non-conformance's severity starts at. Same two refusals as the Product, for
// the same reason.
async function resolveActiveDefectCode(defectCodeId) {
  if (parseId(defectCodeId) === null) {
    throw httpError(400, 'defectCodeId must be a valid Defect code id');
  }
  const { rows } = await getPool().query(
    `SELECT id, code, name, default_severity, is_active
       FROM defect_codes
      WHERE id = $1`,
    [defectCodeId]
  );
  if (!rows[0]) throw notFound('Defect code');
  if (!rows[0].is_active) {
    throw httpError(409, 'that Defect code has been retired and a Non-conformance cannot be recorded against it');
  }
  return rows[0];
}

// An Asset, if one is named, must sit at the Org Unit the Non-conformance is
// recorded at or beneath it — issue #205's own criterion, and the reason the
// Asset is optional at all: a Non-conformance about a batch need not name a
// machine. `@>` asks "is this path an ancestor of that one", which is the same
// walk `ou.path <@ $::ltree` does in the other direction. A malformed id is
// the route's business (it parses before calling here); an id that names no
// Asset is a 404, and one that names an Asset elsewhere is a 400 rather than a
// 404 — the Asset exists, it is the placement that is wrong, and a caller can
// fix that by naming the right Org Unit.
async function resolveAssetAtOrgUnit(assetId, orgUnitPath) {
  if (assetId === null) return null;
  const { rows } = await getPool().query(
    `SELECT a.id, a.code, a.name, a.is_active, ou.path AS org_unit_path
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE a.id = $1`,
    [assetId]
  );
  if (!rows[0]) throw notFound('Asset');
  if (!rows[0].org_unit_path.startsWith(orgUnitPath)) {
    throw httpError(400, 'the Asset named does not sit at that Org Unit or beneath it');
  }
  return rows[0];
}

// The Site's short code, which the document number quotes. Read off the Org
// Unit's own Site rather than taken from a caller, so a number can never be
// issued against a Site the record does not sit in.
async function findSiteCodeForOrgUnit(orgUnitId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT s.code
       FROM org_units ou
       JOIN sites s ON s.id = ou.site_id
      WHERE ou.id = $1`,
    [orgUnitId]
  );
  return rows[0] ? rows[0].code : null;
}

/**
 * Record a Non-conformance (issue #205).
 *
 * The route has already resolved the Org Unit, refused a caller whose Grant
 * does not reach it with `write: true`, and parsed the Asset id; everything
 * that is a fact about the record itself is decided here.
 *
 * The `uom_code` is not an input: it is read off the Product, because a
 * quantity of a Product is measured in the unit that Product is defined in
 * (`products.uom_code`), and a caller free to name a different unit for the
 * same batch is a caller free to make the containment count wrong. ADR-0023's
 * rule in its positive form: a value with a known set is chosen, and the
 * choice here is the Product's.
 *
 * The number, the shift instance and the audit columns are all the database's
 * own work — `next_document_number` for the first, `fill_shift_instance` for
 * the second, the shared audit trigger for the third — so the INSERT names
 * only what a person actually decided. `status` starts `open` and becomes
 * `contained` when immediate containment is recorded in the same breath, which
 * is the one state transition this slice has.
 */
async function recordNonconformance(input, accountId) {
  const body = input ?? {};

  const orgUnitId = parseId(body.orgUnitId);
  if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');

  const assetId = body.assetId === undefined || body.assetId === null
    ? null
    : parseId(body.assetId);
  if (body.assetId !== undefined && body.assetId !== null && assetId === null) {
    throw httpError(400, 'assetId must be a valid Asset id');
  }

  requireMembership('detectionPoint', body.detectionPoint, DETECTION_POINTS);
  const quantityAffected = requirePositiveQuantity('quantity', body.quantity);

  const product = await resolveActiveProduct(body.productId);
  const defectCode = await resolveActiveDefectCode(body.defectCodeId);

  // The severity: the Defect code's default unless a higher one is named. The
  // comparison is against the *defect code's* default, not against a severity
  // already on the record, because there is no record yet — and naming a lower
  // one than the code's own default is the same decision #206 owns whether it
  // is taken at recording or afterwards.
  let severity = defectCode.default_severity;
  if (body.severity !== undefined && body.severity !== null) {
    requireMembership('severity', body.severity, SEVERITIES);
    if (severityRank(body.severity) < severityRank(defectCode.default_severity)) {
      throw httpError(
        403,
        `severity cannot be set below this Defect code's own ${defectCode.default_severity}`
      );
    }
    severity = body.severity;
  }

  const { rows: [orgUnit] } = await getPool().query(
    'SELECT id, path FROM org_units WHERE id = $1',
    [orgUnitId]
  );
  if (!orgUnit) throw notFound('Org Unit');

  if (assetId !== null) await resolveAssetAtOrgUnit(assetId, orgUnit.path);

  const lotRef = typeof body.lotRef === 'string' && body.lotRef.trim() !== ''
    ? body.lotRef.trim()
    : null;
  const description = typeof body.description === 'string' && body.description.trim() !== ''
    ? body.description.trim()
    : null;
  const immediateContainment =
    typeof body.immediateContainment === 'string' && body.immediateContainment.trim() !== ''
      ? body.immediateContainment.trim()
      : null;

  try {
    const id = await withActor(accountId, async (client) => {
      const siteCode = await findSiteCodeForOrgUnit(orgUnitId, client);
      if (!siteCode) throw notFound('Site');

      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('NC', $1, EXTRACT(YEAR FROM now())::int) AS issue_no`,
        [siteCode]
      );

      const { rows: [row] } = await client.query(
        `INSERT INTO quality_issues (
           issue_no, org_unit_id, asset_id, product_id, defect_code_id,
           detection_point, severity, quantity_affected, uom_code, lot_ref,
           detected_at, description, immediate_containment, status,
           recorded_by_account_id
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                 COALESCE($11::timestamptz, now()), $12, $13, $14, $15)
         RETURNING id`,
        [
          numberRow.issue_no,
          orgUnitId,
          assetId,
          product.id,
          defectCode.id,
          body.detectionPoint,
          severity,
          quantityAffected,
          product.uom_code,
          lotRef,
          body.detectedAt ?? null,
          description,
          immediateContainment,
          immediateContainment === null ? 'open' : 'contained',
          accountId ?? null
        ]
      );
      return row.id;
    });

    // Re-read through the detail projection, so a recorded Non-conformance and
    // one read back later are the same shape, history included (empty).
    return await getNonconformanceDetail(String(id));
  } catch (error) {
    throw mapQuantityChangeWriteError(error);
  }
}

/**
 * Raise the severity — or record the containment that makes the record
 * `contained`.
 *
 * The ratchet is one-way here on purpose. A higher severity is what finding
 * out more about a failure looks like, and any Account that reached the Org
 * Unit to record it can say so. A *lower* one is a Quality-authority decision
 * (ADR-0035): it decides that nonconforming product is less bad than the
 * Defect code says, which is the same judgement a Concession makes, and issue
 * #206 gives that judgement to a Grant carrying Quality authority. Refusing it
 * with a 403 — the code a permission refusal gets, not the 409 a state
 * conflict gets — is what that ticket says to do in this slice.
 *
 * `immediateContainment` is the second half, and it is what moves `open` to
 * `contained` (issue #205's own criterion). An already-`contained` record may
 * have its containment text corrected; the status is left alone rather than
 * re-set, because re-setting it would overwrite a later state this slice does
 * not know about.
 */
async function updateNonconformance(id, input, accountId) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');

  const body = input ?? {};
  const sets = [];
  const params = [];

  if (Object.prototype.hasOwnProperty.call(body, 'severity')) {
    requireMembership('severity', body.severity, SEVERITIES);
    if (severityRank(body.severity) < severityRank(existing.severity)) {
      throw httpError(403, 'severity cannot be lowered; only a holder of Quality authority may do that');
    }
    params.push(body.severity);
    sets.push(`severity = $${params.length}`);
  }

  if (Object.prototype.hasOwnProperty.call(body, 'immediateContainment')) {
    if (typeof body.immediateContainment !== 'string' || body.immediateContainment.trim() === '') {
      throw httpError(400, 'immediateContainment is required when it is sent');
    }
    params.push(body.immediateContainment.trim());
    sets.push(`immediate_containment = $${params.length}`);
    if (existing.status === 'open') {
      params.push('contained');
      sets.push(`status = $${params.length}`);
    }
  }

  if (sets.length === 0) {
    // Nothing to change — the existing record, unmodified, rather than an
    // UPDATE with an empty SET list (which Postgres would reject outright).
    return getNonconformanceDetail(id);
  }

  params.push(id);
  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE quality_issues SET ${sets.join(', ')} WHERE id = $${params.length}`,
        params
      );
    });
  } catch (error) {
    throw mapQuantityChangeWriteError(error);
  }
  return getNonconformanceDetail(id);
}

/**
 * Increase the affected quantity, keeping what it was before (issue #205).
 *
 * The affected quantity grows as sorting finds more pieces, and never shrinks:
 * an increase is a bigger containment, and a decrease would silently un-say a
 * number that has already gone onto a label, into an email and onto the
 * customer's own paperwork. So a decrease is refused with a 409 — a state
 * conflict, which is what it is — and so is a "change" that changes nothing,
 * because a history row recording `12 -> 12` is noise a reader has to rule out
 * rather than information.
 *
 * The write and the history row go in one transaction: a quantity that moved
 * with no row saying who moved it is the state the history table exists to
 * prevent. The `changed_by_account_id` is the signed-in Account, which is the
 * only shape this slice has — an Employee at a floor device is the other
 * column, and the ticket that builds that path fills it.
 */
async function increaseQuantity(id, input, accountId) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');

  const body = input ?? {};
  const quantity = requirePositiveQuantity('quantity', body.quantity);

  if (quantity === existing.quantityAffected) {
    throw httpError(409, 'the affected quantity is already that; a change records a difference');
  }
  if (quantity < existing.quantityAffected) {
    throw httpError(409, 'the affected quantity can only be increased');
  }

  const note = typeof body.note === 'string' && body.note.trim() !== '' ? body.note.trim() : null;

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE quality_issues SET quantity_affected = $1 WHERE id = $2`,
        [quantity, id]
      );
      await client.query(
        `INSERT INTO quality_issue_quantity_changes (
           quality_issue_id, previous_quantity, new_quantity,
           changed_by_account_id, note
         )
         VALUES ($1, $2, $3, $4, $5)`,
        [id, existing.quantityAffected, quantity, accountId ?? null, note]
      );
    });
  } catch (error) {
    throw mapQuantityChangeWriteError(error);
  }

  return getNonconformanceDetail(id);
}

module.exports = {
  DETECTION_POINTS,
  SEVERITIES,
  NONCONFORMANCE_STATUSES,
  listNonconformances,
  findNonconformance,
  getNonconformanceDetail,
  listQuantityChanges,
  recordNonconformance,
  updateNonconformance,
  increaseQuantity
};
