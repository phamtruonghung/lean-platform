/**
 * The permission catalogue, the roles that carry it, and the assignment of a
 * role to one Account (issue #492, ADR-0061).
 *
 * **Why four tables and not a `permissions` array on `app_users`.** The
 * administrator's unit of work is a *group*: "everyone who runs the store room
 * gets these". A role is that group, its permission set is a separate table so
 * editing it is one write that lands on every Account holding the role (SAP's
 * PFCG regenerating a profile), and the assignment table is separate again
 * because it is the one act an administrator performs per person — the
 * "Assign" button the card names. Collapsing any two of the three makes an
 * edit-to-everyone impossible without rewriting every Account's row.
 *
 * **`permissions` is a catalogue, not data an administrator maintains.**
 * `src/modules/people/permissions.js` is where a code comes into existence and
 * the routes offer it read-only; this migration carries a frozen copy of that
 * list, because a migration is a one-way door (ADR-0007) and an edit to the
 * source file must never change what this migration does to a database that
 * has already run it. `test/integration/roles.test.js` asserts the two agree,
 * which is what keeps the copy honest. The seed below is generated, not
 * hand-typed: the codes, labels and descriptions are the source file's, in the
 * sidebar's own group order, and `sort_order` is their position.
 *
 * **Two automatic sources, so nothing has to be backfilled.** `is_default` is
 * the group every Account holds — the card's "nhóm chức năng mặc định", and
 * SAP's `SAP_NEW` profile in spirit rather than in mechanism. `legacy_role`
 * names an `app_users.role` value (`operator` … `admin`) that earns the role
 * automatically, so the five seeded legacy roles reproduce today's doors for
 * every existing Account the moment this migration runs, with no data
 * migration and no administrator's action. `app_users.role` itself is not
 * touched: it stays the column the Accounts Screen and the route guards already
 * read, and ADR-0061 records that the two are read together, not replaced.
 *
 * **`app_user_roles` is the assignment.** A row is one person holding one role
 * because an administrator put them there. There is no validity window and no
 * "user comparison" step: a role edit takes effect on the Account's next
 * request, which is what SAP's user comparison + next logon delivers, arrived
 * at from the other end. ADR-0061 names that deviation.
 *
 * **One default role, enforced.** `app_roles_one_default` is a partial unique
 * index rather than a convention, because two "everyone" groups would make the
 * effective set depend on which one a reader happened to query.
 *
 * **A role code is bounded.** 3–30 characters, uppercase letters, digits and
 * underscores — SAP's own 30-character technical-name limit for a role, kept
 * because a code is what an administrator types into a request for access and
 * what a test asserts on.
 *
 * Backward-compatible per ADR-0007: four new tables and seeded rows change
 * nothing an older running image reads or writes.
 */

exports.shorthands = undefined;

