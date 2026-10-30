-- A MIRROR of the MTU KPI catalogue's schema, for the integration test only.
--
-- The source of truth is phamtruonghung/data-analysis, relats/kpi/sql/
-- 0001_kpi_schema.sql and 0002_kpi_review.sql, deployed to CT100 by
-- relats/kpi/setup_kpi_ct100.sh as the role etl_kpi. What follows is those two
-- files verbatim, 0001 then 0002, same statements and same seed (the DO $$ grant
-- blocks included: they are guarded on the roles existing, so on a dev database
-- they are no-ops). A change there must be carried here in the same breath; the
-- two must not drift, or the test proves the Module against a schema nobody runs.
--
-- Why it exists at all: the Platform's own dev database does not have schema
-- `kpi`. In production it is another database on another host (ADR-0055), so
-- test/integration/kpi.test.js stands the schema up locally, in the Platform's
-- own database, and points MTU_DATABASE_URL at it.
--
-- It is NOT a migration and must never be run by `npm run migrate`: it lives
-- under test/ so that migrations/ stays the only thing a deploy applies
-- (ADR-0007), and the Platform's database must not own a copy of this schema.

-- 0001_kpi_schema.sql: schema kpi, the KPI Catalogue and its Targets (ADR 0015). Shared by Power BI (dim_KPI, dim_KPITarget of
-- Scrap Model.pbix) and the Lean Platform, so both read one list of KPIs and one Target history.
-- Idempotent: setup_kpi_ct100.sh applies it on every run as role etl_kpi (owner of schema kpi). Additive only: nothing here touches
-- schemas sap, public or perf. Seed rows never overwrite a row that already exists (same rule as sap.dim_wc).
--
-- Vocabulary:
--   KPI     one tracked indicator (kpi_id 1..n). Its VALUE is computed elsewhere (Power BI measure named in value_measure); this schema
--           holds only what the KPI is: name, title, unit, direction of "met", decimals shown.
--   Grain   the period a Target applies to: 'Daily', 'Weekly' (ISO week) or 'Monthly'. Exactly the text Power BI's [KPI Grain] returns.
--   Target  a threshold for one KPI x Grain, in force from valid_from until the next valid_from of the same KPI x Grain.
--           A period is judged against the Target in force on its LAST day (Power BI [KPI Target]).
--
-- Targets are APPEND-ONLY: a change of target is a new row with a new valid_from, so past periods keep the target they had.
-- A typo is corrected by inserting another row with the SAME kpi_id x grain x valid_from: the latest entered_at wins
-- (v_dim_kpi_target), the wrong row stays in the history (v_target_history). target NULL = "no target from valid_from on".
-- UPDATE and DELETE on kpi.kpi_target are refused by a trigger, for every role (the owner can ALTER TABLE ... DISABLE TRIGGER
-- for a deliberate repair, which is then visible in the DDL history, not silent).

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'kpi') THEN CREATE SCHEMA kpi; END IF;
END $$;

