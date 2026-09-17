# How a Screen is laid out

Three rules, two traps, and where each rule is enforced. Short on purpose: the
widgets and the tests are the detail, and this file exists so the next agent does
not have to infer the conventions from twenty-five files.

Written after #193, where a page frame that shrink-wraps put `/stores`' title and
description 142px right of the card under them, and a `Column`'s default alignment
pushed `/skills`' rows 43px into their own card. Both are Flutter defaults that
nobody decided — which is why the rules below are the ones worth stating, and why
two of them are enforced by tests rather than by review.

## 1. A page's content is one `AppPageFrame`, and it starts at one left edge

A Screen lays its title, description, controls and list inside
`AppPageFrame` (`lib/widgets/app_page_frame.dart`), wrapped in the Screen's own
`Center` so a 900px page sits centred in a wider window:

```dart
Center(
  child: AppPageFrame(
    maxWidth: SomeScreen.maxWidth,   // itself `AppLayout.pageWidth` unless the page is a table or a board
    child: ListView(padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl), ...),
  ),
)
```

The title, the description, the first card and the first row's own text all begin
at the frame's left edge plus the page's own inset (16, or 24 on Home).

## 2. A card of rows is `AppListCard`, or a `Card` whose column states its alignment

`AppListCard` (`lib/widgets/app_list_card.dart`) is the card a catalogue's rows
sit in: a hairline between rows, none around the outside, and **no wrapper around
each row**, so every row keeps its own `Key` where a test can find it.

A card that is not a catalogue — a detail Screen's Tasks or Labour section — is a
`Card` whose `Column` states its `crossAxisAlignment`. `stretch` is the usual
answer, because it gives each row the card's full width.

## 3. A search control is one of the two shared ones

- **`AppSearchField`** (`lib/widgets/app_search_field.dart`, ADR-0023) — suggests
  records it *fetches*, and reports a pick. It is for **choosing a value** the
  system knows the set of: a form field, a picker.
