---
status: accepted
---

# Assignment writes are Org-Unit-scoped, unlike the rest of the directory's write surface

Date: 2026-09-02

Issue #10 ("Job roles and Org Unit assignments") adds `POST
/employees/:id/assignments`: recording that an Employee works at a given Org
Unit, as a given job role, from a given date. Every other write route in
`directory-routes.js` — `POST /employees`, `PATCH /employees/:id`, `POST
/employees/:id/departure`, `POST /employees/:id/reinstatement` — is
administrator-only (`requireAdmin`), on the reasoning ADR-0009 already gives:
an Employee is not "owned" by an Org Unit, so Org Unit scope has no natural
place to attach to a write against the Employee record itself. The new
assignment route deliberately does not follow that pattern. It sits behind
write scope on the Org Unit it names, the same `authorization.canAct({
write: true })` check plant-routes.js already uses for "create an Org Unit
under this parent" and "deactivate this Org Unit" — recorded here because,
without it, a later reader comparing this route to its four siblings in the
same file would see an inconsistency rather than a considered decision.

## The decision

`POST /employees/:id/assignments` requires write scope on the **destination**
Org Unit named in the request body (`orgUnitId`) — a grant on that Org Unit
itself, or on an ancestor of it, following the same downward-reachability
rule (`canAct`) every other Org Unit write in this Module already uses. An
administrator needs no grant at all, since `canAct` already returns true for
that role unconditionally.

The ordering follows authorization.js's own documented existence-before-scope
rule, applied to a body field rather than a path param, the same way
plant-routes.js's `requireOrgUnitCreateScope` already does for `POST
/sites/:siteId/org-units`: parse `orgUnitId` (400 if malformed) → resolve it
via `plant.getOrgUnit` (404 if it names nothing) → `authorization.canAct`
(403, the shared `OUTSIDE_GRANTED_ORG_UNITS` body, if the caller holds no
write grant reaching it). The Employee's own existence (and whether they have
departed) is checked afterwards, inside `directory.createAssignment` itself,
once the caller is already known to be allowed to write to the destination.

Scope is checked on the destination only. A transfer's *source* Org Unit —
where the Employee's now-open assignment currently is — is deliberately left
ungated: a supervisor receiving a transfer into their own line does not need
a grant on the line the person is leaving. Requiring scope on both ends would
make an otherwise-ordinary transfer depend on a grant the receiving
supervisor has no reason to hold, for a write that changes nothing about the
source Org Unit's own record beyond closing a date range.

## Why an Employee record and an assignment are different

ADR-0009's reasoning is about the Employee record: name, hire date,
employment type, work email — none of that is a fact "about" any particular
Org Unit, so there is no Org Unit whose scope could meaningfully gate editing
it. An assignment is a different kind of row. Its entire content is "this
Employee, at this Org Unit, as this job role, from this date" — it names one
particular Org Unit as its own subject, the exact shape `plant-routes.js`
already gates by scope for every other write that names an Org Unit
(creating a child under it, deactivating it). Treating the assignment write
as administrator-only, the way the rest of this file's write surface is,
would mean a line supervisor who may already create Org Units and grant
access beneath their own line still cannot assign a person to it without an
administrator — a strictly greater restriction than everything else that
Org Unit already lets them do.

## Consequences

A future write that similarly names one particular Org Unit as its subject —
rather than editing a fact about the Employee themselves — should default to
this same shape (write scope on the named Org Unit) rather than to
`requireAdmin`, unless there is a reason specific to that write to prefer the
administrator-only pattern instead. Skills (issue #11) are the test case:
a skill names an Employee and a competency, not an Org Unit, so ADR-0009's
original reasoning is expected to hold there unchanged — this ADR is not a
general loosening of the directory's write surface, only the one place an
Org Unit is genuinely the subject of the write.
