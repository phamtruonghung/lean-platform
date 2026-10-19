/**
 * "Today" is the Site's local date, not the database's UTC date (ADR-0048).
 *
 * `CURRENT_DATE` is the session's date, and nothing in this Platform sets a
 * session timezone, so it was UTC everywhere. A Site at UTC+7 is already on
 * tomorrow's date from 17:00 UTC; an Action due "today" there read as not yet
 * late for seven hours of every local day, and a PM came due seven hours late.
 *
 * Two functions, built on the baseline's own `plant_date` (the Site's calendar
 * date for an instant, resolved through the Org Unit):
 *
 *   org_unit_today(org_unit_id)  the local date at the Org Unit's Site
 *   employee_today(employee_id)  the local date at the Site of the Employee's
 *                                default Org Unit; UTC when they have none
 *
 * Both fall back to the UTC date when no Site can be resolved, which is what
 * the old CURRENT_DATE did, so nothing changes for a row without a Site.
 *
 * The four views that read CURRENT_DATE are replaced with the same columns.
 * Backward-compatible per ADR-0007: only function additions and view bodies.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE OR REPLACE FUNCTION org_unit_today(p_org_unit_id BIGINT)
    RETURNS DATE
    LANGUAGE sql
    STABLE
    AS $$
      SELECT COALESCE(public.plant_date(p_org_unit_id, now()),
                      (now() AT TIME ZONE 'UTC')::date);
    $$
  `);
  pgm.sql(`
    CREATE OR REPLACE FUNCTION employee_today(p_employee_id BIGINT)
    RETURNS DATE
    LANGUAGE sql
    STABLE
    AS $$
      SELECT COALESCE(
        (SELECT public.plant_date(e.default_org_unit_id, now())
           FROM public.employees e
          WHERE e.id = p_employee_id),
        (now() AT TIME ZONE 'UTC')::date);
    $$
  `);

  // The deny-all floor (rls.test.js): no routine in public is executable by
  // PUBLIC. The application's own role owns these, so it still can.
  pgm.sql('REVOKE EXECUTE ON FUNCTION org_unit_today(BIGINT) FROM PUBLIC');
  pgm.sql('REVOKE EXECUTE ON FUNCTION employee_today(BIGINT) FROM PUBLIC');

  pgm.sql(`
    CREATE OR REPLACE VIEW v_skill_coverage AS
    SELECT
      sr.org_unit_id,
      sr.skill_id,
      sk.code                              AS skill_code,
      sk.name                              AS skill_name,
      sr.minimum_level,
      sr.minimum_qualified_headcount,
      COUNT(es.id) FILTER (
        WHERE es.proficiency_level >= sr.minimum_level
          AND (es.expires_on IS NULL OR es.expires_on > employee_today(es.employee_id))
      )                                    AS qualified_headcount,
      COUNT(es.id) FILTER (
        WHERE es.proficiency_level >= sr.minimum_level
          AND es.expires_on IS NOT NULL
          AND es.expires_on <= employee_today(es.employee_id)
      )                                    AS expired_headcount,
      GREATEST(
        sr.minimum_qualified_headcount - COUNT(es.id) FILTER (
          WHERE es.proficiency_level >= sr.minimum_level
            AND (es.expires_on IS NULL OR es.expires_on > employee_today(es.employee_id))
        ), 0
      )                                    AS shortfall
    FROM skill_requirements sr
    JOIN skills sk ON sk.id = sr.skill_id
    JOIN org_units req ON req.id = sr.org_unit_id
    LEFT JOIN employees e
      ON e.is_active
     AND EXISTS (
           SELECT 1
             FROM employee_assignments ea
             JOIN org_units eau ON eau.id = ea.org_unit_id
            WHERE ea.employee_id = e.id
              AND eau.path <@ req.path
              AND ea.effective_from <= employee_today(ea.employee_id)
              AND (ea.effective_to IS NULL OR ea.effective_to > employee_today(ea.employee_id))
         )
    LEFT JOIN employee_skills es ON es.employee_id = e.id AND es.skill_id = sr.skill_id
    GROUP BY sr.org_unit_id, sr.skill_id, sk.code, sk.name,
             sr.minimum_level, sr.minimum_qualified_headcount
  `);

  pgm.sql(`
    CREATE OR REPLACE VIEW v_open_actions AS
    SELECT
      ai.id,
      ai.action_no,
      ai.title,
      ai.pillar_code,
      ai.source_type,
      ai.org_unit_id,
      ou.code                   AS org_unit_code,
      ou.path                   AS org_unit_path,
      ai.action_type,
      ai.priority,
      ai.status,
      ai.due_date,
      (ai.due_date IS NOT NULL AND ai.due_date < org_unit_today(ai.org_unit_id)) AS is_overdue,
      org_unit_today(ai.org_unit_id) - ai.due_date AS days_overdue,
      ai.owner_employee_id,
      e.display_name            AS owner_name,
      ai.raised_at,
      ai.escalated_to_org_unit_id
    FROM action_items ai
    JOIN org_units ou ON ou.id = ai.org_unit_id
    LEFT JOIN employees e ON e.id = ai.owner_employee_id
    WHERE ai.status IN ('open', 'in_progress', 'blocked')
  `);

  pgm.sql(`
    CREATE OR REPLACE VIEW v_pm_due AS
    WITH latest_reading AS (
      SELECT DISTINCT ON (mr.asset_meter_id)
             mr.asset_meter_id, mr.reading, mr.read_at
      FROM meter_readings mr
      ORDER BY mr.asset_meter_id, mr.read_at DESC
    )
    SELECT s.id AS pm_schedule_id, s.code, s.name, s.asset_id, a.org_unit_id, s.job_plan_id,
           s.next_due_on, s.next_due_meter, lr.reading AS current_meter,
           COALESCE(s.next_due_on IS NOT NULL AND s.next_due_on <= org_unit_today(a.org_unit_id), false)
             AS due_by_date,
           COALESCE(s.next_due_meter IS NOT NULL AND lr.reading >= s.next_due_meter, false)
             AS due_by_meter,
           COALESCE(s.next_due_on IS NOT NULL
                    AND s.next_due_on - s.lead_time_days <= org_unit_today(a.org_unit_id), false)
             AS within_lead_time,
           s.next_due_on - org_unit_today(a.org_unit_id) AS days_until_due
    FROM pm_schedules s
    JOIN assets a ON a.id = s.asset_id
    LEFT JOIN latest_reading lr ON lr.asset_meter_id = s.asset_meter_id
    WHERE s.is_active
  `);

  pgm.sql(`
    CREATE OR REPLACE VIEW v_pm_compliance AS
    WITH pm AS (
      SELECT wo.org_unit_id,
             wo.status,
             wo.actual_end,
             COALESCE(wo.due_date, plant_date(wo.org_unit_id, wo.actual_end)) AS due_on
      FROM work_orders wo
      WHERE wo.pm_schedule_id IS NOT NULL
        AND wo.status <> 'cancelled'
    )
    SELECT org_unit_id,
           date_trunc('month', due_on)::date AS period_start,
           COUNT(*)                                                    AS pm_due,
           COUNT(*) FILTER (WHERE status IN ('completed', 'closed'))   AS pm_completed,
           COUNT(*) FILTER (
             WHERE status IN ('completed', 'closed')
               AND plant_date(org_unit_id, actual_end) <= due_on
           )                                                           AS pm_on_time,
           ROUND(
             100.0 * COUNT(*) FILTER (
               WHERE status IN ('completed', 'closed')
                 AND plant_date(org_unit_id, actual_end) <= due_on
             ) / NULLIF(COUNT(*), 0), 2
           )                                                           AS compliance_pct
    FROM pm
    WHERE due_on IS NOT NULL
      AND due_on <= org_unit_today(org_unit_id)
    GROUP BY org_unit_id, date_trunc('month', due_on)::date
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 - this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions. The views keep their new bodies, which only
  // need the functions to exist, so the down migration leaves both in place.
  pgm.sql('SELECT 1');
};
