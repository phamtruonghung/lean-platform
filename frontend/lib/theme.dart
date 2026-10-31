import 'package:flutter/material.dart';

import 'status_tone.dart';

/// Design tokens for the app: spacing, radius, and — as of issue #102 — a
/// three-layer colour system plus a named type scale. As of issue #366 the
/// colour system has two palettes, light and dark, behind one accessor.
///
/// The three colour layers, each built only from the one before it:
///
/// 1. **Primitive** (`_PrimitivesLight` and `_PrimitivesDark`, private to this
///    file) — the raw hex values themselves, and nothing else; one set per
///    palette. A primitive is never spent directly by a Screen; it exists so a
///    value is written down exactly once.
/// 2. **Semantic** ([AppPalette]'s role-named fields) — the same values named
///    for the ROLE they play (surface, border, text, action, status), never
///    for what they look like. This is the layer a Screen reaches for.
/// 3. **Component** ([AppPalette]'s bindings: `cardBorder`, `focusRing`,
///    `rowHoverFill` and the rest) — a semantic value bound to a shape that
///    repeats across more than one widget (a selected nav item's fill, a
///    card's hairline, a focus ring), named for that shape so the binding is
///    made once rather than re-derived at each call site. They are getters
///    over the semantic fields, so a binding cannot drift from the value it
///    binds, and a second palette cannot forget one.
///
/// **A Screen reads a token through [AppColors.of]**, which returns the
/// [AppPalette] the nearest [Theme] carries: `AppColors.of(context).card`.
/// A token is a `ThemeExtension` value rather than a `static const` so that it
/// can differ between [ThemeData]s at runtime; the corollary is that a token
/// cannot be spent where there is no `BuildContext` (a top-level `const`, a
/// `static final`). Such a site takes the palette or the colour as an argument
/// from the `build` method that does have a context — a palette is never
/// cached in a static.
///
/// **No `Color` literal and no `Colors.*` constant may appear anywhere
/// under `frontend/lib/` outside this file.** `theme_skeleton_test.dart`
/// enforces that by reading every other source file under `lib/` and
/// failing if one is found — so the rule survives the next agent rather
/// than relying on review to catch it. A Screen that needs a colour reaches
/// for [AppColors.of], or, for anything the palette does not name, for
/// `Theme.of(context).colorScheme` directly — that is theme-derived rather
/// than literal, so it is never a violation.
///
/// **Adding a palette** is a second primitives set, a second [AppPalette]
/// instance built from it, and a second `ColorScheme` pinned role by role in
/// [buildAppTheme] — not a Screen rewrite, because no Screen names a palette.
/// ADR-0056 records the decision, and the measured dark table.
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Shared radius values.
abstract final class AppRadius {
  /// The pill used by the search field and other single-line controls.
  static const double pill = 28;

  /// The card radius the app already uses everywhere.
  static const double card = 14;
}

/// Layout tokens (issue #189): the sizes a Screen's own page agrees on,
/// written down once rather than re-picked per Screen.
///
/// This exists because six Screens were each declaring their own
/// `static const double maxWidth` — 700, 760, 760, 800, 800, 800 against the
/// 900 the Directory, Org Units, the Approval queue and Home already used — and
/// nothing said which was intended. A Screen still declares its own constant
/// (so `SkeletonList(maxWidth: X.maxWidth)` keeps working and the Screen's own
/// vocabulary stays in its file); it just does not decide the number.
///
/// **The wide pages are exceptions and name themselves as such.** The Work
/// orders table, the maintenance registers, the Action log and the tier board
/// lay out tables and boards that need more than [pageWidth]; the employee and
/// Work order detail Screens are single-record pages whose narrower measure is
/// a reading decision. Those keep their own numbers deliberately — this token
/// names the default, not a rule every Screen must spend.
abstract final class AppLayout {
  /// A Screen's page: the box its title, controls and list are laid out in,
  /// centred in whatever width the Shell leaves.
  static const double pageWidth = 900;
}

/// Layer 1, light — primitives. Raw values only, and only the ones a semantic
/// or component token below actually spends.
///
/// **Where these values come from (issue #169).** The palette is the
/// `ui-ux-pro-max` design skill's own "Analytics Dashboard" scheme, adopted
/// wholesale on the user's explicit approval: primary `#1E40AF` with white on
/// it, background `#F8FAFC`, foreground `#1E3A8A`, muted `#E9EEF6` with
/// `#475569` on it, border `#DBEAFE`, destructive `#DC2626`, and a
/// primary-coloured ring. Two of its roles are deliberately not carried as
/// tokens: the skill's accent (`#D97706`, amber) is the family this Platform
/// already spends through [StatusTone.warning], and its secondary
/// (`#3B82F6`) is a second brand colour the Platform has no use for — a token
/// nothing spends is the speculative generality this layer's own rule above
/// rules out, so `secondary` is generated by the scheme and named nowhere here.
///
/// This **supersedes #102's own choice of seed**, which kept the standalone
/// dark slate the Platform was born with (`#0F172A`) and recorded its
/// `fromSeed` output as literals. #102's reasoning was that the Platform
/// absorbs two predecessor applications and should not inherit either one's
/// palette — a concern this palette does not raise, because it comes from the
/// design skill's own dashboard scheme rather than from
/// `employee-management`'s indigo. Two things #102 got right and this keeps:
/// the values are still written down exactly once, here, and the three-layer
/// structure above is untouched.
///
/// Every pair this file hands out was measured rather than estimated, and the
/// ratio is recorded beside it (a measurement, not a claim that something
/// "looks fine"): foreground 10.36:1 on a card and 9.90:1 on the canvas, muted
/// foreground 7.58:1 and 7.24:1, white on primary 8.72:1, primary on its own
/// container 8.49:1, and all five status tones between 5.3:1 and 8.5:1
/// (see [AppPalette.statusForeground]'s own table).
abstract final class _PrimitivesLight {
  /// The skill's `--color-primary`. 8.72:1 against white, in both directions.
  static const Color primary = Color(0xFF1E40AF);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// The selected Destination's fill and the colour on it: the skill's
  /// `--color-border` blue-100 reused as a container, with the scheme's own
  /// foreground on top (8.49:1).
  static const Color primaryContainer = Color(0xFFDBEAFE);