-- ---------------------------------------------------------------- KPI catalogue
CREATE TABLE IF NOT EXISTS kpi.kpi (
    kpi_id integer PRIMARY KEY CHECK (kpi_id > 0),
    kpi text NOT NULL UNIQUE,                       -- short name, the slicer value in Power BI (dim_KPI[KPI])
    title text NOT NULL,                            -- chart title, with the unit in brackets
    unit text NOT NULL DEFAULT '',                  -- suffix printed right after the number, leading space included: '%', ' min', ' h'
    direction text NOT NULL CHECK (direction IN ('<=', '<', '>=', '>')),   -- the side of the Target that counts as met
    decimals integer NOT NULL CHECK (decimals BETWEEN 0 AND 6),            -- the value is rounded to this before it is compared
    value_measure text,                             -- documentation only: the Power BI measure behind the value
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE kpi.kpi IS 'KPI Catalogue (ADR 0015): one row per KPI. Targets in kpi.kpi_target. Power BI: dim_KPI via kpi.v_dim_kpi.';

-- ---------------------------------------------------------------- Targets (append-only)
CREATE TABLE IF NOT EXISTS kpi.kpi_target (
    target_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kpi_id integer NOT NULL REFERENCES kpi.kpi (kpi_id),
    grain text NOT NULL CHECK (grain IN ('Daily', 'Weekly', 'Monthly')),
    valid_from date NOT NULL,                       -- plant date (Asia/Ho_Chi_Minh) the Target applies from
    target numeric,                                 -- NULL = no target from valid_from on (the chart shows grey bars)
    note text,                                      -- why the target changed
    app_user text,                                  -- who asked for it in the Lean Platform (the app logs in as one role)
    entered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    entered_by text NOT NULL DEFAULT session_user   -- database login; lean_app cannot set it (column-level INSERT grant)
);
CREATE INDEX IF NOT EXISTS kpi_target_lookup ON kpi.kpi_target (kpi_id, grain, valid_from, entered_at DESC, target_id DESC);
COMMENT ON TABLE kpi.kpi_target IS 'Targets per KPI x Grain x valid_from, append-only (ADR 0015). Latest entered_at per KPI x Grain x valid_from wins.';

CREATE OR REPLACE FUNCTION kpi.refuse_target_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'kpi.kpi_target is append-only: insert a new row (same kpi_id, grain, valid_from to correct one; a new valid_from to change the target)';
END $$;
DROP TRIGGER IF EXISTS kpi_target_append_only ON kpi.kpi_target;
CREATE TRIGGER kpi_target_append_only BEFORE UPDATE OR DELETE ON kpi.kpi_target
    FOR EACH ROW EXECUTE FUNCTION kpi.refuse_target_change();
DROP TRIGGER IF EXISTS kpi_target_no_truncate ON kpi.kpi_target;
CREATE TRIGGER kpi_target_no_truncate BEFORE TRUNCATE ON kpi.kpi_target
    FOR EACH STATEMENT EXECUTE FUNCTION kpi.refuse_target_change();

-- ---------------------------------------------------------------- views
-- Power BI dim_KPI: the column names and types of the former DATATABLE (KPI ID and Decimals Int64).
CREATE OR REPLACE VIEW kpi.v_dim_kpi AS
SELECT kpi_id::bigint AS "KPI ID", kpi AS "KPI", title AS "Title", unit AS "Unit", direction AS "Direction",
       decimals::bigint AS "Decimals", value_measure AS "Value Measure"
FROM kpi.kpi;

-- Power BI dim_KPITarget: one row per KPI x Grain x valid_from, the latest entry of each (corrections replace, history stays in the table).
CREATE OR REPLACE VIEW kpi.v_dim_kpi_target AS
SELECT DISTINCT ON (kpi_id, grain, valid_from)
       kpi_id::bigint AS "KPI ID", grain AS "Grain", valid_from AS "Valid From", target::double precision AS "Target"
FROM kpi.kpi_target
ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC;

-- Every entry ever made, with whether it is still the effective one for its KPI x Grain x valid_from.
CREATE OR REPLACE VIEW kpi.v_target_history AS
SELECT t.target_id, t.kpi_id, k.kpi, t.grain, t.valid_from, t.target, t.note, t.app_user, t.entered_at, t.entered_by,
       row_number() OVER (PARTITION BY t.kpi_id, t.grain, t.valid_from ORDER BY t.entered_at DESC, t.target_id DESC) = 1 AS is_effective
FROM kpi.kpi_target t
JOIN kpi.kpi k USING (kpi_id);

-- The Target in force today (plant date) per KPI x Grain, with the KPI attributes: what the Lean Platform shows next to a KPI.
-- A KPI x Grain with no row, or whose latest row has target NULL, has no target.
CREATE OR REPLACE VIEW kpi.v_target_current AS
WITH eff AS (
    SELECT DISTINCT ON (kpi_id, grain, valid_from) kpi_id, grain, valid_from, target
    FROM kpi.kpi_target
    ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC
), cur AS (
    SELECT DISTINCT ON (kpi_id, grain) kpi_id, grain, valid_from, target
    FROM eff
    WHERE valid_from <= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
    ORDER BY kpi_id, grain, valid_from DESC
)
SELECT k.kpi_id, k.kpi, k.title, k.unit, k.direction, k.decimals, g.grain, c.valid_from, c.target
FROM kpi.kpi k
CROSS JOIN (VALUES ('Daily'), ('Weekly'), ('Monthly')) AS g (grain)
LEFT JOIN cur c ON c.kpi_id = k.kpi_id AND c.grain = g.grain;

-- ---------------------------------------------------------------- seed (copied from Scrap Model.pbix on 2026-10-29, Model Change Log (42)-(59))
INSERT INTO kpi.kpi (kpi_id, kpi, title, unit, direction, decimals, value_measure) VALUES
    (1, 'Scrap Ratio MTU', 'Scrap Ratio MTU (%)', '%', '<=', 2, '[Scrap Ratio (%)], Process = MTU'),
    (2, 'Scrap Ratio RS-FS-UR', 'Scrap Ratio RS-FS-UR (%)', '%', '<=', 2, '[Scrap Ratio (%)], Process = RS, FS, UR'),
    (3, 'Scrap Ratio Total', 'Scrap Ratio Total (%)', '%', '<=', 2, '[Scrap Ratio (%)], mọi công đoạn'),
    (4, 'Availability', 'Availability (%)', '%', '>=', 1, '[Run Share (%)]'),
    (5, 'MTTR Maintenance', 'MTTR Maintenance (min)', ' min', '<', 1, '[MTTR Maintenance (min)]'),
    (6, 'MTBF Maintenance', 'MTBF Maintenance (h)', ' h', '>', 2, '[MTBF Maintenance (h)]'),
    (7, 'Capacity vs Baseline', 'Capacity vs Baseline (%)', '%', '>=', 0, '[Capacity vs Baseline (%)]'),
    (8, 'Waste Gap', 'Waste Gap (%)', '%', '<=', 0, '[SC Waste Gap Ratio (%)], Loại rác = Ống dây SC, Ống dây SC (Cutting + EM)'),
    (9, 'Planned Hours per Shift', 'Planned Hours per Shift (h)', ' h', '>=', 2, '[Avg Planned Hours per Shift (h)]'),
    (10, 'No-Plan Machines per Shift', 'No-Plan Machines per Shift', ' machines', '<=', 1, '[No-Plan Machines per Shift (#)]'),
    (11, 'MTU Output (m/day)', 'MTU Output (m / production day)', ' m', '>=', 0, '[MTU Output per Day (m)]'),
    (12, 'MTU Output (kg/day)', 'MTU Output (kg / production day)', ' kg', '>=', 0, '[MTU Output per Day (kg)]'),
    (13, 'MTU Declarers per Shift', 'MTU Declarers per Shift', ' people', '>=', 1, '[MTU Declarers per Shift (#)]'),
    (14, 'Utilization', 'Utilization (% of available hours)', '%', '>=', 1, '[Utilization (%)]'),
    (15, 'No-Plan', 'No-Plan (% of available hours)', '%', '<=', 1, '[No-Plan (%)]'),
    (16, 'Total Loss', 'Total Loss (% of available hours)', '%', '<=', 1, '[Total Loss (%)]'),
    (17, 'Production Loss', 'Production Loss (% of available hours)', '%', '<=', 1, '[Production Loss (%)]'),
    (18, 'Maintenance Loss', 'Maintenance Loss (% of available hours)', '%', '<=', 1, '[Maintenance Loss (%)]'),
    (19, 'Other Loss', 'Other Loss (% of available hours)', '%', '<=', 1, '[Other Loss (%)]')
ON CONFLICT (kpi_id) DO NOTHING;

-- Targets: one per KPI for all three grains (user, 22/10/2026); KPI 3, 9, 10 have none. 11-19 = average 12/10-25/10/2026.
-- A seed row is inserted only when its KPI x Grain x valid_from has no entry at all, so a rerun never adds a second copy and
-- never overrides an entry made later in the Lean Platform.
INSERT INTO kpi.kpi_target (kpi_id, grain, valid_from, target, note)
SELECT s.kpi_id, g.grain, DATE '2020-01-01', s.target, 'seed from Scrap Model.pbix dim_KPITarget, 2026-10-29'
FROM (VALUES
    (1, 2.4), (2, 0.35), (4, 50), (5, 30), (6, 8), (7, 100), (8, 10),
    (11, 115624), (12, 2070), (13, 10.6), (14, 35.1), (15, 25.3), (16, 39.6), (17, 10.0), (18, 3.3), (19, 26.3)
) AS s (kpi_id, target)
CROSS JOIN (VALUES ('Daily'), ('Weekly'), ('Monthly')) AS g (grain)
WHERE NOT EXISTS (SELECT 1 FROM kpi.kpi_target t
                  WHERE t.kpi_id = s.kpi_id AND t.grain = g.grain AND t.valid_from = DATE '2020-01-01');

-- ---------------------------------------------------------------- grants (roles are created by setup_kpi_ct100.sh)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_ro') THEN
        GRANT USAGE ON SCHEMA kpi TO powerbi_ro;
        GRANT SELECT ON kpi.v_dim_kpi, kpi.v_dim_kpi_target, kpi.v_target_history, kpi.v_target_current TO powerbi_ro;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lean_app') THEN
        GRANT USAGE ON SCHEMA kpi TO lean_app;
        GRANT SELECT ON kpi.kpi, kpi.kpi_target, kpi.v_dim_kpi, kpi.v_dim_kpi_target, kpi.v_target_history, kpi.v_target_current
            TO lean_app;
        GRANT INSERT (kpi_id, grain, valid_from, target, note, app_user) ON kpi.kpi_target TO lean_app;
    END IF;
END $$;

-- 0002_kpi_review.sql: the daily KPI review and a KPI the Lean Platform can add (ADR 0016, amends ADR 0015).
-- Idempotent: setup_kpi_ct100.sh applies it on every run, after 0001, as role etl_kpi (owner of schema kpi). Additive only.
--
-- A review is a HUMAN JUDGEMENT of one KPI on one day: met / missed / not_measured, optionally the number the reviewer read off the
-- chart (observed), and a note that is mandatory when the day was missed. It does not compute the KPI value (that is still the Power BI
-- measure named in kpi.kpi.value_measure).
--
-- Reviews are APPEND-ONLY, same rule as kpi.kpi_target: a judgement is never edited. A correction is a new row with the SAME
-- kpi_id x review_date; the latest entered_at wins (v_kpi_review_current), the superseded row stays in the table.
-- UPDATE, DELETE and TRUNCATE are refused by a trigger, for every role (the owner can ALTER TABLE ... DISABLE TRIGGER for a deliberate
-- repair, which is then visible in the DDL history, not silent).

-- ---------------------------------------------------------------- kpi.kpi_id becomes an identity
-- The app adds a KPI without naming an id. GENERATED BY DEFAULT (not ALWAYS) on purpose: 0001 seeds explicit ids 1..19 with
-- ON CONFLICT (kpi_id) DO NOTHING, and that must keep working on every rerun.
-- The guard makes a rerun a no-op (attidentity = '' means the column is not an identity yet).
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_attribute
               WHERE attrelid = 'kpi.kpi'::regclass AND attname = 'kpi_id' AND attidentity = '') THEN
        ALTER TABLE kpi.kpi ALTER COLUMN kpi_id ADD GENERATED BY DEFAULT AS IDENTITY;
    END IF;
