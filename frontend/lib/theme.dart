import 'package:flutter/material.dart';

/// Design tokens for the app: spacing, radius, and — as of issue #102 — a
/// three-layer colour system plus a named type scale.
///
/// The three colour layers, each built only from the one before it:
///
/// 1. **Primitive** (`_Primitives`, private to this file) — the raw hex
///    values themselves, and nothing else. A primitive is never spent
///    directly by a Screen; it exists so a value is written down exactly
///    once.
/// 2. **Semantic** ([AppColors]) — the same values named for the ROLE they
///    play (surface, border, text, action, status), never for what they
///    look like. This is the layer a Screen reaches for.
/// 3. **Component** ([AppComponentColors]) — a semantic value bound to a
///    shape that repeats across more than one widget (a selected nav
///    item's fill, a card's hairline, a focus ring), named for that shape
///    so the binding is made once rather than re-derived at each call
///    site.
///
/// **No `Color` literal and no `Colors.*` constant may appear anywhere
/// under `frontend/lib/` outside this file.** `theme_skeleton_test.dart`
/// enforces that by reading every other source file under `lib/` and
/// failing if one is found — so the rule survives the next agent rather
/// than relying on review to catch it. A Screen that needs a colour reaches
/// for [AppColors] or [AppComponentColors], or, for anything neither names,
/// for `Theme.of(context).colorScheme` directly — that is theme-derived
/// rather than literal, so it is never a violation.
///
/// Dark mode is out of scope for this pass (#99's Implementation
/// Decisions) — only the light palette ships — but nothing here is read
/// except through its semantic name, so adding a second palette later is a
/// values change to this file alone, not a Screen-by-Screen rewrite.
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

/// Layer 1 — primitives. Raw values only, and only the ones a semantic or
/// component token below actually spends.
///
/// `primary`, `onPrimary`, `primaryContainer`, `error`, `onSurface` and
/// `onSurfaceVariant` are `ColorScheme.fromSeed(0xFF0F172A)`'s own output on
/// the pinned Flutter 3.44.0 — dumped once against the real SDK and
/// recorded here as literals rather than re-derived, since `fromSeed`'s
/// algorithm is not guaranteed stable across Flutter releases (issue #102).
/// The same seed also produces `onPrimaryContainer` (`#2F4578`), `outline`
/// (`#757780`), `outlineVariant` (`#C5C6D0`) and `surfaceContainerHighest`
/// (`#E2E2E9`); those four earn no constant here because nothing in the app
/// spends them by name — they are read straight off
/// `Theme.of(context).colorScheme` where they are used (the selected nav
/// item's `_AccountFooter` avatar in `platform/shell.dart`, and
/// `widgets/skeleton_list.dart`'s placeholder fill), which is theme-derived
/// rather than a literal, so naming them again here would just be a second
/// copy of a value Flutter already hands out.
///
/// `success` and `warning` fill the two status roles Material 3 does not
/// define. Both were chosen, and measured rather than estimated, to sit
/// alongside `primary` and `error`, which each measure 6.46:1 against
/// white.
abstract final class _Primitives {
  static const Color primary = Color(0xFF475D92);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFD9E2FF);
  static const Color error = Color(0xFFBA1A1A);
  static const Color onSurface = Color(0xFF1A1B20);
  static const Color onSurfaceVariant = Color(0xFF44464F);

  /// 6.53:1 against white.
  static const Color success = Color(0xFF146C2E);

  /// 6.45:1 against white.
  static const Color warning = Color(0xFF8A5100);

  /// The scaffold background, unchanged by #102 — a cool off-white that
  /// lets cards read as one surface next to the sidebar.
  static const Color canvas = Color(0xFFF7F7FB);

  /// The hairline every flattened card and panel uses, unchanged by #102.
  static const Color edge = Color(0xFFE3E3EC);

  /// Plain white — the sidebar and filled-input surface. Unchanged by
  /// #102: it was already this exact value as a `Colors.white` literal in
  /// `platform/shell.dart` and in this file's own `InputDecorationTheme`
  /// before this rewrite gave it a name.
  static const Color white = Color(0xFFFFFFFF);
}

/// Layer 2 — semantic tokens, named for the role they play rather than
/// their appearance. This is the layer a Screen reaches for; see this
/// file's top doc comment for the full three-layer picture (issue #102).
///
/// `canvas` and `edge` predate this rewrite and keep both their names and
/// their values unchanged — only their place in the layering is new.
abstract final class AppColors {
  // --- surface ---

  /// The scaffold background.
  static const Color canvas = _Primitives.canvas;

  /// The panel surface raised above [canvas] — the sidebar's fill, and,
  /// via [AppComponentColors.cardBorder], every flattened card's own fill.
  /// Plain white, same as before this rewrite; only its name is new.
  static const Color card = _Primitives.white;