  /// The skill's `--color-destructive`. 4.83:1 against white — the floor for
  /// text, and exactly why the *status* red below is a shade darker: red on
  /// its own tint is not the same measurement as red on white.
  static const Color error = Color(0xFFDC2626);
  static const Color onError = Color(0xFFFFFFFF);

  /// The pale red behind anything on an error surface — a refusal banner, a
  /// shortfall badge, a status chip saying something failed. One value, spent
  /// by two roles (`colorScheme.errorContainer` and the danger status fill),
  /// named once here so the two cannot drift apart.
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF991B1B);

  /// The skill's `--color-background`: the scaffold behind every card.
  static const Color canvas = Color(0xFFF8FAFC);

  /// The skill's `--color-foreground`. 10.36:1 on a card, 9.90:1 on the
  /// canvas. A cool near-black rather than the neutral one the Platform used
  /// to carry: against a slate canvas and blue-bordered cards, a neutral
  /// black reads as a colour from a different family.
  ///
  /// Spent as the scheme's `onSurface`, as `onPrimaryContainer` over
  /// [primaryContainer], and as the label colour of an `info` status chip —
  /// the same value in three roles, which is why it is written once.
  static const Color onSurface = Color(0xFF1E3A8A);

  /// The skill's `--color-muted-foreground`. 7.58:1 on a card, 7.24:1 on the
  /// canvas.
  static const Color onSurfaceVariant = Color(0xFF475569);

  /// The skill's `--color-muted` — a quiet surface, not a colour. Spent by the
  /// table's own header band, by the skeleton placeholders, by the sidebar's
  /// avatar fill, and as the neutral status fill. Against white it is 1.17:1:
  /// a surface, never text.
  static const Color muted = Color(0xFFE9EEF6);

  /// The skill's `--color-border` — the hairline around a flattened card and
  /// under a table's header band. 1.22:1 against white: a hairline, never
  /// text.
  static const Color edge = Color(0xFFDBEAFE);

  /// The rim of an outlined control — an `OutlinedButton`, a picker's own
  /// panel, an input's border. 4.76:1 against white, which matters twice: a
  /// border below 3:1 fails WCAG 1.4.11 (non-text contrast) outright, and the
  /// near-white hairline this Platform used to derive from its seed left every
  /// outlined control reading as disabled rather than pressable. It is slate,
  /// not blue: a blue rim at this weight competes with the action colour,
  /// which is what a border is supposed to sit behind.
  static const Color outline = Color(0xFF64748B);

  /// The action colour at 10% over white (`#E8ECF7`) — the highlight that
  /// follows the pointer across a table row. A raw value like every other
  /// primitive; the role it plays is named in [AppPalette.surfaceHover].
  static const Color hover = Color(0x1A1E40AF);

  /// Plain white: the panel surface, a card's own fill, and the fill of every
  /// input.
  static const Color white = Color(0xFFFFFFFF);

  /// The three status roles Material 3 does not define: success, warning and
  /// the darker red a status wears *on its own tint* (5.30:1 there, where
  /// [error] alone would measure 3.95:1). Each is the darker shade of its own
  /// family — green-800, orange-800, red-700 — chosen for the floor rather
  /// than for taste, and each measured against its own fill below.
  ///
  /// **Warning is orange, not amber** (`#9A3412`, orange-800). The first value
  /// tried was amber-800 (`#92400E`), which measures 6.37:1 and is legible —
  /// and next to the green it reads as *brown*, which nobody scans as "warn".
  /// Orange-800 measures 6.56:1 on the amber tint and 6.38:1 on the orange one
  /// below, and is unmistakably the middle of the three.
  static const Color success = Color(0xFF166534);
  static const Color warning = Color(0xFF9A3412);
  static const Color danger = Color(0xFFB91C1C);

  /// The status fills (issue #168) — one tint per [StatusTone], each measured
  /// against its own foreground below and none below 4.5:1. Two of them are
  /// values this file already keeps ([muted] and [errorContainer]) rather than
  /// second copies of the same hex: one value, named once, spent by more than
  /// one role, which is the rule layer 1 exists to keep.
  static const Color successFill = Color(0xFFDCFCE7);
  static const Color warningFill = Color(0xFFFFEDD5);

  /// A Signature's ink: [onSurface] navy, exactly the colour the pad has always
  /// drawn in (issue #366). Written as its own primitive rather than spent as
  /// [onSurface] so the ink is the same in both palettes — see
  /// [AppPalette.signatureInk].
  static const Color signatureInk = Color(0xFF1E3A8A);

  /// No fill: the light surfaces a displayed Signature already sits on are
  /// light, so it needs no paper of its own (see [AppPalette.signatureBackdrop]).
  static const Color clear = Color(0x00FFFFFF);
}