const RLS_TABLES = ['permissions', 'app_roles', 'app_role_permissions', 'app_user_roles'];

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE permissions (
      code        TEXT        PRIMARY KEY,
      module      TEXT        NOT NULL,
      label       TEXT        NOT NULL,
      description TEXT        NOT NULL,
      sort_order  INTEGER     NOT NULL UNIQUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  pgm.sql(`
    CREATE TABLE app_roles (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code        TEXT        NOT NULL UNIQUE,
      name        TEXT        NOT NULL,
      description TEXT        NOT NULL DEFAULT '',
      -- The group every Account holds, whatever its app_users.role. At most one
      -- row may be true — see app_roles_one_default below.
      is_default  BOOLEAN     NOT NULL DEFAULT FALSE,
      -- The app_users.role value that earns this role automatically, or NULL for
      -- a role an administrator assigns one Account at a time. Slack in the
      -- CHECK is deliberate: a new account role would need a new value here,
      -- which is exactly the moment to ask whether it needs a new role too.
      legacy_role TEXT,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT app_roles_code_shape
        CHECK (code ~ '^[A-Z][A-Z0-9_]{2,29}$'),
      CONSTRAINT app_roles_legacy_role_check
        CHECK (legacy_role IS NULL
               OR legacy_role IN ('operator', 'supervisor', 'engineer', 'manager', 'admin'))
    )
  `);

  pgm.sql(`
    CREATE UNIQUE INDEX app_roles_one_default
      ON app_roles ((is_default))
      WHERE is_default
  `);

  pgm.sql(`
    CREATE TABLE app_role_permissions (
      app_role_id     BIGINT      NOT NULL REFERENCES app_roles (id) ON DELETE CASCADE,
      permission_code TEXT        NOT NULL REFERENCES permissions (code) ON DELETE RESTRICT,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,

      PRIMARY KEY (app_role_id, permission_code)
    )
  `);

  pgm.sql(`
    CREATE TABLE app_user_roles (
      app_user_id BIGINT      NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
      app_role_id BIGINT      NOT NULL REFERENCES app_roles (id) ON DELETE CASCADE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,

      PRIMARY KEY (app_user_id, app_role_id)
    )
  `);

  pgm.sql('CREATE INDEX app_role_permissions_permission_idx ON app_role_permissions (permission_code)');
  pgm.sql('CREATE INDEX app_user_roles_role_idx ON app_user_roles (app_role_id)');

  // The catalogue — generated from permissions.js at the moment this migration
  // was written. Frozen: see the header.
  pgm.sql(`
    INSERT INTO permissions (code, module, label, description, sort_order) VALUES
    ('PPL_DIRECTORY_DISPLAY', 'People', 'Directory', 'Read the Employee directory and an Employee record.', 0),
    ('PPL_DIRECTORY_CHANGE', 'People', 'Maintain Employees', 'Add an Employee, correct one, record an assignment, or mark one departed.', 1),
    ('PPL_JOB_ROLES_DISPLAY', 'People', 'Job roles', 'Read the Job role catalogue.', 2),
    ('PPL_JOB_ROLES_CHANGE', 'People', 'Maintain Job roles', 'Add a Job role or retire one.', 3),
    ('PPL_SKILLS_DISPLAY', 'People', 'Skills', 'Read the Skills catalogue and who holds each one.', 4),
    ('PPL_SKILLS_CHANGE', 'People', 'Maintain Skills', 'Add a Skill, retire one, or record that an Employee holds it.', 5),
    ('PPL_ORG_UNITS_DISPLAY', 'People', 'Org Units', 'Read the Org Unit tree and the Sites it hangs beneath.', 6),
    ('PPL_ORG_UNITS_CHANGE', 'People', 'Maintain Org Units', 'Add or change a Site or an Org Unit, or import a tree.', 7),
    ('PPL_ATTENDANCE_DISPLAY', 'People', 'Attendance', 'Read a shift instance''s Attendance sheet.', 8),
    ('PPL_ATTENDANCE_CHANGE', 'People', 'Confirm Attendance', 'Confirm an Attendance sheet for a shift instance.', 9),
    ('PPL_TRAINING_DISPLAY', 'People', 'Training', 'Read Training records and follow one that names the caller.', 10),
    ('PPL_TRAINING_CHANGE', 'People', 'Raise Training', 'Raise a Training record, add a trainee, or sign one off.', 11),
    ('PPL_SIGNATURE_OWN', 'People', 'My signature', 'Store and change the caller''s own signature.', 12),
    ('PPL_LEAVE_REQUESTS_DISPLAY', 'People', 'Leave requests', 'Read the caller''s own leave requests and those they decide.', 13),
    ('PPL_LEAVE_REQUESTS_DECIDE', 'People', 'Decide Leave', 'Approve or decline a leave request for an Employee in the caller''s scope.', 14),
    ('PPL_COST_RATES_MAINTAIN', 'People', 'Cost rates', 'Maintain the cost rates an Employee''s hours are priced at.', 15),
    ('PPL_PRODUCT_COSTS_MAINTAIN', 'People', 'Product standard costs', 'Maintain a product''s standard cost.', 16),
    ('MTN_ASSETS_DISPLAY', 'Maintenance', 'Assets', 'Read the Asset register.', 17),
    ('MTN_ASSETS_CHANGE', 'Maintenance', 'Maintain Assets', 'Add or change an Asset, nest one, or retire one.', 18),
    ('MTN_WORK_ORDERS_DISPLAY', 'Maintenance', 'Work orders', 'Read Work orders and one Work order''s detail.', 19),
    ('MTN_WORK_ORDERS_CHANGE', 'Maintenance', 'Maintain Work orders', 'Raise, assign, complete or cancel a Work order.', 20),
    ('MTN_PARTS_DISPLAY', 'Maintenance', 'Parts', 'Read the Parts catalogue.', 21),
    ('MTN_PARTS_CHANGE', 'Maintenance', 'Maintain Parts', 'Add or change a Part.', 22),
    ('MTN_STORES_DISPLAY', 'Maintenance', 'Stores', 'Read Stores and their stock.', 23),
    ('MTN_STORES_CHANGE', 'Maintenance', 'Maintain Stores', 'Add a Store or record stock movement.', 24),
    ('MTN_REQUESTS_RAISE', 'Maintenance', 'Raise a Request', 'Raise a Maintenance Request and follow the ones the caller raised.', 25),
    ('MTN_REQUESTS_TRIAGE', 'Maintenance', 'Triage Requests', 'Read the triage queue and accept or decline a Request.', 26),
    ('MTN_DOWNTIME_DISPLAY', 'Maintenance', 'Downtime', 'Read recorded downtime.', 27),
    ('MTN_DOWNTIME_CHANGE', 'Maintenance', 'Record Downtime', 'Record downtime against an Asset and its reason.', 28),
    ('MTN_PM_SCHEDULES_DISPLAY', 'Maintenance', 'PM schedules', 'Read preventive-maintenance schedules.', 29),
    ('MTN_PM_SCHEDULES_CHANGE', 'Maintenance', 'Maintain PM schedules', 'Add or change a preventive-maintenance schedule.', 30),
    ('MTN_METERS_DISPLAY', 'Maintenance', 'Meters', 'Read Asset meters and their readings.', 31),
    ('MTN_METERS_CHANGE', 'Maintenance', 'Record meter readings', 'Record a meter reading that drives a PM schedule.', 32),
    ('MTN_JOB_PLANS_MAINTAIN', 'Maintenance', 'Job plans', 'Maintain the Job plans a PM schedule runs.', 33),
    ('ACT_LOG_DISPLAY', 'Actions', 'Action log', 'Read the action log: Concerns and CAPAs.', 34),
    ('ACT_RAISE', 'Actions', 'Raise a Concern', 'Raise a Concern where the caller found it.', 35),
    ('ACT_MEASURE', 'Actions', 'Record measures', 'Record an immediate measure against a Concern.', 36),
    ('ACT_VERIFY', 'Actions', 'Verify an Action', 'Verify an Action that has been carried out.', 37),
    ('ACT_CAPA_DISPLAY', 'Actions', 'CAPAs', 'Read an investigation.', 38),
    ('ACT_CAPA_OPEN', 'Actions', 'Open a CAPA', 'Open an investigation on a Concern.', 39),
    ('ACT_CAPA_VERIFY', 'Actions', 'Verify a CAPA', 'Sign off an investigation''s root causes and whys.', 40),
    ('ACT_CAPA_EFFECTIVENESS', 'Actions', 'Check effectiveness', 'Check whether an investigation''s measures held.', 41),
    ('QLT_PRODUCTS_DISPLAY', 'Quality', 'Products', 'Read the product catalogue.', 42),
    ('QLT_PRODUCTS_CHANGE', 'Quality', 'Maintain Products', 'Add or change a product.', 43),
    ('QLT_DEFECT_CODES_DISPLAY', 'Quality', 'Defect codes', 'Read the defect-code catalogue.', 44),
    ('QLT_DEFECT_CODES_CHANGE', 'Quality', 'Maintain defect codes', 'Add or change a defect code.', 45),
    ('QLT_NONCONFORMANCES_DISPLAY', 'Quality', 'Non-conformances', 'Read the Non-conformance register.', 46),
    ('QLT_NONCONFORMANCES_RECORD', 'Quality', 'Record a Non-conformance', 'Record a Non-conformance where it was found.', 47),
    ('QLT_NONCONFORMANCES_DISPOSE', 'Quality', 'Dispose of nonconforming product', 'Concede, rework or scrap nonconforming product. Needs Quality authority at the Org Unit.', 48),
    ('QLT_CUSTOMERS_DISPLAY', 'Quality', 'Customers', 'Read the customer catalogue.', 49),
    ('QLT_CUSTOMERS_CHANGE', 'Quality', 'Maintain Customers', 'Add or change a customer.', 50),
    ('QLT_COMPLAINTS_DISPLAY', 'Quality', 'Customer complaints', 'Read the customer-complaint register.', 51),
    ('QLT_COMPLAINTS_RECORD', 'Quality', 'Record a complaint', 'Record a customer complaint.', 52),
    ('QLT_SLIDESHOW_DISPLAY', 'Quality', 'Slide show', 'Open the shop-floor slide show.', 53),
    ('QLT_SLIDESHOW_CHOOSE', 'Quality', 'Choose slide-show issues', 'Put a Quality issue in the slide show and order it.', 54),
    ('QLT_SUPPLIERS_DISPLAY', 'Quality', 'Suppliers', 'Read the supplier catalogue.', 55),
    ('QLT_SUPPLIERS_CHANGE', 'Quality', 'Maintain Suppliers', 'Add or change a supplier.', 56),
    ('QLT_SUPPLIER_NCRS_DISPLAY', 'Quality', 'Supplier NCRs', 'Read the supplier non-conformance reports.', 57),
    ('QLT_SUPPLIER_NCRS_RECORD', 'Quality', 'Record a supplier NCR', 'Record a supplier non-conformance report.', 58),
    ('SAF_INCIDENTS_DISPLAY', 'Safety', 'Incidents', 'Read the Safety incident register.', 59),
    ('SAF_INCIDENTS_RECORD', 'Safety', 'Record an Incident', 'Record a Safety incident.', 60),
    ('SAF_CLASSIFY', 'Safety', 'Classify an injury', 'Record or read an injured person''s diagnosis. Needs Safety authority at the Org Unit (ADR-0037).', 61),
    ('SAF_OBSERVATIONS_DISPLAY', 'Safety', 'Observations', 'Read the Safety observation register.', 62),
    ('SAF_OBSERVATIONS_RECORD', 'Safety', 'Record an Observation', 'Record a Safety observation.', 63),
    ('SAF_INJURY_TYPES_MAINTAIN', 'Safety', 'Injury types', 'Maintain the injury-type catalogue.', 64),
    ('SAF_BODY_PARTS_MAINTAIN', 'Safety', 'Body parts', 'Maintain the body-part catalogue.', 65),
    ('PRD_HANDOVER_DISPLAY', 'Production', 'Shift handovers', 'Read a Section''s Shift handover.', 66),
    ('PRD_HANDOVER_WRITE', 'Production', 'Write a Shift handover', 'Open, amend and submit a Section''s Shift handover.', 67),
    ('PRD_HANDOVER_ACKNOWLEDGE', 'Production', 'Acknowledge a Shift handover', 'Acknowledge the Shift handover handed to the caller.', 68),
    ('INS_TIER_BOARD_DISPLAY', 'Insights', 'Tier board', 'Read the tier board.', 69),
    ('INS_SKILL_COVERAGE_DISPLAY', 'Insights', 'Skill coverage', 'Read how coverage of each Skill stands across a Site.', 70),
    ('INS_KPI_CATALOGUE_DISPLAY', 'Insights', 'KPI catalogue', 'Read the MTU KPI catalogue and its Targets.', 71),
    ('INS_KPI_CATALOGUE_CHANGE', 'Insights', 'Maintain the KPI catalogue', 'Add a KPI or change its Targets.', 72),
    ('INS_KPI_REVIEW_DISPLAY', 'Insights', 'KPI review', 'Read the daily KPI review.', 73),
    ('INS_KPI_REVIEW_RECORD', 'Insights', 'Record a KPI review', 'Record the daily KPI review.', 74),
    ('ADM_APPROVALS_DISPLAY', 'Administration', 'Approvals', 'Read the queue of Accounts awaiting Approval.', 75),
    ('ADM_APPROVALS_DECIDE', 'Administration', 'Decide an Approval', 'Admit an Account with its role and Grants, or reject it.', 76),
    ('ADM_ACCOUNTS_DISPLAY', 'Administration', 'Accounts', 'Read every Account and the Grants each holds.', 77),
    ('ADM_ACCOUNTS_CHANGE', 'Administration', 'Administer Accounts', 'Correct an Account''s role or Grants, or deactivate it.', 78),
    ('ADM_ROLES_DISPLAY', 'Administration', 'Roles', 'Read the roles and the permissions each carries.', 79),
    ('ADM_ROLES_CHANGE', 'Administration', 'Maintain roles', 'Create a role, change what it carries, retire it, or assign it to an Account.', 80)
  `);

  // The five automatic roles plus the default group. Each legacy role carries
  // its COMPLETE set rather than a delta, because a legacy role is what an
  // administrator opens in the Roles Screen and edits: an empty Operator role
  // beside a non-empty Standard one would read as "operators have nothing",
  // which is the opposite of the truth.
  pgm.sql(`
    INSERT INTO app_roles (code, name, description, is_default, legacy_role)
    SELECT code, name, description, is_default, legacy_role
    FROM (VALUES
    ('ROLE_STANDARD', 'Standard', 'What every Account holds, whether or not an administrator assigns anything: the default group.', true, NULL),
    ('ROLE_OPERATOR', 'Operator', 'An Account whose app_users.role is operator. Today an operator earns nothing beyond the default group; this role exists so that is visible and changeable.', false, 'operator'),
    ('ROLE_SUPERVISOR', 'Supervisor', 'An Account whose app_users.role is supervisor: the default group plus the Maintenance and Insights Screens, and the shop-floor decisions a supervisor signs.', false, 'supervisor'),
    ('ROLE_ENGINEER', 'Engineer', 'An Account whose app_users.role is engineer: a supervisor''s set plus the writes behind an Asset, Work order, Part, Store and PM schedule, opening and verifying a CAPA, and disposing of nonconforming product.', false, 'engineer'),
    ('ROLE_MANAGER', 'Manager', 'An Account whose app_users.role is manager. Today a manager and an engineer are offered the same doors; the two roles are here so that they can diverge.', false, 'manager'),
    ('ROLE_ADMIN', 'Administrator', 'Every permission in the catalogue. An administrator also answers true to every check before the role''s own set is read (documented in ADR-0061), so this role is what makes the fact visible rather than the mechanism that grants it.', false, 'admin')
    ) AS seeded (code, name, description, is_default, legacy_role)
  `);

  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, permission_code
    FROM (VALUES
    ('ROLE_STANDARD', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_JOB_ROLES_DISPLAY', 'PPL_SKILLS_DISPLAY', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ATTENDANCE_DISPLAY', 'PPL_TRAINING_DISPLAY', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'MTN_REQUESTS_RAISE', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY', 'QLT_PRODUCTS_DISPLAY', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_CUSTOMERS_DISPLAY', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIER_NCRS_DISPLAY', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'INS_TIER_BOARD_DISPLAY']::TEXT[]),
    ('ROLE_OPERATOR', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_JOB_ROLES_DISPLAY', 'PPL_SKILLS_DISPLAY', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ATTENDANCE_DISPLAY', 'PPL_TRAINING_DISPLAY', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'MTN_REQUESTS_RAISE', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY', 'QLT_PRODUCTS_DISPLAY', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_CUSTOMERS_DISPLAY', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIER_NCRS_DISPLAY', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'INS_TIER_BOARD_DISPLAY']::TEXT[]),
    ('ROLE_SUPERVISOR', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_JOB_ROLES_DISPLAY', 'PPL_SKILLS_DISPLAY', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ATTENDANCE_DISPLAY', 'PPL_TRAINING_DISPLAY', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'MTN_REQUESTS_RAISE', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY', 'QLT_PRODUCTS_DISPLAY', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_CUSTOMERS_DISPLAY', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIER_NCRS_DISPLAY', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'INS_TIER_BOARD_DISPLAY', 'MTN_ASSETS_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY', 'MTN_PARTS_DISPLAY', 'MTN_STORES_DISPLAY', 'MTN_REQUESTS_TRIAGE', 'MTN_DOWNTIME_DISPLAY', 'MTN_DOWNTIME_CHANGE', 'MTN_PM_SCHEDULES_DISPLAY', 'MTN_METERS_DISPLAY', 'MTN_METERS_CHANGE', 'INS_KPI_CATALOGUE_DISPLAY', 'INS_KPI_REVIEW_DISPLAY', 'INS_KPI_REVIEW_RECORD', 'PPL_ATTENDANCE_CHANGE', 'PPL_TRAINING_CHANGE', 'PPL_LEAVE_REQUESTS_DECIDE', 'ACT_MEASURE', 'ACT_VERIFY', 'SAF_CLASSIFY']::TEXT[]),
    ('ROLE_ENGINEER', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_JOB_ROLES_DISPLAY', 'PPL_SKILLS_DISPLAY', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ATTENDANCE_DISPLAY', 'PPL_TRAINING_DISPLAY', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'MTN_REQUESTS_RAISE', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY', 'QLT_PRODUCTS_DISPLAY', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_CUSTOMERS_DISPLAY', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIER_NCRS_DISPLAY', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'INS_TIER_BOARD_DISPLAY', 'MTN_ASSETS_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY', 'MTN_PARTS_DISPLAY', 'MTN_STORES_DISPLAY', 'MTN_REQUESTS_TRIAGE', 'MTN_DOWNTIME_DISPLAY', 'MTN_DOWNTIME_CHANGE', 'MTN_PM_SCHEDULES_DISPLAY', 'MTN_METERS_DISPLAY', 'MTN_METERS_CHANGE', 'INS_KPI_CATALOGUE_DISPLAY', 'INS_KPI_REVIEW_DISPLAY', 'INS_KPI_REVIEW_RECORD', 'PPL_ATTENDANCE_CHANGE', 'PPL_TRAINING_CHANGE', 'PPL_LEAVE_REQUESTS_DECIDE', 'ACT_MEASURE', 'ACT_VERIFY', 'SAF_CLASSIFY', 'MTN_ASSETS_CHANGE', 'MTN_WORK_ORDERS_CHANGE', 'MTN_PARTS_CHANGE', 'MTN_STORES_CHANGE', 'MTN_PM_SCHEDULES_CHANGE', 'ACT_CAPA_OPEN', 'ACT_CAPA_VERIFY', 'ACT_CAPA_EFFECTIVENESS', 'QLT_NONCONFORMANCES_DISPOSE']::TEXT[]),
    ('ROLE_MANAGER', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_JOB_ROLES_DISPLAY', 'PPL_SKILLS_DISPLAY', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ATTENDANCE_DISPLAY', 'PPL_TRAINING_DISPLAY', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'MTN_REQUESTS_RAISE', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY', 'QLT_PRODUCTS_DISPLAY', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_CUSTOMERS_DISPLAY', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIER_NCRS_DISPLAY', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'INS_TIER_BOARD_DISPLAY', 'MTN_ASSETS_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY', 'MTN_PARTS_DISPLAY', 'MTN_STORES_DISPLAY', 'MTN_REQUESTS_TRIAGE', 'MTN_DOWNTIME_DISPLAY', 'MTN_DOWNTIME_CHANGE', 'MTN_PM_SCHEDULES_DISPLAY', 'MTN_METERS_DISPLAY', 'MTN_METERS_CHANGE', 'INS_KPI_CATALOGUE_DISPLAY', 'INS_KPI_REVIEW_DISPLAY', 'INS_KPI_REVIEW_RECORD', 'PPL_ATTENDANCE_CHANGE', 'PPL_TRAINING_CHANGE', 'PPL_LEAVE_REQUESTS_DECIDE', 'ACT_MEASURE', 'ACT_VERIFY', 'SAF_CLASSIFY', 'MTN_ASSETS_CHANGE', 'MTN_WORK_ORDERS_CHANGE', 'MTN_PARTS_CHANGE', 'MTN_STORES_CHANGE', 'MTN_PM_SCHEDULES_CHANGE', 'ACT_CAPA_OPEN', 'ACT_CAPA_VERIFY', 'ACT_CAPA_EFFECTIVENESS', 'QLT_NONCONFORMANCES_DISPOSE']::TEXT[]),
    ('ROLE_ADMIN', ARRAY['PPL_DIRECTORY_DISPLAY', 'PPL_DIRECTORY_CHANGE', 'PPL_JOB_ROLES_DISPLAY', 'PPL_JOB_ROLES_CHANGE', 'PPL_SKILLS_DISPLAY', 'PPL_SKILLS_CHANGE', 'PPL_ORG_UNITS_DISPLAY', 'PPL_ORG_UNITS_CHANGE', 'PPL_ATTENDANCE_DISPLAY', 'PPL_ATTENDANCE_CHANGE', 'PPL_TRAINING_DISPLAY', 'PPL_TRAINING_CHANGE', 'PPL_SIGNATURE_OWN', 'PPL_LEAVE_REQUESTS_DISPLAY', 'PPL_LEAVE_REQUESTS_DECIDE', 'PPL_COST_RATES_MAINTAIN', 'PPL_PRODUCT_COSTS_MAINTAIN', 'MTN_ASSETS_DISPLAY', 'MTN_ASSETS_CHANGE', 'MTN_WORK_ORDERS_DISPLAY', 'MTN_WORK_ORDERS_CHANGE', 'MTN_PARTS_DISPLAY', 'MTN_PARTS_CHANGE', 'MTN_STORES_DISPLAY', 'MTN_STORES_CHANGE', 'MTN_REQUESTS_RAISE', 'MTN_REQUESTS_TRIAGE', 'MTN_DOWNTIME_DISPLAY', 'MTN_DOWNTIME_CHANGE', 'MTN_PM_SCHEDULES_DISPLAY', 'MTN_PM_SCHEDULES_CHANGE', 'MTN_METERS_DISPLAY', 'MTN_METERS_CHANGE', 'MTN_JOB_PLANS_MAINTAIN', 'ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_MEASURE', 'ACT_VERIFY', 'ACT_CAPA_DISPLAY', 'ACT_CAPA_OPEN', 'ACT_CAPA_VERIFY', 'ACT_CAPA_EFFECTIVENESS', 'QLT_PRODUCTS_DISPLAY', 'QLT_PRODUCTS_CHANGE', 'QLT_DEFECT_CODES_DISPLAY', 'QLT_DEFECT_CODES_CHANGE', 'QLT_NONCONFORMANCES_DISPLAY', 'QLT_NONCONFORMANCES_RECORD', 'QLT_NONCONFORMANCES_DISPOSE', 'QLT_CUSTOMERS_DISPLAY', 'QLT_CUSTOMERS_CHANGE', 'QLT_COMPLAINTS_DISPLAY', 'QLT_COMPLAINTS_RECORD', 'QLT_SLIDESHOW_DISPLAY', 'QLT_SLIDESHOW_CHOOSE', 'QLT_SUPPLIERS_DISPLAY', 'QLT_SUPPLIERS_CHANGE', 'QLT_SUPPLIER_NCRS_DISPLAY', 'QLT_SUPPLIER_NCRS_RECORD', 'SAF_INCIDENTS_DISPLAY', 'SAF_INCIDENTS_RECORD', 'SAF_CLASSIFY', 'SAF_OBSERVATIONS_DISPLAY', 'SAF_OBSERVATIONS_RECORD', 'SAF_INJURY_TYPES_MAINTAIN', 'SAF_BODY_PARTS_MAINTAIN', 'PRD_HANDOVER_DISPLAY', 'PRD_HANDOVER_WRITE', 'PRD_HANDOVER_ACKNOWLEDGE', 'INS_TIER_BOARD_DISPLAY', 'INS_SKILL_COVERAGE_DISPLAY', 'INS_KPI_CATALOGUE_DISPLAY', 'INS_KPI_CATALOGUE_CHANGE', 'INS_KPI_REVIEW_DISPLAY', 'INS_KPI_REVIEW_RECORD', 'ADM_APPROVALS_DISPLAY', 'ADM_APPROVALS_DECIDE', 'ADM_ACCOUNTS_DISPLAY', 'ADM_ACCOUNTS_CHANGE', 'ADM_ROLES_DISPLAY', 'ADM_ROLES_CHANGE']::TEXT[])
    ) AS seeded (code, permissions)
    JOIN app_roles r ON r.code = seeded.code
    CROSS JOIN LATERAL unnest(seeded.permissions) AS permission_code
  `);

  for (const table of RLS_TABLES) {
    pgm.sql(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`);
  }

  pgm.sql(`SELECT attach_updated_at('permissions')`);
  pgm.sql(`SELECT attach_updated_at('app_roles')`);
  pgm.sql(`SELECT attach_actor_columns('app_roles')`);
  pgm.sql(`SELECT attach_audit('app_roles')`);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration define
  // both directions.
  pgm.sql('DROP TRIGGER IF EXISTS app_roles_audit ON app_roles');
  pgm.sql('DROP TRIGGER IF EXISTS zz_app_roles_set_actor ON app_roles');
  pgm.sql('DROP TRIGGER IF EXISTS app_roles_set_updated_at ON app_roles');
  pgm.sql('DROP TRIGGER IF EXISTS permissions_set_updated_at ON permissions');
  pgm.sql('DROP TABLE IF EXISTS app_user_roles');
  pgm.sql('DROP TABLE IF EXISTS app_role_permissions');
  pgm.sql('DROP TABLE IF EXISTS app_roles');
  pgm.sql('DROP TABLE IF EXISTS permissions');
};
