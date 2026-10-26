---
status: proposed
---

# A shift handover is one record per Section per shift instance, frozen when the incoming Team Leader acknowledges it

Date: 2026-10-26

Issue #332 asks for the shift handover the Self-Closing section runs today on
paper: Cutting, Shaping, Raschel and Warping hand a shift from one Team Leader
to the next, and the form that carries it exists nowhere in the Platform. The
baseline already carries everything the record needs to point at —
`shift_instances`, `org_units` (with `section` as a `unit_type` since #271),
`assets`, `production_runs`, `production_counts`, `downtime_events`,
`quality_issues`, `action_items` — and nothing reads any of it. So this is the
first slice of a Production Module, and it is thin on purpose: it records a
transfer of responsibility, it does not become a second production log.

The research behind the shape is `docs/research/shift-handover.md`.

## The decision

**One record per Section per shift instance, and a unique constraint says
so.** A handover belongs to `(org_unit_id, shift_instance_id)` with a unique
index on the pair. Not one per machine: the Team Leader hands over the section,
and the machines are lines inside that one act. Not one per production order: an
order can span shifts, and a shift can run several. The unit of accountability
is the thing a person is responsible for at the boundary, which is the Section.

**The absence of a handover is derived, never a fake row.** A closed shift
instance with no submitted handover is reported as "no handover recorded" by the
query that lists them, in the same spirit as an unconfirmed Attendance sheet. It
is not an empty handover inserted on the section's behalf: an empty record and a
missing one must stay different facts, and a row nobody wrote must not be
signable.

**The record freezes the numbers it showed.** At submit, the handover computes
and stores the figures the form displays — OEE and its three components, planned
production minutes, run and unplanned-downtime minutes, the top loss and its
minutes, unclassified downtime, good/reject/rework and the planned-versus-good
gap, the open quality issues and safety events of the shift — and never
recomputes them. This deliberately contrasts with the tier board, which
recomputes on read (ADR-0004's reasoning, `maintenance/board.js`): the board is
a live reading of the plant, while a handover is evidence of what one Team
Leader told another at one moment. A late downtime event corrects OEE; it must
not rewrite yesterday's handover, which is a record of a conversation.

**The authenticated act is the evidence; no signature image in this slice.**
Authorship and acknowledgement are Accounts acting inside their Grants, recorded
with who and when, exactly as ADR-0052 argues for a Signature: an image is the
rendering of an act, not its proof. Nothing prints a handover yet, so there is
no cell to render a mark into; when the plant wants the paper form printed, the
Signature model applies on its own ticket.

**Any Account whose edit Grant reaches the Section may author or acknowledge,
and the acknowledger may not be the author.** Team Leader is a Job role, not an
account role (`operator`/`supervisor`/`engineer`/`manager`/`admin`), so gating on
a role name would either invent a role or exclude the person who actually does
the work. Scope already answers "may this person act at this Section", and the
one extra rule — a handover is not acknowledged by the person who wrote it — is
a check the record can make against itself.

**The lifecycle is draft, submitted, acknowledged, and a correction is an
amendment.** A draft is editable by whoever may act at the Section. Submit seals
it: the snapshot is written, the author and time recorded, the content no longer
editable. The incoming Team Leader's acknowledgement records who and when, and
is the point the handover appears on the section's board as received. After the
freeze nothing is edited in place; an amendment is a new row set that points at
the version it replaces and carries its own reason and author, so both versions
remain readable. Nothing auto-acknowledges, and nothing ever overwrites a sealed
handover — an unacknowledged handover stays visible as an exception until a
person deals with it.

**Every active Asset in the Section gets a machine status line, and a line that
is not running normally must say why.** The check runs at submit and refuses
with the assets it is missing. The state is a chosen value, never typed, and a
state outside normal running carries a reason plus at least one of a downtime
event, a quality issue or a work order — the platform's existing records, by id,
not a paraphrase of them.

**Change points are their own rows, one per 4M dimension, with the watch they
trigger.** A different person, a changed machine setting or tool, a new material
lot, a changed method: each is recorded because the next shift must look for the
harm it might cause, and each carries what to watch and whether that watch ran.
This is the half of the handover a free-text box loses first.

**Actions are linked, not copied.** `shift_handover_actions` points at
`action_items` rows, so the plant keeps one action list and one PDCA phase log
(ADR-0033). Every open action on the Section is dispositioned by each new
handover — carried, reassigned, or closed with the evidence that closed it —
and a carried action's age in shifts is derived from the handovers that carried
it. Retyping an action into a handover is the failure mode this prevents: two
lists that disagree within a month.

**The handover is Production's record, and the new Module owns it.** It is
neither Maintenance's nor Actions' nor People's. It joins their tables directly
for reads (ADR-0006's code-seam rule), and it calls a Module's entry point only
where it needs that Module's judgment — raising a Countermeasure from an
abnormality goes through Actions, not through an insert.

## Consequences

- A new backend Module (`src/modules/production/`) and a matching
  `frontend/lib/production/`, mounted at `/api/production`, with the boundary
  checker (`npm run lint`) extended by nothing: it already reads every directory
  under `modules/`.
- Three tables: `shift_handovers`, `shift_handover_machine_lines`,
  `shift_handover_change_points`, plus `shift_handover_actions` as the link to
  the action log. Forward-only migration, one file.
- The section board reads handovers per Section and production day; the tier
  board gains two numbers (`PRO_HANDOVER_COMPLETION`, `PRO_HANDOVER_ACK_MINUTES`)
  in a later slice, computed from these rows.
- The Production Module's `kpi-registry.js` contributes those two and nothing
  else until a KPI needs it.
- `CONTEXT.md` gains Section, Shift handover, Machine status line, Change point,
  Handover acknowledgement and Carried action, so code, tests and UI copy have
  one word each.

## Alternatives considered

**A handover per machine.** Rejected: the unit of responsibility at a shift
boundary is the Section, and a per-machine record fragments one conversation
into six records that no one reads in order. Machine detail stays as lines.

**A handover per production order.** Rejected: orders cross shifts and shifts
cross orders, so either the record duplicates or the shift's other machines have
nowhere to go.

**Copying the shift's numbers into free text, or recomputing them on read.**
Rejected both ways: free text loses the numbers to a spreadsheet, and
recomputation makes a sealed handover change under the people who signed it.

**Reusing the tier meeting (`tier_meetings`) as the record.** Rejected: a
meeting is an event several people attend; a handover is a transfer between two
named people with an acknowledgement. The huddle reads the handover; it is not
the handover.

**A supervisor co-signature in this slice.** Deferred, not rejected: the plant's
current form may have one, and adding a second signature later is additive. The
record carries the columns a second act would need (who, when, role of the act).