/// Layer 1, dark — primitives for the dark palette (issue #366, ADR-0056).
///
/// **Dark is a values change, not an inversion.** A cool slate family to match
/// the light palette's blues (Tailwind slate surfaces, blue-300 action with
/// near-black on it), and every pair is measured — the arithmetic is WCAG 2.x
/// relative luminance, alpha colours composited over the surface they sit on
/// first; the ratio is recorded on the token that spends it, and
/// `palette_contrast_test.dart` measures all of them again rather than
/// trusting these comments.
///
/// Where the light palette keeps its saturated mid-tones as the text colours,
/// dark keeps its pale tints (shade 200-300) as text and its deep shades
/// (800-900) as fills — the same two families swapping jobs.
abstract final class _PrimitivesDark {
  /// Slate-900. The scaffold behind every card.
  static const Color canvas = Color(0xFF0F172A);

  /// Slate-800. A card's own fill, the sidebar, every input.
  static const Color card = Color(0xFF1E293B);

  /// A surface raised one step above [card] — the fill of a dialog, a menu and
  /// a date picker (`surfaceContainer` / `surfaceContainerHigh`). Slate-800
  /// lifted by a few percent so a dialog over a card does not melt into it.
  static const Color raised = Color(0xFF253349);

  /// Slate-700. The quiet surface: a table's header band, skeleton
  /// placeholders, the neutral status fill.
  static const Color muted = Color(0xFF334155);

  /// Slate-100. 13.35:1 on a card, 16.30:1 on the canvas, 11.63:1 on
  /// [raised], 9.45:1 on [muted].
  static const Color onSurface = Color(0xFFF1F5F9);

  /// Slate-300. 9.85:1 on a card, 12.02:1 on the canvas, 8.58:1 on [raised],
  /// 6.97:1 on [muted].
  static const Color onSurfaceVariant = Color(0xFFCBD5E1);

  /// The hairline. Slate, lifted until it clears 3:1 outright: 3.48:1 on a
  /// card and 4.25:1 on the canvas (the light hairline is 1.22:1 by design;
  /// see ADR-0056 for why dark does not copy that).
  static const Color edge = Color(0xFF6B7D96);

  /// Slate-400. The rim of an outlined control: 5.71:1 on a card, 6.96:1 on
  /// the canvas, 4.97:1 on [raised].
  static const Color outline = Color(0xFF94A3B8);

  /// Blue-300, the action colour. 8.11:1 on a card, 9.90:1 on the canvas,
  /// 7.06:1 on [raised]; 5.74:1 on [primaryContainer].
  static const Color primary = Color(0xFF93C5FD);

  /// Slate-900 on [primary]: 9.90:1.
  static const Color onPrimary = Color(0xFF0F172A);

  /// Blue-900, the selected Destination's and the info status's fill; with
  /// [onPrimaryContainer] on it, 8.49:1.
  static const Color primaryContainer = Color(0xFF1E3A8A);
  static const Color onPrimaryContainer = Color(0xFFDBEAFE);

  /// The action colour at 12% (`0x1F`), composited over a card to `#2C3C53`
  /// and over the canvas to `#1F2C44`; body text on those measures 10.21:1 and
  /// 12.76:1, muted text 7.53:1 and 9.42:1.
  static const Color hover = Color(0x1F93C5FD);

  /// Red-400, `colorScheme.error`: 5.29:1 on a card, 6.45:1 on the canvas,
  /// 4.61:1 on [raised]. The floor on a dialog is why it is not any darker.
  static const Color error = Color(0xFFF87171);

  /// Red-950 on [error]: 5.84:1.
  static const Color onError = Color(0xFF450A0A);

  /// Red-900 with red-200 on it: 6.93:1.
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color onErrorContainer = Color(0xFFFECACA);

  /// The three status foregrounds, light tints (shade 300) over deep fills
  /// (shade 900 / 950). Danger is red-300 (5.28:1 on [errorContainer], 7.71:1
  /// on a card); success green-300 on green-900 (6.49:1; 10.42:1 on a card);
  /// warning orange-300 on orange-950 (9.28:1; 8.67:1 on a card). **Warning
  /// reads as orange, not brown**: the text is the bright member of the pair,
  /// and the fill is dark enough (orange-950) that it does not itself read as
  /// a colour — a brown fill (orange-900, amber-900) was the thing to avoid.
  static const Color danger = Color(0xFFFCA5A5);
  static const Color success = Color(0xFF86EFAC);
  static const Color successFill = Color(0xFF14532D);
  static const Color warning = Color(0xFFFDBA74);
  static const Color warningFill = Color(0xFF431407);

  /// Slate-200 with slate-900 on it, a snackbar: 14.48:1. [inversePrimary]
  /// (blue-700) is its action text: 5.44:1.
  static const Color inverseSurface = Color(0xFFE2E8F0);
  static const Color onInverseSurface = Color(0xFF0F172A);
  static const Color inversePrimary = Color(0xFF1D4ED8);

  /// The Signature's ink and paper: identical to the light palette's on
  /// purpose (a Signature is a legal mark; its exported pixels do not depend on
  /// the palette). 10.36:1, navy on white.
  static const Color signatureInk = Color(0xFF1E3A8A);
  static const Color white = Color(0xFFFFFFFF);
}

