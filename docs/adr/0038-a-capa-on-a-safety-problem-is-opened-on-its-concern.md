---
status: accepted
---

# A CAPA on a safety problem is opened on its Concern

Date: 2026-09-20

ADR-0034 already decided that a CAPA is a formal investigation opened on an
existing Concern, never a record of its own that runs beside one, and that a
CAPA belongs to no one Module — it is raised from a quality escape, a
customer complaint, a supplier non-conformance, a safety incident, or from
nothing at all. The baseline schema nonetheless carries `capas.quality_issue_id`,
`customer_complaint_id`, `supplier_ncr_id` and `safety_incident_id` as four
direct source links, alongside a `source_type` column generated from whichever
one is set and a `capas_single_source` CHECK limiting a CAPA to at most one of
them.

## The decision

Nothing writes `capas.safety_incident_id`. A CAPA opened on a Concern raised
from a safety incident is opened exactly the way ADR-0034 already describes
for every other source: `actions.openCapa(concernId, ...)` creates the CAPA
row and records it against the Concern's own `action_items.capa_id` — the
same path a CAPA opened on a Non-conformance's Concern, a complaint's
Concern, or a supplier NCR's Concern already takes. The Concern is what a
CAPA is opened on; `safety_incident_id` is not a second way to open one, and
this Module does not use it as one.

`capas.safety_incident_id` stays in the schema, unused, alongside the three
source columns it was added beside. It is named here specifically, rather
than folded into ADR-0034's general statement, because a column spelled
exactly like the thing a safety-CAPA ticket is about is precisely what a
later reader — grepping for `safety_incident_id` while building the next
piece of the Safety Module — will reach for and wire up, undoing this
decision by one convenient-looking `UPDATE`.

## Considered options

- **Set `capas.safety_incident_id` when opening a CAPA from a safety
  Concern**, treating it as denormalised provenance alongside the Concern
  link. Rejected: a CAPA would then be reachable two ways — through its
  Concern, and through a direct incident link — and the two could drift the
  moment either is updated without the other, which is the exact failure
  ADR-0034 already rejected for the general case.
- **Drop the four source columns entirely**, since ADR-0034 makes them
  unnecessary. Rejected as out of scope here: migrations are forward-only
  (ADR-0007), dropping a column is a later ticket's decision if it is ever
  made, and this ADR only needs to say the column is not used, not remove
  it.
- **Say nothing safety-specific**, and let ADR-0034's general statement
  stand for all four source columns including this one. Rejected: #234
  asks for the column to be named so a grep for `safety_incident_id` finds
  a decision rather than silence, since that column's name is the one most
  likely to look like an invitation once the Safety Module actually exists
  and is raising Concerns.

## Consequences

A CAPA report opened from a safety incident will name the incident through
its Concern — `action_items.safety_incident_id` is the source column the
Concern itself already carries in the baseline, and `readCapaConcern` reads
a CAPA's Concern in full — not through any field on the CAPA. No code reads
or writes `capas.safety_incident_id` today, and none should when the Safety
Module is built: it, `capas_safety_incident_idx` and the `safety_incident`
arm of `source_type` remain in the schema as dead weight, matching the
other three source columns ADR-0034 already leaves unused. Nothing here
treats the safety case as different from those three; it is named only
because its name is the one a Safety-Module ticket will otherwise reach
for.
