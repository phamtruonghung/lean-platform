---
status: accepted
---

# Modules are code seams, not data seams

Date: 2026-09-01

The Platform's Modules — People, Maintenance, Tier Board — are folders in one
backend over one schema. A Module owns its routes and its domain services, and
never imports another Module's internals: it calls that Module's service. No
Module owns a private set of tables, and cross-module reads are ordinary joins.

## Why not give each Module its own data

Because that is the boundary ADR-0001 removed. The schema is one connected
graph — Maintenance reads `employees`, `org_units`, `shift_instances` and
`downtime_events` constantly — so data seams would turn foreign keys into
function calls and give up referential integrity to enforce a separation the
domain does not have.

## Consequences

The rule is a convention, so it needs enforcing: an import-boundary lint rule in
the backend, not code review alone. It is also cheap to reverse, which is the
point — if a Module ever genuinely needs to be extracted, having kept its
services distinct is what makes that possible.

## What a Module's entry point may expose

Added 2026-09-04 (issue #59). This elaborates the decision above rather than
reversing it: "calls that Module's service through its entry point" never said
what may be *in* one, and Maintenance becoming the second Module with routes
of its own to guard (issues #56, #57, #61, #62, #63, off parent #55) is the
first time the question has real stakes. Three clauses govern what an entry
point (`<module>/index.js`) may export to another Module:

1. **Questions, not commands.** An entry point exposes read-only lookups and
   predicates over the records that Module owns. It never exposes a write —
   a second Module changes its own records, never another Module's, even
   through a function call that happens to be reachable.
2. **Values, not control flow.** A cross-Module lookup returns a value —
   `null` for "no such row" — rather than throwing an HTTP-status-carrying
   `Error` into a caller that does not own that Module's error funnel.
   Otherwise the `.status`-on-Error protocol becomes an undocumented contract
   between two Modules owned by neither, and the consumer loses control of
   its own 404 wording for a row it is asking another Module about.
3. **Domain, not utility.** Generic helpers — id parsing, HTTP error
   construction, a generic 404, a SQL `LIKE`-escaper — never cross an entry
   point. A Module's entry point is a set of domain answers, not a place to
   borrow utility code; every other Module gets its own small copy of
   whatever generic plumbing it needs.

One deliberate exception to clause 3: a string naming the exact refusal a
Module's own authorization model produces (People's `OUTSIDE_GRANTED_ORG_UNITS`
is the first instance) is domain, not utility, even though it resembles a
generic error constant. It is the canonical wording of a refusal only the
owning Module can produce correctly, and a caller getting different sentences
for the same refusal depending on which Module happened to answer would be a
real inconsistency, not a false one avoided by clause 3.

`router` is a special case of none of the three clauses: `src/index.js`, which
mounts it, sits outside `modules/` entirely, so it is not a cross-Module
export the boundary checker even evaluates — it is just how a Module becomes
reachable over HTTP at all.

The authentication middleware — People's `authenticate` and `requireActive` —
is the second such case, and a more interesting one, because it breaks clauses
1 and 2 outright rather than sidestepping them. It is control flow, not a
value: it answers by calling `next()` or by writing a 401 itself. And
`authenticate` **writes**: resolving an identity that has never signed in
before creates the Account row for it, and on a genuinely empty instance that
row becomes the bootstrap administrator (issue #6). A first-ever sign-in whose
first request happens to land on a Maintenance route therefore writes People's
own `app_users` table through another Module's request path.

That is a real exception, not a technicality, and it is allowed for a
structural reason: every Module's routes sit behind the same session, because
there is one identity provider and one Account per person for the whole
Platform (ADR-0002). A second Module cannot re-implement "is this caller
signed in, and admitted" without re-implementing Accounts, which is precisely
the data seam this ADR exists to refuse. The narrow rule: **a Module may
export middleware that establishes the caller's identity, and only that.**
Anything a Module exports that is *about a record* still obeys all three
clauses.

Org Unit scope enforcement (`canAct`, and the middleware built on it) stays in
People rather than moving to a shared `src/platform` module, for two reasons.
Mechanically: `requireOrgUnitScope` calls `plant.getOrgUnit`, so a platform
copy would either have to require a Module itself — a hard lint violation, the
inverse of the direction this ADR allows — or duplicate the definition of what
an Org Unit is. Architecturally: `canAct` is a join over `app_user_org_units`
and `org_units`, both People's own records, so moving it to `platform` would
give People's schema two owners — violating this ADR in spirit while the lint
stayed green, which is a worse outcome than a violation the lint actually
catches. The rule this leaves standing: `platform` holds what has no domain
content; Org Unit scope has domain content, so it stays in the Module that
owns the data it is scope *over*.

The client mirrors this per ADR-0012: a client Module likewise exposes its
repository/Bloc through its own entry point rather than its widgets, the same
code-seam-not-data-seam shape applied one layer up. This ticket does not touch
the client.