/// Layers 2 and 3 — the semantic tokens and the component bindings, as one
/// [ThemeExtension] (issue #366). A Screen reads them through
/// [AppColors.of]; the light and dark values are [AppPalette.light] and
/// [AppPalette.dark], and [buildAppTheme] registers one in each [ThemeData].
///
/// Semantic fields are named for the role they play rather than their
/// appearance. Component tokens are getters over a semantic field, so the
/// binding is made once and a palette cannot supply it wrongly.
///
/// The two palettes are `static const` fields rather than named constructors
/// because `ThemeData.extensions` and the tests need to refer to each as a
/// value.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.card,
    required this.edge,
    required this.textPrimary,
    required this.textMuted,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.actionPrimary,
    required this.onActionPrimary,
    required this.statusDanger,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusNeutralFill,
    required this.statusInfoFill,
    required this.statusSuccessFill,
    required this.statusWarningFill,
    required this.statusDangerFill,
    required this.statusInfoForeground,
    required this.signatureInk,
    required this.signaturePaper,
    required this.signatureBackdrop,
  });

  /// The light palette — every value the Platform shipped before issue #366.
  static const AppPalette light = AppPalette(
    canvas: _PrimitivesLight.canvas,
    card: _PrimitivesLight.white,
    edge: _PrimitivesLight.edge,
    textPrimary: _PrimitivesLight.onSurface,
    textMuted: _PrimitivesLight.onSurfaceVariant,
    surfaceMuted: _PrimitivesLight.muted,
    surfaceHover: _PrimitivesLight.hover,
    actionPrimary: _PrimitivesLight.primary,
    onActionPrimary: _PrimitivesLight.onPrimary,
    statusDanger: _PrimitivesLight.danger,
    statusSuccess: _PrimitivesLight.success,
    statusWarning: _PrimitivesLight.warning,
    statusNeutralFill: _PrimitivesLight.muted,
    statusInfoFill: _PrimitivesLight.primaryContainer,
    statusSuccessFill: _PrimitivesLight.successFill,
    statusWarningFill: _PrimitivesLight.warningFill,
    statusDangerFill: _PrimitivesLight.errorContainer,
    statusInfoForeground: _PrimitivesLight.onSurface,
    signatureInk: _PrimitivesLight.signatureInk,
    signaturePaper: _PrimitivesLight.white,
    signatureBackdrop: _PrimitivesLight.clear,
  );

  /// The dark palette (ADR-0056). Every pair is measured; see
  /// [_PrimitivesDark] and each field's own ratios.
  static const AppPalette dark = AppPalette(
    canvas: _PrimitivesDark.canvas,
    card: _PrimitivesDark.card,
    edge: _PrimitivesDark.edge,
    textPrimary: _PrimitivesDark.onSurface,
    textMuted: _PrimitivesDark.onSurfaceVariant,
    surfaceMuted: _PrimitivesDark.muted,
    surfaceHover: _PrimitivesDark.hover,
    actionPrimary: _PrimitivesDark.primary,
    onActionPrimary: _PrimitivesDark.onPrimary,
    statusDanger: _PrimitivesDark.danger,
    statusSuccess: _PrimitivesDark.success,
    statusWarning: _PrimitivesDark.warning,
    statusNeutralFill: _PrimitivesDark.muted,
    statusInfoFill: _PrimitivesDark.primaryContainer,
    statusSuccessFill: _PrimitivesDark.successFill,
    statusWarningFill: _PrimitivesDark.warningFill,
    statusDangerFill: _PrimitivesDark.errorContainer,
    statusInfoForeground: _PrimitivesDark.onPrimaryContainer,
    signatureInk: _PrimitivesDark.signatureInk,
    signaturePaper: _PrimitivesDark.white,
    signatureBackdrop: _PrimitivesDark.white,
  );

  // --- surface ---

  /// The scaffold background.
  final Color canvas;

  /// The panel surface raised above [canvas] — the sidebar's fill, and,
  /// via [cardBorder], every flattened card's own fill. Plain white in the
  /// light palette.
  final Color card;

  // --- border ---

  /// The hairline every flattened card, panel and divider uses. Light:
  /// 1.22:1 against white — a hairline, never text, and below 3:1 by design
  /// (ADR-0056 records it as the one documented exception). Dark: 3.48:1 on a
  /// card and 4.25:1 on the canvas.
  final Color edge;

  // --- text ---

  /// Body and heading text. Light: 10.36:1 on a card, 9.90:1 on the canvas.
  /// Dark: 13.35:1 on a card, 16.30:1 on the canvas.
  final Color textPrimary;

  /// Secondary text — metadata, captions, anything a Screen wants read as
  /// quieter than [textPrimary] without dropping below the 4.5:1 floor.
  /// Light: 7.58:1 on a card, 7.24:1 on the canvas. Dark: 9.85:1 and 12.02:1.
  final Color textMuted;

  // --- surface ---

  /// A quiet surface rather than a colour: the table's own column-label band,
  /// and anything that wants to read as recessed next to [card]. Light: 1.17:1
  /// against white, which is what makes it a surface and never text.
  final Color surfaceMuted;

  /// The highlight that follows the pointer across a row. Light: the action
  /// colour at 10% over white. Dark: the action colour at 12%. Named here
  /// rather than left as a literal inside [rowHoverFill], so that the
  /// component layer binds a semantic value the way this file's own layer
  /// rule says it does.
  final Color surfaceHover;

  // --- action ---

  /// The Platform's one action colour — buttons, links, and the selected
  /// nav item's foreground (see [navSelectedForeground]).
  final Color actionPrimary;

  /// Text or an icon drawn on top of an [actionPrimary] fill. Light 8.72:1,
  /// dark 9.90:1.
  final Color onActionPrimary;

  // --- status ---

  /// An error, or a destructive action — but the *darker* red (5.3:1), not
  /// the theme's own `colorScheme.error` (`#DC2626`, 4.83:1 on white). The two
  /// are the same family and different jobs: `#DC2626` is red on white, which
  /// is what a destructive button and a form error need; this is red on its
  /// own pale tint, where `#DC2626` measures 3.95:1 and would fail the floor.
  /// A Screen reaches for this one whenever the red is a status rather than a
  /// call to action. Dark: red-300, 5.28:1 on [statusDangerFill] and 7.71:1 as
  /// plain text on a card.
  final Color statusDanger;

  /// Success. Material 3 has no role for this, so #102 adds one. The value is
  /// the skill palette's green family at the shade that measures against its
  /// own tint rather than against white — 6.49:1, where green-600 (`#16A34A`)
  /// measures 3.0:1 and would be a status nobody with ordinary sight could
  /// read on a chip. Dark: green-300, 6.49:1 on its fill and 10.42:1 on a card.
  final Color statusSuccess;

  /// Warning. Likewise absent from Material 3, and **orange rather than
  /// amber**: the skill's accent (`#D97706`) is this family's mid-tone and
  /// measures 2.86:1 on the tint — a highlight, never a text colour — and
  /// amber-800 measures 6.37:1 but reads as brown beside the green. This is
  /// orange-800 at 6.38:1 on the orange tint, which is the middle of the three
  /// the moment a reader looks at a list. Dark: orange-300, 9.28:1 on its
  /// fill and 8.67:1 on a card.
  final Color statusWarning;

  // --- status fills ---
  //
  // The fills half of the same five bindings, named here rather than reached
  // for as primitives by [statusFill] — the layer this file declares says a
  // component token binds a *semantic* value, and a component reaching past
  // this layer into the primitives would be the one shortcut in the file that
  // makes the layering a story rather than a rule.
  //
  // Two of them name a value another role already owns ([surfaceMuted] and the
  // scheme's own `errorContainer`): one value, two roles, written once.

  /// The quiet fill: a settled state, a deliberate cancellation, a retirement.
  final Color statusNeutralFill;

  /// The live fill — the same value as [navSelectedBackground] (the skill's
  /// border blue used as a container), because an actionable status and the
  /// selected Destination say the same thing.
  final Color statusInfoFill;

  /// The finished fill.
  final Color statusSuccessFill;

  /// The fill that wants a decision.
  final Color statusWarningFill;

  /// The fill for a fault — a step that failed.
  final Color statusDangerFill;

  /// The text on [statusInfoFill] — the scheme's own foreground, which is what
  /// `onPrimaryContainer` resolves to as well: 8.49:1 on that fill, in both
  /// palettes.
  final Color statusInfoForeground;

  // --- signature (issue #366) ---

  /// The colour a Signature is drawn in. **The same in both palettes**: a
  /// Signature is a legal mark, and the pad exports its strokes as a
  /// transparent PNG in this colour, so the exported ink must not depend on
  /// which palette the person drew it under. 10.36:1 on [signaturePaper].
  final Color signatureInk;

  /// The paper a Signature is drawn on — the pad's fill. White in both
  /// palettes: the pad shows what the exported PNG will look like on paper,
  /// and [signatureInk] is dark ink, so a dark pad would hide the very
  /// strokes it is collecting.
  final Color signaturePaper;

  /// The fill behind a stored Signature image on display. The image is dark
  /// ink on transparency (or on whatever the person uploaded), which vanishes
  /// on a dark card. Light: clear — the surface a Signature is shown on is
  /// already paper-light, and no light pixel moves. Dark: white, so the mark
  /// is shown on paper.
  final Color signatureBackdrop;

  // --- component bindings (layer 3) ---

  /// The selected sidebar destination's fill (`_NavItem` in
  /// `platform/shell.dart`). Bound to [statusInfoFill].
  Color get navSelectedBackground => statusInfoFill;

  /// The selected sidebar destination's icon and label, paired with
  /// [navSelectedBackground]: the action colour on that container, 7.15:1 in
  /// the light palette and 5.74:1 in the dark.
  Color get navSelectedForeground => actionPrimary;

  /// The hairline drawn around a flattened card, and around the inline
  /// panels that echo one — the `Border.all` a handful of dialogs draw by
  /// hand around a nested picker or list (e.g. `people/org_unit_picker.dart`,
  /// `maintenance/org_unit_chooser.dart`).
  Color get cardBorder => edge;

  /// The ring a focused control is drawn with. Named here so the
  /// keyboard-focus work #99's Implementation Decisions still owes (its
  /// user story 21) has a token to reach for rather than a reason to invent
  /// a colour; [buildAppTheme]'s own `focusColor` already spends it. Dark:
  /// 8.11:1 on a card, 9.90:1 on the canvas.
  Color get focusRing => actionPrimary;

  /// The mark drawn beside the selected Destination in the Shell (issue #168).
  ///
  /// The selected Destination already differed by fill
  /// ([navSelectedBackground]), by foreground ([navSelectedForeground]) and by
  /// label weight — but a pale tint against near-white is precisely the cue a
  /// low-vision reader or a badly calibrated display loses first, and a weight
  /// step on 14px text is a faint one. This is the cue that survives both,
  /// and it is the same action colour the selected label is already set in,
  /// so nothing new is being introduced into the palette.
  Color get navSelectedAccent => actionPrimary;

  /// The band behind a table's column labels (issue #168).
  ///
  /// The wide Work orders table's header row used to sit on the same white as
  /// its data, separated by one hairline — so it read as a fifth row rather
  /// than as a header.
  ///
  /// The first band value shipped was `#F7F7FB`, and that was wrong, caught by
  /// looking at the regenerated golden rather than by any test: against a white
  /// row it measures 1.02:1, a band nobody can see, so the header still read as
  /// a data row. It is the palette's own muted `#E9EEF6` (1.17:1) — still
  /// quiet, but visibly a band. The value is shared with
  /// [StatusTone.neutral] deliberately: "quiet fill" means the same thing in
  /// both places, and two nearly identical greys would be two things to keep in
  /// step for no gain.
  Color get tableHeaderFill => surfaceMuted;

  /// The highlight under the pointer as it tracks across a table row
  /// (issue #168).
  ///
  /// A row here is seven columns wide and is itself tappable (`_WorkOrderTableRow`'s
  /// own `InkWell`, which opens the Work order), so the pointer's own position
  /// is the only thing tying an ID at the left edge to an action at the right.
  /// Material's default hover highlight is deliberately faint and, on a white
  /// row beside six other white rows, effectively invisible — this is the
  /// action colour at 10% over white (`#E8ECF7`), which is legible as a band
  /// without becoming a selection state. Body text on it measures 8.77:1 and
  /// muted metadata 6.41:1, so the highlight never costs anybody readability.
  /// Dark: 10.21:1 and 7.53:1 over a card.
  Color get rowHoverFill => surfaceHover;

  /// The fill a status chip wears for [tone] (issue #168).
  ///
  /// A switch rather than a map so that adding a [StatusTone] is a compile
  /// error here until it is given a fill — the same reason [StatusTone] keeps
  /// the five meanings in one place. `widgets/status_chip.dart` is the only
  /// spender today; every Screen that shows a status goes through that widget
  /// rather than reaching for this method directly.
  Color statusFill(StatusTone tone) => switch (tone) {
        StatusTone.neutral => statusNeutralFill,
        StatusTone.info => statusInfoFill,
        StatusTone.success => statusSuccessFill,
        StatusTone.warning => statusWarningFill,
        StatusTone.danger => statusDangerFill,
      };

  /// The text (and icon) colour paired with [statusFill], per [tone] — the
  /// other half of the same binding. Every pair is measured, none is below the
  /// 4.5:1 floor, and `status_chip_test.dart` measures them again rather than
  /// trusting this table:
  ///
  /// | tone | light | dark |
  /// |------|-------|------|
  /// | neutral | 6.50:1 | 6.97:1 |
  /// | info | 8.49:1 | 8.49:1 |
  /// | success | 6.49:1 | 6.49:1 |
  /// | warning | 6.38:1 | 9.28:1 |
  /// | danger | 5.30:1 | 5.28:1 |
  ///
  /// The three status roles are this class' own semantic values rather than
  /// new ones, so a status colour is written down exactly once in this file.
  Color statusForeground(StatusTone tone) => switch (tone) {
        StatusTone.neutral => textMuted,
        StatusTone.info => statusInfoForeground,
        StatusTone.success => statusSuccess,
        StatusTone.warning => statusWarning,
        StatusTone.danger => statusDanger,
      };

  /// Value equality, so a palette read back from a theme that `MaterialApp`
  /// has animated to (which rebuilds the extension through [lerp]) still equals
  /// the constant it came from.
  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      canvas == other.canvas &&
      card == other.card &&
      edge == other.edge &&
      textPrimary == other.textPrimary &&
      textMuted == other.textMuted &&
      surfaceMuted == other.surfaceMuted &&
      surfaceHover == other.surfaceHover &&
      actionPrimary == other.actionPrimary &&
      onActionPrimary == other.onActionPrimary &&
      statusDanger == other.statusDanger &&
      statusSuccess == other.statusSuccess &&
      statusWarning == other.statusWarning &&
      statusNeutralFill == other.statusNeutralFill &&
      statusInfoFill == other.statusInfoFill &&
      statusSuccessFill == other.statusSuccessFill &&
      statusWarningFill == other.statusWarningFill &&
      statusDangerFill == other.statusDangerFill &&
      statusInfoForeground == other.statusInfoForeground &&
      signatureInk == other.signatureInk &&
      signaturePaper == other.signaturePaper &&
      signatureBackdrop == other.signatureBackdrop;

  @override
  int get hashCode => Object.hashAll([
        canvas,
        card,
        edge,
        textPrimary,
        textMuted,
        surfaceMuted,
        surfaceHover,
        actionPrimary,
        onActionPrimary,
        statusDanger,
        statusSuccess,
        statusWarning,
        statusNeutralFill,
        statusInfoFill,
        statusSuccessFill,
        statusWarningFill,
        statusDangerFill,
        statusInfoForeground,
        signatureInk,
        signaturePaper,
        signatureBackdrop,
      ]);

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? card,
    Color? edge,
    Color? textPrimary,
    Color? textMuted,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? actionPrimary,
    Color? onActionPrimary,
    Color? statusDanger,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusNeutralFill,
    Color? statusInfoFill,
    Color? statusSuccessFill,
    Color? statusWarningFill,
    Color? statusDangerFill,
    Color? statusInfoForeground,
    Color? signatureInk,
    Color? signaturePaper,
    Color? signatureBackdrop,
  }) =>
      AppPalette(
        canvas: canvas ?? this.canvas,
        card: card ?? this.card,
        edge: edge ?? this.edge,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        surfaceHover: surfaceHover ?? this.surfaceHover,
        actionPrimary: actionPrimary ?? this.actionPrimary,
        onActionPrimary: onActionPrimary ?? this.onActionPrimary,
        statusDanger: statusDanger ?? this.statusDanger,
        statusSuccess: statusSuccess ?? this.statusSuccess,
        statusWarning: statusWarning ?? this.statusWarning,
        statusNeutralFill: statusNeutralFill ?? this.statusNeutralFill,
        statusInfoFill: statusInfoFill ?? this.statusInfoFill,
        statusSuccessFill: statusSuccessFill ?? this.statusSuccessFill,
        statusWarningFill: statusWarningFill ?? this.statusWarningFill,
        statusDangerFill: statusDangerFill ?? this.statusDangerFill,
        statusInfoForeground: statusInfoForeground ?? this.statusInfoForeground,
        signatureInk: signatureInk ?? this.signatureInk,
        signaturePaper: signaturePaper ?? this.signaturePaper,
        signatureBackdrop: signatureBackdrop ?? this.signatureBackdrop,
      );

  /// Runs while `MaterialApp` animates between its two themes, so every field
  /// is interpolated; a field missed here would snap instead of fading.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      onActionPrimary: Color.lerp(onActionPrimary, other.onActionPrimary, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusNeutralFill: Color.lerp(statusNeutralFill, other.statusNeutralFill, t)!,
      statusInfoFill: Color.lerp(statusInfoFill, other.statusInfoFill, t)!,
      statusSuccessFill: Color.lerp(statusSuccessFill, other.statusSuccessFill, t)!,
      statusWarningFill: Color.lerp(statusWarningFill, other.statusWarningFill, t)!,
      statusDangerFill: Color.lerp(statusDangerFill, other.statusDangerFill, t)!,
      statusInfoForeground: Color.lerp(statusInfoForeground, other.statusInfoForeground, t)!,
      signatureInk: Color.lerp(signatureInk, other.signatureInk, t)!,
      signaturePaper: Color.lerp(signaturePaper, other.signaturePaper, t)!,
      signatureBackdrop: Color.lerp(signatureBackdrop, other.signatureBackdrop, t)!,
    );
  }
}

