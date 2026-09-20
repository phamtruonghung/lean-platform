---
status: accepted
---

# Safety authority is held on a Grant, not on a role

Date: 2026-09-20

The Safety Module (#223) has decisions only some people may take: classify an
injury — who was hurt, the injury type, the body part — set or correct an
incident's severity, record the days it cost, and close it. ADR-0035 already
settled this exact question for Quality authority — grant a Concession,
reopen a Non-conformance, open a CAPA, verify one held — and nothing about
Safety changes the reasoning: a Grant carries `can_write` and, since #204,
`quality_authority`; no check anywhere reads a role beyond `admin`.

## The decision

A Grant carries a second, separate authority flag — `safety_authority`,
alongside `can_write` and `quality_authority` — reached downward like any
Grant (`canAct`). Safety authority does not imply write and write does not
imply Safety authority; an administrator holds it everywhere, as with every
other check. Recording an incident or an observation needs only an edit
Grant, and needs no authority (#223's own rule).

Safety authority is also independent of Quality authority. Neither implies
nor excludes the other: a Grant may carry either, both or neither, in any
combination with its level. The two questions — "may this Account accept bad
product here" and "may this Account close a safety incident here" — are
asked of the same Account for unrelated reasons, and folding one into the
other would make an administrator hand out an authority nobody asked for
whenever they meant to hand out the other.

## Why not a Safety role

Rejected for exactly ADR-0035's own reasons, restated because they hold
unchanged for a second Module:

- **A role is plant-wide, and an Account holds exactly one.** A
  `safety_officer` role would let a safety officer on Line 2 close an
  incident on Line 5 — the same authority-follows-a-place argument ADR-0035
  makes for Quality, now made for Safety. It would also collide with
  whatever else that Account already is: a line supervisor who is also the
  safety contact for their own line could not be both a `supervisor` and a
  `safety_officer`.
- **The `engineer` role plus a write Grant, or any write Grant.** Rejected
  for the same reason ADR-0035 rejects it for Quality: whoever may record
  work on a line would also be who may classify its injuries and close its
  incidents, which is exactly the separation of duties a safety programme
  needs between doing the work and judging what happened.

Nothing here is new. The point of applying ADR-0035's pattern a second time
rather than inventing a variant of it is that a Grant is already the record
of "who may act where", and a second Module needing its own additional
standing on top of the level is not a reason to reach for a different
mechanism — it is the same fact (an authority belongs to a place) asked
about a second kind of authority.

## Why not generalise to an authority set now that there are two

`app_user_org_units` now carries three independent booleans — `can_write`,
`quality_authority`, `safety_authority` — and it would be tidy to replace the
last two with a single `authorities TEXT[]` or a join table keyed by an
authority code, so a third Module would not need its own migration and its
own `canAct` option. That generalisation is deliberately not made here.

Two is not yet a pattern. Rewriting `quality_authority` into a generalised
shape now would touch a Module that shipped last week — its migration, its
`canAct` clause, its Approval writer, its `/me` response, its Accounts
Screen rendering, and every test covering all of that — for no change in
what any caller can observe: the behaviour before and after is identical,
only the storage shape differs. That is exactly the kind of rewrite this
codebase's own conventions warn against taking on without a concrete need
driving it, and "a third Module might want one eventually" is not a concrete
need.

**The third authority is the trigger to revisit.** If a third Module ever
needs its own standing on a Grant, two prior columns built the same way is
real evidence of a pattern — two data points, not one — and is the moment to
ask whether a generalised authority set pays for itself against a third
one-off column and a third `canAct` option. This ADR records that trigger
explicitly so the next person to add an authority finds the decision here
rather than only finding two columns and having to guess whether they were
an oversight or a choice.

## Consequences

`app_user_org_units` gains `safety_authority BOOLEAN NOT NULL DEFAULT FALSE`
(migration `1800700000000`), independent of `can_write` and
`quality_authority`. `canAct` (`modules/people/authorization.js`) gains a
`safety` option beside `write` and `quality`, additive with both.
`approveAccount` (`modules/people/service.js`) — the one writer of a Grant —
sets and replaces `safetyAuthority` exactly as it already does
`qualityAuthority`: Approval sends the whole Grant set and the whole set
replaces what was there, so a later Approval that omits the flag removes it.
`/me`'s `orgUnitScope.grants[]` and the Accounts Screen's Grant listing both
report it beside Quality authority, and the Org Unit picker gives it through
its own checkbox on the Granted row, independent of the Quality authority
checkbox beside it.

Nothing in the Safety Module consumes the flag yet (#223 is a spec, #224 and
#228 are where classification and closure actually check it) — this ticket
is the standing itself, proven over HTTP through Approval, `/accounts` and
`/me`, exactly as ADR-0035 proved Quality authority before anything read it.