END $$;
-- Point the sequence at the existing maximum, so the next generated id is max + 1 (20 after the 19 seeded KPIs).
-- This runs on every apply, deliberately: 0002 runs after 0001, so if the owner seeds an explicit higher id, the rerun moves the
-- sequence past it and the app never collides with it.
SELECT setval(pg_get_serial_sequence('kpi.kpi', 'kpi_id'), (SELECT max(kpi_id) FROM kpi.kpi), true);

-- ---------------------------------------------------------------- the review (append-only)
CREATE TABLE IF NOT EXISTS kpi.kpi_review (
  review_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kpi_id      integer NOT NULL REFERENCES kpi.kpi (kpi_id),
  review_date date    NOT NULL,
  status      text    NOT NULL CHECK (status IN ('met','missed','not_measured')),
  observed    numeric(18,4),        -- what the reviewer read off the chart; NULL when they judged without a number
  note        text,                 -- why it was missed, or what was done about it
  app_user    text,                 -- the person, written by lean_app
  entered_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  entered_by  text NOT NULL DEFAULT session_user,
  CONSTRAINT kpi_review_miss_needs_note
    CHECK (status <> 'missed' OR (note IS NOT NULL AND length(btrim(note)) >= 10))
);
CREATE INDEX IF NOT EXISTS kpi_review_lookup ON kpi.kpi_review (kpi_id, review_date, entered_at DESC, review_id DESC);
CREATE INDEX IF NOT EXISTS kpi_review_date ON kpi.kpi_review (review_date);
COMMENT ON TABLE kpi.kpi_review IS 'Daily KPI review (ADR 0016): a human judgement (met / missed / not_measured) per KPI x review_date, append-only. A judgement is never edited: a correction is a new row with the same kpi_id x review_date and the latest entered_at wins (kpi.v_kpi_review_current); the superseded row stays in the table. A missed day needs a note of at least 10 characters.';