/// The one accessor a Screen reads a colour token through (issue #366):
/// `AppColors.of(context).card`.
///
/// It reads the [AppPalette] the nearest [Theme] carries and does not fall
/// back to a default: a widget pumped under a `MaterialApp` with no
/// [buildAppTheme] is a bug in whoever pumped it, and a silent light fallback
/// would hide it.
abstract final class AppColors {
  static AppPalette of(BuildContext context) => Theme.of(context).extension<AppPalette>()!;
}

/// The Platform's type scale (issue #102). Material 3's own scale already
/// supplies the exact numbers wanted, so this class names which role a
/// Screen should reach for rather than redefining any of them —
/// `ThemeData.textTheme`, built by [buildAppTheme] from the Material 3
/// defaults and tinted by the seed's `ColorScheme`, stays the source of
/// truth.
///
/// - **Body** — `bodyLarge`, 16px / 24px line height (1.5). The base size
///   this ticket asks for; new body copy should reach for this.
/// - **Dense** — `bodyMedium`, 14px / 20px. Still correct for labels,
///   metadata and dense table cells; not being replaced.
/// - **Floor** — `bodySmall`, 12px / 16px. Nothing in the Platform goes
///   below this. **Enforced as of issue #168**: the last labels that sat below
///   it — including the Shell's own Destination-group heading, at 11px — were
///   brought up to `labelMedium`, and `labelSmall` is no longer spent anywhere
///   under `lib/`. A new label below this floor is a regression, not a
///   judgement call.
///
/// The existing Screens still reach for `bodyMedium` as their body
/// default — migrating all of them is deliberately out of scope for #102
/// (see #99's Implementation Decisions on scope, and its note that
/// restyling a client about to be restructured means restyling it twice).
/// `home_screen.dart` is updated to [body] here only because #102 is
/// already touching that file for its colour fix.
abstract final class AppTypography {
  static TextStyle? body(BuildContext context) => Theme.of(context).textTheme.bodyLarge;

