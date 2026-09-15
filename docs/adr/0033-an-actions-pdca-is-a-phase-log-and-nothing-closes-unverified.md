---
status: accepted
---

# An Action's PDCA is a phase log, and nothing closes unverified

Date: 2026-09-15

Issue #175, implemented by #177 (the phases) and #179 (the closure rules).
`action_items.status` is `open` / `in_progress` / `blocked` / `done` /
`cancelled`: a row knows whether it is finished and never which phase of the
cycle it is in, who owns that phase, when it is due, or — the step every plant
skips — whether the countermeasure was ever verified to have worked. This ADR
records where the four phases live, what moves the Action's own status, and what
is refused at the end of a cycle.

## The decision

A new child table holds one row per phase per cycle: `action_phases`, with
`(action_item_id, cycle, phase)` unique, `phase` in `plan | do | check | act`,
and each row carrying its own owner, due date, completion, note and — on a Check
— an outcome of `effective` or `not_effective`. An Action is raised with its
cycle-1 Plan; completing a phase opens the next one; a Check that records
`not_effective` opens the next cycle's Plan instead of the Act; completing the
Act closes the Action. `action_items.status` keeps its five values and is written
by those transitions.

## Why a phase log rather than four status values

The alternative considered first was to put the cycle into the status column —
`plan`, `do`, `check`, `act` as the values, one column, one state machine. It
fails on three counts, and the first is decisive.

A phase has its own owner and its own due date. The baseline already made this
argument when it kept `capa_steps` as rows rather than eight columns: "so each
step carries its own owner and due date — an 8D where only the whole thing has an
owner is an 8D nobody progresses". A status value cannot carry either, so the
four-status design answers "which phase is it in" and then has nowhere to put
"whose is it, and when is it due" — which is the only question a daily-management
list is read for.

The second count is the cycle itself. PDCA is a circle: a Check that says the
countermeasure did not hold sends the Action back to Plan, and the first round's
reasoning is the most valuable thing the record holds. Four status values have no
memory of a cycle that was re-run; a row per phase per cycle keeps every round,
numbered.

The third is that the status column is already load-bearing elsewhere. Both
`v_open_actions` and `v_sqcp_board` predicate on the current five values, the
open-item indexes are partial on them, and replacing the vocabulary would mean
rewriting two views and three indexes to say the same thing less.

## Why the status column still moves

Keeping both would be two sources of truth if they could disagree, so one rule
holds them together: every phase completion writes the status that phase implies,
in the same transaction, inside one service function. `open` while the Plan is
open, `in_progress` from the completion of the Plan onward, `done` on the
completion of the Act. `blocked` and `cancelled` are untouched by the cycle.

The reading is deliberate and asymmetric: the status is what the register, the
indexes and the views count with — a small, coarse vocabulary — and the phases
are what a person reads when they want to know what is actually happening. A
reader who wants detail reads the phases; nobody has to read both to act.

## Each new phase inherits the Action's owner and due date

The server creates every phase after the first, and it copies the Action's
current `owner_employee_id` and `due_date` onto it. The alternative — a phase
born with neither, to be filled in later — produces rows nothing can triage and
needs an edit route to fix, and the plan has no edit route for a phase: a phase
is completed once, and the next cycle is how a course is corrected.

## Nothing closes unverified

Completing a Concern's Act phase is refused, 409, twice over: while the Concern
has no measure of type `countermeasure` at all, and while any measure of it is
still open. The baseline's own line about CAPA is the argument — "the field that
separates a CAPA system from a list of good intentions … an 8D here cannot be
closed without it" — and this is that field one level down, at the concern rather
than the investigation.

The first refusal is deliberately not "has no measures". A concern with a
Containment and no Countermeasure was contained, never fixed; a check that
counted measures would let exactly the case the rule exists for walk through.

Both refusals are evaluated after `SELECT … FOR UPDATE` on the Action, so a
measure raised between the check and the write cannot close under a Concern that
has already been judged. They also apply to a Concern only: a measure's own Act
is not held to either rule, because a Containment answers a concern and has no
countermeasures of its own. That asymmetry is what makes "containment now,
countermeasure after" legible in the data.

Cancelling is the other door, and its rule is the opposite of completing: the
reason is optional, because undoing a mistake should not demand prose, and a
cancel writes no evidence — it withdraws a claim. `action_items_done_has_time`
makes the timestamp mandatory with the status, so the database is a backstop and
not the primary defence; the guard is the service function's, over a locked row,
the shape ADR-0019 already fixed for the Work order's transitions.

## Consequences

The register's row grows an "open phase" column (read through a lateral join) and
the detail response grows a `phases` array holding every cycle, oldest first. The
turn of the circle is visible: a concern that needed two rounds reads as two
rounds rather than as one.

A phase completed by mistake cannot be un-completed, and its note cannot be
edited. What a plant does instead is record the correction in the next cycle's
Plan, which is the honest version of the same act.

## What this does not settle

Whether an Action's own owner or due date can be corrected after it is raised.
This plan has no route for it: the values the raise form set stand, and a
correction would have to reuse the raise route's own validation — which is a
ticket of its own rather than a side effect of the cycle.

Where a *blocked* Action records why it is blocked. The status is legal in the
schema, unused by this plan, and the reason wants the same treatment as an
escalation's target: a value with a known set, chosen rather than typed. The
ticket that needs it decides it.

Whether a numeric target and a measured result belong on the Action. They do not
today: the Plan phase's note carries what will be different and the Check's note
carries what was measured, and comparing the two numbers is a KPI's job. A second
copy of a number in this table is exactly the stale figure `board.js` refuses to
materialise.
