---
status: accepted
---

# A second palette is a theme extension, chosen at runtime and remembered

Date: 2026-10-31

Issue #366 asked for a dark mode, requested from the dashboard as "add dark mode".
`frontend/lib/theme.dart` had carried a promise since issue #102: only the light
palette ships, but every colour is read through its semantic name, "so adding a
second palette later is a values change to this file alone, not a Screen-by-Screen
rewrite". That was only half true. The semantic tokens were `static const`, so a
second palette could not differ at runtime without every Screen asking for it
through something. The request was to finish the promise: a second palette that
is a theme, follows the browser by default, can be overridden by a person, and
leaves the light palette unchanged pixel for pixel.

## The decision

**A palette is a `ThemeExtension`.** `AppPalette` carries the semantic tokens and
the component bindings that `AppColors` and `AppComponentColors` used to name.
`AppPalette.light` and `AppPalette.dark` are the two values, and each `ThemeData`
registers its own. A Screen reads `AppColors.of(context).card` where it read
`AppColors.card`; `AppColors.of` is `Theme.of(context).extension<AppPalette>()!`
and has no fallback, so a widget pumped under a bare `MaterialApp` fails loudly
rather than silently wearing the wrong palette. `AppComponentColors` is gone.

**The three layers stay.** Primitives are private to `theme.dart`, one set per
palette (`_PrimitivesLight`, `_PrimitivesDark`), raw hex only. A semantic token is
named for its role. A component token binds a semantic value, and is now a getter
over it (`cardBorder => edge`, `focusRing => actionPrimary`,
`navSelectedBackground => statusInfoFill`), so a binding cannot drift from the value
it binds. The two palettes are `static const` fields because `ThemeData.extensions`
and the tests need each as a value; a same-named constructor cannot also be a
constant field. A token cannot be spent where there is no `BuildContext`, so the
places that did (the Signature pad's painter, `const Divider(...)`, `const
BorderSide(...)`) take the palette or the colour from the `build` method above
them. No palette is cached in a static.

**`buildAppTheme([Brightness brightness = Brightness.light])`** builds both from
one function. The light `ColorScheme` is pinned role by role exactly as before; the
dark one is the same shape, with every role the Platform reads pinned to a named
dark primitive, plus the roles Material widgets read implicitly in dark — dialogs,
menus and date pickers (`surfaceContainer*`, `surfaceTint`) and snackbars
(`inverseSurface`, `onInverseSurface`, `inversePrimary`) — so that text on them is
measured too and a Flutter upgrade cannot restyle dark.

**`ThemeModeCubit`** holds a `ThemeMode`. `ThemeMode.system` is the default, and only
an explicit choice is stored, in `shared_preferences` (the store `LocalAuthGateway`
keeps the session in) under `platform.theme_mode` as `system`, `light` or `dark`;
absent and unrecognised both mean `system`. The first frame never waits on
storage: the cubit starts at `system` and emits the stored value when it arrives.
A read that fails (no storage plugin, a blocked store) degrades to `system` with
no error; a read that lands after `close()` or after the person has already chosen
is dropped. `PlatformApp` builds the cubit in `initState`, closes it in `dispose`,
provides it above `MaterialApp.router`, and builds the two `ThemeData`s once.
`routerConfig` is still the one `_router` field, so a mode change rebuilds the app
without losing navigation history.

**The toggle is one item in the account menu** (issue #270's avatar menu): `Dark
palette`, checked while the dark palette is on screen, switching between the two.
`PlatformShell` is handed `darkPalette` and `onToggleDarkPalette` rather than the
cubit, so the Shell is still pumped in a test with no provider. For `ThemeMode.system`
the check follows the browser's own preference, so a person on a dark system sees
it checked and one press goes to light.

**A Signature does not change colour.** A Signature is a legal mark (ADR-0052), and
the pad exports a transparent PNG in navy ink, `#1E3A8A`. That ink was the light
palette's `textPrimary`; under a dark `textPrimary` it would have been pale ink,
silently different pixels in a stored mark. So the ink is its own token,
`signatureInk`, identical in both palettes, and the pad's controller is handed it
by the caller (`toPng(ink)`) rather than reading a palette. The pad is drawn on
`signaturePaper` (white in both palettes; in light it is the card's own white), because
a dark pad would hide the very strokes it collects. A stored Signature shown on
screen is dark ink on transparency (or on whatever the person uploaded) and would
vanish on a dark card, so it sits on `signatureBackdrop`: clear in light, so no
light pixel moves, white in dark.

## What was rejected

- **A `static` or mutable global palette** (`AppColors.use(dark)`), keeping every
  Screen's code unchanged. Nothing would rebuild when it flipped, a widget test
  could leak one test's palette into the next, and the palette would be a fact
  about the process rather than about the widget tree it is drawn in.
- **Restyling each Screen** with `Theme.of(context).brightness == Brightness.dark ?
  ... : ...`. That is the Screen-by-Screen rewrite #102 promised not to need,
  and it spreads the one decision (what dark looks like) over ninety call sites.
- **A Site-wide theme**, set by an administrator for every Account. The request is a
  person's own preference, and the browser already knows it. A Site-wide theme,
  a per-Module palette and a high-contrast palette are separate requests.
- **Dark as an inversion** of the light values. Every pair is measured instead
  (below); the two families swap jobs, with pale tints as text and deep shades as
  fills.

## Measured

WCAG 2.x relative luminance, alpha colours composited over the surface they sit
on first. The formula is `frontend/test/contrast.dart`, and
`frontend/test/palette_contrast_test.dart` measures every pair again against both
built themes rather than trusting this table. Text is held to 4.5:1,
anything that is not text to 3:1.

| Pair | Ratio |
|------|-------|
| `textPrimary` `#F1F5F9` on card `#1E293B` / canvas `#0F172A` | 13.35 / 16.30 |
| `textPrimary` on surfaceMuted `#334155` / dialog and menu `#253349` | 9.45 / 11.63 |
| `textPrimary` on a hovered row (over card `#2C3C53` / over canvas `#1F2C44`) | 10.21 / 12.76 |
| `textMuted` `#CBD5E1` on card / canvas | 9.85 / 12.02 |
| `textMuted` on surfaceMuted / dialog / hovered row (card, canvas) | 6.97 / 8.58 / 7.53, 9.42 |
| `colorScheme.error` `#F87171` on card / canvas / dialog | 5.29 / 6.45 / 4.61 |
| `actionPrimary` (`primary`) `#93C5FD` on card / canvas / dialog | 8.11 / 9.90 / 7.06 |
| `onActionPrimary` `#0F172A` on `actionPrimary` | 9.90 |
| `onPrimaryContainer` `#DBEAFE` on `primaryContainer` `#1E3A8A` | 8.49 |
| `navSelectedForeground` (`actionPrimary`) on `navSelectedBackground` | 5.74 |
| `onErrorContainer` `#FECACA` on `errorContainer` `#7F1D1D` | 6.93 |
| `onError` `#450A0A` on `error` | 5.84 |
| `onSecondaryContainer` `#86EFAC` on `secondaryContainer` `#14532D` | 6.49 |
| `onInverseSurface` `#0F172A` on `inverseSurface` `#E2E8F0` | 14.48 |
| `inversePrimary` `#1D4ED8` on `inverseSurface` | 5.44 |
| status neutral: `textMuted` on `#334155` | 6.97 |
| status info: `#DBEAFE` on `#1E3A8A` | 8.49 |
| status success: `#86EFAC` on `#14532D` | 6.49 |
| status warning: `#FDBA74` on `#431407` | 9.28 |
| status danger: `#FCA5A5` on `#7F1D1D` | 5.28 |
| status danger / success / warning as plain text on a card | 7.71 / 10.42 / 8.67 |
| `edge` (hairline) `#6B7D96` on card / canvas | 3.48 / 4.25 |
| `outline` (a control's rim) `#94A3B8` on card / canvas / dialog | 5.71 / 6.96 / 4.97 |
| `focusRing` (`actionPrimary`) on card / canvas | 8.11 / 9.90 |
| `navSelectedAccent` on the selected Destination's fill | 5.74 |

**Warning reads as orange, not brown.** `#FDBA74` (orange-300) is the bright member
of its pair, on `#431407` (orange-950), which is dark enough not to read as a
colour itself. An orange-900 or amber-900 fill was the thing to avoid, as amber-800
text was in the light palette (#169).

**The light hairline is the one documented exception.** The light `edge` is
1.22:1 on a card and 1.17:1 on the canvas, and the light table band and hover fill
are likewise below 3:1 — by design, since #169, as surfaces and hairlines rather
than information. The light palette must not move a pixel, so it cannot be
brought up to 3:1. The contrast test holds the light palette's rim (`outline`,
4.76:1) and `focusRing` to 3:1, lists the light `edge` as a named exception, and
pins it at its measured 1.22:1 so it can only get no quieter. Dark has no such
exception: its `edge` clears 3:1 on both a card and the canvas.

**The light scheme's un-pinned implicit roles are not measured.** The light
`ColorScheme` pins only what #169 pinned; a dialog, menu or snackbar in light
wears what `fromSeed` generates, unchanged by this decision. One of those, `colorScheme.error`
on the light dialog surface, measures 3.94:1. That is a property of the light
palette as it already shipped, noted here and left alone rather than changed under a
"no pixel moves" constraint; the dark palette pins and measures those roles.

## What this costs

- `ThemeModeCubit` is a `Cubit`, not a `Bloc`. `AGENTS.md` §7 asks for a `Bloc`
  with an explicit event type for every **Screen-driving** state machine. This
  drives no Screen: it holds one three-valued setting for `MaterialApp`, and an
  event type would be ceremony around a single assignment. That is the reason it is
  an exception, not a new convention, and a Screen's state machine still takes the
  Bloc form.
- The Training Record form (a printable document) is drawn in the dark palette when
  dark is on; printing it from the browser prints what is on screen. Nothing here
  changes how it prints, and a print stylesheet is a separate request.
  The CAPA report (`router.dart`, `capaReport`, issue #212) is routed outside the Shell
  under the same `MaterialApp` and prints dark too.
- Ninety token reads across twenty-seven files changed from a `static` to
  `AppColors.of(context)`, and about ten `const` expressions stopped being `const`.
  That is the price of a runtime palette and was paid once, here.