  static TextStyle? dense(BuildContext context) => Theme.of(context).textTheme.bodyMedium;

  static TextStyle? floor(BuildContext context) => Theme.of(context).textTheme.bodySmall;
}

/// Builds the app theme for [brightness] (issue #366): the light one by
/// default, so every existing no-argument call keeps meaning what it meant.
///
/// The palette is the `ui-ux-pro-max` design skill's own "Analytics Dashboard"
/// scheme (issue #169), approved by the user: blue data, amber warnings, red
/// failures. `colorScheme` is built from that palette and pinned role by role
/// rather than left to `fromSeed` alone — the scheme's own algorithm picks
/// *companion* tones for the roles this file does not name, but every role the
/// Platform reads is the value written down in [_PrimitivesLight] (or
/// [_PrimitivesDark]), so a Flutter upgrade cannot quietly restyle the app.
///
/// This **replaces #102's seed** (`#0F172A`, the dark slate the Platform was
/// born with). #102's own reasoning — that the Platform absorbs two
/// predecessor applications and should read as neither — still holds, and this
/// palette does not raise it: it is the design skill's own dashboard scheme,
/// not a predecessor's colours.
///
/// #102's other decision is untouched: every colour here is a named token from
/// [AppPalette], never a literal at a call site, and the flattened cards,
/// filled inputs and flattened elevation below are unchanged. Both themes
/// register their [AppPalette] as an extension, which is what [AppColors.of]
/// reads.
ThemeData buildAppTheme([Brightness brightness = Brightness.light]) => switch (brightness) {
      Brightness.light => _themeFrom(_lightScheme(), AppPalette.light),
      Brightness.dark => _themeFrom(_darkScheme(), AppPalette.dark),
    };

