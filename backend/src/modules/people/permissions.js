/*
 * The permission catalogue: every function this Platform can grant, named by a
 * code (issue #492, ADR-0061).
 *
 * **A permission is a code, not a row an administrator invents.** SAP's own
 * model draws the same line: an authorization object plus the activity it is
 * checked with is written by the supplier (`M_MSEG_WMB` with `ACTVT` 03), and
 * the administrator's job is to say *who* holds it, never to invent a new one.
 * So this file is the one place a code comes into existence, and
 * `role-routes.js` offers it read-only; a code that is not here cannot be
 * granted, and the migration that seeds `permissions` carries a frozen copy
 * that `test/integration/roles.test.js` asserts against this list. (Frozen in
 * the migration rather than required from here, because a migration is a
 * one-way door: an edit to this file must never change what an old migration
 * does to a database that has already run it. ADR-0007.)
 *
 * **The shape of a code** is `<MODULE>_<THING>_<ACTIVITY>`, where the module is
 * the three-letter prefix of the Module that owns the function (`PPL`, `MTN`,
 * `ACT`, `QLT`, `SAF`, `PRD`, `INS`, `ADM`) and the activity is one of:
 *
 *   - `DISPLAY` — may open the Screen and read what it shows. SAP's `ACTVT` 03.
 *   - `CHANGE`  — may maintain the records behind it. `ACTVT` 02.
 *   - a verb that names the one decision the Screen is for, where "change" is
 *     too coarse to be safe: `QLT_NONCONFORMANCES_DISPOSE`,
 *     `SAF_CLASSIFY`, `PPL_LEAVE_REQUESTS_DECIDE`, `ACT_CAPA_VERIFY`.
 *
 * Two codes are deliberately *not* per-Screen, because the Screen is where an
 * Account works and the permission is what it may do there: `ACT_RAISE` (raise a
 * Concern, which every Account may do anywhere it can see — ADR's own Concern
 * entry) and `MTN_REQUESTS_RAISE` (raise a Maintenance Request, issue #55).
 *
 * **A permission says what, a Grant says where.** These codes answer "may this
 * Account maintain Work orders at all"; `people.canAct` still answers "at this
 * Org Unit". They are independent on purpose (ADR-0061): a role carrying
 * `MTN_WORK_ORDERS_CHANGE` for an Account with no write Grant opens the Screen
 * and shows it empty, which is the truthful picture, not an error.
 *
 * Ordering matters: `PERMISSIONS` is written in the order the sidebar's groups
 * render (ADR-0020), so the roles editor reads like the Shell does, and
 * `sort_order` is this array's index. Append; never reorder a released list,
 * because `sort_order` is what an administrator's eye learned.
 */

