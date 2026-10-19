/*
 * Nothing ever removed an expired Account session or technician identification:
 * both tables only grew, and every sign-in and every floor burst added a row.
 * An expired row is already refused by the code that reads it, so deleting it
 * changes no behaviour, it only stops the tables growing without bound.
 *
 * The nightly `sqdcp_maintenance()` is the existing single entry point for
 * scheduled housekeeping (the baseline's own header says new work belongs
 * there rather than in a cron entry), so the purge joins it. The function is
 * replaced whole with the baseline's body plus the two deletes, and its result
 * text gains the purge counts. Forward-only and safe for the previous version
 * to keep running against: the function's signature and return type are
 * unchanged.
 *
 * Revoked sessions are kept until they also expire, so a revoked token still
 * reads as revoked rather than as unknown for as long as it could have been
 * presented.
 */

exports.up = (pgm) => {
  pgm.sql(`
    CREATE OR REPLACE FUNCTION sqdcp_maintenance()
    RETURNS TEXT
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_measurements    INTEGER;
      v_audit           INTEGER;
      v_sessions        INTEGER;
      v_identifications INTEGER;
    BEGIN
      v_measurements := ensure_time_partitions(
        'measurements',
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '3 months')::date
      );

      v_audit := ensure_time_partitions(
        'audit_log',
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '3 months')::date
      );

      PERFORM refresh_sqdcp_rollups();

      DELETE FROM account_sessions WHERE expires_at < now();
      GET DIAGNOSTICS v_sessions = ROW_COUNT;

      DELETE FROM technician_identifications WHERE expires_at < now();
      GET DIAGNOSTICS v_identifications = ROW_COUNT;

      RETURN format(
        'partitions created: measurements=%s audit_log=%s; rollups refreshed; purged: account_sessions=%s technician_identifications=%s',
        v_measurements, v_audit, v_sessions, v_identifications
      );
    END;
    $$
  `);
};