/// The light palette, pinned role by role (issue #169). `fromSeed` still picks
/// the *companion* tones for the roles this file does not name — the inverse
/// roles, the tertiary family, the surface tints nothing here reads — but
/// every role the Platform actually renders is the value written down in
/// `_PrimitivesLight`, so `fromSeed`'s algorithm (which #102 already noted is
/// not guaranteed stable across Flutter releases) cannot quietly restyle the
/// app on the next upgrade.
ColorScheme _lightScheme() => ColorScheme.fromSeed(
      seedColor: _PrimitivesLight.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: _PrimitivesLight.primary,
      onPrimary: _PrimitivesLight.onPrimary,
      primaryContainer: _PrimitivesLight.primaryContainer,
      // The same value the scheme's own `onSurface` gets, in a second role.
      onPrimaryContainer: _PrimitivesLight.onSurface,
      error: _PrimitivesLight.error,
      onError: _PrimitivesLight.onError,
      errorContainer: _PrimitivesLight.errorContainer,
      onErrorContainer: _PrimitivesLight.onErrorContainer,
      surface: _PrimitivesLight.white,
      onSurface: _PrimitivesLight.onSurface,
      onSurfaceVariant: _PrimitivesLight.onSurfaceVariant,
      // The hairline. Every table row, card and panel reaches for this through
      // `outlineVariant` (`_WorkOrderTableRow`'s own bottom border), so it is
      // the palette's border rather than a generated one.
      outlineVariant: _PrimitivesLight.edge,
      // The rim of an outlined control, which is a different job from the
      // hairline above and needs a different weight to do it: 4.76:1 rather than
      // 1.22:1, so an OutlinedButton or an input reads as something you can
      // press. Left to `fromSeed`, this came out a neutral grey at roughly 1.6:1
      // and every outlined control read as disabled.
      outline: _PrimitivesLight.outline,
      // Read by the skeleton placeholders and the sidebar's own avatar fill.
      surfaceContainerHighest: _PrimitivesLight.muted,
      // A deliberate binding to what this client actually paints with the role
      // (issue #169): every write confirmation in the Platform — "Work order
      // raised", "Employee corrected" — is a notice banner wearing
      // `secondaryContainer` with `onSecondaryContainer` on it, and failures wear
      // `errorContainer` beside them. So the "something worked" surface is the
      // success pair, and a confirmation reads green the way the green status
      // does rather than as a second, unexplained lavender.
      //
      // This is a statement about this client's use of the role, not a claim
      // about Material's secondary semantics: a future Screen that wants a real
      // secondary colour needs its own token rather than this one.
      secondaryContainer: _PrimitivesLight.successFill,
      onSecondaryContainer: _PrimitivesLight.success,
    );

