/*
 * Customer complaints (issue #214) — what a customer told us, which Product it
 * was about, and the Non-conformance that controls the product they complained
 * about.
 *
 * `customer_complaints` is a baseline table and this file adds one column's
 * worth of meaning to it (`response_note`, added by
 * 1800500000000_customer-complaint-response-note.js). It is otherwise used as
 * it stands, and its own comments are the design: `first_response_at` is kept
 * apart from `closed_at` because customers judge both, and a reply that arrives
 * in week three after silence on day one is a different failure from one that
 * took three weeks with an acknowledgement the same day.
 *
 * **One complaint names one Non-conformance, and that is the baseline's own
 * shape rather than a simplification.** `customer_complaints.quality_issue_id`
 * is a column — one value — and this is the same question issue #208 answered
 * for the Non-conformance-to-Concern link, answered the same way: prefer the
 * machinery that exists. The join table #208 added is right for a Concern
 * because a Concern *answers several occurrences of one problem*, which is
 * many-to-many; a complaint is one customer's one report of one delivery, and
 * the product it complains about is controlled by one Non-conformance. The
 * reverse is deliberately not symmetric: two complaints about the same bad lot
 * may name the same Non-conformance — that is the same product being controlled
 * for two customers — so a Non-conformance's own detail read returns a *list*
 * of the complaints that name it (see nonconformances.js's `listCustomerComplaints`),
 * while a complaint names one.
 *
 * **A linked Non-conformance must be about the complaint's own Product.** The
 * link exists to say the complained-of product is controlled; a Non-conformance
 * about a different Product does not control it, and accepting one would make
 * the link mean "some investigation, somewhere". The refusal is a 409 naming
 * the mismatch, and it is checked in the service rather than by a constraint
 * because it is a fact about two rows.
 *
 * **The Defect code is copied when a Non-conformance is recorded from the
 * complaint**, so the record carries the complaint's own Product and Defect
 * code with `detection_point = 'customer'` — the complaint is where the plant
 * found out. The Defect code, the quantity and the description are optional on
 * a complaint (the ticket requires the Customer and the Product), so the body
 * of that write may name any of the three the complaint does not carry; when it
 * names none and the complaint has none, the refusal is a 400 saying which one
 * is missing rather than a raw NOT NULL failure.
 *
 * **The response due date is a day, stored as the instant that day ends at the
 * Site.** `response_due_at` is a TIMESTAMPTZ in the baseline and the form
 * chooses a date (ADR-0023), so "due 2026-09-20" is stored as the end of that
 * day in the Site's own timezone (ADR-0017's rule that a day belongs to the
 * Site's calendar) — a complaint is late once the day it was promised on has
 * finished, not at midnight when it started. `isOverdue` is then the fact a
 * reader asks about: past its due instant and not yet finished with, which is
 * why a closed complaint is never marked late, while `daysOverdue` still says
 * how late the reply was or is.
 *
 * **Two statements, and it is worth being plain about it.** Recording a
 * Non-conformance from a complaint calls this Module's own recording service
 * (one definition of how a Non-conformance is numbered, validated and
 * severity-ratcheted — never a second INSERT) and then writes the link in a
 * second statement, rather than wrapping both in one transaction. The failure
 * this leaves reachable is a Non-conformance recorded but not yet linked, which
 * is a whole record on its own and is recoverable through the complaint's own
 * link address in the same slice; nothing is left half-written. The alternative
 * was threading a transaction through the recording service, which is a
 * Non-conformance slice's own shape and not this ticket's to change.
 *
 * Mirrors the rest of the Module: this file knows nothing about HTTP or about
 * who is calling. Its own private helpers stay private, and it reaches
 * `nonconformances.js` and `customers.js` directly — all three are this
 * Module's own files, which ADR-0006 constrains nothing about; only reaching
 * into *another* Module has to go through that Module's entry point.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const nonconformances = require('./nonconformances');
const customers = require('./customers');

const COMPLAINT_STATUSES = ['open', 'investigating', 'responded', 'closed', 'rejected'];
const COMPLAINT_TYPES = [
  'quality',
  'delivery',
  'quantity',
  'documentation',
  'packaging',
  'service'
];
const SEVERITIES = ['minor', 'major', 'critical'];
const FINISHED_STATUSES = ['closed', 'rejected'];

const COMPLAINT_LIST_LIMIT = 200;

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

// The complaint as every read sends it. `s.timezone` rides along because the
// due date is read and judged in the Site's own calendar.
const COMPLAINT_COLUMNS = `
  cc.id, cc.complaint_no, cc.status,
  cc.customer_id, c.code AS customer_code, c.name AS customer_name,
  cc.product_id, p.code AS product_code, p.name AS product_name,
  cc.defect_code_id, dc.code AS defect_code_code, dc.name AS defect_code_name,
  cc.org_unit_id, ou.name AS org_unit_name, ou.path AS org_unit_path,
  ou.site_id, s.code AS site_code, s.name AS site_name, s.timezone AS site_timezone,
  cc.quality_issue_id,
  qi.issue_no AS quality_issue_no, qi.status AS quality_issue_status,
  qi.detection_point AS quality_issue_detection_point,
  qi.quantity_affected AS quality_issue_quantity_affected,
  qi.severity AS quality_issue_severity,
  to_char(qi.detected_at, 'YYYY-MM-DD') AS quality_issue_detected_on,
  cc.complaint_type, cc.severity, cc.quantity_affected, cc.uom_code,
  cc.customer_ref, cc.lot_ref, cc.description,
  cc.received_at,
  cc.response_due_at,
  to_char(cc.response_due_at AT TIME ZONE s.timezone, 'YYYY-MM-DD') AS response_due_date,
  cc.first_response_at, cc.is_warranty, cc.claim_cost, cc.currency,
  cc.closed_at, cc.response_note, cc.created_at, cc.updated_at,
  -- The two facts a reader asks about a deadline: whether it has been missed by
  -- a complaint that is still being worked, and by how many days a reply is (or
  -- was) late.
  (cc.response_due_at IS NOT NULL
     AND cc.response_due_at < now()
     AND cc.status NOT IN ('closed', 'rejected')) AS is_overdue,
  CASE WHEN cc.response_due_at IS NOT NULL AND cc.response_due_at < now()
       THEN (CURRENT_DATE - (cc.response_due_at AT TIME ZONE s.timezone)::date) END AS days_overdue`;

// Every join is a foreign key or a NOT NULL column, so a complaint never
// multiplies into two rows: Customer, Product and Org Unit are required by this
// slice's own routes, and the Defect code is an ordinary LEFT JOIN because the
// baseline allows a complaint without one.
const COMPLAINT_JOINS = `
  FROM customer_complaints cc
  JOIN customers c ON c.id = cc.customer_id
  JOIN products p ON p.id = cc.product_id
  JOIN org_units ou ON ou.id = cc.org_unit_id
  JOIN sites s ON s.id = ou.site_id
  LEFT JOIN defect_codes dc ON dc.id = cc.defect_code_id
  LEFT JOIN quality_issues qi ON qi.id = cc.quality_issue_id`;

function toComplaint(row) {
  return {
    id: row.id,
    complaintNo: row.complaint_no,
    status: row.status,
    customerId: row.customer_id,
    customerCode: row.customer_code,
    customerName: row.customer_name,
    productId: row.product_id,
    productCode: row.product_code,
    productName: row.product_name,
    defectCodeId: row.defect_code_id ?? null,
    defectCodeCode: row.defect_code_code ?? null,
    defectCodeName: row.defect_code_name ?? null,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    orgUnitPath: row.org_unit_path,
    siteId: row.site_id,
    siteCode: row.site_code,
    siteName: row.site_name,
    complaintType: row.complaint_type,
    severity: row.severity,
    quantityAffected: row.quantity_affected === null ? null : Number(row.quantity_affected),
    uomCode: row.uom_code ?? null,
    customerRef: row.customer_ref ?? null,
    lotRef: row.lot_ref ?? null,
    description: row.description,
    receivedAt: row.received_at,
    // The day the caller chose, in the Site's own calendar, and the instant it
    // ends at — both, because one is what a person said and the other is what
    // the deadline is judged against.
    responseDueDate: row.response_due_date ?? null,
    responseDueAt: row.response_due_at ?? null,
    isOverdue: row.is_overdue === true,
    daysOverdue: row.days_overdue === null || row.days_overdue === undefined
      ? null
      : Number(row.days_overdue),
    firstResponseAt: row.first_response_at ?? null,
    isWarranty: row.is_warranty,
    claimCost: row.claim_cost === null ? null : Number(row.claim_cost),
    currency: row.currency,
    closedAt: row.closed_at ?? null,
    responseNote: row.response_note ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // The Non-conformance that controls the product this complaint is about —
    // the record both this read and the Non-conformance's own read show, from
    // their two ends. Null until one is recorded from the complaint or linked
    // to it, which is a real state rather than a missing field.
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

// A write against `customer_complaints` can fail for reasons this file turns
// into a clean 4xx rather than a 500, each named by the constraint Postgres
// actually reports. The unique complaint number is the only one a caller could
// ever trigger (a duplicate would have to come from the sequence itself), and
// it is mapped all the same rather than echoed, the house rule being that a raw
// Postgres message never reaches a caller.
function mapComplaintWriteError(error) {
  if (error.code === '23505' && error.constraint === 'customer_complaints_complaint_no_key') {
    return httpError(409, 'that complaint number is already taken');
  }
  if (error.code === '23514') {
    return httpError(400, 'That complaint was refused by the database: a field is outside the set of values it accepts');
  }
  if (error.code === '23503') {
    return httpError(400, 'that record does not exist');
  }
  return error;
}

// The Org Unit a complaint is filed at, with its Site's code, name and
// timezone. A null id and "no such row" are the same 404, one query.
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
 * One Site's complaints, newest first, narrowed by status and by Org Unit —
 * the two filters the ticket names.
 *
 * `orgUnitPath` is the *area* filter: one Org Unit and everything beneath it,
 * which is the same `<@` walk the Non-conformance register does. It is a read
 * filter over a register the caller can already see, never an entitlement
 * question — the Site is that, and the route has already asked it.
 */