- **`AppFilterField`** (`lib/widgets/app_filter_field.dart`, #187) — narrows rows
  the caller **already holds**, and reports only the term. It is for **finding a
  record** in a list or a register, and it issues no request.

A set already read in full is filtered in the client. A set the server bounds is
narrowed by the server, or the client says it is bounded (ADR-0026).

**A picker reaches for `AppSearchField` or for a dropdown by the size of the set,
not by taste** (issue #190, #191's counterpart). A set a person cannot scan —
every Asset at a Site, the whole parts catalogue, every Employee in the plant,
the Skills or Job plans catalogue, a Site's Stores — is a search box whose
`fetchSuggestions` filters the list the caller already read, in memory, with no
`search` parameter added to any endpoint. A fixed, enumerated set of under a
dozen values — a work type, a priority, a meter type, a criticality, an urgency,
a unit of measure, an interval basis, the source of a parts booking, a
proficiency level — stays a `DropdownButtonFormField`, because a search box over
eight rows is a worse control than a menu.

**The trigger: a list that can outgrow a screen gets a filter** (#191). A register
whose rows a reader has to find by name carries an `AppFilterField` above its
rows — the sixteen Screens that sweep covered are the Work order register, Assets,
the triage and my-own Requests, PM schedules, Meters, Job plans, Downtime, the
Parts catalogue, Stores, one Store's stock, Accounts, the Approval queue, Job
roles, Skills and Skill coverage. Such a box narrows over the fields that identify
each record (its name, its code, its number, and for a Work order its summary and
its Asset), sits with the Screen's other controls at the page's own `Spacing.lg`
padding, and owns its term in the Screen's own `State` — a filter is a view of the
rows a Bloc already holds, so it is a `setState` and never a Bloc event. A term
matching nothing renders `PlatformEmptyState.noneMatched`, never the Screen's own
"there is nothing here" state.

**The Screens that deliberately do not, so the seventeenth register is not argued
about.** The Actions list (`ACTION_LIST_LIMIT`) and the Org Unit search
(`ORG_UNIT_SEARCH_LIMIT`) are bounded by the server: a client filter over that
page would answer "no such record" for one that exists further down the server's
own order. Actions keeps its server-side filters. The Directory and the Org Units
tree keep their `AppSearchField` (ADR-0023) — a control that reports a pick is not
a control that narrows a list a reader is working through. **The CAPA list
(#211) joins them for the same reason**: it is bounded by `CAPA_LIST_LIMIT`, and
its Org Unit filter, its status chooser and its overdue switch are all answered
by the server, so a term typed over the page it received would report "no such
investigation" for one the server put further down its own order.

## The two traps behind all of it

1. **A container sizes itself to its child, not to the space it is given.** A
   `Center` around a `ConstrainedBox` does not make a wide box; a `Column` of
   `Text`s is as wide as its longest line. Put the two together and a page whose
   content is only a title, a description and a button shrinks to the width of its
   own sentence and floats to the middle — and it only *shows* on pages whose
   content does not happen to contain something that forces a width (a table, a
   `ListView`, an input). `AppPageFrame`'s `SizedBox(width: double.infinity)` is
   what removes the possibility.
2. **`Column`'s cross-axis default is `center`.** Any child that sizes to its own
   content — a `Wrap`, a short `Row` — is centred inside it. `Wrap` never stretches
   a partly-filled run either, which is the same trap in a second place: a row of
   cards in a `Wrap` leaves the last row ragged unless it is chunked into `Row`s of
   `Expanded` cells, which is what Home's grid does.

## Where each rule is enforced

| rule | enforced by | fails when |
|---|---|---|
| page frame | `test/layout_rules_test.dart` | a `*_screen.dart` states its own `ConstrainedBox` `maxWidth` (other than the centred cards' 400/460) |
| card alignment | `test/layout_rules_test.dart` | a `Card`'s direct child is a `Column` that does not state `crossAxisAlignment` |
| one left edge | `test/page_alignment_test.dart` | a page's title, description, first card or first row's text is not where the rule says |
| Screen coverage | `test/page_alignment_test.dart` | a new `*_screen.dart` is neither audited in that file's table nor excluded there with a reason |
| a form picker finds a record | `test/form_pickers_test.dart` | one of the eleven pickers is no longer an `AppSearchField`, issues a request as a term is typed, stops showing its label, its record, the no-match state, or stops gating submission on a pick |

**The layout rows are ordinary `flutter test` files**, so `npm`-free CI runs them
with everything else. They are *source* tests rather than widget tests — the
exception `theme_skeleton_test.dart` already is, and for the same reason: what is
asserted is a property of the code, not of one rendered tree. The picker row is
the opposite case and is a **widget** test: what it asserts — a term typed, a
record picked, a body posted, a gate still closed — is behaviour, and behaviour
is only visible in a rendered tree (AGENTS.md §5's frontend seam).

## What is deliberately not a rule

- **One shared page *header*.** Screens compose their titles and actions
  differently (a `Row` with an `Expanded` column, a `Wrap`, no description at all).
  Nothing has broken because of that; #193 records it as an exclusion.
- **Page widths.** The Work orders table, the maintenance registers, the Action log
  and the tier board are wider than `AppLayout.pageWidth` on purpose, and the two
  detail Screens are narrower. Each names its own number. **The CAPA report
  (#212) joins the wider list at 1100** — it is a document with two Why chains,
  three kinds of measure and a table of evidence on it, so it spends the
  registers' own width rather than the catalogues' 900, and its Screen says so
  where the number is chosen.
- **Goldens for every Screen.** `test/GOLDENS.md` scopes them to the Shell and the
  Work orders Screen: a golden per Screen fails on every ordinary content change and
  gets deleted. Geometry assertions catch this class without that cost.
- **Centred states.** `PlatformEmptyState`, `PlatformFailureState`, sign-in and
  awaiting-Approval are centred blocks on purpose, which is why the guard allows the
  400/460 widths they use.
