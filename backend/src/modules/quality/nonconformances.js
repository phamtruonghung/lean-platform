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
 * **Two doors record, and the baseline's two attribution columns name which
 * one was used.** A Non-conformance recorded by a signed-in Account carries
 * `recorded_by_account_id` and nothing in `detected_by`; one recorded at a
 * shared floor device (ADR-0016, issue #207) carries the identified Employee
 * in `detected_by` and nothing in `recorded_by_account_id`, because the
 * Employee who found the product IS who detected it — most of a plant cannot
 * sign in (CONTEXT.md), so the person at the machine has no Account to record
 * against. The two are kept apart rather than both filled, and the reason is
 * auditability: "who the system attributed this to" has to be answerable from
 * one column without a reader having to decide which one is authoritative.
 * `recordNonconformance` takes an actor object for exactly this —
 * `{ accountId }` from the Account door, `{ employeeId }` from the floor's —
 * the same shape work-orders.js's start and complete already take.
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
 * **The severity rule is a one-way ratchet for a recorder, and a two-way
 * decision for a holder of Quality authority.** A Non-conformance starts at
 * its Defect code's `default_severity`; the recorder may name a higher one at
 * recording time or raise it afterwards, and naming a lower one is refused
 * with a 403 — not because a lower severity is always wrong, but because
 * lowering it is a Quality-authority decision (ADR-0035). Issue #206 is the
 * slice that takes that decision: `lowerSeverity` is its own act, behind its
 * own address, and it needs Quality authority at the Org Unit and a note.
 *
 * **A Non-conformance is dealt with in parts, and closes by itself.** Issue
 * #206 adds the Dispositions (scrap, rework with rework minutes, return to
 * supplier, and the Concession that accepts the product as it is behind
 * Quality authority), and the rule that the record closes the moment its whole
 * quantity has a Disposition — `settleDispositionStatus` is where, and it
 * consults nothing about the cause of the failure, because a Non-conformance
 * records bad product rather than the problem behind it. A cancelled
 * Non-conformance accepts no further Dispositions or quantity changes, and the
 * three corrections a holder of Quality authority can make (a lower severity,
 * a reopen, a cancel) are kept with who made each one, when, and the note it
 * was made with.
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

// The three kinds of Disposition a recorder writes down (issue #206). The
// baseline's own `quality_dispositions_type_check` permits three more —
// `use_as_is` (the Concession, which needs Quality authority and therefore has
// its own act and its own address rather than riding in this set), `regrade`
// and `sort` — and those are deliberately not accepted here: a set a caller can
// reach is a set this file names, and a kind with no rule behind it is a kind
// nobody can be held to.
const DISPOSITION_TYPES = ['scrap', 'rework', 'return_to_supplier'];

// The baseline's own value for a Disposition that accepts the product as it
// is, which is what a Concession is (CONTEXT.md's own entry).
const CONCESSION_DISPOSITION_TYPE = 'use_as_is';

// The three corrections issue #206 gives a holder of Quality authority. The
// set is the database's too (the CHECK on `quality_issue_corrections.kind`),
// repeated here so a caller gets a sentence naming the field rather than a raw
// constraint violation.
const CORRECTION_KINDS = ['severity_lowered', 'reopened', 'cancelled'];

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

// The rework half of a Disposition (issue #206): minutes are a count of time,
// never negative. Zero is a permitted answer — a rework Disposition whose
// minutes have not been booked yet — so the test is `>= 0` rather than `> 0`,
// and the value is required (rather than defaulted) when the kind is `rework`,
// because "rework carries rework minutes" is the ticket's own criterion and a
// silent zero is a number nobody decided.
function requireNonNegativeMinutes(field, value) {
  const minutes = typeof value === 'string' ? Number(value.trim()) : value;
  if (typeof minutes !== 'number' || !Number.isFinite(minutes) || minutes < 0) {
    throw httpError(400, `${field} must be a number of minutes, or zero`);
  }
  return minutes;
}

