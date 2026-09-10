# Golden tests

Issue #105. Golden tests hold #99's UI/UX pass in place by asserting on
rendered pixels rather than text — `flutter test` alone cannot see a visual
regression, and these can.

## What is goldened, and what is not

- The Shell, expanded and as the icon rail, either side of the 700px
  breakpoint (`test/shell_test.dart`, `goldens/shell_expanded.png` /
  `goldens/shell_rail.png`) — extends `shell_test.dart`'s own
  `PlatformShell`-on-a-real-`GoRouter` mount rather than adding a second one.
- The reworked Work orders Screen, populated, at two widths either side of
  its own 800px-of-content breakpoint (`test/work_orders_golden_test.dart`,
  `goldens/work_orders_wide.png` / `goldens/work_orders_narrow.png`).
- One golden per shared state (`test/work_orders_golden_test.dart`) — both
  empty variants (nothing has ever been raised, and a filter matching
  nothing), loading, a failed read, and a scope refusal.

**Re-opened and extended, deliberately, during this same ticket's review**:
one further golden, `goldens/work_orders_collision_700.png`, at a 700px
*window* — not a width from the list above, and not added quietly. Before
this fix, `WorkOrdersScreen` decided cards-versus-table off
`MediaQuery.sizeOf(context).width` (the whole window), the same input
`PlatformShell`'s own rail breakpoint uses. Both sat at 700px, so at exactly
that window width the Shell had just switched to its 260px expanded sidebar
while the Screen concluded it still had 700px of room for a table — it
actually had 440. The table rendered anyway, with its own header wrapping
one letter per line. This golden holds the fix — the Screen now reads
`LayoutBuilder`'s own `constraints.maxWidth`, the box it actually receives,
and its own breakpoint moved to 800px of *that* — in place at the exact
window width the two breakpoints used to collide, so a future change that
re-couples them (even by accident, even by picking a new number that
happens to match `PlatformShell.railBreakpoint` again) is visible on sight,
not only provable by reading `work_orders_test.dart`'s own regression test
for the same width. See `WorkOrdersScreen.narrowBreakpoint`'s own doc
comment (`lib/maintenance/work_orders_screen.dart`) for the full account,
including why 800 and not some other number.

Every golden rides a mount this repo already had, and none of them adds one.
The eight Work orders goldens are `matchesGoldenFile` against a Screen pumped
through `harness.dart`'s `pumpApp`, with `FakeWire` scripted to answer empty,
to answer an error, or to leave a request outstanding — the same seam
`approval_queue_test.dart` already uses for its own (non-pixel) assertions.
The two Shell goldens instead extend `shell_test.dart`'s own `_harness`, which
mounts `PlatformShell` under a real `GoRouter` over stand-in destinations;
that is the narrower mount AGENTS.md §5 already sanctions for the Shell, and
the Shell is not a Screen, so `pumpApp` is not the right door for it.

No golden mounts a state widget in isolation: doing that would be a third test
seam, which AGENTS.md §5 forbids.

Scope is deliberately narrow. The other fifteen Screens are **not**
goldened — a golden per Screen would fail on every ordinary content change
and get deleted within a month, which is worse than not having one. Do not
add a golden for a Screen outside this list without re-opening that scope
question first.

## Fonts: what these goldens can and cannot see

By default, `flutter_test` substitutes a solid placeholder box for every
glyph, regardless of which font a widget actually asked for — a golden
generated against that default would draw identical boxes whether the real
font was Roboto at the right weight or something else entirely, so it could
not see a font, weight, line-height or text-colour regression on any text.
#99's own user stories 18–20 are specifically about that (16/24 body text,
4.5:1 contrast on every text colour, the status green replaced), so a golden
that cannot see it is not doing this ticket's job.

Every golden test therefore calls `loadAppFonts()` (`harness.dart`) from its
own `setUpAll`, before the first `pumpWidget`. It reads the three TTFs
already committed at `assets/fonts/` and registers them, via `FontLoader`,
under the exact family name `theme.dart`'s own `buildAppTheme` sets
(`fontFamily: 'Roboto'`). Those are the same files `assets/fonts/README.md`
describes as bundled for a different reason — Flutter Web's CanvasKit
renderer fetching Roboto from `fonts.gstatic.com` at runtime, which is a
concern for the shipped web build, not for anything that paints inside
`flutter test` — but the same on-disk files serve both purposes, so nothing
new needed adding. With them loaded, text glyphs in these goldens are real
Roboto at their real weights and colours, so a text-rendering, weight, or
colour regression is visible in the PNG, not hidden behind a uniform box.

