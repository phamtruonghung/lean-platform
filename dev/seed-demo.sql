-- =============================================================================
-- Demo data for the local review stack (scripts/review.sh).
--
-- Applied by `./scripts/review.sh up` after migrations, and by
-- `./scripts/review.sh seed` on demand. This is local development data only:
-- it runs inside the review stack's own Postgres and is never applied in
-- production, where `deploy/deploy.sh` runs migrations and nothing else.
--
-- Two things this file deliberately does NOT do:
--   - It never inserts `app_users`. An Account row is created by
--     `resolveAccountForIdentity` on a person's first Supabase sign-in (see
--     `cmd_promote_admin` in scripts/review.sh); pre-creating one would make
--     that sign-in try to INSERT a second row with the same unique email and
--     fail. Use `./scripts/review.sh grant-account` to give an Account that
--     has signed in a Grant on a Demo Org Unit.
--   - It seeds no Floor device or technician PIN. A device credential is a
--     build-time `--dart-define`, and a technician PIN is hashed with salt by
--     the API; neither is something SQL can produce.
--
-- Idempotency. Every row is keyed by a fixed demo identifier and inserted with
-- ON CONFLICT DO NOTHING, or guarded by a NOT EXISTS on a fixed parent. The
-- work order, request and PM numbers use a `DEMO-` prefix rather than
-- `next_document_number()`, so re-running never advances a document sequence or
-- duplicates a row. A re-run must leave every count unchanged.
--
-- Shape. The whole file is one transaction: a failure part-way rolls the seed
-- back rather than leaving a half-populated plant, and `review.sh` runs psql
-- with ON_ERROR_STOP=1 so that failure is loud.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Site and Org Units — the Demo Plant's shape.
-- -----------------------------------------------------------------------------
INSERT INTO sites (code, name, timezone, country_code)
VALUES ('DEMO', 'Demo Plant', 'UTC', 'GB')
ON CONFLICT (code) DO NOTHING;

INSERT INTO org_units (site_id, parent_id, code, name, unit_type, sort_order) VALUES
  ((SELECT id FROM sites WHERE code = 'DEMO'), NULL,
   'A1', 'Assembly', 'area', 1),
  ((SELECT id FROM sites WHERE code = 'DEMO'), NULL,
   'PKG', 'Packaging', 'area', 2)
ON CONFLICT (site_id, code) DO NOTHING;

