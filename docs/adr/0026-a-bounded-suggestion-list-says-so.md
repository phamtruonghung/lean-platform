---
status: accepted
---

# A bounded suggestion list says so

Date: 2026-09-13

`AppSearchField` (ADR-0023) renders at most ten suggestions even when a
caller's fetch returns more, and until now it rendered them with no sign that
it had stopped. Before #130 the Org Units search showed its own results panel,
which carried a truncation notice driven by the server's `ORG_UNIT_SEARCH_LIMIT`
(plant.js, 50); #130 replaced that panel with `AppSearchField`, which has no
such slot, and the notice went with it. A person typing a two- or three-
character term into a large plant then saw ten Org Units with nothing on screen
saying the rest existed, and could not tell whether the unit they wanted was
absent or merely past the tenth row. The same gap applies in principle to the
Directory (#128) and the Employee link picker (#129), whose fetches also carry
a `limit`.

The question is not whether to raise the cap — ADR-0023 sets it at ten on
purpose. It is whether the widget tells the person it was cut, and how it
knows.

## The decision

**The widget says so whenever it is showing fewer records than its caller's
fetch returned.** `_issueFetch` compares the fetched list's length against
`_maxSuggestions`; when it is longer, the suggestion box carries a footer —
"There are more matches than are shown — keep typing to narrow the list." —
below the ten rows it renders.

The widget is the right owner because it is the thing doing the bounding: it
already knows, with no new input, that it discarded part of what it was given.
The footer is therefore uniform across all four call sites (Directory, Org
Units, Employee link picker, Site timezone) for free, and no caller has to
remember to report anything.

## Why not the caller reporting truncation

The alternative was to let a caller mark its own result set as truncated, so
the server's `ORG_UNIT_SEARCH_LIMIT` probe could drive the message and say
"more than fifty" rather than "more than these ten". It was rejected for this
ticket because it costs an interface every caller must satisfy to report a
bound that, in practice, never binds differently from the widget's own:

- The Org Units search's server bound (50) is far above the widget's (10), so
  whenever the server would report truncation the widget has already fetched
  more than ten rows and reports it anyway. `OrgUnitSearchResult.truncated`
  stays parsed off the wire and stays unrendered, deliberately: it would only
  change the picture if the server's bound ever fell at or below ten.
- The Directory and the Employee link picker fetch with a `limit` equal to the
  widget's cap, so their server bound *is* the widget's bound; a truthful "more
  than fifty" is not available to them at all without over-fetching or adding a
  probe. Giving them a signal by widening their `limit` by one is a change to
  each caller, not to this widget, and belongs with whatever asks for it.

If a later caller's server bound genuinely falls below ten — or a caller can
tell the person *how many* more there are and that number is worth showing —
the explicit field can be added then, against that need. The footer's own copy
is deliberately count-free so that adding a count later is an enrichment, not
a correction.

## What this costs

The message says "more matches than are shown", not by how much. That is a
real reduction from what a server-driven message could say, and it is accepted
because the harm the ticket names — a person cannot tell absence from being
past the cap — is answered by knowing more exist and being told to narrow. A
person who needs the exact count is searching too broadly to be helped by it.

The footer is only shown while the suggestion list is. Collapsing the list (a
pick, #144; a submit, #128; typing below the minimum length) clears it with
the rows it described, so nothing is left claiming more matches behind an empty
box.
