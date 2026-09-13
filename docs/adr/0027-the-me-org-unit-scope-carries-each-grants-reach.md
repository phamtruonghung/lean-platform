---
status: accepted
---

# The `/me` Org Unit scope carries each Grant's reach

Date: 2026-09-13

`GET /api/people/me` (`routes.js`) reports which Org Units an Account holds a
Grant on, one row per Grant, but not the Org Units those Grants *reach*. A
Grant reaches downward — `canAct`'s `target.path <@ granted.path`
(`authorization.js`) — so an Account granted "Line 3" may act on everything
beneath it, yet `/me` names only "Line 3". Every client-side count or filter
that tries to answer "on my Org Units" by matching a Work order's `orgUnitId`
against a Grant's own id is therefore too narrow: a supervisor granted "Line
3" sees nothing sitting on "Line 3 › Cell B", even though they could act on it
(issue #110).

Two places in the client do exactly that arithmetic, and they must agree:

- **Home's awaiting-assignment card** (`home_bloc.dart`) filters the
  Site-wide Work order list by exact `orgUnitId`. Mitigated before #110 only
  by wording — the card said "On the Org Units granted to you, not what sits
  beneath them" rather than fixing the number.
- **`canAssignWorkOrder`** (`router.dart`) reads the coarse
  `orgUnitScope.canWriteSomewhere`, which answers "may this Account write
  anywhere", not "may it write at *this* Work order's Org Unit".

The issue left the choice open: give `/me` the Org Unit ancestry so the client
can match a subtree, or have the server answer scoped counts instead. It
deferred the decision to the first real Org-Unit-scoped list reads (#72–#80).

## The decision

`/me`'s `orgUnitScope.grants` each gain `orgUnitIds`: every Org Unit that
Grant reaches — the granted unit itself plus all of its descendants —
computed by the server in `orgUnitScopeFor` with the same `path <@`
containment `canAct` already uses, as one correlated subquery per Grant over
the GiST-indexed `org_units.path`. A raw Grant row is otherwise unchanged, and
an administrator's `{ everywhere: true, grants: [] }` is untouched.

The client consumes that reach through exactly one mechanism,
`OrgUnitScope.reachesOrgUnit(orgUnitId)` for reads and
`OrgUnitScope.canWriteAt(orgUnitId)` for writes — both a flat membership test
across the Grants' own `orgUnitIds`. Home's count uses the first;
`WorkOrdersScreen.canAssignWorkOrder` becomes a `bool Function(String
orgUnitId)` the router wires to `canWriteAt`, evaluated once per row. Neither
call site keeps its own coarse read.

The descendant walk stays on the server. The server already owns it —
`target.path <@ granted.path` is what "a Grant reaches downward" *means* in
this codebase — and the client never has to parse an `ltree` path or know that
one exists.

## Why not the alternatives

**A server-side scoped count was rejected — the acceptance criteria force the
other shape.** Home's number could be answered by a new endpoint that counts
unassigned Work orders within the caller's Grants, but `canAssignWorkOrder` is
a per-record question: may I act on *this* Work order? A count cannot answer
it. If the count came from the server and the affordance came from ancestry,
the two call sites would be back to using two different mechanisms — exactly
what the criterion "uses the same mechanism rather than keeping its own coarse
read" exists to prevent. Only the client knowing which Org Units a Grant
reaches can serve both, so the mechanism is settled by the criteria,
independent of how #72–#80 shaped their list reads.

**Handing the client raw `path` strings to prefix-match was rejected.** It is
the same information in a form that moves a rule the server owns into Dart:
the client would have to know `org_units.path` is a dotted chain of ids, that
containment is a prefix test, and that the encoding is stable. It would also
need each Work order's own path, which the wire does not carry. Keeping the
server's resolved id list makes the client's question a set membership test
and leaves the tree semantics in one place.

**Returning descendants *excluding* the granted unit was rejected.** The
granted unit is always inside its own reach, and a list that omitted it would
force every caller to special-case "or the row's own id". Including it costs
one array entry per Grant and makes `reachesOrgUnit` and `canWriteAt` a single
`contains` with no branch.

## Consequences

**`/me`'s payload grows by the caller's own Grant subtrees.** This is bounded
by the Account's Grants, not by the Site, and it is computed once per `/me`
call alongside the Grant rows it already fetched (`/me` runs on every session
resolution). A deeply-granted Account gets a larger response than before; an
administrator's is unchanged, since an administrator holds no Grant rows. If
this ever becomes a real cost, a `?fields=` projection is the honest fix, not
a return to a coarse read.

**`canWriteSomewhere` survives, deliberately.** It still answers the
screen-level question "does this Account hold a write Grant anywhere at all",
which is what the raise affordance and the Work order dialog address gate
read. What changes is that `canAssignWorkOrder` no longer borrows it for a
per-record question; the two are now used for the two different questions they
actually answer. The Work order dialog address's own `permitted` gate stays
coarse on purpose: it refuses a caller with no write Grant anywhere before a
row is even resolved, and the server remains the real gate for the row's own
Org Unit.

**Home's scoped wording is corrected, not removed.** The number now includes
everything beneath a Grant, so "not what sits beneath them" is no longer true
and is gone; the card says "On the Org Units granted to you, and everything
beneath them" for a scoped Account, because the number is complete across
*their reach* while an administrator's is complete across the Site.

**No migration.** The reach is derived on read from `org_units.path`, which
the baseline already provides and indexes; nothing is stored.