CREATE OR REPLACE FUNCTION kpi.refuse_review_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'kpi.kpi_review is append-only: insert a new row for the same kpi_id and review_date to correct a judgement (the latest entered_at wins)';
END $$;
DROP TRIGGER IF EXISTS kpi_review_append_only ON kpi.kpi_review;
CREATE TRIGGER kpi_review_append_only BEFORE UPDATE OR DELETE ON kpi.kpi_review
    FOR EACH ROW EXECUTE FUNCTION kpi.refuse_review_change();
DROP TRIGGER IF EXISTS kpi_review_no_truncate ON kpi.kpi_review;
CREATE TRIGGER kpi_review_no_truncate BEFORE TRUNCATE ON kpi.kpi_review
    FOR EACH STATEMENT EXECUTE FUNCTION kpi.refuse_review_change();

-- ---------------------------------------------------------------- views
-- The judgement that counts: the latest row per KPI x review_date, with the KPI's attributes next to it.
CREATE OR REPLACE VIEW kpi.v_kpi_review_current AS
SELECT DISTINCT ON (r.kpi_id, r.review_date)
       r.review_id, r.kpi_id, k.kpi, k.title, k.unit, k.direction, k.decimals, r.review_date,
       r.status, r.observed, r.note, r.app_user, r.entered_at, r.entered_by
