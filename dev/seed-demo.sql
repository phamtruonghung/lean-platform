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

-- -----------------------------------------------------------------------------
-- Shift calendar — a two-shift pattern, generated across recent and upcoming
-- days. `generate_shift_instances` is idempotent, so re-running is safe.
-- -----------------------------------------------------------------------------
INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes, day_offset, sort_order) VALUES
  ((SELECT id FROM sites WHERE code = 'DEMO'), 'D', 'Day shift',   TIME '06:00', 480, 30, 0, 1),
  ((SELECT id FROM sites WHERE code = 'DEMO'), 'N', 'Night shift', TIME '22:00', 480, 30, 0, 2)
ON CONFLICT (site_id, code) DO NOTHING;

SELECT generate_shift_instances(id, CURRENT_DATE - 30, CURRENT_DATE + 60)
  FROM org_units
 WHERE site_id = (SELECT id FROM sites WHERE code = 'DEMO');

-- -----------------------------------------------------------------------------
-- Production — one product, two orders, and a month of runs with counts.
--
-- A note on scope: the Tier board's registry maps only the eight maintenance
-- KPIs, so these production rows populate their own tables and any Screen that
-- reads them, but they do not put an OEE number on the board today.
-- -----------------------------------------------------------------------------
INSERT INTO products (code, name, description, product_type, uom_code) VALUES
  ('DEMO-PROD-1', 'Widget A', 'A finished widget used for the demo plant.', 'finished', 'EA')
ON CONFLICT (code) DO NOTHING;

INSERT INTO production_orders
  (order_no, product_id, org_unit_id, quantity_ordered, uom_code, due_date, promised_date,
   priority, status, released_at, started_at, completed_at)
VALUES
  ('DEMO-PO-1', (SELECT id FROM products WHERE code = 'DEMO-PROD-1'),
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   2000, 'EA', CURRENT_DATE + 5, CURRENT_DATE + 5, 2, 'in_progress',
   now() - interval '20 days', now() - interval '20 days', NULL),
  ('DEMO-PO-2', (SELECT id FROM products WHERE code = 'DEMO-PROD-1'),
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   1500, 'EA', CURRENT_DATE - 3, CURRENT_DATE - 3, 3, 'completed',
   now() - interval '40 days', now() - interval '35 days', now() - interval '31 days')
ON CONFLICT (order_no) DO NOTHING;

-- Ten completed runs on the constraint machine, one every few days. Guarded on
-- the run's own note, which is stable, rather than on a relative timestamp.
INSERT INTO production_runs
  (production_order_id, product_id, org_unit_id, asset_id, planned_quantity, uom_code,
   started_at, ended_at, status, notes)
SELECT po.id, pr.id, a.org_unit_id, a.id, 200, 'EA',
       now() - make_interval(days => 30 - gs.n * 3),
       now() - make_interval(days => 30 - gs.n * 3) + interval '8 hours',
       'completed', 'DEMO production run ' || gs.n
  FROM generate_series(1, 10) AS gs(n)
  JOIN products pr ON pr.code = 'DEMO-PROD-1'
  JOIN assets a ON a.code = 'DEMO-CNC-01'
  JOIN production_orders po ON po.order_no = 'DEMO-PO-1'
 WHERE NOT EXISTS (
   SELECT 1 FROM production_runs r WHERE r.notes = 'DEMO production run ' || gs.n
 );

INSERT INTO production_counts
  (production_run_id, org_unit_id, asset_id, shift_instance_id, period_start, period_end,
   good_quantity, reject_quantity, rework_quantity, uom_code, recorded_by)
SELECT r.id, r.org_unit_id, r.asset_id, r.shift_instance_id, r.started_at, r.ended_at,
       180, 15, 5, 'EA', e.id
  FROM production_runs r
  JOIN employees e ON e.employee_no = 'DEMO-004'
 WHERE r.notes LIKE 'DEMO production run %'
   AND NOT EXISTS (SELECT 1 FROM production_counts pc WHERE pc.production_run_id = r.id);

