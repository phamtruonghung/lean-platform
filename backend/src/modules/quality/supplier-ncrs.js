/*
 * Supplier NCRs (issue #215) — an incoming lot the Supplier got wrong, and the
 * Non-conformance that controls the product it was found on.
 *
 * `supplier_ncrs` is a baseline table and this file uses it as it stands, with
 * no column added to it anywhere. Every field the ticket's criteria name is
 * already there — `incoming_lot_ref` for the lot the inspector quotes, the
 * `defect_code_id` chosen from the catalogue, the baseline's own
 * `disposition` CHECK for the five answers to "what happens to this material",
 * `cost_recovered` and its `currency` for what was clawed back, and
 * `closed_at` for the end of it. That last one is the reason this slice needs
 * no migration: unlike a customer complaint, whose slice had to add somewhere
 * to write the response a customer was given, a supplier NCR's closing state is
 * already in the schema. The baseline's own comment is the design, and this
 * slice reads it literally: "`cost_recovered` is the column that changes
 * behaviour. A supplier problem logged without a recovery figure is an
 * inconvenience; the same problem with the cost attached is a conversation with
 * the supplier, and it is the only way incoming quality ever appears in the C
 * pillar."
 *
 * **One supplier NCR names one Non-conformance, and that is the baseline's own
 * shape rather than a simplification.** `supplier_ncrs.quality_issue_id` is a
 * column — one value — and this is the answer issue #208 gave for the
 * Non-conformance-to-Concern link and issue #214 gave again for a complaint,
 * answered the same way a third time. The reverse is deliberately not
 * symmetric: two NCRs about the same bad lot may name the same Non-conformance,
 * so a Non-conformance's own detail read returns a *list* of the supplier NCRs
 * that name it (see nonconformances.js's `listSupplierNcrs`), while an NCR
 * names one.
 *
 * **A linked Non-conformance must be about the NCR's own Product, when the NCR
 * carries one.** The link exists to say the received product is controlled; a
 * Non-conformance about a different Product does not control it. A supplier NCR
 * may name no Product at all — the baseline leaves `product_id` nullable, and
 * what an inspector has in front of them is a lot, not always a finished
 * product — so the check is a fact about two rows that are both present and is
 * skipped when the NCR names none.
 *
 * **The Defect code is copied when a Non-conformance is recorded from the
 * NCR**, so the record carries the NCR's own Product and Defect code with
 * `detection_point = 'incoming'` — the goods-in gate is where the plant found
 * out. The Product is required to record one (`quality_issues.product_id` is
 * NOT NULL) and this table's is nullable, so a body that names neither the
 * NCR's Product nor one of its own is refused with a 400 saying which field is
 * missing rather than a raw NOT NULL failure.
 *
 * **The response due date is a day, stored as the instant that day ends at the
 * Site.** `response_due_at` is a TIMESTAMPTZ in the baseline and the form
 * chooses a date (ADR-0023), so "due 2026-09-20" is stored as the end of that
 * day in the Site's own timezone (ADR-0017's rule that a day belongs to the
 * Site's calendar) — the NCR is late once the day the Supplier was given has
 * finished, not at midnight when it started. `isOverdue` is then the fact a
 * reader asks about: past its due instant and not yet finished with, which is
 * why a closed NCR is never marked late, while `daysOverdue` still says how
 * late the answer was or is.
 *
 * **Two statements, and it is worth being plain about it.** Recording a
 * Non-conformance from an NCR calls this Module's own recording service (one
 * definition of how a Non-conformance is numbered, validated and
 * severity-ratcheted — never a second INSERT) and then writes the link in a
 * second statement, rather than wrapping both in one transaction. The failure
 * this leaves reachable is a Non-conformance recorded but not yet linked, which
 * is a whole record on its own and is recoverable through the NCR's own link
 * address in the same slice; nothing is left half-written. The alternative was
 * threading a transaction through the recording service, which is a
 * Non-conformance slice's own shape and not this ticket's to change.
 *
 * **The disposition is a field and the closure is the one transition.** The
 * plant's answer for the material — return it, scrap it, have it reworked at
 * the Supplier's cost, sort it, use it as it is — is recorded on the row and
 * does not move `status`; the baseline's other statuses (`issued`, `responded`)
 * are accepted by the register's own filter and left for another slice rather
 * than invented here. Recording the disposition a second time corrects it,
 * which is the difference between a field and the one link this table can
 * carry.
 *
 * Mirrors the rest of the Module: this file knows nothing about HTTP or about
 * who is calling. Its own private helpers stay private, and it reaches
 * `nonconformances.js` and `suppliers.js` directly — all three are this
 * Module's own files, which ADR-0006 constrains nothing about; only reaching
 * into *another* Module has to go through that Module's entry point.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const nonconformances = require('./nonconformances');
const suppliers = require('./suppliers');

const SUPPLIER_NCR_STATUSES = ['open', 'issued', 'responded', 'closed', 'rejected'];
const DISPOSITIONS = ['return_to_supplier', 'scrap', 'rework_at_cost', 'sort', 'use_as_is'];
const FINISHED_STATUSES = ['closed', 'rejected'];

const SUPPLIER_NCR_LIST_LIMIT = 200;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

function requireMembership(field, value, allowed) {
  if (value === undefined || value === null) return null;
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
  return value;
}

// A value with a known set is chosen, never typed (ADR-0023) — and a disposition
// is one of five answers, not free text.
function requireDisposition(value) {
  if (typeof value !== 'string' || !DISPOSITIONS.includes(value)) {
    throw httpError(400, `disposition must be one of: ${DISPOSITIONS.join(', ')}`);
  }
  return value;
}

function optionalText(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw httpError(400, 'that field must be text');
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function optionalNumber(field, value, { minimum = 0 } = {}) {
  if (value === undefined || value === null) return null;
  const number = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(number)) throw httpError(400, `${field} must be a number`);
  if (number < minimum) throw httpError(400, `${field} must be at least ${minimum}`);
  return number;
}

// A three-letter currency, the baseline's own CHECK (`char_length(currency) = 3`)
// said before the database says it.
function requireCurrency(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || !/^[A-Za-z]{3}$/.test(value.trim())) {
    throw httpError(400, 'currency must be a three-letter code');
  }
  return value.trim().toUpperCase();
}

// A day the caller has chosen, or null. Never a timestamp: the due date is a
// day in the Site's calendar (ADR-0017), and a partial timestamp would silently
// mean something different at each Site.
function optionalDate(field, value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

// The NCR as every read sends it. `s.timezone` rides along because the due date
// is read and judged in the Site's own calendar.
const SUPPLIER_NCR_COLUMNS = `
  sn.id, sn.ncr_no, sn.status,
  sn.supplier_id, sup.code AS supplier_code, sup.name AS supplier_name,
  sn.product_id, p.code AS product_code, p.name AS product_name,
  sn.defect_code_id, dc.code AS defect_code_code, dc.name AS defect_code_name,
  sn.org_unit_id, ou.name AS org_unit_name, ou.path AS org_unit_path,
  ou.site_id, s.code AS site_code, s.name AS site_name, s.timezone AS site_timezone,
  sn.quality_issue_id,
  qi.issue_no AS quality_issue_no, qi.status AS quality_issue_status,
  qi.detection_point AS quality_issue_detection_point,
  qi.quantity_affected AS quality_issue_quantity_affected,
  qi.severity AS quality_issue_severity,
  to_char(qi.detected_at, 'YYYY-MM-DD') AS quality_issue_detected_on,
  sn.incoming_lot_ref, sn.purchase_ref,
  sn.quantity_affected, sn.uom_code, sn.disposition,
  sn.detected_at,
  sn.response_due_at,
  to_char(sn.response_due_at AT TIME ZONE s.timezone, 'YYYY-MM-DD') AS response_due_date,
  sn.cost_recovered, sn.currency, sn.description,
  sn.closed_at, sn.created_at, sn.updated_at,
  -- The two facts a reader asks about a deadline: whether it has been missed by
  -- an NCR that is still being worked, and by how many days an answer is (or
  -- was) late.
  (sn.response_due_at IS NOT NULL
     AND sn.response_due_at < now()
     AND sn.status NOT IN ('closed', 'rejected')) AS is_overdue,
  CASE WHEN sn.response_due_at IS NOT NULL AND sn.response_due_at < now()
       THEN (CURRENT_DATE - (sn.response_due_at AT TIME ZONE s.timezone)::date) END AS days_overdue`;

// Every join is an INNER join except the two the baseline leaves nullable. The
// Org Unit is required by this slice's own routes (it is the Grant question's
// subject and it is what makes the register Sited), the Supplier is NOT NULL in
// the baseline, and the Product and the Defect code are ordinary LEFT JOINs
// because a lot can be received with neither named yet.
const SUPPLIER_NCR_JOINS = `
  FROM supplier_ncrs sn
  JOIN suppliers sup ON sup.id = sn.supplier_id
  JOIN org_units ou ON ou.id = sn.org_unit_id
  JOIN sites s ON s.id = ou.site_id
  LEFT JOIN products p ON p.id = sn.product_id
  LEFT JOIN defect_codes dc ON dc.id = sn.defect_code_id
  LEFT JOIN quality_issues qi ON qi.id = sn.quality_issue_id`;

function toSupplierNcr(row) {
  return {
    id: row.id,
    ncrNo: row.ncr_no,
    status: row.status,
    supplierId: row.supplier_id,
    supplierCode: row.supplier_code,
    supplierName: row.supplier_name,
    productId: row.product_id ?? null,
    productCode: row.product_code ?? null,
    productName: row.product_name ?? null,
    defectCodeId: row.defect_code_id ?? null,
    defectCodeCode: row.defect_code_code ?? null,
    defectCodeName: row.defect_code_name ?? null,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    orgUnitPath: row.org_unit_path,
    siteId: row.site_id,
    siteCode: row.site_code,
    siteName: row.site_name,
    incomingLotRef: row.incoming_lot_ref ?? null,
    purchaseRef: row.purchase_ref ?? null,
    quantityAffected: row.quantity_affected === null ? null : Number(row.quantity_affected),
    uomCode: row.uom_code,
    disposition: row.disposition,
    detectedAt: row.detected_at,
    // The day the caller chose, in the Site's own calendar, and the instant it
    // ends at — both, because one is what a person said and the other is what
    // the deadline is judged against.
    responseDueDate: row.response_due_date ?? null,
    responseDueAt: row.response_due_at ?? null,
    isOverdue: row.is_overdue === true,
    daysOverdue: row.days_overdue === null || row.days_overdue === undefined
      ? null
      : Number(row.days_overdue),
    costRecovered: row.cost_recovered === null ? null : Number(row.cost_recovered),
    currency: row.currency,
    description: row.description ?? null,
    closedAt: row.closed_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // The Non-conformance that controls the received product — the record both
    // this read and the Non-conformance's own read show, from their two ends.
    // Null until one is recorded from the NCR or linked to it, which is a real
    // state rather than a missing field.
    nonconformance: row.quality_issue_id
      ? {
          id: row.quality_issue_id,
          issueNo: row.quality_issue_no,
          status: row.quality_issue_status,
          detectionPoint: row.quality_issue_detection_point,
          severity: row.quality_issue_severity,
          quantityAffected:
            row.quality_issue_quantity_affected === null
              ? null
              : Number(row.quality_issue_quantity_affected),
          detectedOn: row.quality_issue_detected_on
        }
      : null
  };
}

// A write against `supplier_ncrs` can fail for reasons this file turns into a
// clean 4xx rather than a 500, each named by the constraint Postgres actually
// reports. The unique NCR number is the only one a caller could ever trigger (a
// duplicate would have to come from the sequence itself), and it is mapped all
// the same rather than echoed, the house rule being that a raw Postgres message
// never reaches a caller.
function mapSupplierNcrWriteError(error) {
  if (error.code === '23505' && error.constraint === 'supplier_ncrs_ncr_no_key') {
    return httpError(409, 'that supplier NCR number is already taken');
  }
  if (error.code === '23514') {
    return httpError(400, 'That supplier NCR was refused by the database: a field is outside the set of values it accepts');
  }
  if (error.code === '23503') {
    return httpError(400, 'that record does not exist');
  }
  return error;
}

// The Org Unit an NCR is filed at, with its Site's code, name and timezone. A
// null id and "no such row" are the same 404, one query.
async function findOrgUnitWithSite(orgUnitId, client = null) {
  if (parseId(orgUnitId) === null) throw notFound('Org Unit');
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ou.id, ou.name, ou.path, ou.site_id,
            s.code AS site_code, s.name AS site_name, s.timezone
       FROM org_units ou
       JOIN sites s ON s.id = ou.site_id
      WHERE ou.id = $1`,
    [orgUnitId]
  );
  if (!rows[0]) throw notFound('Org Unit');
  return rows[0];
}

/**
 * One Site's supplier NCRs, newest first, narrowed by Supplier and by status —
 * the two filters the ticket names — and by Org Unit, which the register
 * carries for the same reason the complaint register does.
 *
 * `orgUnitPath` is the *area* filter: one Org Unit and everything beneath it,
 * which is the same `<@` walk the Non-conformance register does. It is a read
 * filter over a register the caller can already see, never an entitlement
 * question — the Site is that, and the route has already asked it.
 */
