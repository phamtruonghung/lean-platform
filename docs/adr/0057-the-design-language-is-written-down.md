---
status: accepted
---

# The design language is written down, and density is a target with a measured reference

Date: 2026-11-01

Issue #386 came from the owner's verdict on the first UI pass, "the UI has not
changed", and their request that every Screen reach the information density of
the MTU board: its density and grouping only, never its CSS, fonts or colours.
Without a number that request is unfalsifiable, and it collides with a floor the
Platform already holds, a 44px tap target. The tokens in `theme.dart` were sound;
what was missing was the statement of how the pieces join, and which demand wins
when density and the floor meet.

## The decision

**Density is a written target with a measured reference, and a 32px row is
allowed while a 44px tap floor is not negotiable.** The Platform adopts the
reference board's *information density* and keeps its own palette, its own fonts
and its own access floors. The way those coexist is one rule: a register row is
**32px when nothing in it is tappable and `AppTouchTarget.min` (44) when
something is**, and density is paid for in padding and in right-aligned tabular
numerics, never by going below 44 on a control.

**What the reference measures.** The board's deployed CSS, read as served:
`body{font:14px/1.45 "Segoe UI"; padding:12px 16px}`, headings at `600 16px`
(1.14x the body), `th,td{padding:6px 8px; border-bottom:1px solid}` with
`th` at 12px in a muted colour, panels at `padding:12px; border-radius:8px`, gaps
of 6, 10 and 14. A row is `6 + 20.3 + 6`, about 32px. The Platform's Work orders
row states `minHeight: 56`. That 24px per row is the density gap, and it is
nearly all of it.

**Why its colours and fonts are not adopted.** It is `"Segoe UI"` on a green-grey
palette (`#f6f7f5`). The Platform bundles Roboto so Flutter Web never fetches a
font, and ADR-0056 gave it a blue palette in two schemes whose contrast is
measured pair by pair. Copying the board's look would restyle every Screen and
re-open every contrast figure to gain nothing the owner asked for: what the board
has that the Platform lacks is how little space it spends, not what colour it is.

**Why 32 and 44 can both be true.** A row nobody can tap (a read-only register
row, a band) has no tap target, so 44 does not apply to it and the board's figure
can. A row that holds a button, or is itself the target, is a tap target, and 44 is
the floor. The two rules never meet on one row. A row with a row-action column is the second
kind, and so is Work orders' whole-row tap: that Screen moves from 56 to 44, not
to 32, and the rest of its density comes from padding and right-aligned numerics.

**Rejected: match the board at 32px everywhere.** It delivers the density and
fails the access floor on every row that holds a control, on the Screens where a
person on a touch device most needs the control to be hit first time. A density
that is paid for by a form of exclusion is not a trade this ADR will make.

**Rejected: keep the 56px rows and concede.** It leaves the code as it is and
says, in writing, that the owner's first requirement was never going to be
delivered. It also makes the next review's argument "is 56 right?" with nothing to
say, which is the position this ADR exists to leave.

The rest of the language (the token ladder, the page rhythm, the five body
patterns, the four states, the access floors, the breakpoint rule) is
`docs/design-language.md`. It is not repeated here: it is the detail, and this is
the one decision in it a reader would otherwise second-guess.

## What this costs

- **Later slices must adopt the primitives.** `AppBreakpoints` and
  `AppTouchTarget` are in `theme.dart`, and the five widget files are in
  `frontend/lib/widgets/` — `app_toolbar.dart`, `app_table.dart`
  (`AppTableHeader` + `AppTableRow`), `app_stat_tile.dart`,
  `app_detail_section.dart`, `app_section_grid.dart` — all shipped with this
  card. Each Screen's move onto them is its own change, so the document still
  says which names shipped and which Screen has not adopted them.
- **Work orders' private table header and Home's private tile survive this card.**
  `_WorkOrderTableHeader` (w700, `onSurface`, 56px rows) and `_HomeCard` are the
  shapes the primitives generalise, and each is adopted, with its own golden, in
  its own slice. Work orders' 800px breakpoint is a deliberate deviation from the
  700 of `AppBreakpoints.registerTable` and keeps its own reason in its own file.
- **The Shell's 700px rail cliff is untouched.** Growing a window from 699 to 700
  shrinks a page's content box from 635 to 440. The document states it as a
  constraint the design survives, and changing it is a separate ticket.
- **No Screen changes.** The card adds this record, `docs/design-language.md`, a
  fifth rule in `docs/frontend-layout.md`, a paragraph in
  `frontend/test/GOLDENS.md`, `AppTouchTarget` and `AppBreakpoints` in
  `frontend/lib/theme.dart`, five widget files under `frontend/lib/widgets/`,
  their five test files and seven goldens. Nothing under a module directory moves
  and `home_screen.dart` is not touched: every Screen keeps its own widgets until
  its own slice adopts a primitive.
- **A 32px row is a new thing to defend in review.** Anyone who sees one will
  reasonably ask whether it breaks the tap floor. The answer is in this file and
  in the row-height rule, and the primitive's own test is what will pin it.
