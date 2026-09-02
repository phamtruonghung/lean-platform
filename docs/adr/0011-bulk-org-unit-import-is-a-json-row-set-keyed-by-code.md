---
status: accepted
---

# Bulk Org Unit import is a JSON row set, rows keyed by code, validated whole and applied in one transaction

Date: 2026-09-02

Issue #12 ("Bulk Org Unit import") asks for an administrator to import an Org
Unit hierarchy "from a file" in one call, rather than building it a row at a
time through `POST /sites/:siteId/org-units` (issue #7). That existing route
already does everything a single Org Unit create needs — validation, the
`(site_id, code)` uniqueness, Org Unit scope on the parent (issue #8) — so
this issue is not a new way to create one Org Unit, it is a new way to submit
many at once, several of which may not exist yet even as each other's
parents. Four decisions define the shape that took: what "a file" means over
this API, how a row not yet in the database names its own parent, what
"applies none of it" means operationally, and how scope is decided per row
rather than once for the whole request. None of the three existing Org Unit
ADRs (0006 modules, 0008 entry points, 0010 assignment scope) covers a
multi-row write, which is why this is recorded separately.

## The decision: a JSON body of rows, not a file upload

`POST /sites/:siteId/org-units/import` takes a JSON body,
`{ "orgUnits": [ {...}, {...} ] }`, the same content type and body-parsing
path (`express.json()`) as every other write route in this Module. This is
"a file" in the sense the issue's user story means — a spreadsheeter
preparing a hierarchy offline and submitting it in one call — without adding
a second request shape (`multipart/form-data`) or a CSV parser to a codebase
that has needed neither so far. A JSON array of objects already gives every
value its own type: an integer `sortOrder` is not a quoted string a CSV
column would hand back, and a `null` `parentCode` is not the three characters
`"null"` — exactly the ambiguity a hand-rolled CSV reader would otherwise
have to resolve itself. Turning an actual uploaded file (`.csv`, `.xlsx`)
into this JSON shape is left to whatever produces the request — the Flutter
app or a script — the same way this Module already leaves "how did an
Account's bearer token get onto the request" to the client, not to this API.

## The decision: rows reference their parent by `code`, not by id

A file has no database ids to give — the whole point of importing a
hierarchy is that most of it does not exist yet. Each row instead carries a
`parentCode`, resolved against two things at once: the `code` of another row
*in the same payload* (so a whole new branch, several levels deep, can be
described in one call), or the `code` of an Org Unit that already exists at
this Site (so new rows can be attached under an existing branch).
`org_units.code` is already unique per Site (`org_units_code_unique`, the
baseline), so it is a name a spreadsheet can carry without ever having seen
an id — the same reason `code` rather than `id` is already how this Module's
own uniqueness constraint is expressed. A `parentCode` of `null` or omitted
names a root row: the start of a new branch, exactly as a `parentId`-less
`POST /sites/:siteId/org-units` already means.

## The decision: validate every row, apply none of it on any failure

Every row is checked before any row is written — missing or blank `code`/
`name`, an unknown `unitType`, a non-integer `sortOrder`, a duplicate `code`
within the payload, a `code` already at this Site, a `parentCode` matching
neither a payload row nor an existing Org Unit, and a cycle among payload
rows (including a row naming itself as its own parent). All of these are
collected in one pass — never fail on the first bad row — and returned as a
`422` with one entry per offending row (`row`, the 0-based index in the
submitted array; `field`; `message`), so a spreadsheeter can fix every
problem before resubmitting rather than discovering them one at a time. A
malformed envelope (`orgUnits` missing, not an array, or empty) is a `400`
instead: there is no row to report on, only a request that never named any.
Once every row passes, the whole payload is applied inside one
`withActor(...)` transaction, parents inserted before children in
topological order — never `plant.createOrgUnit` per row, since that function
opens its own transaction on each call and would leave a half-built plant
behind on whichever row failed. Any failure at any stage, structural,
scope, or a write itself, leaves the database exactly as it was; `422`,
`403`, and a rolled-back transaction are the only three ways this route ever
ends without every row having been created.

## The decision: scope is decided per row, not once for the whole request

Issue #8's scope rule (a grant reaches an Org Unit and everything beneath it,
`authorization.canAct`) and its root-creation special case
(`requireOrgUnitCreateScope`, only an administrator may start a new branch)
both already exist for a single-row create. A bulk import does not get a
weaker version of either: a root row (no `parentCode`) requires the
administrator role, a row parented to an existing Org Unit requires write
scope on it, and a row parented to another payload row inherits whatever
that chain of payload rows ultimately anchors on. This is decided only after
every row has already passed structural validation, so the caller never
learns "you may not do part of this" before "part of this is malformed" —
and if any row fails, the whole import is refused with the same `403` body
(`OUTSIDE_GRANTED_ORG_UNITS`) `requireOrgUnitScope` and
`requireOrgUnitCreateScope` already return, with nothing applied.

## Consequences

`plant.js` now exports `UNIT_TYPES`, `ORG_UNIT_COLUMNS`, `toOrgUnit` and
`mapOrgUnitWriteError` — previously private to that file — so
`org-unit-import.js` can insert every row itself, inside its own single
transaction, using the same column mapping and write-error translation
`createOrgUnit` uses, rather than duplicating either or reopening a
transaction per row. Both files still hold their existing boundary
otherwise: `plant.js` stays unaware of scope and of HTTP, and
`org-unit-import.js` stays a Module-internal service, not re-exported from
`index.js` (ADR-0006). A future bulk-write route facing the same "rows
reference each other, not yet in the database" problem should default to
this same shape — a natural key the rows already carry, validated whole
before anything is applied — rather than inventing a client-side id scheme
of its own.