async function listSupplierNcrs(
  siteId,
  { orgUnitPath = null, status = null, supplierId = null, limit = SUPPLIER_NCR_LIST_LIMIT } = {}
) {
  const conditions = ['ou.site_id = $1'];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`sn.status = $${params.length}`);
  }
  if (supplierId !== null) {
    params.push(supplierId);
    conditions.push(`sn.supplier_id = $${params.length}`);
  }

  // One row past the limit, so "there is more" is a fact rather than a guess
  // (ADR-0026's capped-list rule, the same shape the complaint register keeps).
  const { rows } = await getPool().query(
    `SELECT ${SUPPLIER_NCR_COLUMNS}
     ${SUPPLIER_NCR_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY sn.detected_at DESC, sn.id DESC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    supplierNcrs: rows.slice(0, limit).map((row) => toSupplierNcr(row)),
    truncated
  };
}

// Mirrors findComplaint: a malformed id resolves to null rather than reaching
// Postgres as a BIGINT parameter. The whole NCR, because its detail read *is*
// this projection — there is no second history to fetch.
async function findSupplierNcr(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${SUPPLIER_NCR_COLUMNS} ${SUPPLIER_NCR_JOINS} WHERE sn.id = $1`,
    [id]
  );
  return rows[0] ? toSupplierNcr(rows[0]) : null;
}