// [code, label, description], grouped by Module in the sidebar's own order.
const CATALOGUE = [
  [
    'People',
    [
      ['PPL_DIRECTORY_DISPLAY', 'Directory', 'Read the Employee directory and an Employee record.'],
      ['PPL_DIRECTORY_CHANGE', 'Maintain Employees', 'Add an Employee, correct one, record an assignment, or mark one departed.'],
      ['PPL_JOB_ROLES_DISPLAY', 'Job roles', 'Read the Job role catalogue.'],
      ['PPL_JOB_ROLES_CHANGE', 'Maintain Job roles', 'Add a Job role or retire one.'],
      ['PPL_SKILLS_DISPLAY', 'Skills', 'Read the Skills catalogue and who holds each one.'],
      ['PPL_SKILLS_CHANGE', 'Maintain Skills', 'Add a Skill, retire one, or record that an Employee holds it.'],
      ['PPL_ORG_UNITS_DISPLAY', 'Org Units', 'Read the Org Unit tree and the Sites it hangs beneath.'],
      ['PPL_ORG_UNITS_CHANGE', 'Maintain Org Units', 'Add or change a Site or an Org Unit, or import a tree.'],
      ['PPL_ATTENDANCE_DISPLAY', 'Attendance', 'Read a shift instance\'s Attendance sheet.'],
      ['PPL_ATTENDANCE_CHANGE', 'Confirm Attendance', 'Confirm an Attendance sheet for a shift instance.'],
      ['PPL_TRAINING_DISPLAY', 'Training', 'Read Training records and follow one that names the caller.'],
      ['PPL_TRAINING_CHANGE', 'Raise Training', 'Raise a Training record, add a trainee, or sign one off.'],
      ['PPL_SIGNATURE_OWN', 'My signature', 'Store and change the caller\'s own signature.'],
      ['PPL_LEAVE_REQUESTS_DISPLAY', 'Leave requests', 'Read the caller\'s own leave requests and those they decide.'],
      ['PPL_LEAVE_REQUESTS_DECIDE', 'Decide Leave', 'Approve or decline a leave request for an Employee in the caller\'s scope.'],
      ['PPL_COST_RATES_MAINTAIN', 'Cost rates', 'Maintain the cost rates an Employee\'s hours are priced at.'],
      ['PPL_PRODUCT_COSTS_MAINTAIN', 'Product standard costs', 'Maintain a product\'s standard cost.'],
    ],
  ],
  [
    'Maintenance',
    [
      ['MTN_ASSETS_DISPLAY', 'Assets', 'Read the Asset register.'],
      ['MTN_ASSETS_CHANGE', 'Maintain Assets', 'Add or change an Asset, nest one, or retire one.'],
      ['MTN_WORK_ORDERS_DISPLAY', 'Work orders', 'Read Work orders and one Work order\'s detail.'],
      ['MTN_WORK_ORDERS_CHANGE', 'Maintain Work orders', 'Raise, assign, complete or cancel a Work order.'],
      ['MTN_PARTS_DISPLAY', 'Parts', 'Read the Parts catalogue.'],
      ['MTN_PARTS_CHANGE', 'Maintain Parts', 'Add or change a Part.'],
      ['MTN_STORES_DISPLAY', 'Stores', 'Read Stores and their stock.'],
      ['MTN_STORES_CHANGE', 'Maintain Stores', 'Add a Store or record stock movement.'],
      ['MTN_REQUESTS_RAISE', 'Raise a Request', 'Raise a Maintenance Request and follow the ones the caller raised.'],
      ['MTN_REQUESTS_TRIAGE', 'Triage Requests', 'Read the triage queue and accept or decline a Request.'],
      ['MTN_DOWNTIME_DISPLAY', 'Downtime', 'Read recorded downtime.'],
      ['MTN_DOWNTIME_CHANGE', 'Record Downtime', 'Record downtime against an Asset and its reason.'],
      ['MTN_PM_SCHEDULES_DISPLAY', 'PM schedules', 'Read preventive-maintenance schedules.'],
      ['MTN_PM_SCHEDULES_CHANGE', 'Maintain PM schedules', 'Add or change a preventive-maintenance schedule.'],
      ['MTN_METERS_DISPLAY', 'Meters', 'Read Asset meters and their readings.'],
      ['MTN_METERS_CHANGE', 'Record meter readings', 'Record a meter reading that drives a PM schedule.'],
      ['MTN_JOB_PLANS_MAINTAIN', 'Job plans', 'Maintain the Job plans a PM schedule runs.'],
    ],
  ],
  [
    'Actions',
    [
      ['ACT_LOG_DISPLAY', 'Action log', 'Read the action log: Concerns and CAPAs.'],
      ['ACT_RAISE', 'Raise a Concern', 'Raise a Concern where the caller found it.'],
      ['ACT_MEASURE', 'Record measures', 'Record an immediate measure against a Concern.'],
      ['ACT_VERIFY', 'Verify an Action', 'Verify an Action that has been carried out.'],
      ['ACT_CAPA_DISPLAY', 'CAPAs', 'Read an investigation.'],
      ['ACT_CAPA_OPEN', 'Open a CAPA', 'Open an investigation on a Concern.'],
      ['ACT_CAPA_VERIFY', 'Verify a CAPA', 'Sign off an investigation\'s root causes and whys.'],
      ['ACT_CAPA_EFFECTIVENESS', 'Check effectiveness', 'Check whether an investigation\'s measures held.'],
    ],
  ],
  [
    'Quality',
    [
      ['QLT_PRODUCTS_DISPLAY', 'Products', 'Read the product catalogue.'],
      ['QLT_PRODUCTS_CHANGE', 'Maintain Products', 'Add or change a product.'],
      ['QLT_DEFECT_CODES_DISPLAY', 'Defect codes', 'Read the defect-code catalogue.'],
      ['QLT_DEFECT_CODES_CHANGE', 'Maintain defect codes', 'Add or change a defect code.'],
      ['QLT_NONCONFORMANCES_DISPLAY', 'Non-conformances', 'Read the Non-conformance register.'],
      ['QLT_NONCONFORMANCES_RECORD', 'Record a Non-conformance', 'Record a Non-conformance where it was found.'],
      ['QLT_NONCONFORMANCES_DISPOSE', 'Dispose of nonconforming product', 'Concede, rework or scrap nonconforming product. Needs Quality authority at the Org Unit.'],
      ['QLT_CUSTOMERS_DISPLAY', 'Customers', 'Read the customer catalogue.'],
      ['QLT_CUSTOMERS_CHANGE', 'Maintain Customers', 'Add or change a customer.'],
      ['QLT_COMPLAINTS_DISPLAY', 'Customer complaints', 'Read the customer-complaint register.'],
      ['QLT_COMPLAINTS_RECORD', 'Record a complaint', 'Record a customer complaint.'],
      ['QLT_SLIDESHOW_DISPLAY', 'Slide show', 'Open the shop-floor slide show.'],
      ['QLT_SLIDESHOW_CHOOSE', 'Choose slide-show issues', 'Put a Quality issue in the slide show and order it.'],
      ['QLT_SUPPLIERS_DISPLAY', 'Suppliers', 'Read the supplier catalogue.'],
      ['QLT_SUPPLIERS_CHANGE', 'Maintain Suppliers', 'Add or change a supplier.'],
      ['QLT_SUPPLIER_NCRS_DISPLAY', 'Supplier NCRs', 'Read the supplier non-conformance reports.'],
      ['QLT_SUPPLIER_NCRS_RECORD', 'Record a supplier NCR', 'Record a supplier non-conformance report.'],
    ],
  ],
  [
    'Safety',
    [
      ['SAF_INCIDENTS_DISPLAY', 'Incidents', 'Read the Safety incident register.'],
      ['SAF_INCIDENTS_RECORD', 'Record an Incident', 'Record a Safety incident.'],
      ['SAF_CLASSIFY', 'Classify an injury', 'Record or read an injured person\'s diagnosis. Needs Safety authority at the Org Unit (ADR-0037).'],
      ['SAF_OBSERVATIONS_DISPLAY', 'Observations', 'Read the Safety observation register.'],
      ['SAF_OBSERVATIONS_RECORD', 'Record an Observation', 'Record a Safety observation.'],
      ['SAF_INJURY_TYPES_MAINTAIN', 'Injury types', 'Maintain the injury-type catalogue.'],
      ['SAF_BODY_PARTS_MAINTAIN', 'Body parts', 'Maintain the body-part catalogue.'],
    ],
  ],
  [
    'Production',
    [
      ['PRD_HANDOVER_DISPLAY', 'Shift handovers', 'Read a Section\'s Shift handover.'],
      ['PRD_HANDOVER_WRITE', 'Write a Shift handover', 'Open, amend and submit a Section\'s Shift handover.'],
      ['PRD_HANDOVER_ACKNOWLEDGE', 'Acknowledge a Shift handover', 'Acknowledge the Shift handover handed to the caller.'],
    ],
  ],
  [
    'Insights',
    [
      ['INS_TIER_BOARD_DISPLAY', 'Tier board', 'Read the tier board.'],
      ['INS_SKILL_COVERAGE_DISPLAY', 'Skill coverage', 'Read how coverage of each Skill stands across a Site.'],
      ['INS_KPI_CATALOGUE_DISPLAY', 'KPI catalogue', 'Read the MTU KPI catalogue and its Targets.'],
      ['INS_KPI_CATALOGUE_CHANGE', 'Maintain the KPI catalogue', 'Add a KPI or change its Targets.'],
      ['INS_KPI_REVIEW_DISPLAY', 'KPI review', 'Read the daily KPI review.'],
      ['INS_KPI_REVIEW_RECORD', 'Record a KPI review', 'Record the daily KPI review.'],
    ],
  ],
  [
    'Administration',
    [
      ['ADM_APPROVALS_DISPLAY', 'Approvals', 'Read the queue of Accounts awaiting Approval.'],
      ['ADM_APPROVALS_DECIDE', 'Decide an Approval', 'Admit an Account with its role and Grants, or reject it.'],
      ['ADM_ACCOUNTS_DISPLAY', 'Accounts', 'Read every Account and the Grants each holds.'],
      ['ADM_ACCOUNTS_CHANGE', 'Administer Accounts', 'Correct an Account\'s role or Grants, or deactivate it.'],
      ['ADM_ROLES_DISPLAY', 'Roles', 'Read the roles and the permissions each carries.'],
      ['ADM_ROLES_CHANGE', 'Maintain roles', 'Create a role, change what it carries, retire it, or assign it to an Account.'],
    ],
  ],
];

