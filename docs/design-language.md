# The Platform's design language

What a Screen is allowed to spend, in what order it lays itself out, how dense
a list of records is, and which floors no Screen goes beneath. Written down
because the pieces already exist and are right (`theme.dart`'s tokens,
`AppPageFrame`, `AppPageHeader`, `AppListCard`, the four state widgets) but the
*rules that join them* lived only in the heads and the doc comments of whoever
shipped the last Screen, and one of them was broken twice.

This file argues rather than instructs. Every number below is either read off
the code, measured from a rendered tree, or measured from the reference board
named in section 3, and it says which. Where this file describes what has
shipped and disagrees with the code, the code is right and this file is the bug.
Where it describes what a later slice still has to adopt, it says so at that line.

`docs/frontend-layout.md` is the shorter companion: the layout rules that tests
enforce. This is the wider one: the vocabulary of the look. The decision to
write it down, and the one trade it settles, is ADR-0057.

**What this card ships, and what a later slice adopts.** Issue #386 lands in
slices. Slice A wrote this document; slice B built every primitive it names, so
those are in `lib/` as of this card. What remains is each Screen's move onto a
primitive, which is that Screen's own slice. The shared names therefore sort into
three lists, and only the third is still a target.

| already in `lib/` before this card | shipped in this card (#386) | adopted by a later slice |
|---|---|---|
| `AppPageFrame`, `AppPageHeader`, `AppListCard` | `AppBreakpoints`, `AppTouchTarget` (`theme.dart`) | Work orders' register onto `AppTableHeader` / `AppTableRow` |
| `SkeletonList`, `SkeletonDetail`, `SkeletonGrid` | `AppToolbar` (`app_toolbar.dart`) | Home's private `_HomeCard` onto `AppStatTile` |
| `PlatformEmptyState.noneExist` / `.noneMatched`, `PlatformFailureState` | `AppTableHeader`, `AppTableRow` (`app_table.dart`) | a detail Screen's sections onto `AppDetailSection` / `AppSectionGrid` |
| `AppFilterField`, `StatusChip`, `DisclosingText` | `AppStatTile` (`app_stat_tile.dart`) | a form onto `AppDetailSection` plus the section 6 sticky bar |
| `AppPalette` (read as `AppColors.of(context)`), `Spacing`, `AppRadius`, `AppLayout`, `AppTypography` | `AppDetailSection` (`app_detail_section.dart`), `AppSectionGrid` (`app_section_grid.dart`) | |

**Issue #398 extends this document** with the three conventions no per-Screen
slice touches: sections 11 (dialogs), 12 (feedback) and 13 (data display), and
ships the primitives they name: `AppDialog` (`app_dialog.dart`), `AppConfirmDialog`
(`app_confirm_dialog.dart`) and `AppBanner` (`app_banner.dart`), with two further
rows in section 10's table. Section 13 names no widget on purpose. No dialog and
no Screen has adopted these yet; each Screen's and dialog's move is its own slice,
exactly as for the first list.

`_RowActions` is not in either list: it is a private widget, and there are two
of them, one in `maintenance/work_orders_screen.dart` and one in
`people/accounts_screen.dart`. Where this document says "the row's own
`_RowActions`" it means a Screen's own private widget of that shape, not a
shared one.

## 1. A word about words

`CONTEXT.md` defines **Screen**, **Destination**, **Destination group** and
**Shell**, with `_Avoid_` lists. This document uses them as defined: a Screen is
never "a page" in the domain's sense. "The page", as in `docs/frontend-layout.md`
and in the names `AppPageFrame` and `AppPageHeader`, means the *layout box* a
Screen draws into. Where both are meant, this file says "the Screen's page".

**Register** and **catalogue** are not glossary words. `CONTEXT.md` has no entry
for either (it uses "catalogue" in passing for the shared parts and KPI sets,
which is a different and looser sense). They are *pattern names* introduced in
section 6, for the two ways a list of records can be laid out, so no `_Avoid_`
list is violated by them.

A detail **section** (`AppDetailSection`) is a titled card on a detail Screen.
`CONTEXT.md`'s `_Avoid_: Section` is about the Shell's own heading, which is a
Destination group; the name here comes from the primitive and means something
else.

## 2. The three widths, measured from the Shell's own code

Every layout decision below is made against the box a Screen actually receives,
so that box has to be known first. `PlatformShell` reads
`MediaQuery.sizeOf(context).width < railBreakpoint` (700) to choose between an
expanded sidebar (`expandedWidth`, 260) and an icon rail (`collapsedWidth`, 64),
and gives everything else to `Expanded(child: child)`. The content box a page
gets is therefore:

| window | sidebar | content box the page gets |
|---|---|---|
| 700 | expanded (700 is not `< 700`) | **440** |
| 900 | expanded | **640** |
| 1280 | expanded | **1020** |
| 699 | collapsed | 635 |

Two things follow, and both are rules.

**The narrowest box the app really gives a page is 440, at a 700px window, not
700.** Nothing may treat 700 as the narrow case, and no breakpoint may be read
from the window. It is read from the box a `LayoutBuilder` hands the widget.
That was shipped wrong once: `WorkOrdersScreen` decided table-versus-cards from
`MediaQuery.sizeOf(context).width`, the same input as the Shell's rail, with
both breakpoints at 700. At exactly that window the Shell had just switched to
its 260px sidebar while the Screen concluded it still had 700px for a table. It
had 440, and the table header wrapped one letter per line (#105;
`frontend/test/GOLDENS.md` records it at length and
`goldens/work_orders_collision_700.png` holds it in place).

**The 700px rail breakpoint is a cliff.** Growing the window from 699 to 700
*shrinks* the page's content box from 635 to 440, because 260 replaces 64. That
is the Shell's decision, frozen by #99, and it is out of scope here: it is a
constraint this design has to survive, and changing it is a separate ticket.
What survives it is the rule above: a Screen that asks its own box never meets
the cliff as a surprise.

**Text size moves the box too.** At a text scale of 2.0 the same 440 box behaves
like 220 for text layout, because the text doubles and the box does not. So a
breakpoint is always multiplied by the reader's text scale, never below 1, before
the box is compared with it (WCAG 1.4.4, Resize Text). `AppPageHeader.wrapBreakpoint`
already states exactly this rule; section 10 names it once for everyone, and
`AppBreakpoints.effective` is the one helper that spends it.

## 3. The reference: what is copied and what is not

The owner's verdict on the first UI pass was that "the UI has not changed", and
what they asked for next was the information density of the MTU board: its density
and grouping only, never its CSS, fonts or colours (#386). "Dense" is undefined
until it is measured, so it was measured: the board's own deployed CSS
at `https://mtu-db.digitalciapp.com/`, read as served.

```
body{font:14px/1.45 "Segoe UI",system-ui,sans-serif; padding:12px 16px}
h1,h2{font:600 16px/1.2; margin:0}                      title 16 / body 14 = 1.14x
.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
table{width:100%;border-collapse:collapse;min-width:640px}
th,td{text-align:right;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
th{color:var(--mute);font-weight:500;font-size:12px}
.z{color:var(--mute)}                                   identifier column reads quieter
.kpi div{display:flex;flex-direction:column;line-height:1.15}
.kpi b{font-size:16px}   .kpi span{font-size:11px;color:var(--mute);white-space:nowrap}
gaps in use: 6px, 10px, 14px (and gap:6px 14px in a grid)
font-size census on the served page: 12px x8, 11px x2, 16px, 14px, 13px, 10px
```

The arithmetic that matters is the table row. `6px + a 20.3px line (14px at
1.45) + 6px` is **about 32px**. The Platform's Work orders row states
`minHeight: 56`. That 24px gap, repeated down a screenful, is the whole distance
between "the UI has not changed" and a dense board, and it is where
this document makes its one concession (section 6): a row nobody can tap is 32px,
and a row its Screen gives an `onTap` is 44 — a row that holds a control is given
one, so the control is never the only thing to press.

**Copied: the density, the grouping, the column-label band, and right-aligned
numerics.** A small ladder of gaps and a short ladder of type; related things
sharing one bordered panel; a label band that reads as a header; and figures
right-aligned so a column of them can be compared by eye.

**Not copied: its CSS, its fonts, its colours.** The board is `"Segoe UI"` on a
green-grey palette (`#f6f7f5`). The Platform keeps Roboto, which is bundled so
Flutter Web's CanvasKit never fetches a font, and its own blue palette with a
second, dark one (ADR-0056). Its 8px radius is not copied either: `AppRadius.card`
is 14, which every Screen already spends. Two numbers differ on purpose: the
board's `th` is w500, and the Platform's label band is w600 in `textMuted`, a pair
the contrast table in section 9 measures. The board's
`th,td` are right-aligned throughout; the Platform right-aligns only the columns
whose content is a quantity (section 6), because names and codes right-aligned
are read badly in a language that reads left to right.

One more number to keep honest. `theme.dart`'s own comment on `_typeScale`
reports the board's largest heading as "about 1.33x the body it reads at": that is
16 against the 12px of its table text. Against its 14px body it is 1.14x, the
figure in the CSS above. Both are true; the second is the one a heading is
compared with.

## 4. The token ladder a Screen spends

A Screen spends six things and nothing else:

1. **`AppColors.of(context)`**, which returns an `AppPalette`. `AppComponentColors`
   no longer exists: ADR-0056 replaced it, and the component bindings are now
   getters on `AppPalette` itself (`cardBorder`, `focusRing`, `rowHoverFill`,
   `tableHeaderFill`, `navSelectedBackground`, `navSelectedForeground`). A token
   is read as `AppColors.of(context).<name>`, has no fallback, and fails loudly
   under a bare `MaterialApp`.
2. **`Spacing`**: 2, 4, 8, 12, 16, 24, 32 (`xxs`, `xs`, `sm`, `md`, `lg`, `xl`,
   `xxl`).
3. **`AppRadius`**: `card` 14 and `pill` 28.
4. **`AppLayout`**: `pageWidth` 900.
5. **`AppTypography`**: `body` 16/24, `dense` 14/20, `floor` 12/16.
6. **`AppTouchTarget.min`**: 44. The constant ships in this card (#386), in
   `theme.dart` beside the rest of the ladder.

No `Color` literal, no `Colors.*`, no magic padding. `test/theme_skeleton_test.dart`
enforces the colour half by reading every file under `lib/`. The padding half is
a convention that review enforces, which is why this document names the
`Spacing` value for every gap in section 5.

**The type ladder.** Sizes are pinned role by role in `theme.dart`'s
`_typeScale`; weight and line height stay Material's.

| role | Material role | size | ratio to the 14px dense body |
|---|---|---|---|
| a Screen's title | `headlineSmall`, w700 | 18 | 1.29x |
| a section's title | `titleMedium`, w600 | 16 | 1.14x |
| body | `dense` (`bodyMedium`) | 14 / 20 | 1.00x |
| floor, labels, a lane's count | `floor` (`bodySmall`), `labelMedium` | 12 / 16 | 0.86x |
| nothing below 12 | | | |

The board's own heading ratio is 1.14x. The Platform's 1.29x is the **ceiling,
not a target**: a title earns its weight with w700 rather than with more size,
which is #372's rule. The one larger text a Screen sets is a figure, not a title:
the count on a Home tile, in `headlineLarge` (26).

## 5. The page rhythm: one order, top to bottom

```
AppPageFrame(maxWidth)                 // 900 by default; a table/board page names its own
  AppPageHeader                        // title + description + actions + hairline + `below:`
    below: AppToolbar                  //   filters · count · actions
  the body                             // AppListCard | AppTableHeader + rows | board lanes | sections
  footer actions                       // only where a page has a primary act at the end
```

`AppToolbar` ships in this card (#386). A Screen that has not adopted it yet still
composes its own filter row in that slot, at the same spacing.

Spacing is a `Spacing` value everywhere, and these are the values:

| between | value |
|---|---|
| page inset, horizontal | `Spacing.lg` (16). Home is `Spacing.xl` (24), the one documented exception |
| page inset, top and bottom | `Spacing.xl` (24) |
| header to its `below` (the toolbar) | `Spacing.md` (12). `AppPageHeader` already draws this |
| toolbar to the body | `Spacing.md` (12) |
| one card or section to the next | `Spacing.md` (12) |
| inside a card | `Spacing.lg` (16) |
| inside a register row, vertical | `Spacing.xs` (4) top and bottom = 8, around a 20px line; the row is 32 by its `minHeight`, content centred |
| inside a register row, horizontal | `Spacing.md` (12) |
| section title to its hairline | `Spacing.sm` (8) |
| a label to the figure under it | `Spacing.xs` (4) |

A note on the register row's vertical figure. The board's `6px + line + 6px` has
no 6 on the `Spacing` ladder, and this document does not add one. The row is
specified by its height (32, content centred vertically), which is what yields 6
above and below a 20px line. `AppTableRow` pads `Spacing.xs` (4) top and bottom
and floors the row at 32 through its `minHeight`, so the 6 above and below the
line is what centring a 20px line in 32 leaves, not a sum of two paddings.

**One left edge.** The title, the description, the toolbar's first control and the
first row's first cell all begin at the frame's left edge plus the page inset.
`test/page_alignment_test.dart` pins that per page, and its table is not edited to
suit a new page: a new Screen conforms to the table, not the other way round.
`AppPageHeader` deliberately owns no padding for this reason.

## 6. The body patterns

Five patterns shape a Screen's body: the register, the catalogue, the detail, the
board and the form. A Screen picks one and says so. The stat tile, last of the
entries below, is a part some of them are built from, not a sixth.

### The register: a list of records that are read across

A column-label band plus rows. This is the Work orders table, the KPI matrices,
and the shape the maintenance registers are moving towards.

**The band** is `AppTableHeader`, shipped in this card (#386). Fill
`tableHeaderFill`; a 1px `edge` hairline under it; `labelMedium` 12 at **w600 in
`textMuted`**, which measures 6.50:1 on the band in light and 6.97:1 in dark
(section 9). Sentence case, never uppercased: uppercase is the Shell's
Destination-group device, and the labels are the domain's own words ("WO#", "Org
Unit"). A band is never a row: it has no hover and no tap.

Today's `_WorkOrderTableHeader` is private to its Screen and differs from this: it
sets `colorScheme.onSurface` at w700 with 0.2 letter spacing. The row above is the
target, and Work orders adopts it in its own slice.

**A row** is `AppTableRow`, shipped in this card (#386): **32px when the row's own
`onTap` is null, `AppTouchTarget.min` (44) when it is set.** The primitive floors
the row, not the cell, so a row that holds a control is given the row's `onTap`
and the control sits inside the 44. A hairline of `edge` sits under every row.
A row that is itself the tap target (Work orders' whole row
opens the Work order) carries `rowHoverFill`, because a seven-column row's only tie
between its first cell and its action is where the pointer is. Such a row is 44,
not 32: Work orders moves from 56 to 44 and reaches the board's 32 only on a row
nobody taps.

**Alignment by column kind.** This table is a rule, not a preference:

| kind | example | horizontal alignment | style |
|---|---|---|---|
| name | Summary, Employee, Asset | start | `dense`, `textPrimary` |
| code | WO#, Code, Employee no. | start | `dense`, `textMuted` (the board's `.z`) |
| count | Qty, Hours, Days | **end** | `dense`, `FontFeature.tabularFigures()` |
| money | Cost, Rate | **end** | `dense`, tabular figures, `Spacing.sm` right inset |
| tone | Status, Priority | start | `StatusChip`, never a bare coloured word |
| action | row buttons | **end** | the row's own `_RowActions`, never a link |

Tabular figures are what make right alignment worth having: with proportional
digits a column of right-aligned numbers still wanders by a pixel or two per digit
and the eye cannot compare them.

**One column spec builds the band and every row**, so a header label and its cells
start at the same x by construction. That is the rule `test/kpi_test.dart` already
enforces for the two KPI Screens ("a header label and its cells start at the same
x"), and `docs/frontend-layout.md` section 4 states. The spec's own numbers are
`flex` weights, or a fixed `width` for a tone or action column. Work orders
measures its status column by laying out its widest status label and adding 32 and
`Spacing.sm` (`_statusColumnWidth`), and gives its action column a fixed 232. A
fixed width is reached for only where a label's length is bounded and `flex` would
make the column's edge move with the window.

**Below the table, a card per record.** A register of five columns or fewer
becomes a card per record below `AppBreakpoints.registerTable` (700) of box width.
A wider register states its own larger breakpoint and says why in its own file.
Work orders' 800 is the existing example: at 700 of box its WO# still
ellipsized, and at 750 "Assignee" and "Actions" ran together, so it chose 800 by
rendering the Screen at each width. Its location, in the Screen rather than in
`AppBreakpoints`, is a deliberate deviation, not a precedent to copy silently.

Read against section 2, this is concrete. A register measures the box it is handed
— the page's box less its inset, 32 at the `Spacing.lg` (16) each side of section
5. At a 700 window that is 408, at 900 it is 608: **both are below 700, so a
five-column register is cards at both**, and tables appear only where the box
reaches 700, which is a page box of 732 and a window of about 992 and up. Work
orders, at 800, is cards until the window is about 1060.

### The catalogue: a list of records that are read down

`AppListCard` of rows, `Spacing.lg` padding, the name in `dense` / `textPrimary`
with the code under it in `dense` / `textMuted`, the row's own controls at the far
end, and a row of at least 44px when it holds a control. **No hover fill.** A
catalogue row's affordances are its own buttons, so a hover band would advertise a
click that does nothing; `app_list_card.dart` already argues this and its comment
says not to "complete" the widget by adding one. The card draws a hairline
*between* rows and none around the outside, and wraps no row, so every row keeps
its own `Key`.

The choice between a register and a catalogue is by how the list is read. If the
reader compares a value across rows (quantities, dates, costs), it is a register
and its numerics align. If the reader finds a record by name and then does
something to it, it is a catalogue. `docs/frontend-layout.md` section 5 says the
same in shorter form, and a Screen's own doc comment names which it is.

### The detail

A summary card first (the record's identifying fields), then `AppDetailSection`s
(shipped in #386). Each is a `Card` whose `Column` states
`CrossAxisAlignment.stretch` (`layout_rules_test.dart` enforces that the column
states *something*), a `titleMedium` w600 title with an optional trailing action,
a hairline `Spacing.sm` under it, then the section's rows. **One column below 1000
of box width, two above: `AppBreakpoints.detailTwoColumn`**, and the sections in a
row share a height (`AppSectionGrid`, shipped in #386).

Against section 2 that is also concrete, once the page's inset is counted (the 32
of section 5, and 48 where the page insets `Spacing.xl`): at a 900 window the page
has 640 and the grid is handed 608, and at 1280 it has 1020 and the grid is handed
988 — 972 on a page inset 24 each side. So **a detail Screen is two-column only in
a window of about 1292 and wider, and only where the page names a frame of at
least 1032**; the default `AppPageFrame(900)` hands it 868 and never reaches 1000.
That is intended. A section is a card with a title and rows; squeezed to half of
640 it is worse than stacked.

### The board

Lanes. A lane header (the lane's name in `dense` w600, its count beside it in
`floor` / `textMuted`), then tiles `Spacing.sm` apart, each with `Spacing.md`
padding. A lane never scrolls inside a page that already scrolls: two nested
vertical scrollers is a trap on a touch screen and in a screen reader alike.

**A legend sits above the lanes**: one row, its chips `Spacing.sm` apart,
`Spacing.md` above the first lane, holding one `StatusChip` for each tone the board
actually uses, labelled with that tone's own word. It is a rule, not decoration. A
tile's fill carries meaning (a lane's own colour, a tile's tone), and a colour that
is the only carrier of an outcome fails WCAG 1.4.1, Use of Colour. The legend is
what makes the colour a second carrier rather than the only one, and it is also
what tells a reader arriving mid-shift what green and amber mean on *this* board.
It is built from the board's own tones, not from a fixed set: a board that shows
four tones shows four chips, and copying a five-chip legend onto a board that never
draws one of them is the same speculative generality `theme.dart` already refuses
for palette tokens. A tone is never invented for a legend: it comes from
`StatusTone` and renders through `StatusChip`, the same widget the tiles and the
registers use.

### The stat tile

`AppStatTile` (shipped in #386) generalises Home's private `_HomeCard`: an icon
tile (`_iconTileSize`, 40), a label, a figure, a caption. The figure is
`headlineLarge` w700 when there is something to read, and a quiet `titleMedium`
w400 `textMuted` when it is zero (`_countStyle`). The figure sits `Spacing.xs`
under its label. A quiet figure measures 7.58:1 light and 9.85:1 dark on a card
(section 9). Home's tile survives this card and is adopted in its own slice.

### The form

A section per group of fields (`AppDetailSection`, shipped in #386), a field grid,
and a sticky submit.

**One column below 900 of box width, two above: `AppBreakpoints.formTwoColumn`.**
It is a number of its own and not `AppBreakpoints.detailTwoColumn`, because a form
is not a detail page. Against section 2, the boxes it is handed are 408, 608 and
988, so **a form is one column at a 700 or 900 window and two columns at a 1280
window only where the page names a frame of at least 932** (900 of box plus the 32
inset); the default `AppPageFrame(900)` hands it 868 and stays one column at any
window. That is intended: a form is a sheet of paper, not a dashboard.

**The submit is sticky.** It is a bar pinned to the bottom of the page's own
viewport, holding the form's primary action at the inline end, and a secondary
"Cancel" or "Back" at the inline start where the form has one, and it stays in
place while the fields scroll beneath it. A long form's primary action is never
reachable only by scrolling to the end of it.

**The bar is outside the scroll view, and the scroll view pays for it.** The form's
list adds bottom padding equal to the bar's own height, so the last field is never
hidden under the bar. That is the trap this rule exists for: a pinned bar over a
`ListView` silently covers its last row, and on a form that row is usually the very
field the person was about to fill. **The bar spans the page frame, not the
window**: it is `AppPageFrame`'s own width, so a 900px form does not grow a submit
bar 1020px wide.

**It is a pattern here, not a primitive.** `AppDetailSection` already gives a form
its sections, and a submit bar has exactly one consumer shape today, so it is
specified here rather than added to the widget set. The slice that builds the first
form decides whether it earns one.

## 7. The four states, and where each is used

Every read has four outcomes, and each has one widget. A Screen that draws its own
is a Screen whose "nothing here" looks different from its neighbour's.

| state | widget | when |
|---|---|---|
| loading | `SkeletonList` / `SkeletonDetail` / `SkeletonGrid` | a read is outstanding; the placeholder has the shape of the thing that will arrive |
| empty, none exist | `PlatformEmptyState.noneExist` | the read succeeded and there is nothing yet |
| empty, none matched | `PlatformEmptyState.noneMatched` | rows exist and the reader's own filter matched none |
| failed | `PlatformFailureState` | the read failed, with the Screen's own retry |

The copy is the wording each Screen already ships; this document does not rewrite
it. A term typed into `AppFilterField` that matches nothing renders `noneMatched`,
never `noneExist`: telling a reader "nothing has been raised" when they have
merely mistyped is a false statement about the plant. The skeleton has the shape of
the arrival so the page does not jump when the read settles; a list skeleton in
front of a grid is a layout shift in disguise.

## 8. The access floors

None of these is a taste. Each has a measured reason or a standard behind it.

- **44px** minimum on every control's tap target (`AppTouchTarget.min`, shipped in
  #386). This is the one number the density work does not get to spend: the
  reference board's 32px rows are under it.
- **A semantics label on every icon-only control**; a decorative icon is
  `ExcludeSemantics`. The Home tile's chevron is the example.
- **A visible keyboard focus ring**: 2px `AppColors.of(context).focusRing`, drawn
  by swapping the card's `shape` so no pixel of layout moves, and only under
  `FocusHighlightMode.traditional` so a click leaves no ring behind. Non-text
  contrast floor 3:1; it measures 8.72:1 light and 8.11:1 dark on a card.
- **Motion of 200ms or less**, and `Duration.zero` under
  `MediaQuery.disableAnimationsOf(context)`. The ink ripple is off on any tile
  that animates (`NoSplash.splashFactory`) because it runs longer than 200ms and
  ignores that setting. Home's `_HomeCard` is the example of all three.
- **Contrast**, the table below, every pair measured.

## 9. Contrast, measured

WCAG 2.x relative luminance, the formula in `frontend/test/contrast.dart`,
computed from the hex values in `theme.dart`'s `_PrimitivesLight` and
`_PrimitivesDark`. The same computation reproduces every value that file and
`palette_contrast_test.dart` already pin (light `textPrimary` on card 10.36,
`textMuted` on card 7.58, `edge` on card 1.22; dark 13.35, 9.85 and 3.48), which
is the check that the table below is not a second, drifting calculation.

| pair | light | dark |
|---|---|---|
| a row's name cell: `textPrimary` on `card` | 10.36:1 | 13.35:1 |
| a row's code cell: `textMuted` on `card` | 7.58:1 | 9.85:1 |
| the column-label band's label: `textMuted` on `tableHeaderFill` | 6.50:1 | 6.97:1 |
| a detail section's title: `textPrimary` on `card` | 10.36:1 | 13.35:1 |
| a stat tile's quiet figure: `textMuted` on `card` | 7.58:1 | 9.85:1 |
| the focus ring: `focusRing` on `card` (non-text, floor 3:1) | 8.72:1 | 8.11:1 |
| the section hairline: `edge` on `card` (non-text) | 1.22:1 | 3.48:1 |

Text pairs clear 4.5:1 by a wide margin; the lowest is the band's label at 6.50:1.

**The last row is an asymmetry, and it is documented, not a defect.** The light
`edge` is 1.22:1 by design: a hairline that quiet is a rule between rows, never
text and never the only cue to anything. The dark one is 3.48:1. ADR-0056 records
why and `palette_contrast_test.dart` pins the light value at 1.22. This document does not "fix" it; it cites it. A rule that carries
meaning on its own (a focus ring, a selected mark) uses `focusRing` or
`navSelectedAccent`, not `edge`.

## 10. The breakpoint rule, written once

A breakpoint is a **box width at a text scale of 1**, always read from a
`LayoutBuilder`, and always multiplied by the reader's text scale (never below 1)
before it is compared. The window is never asked. The one exception is the dialog's
own pair (#398, §11): there the box is compared as it is and the text scale is a
trigger of its own, argued below.

```
effective = breakpoint * max(1, MediaQuery.textScalerOf(context).scale(1))
narrow    = constraints.maxWidth < effective
```

Named once, in one class (the last two rows were added by #398 and are the
exceptions that prove the rule: see the paragraph after the table):

| name | at 1x | decides |
|---|---|---|
| `AppBreakpoints.headerActionsWrap` | 560 | a header's actions drop under its title |
| `AppBreakpoints.toolbarWrap` | 640 | a toolbar's count and actions drop under its filters |
| `AppBreakpoints.registerTable` | 700 | a register of five columns or fewer becomes cards |
| `AppBreakpoints.formTwoColumn` | 900 | a form's field grid goes two-column |
| `AppBreakpoints.detailTwoColumn` | 1000 | a detail page's sections go two-column |
| `AppBreakpoints.dialogSheet` | 700 | a dialog becomes a bottom sheet when the box is **this wide or narrower** (`<=`) |
| `AppBreakpoints.dialogSheetTextScale` | 1.5 | a dialog becomes a bottom sheet at **this text scale or larger** (`>=`), whatever the box |

The last two rows are not like the first five. They are a pair, one dialog's
trigger: the box is compared as it is (a dialog route's box is the window, section
11), and the text scale is its own trigger rather than a factor on the box, so
`AppBreakpoints.effective` is deliberately not applied to either. Multiplying 700 by
the scale as well would count the text twice. They are pinned at their edges by
`test/app_dialog_test.dart`.

One of the first five is still named twice. `headerActionsWrap` (560) is the number
`AppPageHeader.wrapBreakpoint` already holds, and the header still computes its
own text-scale factor, so the class holds the copy that header points at until it
adopts `AppBreakpoints.effective`.

`AppBreakpoints` ships in this card (#386), in `theme.dart`; the five numbers are
named there and this section argues them (#398 added the two dialog rows). Three are pinned by a test today:
`headerActionsWrap` (560), which is the same number as
`AppPageHeader.wrapBreakpoint` and is pinned at its edge by
`test/app_page_header_test.dart`; `toolbarWrap` (640) by
`test/app_toolbar_test.dart`; and `detailTwoColumn` (1000) by
`test/app_section_grid_test.dart`. The other two are named but spent by nothing
yet: `registerTable` (700) belongs to a register of five columns or fewer, and
`formTwoColumn` (900) to a form's field grid; each is pinned by the test of the
Screen that adopts it. Work orders is deliberately not on 700: its seven columns
keep their own 800, argued in section 6, and its own tests cover both sides of
that number. Home's grid carries a private `_CardGrid.twoColumnWidth` of 640,
read from its own `LayoutBuilder`; that is the same 640 already in the class,
spent by Home's grid — and it compares without the text scale, the one place that
does not yet follow the rule above, until its own slice adopts the class.

**Why it is written once.** The bug shipped twice. #105 was the window-versus-box
confusion of section 2, in the Work orders table. #379 was the header's wrap
breakpoint not accounting for the text scale: the actions row grows with the
reader's text size and the box does not, so the same box needs the wrap sooner
(#381 then pinned that rule's edges). Each was fixed where it was found, and each
was a rule that the next Screen would have had to rediscover. The class exists so
there is one place that reads the box and one that reads the text scale. A number
is pinned by the widget that spends it, at its edge (the paragraph above names
which three are pinned today and which two wait for the Screen that spends them).

Against section 2, the five numbers sort the three common windows. Every primitive
measures the box it is handed, which is the page's box less its inset — 16 each
side by section 5, so 32 off the page box — and no more than the frame's
`maxWidth`. The "box" column below is that handover at the section 5 inset, with
the page naming a frame at least as wide as the window allows:

| window | page box | box the primitive is handed | header actions beside the title (560) | toolbar on one line (640) | register table (700) | detail two columns (1000) | form two columns (900) |
|---|---|---|---|---|---|---|---|
| 700 | 440 | 408 | no, under it | no | cards | one column | one column |
| 900 | 640 | 608 | yes | no, it wraps | cards | one column | one column |
| 1280 | 1020 | 988 | yes | yes | table | one column | yes |

Two of those cells are what the box costs. The toolbar wraps at a 900 window
because 608 is 32 under its 640; one line starts at a box of 640, a page box of
672 and a window of about 932. The detail page stays one column at a 1280 window
because 988 is 12 under its 1000, and a page that insets `Spacing.xl` (24 each
side inside the frame, as `capa_detail_screen.dart` does) is handed 972. Two
columns need a page box of 1032 — a window of about 1292 — **and a frame that
names at least 1032**: under the default `AppPageFrame(900)` every one of these
is handed 868, so `detailTwoColumn` (1000) and `formTwoColumn` (900) are
unreachable at any window until the page names a wider frame.

At 2x text every effective breakpoint doubles (1120, 1280, 1400, 1800 and 2000), so even
the 1280 window's 988 box wraps the header and the toolbar, shows cards, and stays
one column.

## 11. The dialog: four widths, one shell, and a sheet when the box is narrow or the text is large

A dialog is the one surface every Module spends and no Screen owns. Of the files
under `frontend/lib/` whose name contains `dialog` there were 113 before this card
(115 now: these two widgets' own files match the name too), and what they share is
accidental: 112 are an `AlertDialog` — the one that is not is
`platform/dialog_page.dart`, the route — 110 put a `SizedBox` directly in
`content:`, and each chose its own number.
`AppDialog` (`widgets/app_dialog.dart`, shipped in #398) is the shell they
will move onto, one slice at a time; `AppConfirmDialog` is its destructive form.
Nothing in `lib/` has adopted either yet, and no existing dialog changes in the
card that ships them.

### The four widths

| kind | width | what fits |
|---|---|---|
| decision | 420 | one question, a description, two actions, no fields |
| picker | 460 | a list or filter to choose one thing from |
| form | 520 | a short form, up to about six fields |
| wide | 640 | a long form, or content with its own columns |

A reader sizes a dialog from this table alone: say what the dialog holds, take
the width in the row. `AppDialogSize` names the four and `AppDialog` defaults to
`form`.

**Where the four come from.** The seven widths in use were counted off the tree
before this card (`grep -hoE "width: [0-9]{3}\\b"` over those 113 files, so a width
is counted once per occurrence): **420 ×34, 520 ×28, 460 ×20, 560 ×11, 480 ×10,
640 ×5, 620 ×5** — 113 occurrences at those seven sizes. The same files hold 121
`width: <n>` lines in all, the other eight being narrower 140–260 widths inside a
dialog's own column. By file rather than by occurrence, where a file sizes two
things, it is 33, 24, 20, 11, 10, 5 and 5. Seven numbers answer four
questions: 420 is the dialog that asks, 460 the one that lists, 520 the one that
asks for a few things, and the three at the top (560, 620, 640) are one dialog
drawn three ways. A 480 is a 460 or a 520 by what is in it; a 560 is a form that
has outgrown 520 or a wide that has not needed 640. That mapping is each adopting
slice's to make against the table above, by content, and when a dialog does not
fit the width it chose it moves to the next one up, never down.

**The width lives on the shell.** In 112 of the 113 the width sits on a
`SizedBox` *inside* `content:`. The `AlertDialog` around it sizes itself to that
box, so the title and the action row are as wide as the content plus the
platform's own padding, not the width the author chose; and the actions, centred
by `AlertDialog`'s default, are in a different place in every dialog.
`WorkOrderCancelDialog` is the example (`maintenance/work_order_cancel_dialog.dart:78`
is its `AlertDialog`, `:81` its `width: 480`). `AppDialog` puts the width on the
surface itself, so the title, the content and the action row share one left edge
and one right edge, and the number is measured on that surface (`AppDialog.surfaceKey`).

A dialog is never wider than its box less `Spacing.xl` a side. On a box wide
enough to be a dialog at all (701 and up) the widest of the four, 640, always fits:
701 − 48 = 653.

### The shell, top to bottom

```
title row        titleMedium, w600, textPrimary; at most one trailing icon control, 44px, with a label
description      dense, textMuted, Spacing.xs under the title (optional)
content          the only scroller; capped at about 60% of the box height
action row       pinned; never scrolls away
```

The fill is `card`, the radius `AppRadius.card` (14), a hairline of `edge` round
it, and no elevation. It is **not** an `AlertDialog`: that widget's platform
padding and centred action row are exactly what this replaces, and a shell
that is a `Dialog` with its own anatomy is one place to read rather than 112.

| gap | value |
|---|---|
| title, description and content, inline | `Spacing.lg` (16) |
| the action row, inline | `Spacing.lg` (16) |
| the action row, above and below | `Spacing.md` (12) |
| the title block to the content | `Spacing.md` (12) |
| the content to the action row | `Spacing.lg` (16) |
| the title to the description | `Spacing.xs` (4) |

The content is the only scroller, and the cap is what makes that safe: a form
that is longer than 60% of the box scrolls inside the dialog while its title and
its actions stay put, so the primary action is never reachable only by scrolling
(§6 argues the same of a page's sticky submit). `app_dialog_test.dart` pins it:
with forty 44px rows in a 600px-high window the action row's bottom edge stays at
or under 600, the content is no taller than 360, and dragging scrolls the content
and not the dialog.

### The action row

Dismiss actions sit at the inline start, a `Spacing.lg` gap, then the destructive
and the primary at the inline end. **The primary is right-most; a destructive
action is separated from it and never first.** There are three kinds
(`AppDialogActionKind`):

| kind | drawn as | `Esc` |
|---|---|---|
| `dismiss` | `OutlinedButton` | runs it |
| `primary` | `FilledButton` | never |
| `destructive` | `FilledButton`, `statusDanger` fill, `canvas` label | never |

Every action carries `AppDialog.actionKey(id)` (`app-dialog-action-<id>`), keeps
the caller's label verbatim, is at least `AppTouchTarget.min` (44) tall through its
`minimumSize`, and renders disabled when its `onPressed` is null, which is how a
caller shows a request in flight. A label that does not fit wraps inside its
button instead of overflowing the row: the dismiss group takes its natural width
up to two fifths of the row and the end group takes what is left.

**The destructive pair is measured, not chosen.** The canvas on `statusDanger`
is **6.18:1 in the light palette and 9.41:1 in the dark**. White on the dark
`statusDanger` (`#FCA5A5`) is **1.90:1**, which is why a destructive fill is never
given a white label in either palette (the light palette would pass and the dark
would not, and a theme that passes in one is how this ships), and why
`Colors.white` is not used at all. `app_confirm_dialog_test.dart` measures all
three numbers from the shipped hexes with `test/contrast.dart`.

### When a dialog is a sheet

A dialog becomes a **bottom sheet** when either trigger holds:

| trigger | name | compared |
|---|---|---|
| the box is 700 wide or less | `AppBreakpoints.dialogSheet` (700) | `box <= 700` |
| the text is 1.5x or larger | `AppBreakpoints.dialogSheetTextScale` (1.5) | `textScale >= 1.5` |

The first is the 700 §2 reads off the Shell, applied to the box a dialog is
actually handed, which is the window. The second is a trigger of its own, not a factor
on the first, because text is the thing that spends width. §2 measured the
440px box behaving like 220 at 2x, and the same arithmetic runs through a dialog:
a 520 form has 488 of usable width after its padding, which at 2x text holds what
244 holds at 1x, and a 360px phone at 1x has 328. A form dialog at 2x text has
less to work with than a phone, whatever the window. So the box is compared as it
is (700, never scaled), and the text scale triggers the sheet by itself;
multiplying the 700 by the scale as well would count the text twice.
`app_dialog_test.dart` pins every edge: 700 of box is a sheet and 701 is not; 1.49
at 1280 is a dialog and 1.5 is a sheet; 2.0 at 1280 is a sheet with nothing
overflowing and both labels in view. A long confirm label such as "Cancel this Work order" at 1.49 in the 420
dialog wraps inside its button if it must, and nothing overflows.

**A sheet's anatomy** is the same four rows in the same order. It is full box
width, anchored to the bottom, `AppRadius.card` on the top corners only, the
title row and the action row pinned, and the content the only scroller. The
action row is full-width and the primary action fills the inline end: a thumb
finds the act without aiming. A field's text and focus survive the box crossing
700 while the dialog is open (a rotated phone, a resized window): the body is
kept alive under a `GlobalKey`, and a test types into a field, narrows the window
and finds the text and the focus where they were.

**The decision comes from the `LayoutBuilder` at the dialog's root, and a dialog
route's box is the window.** A route is mounted in the `Navigator`'s overlay,
above the Shell, so nothing narrows the box it is handed: the sidebar of §2 is not
around it. The window *is* the box, and it is the one place in this document where
a window-sized number is the right input. Do not "fix" it into
`MediaQuery.sizeOf`: a dialog hosted in anything narrower than the window (a
golden, a test, a future split view) would then be told the wrong width, which is
the #105 defect in reverse.

### The address stays the `DialogPage`

ADR-0019 gave the Work order transition dialogs addresses of their own and
ADR-0021 did the same on the client, so that a refresh keeps the dialog and a link
to "cancel this Work order" can be sent. That is `DialogPage`
(`platform/dialog_page.dart:23`): a `Page` whose `createRoute` returns a
`DialogRoute` (`:37`), non-opaque, so the list stays visible beneath it. **That
does not change.** `AppDialog` is the surface *inside* the route, not a second route:
`DialogPage` stays the address and `AppDialog` is what its `builder` returns.

The route has two populations today, both counted off the tree: **52**
`DialogPage<void>(` pages in `platform/router.dart`, each an address, and **137**
`showDialog` call sites across 68 files, each a dialog with no address of its
own. Both stay legal. A dialog that is not addressable (a filter picker, a
confirmation inside a Screen that has no reason to survive a refresh) is a
`showDialog` call that builds an `AppDialog`, and nothing is wrong with that.
**Focus restoration did not need a helper**: `app_dialog_test.dart` opens a dialog
from a focused button with plain `showDialog`, closes it, and finds focus back on
the button, so there is no `showAppDialog` and this document does not ask for
one. Should a measurement ever say otherwise, the smallest thing that fixes it is
the thing to add.

### `barrierDismissible`, and what the primitive guarantees

`DialogPage` defaults `barrierDismissible` to `false` (`dialog_page.dart:26`),
matching every one of the four dialogs it replaced. The policy for the whole
client:

- **`false` wherever the dialog's own act is consequential or destructive.** A tap
  on the barrier is an accident, not a decision, and it loses what was typed.
- **Never the only way out.** The dialog always offers its own dismiss control, so
  a reader is never trapped by a barrier that does nothing.
- **`true` only for a read-only or picker dialog** whose `Esc` and Cancel are
  harmless.

The barrier flag belongs to the route and so to the caller. `Esc` is the primitive's.
Flutter's own `ModalRoute` handles `Esc` only when the route's `barrierDismissible`
is true, so on a `DialogPage` at its default `Esc` did nothing at all; `AppDialog`
catches it and runs the dialog's own dismiss action, which is what makes `Esc` on a
destructive confirm *cancel* rather than pop blindly past a callback the caller
needs to run.

**What `AppDialog` guarantees**, each pinned by a test of the same name:

- focus is **trapped**: the dialog is a focus scope of its own, inside the route's,
  and twelve Tab presses cycle the three stops of a field and two actions without
  ever reaching the field behind it. The scope also sits under the `Esc` handler, so
  a focused action that is disabled while a request is in flight leaves focus on the
  dialog and `Esc` still works when the actions re-enable;
- **first focus**: the first focusable thing in `child`, else the first *enabled*
  primary action, else the enabled dismiss action, else the enabled destructive one;
  with none enabled, the dialog's scope. A dialog whose only act is destructive
  opens on its dismiss, so that Enter does not confirm, and a disabled action is
  never the place focus is sent;
- `Esc` runs the dismiss action; with no dismiss action it pops; with a dismiss
  action that is disabled it does nothing, like the button;
- **focus is restored** to the control that opened it when the route closes;
- a `Semantics(scopesRoute, namesRoute)` node labelled with the title;
- every action 44px, every colour a token.

**What the caller still owns**: its strings, verbatim; its field keys and labels;
its enable conditions (`onPressed: null`); its own failure text, inline in `child`
(§12); what each callback does, including popping or going (the primitive pops
nothing for it); and `DialogPage`'s barrier flag.

## 12. Feedback: one place per outcome, and what is never a snack

`AppBanner` (`widgets/app_banner.dart`, shipped in #398) is the Platform's one
feedback surface: an inline strip with a tone, a message, an optional title, an
optional action and an optional dismiss. There is no `AppFeedback` and no wrapper
around `SnackBar`.

### The three outcome classes

| outcome | where it goes |
|---|---|
| an act succeeded and the view does not show it | `AppBanner(tone: success)` at the top of the page body |
| a failure the reader must act on | `AppBanner(tone: danger)`, with a retry as its `action` |
| a field the reader must fix | that field's own inline error, never a banner |

The first is the one that is missing today: "Work order raised" is true, and the
list that is now longer by one is not evidence of it to a reader who is looking at
a filtered page. The second is §7's `PlatformFailureState` for a *read*; a failed
*act* (a transition, a save) does not replace the page, so it needs a surface that
sits above it. The third is not a banner because a banner tells the reader that
something is wrong somewhere, and a field that is wrong should say so where the
reader's eyes already are.

### Where the banner sits

First child of the page body, above the toolbar's content and `Spacing.md` under
the header, in the order of §5. It is not an overlay and covers no control, so
nothing under it moves when it disappears except the page, which is correct: it was
taking its place. **It is never inside a dialog.** A dialog reports its own failure
inline, the way `WorkOrderCancelDialog` already does (`work_order_cancel_dialog.dart:99`,
`failureKey`, in `error` text directly under the field), and a banner behind a
dialog's barrier is a message nobody can read.

### What is never a snack

- a failure;
- the outcome of a destructive act;
- anything the reader must act on;
- anything that must survive a route change.

A `SnackBar` is one line, one duration, at the bottom of the window and gone
before a second reader looks, which is measured against its two users in `lib/`:
`maintenance/floor_screen.dart` (three calls, at `:137`, `:167` and `:197`) and
`platform/change_password_dialog.dart` (`:36`). All three report a recorded act whose
effect is already visible. That is the only thing a snack is for: **an
acknowledgement of an act whose effect is already on the page.** Anything else is a
banner.

### The announcement

`AppBanner` is `Semantics(container: true, liveRegion: true)`, so a screen reader
reads it when it appears, which is the whole reason there is one surface rather
than many. The tone's colour is never the only carrier: the icon is decorative
(`ExcludeSemantics`) and the words are the message. The contrast of each tone's
text on its own fill, measured from the shipped hexes by `app_banner_test.dart`:

| tone | light | dark |
|---|---|---|
| neutral | 6.50:1 | 6.97:1 |
| info | 8.49:1 | 8.49:1 |
| success | 6.49:1 | 6.49:1 |
| warning | 6.38:1 | 9.28:1 |
| danger | 5.30:1 | 5.28:1 |

All ten clear 4.5:1; the lowest is the dark danger. The action drops under the
message below `AppBreakpoints.headerActionsWrap` (560) of box, scaled by the text
(§10), so a banner at 2x text on a 900 box wraps its action as a 440 box does at 1x.

### One surface, not three

The client's failure is not that it has no transient feedback; Flutter has one,
and a `SnackBar` is in the tree twice. It is that there is nowhere stable to put
a persistent one, so each Screen tints its own `Container`: **17 files outside
`theme.dart` reach for the scheme's `errorContainer` or `secondaryContainer` by
hand** (`grep -lE "errorContainer|secondaryContainer"`), in 17 slightly different
spots. A second surface (`AppFeedback`, a snack wrapper) would be a third place for
an outcome to land and a decision about which, per outcome, forever. One surface
and the table above leaves no decision to make. The adoption of the 17 is each
Screen's own slice.

## 13. Data display: dates, numbers, money, and the tone legend

This section is a **written convention, not a widget.** The client has no `intl`
dependency (`frontend/pubspec.yaml` lists none), so a helper that took a locale
and a pattern would be the first of its kind and would pull a package in to format
a date the plant reads one way. What there is today is three hand-rolled
formatters, read for this section rather than imitated blind:

| file | what it formats |
|---|---|
| `kpi/kpi_catalogue.dart:368` `formatEnteredAt` | a timestamp as `YYYY-MM-DD HH:MM` in the device's zone |
| `production/handover_format.dart:6, :16, :25` | `formatClock` (`HH:mm`, `—` when null), `formatMinutes` (`1 h 35 min`), `formatPercent` (one decimal) |
| `people/worked_hours.dart:85` `formatWorkedMinutes` | minutes as `7h 30m` |

Where a rule below has no helper, the adopting slice owes one, in the module that
needs it, written the same way and tested the same way; there is no fourth
formatter in this card.

### Dates and times

A date is read as a person says it: **`31 Oct 2026`, never `2026-10-31`.** A time
is 24-hour: **`06:30`**. A date with a time is the two, a space apart:
`31 Oct 2026 06:30`. An ISO string is a wire format; showing one is showing the
reader the API.

**A production day is spelled as the plant spells it.** "Today" is the Site's
local date resolved in the database (ADR-0048, migration
`1802300000000_site-local-today`), not the browser's: a Site at UTC+7 is on
tomorrow's date from 17:00 UTC, and a client that formats "today" from
`DateTime.now()` would disagree with the server for seven hours of every day. A
Screen that needs to say what day it is for the plant shows the date the server
sent, formatted, and never derives it from the device clock.

**Where ISO strings render today**, named so the adopting slices have a target and
nothing is changed here: `actions/capa_detail_screen.dart:384`,
`actions/action.dart:279` (`decidedOn`), `actions/action_detail_screen.dart:353`,
`actions/capa_report_screen.dart:343` and `:814`, `people/training_detail_screen.dart:508`
(a bare `substring(0, 10)`), and `kpi/kpi_catalogue.dart:368`, which is the
formatter above. `AppDateField` also shows `YYYY-MM-DD` in its own text
(`widgets/app_date_field.dart:133`): it is an input, a field's value is not a
sentence, and whether it stays ISO is a decision for the slice that adopts this
section, not one made here.

### Numbers

A count has thousands separators and no decimals (`12,480`, never `12480.0`). A
percentage has **one** decimal (`94.5%`), matching `formatPercent`, and **is
rounded once, at display, and never re-derived**: the server's ratio is the
value, `94.5%` is how it is shown, and a Screen that divides two displayed
numbers to produce a third has made a number nobody recorded. Any quantity column
uses tabular figures and aligns to the end (§6's alignment table is the rule and
is not repeated; `widgets/app_table.dart:160` is the one place the code spends
`FontFeature.tabularFigures()` today). A quantity that is a whole number is shown
whole and any other as the API sent it, which is already what `action.dart:293`
and `kpi_catalogue.dart:381` do.

### Money and units

**The unit belongs to the column label, never to the cell.** The header says
`Cost (EUR)` and `Downtime (min)`, and every cell is a bare figure, so a column
of them compares by eye (§6) and a unit is written once. A money cell carries its
currency in the header for the same reason. A figure outside a column (a tile, a
sentence) carries its unit after it, as `formatMinutes` does.

### Nothing versus zero

**An unknown value is `—`; it is never `0` and never blank.** A zero that is a
fact is `0`. The two mean different things: zero downtime and unmeasured downtime
are not the same report, and a blank cell is read as a rendering bug.
`maintenance/tier_board.dart:157` already does this (`'—'` when `value` is null,
with a comment saying never `0` for an unmeasured KPI) and
`production/handover_format.dart:8` does it for a missing time. This is §7's four
states at the scale of one cell: **loading** is a skeleton, **none exist** is `—`,
and **a fact** is the figure.

### The tone legend

The five `StatusTone` values mean (from `status_tone.dart`): **neutral**, nothing is
being asked of anyone (a draft, a deliberate cancellation); **info**, live and in
hand; **success**, finished; **warning**, wants a decision from whoever is reading;
**danger**, something is wrong or was done wrongly. **Every Screen that paints
tones carries a legend or a column label**, because a colour that is the only
carrier of an outcome fails WCAG 1.4.1, and §6's board already argues this. The
legend is **built from the tones the Screen actually paints**: a Screen that
shows three tones shows three chips, labelled with that tone's word, rendered
through `StatusChip`. A banner is the same: its tone is a colour and its message is
the words.

## 14. What this document does not decide

- **The Shell's 700px rail breakpoint**, and the cliff it makes in section 2. A
  separate ticket.
- **Any Screen's copy.** The four states' wording is whatever each Screen ships.
- **Work orders' private header and Home's private tile.** Both survive this card
  and are adopted into the primitives in their own slices, so each Screen's
  change is one reviewable diff with its own golden.
- **Colours, fonts and radii.** ADR-0056 and `theme.dart` own those, and section
  3 says why the reference board's are not borrowed.
- **Which of the 113 dialogs moves onto `AppDialog`, in what order, and at which of
  the four widths.** Section 11 gives the table and the census; each dialog's move is
  its own slice, with its own diff. The same is true of the 17 hand-tinted banners
  (section 12) and of every ISO date (section 13).
- **A formatting helper.** Section 13 is a convention. The slice that first needs a
  date or a number formatted owns the helper and its test.