// The same read, 404ing rather than answering null — what the service's own
// writes and the route's own guard use, so "no such supplier NCR" is one
// sentence wherever it is raised.
async function requireSupplierNcr(id) {
  const ncr = await findSupplierNcr(id);
  if (!ncr) throw notFound('Supplier NCR');
  return ncr;
}

function requireOpen(ncr) {
  if (FINISHED_STATUSES.includes(ncr.status)) {
    throw httpError(409, `that supplier NCR is ${ncr.status} and cannot be changed`);
  }
}

/**
 * Records a supplier NCR: which Supplier, at which Org Unit, how much of what
 * was affected and what is wrong with it.
 *
 * Required: the Org Unit (it is where the NCR is worked, so it is the Grant
 * question's subject), the Supplier, and a quantity greater than zero with the
 * unit it is counted in — the last two because the baseline's own columns are
 * NOT NULL and a received lot is always a number of things. The unit is the
 * Product's own when the caller names a Product and no unit, and must be named
 * otherwise: a unit is never free text (ADR-0023). Optional, and each refused
 * rather than defaulted when it is present and wrong: the Product, the Defect
 * code, the incoming lot reference, the purchase reference, the response due
 * day and the description. `status` starts `open` and is not a field a caller
 * may set — the write that changes it is the close, below.
 *
 * Nothing here is a *decision* about the material. The Non-conformance that
 * controls it is a separate act (`recordNonconformanceFromSupplierNcr`), and
 * the Supplier's disposition and what was recovered are another
 * (`recordDisposition`) — the report, the product control and the commercial
 * answer are three different things and are recorded as three.
 */