// Flattened, with the position an administrator sees. Frozen by the migration
// that seeded it; see the header.
const PERMISSIONS = CATALOGUE.flatMap(([module, entries]) =>
  entries.map(([code, label, description]) => ({ code, module, label, description }))
).map((permission, index) => ({ ...permission, sortOrder: index }));

const PERMISSION_CODES = PERMISSIONS.map((permission) => permission.code);

const BY_CODE = new Map(PERMISSIONS.map((permission) => [permission.code, permission]));

// A role's permission set arrives off the wire as JSON. Anything not in the
// catalogue is dropped here rather than failing the whole write: an
// administrator's editor can hold a code a newer release added while this
// image is running, and the honest answer to that is to grant what this image
// knows, not to refuse the save. Every code is returned as the catalogue
// spells it, so a lower-case paste cannot create a second spelling.
function knownPermissionCodes(codes) {
  if (!Array.isArray(codes)) return [];
  const seen = new Set();
  const known = [];
  for (const code of codes) {
    if (typeof code !== 'string') continue;
    const normalised = code.trim().toUpperCase();
    if (!BY_CODE.has(normalised) || seen.has(normalised)) continue;
    seen.add(normalised);
    known.push(normalised);
  }
  return known;
}

module.exports = {
  CATALOGUE,
  PERMISSIONS,
  PERMISSION_CODES,
  BY_CODE,
  knownPermissionCodes
};
