---
status: accepted
---

# Root-level Org Unit browsing returns a scoped caller's entry points, not the Site's roots

Date: 2026-09-02

`GET /sites/:siteId/org-units` with no `parentId` used to answer one question
regardless of who asked: the Site's root Org Units, filtered per-row to what
the caller may act on (issue #8). For a non-administrator granted a deep Org
Unit — a supervisor granted their own line, several levels under a Site's
root — that filter removes every row: a grant reaches downward only
(`canAct`'s `target.path <@ granted.path`), so none of the Site's roots is at
or beneath a grant that starts further down the tree. The caller gets an
empty list. Their own branch of the tree is real, and `GET /org-units/:id`
and `/subtree` both honour it the moment they know its id, but browsing down
from the Site — story #29, "As a supervisor, I want to browse the Org Unit
tree, so that I can navigate from a Site down to a work centre" — is a dead
end for exactly the Account Org Unit scope is meant to serve. Issue #24
raised this as a consequence worth deciding deliberately rather than by
default, and it changes the endpoint's contract, which is why it is recorded
here rather than as a comment on the issue.

## The decision

For a non-administrator calling at the root level (no `parentId`), the
endpoint now returns that caller's **entry points** into the Site's tree:
every Org Unit in the Site the caller holds any grant on — read or write
alike — that has no *other* granted Org Unit of theirs as a proper ancestor.
An administrator's root-level view is unchanged: the Site's root Org Units,
unfiltered, exactly as issue #8 left it. Any call that passes an explicit
`parentId` is also unchanged, for both roles: the named Org Unit's direct
children, filtered per-row via `canAct` for a non-administrator.

This is a strict generalisation of the old root-level behaviour for a
non-administrator, not a fallback bolted onto it. An Account granted a
Site's own root Org Unit has exactly one entry point — that root, since
nothing else the Account might also hold could be its ancestor — so it gets
back exactly what it always did. What changes is the case issue #8 left
unhandled: a deep-only grant, and the quieter case of a grant on one root
plus a deep grant under a different, ungranted root, which previously
surfaced only the first.

## Overlapping grants: topmost only

An Account can hold two grants where one is a descendant of the other — a
line and, separately, a cell beneath it. Returning both as entry points would
be redundant: reaching the cell by walking down from the line was already
possible before this change. The decision is to return only the topmost of
any such chain, computed with a `NOT EXISTS` check for another granted Org
Unit that is a proper ancestor of the row in question. Each entry point is
therefore returned exactly once, and no entry point is ever also reachable by
walking down from a different entry point in the same response.

## Why the split between authorization.js and plant.js

`authorization.js` is deliberately a pure boolean/id-decision module (see its
own file header) and does not format domain rows — that is `plant.js`'s
column mapping (`ORG_UNIT_COLUMNS`, `toOrgUnit`), private to that file per
ADR-0006's Module boundary. Handing `authorization.js` this feature whole
would force one of: exporting `plant.js`'s private mapping (breaking that
file's own boundary), duplicating it (a second place to keep the row shape in
sync), or an N+1 lookup that matches none of this codebase's existing
one-query list patterns.

The decision instead splits the work along exactly that seam:

- `authorization.grantedEntryPointIds({ account, siteId })` answers "which
  Org Unit ids are this Account's entry points into this Site?" with the one
  query above (the `NOT EXISTS` dedup included) and returns a plain array of
  ids — no formatted rows, no ordering, staying a decision module. It does
  not special-case an administrator: whether an administrator ever asks this
  question at all is left to its caller.
- `plant.listOrgUnitsByIds(ids)` answers "what do these ids look like?" — an
  ordinary, caller-unaware read using the same column mapping and the same
  `sort_order, name` ordering as `listOrgUnits`, over `WHERE id = ANY($1)`.
- `plant-routes.js` composes the two in the root-level, non-administrator
  branch of the existing handler: ids from the first call, rows from the
  second. Two indexed queries total, never a row-at-a-time N+1.

Both modules' stated boundaries hold: `authorization.js` still never shapes
an HTTP-facing row, and `plant.js` still never knows who is calling or why a
particular set of ids was asked for.

## Consequences

A client can no longer assume a root-level row's `parentId` is `null` — for a
non-administrator, a root-level entry point can be several levels deep, and
its `parentId` is whatever its real parent's id is. A client that already
treats each row as "call `?parentId=<id>` to go one level down" needs no
change; one that inferred "root" from `parentId === null` does.

`requireSiteScope`'s existing 404-before-403 gate is untouched: a Site that
does not exist is still a 404, and a Site the caller holds no grant in at all
is still a 403 at the gate, before this endpoint's own per-row logic ever
runs. An Account with a grant somewhere in the Site now never sees an empty
200 at the root level purely because of *where* in the tree that grant
happens to sit — the failure mode issue #24 exists to close.
