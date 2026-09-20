---
status: accepted
---

# An injury's diagnosis is restricted; the incident is not

Date: 2026-09-20

A Safety incident is two different things carried in one record: the event
itself — its severity, its kind, what happened, what was done, what it cost
in days — which is exactly what a plant is meant to act on, and, when it was
an injury, an injured person's diagnosis, which is medical information about
one person.

## The decision

The incident stays readable by anyone who can see the Site: severity level,
incident type, description, immediate action and days lost are open to
every Account that can see the Site, because those are the numbers a
supervisor, a manager and the tier board are meant to act on. The identified
Employee, injury type and body part are readable only by a holder of Safety
authority reaching the incident's Org Unit, and by the Account whose own
`app_users.employee_id` names the injured Employee — that column is UNIQUE
and set at Approval, so "their own" is a real identity, not a guess. A field
withheld from a caller is absent from the response, not nulled with a hint
that something is being kept back.

The restriction covers three structured fields — the identified Employee,
Injury type, Body part — and **nothing else**. This is a limit on what the
restriction protects, not a caveat attached to a broader guarantee.
`description`, `immediate_action`, and any Concern raised from the incident
are free text that a person writes whatever they write into, and none of it
is gated. The Action log's own register, `GET /sites/:siteId/actions`, is
Site-wide by design — its header states plainly that the route sits behind
authentication and an active-Account check "and nothing else — no role
check, no Grant filter, no per-row `canAct`"
(`backend/src/modules/actions/action-routes.js`) — so a Concern raised from
a safety incident is exactly as readable as every other Concern on the Site.
A gate placed on that route to protect a diagnosis would defend nothing: the
same diagnosis, if a recorder chose to write it there, is already sitting in
the incident's own `description` a field away, unprotected by the same
decision.

## Considered options

- **Gate the free-text fields too**, redacting `description` and
  `immediate_action` for a reader without Safety authority. Rejected: a
  supervisor who lacks Safety authority still has to read what happened and
  what was done to run their line, and redacting the field a recorder is
  told to write findings into does not stop a recorder writing a name into
  it — it only stops the plant reading its own record of what happened.
- **Gate the Action log's reads for a Concern raised from a safety
  incident.** Rejected: ADR-0032 already made the Action log one register,
  read the same way regardless of source, and a per-source exception would
  need the log to know a Concern's Module before deciding how to answer a
  read — the distinction the log was built not to need.
- **Describe the restriction as covering "sensitive fields" without naming
  which ones.** Rejected: an unnamed boundary gets redrawn by guess the next
  time someone touches this code. Naming the three structured fields, and
  naming the free-text ones as explicitly outside the restriction, is what
  keeps a later reader from either trusting a gate that is not there or
  building one that defends nothing.

## Consequences

A description or an immediate-action note that names the injured person, or
makes clear who they are, is readable by anyone who can see the Site — the
guidance on what belongs in a description is guidance to whoever writes it,
not a mechanism, and this ADR states that plainly rather than implying a
protection that is not there. What is gated, completely, is the plant's own
structured classification of the injury: who the record names as hurt, what
the injury was, and where on the body — the fields a report, a filter or an
export would otherwise turn into a list.
