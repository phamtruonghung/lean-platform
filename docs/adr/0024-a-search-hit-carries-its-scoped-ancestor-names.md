---
status: accepted
---

# A search hit carries its own scoped ancestor names

Date: 2026-09-13

`GET /sites/:siteId/org-units/search` (`plant.searchOrgUnits`, issue #35)
returns each match's `ltree` `path`, and that path is a chain of **ids**
(`n<id>.n<id>`), not names. Issue #130's own disambiguation criterion needs
that path rendered as a human-readable breadcrumb, so a person can tell two
Org Units with the same name under different parents apart in the suggestion
list. Today the client cannot: `OrgUnitPickerBloc.ancestorNamesFor` resolves
each id against `nodesById`, which only holds levels the tree has already
fetched. A search hit under an unexpanded parent — the ordinary case, since
searching is what someone does *instead of* walking the tree — resolves
nothing and renders `… › …`. Two same-named units under different unexpanded
parents read identically.

Two shapes were on the table:

- **The search response carries ancestor names.** `searchOrgUnits` already has
  each row's `path`; a join back onto `org_units` returns the ancestor chain
  as `[{id, name}]` per match.
- **A batch names endpoint.** Something like `GET /org-units?ids=1,2,3` over
  the existing `plant.listOrgUnitsByIds`.

## The decision

The search response carries each hit's ancestor names, root-first, as
`[{id, name}]`, scoped by the same `path <@ granted.path` predicate the match
itself was scoped by.

## Why not the alternatives

**A batch names endpoint was rejected.** It costs a second round trip per
suggestion set, and the breadcrumb must be on screen as the suggestion list is
drawn — `AppSearchField.suggestionBuilder` is synchronous, so a second fetch
would drag loading states through a widget built to have none. More
seriously, it exposes `listOrgUnitsByIds` over HTTP. That function returns
rows for *any* id a caller names; its scope rule ("which ids may this caller
name?") would be a new authorization surface, audited on its own, on every
future caller. The search route already answers that question — and only that
question — through `path <@`. A general id-to-name lookup re-opens it.

**Returning every ancestor, unscoped, was rejected.** Org Unit *reads* are not
Grant-filtered (ADR-0009), but the search itself deliberately is, through
`path <@` against the caller's Grants. A match sits beneath a granted unit,
yet its ancestry reaches *above* that grant. Returning the raw chain would
name Org Units the search itself would refuse to return, turning the
breadcrumb into a read the endpoint otherwise denies. Ancestors are therefore
filtered by the same containment predicate: a non-administrator's breadcrumb
starts at the topmost ancestor their Grants reach, not at the Site root.

## What this costs

**Every search row grows, including for a caller that wants no breadcrumb.**
Today the Org Unit admin screen is the endpoint's only consumer, so the cost
is zero; if a second consumer appears and resents the payload, a `?fields=`
projection is the honest fix, not a second endpoint.

**One correlated `LEFT JOIN LATERAL` per matched row.** Each lateral is a
`path <@` GiST lookup (`org_units_path_idx`), and the query is already capped
at `ORG_UNIT_SEARCH_LIMIT + 1` (51) matches, so the work is bounded by the
same limit the match set already is.

**The breadcrumb is now derived from the wire, not the tree.** `ancestorNames`
on `OrgUnitNode` is populated only for search hits; a browsed node still
carries none. `OrgUnitPickerState.ancestorNamesFor` reads the node's own
field rather than looking names up in `nodesById`, so it no longer renders `…`
for an ancestor the tree has not loaded.

## Out of scope, deliberately

**The search response's `path` is unchanged.** `OrgUnitNode.ancestorIds`
still parses it for `OrgUnitPickerRevealed`, because revealing walks and
expands the tree by id. Ancestor *names* and ancestor *ids* answer two
different questions — what to write above the hit, and what to expand to
reach it — and the reveal's own `rootIds` trimming (ADR-0008) is a property
of the ids, not the names.

**Showing an Org Unit's code as the disambiguator.** `org_units_code_unique`
(ADR-0011) already guarantees a per-Site unique code, and the suggestion tile
already renders it. The criterion asks for the *path*, because a code
disambiguates two rows without telling a person where they sit.