/// The dark palette, the same shape as [_lightScheme] (issue #366): every role
/// the Platform reads is pinned to a named dark primitive, plus the roles
/// Material widgets read implicitly — a dialog, a menu and a date picker
/// (`surfaceContainer*`, `surfaceTint`) and a snackbar (`inverse*`) — so text
/// on those surfaces is measured too, and a Flutter upgrade cannot restyle
/// dark any more than light.
ColorScheme _darkScheme() => ColorScheme.fromSeed(
      seedColor: _PrimitivesDark.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _PrimitivesDark.primary,
      onPrimary: _PrimitivesDark.onPrimary,
      primaryContainer: _PrimitivesDark.primaryContainer,
      onPrimaryContainer: _PrimitivesDark.onPrimaryContainer,
      error: _PrimitivesDark.error,
      onError: _PrimitivesDark.onError,
      errorContainer: _PrimitivesDark.errorContainer,
      onErrorContainer: _PrimitivesDark.onErrorContainer,
      surface: _PrimitivesDark.card,
      onSurface: _PrimitivesDark.onSurface,
      onSurfaceVariant: _PrimitivesDark.onSurfaceVariant,
      outlineVariant: _PrimitivesDark.edge,
      outline: _PrimitivesDark.outline,
      // The stack of surfaces Material 3 widgets pick from. A card is `card`,
      // the canvas is the lowest step, a dialog / menu / date picker is
      // `raised`, and the skeletons and avatar fill are `muted`.
      surfaceContainerLowest: _PrimitivesDark.canvas,
      surfaceContainerLow: _PrimitivesDark.card,
      surfaceContainer: _PrimitivesDark.raised,
      surfaceContainerHigh: _PrimitivesDark.raised,
      surfaceContainerHighest: _PrimitivesDark.muted,
      surfaceTint: _PrimitivesDark.primary,
      // A snackbar: pale surface, dark text, and the action text on it.
      inverseSurface: _PrimitivesDark.inverseSurface,
      onInverseSurface: _PrimitivesDark.onInverseSurface,
      inversePrimary: _PrimitivesDark.inversePrimary,
      secondaryContainer: _PrimitivesDark.successFill,
      onSecondaryContainer: _PrimitivesDark.success,
    );

ThemeData _themeFrom(ColorScheme scheme, AppPalette palette) {
  // A focused control's own visible ring (#99 user story 21, #104's own
  // accessibility criteria): `focusColor` below feeds `InkWell`/`Focus`
  // directly, but a Material 3 `ButtonStyleButton` (`OutlinedButton`,
  // `FilledButton`, `IconButton`) resolves its *own* default overlay for
  // `WidgetState.focused` rather than reading `ThemeData.focusColor` — so
  // without this, a focused button would still show Material's own subtle
  // default rather than this app's own [AppPalette.focusRing].
  // Wired once here, at the theme, rather than per button style at each
  // call site, so every current and future button gets the same ring for
  // free — `work_orders_test.dart`'s own focus test reads these two
  // `ButtonStyle`s back off a pumped `Theme.of(context)` to prove it.
  final focusedOverlay = WidgetStateProperty.resolveWith<Color?>(
    (states) =>
        states.contains(WidgetState.focused) ? palette.focusRing.withValues(alpha: 0.16) : null,
  );
  final focusedSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: palette.focusRing, width: 2)
        : null,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: palette.canvas,
    focusColor: palette.focusRing.withValues(alpha: 0.12),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: palette.cardBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(overlayColor: focusedOverlay, side: focusedSide),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(overlayColor: focusedOverlay),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(overlayColor: focusedOverlay, side: focusedSide),
    ),
    extensions: <ThemeExtension<dynamic>>[palette],
  );
}