  // --- border ---

  /// The hairline every flattened card, panel and divider uses.
  static const Color edge = _Primitives.edge;

  // --- text ---

  /// Body and heading text.
  static const Color textPrimary = _Primitives.onSurface;

  /// Secondary text — metadata, captions, anything a Screen wants read as
  /// quieter than [textPrimary] without dropping below the 4.5:1 floor.
  static const Color textMuted = _Primitives.onSurfaceVariant;

  // --- action ---

  /// The Platform's one action colour — buttons, links, and the selected
  /// nav item's foreground (see [AppComponentColors.navSelectedForeground]).
  static const Color actionPrimary = _Primitives.primary;

  /// Text or an icon drawn on top of an [actionPrimary] fill.
  static const Color onActionPrimary = _Primitives.onPrimary;

  // --- status ---

  /// An error, or a destructive action. Backed by Material 3's own `error`
  /// role, carried across under a status name so a Screen never has to
  /// choose between this and `theme.colorScheme.error` and risk two
  /// different answers.
  static const Color statusDanger = _Primitives.error;

  /// Success. Material 3 has no role for this, so #102 adds one — 6.53:1
  /// against white. Replaces the `Colors.green.shade700` that used to sit
  /// in `home_screen.dart` at 4.12:1, below the 4.5:1 floor.
  static const Color statusSuccess = _Primitives.success;

  /// Warning. Likewise absent from Material 3 — 6.45:1 against white.
  static const Color statusWarning = _Primitives.warning;
}

/// Layer 3 — component tokens: a semantic value bound to a shape that
/// repeats across more than one widget, named for that shape so the
/// binding is made once rather than re-derived at each call site (issue
/// #102).
abstract final class AppComponentColors {
  /// The selected sidebar destination's fill (`_NavItem` in
  /// `platform/shell.dart`).
  static const Color navSelectedBackground = _Primitives.primaryContainer;

  /// The selected sidebar destination's icon and label, paired with
  /// [navSelectedBackground].
  static const Color navSelectedForeground = AppColors.actionPrimary;

  /// The hairline drawn around a flattened card, and around the inline
  /// panels that echo one — the `Border.all` a handful of dialogs draw by
  /// hand around a nested picker or list (e.g. `people/org_unit_picker.dart`,
  /// `maintenance/org_unit_chooser.dart`).
  static const Color cardBorder = AppColors.edge;

  /// The ring a focused control is drawn with. Named here so the
  /// keyboard-focus work #99's Implementation Decisions still owes (its
  /// user story 21) has a token to reach for rather than a reason to invent
  /// a colour; [buildAppTheme]'s own `focusColor` already spends it.
  static const Color focusRing = AppColors.actionPrimary;
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
///   below this.
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

/// Builds the app theme.
///
/// Matches the pre-existing look exactly — same seed, same canvas, same
/// flattened cards and filled inputs — just moved here so screens share it
/// instead of each shipping their own copy. The seed is the Platform's own
/// dark slate, moved here from the inline `ThemeData` that used to live in
/// `main.dart`; `employee-management`'s indigo is deliberately not inherited
/// — the Platform absorbs both predecessors, and adopting either predecessor's
/// palette would make it read as that application grown larger (issue #33's
/// Implementation Decisions).
///
/// #102 changes what feeds this function, not what it produces: every
/// colour written here is now a named token from [AppColors] or
/// [AppComponentColors] rather than a literal, and no pixel moves as a
/// result — [AppColors.card] and [AppComponentColors.cardBorder] are the
/// same white and the same hairline the old `Colors.white` literal and
/// `AppColors.edge` already were.
ThemeData buildAppTheme() {
  // A focused control's own visible ring (#99 user story 21, #104's own
  // accessibility criteria): `focusColor` above feeds `InkWell`/`Focus`
  // directly, but a Material 3 `ButtonStyleButton` (`OutlinedButton`,
  // `FilledButton`, `IconButton`) resolves its *own* default overlay for
  // `WidgetState.focused` rather than reading `ThemeData.focusColor` — so
  // without this, a focused button would still show Material's own subtle
  // default rather than this app's own [AppComponentColors.focusRing].
  // Wired once here, at the theme, rather than per button style at each
  // call site, so every current and future button gets the same ring for
  // free — `work_orders_test.dart`'s own focus test reads these two
  // `ButtonStyle`s back off a pumped `Theme.of(context)` to prove it.
  final focusedOverlay = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.focused)
        ? AppComponentColors.focusRing.withValues(alpha: 0.16)
        : null,
  );
  final focusedSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: AppComponentColors.focusRing, width: 2)
        : null,
  );

  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF0F172A),
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.canvas,
    focusColor: AppComponentColors.focusRing.withValues(alpha: 0.12),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppComponentColors.cardBorder),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
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
  );
}
