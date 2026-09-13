---
status: accepted
---

# Correcting a Site's timezone is refused once its shift calendar exists

Date: 2026-09-13

A Site's `code`, `name` and `country_code` are labels. Its `timezone` is not:
`generate_shift_instances` computes every shift instance's `starts_at` / `ends_at`
by interpreting the shift definition's local start time in the Site's zone
(the baseline migration), and `shift_instance_at` / `fill_shift_instance` /
`plant_date` attribute recorded work to a `production_date` derived from that
same zone (ADR-0017). Correcting a Site was impossible — the API carried only
`POST /sites` and `GET /sites` — so a Site created with a wrong zone could only
be fixed in SQL (issue #137).

Correcting the labels is uncontroversial. Correcting the zone raises the
question this ADR settles: a change is not editing a field, it is changing the
rule that turns instants into production days, retroactively.

## The decision

A correction is allowed exactly when no shift instance exists for the Site. It
is a full replacement of `code`, `name`, `timezone` and `country_code`, admin
only, with the same validation the create route applies. If the new `timezone`
differs from the stored one **and** any row in `shift_instances` names the Site,
the whole correction is refused with `409` and nothing is written.

## Why not the alternatives

**Rewrite history.** Recomputing existing instances' `production_date` and
re-running `shift_instance_at` over recorded work would move numbers already
reported — the exact outcome ADR-0017's production day exists to prevent. A
correction must never silently restate a shift's output.

**Apply forward only.** This is the honest long-run answer, but it needs an
effective-dated timezone (a history table, or `valid_from`/`valid_to`), a rule
for which zone a given `shift_instance_at` call resolves against, and a
backfill of the existing calendar. That is a schema change and a domain model
of its own; bolting it onto a correction route is how a label fix becomes a
migration nobody reviewed. It wants its own ticket if a real need appears.

**Refuse only once work is recorded against an instance.** Narrower, and it
sounds kinder, but it requires scanning every table that references
`shift_instances` (ten of them in the baseline) and still leaves the calendar
itself inconsistent: instances generated under the old zone would sit next to
new ones generated under the new, overlapping in absolute time. The calendar is
the timezone's one materialised consequence; once it exists, the correction is
already consequential, whether or not a record points at it yet.

## What this costs

**A Site whose calendar was generated but never used cannot be corrected.** The
maintenance job extends the calendar forward, so an unused Site can still have
instances. That is accepted: the calendar embodies the zone, and reinterpreting
it is the hazard being refused. The remedy is a reviewed data operation against
the instance rows, not a field edit.

**The lock is checked, not enforced by the database.** `plant.updateSite`
selects the Site `FOR UPDATE`, compares the zone, and probes `shift_instances`
inside the same transaction, so a concurrent calendar generation cannot slip
between the check and the write. A database constraint cannot express this
without a trigger reaching across two tables, which the codebase avoids for
cross-table rules.

## Out of scope, deliberately

**Comparing-and-setting a timezone "no-op".** A correction whose zone equals the
stored zone is not a timezone change and is always allowed, even with a
calendar — the lock exists to stop reinterpretation, not to stop fixing a code
typo on an active Site.