async function recordSupplierNcr(input, accountId) {
  const body = input ?? {};

  const orgUnit = await findOrgUnitWithSite(body.orgUnitId);

  // The Supplier is a body field rather than a URL id, so a missing or
  // malformed one is a 400 naming the field and an id that names no Supplier is
  // a 404 — the same two refusals a complaint's own Customer gives, which is
  // this Module's convention for an id in a body.
  const supplierId = parseId(body.supplierId);
  if (supplierId === null) throw httpError(400, 'supplierId must be a valid Supplier id');
  const supplier = await suppliers.findSupplier(supplierId);

  // The Product is optional here, unlike on a complaint: an inspector has a lot
  // in front of them, and what it will become may not be known yet.
  const product =
    body.productId === undefined || body.productId === null
      ? null
      : await nonconformances.resolveActiveProduct(body.productId);

  const defectCode =
    body.defectCodeId === undefined || body.defectCodeId === null
      ? null
      : await nonconformances.resolveActiveDefectCode(body.defectCodeId);

  const quantity = optionalNumber('quantity', body.quantity, { minimum: 0 });
  if (quantity === null || quantity <= 0) {
    throw httpError(400, 'quantity must be greater than zero');
  }

  // The unit the quantity is in: the Product's own when there is a Product,
  // otherwise the caller's — and never free text (ADR-0023).
  let uomCode = product === null ? null : product.uom_code;
  if (body.uomCode !== undefined && body.uomCode !== null) {
    if (typeof body.uomCode !== 'string' || body.uomCode.trim() === '') {
      throw httpError(400, 'uomCode must be a unit of measure the plant uses');
    }
    const { rows } = await getPool().query(
      'SELECT code FROM units_of_measure WHERE code = $1',
      [body.uomCode.trim()]
    );
    if (!rows[0]) throw httpError(400, 'uomCode must be a unit of measure the plant uses');
    uomCode = rows[0].code;
  }
  if (uomCode === null) {
    throw httpError(
      400,
      'uomCode is required: this supplier NCR names no Product to take the unit of measure from'
    );
  }

  const responseDueDate = optionalDate('responseDueDate', body.responseDueDate);

  try {
    const id = await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO supplier_ncrs (
           supplier_id, product_id, org_unit_id, defect_code_id,
           incoming_lot_ref, purchase_ref, quantity_affected, uom_code,
           description, response_due_at, status
         )
         VALUES (
           $1, $2, $3, $4, $5, $6, $7, $8, $9,
           CASE WHEN $10::date IS NULL THEN NULL
                ELSE ((($10::date + 1)::timestamp - interval '1 microsecond')
                       AT TIME ZONE $11) END,
           'open'
         )
         RETURNING id`,
        [
          supplier.id,
          product === null ? null : product.id,
          orgUnit.id,
          defectCode === null ? null : defectCode.id,
          optionalText(body.incomingLotRef),
          optionalText(body.purchaseRef),
          quantity,
          uomCode,
          optionalText(body.description),
          responseDueDate,
          orgUnit.timezone
        ]
      );
      return row.id;
    });

    // Re-read through the same projection as every other answer, so a recorded
    // NCR and one read back later are the same shape.
    return await requireSupplierNcr(String(id));
  } catch (error) {
    throw mapSupplierNcrWriteError(error);
  }
}

/**
 * Records the Supplier's disposition and what was recovered — the commercial
 * answer to an incoming non-conformance, and the only place incoming quality
 * appears in the Cost pillar (`cost_recovered` is subtracted from the cost of
 * poor quality by the baseline's own view).
 *
 * The disposition is required and comes from the baseline's own five, checked
 * here so the refusal is a sentence rather than a `23514`. The cost recovered
 * and its currency are optional, and recording neither is a real state: a lot
 * returned to the Supplier recovers nothing, and an NCR whose claim is still
 * being argued says so by staying empty rather than by holding a zero.
 *
 * `status` is deliberately not moved by this write. The disposition is a field
 * on the record; the one transition this slice owns is the closure.
 */
async function recordDisposition(id, input, accountId) {
  const ncr = await requireSupplierNcr(id);
  requireOpen(ncr);

  const body = input ?? {};
  const disposition = requireDisposition(body.disposition);
  const costRecovered = optionalNumber('costRecovered', body.costRecovered, { minimum: 0 });
  const currency = requireCurrency(body.currency);

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE supplier_ncrs
            SET disposition = $2,
                cost_recovered = $3,
                currency = COALESCE($4, currency)
          WHERE id = $1`,
        [ncr.id, disposition, costRecovered, currency]
      );
    });
    return await requireSupplierNcr(ncr.id);
  } catch (error) {
    throw mapSupplierNcrWriteError(error);
  }
}

