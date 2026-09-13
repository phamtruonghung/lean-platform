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

-- -----------------------------------------------------------------------------
-- Inventory — the parts catalogue, two stores, and the stock they hold.
-- A store's on-hand level is derived from these movements, never stored.
-- -----------------------------------------------------------------------------
INSERT INTO parts (part_no, description, uom_code) VALUES
  ('DEMO-P-1001', 'Hydraulic oil ISO 46',   'L'),
  ('DEMO-P-1002', 'Conveyor belt 600 mm',   'M'),
  ('DEMO-P-1003', 'Bearing 6205-2RS',       'EA'),
  ('DEMO-P-1004', 'Grease cartridge',       'EA'),
  ('DEMO-P-1005', 'Safety gloves, pair',    'EA')
ON CONFLICT (part_no) DO NOTHING;

INSERT INTO stores (site_id, org_unit_id, code, name) VALUES
  ((SELECT id FROM sites WHERE code = 'DEMO'),
   (SELECT id FROM org_units WHERE code = 'A1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-STORE-MAIN', 'Main Stores'),
  ((SELECT id FROM sites WHERE code = 'DEMO'),
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   'DEMO-STORE-LINE', 'Cell 1 line-side')
ON CONFLICT (site_id, code) DO NOTHING;

-- Opening receipts. Positive, so their order among themselves cannot trip the
-- below-zero refusal. Guarded per (part, store, reason) so re-running never
-- adds a second opening balance.
INSERT INTO stock_movements (part_id, store_id, quantity, movement_type, reason, occurred_at)
SELECT p.id, s.id, v.quantity, 'receipt', 'DEMO opening receipt',
       now() - make_interval(days => v.days_ago)
  FROM (VALUES
    ('DEMO-P-1001', 'DEMO-STORE-MAIN', 200,  20),
    ('DEMO-P-1002', 'DEMO-STORE-MAIN', 120,  20),
    ('DEMO-P-1003', 'DEMO-STORE-MAIN',  40,  20),
    ('DEMO-P-1004', 'DEMO-STORE-MAIN',  60,  20),
    ('DEMO-P-1005', 'DEMO-STORE-MAIN', 100,  20),
    ('DEMO-P-1003', 'DEMO-STORE-LINE',  10,  18),
    ('DEMO-P-1004', 'DEMO-STORE-LINE',  15,  18)
  ) AS v(part_no, store_code, quantity, days_ago)
  JOIN parts p ON p.part_no = v.part_no
  JOIN stores s ON s.code = v.store_code
   AND s.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
 WHERE NOT EXISTS (
   SELECT 1 FROM stock_movements m
    WHERE m.part_id = p.id AND m.store_id = s.id AND m.reason = 'DEMO opening receipt'
 );

-- The one count correction, in its own statement so it runs after the receipts
-- above have been applied: an outbound movement can legitimately be refused if
-- the shelf is empty, and this seed must not depend on row order to avoid that.
INSERT INTO stock_movements (part_id, store_id, quantity, movement_type, reason, occurred_at)
SELECT p.id, s.id, -2, 'adjustment', 'DEMO cycle count: two bearings scrapped',
       now() - make_interval(days => 10)
  FROM parts p
  JOIN stores s ON s.code = 'DEMO-STORE-MAIN'
   AND s.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
 WHERE p.part_no = 'DEMO-P-1003'
   AND NOT EXISTS (
     SELECT 1 FROM stock_movements m
      WHERE m.part_id = p.id AND m.store_id = s.id
        AND m.reason = 'DEMO cycle count: two bearings scrapped'
   );

-- -----------------------------------------------------------------------------
-- Suppliers — used by a purchased part booking.
-- -----------------------------------------------------------------------------
INSERT INTO suppliers (code, name) VALUES
  ('DEMO-SUP-1', 'Hydraulics Direct'),
  ('DEMO-SUP-2', 'Bearing Supplies Ltd')
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Meters and readings — accumulated use for the meter-driven PM that follows.
-- Guarded on (meter, reading): readings are distinct per meter here, so a re-run
-- leaves them alone even though the timestamps are relative to run time.
-- -----------------------------------------------------------------------------
INSERT INTO asset_meters (asset_id, code, name, uom_code, meter_type) VALUES
  ((SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), 'HOURS',   'Running hours', 'H',  'cumulative'),
  ((SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), 'STROKES', 'Strokes',       'EA', 'cumulative'),
  ((SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),   'HOURS',   'Spindle hours', 'H',  'cumulative')
ON CONFLICT (asset_id, code) DO NOTHING;

INSERT INTO meter_readings (asset_meter_id, org_unit_id, reading, read_at, read_by, source)
SELECT am.id, a.org_unit_id, v.reading,
       now() - make_interval(days => v.days_ago), e.id, 'manual'
  FROM (VALUES
    ('DEMO-PRESS-01', 'HOURS',   4980.0, 30),
    ('DEMO-PRESS-01', 'HOURS',   5005.0, 10),
    ('DEMO-PRESS-01', 'HOURS',   5042.0,  2),
    ('DEMO-PRESS-01', 'STROKES', 980000.0, 30),
    ('DEMO-PRESS-01', 'STROKES', 992500.0,  2),
    ('DEMO-CNC-01',   'HOURS',   12050.0, 30),
    ('DEMO-CNC-01',   'HOURS',   12180.0,  5)
  ) AS v(asset_code, meter_code, reading, days_ago)
  JOIN assets a ON a.code = v.asset_code
  JOIN asset_meters am ON am.asset_id = a.id AND am.code = v.meter_code
  JOIN employees e ON e.employee_no = 'DEMO-001'
 WHERE NOT EXISTS (
   SELECT 1 FROM meter_readings mr
    WHERE mr.asset_meter_id = am.id AND mr.reading = v.reading
 );

-- -----------------------------------------------------------------------------
-- Job plans — the reusable content of a PM job, with its own task list.
-- -----------------------------------------------------------------------------
INSERT INTO job_plans (code, name, description, work_type, estimated_hours, requires_shutdown, safety_note) VALUES
  ('DEMO-JP-500H', 'Press 500-hour service', 'Replace hydraulic oil and inspect the press.',
   'preventive', 4, TRUE, 'Isolate and lock off before breaking into the hydraulic circuit.'),
  ('DEMO-JP-ELEC-ANNUAL', 'Annual electrical inspection', 'Thermographic scan and safety-circuit test.',
   'inspection', 2, TRUE, 'Panel covers to be refitted before the machine is re-energised.')
ON CONFLICT (code) DO NOTHING;

INSERT INTO job_plan_tasks (job_plan_id, step_no, instruction, skill_id, estimated_hours, records_meter_id) VALUES
  ((SELECT id FROM job_plans WHERE code = 'DEMO-JP-500H'), 1,
   'Isolate and lock off the press.', (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 0.5, NULL),
  ((SELECT id FROM job_plans WHERE code = 'DEMO-JP-500H'), 2,
   'Drain and replace the hydraulic oil.', (SELECT id FROM skills WHERE code = 'MECH-FIT'), 2, NULL),
  ((SELECT id FROM job_plans WHERE code = 'DEMO-JP-500H'), 3,
   'Record the press running-hour meter.',
   (SELECT id FROM skills WHERE code = 'MECH-FIT'), 0.5,
   (SELECT am.id FROM asset_meters am JOIN assets a ON a.id = am.asset_id
     WHERE a.code = 'DEMO-PRESS-01' AND am.code = 'HOURS')),
  ((SELECT id FROM job_plans WHERE code = 'DEMO-JP-ELEC-ANNUAL'), 1,
   'Thermographic scan of the line panels.', (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 1, NULL),
  ((SELECT id FROM job_plans WHERE code = 'DEMO-JP-ELEC-ANNUAL'), 2,
   'Test the emergency-stop circuits.', (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 1, NULL)
ON CONFLICT (job_plan_id, step_no) DO NOTHING;

-- -----------------------------------------------------------------------------
-- PM schedules — the three interval shapes: calendar, meter, and both.
-- -----------------------------------------------------------------------------
INSERT INTO pm_schedules
  (code, name, asset_id, job_plan_id, interval_days, asset_meter_id, interval_meter,
   anchor, lead_time_days, priority, last_completed_on, last_completed_meter,
   next_due_on, next_due_meter)
VALUES
  ('DEMO-PM-500H', 'Press service every 500 hours',
   (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'),
   (SELECT id FROM job_plans WHERE code = 'DEMO-JP-500H'),
   NULL,
   (SELECT am.id FROM asset_meters am JOIN assets a ON a.id = am.asset_id
     WHERE a.code = 'DEMO-PRESS-01' AND am.code = 'HOURS'),
   500, 'completed', 14, 3, NULL, 4500, NULL, 5000),
  ('DEMO-PM-ANNUAL', 'Annual electrical inspection',
   (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),
   (SELECT id FROM job_plans WHERE code = 'DEMO-JP-ELEC-ANNUAL'),
   365, NULL, NULL, 'due', 30, 3, CURRENT_DATE - 300, NULL, CURRENT_DATE + 65, NULL),
  ('DEMO-PM-BOTH', 'CNC service, 180 days or 2,000 hours',
   (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),
   (SELECT id FROM job_plans WHERE code = 'DEMO-JP-ELEC-ANNUAL'),
   180,
   (SELECT am.id FROM asset_meters am JOIN assets a ON a.id = am.asset_id
     WHERE a.code = 'DEMO-CNC-01' AND am.code = 'HOURS'),
   2000, 'completed', 14, 4, CURRENT_DATE - 120, 10800, CURRENT_DATE + 60, 12800)
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Downtime — inserted before the breakdown work order that points at it.
-- Guarded on (asset, description).
-- -----------------------------------------------------------------------------
INSERT INTO downtime_events
  (asset_id, org_unit_id, downtime_reason_id, started_at, ended_at, description,
   reported_by, classified_by, classified_at)
SELECT a.id, a.org_unit_id, r.id,
       now() - make_interval(days => v.days_ago), now() - make_interval(days => v.days_ago) + make_interval(mins => v.mins),
       v.description, er.id, ec.id, now() - make_interval(days => v.days_ago) + make_interval(mins => v.mins)
  FROM (VALUES
    ('DEMO-PRESS-01', 'BRK', 3, 120, 'Press stopped: hydraulic failure'),
    ('DEMO-CNC-01',   'MIN', 5,  20, 'CNC minor stop: tool change')
  ) AS v(asset_code, reason_code, days_ago, mins, description)
  JOIN assets a ON a.code = v.asset_code
  JOIN downtime_reasons r ON r.code = v.reason_code
  JOIN employees er ON er.employee_no = 'DEMO-004'
  JOIN employees ec ON ec.employee_no = 'DEMO-005'
 WHERE NOT EXISTS (
   SELECT 1 FROM downtime_events d
    WHERE d.asset_id = a.id AND d.description = v.description
 );

-- -----------------------------------------------------------------------------
-- Maintenance requests — one per state the triage queue shows.
-- -----------------------------------------------------------------------------
INSERT INTO maintenance_requests
  (request_no, asset_id, summary, description, urgency, production_stopped,
   reported_by, reported_at, status, triaged_by, triaged_at)
VALUES
  ('DEMO-MR-1', (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),
   'CNC Mill 1 making an intermittent noise', 'A rattle from the spindle area under load.',
   'normal', FALSE, (SELECT id FROM employees WHERE employee_no = 'DEMO-004'),
   now() - interval '3 days', 'new', NULL, NULL),
  ('DEMO-MR-2', (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'),
   'Hydraulic oil leak under the press', 'A slow drip, roughly a litre a shift.',
   'high', FALSE, (SELECT id FROM employees WHERE employee_no = 'DEMO-004'),
   now() - interval '2 days', 'triaged',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-005'), now() - interval '2 days' + interval '2 hours'),
  ('DEMO-MR-3', (SELECT id FROM assets WHERE code = 'DEMO-PACKER-01'),
   'Palletiser guarding interlock occasionally fails', 'The gate needs a firm push to latch.',
   'normal', FALSE, (SELECT id FROM employees WHERE employee_no = 'DEMO-004'),
   now() - interval '5 days', 'accepted',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-005'), now() - interval '4 days')
ON CONFLICT (request_no) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Work orders — one per lifecycle state, plus the breakdown that cleared the
-- press downtime above. Completed rows carry an actual_end, as the schema
-- requires.
-- -----------------------------------------------------------------------------
INSERT INTO work_orders
  (work_order_no, asset_id, maintenance_request_id, summary, description, work_type,
   is_breakdown, priority, status, scheduled_start, scheduled_end, estimated_hours,
   requires_shutdown, actual_start, actual_end, assigned_to, completed_by,
   completion_note, downtime_event_id, pm_schedule_id, due_date)
VALUES
  ('DEMO-WO-1', (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'), NULL,
   'Investigate CNC spindle noise', 'Raised from the operator report.', 'corrective',
   FALSE, 3, 'draft', NULL, NULL, 2, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('DEMO-WO-2', (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), NULL,
   'Press 500-hour service', 'Generated by the meter-driven PM schedule.', 'preventive',
   FALSE, 3, 'approved', now() + interval '2 days', now() + interval '2 days' + interval '4 hours',
   4, TRUE, NULL, NULL, NULL, NULL, NULL, NULL,
   (SELECT id FROM pm_schedules WHERE code = 'DEMO-PM-500H'), (CURRENT_DATE + 2)),
  ('DEMO-WO-3', (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'),
   (SELECT id FROM maintenance_requests WHERE request_no = 'DEMO-MR-2'),
   'Repair hydraulic oil leak', 'Replace the leaking hose and top up the oil.', 'corrective',
   FALSE, 2, 'scheduled', now() + interval '1 day', now() + interval '1 day' + interval '3 hours',
   3, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, (CURRENT_DATE + 1)),
  ('DEMO-WO-4', (SELECT id FROM assets WHERE code = 'DEMO-CONV-01'), NULL,
   'Conveyor belt tracking and tension', 'Scheduled inspection and adjustment.', 'preventive',
   FALSE, 3, 'in_progress', now() - interval '1 day', now() - interval '1 day' + interval '3 hours',
   2, FALSE, now() - interval '6 hours', NULL,
   (SELECT id FROM employees WHERE employee_no = 'DEMO-001'), NULL, NULL, NULL, NULL, NULL),
  ('DEMO-WO-5', (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), NULL,
   'Replace press hydraulic oil', 'Oil change and filter replacement.', 'preventive',
   FALSE, 2, 'completed', now() - interval '8 days', now() - interval '8 days' + interval '3 hours',
   3, TRUE, now() - interval '8 days', now() - interval '8 days' + interval '3 hours',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-002'),
   (SELECT id FROM employees WHERE employee_no = 'DEMO-005'),
   'Oil and filter replaced; no swarf found.', NULL, NULL, (CURRENT_DATE - 8)),
  ('DEMO-WO-6', (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'), NULL,
   'Breakdown: press hydraulic failure', 'Emergency repair after the press stopped.', 'corrective',
   TRUE, 1, 'completed', NULL, NULL, 3, FALSE,
   now() - interval '3 days', now() - interval '3 days' + interval '2 hours',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-001'),
   (SELECT id FROM employees WHERE employee_no = 'DEMO-001'),
   'Hose replaced; press returned to service.',
   (SELECT id FROM downtime_events WHERE description = 'Press stopped: hydraulic failure'),
   NULL, (CURRENT_DATE - 3)),
  ('DEMO-WO-7', (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'), NULL,
   'Annual electrical inspection', 'Completed on time against the PM schedule.', 'inspection',
   FALSE, 3, 'completed', NULL, NULL, 2, TRUE,
   now() - interval '30 days', now() - interval '30 days' + interval '2 hours',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-002'),
   (SELECT id FROM employees WHERE employee_no = 'DEMO-002'),
   'Thermographic scan clear; emergency stops tested.',
   NULL, (SELECT id FROM pm_schedules WHERE code = 'DEMO-PM-ANNUAL'), (CURRENT_DATE - 30))
ON CONFLICT (work_order_no) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Work order tasks — copied from the plan in reality; here, enough to show a
-- partly done job and a finished one.
-- -----------------------------------------------------------------------------
INSERT INTO work_order_tasks (work_order_id, step_no, instruction, skill_id, status, note, completed_by, completed_at) VALUES
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-4'), 1,
   'Isolate the conveyor.', (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 'done', NULL,
   (SELECT id FROM employees WHERE employee_no = 'DEMO-001'), now() - interval '6 hours'),
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-4'), 2,
   'Inspect belt tracking.', (SELECT id FROM skills WHERE code = 'MECH-FIT'), 'pending', NULL, NULL, NULL),
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-4'), 3,
   'Adjust tension if required.', (SELECT id FROM skills WHERE code = 'MECH-FIT'), 'pending', NULL, NULL, NULL),
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-5'), 1,
   'Isolate and lock off the press.', (SELECT id FROM skills WHERE code = 'ELEC-ISO'), 'done', NULL,
   (SELECT id FROM employees WHERE employee_no = 'DEMO-002'), now() - interval '8 days'),
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-5'), 2,
   'Drain and replace the hydraulic oil.', (SELECT id FROM skills WHERE code = 'MECH-FIT'), 'done', NULL,
   (SELECT id FROM employees WHERE employee_no = 'DEMO-002'), now() - interval '8 days' + interval '2 hours'),
  ((SELECT id FROM work_orders WHERE work_order_no = 'DEMO-WO-5'), 3,
   'Record the press running-hour meter.', (SELECT id FROM skills WHERE code = 'MECH-FIT'), 'done', NULL,
   (SELECT id FROM employees WHERE employee_no = 'DEMO-005'), now() - interval '8 days' + interval '2 hours 30 minutes')
ON CONFLICT (work_order_id, step_no) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Labour — non-overlapping windows per Employee, as the schema's exclusion
-- constraint demands. Guarded on (work order, Employee): one booking each here.
-- -----------------------------------------------------------------------------
INSERT INTO work_order_labour (work_order_id, employee_id, started_at, ended_at, activity, is_overtime, note)
SELECT wo.id, e.id, v.started, v.ended, v.activity, v.overtime, v.note
  FROM (VALUES
    ('DEMO-WO-5', 'DEMO-002', now() - interval '8 days', now() - interval '8 days' + interval '2 hours', 'work', FALSE, NULL),
    ('DEMO-WO-5', 'DEMO-005', now() - interval '8 days' + interval '2 hours', now() - interval '8 days' + interval '3 hours', 'diagnosis', FALSE, 'Checked for swarf.'),
    ('DEMO-WO-6', 'DEMO-001', now() - interval '3 days', now() - interval '3 days' + interval '1 hour 30 minutes', 'work', TRUE, 'Called in early.'),
    ('DEMO-WO-4', 'DEMO-001', now() - interval '6 hours', now() - interval '5 hours', 'work', FALSE, NULL)
  ) AS v(wo_no, employee_no, started, ended, activity, overtime, note)
  JOIN work_orders wo ON wo.work_order_no = v.wo_no
  JOIN employees e ON e.employee_no = v.employee_no
 WHERE NOT EXISTS (
   SELECT 1 FROM work_order_labour l
    WHERE l.work_order_id = wo.id AND l.employee_id = e.id
 );

-- -----------------------------------------------------------------------------
-- Parts fitted: one drawn from the main store (with the matching stock
-- movement), one bought in (touching no stock).
-- -----------------------------------------------------------------------------
INSERT INTO work_order_parts (work_order_id, part_no, description, quantity, uom_code, unit_cost, sourced, supplier_id, fitted_at)
SELECT wo.id, p.part_no, p.description, 2, p.uom_code, 12.50, 'stores', NULL, now() - interval '8 days'
  FROM work_orders wo
  JOIN parts p ON p.part_no = 'DEMO-P-1003'
 WHERE wo.work_order_no = 'DEMO-WO-5'
   AND NOT EXISTS (
     SELECT 1 FROM work_order_parts wp
      WHERE wp.work_order_id = wo.id AND wp.part_no = 'DEMO-P-1003'
   );

INSERT INTO work_order_parts (work_order_id, part_no, description, quantity, uom_code, unit_cost, sourced, supplier_id, fitted_at)
SELECT wo.id, 'HYD-HOSE-3/4', 'Hydraulic hose 3/4"', 1, 'M', 30.00, 'purchased',
       (SELECT id FROM suppliers WHERE code = 'DEMO-SUP-1'), now() - interval '3 days'
  FROM work_orders wo
 WHERE wo.work_order_no = 'DEMO-WO-6'
   AND NOT EXISTS (
     SELECT 1 FROM work_order_parts wp
      WHERE wp.work_order_id = wo.id AND wp.part_no = 'HYD-HOSE-3/4'
   );

-- The stores-sourced booking's outbound movement. `stock_movements` permits
-- `receipt` and `adjustment`; a job issue is an adjustment whose reason names
-- the work order (see #75). Guarded on the reason so a re-run does not draw the
-- shelf down twice.
INSERT INTO stock_movements (part_id, store_id, quantity, movement_type, reason, occurred_at)
SELECT p.id, s.id, -2, 'adjustment', 'Issued to DEMO-WO-5', now() - interval '8 days'
  FROM parts p
  JOIN stores s ON s.code = 'DEMO-STORE-MAIN' AND s.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
 WHERE p.part_no = 'DEMO-P-1003'
   AND NOT EXISTS (
     SELECT 1 FROM stock_movements m
      WHERE m.part_id = p.id AND m.store_id = s.id AND m.reason = 'Issued to DEMO-WO-5'
   );

COMMIT;
