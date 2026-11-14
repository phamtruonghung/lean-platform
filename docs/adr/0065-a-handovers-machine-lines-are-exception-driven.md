# 0065 — A handover's machine lines are exception-driven, not one per active Asset

- **Status:** Accepted
- **Date:** 2026-11-15
- **Issue:** #355 — amends ADR-0054's completeness rule

## Context

The Platform ships the shift handover (ADR-0054) and it is not lean.

`requireComplete` in `backend/src/modules/production/handovers.js:438-524` runs an
anti-join over the Section's active Assets and refuses with `409
INCOMPLETE_HANDOVER`, naming every Asset that has no line (`:439-447`, `:502-503`).
The Screen renders one `_MachineRow` per active Asset with no skip affordance
(`frontend/lib/production/shift_handover_screen.dart:370-379`), and the client turns
the refusal into "No machine status line for …" (`:567`, from
`HandoverRefusal.missingAssets` at `frontend/lib/production/handover.dart:390-397`).
For Self-Closing's Cutting MTU that is **17 machine picks every shift even when
nothing changed** (`dev/seed-relats-vietnam.mjs:122-123` — 17 active MTU machines),
each row an 8-value state pick plus a 7-value abnormality pick plus note, watch and
walked.

The note is the point of a handover; the machines are its context.
`docs/shift-handover-leaner-shape.md` (PR #354, merged) set out the shape and left
four product questions explicitly unanswered. This ADR answers them, so the shape
can be built.

The derivation has a home already: `downtime_events` carries `shift_instance_id` and
is indexed on `(shift_instance_id, started_at)`
(`backend/migrations/1756000000000_baseline.js:1821-1893`), so "what happened to this
machine during this shift instance" is a query the baseline schema already supports.

## Decision

Four answers, in the order the issue asked them.

**1. Exception-driven.** A machine line exists for an Asset only when the shift had
something to hand over about it. A machine that ran normally all shift produces no
line, and that absence is the statement: *nothing happened here*. The frozen
snapshot, change points, carried actions and evidence blocks are unchanged — they
are already lean.

**2. Derived from the Platform's own `downtime_events` for that shift instance.**
Not from mtu-dashboard. A second system's availability must not decide whether a
handover can be submitted, and ADR-0051 already puts production data in this
Platform's own Postgres. Per-machine enrichment from mtu-dashboard stays out of
scope — and if it is ever added it is a read-only hint the form works without,
never a precondition of Submit.

**3. Completeness is: the note is written, and every Asset the derivation flags as
abnormal has a line carrying its reason and reference.** `missingAssets` goes, with
the anti-join behind it and the refusal line that names it. The half of ADR-0054
that stays is the half that matters: *a non-normal-running line carries a reason and
a reference*. Narrowing completeness from "every active Asset" to "every derived
abnormal Asset" is the change; dropping the reason from an abnormal line would lose
the reliability attribution the plant's numbers are built on, so it does not go.

**4. The glossary changes with the implementation, not with this ADR.** `CONTEXT.md`'s
**Machine status line** (`:565-570`) currently ends "Every active Asset in the
Section has one, which is what makes 'the machine nobody mentioned' impossible".
That sentence goes and what replaces it names the derived set. It is deliberately
**not** rewritten here: until the code changes, the current sentence is the true
description of the shipped form, and a glossary that runs ahead of the code is the
failure ADR-0020 already had to correct.

**No migration.** The record already holds `shift_handover_machine_lines`; an
exception-driven handover writes fewer rows of the same shape, not a new shape. The
slice is a read (the derivation), a removal (`missingAssets`, its field on
`HandoverRefusal`, the client's refusal line) and a re-render.

## Consequences

- The implementation is its own card. This ADR records the decision and does not
  build it, which is the whole reason #355 was filed as an issue rather than a pull
  request.
- `docs/user-guide/07-san-xuat.md`'s handover card, step 1 — "Mỗi Tài sản của Bộ
  phận là một dòng" — is the sentence that changes **with the code, in the same pull
  request**. That is the guide's own promise (its words are the words on the Screen)
  applied to a flow change, and it is the reason a decision recorded without an
  implementation leaves the guide alone and correct.
- ADR-0054 gains a pointer to this ADR rather than an edit: its record of what was
  decided stands, and the completeness rule it set is amended here.
- The Screen stops being a form a writer must fill and becomes one they add to.
  That is a change of *effort*, not of what a handover means.

## Alternatives considered

**Keep one line per active Asset.** Rejected: it is the owner's complaint, and 17
rows a shift for "nothing changed" is how a form stops being read — at which point
the completeness rule is being satisfied with whatever fills the dropdowns fastest,
which is worse for the reliability numbers than fewer, honest lines.

**Remove machine lines entirely and carry machines in the note's free text.**
Rejected: machine-level exceptions are what the incoming shift acts on, and the
reliability numbers read these lines. Free text is not a record.

**Derive from mtu-dashboard's per-machine breakdown.** Deferred, not condemned
(answer 2): it is refused as a *dependency* of Submit, not as a source of context.