-- -----------------------------------------------------------------------------
-- Quality and safety — a couple of records each, so those tables are not empty.
-- -----------------------------------------------------------------------------
INSERT INTO quality_issues
  (issue_no, org_unit_id, asset_id, product_id, defect_code_id, detection_point, severity,
   quantity_affected, uom_code, detected_at, detected_by, description, status)
VALUES
  ('DEMO-NC-1',
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),
   (SELECT id FROM products WHERE code = 'DEMO-PROD-1'),
   (SELECT id FROM defect_codes WHERE code = 'SUR'),
   'final_inspection', 'minor', 12, 'EA', now() - interval '12 days',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-004'),
   'Surface marks found on twelve widgets.', 'open'),
  ('DEMO-NC-2',
   (SELECT id FROM org_units WHERE code = 'A1-L1-C1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   (SELECT id FROM assets WHERE code = 'DEMO-CNC-01'),
   (SELECT id FROM products WHERE code = 'DEMO-PROD-1'),
   (SELECT id FROM defect_codes WHERE code = 'FUN'),
   'in_process', 'major', 5, 'EA', now() - interval '4 days',
   (SELECT id FROM employees WHERE employee_no = 'DEMO-004'),
   'Functional test failures on five units.', 'contained')
ON CONFLICT (issue_no) DO NOTHING;

INSERT INTO safety_incidents
  (incident_no, org_unit_id, asset_id, occurred_at, incident_type, severity_level,
   description, status, closed_at)
VALUES
  ('DEMO-SI-1',
   (SELECT id FROM org_units WHERE code = 'PKG-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   (SELECT id FROM assets WHERE code = 'DEMO-PACKER-01'),
   now() - interval '9 days', 'near_miss', 'near_miss',
   'A pallet fell from the stacker; nobody was in the area.', 'closed', now() - interval '8 days'),
  ('DEMO-SI-2',
   (SELECT id FROM org_units WHERE code = 'A1-L1' AND site_id = (SELECT id FROM sites WHERE code = 'DEMO')),
   (SELECT id FROM assets WHERE code = 'DEMO-PRESS-01'),
   now() - interval '2 days', 'injury', 'first_aid',
   'Minor hand laceration while changing a hydraulic hose.', 'open', NULL)
ON CONFLICT (incident_no) DO NOTHING;

INSERT INTO safety_observations
  (org_unit_id, observed_at, observation_type, category, severity_potential, description, observer_employee_id)
SELECT ou.id, now() - make_interval(days => v.days_ago), v.observation_type, v.category,
       v.severity_potential, v.description, e.id
  FROM (VALUES
    ('A1-L1-C1', 7, 'unsafe_condition', 'housekeeping', 'medium', 'DEMO safety observation: oil spill left unmarked.', 'DEMO-002'),
    ('A1-L1',    3, 'safe_act',         'energy_isolation', 'low', 'DEMO safety observation: lock-off applied correctly.', 'DEMO-001')
  ) AS v(unit_code, days_ago, observation_type, category, severity_potential, description, observer_no)
  JOIN org_units ou ON ou.code = v.unit_code
   AND ou.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
  JOIN employees e ON e.employee_no = v.observer_no
 WHERE NOT EXISTS (
   SELECT 1 FROM safety_observations so WHERE so.org_unit_id = ou.id AND so.description = v.description
 );

-- -----------------------------------------------------------------------------
-- KPI targets — so the board judges the eight maintenance KPIs it can read,
-- rather than reporting "no target" for every one. (The registry maps only
-- those eight; the other pillars' definitions have no view mapping and stay
-- no_data regardless of what is seeded.)
-- -----------------------------------------------------------------------------
INSERT INTO kpi_targets
  (kpi_definition_id, org_unit_id, period_type, target_value, lower_threshold, upper_threshold, effective_from)
SELECT kd.id, ou.id, 'month', v.target_value, v.lower_threshold, v.upper_threshold, DATE '2025-01-01'
  FROM (VALUES
    ('MNT_PM_COMPLIANCE',       95,   90,   NULL),
    ('MNT_SCHEDULE_COMPLIANCE', 90,   80,   NULL),
    ('MNT_MTBF',                200,  100,  NULL),
    ('MNT_MTTR',                4,    NULL, 8),
    ('MNT_PLANNED_RATIO',       80,   70,   NULL),
    ('MNT_BACKLOG',             40,   NULL, 80),
    ('MNT_COST',                5000, NULL, 10000),
    ('MNT_PARTS_COST',          2000, NULL, 5000)
  ) AS v(kpi_code, target_value, lower_threshold, upper_threshold)
  JOIN kpi_definitions kd ON kd.code = v.kpi_code
  JOIN org_units ou ON ou.code IN ('A1', 'PKG')
   AND ou.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
 WHERE NOT EXISTS (
   SELECT 1 FROM kpi_targets kt
    WHERE kt.kpi_definition_id = kd.id AND kt.org_unit_id = ou.id AND kt.period_type = 'month'
 );

-- -----------------------------------------------------------------------------
-- Actions — the action log, seeded with one row per shape a reviewer needs to
-- see, because an empty register reads as a broken Screen rather than as a
-- module waiting for data.
--
--   0001  a concern at the packing line, closed on proof: a containment done, a
--         countermeasure done, and two turns of the circle — the first Check
--         found the fix had not held, which is what sent it round again.
--   0002  a concern mid-cycle: Plan done, Do open, its containment closed and
--         its countermeasure still in its own Do phase.
--   0003  an overdue concern with nobody named on it — the register's first row
--         when it orders worst-first, and its "Nobody yet" rendering.
--   0004  a concern handed up to the area above it: the two escalation columns
--         are both set (`action_items_escalation_consistent`), which is what the
--         manager's own queue filter has to find.
--   0005  a standalone containment with no concern behind it, sitting in its
--         Check — a measure that answers nothing, which the Module allows.
--
-- Every row is keyed by a `DEMO-AC-…` action number, every child by a NOT EXISTS
-- on its parent's number, and `next_document_number()` is never called: a re-run
-- leaves every count unchanged and `document_sequences` untouched, which is the
-- contract this file's header states for the work order and PM sections too.
--
-- Nothing here is a state the API would refuse: 0001 has a countermeasure that
-- is done and no measure still open, which is exactly what #179 requires before
-- a concern's Act may be completed. A seed that could only exist by bypassing
-- the Module's own rules would teach the wrong shape.
--
-- Dates are relative to CURRENT_DATE and now(), so the demo still reads as a
-- live register a month from now, and the phase completions spread backwards
-- over days so the rail reads as work in time rather than as rows written in one
-- second. `owner_employee_id` and `raised_by` are resolved by `employee_no` from
-- the Employees section above; 0003 deliberately has neither.
-- `created_by`/`updated_by` are left null as every other section leaves them: no
-- request context means no actor, which is the honest answer rather than a guess.
-- -----------------------------------------------------------------------------
INSERT INTO action_items
  (action_no, org_unit_id, title, description, action_type, pillar_code, priority,
   status, due_date, owner_employee_id, raised_by, raised_at, completed_at,
   closure_note, escalated_to_org_unit_id, escalated_at)
SELECT v.action_no,
       ou.id,
       v.title,
       v.description,
       v.action_type,
       v.pillar_code,
       v.priority,
       v.status,
       CASE WHEN v.due_in_days IS NULL THEN NULL ELSE CURRENT_DATE + v.due_in_days END,
       owner.id,
       raiser.id,
       now() - (v.raised_days_ago || ' days')::interval,
       CASE WHEN v.completed_days_ago IS NULL THEN NULL
            ELSE now() - (v.completed_days_ago || ' days')::interval END,
       v.closure_note,
       escalated.id,
       CASE WHEN escalated.id IS NULL THEN NULL
            ELSE now() - (v.escalated_days_ago || ' days')::interval END
  FROM (VALUES
    ('DEMO-AC-0001', 'PKG-L1', 'Cases jamming on the pallet wrapper',
     'The infeed guide shifts under load and the cases catch on it. Two shifts in a row lost '
     'about twenty minutes each to clearing it.',
     'concern', 'Q', 2, 'done', -2, 'DEMO-004', 'DEMO-004', 16, 1,
     'Guide refitted to the revised setting and the setting is on the line board.',
     NULL, NULL),
    ('DEMO-AC-0002', 'A1-L1', 'Guard on the infeed works loose every shift',
     'The guard on the infeed end works loose during a shift and has to be tightened by hand.',
     'concern', 'S', 2, 'in_progress', 2, 'DEMO-001', 'DEMO-001', 6, NULL, NULL, NULL, NULL),
    ('DEMO-AC-0003', 'A1-L1', 'Pallet stack height varies between shifts',
     'Stacks come out between eight and eleven high with no standard written down, and the '
     'taller ones lean.',
     'concern', 'D', 4, 'open', -9, NULL, 'DEMO-005', 11, NULL, NULL, NULL, NULL),
    ('DEMO-AC-0004', 'A1-L1', 'Night shift has no trained wrapper operator',
     'Nobody on nights is signed off on the wrapper, so a jam waits until the day shift arrives.',
     'concern', 'P', 3, 'in_progress', 5, 'DEMO-003', 'DEMO-003', 5, NULL, NULL, 'A1', 2),
    ('DEMO-AC-0005', 'A1-L1-C1', 'Manual guide check added to the shift checklist',
     'A five-second look at the guide before each shift, added to the operator checklist.',
     'containment', 'S', 2, 'in_progress', 1, 'DEMO-005', 'DEMO-002', 8, NULL, NULL, NULL, NULL)
  ) AS v(action_no, org_unit_code, title, description, action_type, pillar_code, priority,
         status, due_in_days, owner_no, raised_by_no, raised_days_ago, completed_days_ago,
         closure_note, escalated_to_code, escalated_days_ago)
  JOIN org_units ou
    ON ou.code = v.org_unit_code
   AND ou.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
  LEFT JOIN employees owner  ON owner.employee_no = v.owner_no
  LEFT JOIN employees raiser ON raiser.employee_no = v.raised_by_no
  LEFT JOIN org_units escalated
    ON escalated.code = v.escalated_to_code
   AND escalated.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
ON CONFLICT (action_no) DO NOTHING;

-- The measures the two answered concerns carry. A measure is an Action of its
-- own with its own cycle and its own owner, which is the whole point of the
-- containment/countermeasure split: 0001 has both, 0002 has both with the
-- countermeasure still being worked, and none of the other three has one.
INSERT INTO action_items
  (action_no, org_unit_id, title, description, action_type, pillar_code, priority, status,
   due_date, owner_employee_id, raised_by, raised_at, completed_at, closure_note,
   parent_action_item_id)
SELECT v.action_no,
       ou.id,
       v.title,
       v.description,
       v.action_type,
       v.pillar_code,
       v.priority,
       v.status,
       CASE WHEN v.due_in_days IS NULL THEN NULL ELSE CURRENT_DATE + v.due_in_days END,
       owner.id,
       raiser.id,
       now() - (v.raised_days_ago || ' days')::interval,
       CASE WHEN v.completed_days_ago IS NULL THEN NULL
            ELSE now() - (v.completed_days_ago || ' days')::interval END,
       v.closure_note,
       parent.id
  FROM (VALUES
    ('DEMO-AC-0001-A', 'DEMO-AC-0001', 'PKG-L1', 'Run the wrapper at 80% and check the guide each shift',
     'Holds the rate down until the guide is refitted, and catches a shift in the act of moving.',
     'containment', 'Q', 2, 'done', -3, 'DEMO-004', 'DEMO-004', 15, 12,
     'Ran for three shifts without a jam.'),
    ('DEMO-AC-0001-B', 'DEMO-AC-0001', 'PKG-L1', 'Refit the infeed guide to the revised setting',
     'The guide is re-seated, torqued to the revised figure and the setting written on the line '
     'board so the next shift does not move it back.',
     'countermeasure', 'Q', 2, 'done', 0, 'DEMO-004', 'DEMO-004', 13, 2,
     'Standard setting recorded on the line board.'),
    ('DEMO-AC-0002-A', 'DEMO-AC-0002', 'A1-L1', 'Clamp the guard and check it every shift',
     'A temporary clamp holds the guard while the mounting is re-worked.',
     'containment', 'S', 2, 'done', -1, 'DEMO-001', 'DEMO-001', 5, 3,
     'Held for three shifts, so the hazard is contained but not removed.'),
    ('DEMO-AC-0002-B', 'DEMO-AC-0002', 'A1-L1', 'Re-tap the mounting holes and fit the revised bolt',
     'The two mounting holes are re-tapped and the longer bolt from the revised drawing is fitted.',
     'countermeasure', 'S', 2, 'in_progress', 3, 'DEMO-002', 'DEMO-001', 4, NULL, NULL)
  ) AS v(action_no, parent_no, org_unit_code, title, description, action_type, pillar_code,
         priority, status, due_in_days, owner_no, raised_by_no, raised_days_ago,
         completed_days_ago, closure_note)
  JOIN action_items parent ON parent.action_no = v.parent_no
  JOIN org_units ou
    ON ou.code = v.org_unit_code
   AND ou.site_id = (SELECT id FROM sites WHERE code = 'DEMO')
  LEFT JOIN employees owner  ON owner.employee_no = v.owner_no
  LEFT JOIN employees raiser ON raiser.employee_no = v.raised_by_no
ON CONFLICT (action_no) DO NOTHING;

-- The turns of the circle, one row per phase per cycle. 0001 carries two cycles
-- because its first Check found the countermeasure had not held — a failed Check
-- opens the NEXT cycle's Plan rather than closing anything, which is the reason
-- `action_phases` is a table and not a status column.
--
-- A Check is the only phase with an `outcome` (`action_phases_outcome_only_on_check`),
-- and an outcome without a completion is refused
-- (`action_phases_outcome_needs_completion`), so an open Check here carries
-- neither. One phase is open per Action at most — the invariant the service
-- keeps, and the read the register's own "waiting on" column makes.
INSERT INTO action_phases
  (action_item_id, cycle, phase, owner_employee_id, due_date, completed_at, outcome, note)
SELECT ai.id,
       v.cycle,
       v.phase,
       owner.id,
       CASE WHEN v.due_in_days IS NULL THEN NULL ELSE CURRENT_DATE + v.due_in_days END,
       CASE WHEN v.done_days_ago IS NULL THEN NULL
            ELSE now() - (v.done_days_ago || ' days')::interval END,
       v.outcome,
       v.note
  FROM (VALUES
    -- 0001, the concern: a first cycle that failed its Check, and a second that held.
    ('DEMO-AC-0001', 1, 'plan',  'DEMO-004', -14, -15, NULL, 'Check the guide seating and measure the shift''s lost time.'),
    ('DEMO-AC-0001', 1, 'do',    'DEMO-004', -12, -14, NULL, 'Guide checked each shift for a week.'),
    ('DEMO-AC-0001', 1, 'check', 'DEMO-004', -11, -12, 'not_effective', 'Jam came back on the night shift, so the guide was still moving.'),
    ('DEMO-AC-0001', 2, 'plan',  'DEMO-004', -10, -11, NULL, 'Re-seat the guide, not just check it, and write the setting down.'),
    ('DEMO-AC-0001', 2, 'do',    'DEMO-004', -4,  -9,  NULL, 'Guide re-seated and torqued to the revised figure.'),
    ('DEMO-AC-0001', 2, 'check', 'DEMO-004', -2,  -3,  'effective', 'A week of shifts without a jam, at full rate.'),
    ('DEMO-AC-0001', 2, 'act',   'DEMO-004', -1,  -1,  NULL, 'Setting added to the line board and the checklist.'),
    -- 0001-A, the containment: closed on its own evidence.
    ('DEMO-AC-0001-A', 1, 'plan',  'DEMO-004', -14, -15, NULL, 'Hold the rate down and watch the guide.'),
    ('DEMO-AC-0001-A', 1, 'do',    'DEMO-004', -13, -14, NULL, 'Ran at 80% with a per-shift check.'),
    ('DEMO-AC-0001-A', 1, 'check', 'DEMO-004', -12, -12, 'effective', 'No jam over three shifts, so the rate cap holds.'),
    ('DEMO-AC-0001-A', 1, 'act',   'DEMO-004', -12, -12, NULL, 'Kept in place until the guide was refitted.'),
    -- 0001-B, the countermeasure.
    ('DEMO-AC-0001-B', 1, 'plan',  'DEMO-004', -10, -11, NULL, 'Re-seat the guide and record the setting.'),
    ('DEMO-AC-0001-B', 1, 'do',    'DEMO-004', -4,  -9,  NULL, 'Guide refitted and torqued.'),
    ('DEMO-AC-0001-B', 1, 'check', 'DEMO-004', -2,  -3,  'effective', 'A week at full rate with no jam.'),
    ('DEMO-AC-0001-B', 1, 'act',   'DEMO-004', -2,  -2,  NULL, 'Setting recorded on the line board.'),
    -- 0002, the concern mid-cycle: Plan done, Do open.
    ('DEMO-AC-0002', 1, 'plan', 'DEMO-001', 2, -6, NULL, 'Clamp it for now and re-work the mounting.'),
    ('DEMO-AC-0002', 1, 'do',   'DEMO-001', 2, NULL, NULL, NULL),
    -- 0002-A, the containment: done.
    ('DEMO-AC-0002-A', 1, 'plan',  'DEMO-001', -1, -5, NULL, 'Clamp it and check the clamp each shift.'),
    ('DEMO-AC-0002-A', 1, 'do',    'DEMO-001', -1, -4, NULL, 'Clamp fitted and checked each shift.'),
    ('DEMO-AC-0002-A', 1, 'check', 'DEMO-001', -1, -3, 'effective', 'Held for three shifts with no movement.'),
    ('DEMO-AC-0002-A', 1, 'act',   'DEMO-001', -1, -3, NULL, 'Clamp stays until the bolt is fitted.'),
    -- 0002-B, the countermeasure: in its Do phase.
    ('DEMO-AC-0002-B', 1, 'plan', 'DEMO-002', 3, -4, NULL, 'Re-tap both holes and fit the longer bolt.'),
    ('DEMO-AC-0002-B', 1, 'do',   'DEMO-002', 3, NULL, NULL, NULL),
    -- 0003, the overdue concern: nobody has planned it yet.
    ('DEMO-AC-0003', 1, 'plan', 'DEMO-005', -9, NULL, NULL, NULL),
    -- 0004, the escalated concern: underway, and the area has been told.
    ('DEMO-AC-0004', 1, 'plan', 'DEMO-003', 5, -4, NULL, 'Sign two night operators off on the wrapper.'),
    ('DEMO-AC-0004', 1, 'do',   'DEMO-003', 5, NULL, NULL, NULL),
    -- 0005, the standalone containment: waiting on its Check.
    ('DEMO-AC-0005', 1, 'plan',  'DEMO-005', 1, -8, NULL, 'Add the guide to the operator checklist.'),
    ('DEMO-AC-0005', 1, 'do',    'DEMO-005', 1, -6, NULL, 'Checklist updated and laminated at the station.'),
    ('DEMO-AC-0005', 1, 'check', 'DEMO-005', 1, NULL, NULL, NULL)
  ) AS v(action_no, cycle, phase, owner_no, due_in_days, done_days_ago, outcome, note)
  JOIN action_items ai ON ai.action_no = v.action_no
  LEFT JOIN employees owner ON owner.employee_no = v.owner_no
ON CONFLICT ON CONSTRAINT action_phases_unique DO NOTHING;

COMMIT;