INSERT INTO org_units (site_id, parent_id, code, name, unit_type, sort_order) VALUES
  ((SELECT id FROM sites WHERE code = 'DEMO'),
   (SELECT id FROM org_units WHERE code = 'A1'
      AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'A1-L1', 'Assembly Line 1', 'line', 1),
  ((SELECT id FROM sites WHERE code = 'DEMO'),
   (SELECT id FROM org_units WHERE code = 'PKG'
      AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'PKG-L1', 'Packaging Line 1', 'line', 1)
ON CONFLICT (site_id, code) DO NOTHING;

INSERT INTO org_units (site_id, parent_id, code, name, unit_type, sort_order) VALUES
  ((SELECT id FROM sites WHERE code = 'DEMO'),
   (SELECT id FROM org_units WHERE code = 'A1-L1'
      AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'A1-L1-C1', 'Assembly Cell 1', 'cell', 1)
ON CONFLICT (site_id, code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Job roles and skills — the shared people catalogue.
-- -----------------------------------------------------------------------------
INSERT INTO job_roles (code, name) VALUES
  ('FITTER', 'Mechanical Fitter'),
  ('ELEC',   'Electrician'),
  ('PLAN',   'Planner'),
  ('OPER',   'Operator')
ON CONFLICT (code) DO NOTHING;

INSERT INTO skills (code, name, skill_category, requires_certification, revalidation_months) VALUES
  ('MECH-FIT', 'Mechanical fitting',         'maintenance', FALSE, NULL),
  ('ELEC-ISO', 'Electrical isolation',       'safety',      TRUE,  12),
  ('VIB',      'Vibration analysis',         'maintenance', FALSE, 24)
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Employees — the Demo Plant's people.
-- -----------------------------------------------------------------------------
INSERT INTO employees (employee_no, first_name, last_name, employment_type, default_org_unit_id) VALUES
  ('DEMO-001', 'Nour',  'Haddad',  'permanent',
   (SELECT id FROM org_units WHERE code = 'A1-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO'))),
  ('DEMO-002', 'Tomas', 'Berg',    'permanent',
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO'))),
  ('DEMO-003', 'Priya', 'Nair',    'permanent',
   (SELECT id FROM org_units WHERE code = 'A1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO'))),
  ('DEMO-004', 'Sam',   'Okafor',  'permanent',
   (SELECT id FROM org_units WHERE code = 'PKG-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO'))),
  ('DEMO-005', 'Lena',  'Fischer', 'permanent',
   (SELECT id FROM org_units WHERE code = 'A1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')))
ON CONFLICT (employee_no) DO NOTHING;

-- One current assignment each. No natural unique key, so guarded on the
-- Employee rather than a NEW-EXISTS on the composite.
INSERT INTO employee_assignments (employee_id, org_unit_id, job_role_id, effective_from)
SELECT e.id, e.default_org_unit_id, jr.id, DATE '2024-01-01'
  FROM employees e
  JOIN job_roles jr ON jr.code = CASE e.employee_no
                                    WHEN 'DEMO-001' THEN 'FITTER'
                                    WHEN 'DEMO-002' THEN 'ELEC'
                                    WHEN 'DEMO-003' THEN 'PLAN'
                                    WHEN 'DEMO-004' THEN 'OPER'
                                    WHEN 'DEMO-005' THEN 'FITTER'
                                  END
 WHERE e.employee_no LIKE 'DEMO-%'
   AND NOT EXISTS (SELECT 1 FROM employee_assignments ea WHERE ea.employee_id = e.id);

INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, assessed_on) VALUES
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-001'),
   (SELECT id FROM skills WHERE code = 'MECH-FIT'), 3, DATE '2025-06-01'),
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-001'),
   (SELECT id FROM skills WHERE code = 'VIB'),      2, DATE '2025-06-01'),
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-002'),
   (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 3, DATE '2025-09-15'),
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-003'),
   (SELECT id FROM skills WHERE code = 'MECH-FIT'), 2, DATE '2025-03-10'),
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-005'),
   (SELECT id FROM skills WHERE code = 'MECH-FIT'), 4, DATE '2025-01-20'),
  ((SELECT id FROM employees WHERE employee_no = 'DEMO-005'),
   (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 2, DATE '2025-01-20')
ON CONFLICT (employee_id, skill_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Assets — machines and one component, at their Org Units.
-- -----------------------------------------------------------------------------
INSERT INTO assets (org_unit_id, code, name, asset_type, criticality, is_constraint, manufacturer, asset_level) VALUES
  ((SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-CNC-01',    'CNC Mill 1',      'machine', 'high',     TRUE,  'Haas',    'machine'),
  ((SELECT id FROM org_units WHERE code = 'A1-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-PRESS-01',  'Hydraulic Press', 'machine', 'critical', FALSE, 'Schuler', 'machine'),
  ((SELECT id FROM org_units WHERE code = 'A1-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-CONV-01',   'Assembly Conveyor', 'machine', 'medium', FALSE, NULL,     'machine'),
  ((SELECT id FROM org_units WHERE code = 'PKG-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-PACKER-01', 'Palletiser',      'machine', 'high',     FALSE, 'ABB',     'machine')
ON CONFLICT (code) DO NOTHING;

-- The component sits under the press; its own code is still globally unique.
INSERT INTO assets (org_unit_id, code, name, asset_type, criticality, parent_id, asset_level) VALUES
  ((SELECT id FROM org_units WHERE code = 'A1-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-COMP-01', 'Press hydraulic pump', 'other', 'medium',
   (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), 'component')
ON CONFLICT (code) DO NOTHING;

COMMIT;
