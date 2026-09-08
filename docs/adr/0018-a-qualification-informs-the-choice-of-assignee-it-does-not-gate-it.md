---
status: accepted
---

# A qualification informs the choice of assignee; it does not gate it

Date: 2026-09-08

Issue #62 ("Assign a work order, with qualifications shown") gives a
supervisor `PUT /api/maintenance/work-orders/:id/assignee`: give a Work order
to an Employee, or move it to a different one. The ticket's own name puts the
two halves side by side — assigning, and *showing qualifications* — and it
would be easy to read the second half as license to enforce the first: refuse
to assign a Work order when the chosen Employee does not currently hold the
right skill. This route deliberately does not do that. No code path in this
ticket reads a skill in order to decide whether assigning a Work order may
proceed, and this is recorded here because, without it, the absence of that
check reads as an oversight rather than a decision the next person touching
this file might "fix" by adding one.

## The decision

`assignWorkOrder` (`backend/src/modules/maintenance/work-orders.js`) and its
route (`work-order-routes.js`) never consult `employee_skills`, `skills`, or
any qualification of the chosen Employee. The write succeeds for an Employee
holding the right qualification, the wrong one, an expired one, or none at
all — the only two refusals on the write are "no such Employee" (404) and "the
Employee has departed" (409), the same two checks `createAssignment`
(directory.js, issue #10) already applies before recording where in the plant
an Employee works. A named test (`an Employee holding only a lapsed
qualification can still be assigned`) pins this rather than leaving it to be
inferred from the absence of a check.

The candidate list (`GET /api/people/employees/assignee-candidates`) is the
other half: it shows what each candidate currently holds, with a lapsed
qualification marked as lapsed rather than left out. It states a fact and
stops there. It carries no evaluative field — no `isQualified`, no warning
string, no disabled flag — because nothing in the Platform today can say what
a *particular* Work order requires, so any such field would be a claim the
Platform cannot back up.

## Why not enforce it

`work_order_tasks.skill_id` ("The qualification this step needs" — baseline
migration, line ~4981) is where a job's skill requirement actually lives. A
task belongs to a Job plan, and Job plans are issue #74, not built yet.
Nothing today states what a particular Work order requires: a Work order
itself carries a `work_type` and a `priority`, not a skill requirement, and
inventing one on `work_orders` — a `required_skill_id` column, or similar —
would contradict the model that already exists (the requirement belongs on a
task, not on the order that contains tasks) and would be a schema change
outside this ticket's own scope, which AGENTS.md §4 already rules out.

A Platform that refused the write on the strength of a qualification it
cannot actually match to the job would be enforcing a requirement it does not
know. Worse, it would be *wrong* in the specific case a plant most needs
flexibility for: when the fully-qualified Employee is off sick and the
supervisor needs to hand the job to whoever is available today, a hard
refusal would strand the Work order rather than let a human make the call a
human is better placed to make. AC5 ("a Work order can be reassigned") exists
for exactly this scenario.

## Why not warn instead

A softer version was considered and rejected: leave the write unblocked, but
surface a warning banner in the assign dialog when the chosen Employee holds
nothing matching the Work order's own `work_type`, or holds only a lapsed
qualification, or similar. Rejected for the same reason as the hard block,
one level down: a warning is a claim that something is wrong with this
specific choice, and the Platform has no basis for that claim either — there
is still no requirement anywhere it can compare the candidate against. A
warning nobody asked for and nothing backs is worse than no warning at all: it
trains a supervisor to dismiss warnings that turn out to mean nothing, which
is a cost paid on every future warning that *does* mean something.

## Consequences

When #74 lands Job plans and tasks carrying `skill_id`, a Work order will (via
its tasks) finally have something concrete to compare a candidate against.
Revisiting this decision at that point is a new decision, weighed against
whatever #74 actually built, not a bug fix to this ticket. In particular nothing
here should be read as "the check was forgotten" — the check was left out on
purpose, and adding it back is exactly the shape of change ADR-0009's own
Consequences section describes: deliberate enough that the next person is
choosing to extend or override it, not discovering a gap by accident.

Until then, `assignWorkOrder` stays exactly as narrow as `createAssignment`
already is: existence and Departed status are the only two facts about an
Employee a write in this Module checks before recording where they are
placed. A qualification is information a supervisor reads on the way to a
decision, never a gate the Platform closes on their behalf.
