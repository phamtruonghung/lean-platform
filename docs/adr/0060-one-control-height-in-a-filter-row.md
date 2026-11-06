---
status: accepted
---

# A filter row has one control height, and it is the field's

Date: 2026-11-06

The owner reported this on `/actions`: "the height of those elements is not
equal, the drop box is always higher than the others". The row he was looking
at is a `Wrap` at `Spacing.md`/`Spacing.sm` holding three kinds of control — a
`DropdownButtonFormField` with `isDense: true` and a `labelText`, an
`AppFilterField`, and `OutlinedButton.icon`s that open a picker — and the three
do not agree on a height:

| control | 1x | 1.5x | 2x |
|---|---|---|---|
| labelled dense outline dropdown | 56 | 68 | 80 |
| `AppFilterField` (helper in the input) | 76 | 88 | 100 |
| `AppFilterField` (helper as a caption) | 56 | 68 | 80 |
| `OutlinedButton` / `TextButton` | 48 | 48 | 48 |

All four figures measured on the pinned SDK, in a `MediaQuery` text scale, with
`tester.getSize`. Two things cause it. A labelled outline field reserves a line
for its floating label on top of its content, and Material's own button height
is a fixed 48 that does not follow the reader's text size at all. Centred in the
`Wrap`, the field stood 8px proud of the buttons at 100% text and 32px proud of
them at 200%. `AppFilterField` added a third case: a `helperText` handed to the
input's own decoration grows the bordered box to fit it, so the field that names
what to type was 20px taller than the dropdown beside it.

The row was also being levelled by hand, per Screen:
`OutlinedButton.styleFrom(minimumSize: Size(AppTouchTarget.min, AppTouchTarget.min))`
appeared in the filter rows of `work_orders`, `tier_board`, `complaints`,
`supplier_ncrs`, `nonconformances`, `slide_show` and a dozen dialogs — one
number, copied, and forgotten wherever it was not copied.

## The decision

**One height for a filter row, and it is the labelled field's: 56 at a text
scale of 1, plus 24 logical pixels for every 1.0 of text scale above that.**
`AppFilterRow` (`frontend/lib/widgets/app_filter_row.dart`) states it once, as
`AppFilterRow.controlHeight(context)`, and gives **every child that height as a
`minHeight` floor**. A floored child is never squeezed, so nothing is clipped:
the dropdown is already that height, and the buttons are raised to meet it
rather than the field being flattened to meet the buttons.

**The floor is a floor, not the height.** The theme (`theme.dart`) now sets
`AppTouchTarget.min` (44) as `minimumSize` on the outlined, filled and text
button themes and as `constraints.minHeight` on the input theme — one number,
once, instead of twenty `styleFrom` copies. That is what makes the per-Screen
`minimumSize` hacks deletable. It is not the row's height: Material's tap floor
is a *minimum* a control may be hit at, and a labelled field needs a label line
above it.

**The row aligns at its top edge, not its centre.** `WrapCrossAlignment.start`,
because a control that carries a caption below its box (`AppFilterField`'s
helper, its "Showing 3 of 340" line) would otherwise be centred and drop its box
by half the caption's height — misaligning precisely the thing being levelled.

**`AppFilterField`'s helper is a caption under the box.** It was in the input's
`helperText` slot, which grows the bordered control; below the box it is still
disclosed (it is also in the `Tooltip` over the field) and the box is the row
height. Its count line already worked this way.

**`AppToolbar` composes `AppFilterRow` for its filters and lays its actions to
the same height**, so the 20 registers that already use the toolbar got level
rows without a per-Screen edit, and the buttons at the far end of a wide toolbar
sit level with the dropdowns they narrow. The rows that are still their own
`Wrap` (the Action log, the CAPA list, the KPI review, the tier board, the four
Quality registers, the slide show) now use `AppFilterRow` directly.

## The alternatives, and why they are not this

- **44 everywhere** (the tap floor, and the number this card was briefed with).
  Measured: a labelled outline field forced to 44 (or 48) holds its value text
  only by letting the floating label run through it once the text scale passes
  1.5 — at 2x the value text alone is 48 tall. That trades an 8px misalignment
  for a filter value a reader at 200% text cannot read, which is exactly what
  `test/palette_text_scale_sweep_test.dart` exists to refuse.
- **The theme alone.** `ThemeData` is built without a `BuildContext`, so it
  cannot know the reader's text scale; and Material's button height does not
  scale while the field's does. Two families, two curves: no static theme value
  can meet both at every scale.
- **A hard height instead of a floor.** `SizedBox` around every child would clip
  a `Column` that carries a caption (the field's helper and count line) and any
  caller's control taller than the row. A floor cannot.
- **Per-Screen sizing**, the status quo: twenty copies of one number and rows
  that disagree where it was forgotten.

## What follows from it

- A filter row is 8px taller at 100% text than it was (a button is 56 rather than
  48), and proportionally taller again at 200%. Sixteen goldens were re-blessed
  with this card: `app_toolbar_wide/wrapped`, the six Work orders screens, and
  the eight sweep shapes that draw a register, a board, a matrix or a state.
  Neither the sweep's form nor its detail shape changed — dialogs and forms are
  untouched (a `helperText` inside a *form* input is still a line inside the box,
  where there is no row to level).
- Every control in a filter row is that height, including a `FilterChip` toggle,
  which is therefore a taller pill than a chip elsewhere on a page. That is the
  one height taken literally; a chip is a filter control in a filter row.
- The number is Material's, not this Platform's. `test/app_filter_row_test.dart`
  compares `AppFilterRow.controlHeight` against a bare labelled field's own
  rendered height at five text scales, so a Material change that moves the metric
  fails a test that names it rather than quietly clipping a row.
- A Screen that cannot use `AppFilterRow` states why on the card rather than
  shipping a local patch; form dialogs (a button under a field, not beside one)
  are deliberately out of this decision.
