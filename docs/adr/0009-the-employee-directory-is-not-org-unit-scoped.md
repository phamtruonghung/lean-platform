---
status: accepted
---

# The Employee directory is not Org Unit scoped

Date: 2026-09-02

Issue #9 ("The directory") gives any approved Account a way to list, search
and filter Employees, and to read one Employee's detail view — job role, Org
Unit assignments and skills. Every other read surface this Module has built
so far sits behind Org Unit scope (issue #8, ADR-0008): a Site, an Org Unit,
or a subtree is visible only to an administrator or to an Account holding a
grant that reaches it. `GET /employees*` deliberately does not follow that
pattern. It sits behind `authenticate` and `requireActive` only, exactly like
every other route in this Module, but no `authorization.canAct`, no
`requireOrgUnitScope`, and no per-row filtering by the caller's grants. Any
approved Account can list every Employee, filter by any Org Unit, and open
any Employee's detail view — this is recorded here because, without it, the
absence of a scope check reads as an oversight rather than a decision the
next person touching this file might reverse by "fixing" it.

## The decision

`GET /employees`, `GET /employees/me` and `GET /employees/:id`
(directory-routes.js) are readable by any Account that has cleared
Approval — `authenticate` + `requireActive`, nothing more. This holds for the
whole directory, including the Org Unit filter: an Account with no grant
anywhere in a Site can still filter the directory by an Org Unit in that
Site and see who is assigned there.

## Why

Org Unit scope (issue #8's grant model, ADR-0008) exists to bound where an
Account may **act** — write to an Org Unit's tree, and by extension act on
what sits within it. It was never a rule about who an Account may **know
about**. A plant directory is not a secret: knowing that a named Employee
works in a given department, holds a given job role, or carries a given
skill is exactly the kind of fact a supervisor needs about people outside
their own granted Org Units to find cover for a shift, locate a certified
welder, or simply recognise a name on a corridor. Scoping the directory the
way Sites and Org Units are scoped would solve a problem this Platform does
not have, at the cost of making the directory useless for the cross-Org-Unit
questions it exists to answer.

What *is* still restricted is `GET /accounts` (routes.js, issue #8's own
review) — administrator-only, unchanged by this ADR. An Account's email, role
and `external_subject` (the identity-provider subject) is a different kind of
fact than an Employee's name and current posting: it identifies who may sign
in and what they may do here, not who works at the plant, and the two are
allowed to have different visibility rules precisely because CONTEXT.md
treats Employee and Account as different things.

## Consequences

A later Module that wants a genuinely private per-Employee attribute — a
disciplinary note, a pay grade, anything not meant for platform-wide viewing —
cannot simply add a column to `employees` and assume Org Unit scope will
cover it. Nothing does; this ADR is exactly what stops it from doing so. Such
an attribute needs either its own table with its own, deliberately-scoped
read surface, or to live on `app_users` instead if the fact is really about
the Account rather than the Employee. This is the same shape of trade-off
ADR-0008 records for entry points: a decision explicit enough that the next
person to touch this area is choosing to extend it or to override it, not
discovering it by accident.