async function listComplaints(siteId, { orgUnitPath = null, status = null, limit = COMPLAINT_LIST_LIMIT } = {}) {
  const conditions = ['ou.site_id = $1'];
  const params = [siteId];

  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`cc.status = $${params.length}`);
  }

  // One row past the limit, so "there is more" is a fact rather than a guess
  // (ADR-0026's capped-list rule, the same shape the Non-conformance register
  // keeps).
  const { rows } = await getPool().query(
    `SELECT ${COMPLAINT_COLUMNS}
     ${COMPLAINT_JOINS}
     WHERE ${conditions.join(' AND ')}
     ORDER BY cc.received_at DESC, cc.id DESC
     LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    complaints: rows.slice(0, limit).map((row) => toComplaint(row)),
    truncated
  };
}

// Mirrors findNonconformance: a malformed id resolves to null rather than
// reaching Postgres as a BIGINT parameter. The whole complaint, because its
// detail read *is* this projection — there is no second history to fetch.
async function findComplaint(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${COMPLAINT_COLUMNS} ${COMPLAINT_JOINS} WHERE cc.id = $1`,
    [id]
  );
  return rows[0] ? toComplaint(rows[0]) : null;
}

// The same read, 404ing rather than answering null — what the service's own
// writes and the route's own guard use, so "no such complaint" is one sentence
// wherever it is raised.
async function requireComplaint(id) {
  const complaint = await findComplaint(id);
  if (!complaint) throw notFound('Customer complaint');
  return complaint;
}