/**
 * Closes a supplier NCR.
 *
 * The one transition this slice has, mirroring the complaint's closure: nothing
 * moves an NCR to `issued` or `responded`, though the register's status filter
 * accepts all five of the baseline's statuses. A closed NCR keeps whatever
 * disposition and cost recovered were recorded against it — closing does not
 * clear them, because they are the commercial answer to the same lot.
 */
async function closeSupplierNcr(id, accountId) {
  const ncr = await requireSupplierNcr(id);
  requireOpen(ncr);

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE supplier_ncrs SET status = 'closed', closed_at = now() WHERE id = $1`,
        [ncr.id]
      );
    });
    return await requireSupplierNcr(ncr.id);
  } catch (error) {
    throw mapSupplierNcrWriteError(error);
  }
}

/**
 * Links an existing Non-conformance to the NCR (the ticket's second road to
 * "the received product is controlled").
 *
 * Three refusals beyond "no such record": an NCR that is already finished
 * cannot be changed, an NCR that already names a Non-conformance gets a 409
 * rather than a silent replacement (the row names one, and swapping it would
 * hide the record that was linked first), and a Non-conformance about a
 * different Product is refused when this NCR names a Product of its own.
 */
async function linkNonconformance(id, input, accountId) {
  const ncr = await requireSupplierNcr(id);
  requireOpen(ncr);

  if (ncr.nonconformance !== null) {
    throw httpError(409, 'this supplier NCR already names a Non-conformance');
  }

  const body = input ?? {};
  const nonconformanceId = parseId(body.nonconformanceId);
  if (nonconformanceId === null) {
    throw httpError(400, 'nonconformanceId must be a valid Non-conformance id');
  }
  const nonconformance = await nonconformances.findNonconformance(nonconformanceId);
  if (!nonconformance) throw notFound('Non-conformance');
  if (nonconformance.status === 'cancelled') {
    throw httpError(409, 'that Non-conformance was cancelled and cannot control anything');
  }
  if (ncr.productId !== null && String(nonconformance.productId) !== String(ncr.productId)) {
    throw httpError(
      409,
      "that Non-conformance is about another Product, so it does not control this supplier NCR's Product"
    );
  }

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        'UPDATE supplier_ncrs SET quality_issue_id = $2 WHERE id = $1',
        [ncr.id, nonconformance.id]
      );
    });
    return await requireSupplierNcr(ncr.id);
  } catch (error) {
    throw mapSupplierNcrWriteError(error);
  }
}

/**
 * Records the Non-conformance that controls the received lot —
 * `detection_point = 'incoming'`, the NCR's own Product where it has one, and
 * its Defect code, quantity, lot reference and description unless the caller
 * names their own.
 *
 * The Non-conformance is recorded by this Module's own recording service, so
 * there is exactly one answer to how one is numbered, validated, severity-
 * ratcheted and shaped; this function adds the one thing the NCR knows and the
 * service does not — that the plant found out at goods-in, and which NCR it
 * was.
 *
 * Answers with both records, because the caller is looking at the NCR and the
 * record it just created at the same time.
 */
async function recordNonconformanceFromSupplierNcr(id, input, accountId) {
  const ncr = await requireSupplierNcr(id);
  requireOpen(ncr);

  if (ncr.nonconformance !== null) {
    throw httpError(409, 'this supplier NCR already names a Non-conformance');
  }

  const body = input ?? {};

  // `quality_issues.product_id` is NOT NULL and this table's is nullable, so
  // the body is where the Product comes from when the NCR names none. The
  // refusal is a 400 naming the field rather than a raw NOT NULL failure.
  const productId = body.productId ?? ncr.productId;
  if (productId === undefined || productId === null) {
    throw httpError(
      400,
      'productId is required: this supplier NCR carries no Product to record the Non-conformance about'
    );
  }

  const defectCodeId = body.defectCodeId ?? ncr.defectCodeId;
  if (defectCodeId === undefined || defectCodeId === null) {
    throw httpError(
      400,
      'defectCodeId is required: this supplier NCR carries no Defect code to record the Non-conformance with'
    );
  }

  const nonconformance = await nonconformances.recordNonconformance(
    {
      orgUnitId: ncr.orgUnitId,
      productId,
      defectCodeId,
      detectionPoint: 'incoming',
      quantity: body.quantity ?? ncr.quantityAffected,
      severity: body.severity,
      assetId: body.assetId,
      lotRef: body.lotRef ?? ncr.incomingLotRef,
      description: body.description ?? ncr.description,
      immediateContainment: body.immediateContainment,
      detectedAt: body.detectedAt
    },
    { accountId }
  );

  // The link, immediately after the record it points at. See the header: a
  // failure here leaves a whole Non-conformance unlinked rather than a
  // half-written pair, and the NCR's own link address repairs it.
  let updated;
  try {
    await withActor(accountId, async (client) => {
      await client.query(
        'UPDATE supplier_ncrs SET quality_issue_id = $2 WHERE id = $1',
        [ncr.id, nonconformance.id]
      );
    });
    updated = await requireSupplierNcr(ncr.id);
  } catch (error) {
    throw mapSupplierNcrWriteError(error);
  }

  return { nonconformance, supplierNcr: updated };
}

module.exports = {
  SUPPLIER_NCR_STATUSES,
  DISPOSITIONS,
  listSupplierNcrs,
  findSupplierNcr,
  recordSupplierNcr,
  recordDisposition,
  closeSupplierNcr,
  linkNonconformance,
  recordNonconformanceFromSupplierNcr
};
