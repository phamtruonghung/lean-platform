---
status: accepted
---

# A CAPA is an investigation opened on a Concern

Date: 2026-09-16

The Quality Module is built to meet ISO 9001's requirement for a nonconformity
and corrective-action record, and the inherited schema offers a CAPA that stands
on its own: `capas` with eight `capa_steps` rows, each step carrying its own owner
and due date. The Action log built in #175 already records most of what those
steps are for — a Containment is D3, a Countermeasure is D5–D6, a Preventive
action is D7, and ADR-0033 already refuses to close anything whose Check was never
verified.

## The decision

A CAPA is a formal investigation opened on an existing Concern, never a record of
its own that runs beside one. The Concern stays the problem; its Containments,
Countermeasures and Preventive actions are the CAPA's actions, recorded in the
Action log exactly as any other Concern's are. The CAPA carries only what an
investigation adds on top: the team, the problem description, the root-cause
analysis, the effectiveness verification, and the report a customer or auditor
reads. `capa_steps` is not used.

A CAPA is opened by a quality engineer's judgement. Nothing opens one
automatically — not a customer complaint, not a critical non-conformance, not a
recurring defect code.

## Considered options

- **A CAPA owns its own 8D steps** (`capa_steps` as inherited), raising Actions
  where it wants them. Rejected: the same fix would be tracked twice, once as a
  step and once as an Action, and the two would drift — the step marked done
  while the Action's Check said the countermeasure did not hold.
- **A CAPA replaces the Concern for quality problems.** Rejected: a Concern raised
  on the floor that turns out to need an investigation would have to be copied
  into a different kind of record, losing its PDCA history, and a CAPA opened from
  a safety incident would have no Concern to stand on at all.

## Consequences

Opening a CAPA never creates a second place to do the work, so the Action log
screens show a CAPA's progress without knowing CAPAs exist. The CAPA record's
own status is about the investigation — is the root cause confirmed, has
effectiveness been verified — not about whether its actions are done, which the
Concern already answers.
