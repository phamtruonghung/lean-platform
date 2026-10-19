---
status: accepted
---

# "Today" is the Site's local date, resolved in the database

Date: 2026-10-19

CONTEXT.md's Site entry says each Site keeps "its own shift pattern and its own
local time". The code did not: every "is it late yet" and "is it due yet"
question was asked with `CURRENT_DATE`, which is the database session's date.
Nothing in `platform/db.js` or any migration sets a session timezone, so that
date was UTC for every Site. A Site at UTC+7 is on tomorrow's date from 17:00
UTC, so its Actions read as not yet overdue, and its PM schedules as not yet
due, for seven hours of every local day; a Site west of Greenwich had the
opposite error. The failure is quiet in the way ADR-0017 warns about: no
error, a plausible number, wrong for some hours of the day.

## The decision

"Today" is `(now() AT TIME ZONE sites.timezone)::date` for the Site the row
belongs to. It is resolved in the database, by two small SQL functions
(migration `1802300000000_site-local-today`), built on the baseline's
`plant_date(org_unit_id, instant)`, which already resolves an instant to a
Site's calendar date through the Org Unit:

- `org_unit_today(org_unit_id)` - the local date at the Org Unit's Site.
  Used wherever the row has an Org Unit: Actions (`action_items`), CAPAs,
  Customer complaints, Supplier NCRs, PM schedules (through the Asset's Org
  Unit), and the views `v_open_actions`, `v_pm_due`, `v_pm_compliance`.
- `employee_today(employee_id)` - the local date at the Site of the
  Employee's default Org Unit. Used for everything keyed on an Employee:
  whether a qualification has lapsed, whether an Assignment is current, and
  the defaults for `terminated_on`, `assessed_on` and a transfer's
  `effective_from`; and the view `v_skill_coverage`.

Functions rather than `JOIN sites` at each call site, because the same
expression is needed in a dozen queries and three views, and one definition
cannot drift. The functions are `STABLE`, so Postgres evaluates `now()` once
per statement and a single query sees one consistent "today".

## Rows with no Site

If no Site can be resolved, "today" is the UTC date, which is what
`CURRENT_DATE` returned before, so nothing changes for such a row. Two cases:

- An Employee with no default Org Unit (a newly created Employee, an
  administrator's directory entry) has no Site. Their qualifications and
  Assignments are judged against the UTC date until they are given a default
  Org Unit. The Employee's *default* Org Unit is used, not their current
  Assignment's, because the Assignment is the thing being judged: asking which
  Assignment is current in order to find the Site, in order to decide which
  Assignment is current, is circular.
- The `UTC` fallback is spelled out (`now() AT TIME ZONE 'UTC'`) rather than
  `CURRENT_DATE`, so it does not move if someone later sets a session
  timezone.

## What this does not change

- A production day is still the shift pattern's (ADR-0017). "Today" here is the
  Site's calendar date, which is what a due date, an expiry date and an
  effectiveness-check date are: calendar dates entered by a person, not
  production-day buckets.
- `DEFAULT CURRENT_DATE` in the baseline (document-number year prefixes, the
  `employee_skills.assessed_on` column default) is left alone. The number
  prefix is a year label and the application always supplies `assessed_on`.
- `generate_shift_instances_ahead` still uses `CURRENT_DATE`; it is a nightly
  rollover job, not a per-row judgement, and is outside this decision.
- Maintenance writes in `work-orders.js` (stamping `last_completed_on` and
  rolling `next_due_on` when a PM is completed) are being changed separately;
  they should use `org_unit_today(wo.org_unit_id)` as well.