FROM kpi.kpi_review r
JOIN kpi.kpi k USING (kpi_id)
ORDER BY r.kpi_id, r.review_date, r.entered_at DESC, r.review_id DESC;

-- "Why was it red": the days whose CURRENT judgement is missed, with the Daily Target in force on that day.
-- The missed filter is applied to the current rows (not inside the DISTINCT ON), so a missed day later corrected to met leaves the list.
-- The Target in force: the latest entry per KPI x grain x valid_from (as in 0001), then the greatest valid_from <= review_date.
-- No "target IS NOT NULL" filter: a latest row with target NULL means "no target from valid_from on", and must give NULL here,
-- not an older target.
CREATE OR REPLACE VIEW kpi.v_kpi_review_missed AS
WITH eff AS (
    SELECT DISTINCT ON (kpi_id, grain, valid_from) kpi_id, grain, valid_from, target
    FROM kpi.kpi_target
    ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC
)
SELECT c.kpi_id, c.title, c.review_date, t.target, c.observed, c.note, c.app_user, c.entered_at
FROM kpi.v_kpi_review_current c
LEFT JOIN LATERAL (
    SELECT e.target
    FROM eff e
    WHERE e.kpi_id = c.kpi_id AND e.grain = 'Daily' AND e.valid_from <= c.review_date
    ORDER BY e.valid_from DESC
    LIMIT 1
) t ON true
WHERE c.status = 'missed'
ORDER BY c.review_date DESC, c.kpi_id;

-- ---------------------------------------------------------------- grants (roles are created by setup_kpi_ct100.sh)
-- The INSERT column lists are narrow on purpose: entered_at / entered_by are written by the database (clock_timestamp(),
-- session_user) and the KPI id comes from the identity, so the app cannot forge who or when, nor renumber an existing KPI.
-- A GENERATED BY DEFAULT AS IDENTITY column needs no separate GRANT USAGE ON SEQUENCE for the insert.
-- No UPDATE / DELETE / TRUNCATE for lean_app anywhere; the 0001 grants are left as they are.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_ro') THEN
        GRANT USAGE ON SCHEMA kpi TO powerbi_ro;
        GRANT SELECT ON kpi.v_kpi_review_current, kpi.v_kpi_review_missed TO powerbi_ro;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lean_app') THEN
        GRANT USAGE ON SCHEMA kpi TO lean_app;
        GRANT SELECT ON kpi.v_kpi_review_current, kpi.v_kpi_review_missed TO lean_app;
        GRANT INSERT (kpi_id, review_date, status, observed, note, app_user) ON kpi.kpi_review TO lean_app;
        GRANT INSERT (kpi, title, unit, direction, decimals, value_measure) ON kpi.kpi TO lean_app;
    END IF;
END $$;