function requireOpen(complaint) {
  if (FINISHED_STATUSES.includes(complaint.status)) {
    throw httpError(409, `that Customer complaint is ${complaint.status} and cannot be changed`);
  }
}

/**
 * Records a complaint: who complained, about which Product, filed at an Org
 * Unit, with what they said.
 *
 * Required: the Org Unit (it is where the complaint is worked, so it is the
 * Grant question's subject), the Customer, the Product and a description —
 * the last because the baseline's own column is NOT NULL, and a complaint with
 * nothing written down is not a complaint. Optional, and each refused rather
 * than defaulted when it is present and wrong: the Defect code, the quantity
 * (with its unit, taken from the Product when the caller does not name one),
 * the response due day, whether it is a warranty claim, the type, the severity,
 * the customer's own reference and the lot. `status` starts `open` and is not a
 * field a caller may set — the write that changes it is the close, below.
 *
 * Nothing here is a *decision* about the product — this is the report. The
 * Non-conformance that controls what they complained about is a separate act
 * (`recordNonconformanceFromComplaint`), which is where the two records meet.
 */
async function recordComplaint(input, accountId) {
  const body = input ?? {};

  const orgUnit = await findOrgUnitWithSite(body.orgUnitId);

  // The Customer is a body field rather than a URL id, so a missing or
  // malformed one is a 400 naming the field and an id that names no Customer is
  // a 404 — the same two refusals resolveActiveProduct/resolveActiveDefectCode
  // give below, which is this Module's convention for an id in a body.
  const customerId = parseId(body.customerId);
  if (customerId === null) throw httpError(400, 'customerId must be a valid Customer id');
  const customer = await customers.findCustomer(customerId);

  const product = await nonconformances.resolveActiveProduct(body.productId);

  const defectCode =
    body.defectCodeId === undefined || body.defectCodeId === null
      ? null
      : await nonconformances.resolveActiveDefectCode(body.defectCodeId);

  requireNonEmptyString('description', body.description);

  const quantity = optionalNumber('quantity', body.quantity, { minimum: 0 });
  if (quantity !== null && quantity <= 0) {
    throw httpError(400, 'quantity must be greater than zero');
  }

  // The unit the quantity is in: the Product's own unless the caller names
  // another one the plant uses. A unit is never free text (ADR-0023).
  let uomCode = null;
  if (quantity !== null) {
    uomCode = product.uom_code;
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
  }

  const complaintType = requireMembership('complaintType', body.complaintType, COMPLAINT_TYPES) ?? 'quality';
  const severity = requireMembership('severity', body.severity, SEVERITIES) ?? 'major';
  const responseDueDate = optionalDate('responseDueDate', body.responseDueDate);
  const isWarranty = body.isWarranty === undefined ? false : body.isWarranty;
  if (typeof isWarranty !== 'boolean') throw httpError(400, 'isWarranty must be a boolean');

  try {
    const id = await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO customer_complaints (
           customer_id, product_id, org_unit_id, defect_code_id, complaint_type,
           severity, quantity_affected, uom_code, customer_ref, lot_ref,
           description, response_due_at, is_warranty, status
         )
         VALUES (
           $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
           CASE WHEN $12::date IS NULL THEN NULL
                ELSE ((($12::date + 1)::timestamp - interval '1 microsecond')
                       AT TIME ZONE $13) END,
           $14, 'open'
         )
         RETURNING id`,
        [
          customer.id,
          product.id,
          orgUnit.id,
          defectCode === null ? null : defectCode.id,
          complaintType,
          severity,
          quantity,
          uomCode,
          optionalText(body.customerRef),
          optionalText(body.lotRef),
          body.description.trim(),
          responseDueDate,
          orgUnit.timezone,
          isWarranty
        ]
      );
      return row.id;
    });

    // Re-read through the same projection as every other answer, so a recorded
    // complaint and one read back later are the same shape.
    return await requireComplaint(String(id));
  } catch (error) {
    throw mapComplaintWriteError(error);
  }
}

/**
 * Closes a complaint with the response the customer was given.
 *
 * The note is required — a complaint that is closed with nothing said back to
 * the customer is the failure this whole record exists to make visible, and the
 * refusal is a 400 naming the field rather than a 500 from the constraint
 * underneath it (`customer_complaints_closed_has_response`, which says the same
 * thing for a writer that does not come through here).
 *
 * `first_response_at` is set in the same statement, and only when it is still
 * empty: the first reply is the one the customer waited for, and a complaint
 * that had already been acknowledged keeps the earlier moment.
 */
async function closeComplaint(id, input, accountId) {
  const complaint = await requireComplaint(id);
  requireOpen(complaint);

  const body = input ?? {};
  const responseNote = optionalText(body.responseNote ?? body.note);
  if (responseNote === null) throw httpError(400, 'responseNote is required to close a complaint');

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `UPDATE customer_complaints
            SET status = 'closed',
                closed_at = now(),
                first_response_at = COALESCE(first_response_at, now()),
                response_note = $2
          WHERE id = $1`,
        [complaint.id, responseNote]
      );
    });
    return await requireComplaint(complaint.id);
  } catch (error) {
    throw mapComplaintWriteError(error);
  }
}

/**
 * Links an existing Non-conformance to the complaint (the ticket's second road
 * to "the complained-of product is controlled").
 *
 * Three refusals beyond "no such record": a complaint that is already finished
 * cannot be changed, a complaint that already names a Non-conformance gets a
 * 409 rather than a silent replacement (the row names one, and swapping it
 * would hide the record that was linked first), and a Non-conformance about a
 * different Product is refused because it does not control the product this
 * complaint is about.
 */
async function linkNonconformance(id, input, accountId) {
  const complaint = await requireComplaint(id);
  requireOpen(complaint);

  if (complaint.nonconformance !== null) {
    throw httpError(409, 'this Customer complaint already names a Non-conformance');
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
  if (String(nonconformance.productId) !== String(complaint.productId)) {
    throw httpError(
      409,
      "that Non-conformance is about another Product, so it does not control this complaint's Product"
    );
  }

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        'UPDATE customer_complaints SET quality_issue_id = $2 WHERE id = $1',
        [complaint.id, nonconformance.id]
      );
    });
    return await requireComplaint(complaint.id);
  } catch (error) {
    throw mapComplaintWriteError(error);
  }
}

/**
 * Records the Non-conformance that controls what the customer complained about
 * — `detection_point = 'customer'`, the complaint's Product, and its Defect
 * code, quantity and description unless the caller names their own (a complaint
 * may carry none of the three).
 *
 * The Non-conformance is recorded by this Module's own recording service, so
 * there is exactly one answer to how one is numbered, validated, severity-
 * ratcheted and shaped; this function adds the one thing the complaint knows
 * and the service does not — that the plant found out from a customer, and
 * which complaint it was.
 *
 * Answers with both records, because the caller is looking at the complaint and
 * the record it just created at the same time.
 */
async function recordNonconformanceFromComplaint(id, input, accountId) {
  const complaint = await requireComplaint(id);
  requireOpen(complaint);

  if (complaint.nonconformance !== null) {
    throw httpError(409, 'this Customer complaint already names a Non-conformance');
  }

  const body = input ?? {};

  const defectCodeId = body.defectCodeId ?? complaint.defectCodeId;
  if (defectCodeId === undefined || defectCodeId === null) {
    throw httpError(
      400,
      "defectCodeId is required: this complaint carries no Defect code to record the Non-conformance with"
    );
  }
  const quantity = body.quantity ?? complaint.quantityAffected;
  if (quantity === undefined || quantity === null) {
    throw httpError(
      400,
      "quantity is required: this complaint carries no quantity to record the Non-conformance with"
    );
  }

  const nonconformance = await nonconformances.recordNonconformance(
    {
      orgUnitId: complaint.orgUnitId,
      productId: complaint.productId,
      defectCodeId,
      detectionPoint: 'customer',
      quantity,
      severity: body.severity,
      assetId: body.assetId,
      lotRef: body.lotRef ?? complaint.lotRef,
      description: body.description ?? complaint.description,
      immediateContainment: body.immediateContainment,
      detectedAt: body.detectedAt
    },
    { accountId }
  );

  // The link, immediately after the record it points at. See the header: a
  // failure here leaves a whole Non-conformance unlinked rather than a
  // half-written pair, and the complaint's own link address repairs it.
  let updated;
  try {
    await withActor(accountId, async (client) => {
      await client.query(
        'UPDATE customer_complaints SET quality_issue_id = $2 WHERE id = $1',
        [complaint.id, nonconformance.id]
      );
    });
    updated = await requireComplaint(complaint.id);
  } catch (error) {
    throw mapComplaintWriteError(error);
  }

  return { nonconformance, complaint: updated };
}

module.exports = {
  COMPLAINT_STATUSES,
  COMPLAINT_TYPES,
  SEVERITIES,
  listComplaints,
  findComplaint,
  recordComplaint,
  closeComplaint,
  linkNonconformance,
  recordNonconformanceFromComplaint
};
