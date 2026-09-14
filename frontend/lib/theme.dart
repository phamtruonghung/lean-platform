import 'package:flutter/material.dart';

import 'status_tone.dart';

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

  /// The paired foreground for [primaryContainer] — the exact value
  /// `ColorScheme.fromSeed(0xFF0F172A)` produces for `onPrimaryContainer` on
  /// the pinned Flutter 3.44.0, recorded here because an `info` status chip
  /// (issue #168) needs a text colour to sit on that fill. 7.25:1 against it.
  static const Color onPrimaryContainer = Color(0xFF2F4578);

  /// The status fills (issue #168) — one tint per [StatusTone], each measured
  /// against its own foreground below and none below 4.5:1. `info` has no new
  /// value here: it deliberately reuses [primaryContainer], because an
  /// actionable status and the selected Destination are saying the same thing
  /// ("this is the live one") and two near-identical blues a reader has to
  /// tell apart would be worse than one that repeats.
  static const Color neutralFill = Color(0xFFEDEEF3);
  static const Color successFill = Color(0xFFDEEFE1);
  static const Color warningFill = Color(0xFFFAECD6);
  static const Color dangerFill = Color(0xFFFBE0DF);

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

  /// The mark drawn beside the selected Destination in the Shell (issue #168).
  ///
  /// The selected Destination already differed by fill
  /// ([navSelectedBackground]), by foreground ([navSelectedForeground]) and by
  /// label weight — but a pale tint against near-white is precisely the cue a
  /// low-vision reader or a badly calibrated display loses first, and a weight
  /// step on 14px text is a faint one. This is the cue that survives both,
  /// and it is the same action colour the selected label is already set in,
  /// so nothing new is being introduced into the palette.
  static const Color navSelectedAccent = AppColors.actionPrimary;

  /// The band behind a table's column labels (issue #168).
  ///
  /// The wide Work orders table's header row used to sit on the same white as
  /// its data, separated by one hairline — so it read as a fifth row rather
  /// than as a header.
  ///
  /// This first shipped as [AppColors.canvas] (`#F7F7FB`) and that was wrong,
  /// caught by looking at the regenerated golden rather than by any test:
  /// against a white row, `#F7F7FB` measures 1.02:1, which is a band nobody
  /// can see, so the header still read as a data row. It is the neutral status
  /// fill instead (`#EDEEF3`, 1.16:1) — still quiet, but visibly a band, the
  /// same weight of grey every table header anybody has used already is. The
  /// value is shared with [StatusTone.neutral] deliberately: "quiet fill"
  /// means the same thing in both places, and two nearly identical greys would
  /// be two things to keep in step for no gain.
  static const Color tableHeaderFill = _Primitives.neutralFill;

  /// The highlight under the pointer as it tracks across a table row
  /// (issue #168).
  ///
  /// A row here is seven columns wide and is itself tappable (`_WorkOrderTableRow`'s
  /// own `InkWell`, which opens the Work order), so the pointer's own position
  /// is the only thing tying an ID at the left edge to an action at the right.
  /// Material's default hover highlight is deliberately faint and, on a white
  /// row beside six other white rows, effectively invisible — this is the
  /// action colour at 10% over white (`#ECEEF4`), which is legible as a band
  /// without becoming a selection state. Body text on it still measures above
  /// 15:1, so the highlight never costs anybody readability.
  static const Color rowHoverFill = Color(0x1A475D92);

  /// The fill a status chip wears for [tone] (issue #168).
  ///
  /// A switch rather than a map so that adding a [StatusTone] is a compile
  /// error here until it is given a fill — the same reason [StatusTone] keeps
  /// the five meanings in one place. `widgets/status_chip.dart` is the only
  /// spender today; every Screen that shows a status goes through that widget
  /// rather than reaching for this method directly.
  static Color statusFill(StatusTone tone) => switch (tone) {
        StatusTone.neutral => _Primitives.neutralFill,
        StatusTone.info => _Primitives.primaryContainer,
        StatusTone.success => _Primitives.successFill,
        StatusTone.warning => _Primitives.warningFill,
        StatusTone.danger => _Primitives.dangerFill,
      };

  /// The text (and icon) colour paired with [statusFill], per [tone] — the
  /// other half of the same binding. Every pair is measured and none is below
  /// 4.5:1 (issue #168; `status_chip_test.dart` asserts this rather than
  /// trusting the comment):
  ///
  /// | tone | against its own fill |
  /// |------|----------------------|
  /// | neutral | 8.11:1 |
  /// | info | 7.25:1 |
  /// | success | 5.46:1 |
  /// | warning | 5.54:1 |
  /// | danger | 5.18:1 |
  ///
  /// The three status roles are [AppColors]' own semantic values rather than
  /// new ones, so a status colour is written down exactly once in this file.
  static Color statusForeground(StatusTone tone) => switch (tone) {
        StatusTone.neutral => AppColors.textMuted,
        StatusTone.info => _Primitives.onPrimaryContainer,
        StatusTone.success => AppColors.statusSuccess,
        StatusTone.warning => AppColors.statusWarning,
        StatusTone.danger => AppColors.statusDanger,
      };
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