**Icons are a known, deliberate gap.** Only the text font family is loaded
here — Material's icon font is not, so every icon glyph (the sidebar's
`Icons.home_outlined` and its neighbours, action icons, and so on) still
renders as `flutter_test`'s placeholder box rather than its real shape. An
icon's own colour and position are still the real ones (the box is drawn in
the icon's actual colour, at its actual place in the layout), so a colour or
layout regression on an icon remains visible — only the glyph shape itself
does not render, and a golden diff cannot distinguish one icon from another
by eye.

This gap costs most on `shell_rail.png`, which is very nearly all icons: below
the rail breakpoint the Shell renders Destinations as icons alone, with their
labels moved into tooltips. That golden therefore holds the rail's geometry,
its spacing and its selected-Destination treatment, but it would not notice a
Destination's icon being swapped for a different one. A change to which icon a
Destination carries needs a test that names the icon, not this golden.

## Determinism

Given the fonts above, what makes the actual pixels reproducible: CI
(`.github/workflows/ci.yml`) pins the identical Flutter `3.44.0` these were
generated against, on the same `ubuntu-latest` Linux x64 — locally, that is
`ghcr.io/cirruslabs/flutter:3.44.0`, the same image `frontend/Dockerfile`'s
build stage and CI's own `flutter-action` both resolve to. Every golden test
also pins `tester.view.devicePixelRatio` and `tester.view.physicalSize`
explicitly, rather than relying on `flutter_test`'s own default test
surface, and every golden test loads the same three font files rather than
depending on whatever fonts happen to be installed on the machine running
the test.

That reasoning is why these are expected to render identically on CI — it is
not yet confirmed by an actual CI run. Only a real CI run, not this
document's own argument for why it should pass, is evidence that it does.

## Regenerating a golden

**Only for a deliberate, reviewed visual change** — a token value, a layout
decision, spacing, a new shared state. A golden that starts failing on a
change nobody meant to make to visuals is not something to reflexively
overwrite: read the diff first (`flutter test`'s own failure output on a
golden mismatch links the actual/expected/diff PNGs), work out what
actually moved, and only regenerate once you can say why the new pixels are
correct. A failing golden is far more often a real regression than a golden
gone stale — the tests exist precisely to make that regression visible
before it lands.

To regenerate, work against a **copy** of `frontend/`, never the real
directory — the same rule as every other Flutter command in this repo
(`AGENTS.md` §3): `flutter pub get` rewrites `pubspec.lock` to whatever the
container's SDK resolves, and running that against a live `frontend/` can
silently break the next real build.

```bash
# From the repo root.
rm -rf /tmp/golden-work && cp -r frontend /tmp/golden-work
docker run --rm -v /tmp/golden-work:/app -w /app \
  ghcr.io/cirruslabs/flutter:3.44.0 \
  bash -c "flutter pub get && flutter test --update-goldens"

# Copy the regenerated PNGs back into the real tree.
cp /tmp/golden-work/test/goldens/*.png frontend/test/goldens/

# Confirm the container's own `pub get` did not leave a side effect behind.
git status --short frontend/pubspec.lock
# If it shows a change, restore it:
git checkout -- frontend/pubspec.lock

rm -rf /tmp/golden-work
```

Then run a **clean** copy (a fresh `cp -r`, not the same directory
`--update-goldens` just wrote into) through `flutter test` without the
update flag, so the new goldens are actually asserted against once rather
than only ever having been written:

```bash
rm -rf /tmp/golden-verify && cp -r frontend /tmp/golden-verify
docker run --rm -v /tmp/golden-verify:/app -w /app \
  ghcr.io/cirruslabs/flutter:3.44.0 \
  bash -c "flutter pub get && flutter analyze && flutter test"
rm -rf /tmp/golden-verify
```

Commit the changed PNGs alongside the Dart change that motivated them, in
the same pull request, so a reviewer sees the visual diff and the code
change together — not a later, unexplained PNG-only commit.