// An optional free-text field: trimmed where it carries something, null where
// it does not. A field sent as whitespace is the same as one not sent at all,
// which is the rule `recordNonconformance` already follows for `lotRef`.
function optionalText(value) {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

// The note a correction is taken with (issue #206). Required for all three of
// them: a correction with no reason on it is the row an auditor cannot use,
// and the database refuses it too (`quality_issue_corrections.note`'s CHECK).
function requireNote(body) {
  const note = optionalText(body.note);
  if (note === null) throw httpError(400, 'note is required: say why the Non-conformance is being corrected');
  return note;
}

// Quantities are NUMERIC(18,4) in the database, so the arithmetic this file
// does on them is done at that scale — a comparison of two floating-point
// numbers that are equal at the fourth decimal must not read as a difference.
function roundQuantity(value) {
  return Math.round(value * 10000) / 10000;
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
  qi.closed_at,
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

// One Disposition, with whoever decided it named — an Account where the
// decision was made by a signed-in person, an Employee where it was made at a
// floor device (issue #207). For a Concession the Account column IS the
// granting Account, which is why it is read back rather than left to the
// client to look up: "only a quality engineer may grant one and their name
// stays on the record" is CONTEXT.md's own sentence about it.
const DISPOSITION_COLUMNS = `
  qd.id, qd.disposition_type, qd.quantity, qd.uom_code, qd.rework_minutes,
  qd.decided_at, qd.approval_ref, qd.notes,
  qd.decided_by_account_id, dau.display_name AS decided_by_account_name,
  qd.decided_by, e.display_name AS decided_by_employee_name`;

const DISPOSITION_JOINS = `
  FROM quality_dispositions qd
  LEFT JOIN app_users dau ON dau.id = qd.decided_by_account_id
  LEFT JOIN employees e ON e.id = qd.decided_by`;

// One correction: what the record was, what it became, the note it was taken
// with, and the Account that decided it (issue #206). `corrected_by_account_id`
// is NOT NULL in the table, so the join never drops a row.
const CORRECTION_COLUMNS = `
  qic.id, qic.kind, qic.previous_severity, qic.new_severity,
  qic.previous_status, qic.new_status, qic.note, qic.corrected_at,
  qic.corrected_by_account_id, cau.display_name AS corrected_by_account_name`;

const CORRECTION_JOINS = `
  FROM quality_issue_corrections qic
  LEFT JOIN app_users cau ON cau.id = qic.corrected_by_account_id`;

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

function toDisposition(row) {
  return {
    id: row.id,
    dispositionType: row.disposition_type,
    // A Concession is a Disposition to use the product as it is, so the kind
    // is the only thing that distinguishes one — said as a boolean too,
    // because the Screen labels and tones it differently rather than
    // translating the baseline's own value in three places.
    isConcession: row.disposition_type === CONCESSION_DISPOSITION_TYPE,
    quantity: toQuantity(row.quantity),
    uomCode: row.uom_code,
    reworkMinutes: toQuantity(row.rework_minutes),
    decidedAt: row.decided_at,
    // The deviation or approval number an auditor asks for. Named `reference`
    // on the wire, which is the word issue #206 uses for it.
    reference: row.approval_ref ?? null,
    note: row.notes ?? null,
    decidedByAccountId: row.decided_by_account_id ?? null,
    decidedByAccountName: row.decided_by_account_name ?? null,
    decidedByEmployeeId: row.decided_by ?? null,
    decidedByEmployeeName: row.decided_by_employee_name ?? null
  };
}

function toCorrection(row) {
  return {
    id: row.id,
    kind: row.kind,
    previousSeverity: row.previous_severity ?? null,
    newSeverity: row.new_severity ?? null,
    previousStatus: row.previous_status ?? null,
    newStatus: row.new_status ?? null,
    note: row.note,
    correctedAt: row.corrected_at,
    correctedByAccountId: row.corrected_by_account_id,
    correctedByAccountName: row.corrected_by_account_name ?? null
  };
}

function toNonconformance(row, { quantityChanges = [], dispositions = [], corrections = [] } = {}) {
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
    // When the record finished with itself: set when its whole quantity got a
    // Disposition, or when a holder of Quality authority cancelled it
    // (issue #206). The baseline's own CHECK is why both states carry one.
    closedAt: row.closed_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    quantityChanges,
    dispositions,
    corrections
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

// A Disposition write can fail for two reasons this file turns into a clean
// 4xx rather than a 500. `quality_issues_disposition_fits` is the database's
// own statement of "no more than was affected can be dispositioned" — issue
// #206's 409, reached here by a race the service's own check could not see.
// `quality_dispositions_rework_only` refuses minutes on anything that is not a
// rework, which the service also checks itself; it maps to a 400 because it is
// a caller's mistake about a field, not a state conflict. Neither a raw
// Postgres message nor the column it names is ever echoed to a caller.
function mapDispositionWriteError(error) {
  if (error.code === '23514') {
    if (error.constraint === 'quality_issues_disposition_fits') {
      return httpError(409, 'that is more than the quantity still undecided on this Non-conformance');
    }
    if (error.constraint === 'quality_dispositions_rework_only') {
      return httpError(400, 'reworkMinutes may only be recorded on a rework Disposition');
    }
  }
  return error;
}

// A Non-conformance that was cancelled in error accepts nothing further — no
// Disposition, no quantity change, no correction — and the refusal is a 409
// rather than a 403 because it is the record's state that refuses, not the
// caller's entitlement (issue #206's own criterion, and the same distinction
// `increaseQuantity` already draws between its 409 and the 403 a permission
// refusal gets).
function requireNotCancelled(existing) {
  if (existing.status === 'cancelled') {
    throw httpError(
      409,
      'this Non-conformance was cancelled and accepts no further Dispositions or quantity changes'
    );
  }
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
 * One Non-conformance with its quantity history, its Dispositions and its
 * corrections — what the detail Screen reads, and what every write in this
 * file answers with.
 *
 * All three histories are part of the record rather than separate reads,
 * because the ticket's own criteria say so: a quantity change "is returned
 * with the Non-conformance" (issue #205), and issue #206's corrections must be
 * "readable back with who and when". Ordered oldest first, which is the order
 * a person reads a record's own story in.
 */
async function getNonconformanceDetail(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${NONCONFORMANCE_COLUMNS} ${NONCONFORMANCE_JOINS} WHERE qi.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return toNonconformance(rows[0], {
    quantityChanges: await listQuantityChanges(rows[0].id),
    dispositions: await listDispositions(rows[0].id),
    corrections: await listCorrections(rows[0].id)
  });
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

async function listDispositions(qualityIssueId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${DISPOSITION_COLUMNS}
     ${DISPOSITION_JOINS}
     WHERE qd.quality_issue_id = $1
     ORDER BY qd.decided_at, qd.id`,
    [qualityIssueId]
  );
  return rows.map(toDisposition);
}

async function listCorrections(qualityIssueId, client = null) {
  const runner = client ?? getPool();
  const { rows } = await runner.query(
    `SELECT ${CORRECTION_COLUMNS}
     ${CORRECTION_JOINS}
     WHERE qic.quality_issue_id = $1
     ORDER BY qic.corrected_at, qic.id`,
    [qualityIssueId]
  );
  return rows.map(toCorrection);
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
 * Record a Non-conformance (issue #205), from either door (issue #207).
 *
 * `actor` is `{ accountId }` when a signed-in Account is recording and
 * `{ employeeId }` when the identification at a shared floor device is — the
 * same two-door shape `maintenance/work-orders.js` gives a start and a
 * complete, and the same two attribution columns the baseline's
 * `quality_issues` carries. Exactly one of the two is filled on the row, and
 * `detected_by` is the Employee on the floor path because the Employee who
 * found the product is the one who detected it: the identification is the
 * whole of what the route proved, and inventing an Account for it would be
 * attributing the record to somebody who was not there.
 *
 * The route has already resolved the Org Unit and answered the scope question
 * for whichever door the write came through — `people.canAct({ …,
 * write: true })` for an Account, `people.deviceReachesOrgUnit` for a device —
 * and parsed the Asset id; everything that is a fact about the record itself
 * is decided here. The field, severity and quantity rules below are the same
 * on both doors, because they are the same function: a floor device gets no
 * looser reading of what a Non-conformance is, and no severer one.
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
async function recordNonconformance(input, actor = {}) {
  const body = input ?? {};
  const accountId = actor.accountId ?? null;
  const employeeId = actor.employeeId ?? null;

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
           recorded_by_account_id, detected_by
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                 COALESCE($11::timestamptz, now()), $12, $13, $14, $15, $16)
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
          accountId,
          employeeId
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
  requireNotCancelled(existing);

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
  requireNotCancelled(existing);

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

/**
 * Settle what a Non-conformance's status is once a Disposition has landed
 * (issue #206).
 *
 * Three things happen in one statement, and they are one statement on purpose:
 * the cached total is recomputed from the disposition rows the way the
 * baseline's own trigger recomputes it, the status follows from that total,
 * and the closing time is set with it. Splitting them would leave a window in
 * which the record says `closed` with no time, which the baseline's own
 * `quality_issues_closed_has_time` refuses — and it would leave two places
 * computing the same sum.
 *
 * **The whole quantity having a Disposition is the only thing that closes a
 * Non-conformance.** No Concern is consulted, and none can be: a
 * Non-conformance records the bad product rather than the problem behind it,
 * and the cause may still be being answered while the product itself is dealt
 * with (CONTEXT.md's own entry, and issue #206's criterion "regardless of any
 * linked Concern"). Part of the quantity having one makes it `dispositioned`
 * — the baseline's own word for a record that is partly dealt with, which is
 * what the register's status filter already offers.
 *
 * The recomputation is from `quality_dispositions` rather than an increment,
 * matching the baseline trigger's own choice: a deleted or corrected
 * Disposition then self-heals rather than leaving a total nobody can explain.
 * The baseline's deferred constraint trigger still runs at COMMIT and
 * recomputes the same number, so the two agree by construction.
 */
async function settleDispositionStatus(client, qualityIssueId) {
  await client.query(
    `WITH totals AS (
       SELECT COALESCE(SUM(quantity), 0) AS total
         FROM quality_dispositions
        WHERE quality_issue_id = $1
     )
     UPDATE quality_issues qi
        SET quantity_dispositioned = totals.total,
            status = CASE WHEN totals.total >= qi.quantity_affected
                          THEN 'closed' ELSE 'dispositioned' END,
            closed_at = CASE WHEN totals.total >= qi.quantity_affected
                             THEN now() ELSE NULL END
       FROM totals
      WHERE qi.id = $1`,
    [qualityIssueId]
  );
}

/**
 * Record a Disposition (issue #206): scrap, rework with its minutes, or return
 * to the supplier — or, with `concession`, the Concession that accepts the
 * product as it is.
 *
 * The kind is decided by the caller of this helper rather than by a field in
 * the body, because the two acts have different rules and different addresses:
 * a scrap, rework or return Disposition needs the same access as recording
 * (`write: true` at the Org Unit, which the route asks about), and a Concession
 * needs Quality authority at it (ADR-0035, which the route asks about too).
 *
 * **What is still undecided is the whole guard.** Product is dealt with in
 * parts as it is sorted, so a Disposition may cover any part of what is left
 * and no more: claiming to deal with 30 of the 12 still in the quarantine cage
 * is a number that cannot be true, and it is refused with a 409 — the same
 * class of refusal the affected quantity's own decrease gets, and the same
 * class the database's `quality_issues_disposition_fits` produces if a race
 * gets past this check.
 *
 * The unit is not an input: it is the record's own `uom_code`, read off the
 * Product when the Non-conformance was recorded, for the reason
 * `recordNonconformance` gives — a caller free to name a different unit for
 * the same batch is a caller free to make the containment count wrong.
 */
async function recordDisposition(id, input, accountId, { concession = false } = {}) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');
  requireNotCancelled(existing);

  const body = input ?? {};
  const dispositionType = concession ? CONCESSION_DISPOSITION_TYPE : body.dispositionType;

  if (!concession) {
    requireMembership('dispositionType', dispositionType, DISPOSITION_TYPES);
  }

  const quantity = requirePositiveQuantity('quantity', body.quantity);

  // What is still undecided — read off the record's own two numbers rather
  // than summed here, because the baseline's trigger keeps the cached total
  // correct whatever else has happened to the record.
  const undecided = roundQuantity(existing.quantityAffected - existing.quantityDispositioned);
  if (roundQuantity(quantity) > undecided) {
    throw httpError(
      409,
      `that is more than the ${undecided} ${existing.uomCode} still undecided on this Non-conformance`
    );
  }

  // Rework minutes: required where the Disposition is a rework, refused where
  // it is not (the baseline's `quality_dispositions_rework_only` CHECK says the
  // same thing, and this produces the sentence a caller can read).
  let reworkMinutes = 0;
  if (dispositionType === 'rework') {
    if (body.reworkMinutes === undefined || body.reworkMinutes === null) {
      throw httpError(400, 'reworkMinutes is required on a rework Disposition');
    }
    reworkMinutes = requireNonNegativeMinutes('reworkMinutes', body.reworkMinutes);
  } else if (
    body.reworkMinutes !== undefined &&
    body.reworkMinutes !== null &&
    Number(body.reworkMinutes) !== 0
  ) {
    throw httpError(400, 'reworkMinutes may only be recorded on a rework Disposition');
  }

  // A Concession carries both: the reference is the deviation or approval
  // number an auditor asks for, and the note is why the product was accepted.
  // The ticket names both as required on a Concession, and only a note is
  // meaningful on the others.
  const reference = optionalText(body.reference);
  const note = optionalText(body.note);
  if (concession) {
    if (reference === null) {
      throw httpError(400, 'reference is required on a Concession: quote the deviation it was granted under');
    }
    if (note === null) throw httpError(400, 'note is required on a Concession: say why it was granted');
  }

  try {
    await withActor(accountId, async (client) => {
      await client.query(
        `INSERT INTO quality_dispositions (
           quality_issue_id, disposition_type, quantity, uom_code,
           rework_minutes, decided_by_account_id, approval_ref, notes
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          existing.id,
          dispositionType,
          quantity,
          existing.uomCode,
          reworkMinutes,
          accountId ?? null,
          reference,
          note
        ]
      );
      await settleDispositionStatus(client, existing.id);
    });
  } catch (error) {
    throw mapDispositionWriteError(error);
  }

  return getNonconformanceDetail(id);
}

// The Concession, as its own act. `recordDisposition` does the work; this
// exists so the route and the reader can see that granting a Concession is a
// decision with Quality authority behind it rather than one of the three
// ordinary dispositions, which is the distinction ADR-0035 draws.
async function grantConcession(id, input, accountId) {
  return recordDisposition(id, input, accountId, { concession: true });
}

// One correction row, in the transaction that made the change — so a record
// that moved with no row saying who moved it is not a state this file can
// produce. The Account is required by the table itself (NOT NULL), which is
// deliberate: every correction in this slice is made by a signed-in holder of
// Quality authority, and an unattributed correction is worse than none.
async function writeCorrection(client, {
  qualityIssueId,
  kind,
  accountId,
  note,
  previousSeverity = null,
  newSeverity = null,
  previousStatus = null,
  newStatus = null
}) {
  await client.query(
    `INSERT INTO quality_issue_corrections (
       quality_issue_id, kind, previous_severity, new_severity,
       previous_status, new_status, note, corrected_by_account_id
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [
      qualityIssueId,
      kind,
      previousSeverity,
      newSeverity,
      previousStatus,
      newStatus,
      note,
      accountId
    ]
  );
}

/**
 * Lower a Non-conformance's severity (issue #206).
 *
 * The one severity change issue #205 refused a recorder: deciding that
 * nonconforming product is less bad than the Defect code says is the same
 * judgement a Concession makes, so a Grant carrying Quality authority at the
 * record's Org Unit is what it takes (ADR-0035) and the route asks People
 * before calling here. The note is required — a lowering with no reason on it
 * is the row an auditor cannot use — and it is kept with the Account that
 * decided it and the moment it was decided, which is what makes the change
 * readable back over HTTP.
 *
 * There is no floor here beyond "actually lower": the criterion is that a
 * lowering *below the Defect code's own default* is allowed with the authority
 * and the note, so a record raised to `critical` may be brought back to the
 * code's `major`, and further down still if that is the honest reading.
 */
async function lowerSeverity(id, input, accountId) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');
  requireNotCancelled(existing);

  const body = input ?? {};
  requireMembership('severity', body.severity, SEVERITIES);
  const note = requireNote(body);

  if (severityRank(body.severity) >= severityRank(existing.severity)) {
    throw httpError(
      409,
      `this Non-conformance is ${existing.severity}; a lowering records a difference, and a raising is a different act`
    );
  }

  await withActor(accountId, async (client) => {
    await client.query('UPDATE quality_issues SET severity = $1 WHERE id = $2', [
      body.severity,
      id
    ]);
    await writeCorrection(client, {
      qualityIssueId: existing.id,
      kind: 'severity_lowered',
      accountId,
      note,
      previousSeverity: existing.severity,
      newSeverity: body.severity
    });
  });

  return getNonconformanceDetail(id);
}

/**
 * Reopen a closed Non-conformance (issue #206).
 *
 * A record that closed itself once its whole quantity had a Disposition can
 * turn out to have been closed too early — more of the same product found
 * after the fact, or a disposition that should not have been made. Only a
 * closed record can be reopened, and it goes back to `dispositioned` rather
 * than to `open`: its quantity has already been dealt with, so what a reopen
 * restores is the *record's* availability, not the product's. The way back to
 * a close is the path that got there the first time — raise the affected
 * quantity because sorting found more (issue #205, the number still never
 * shrinks) and dispose of the rest.
 *
 * The closing time is cleared with the status, because a record that is open
 * again carrying the time it closed reads as a contradiction.
 */
async function reopenNonconformance(id, input, accountId) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');

  const note = requireNote(input ?? {});

  if (existing.status !== 'closed') {
    throw httpError(
      409,
      `only a closed Non-conformance can be reopened; this one is ${existing.status}`
    );
  }

  await withActor(accountId, async (client) => {
    const { rows: [updated] } = await client.query(
      `UPDATE quality_issues
          SET status = CASE WHEN quantity_dispositioned >= quantity_affected
                            THEN 'dispositioned'
                            WHEN immediate_containment IS NOT NULL THEN 'contained'
                            ELSE 'open' END,
              closed_at = NULL
        WHERE id = $1
        RETURNING status`,
      [id]
    );
    await writeCorrection(client, {
      qualityIssueId: existing.id,
      kind: 'reopened',
      accountId,
      note,
      previousStatus: existing.status,
      newStatus: updated.status
    });
  });

  return getNonconformanceDetail(id);
}

/**
 * Cancel a Non-conformance recorded in error (issue #206).
 *
 * The mistake this exists for is a record that should never have been written
 * down at all — the wrong Product, the wrong line, a duplicate of one already
 * on the log. It takes Quality authority and a note for the same reason the
 * others do, and an already-cancelled record is a 409 rather than a second
 * cancellation: the note on the first one is the record of why it went.
 *
 * A closed record is refused too, and told to reopen first: cancelling it
 * would overwrite the closing time its own closure produced, and "this record
 * was finished" and "this record never happened" are two different statements
 * about the same row.
 *
 * The baseline's `quality_issues_closed_has_time` requires a closing time for
 * either state, which is why `closed_at` is set here — a cancelled record is
 * finished with, and the log reads that off one column.
 */
async function cancelNonconformance(id, input, accountId) {
  const existing = await findNonconformance(id);
  if (!existing) throw notFound('Non-conformance');

  const note = requireNote(input ?? {});

  if (existing.status === 'cancelled') {
    throw httpError(409, 'this Non-conformance is already cancelled');
  }
  if (existing.status === 'closed') {
    throw httpError(409, 'a closed Non-conformance cannot be cancelled; reopen it first');
  }

  await withActor(accountId, async (client) => {
    const { rows: [updated] } = await client.query(
      `UPDATE quality_issues
          SET status = 'cancelled', closed_at = now()
        WHERE id = $1
        RETURNING status`,
      [id]
    );
    await writeCorrection(client, {
      qualityIssueId: existing.id,
      kind: 'cancelled',
      accountId,
      note,
      previousStatus: existing.status,
      newStatus: updated.status
    });
  });

  return getNonconformanceDetail(id);
}

module.exports = {
  DETECTION_POINTS,
  SEVERITIES,
  NONCONFORMANCE_STATUSES,
  DISPOSITION_TYPES,
  CORRECTION_KINDS,
  listNonconformances,
  findNonconformance,
  getNonconformanceDetail,
  listQuantityChanges,
  listDispositions,
  listCorrections,
  recordNonconformance,
  updateNonconformance,
  increaseQuantity,
  recordDisposition,
  grantConcession,
  lowerSeverity,
  reopenNonconformance,
  cancelNonconformance
};
