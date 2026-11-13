/// `PaletteToggle`: the one control that switches the Platform between its two
/// palettes (issue #415, on top of #366 / ADR-0056).
///
/// **Why one widget.** The dark palette shipped in #366 with exactly one way to
/// reach it: a `Dark palette` item inside the Shell's account menu. That left
/// the front door — the sign-in Screen, which is drawn outside the Shell —
/// with no control at all, and left a person inside the app hunting their own
/// avatar for a setting. Its own issue, one widget, drawn in both places rather
/// than a second hand-rolled toggle per Screen.
///
/// **It decides nothing.** [darkPalette] is which palette is on screen and
/// [onPressed] is what to do about it, exactly the pair the Shell already took
/// for its menu item (issue #366): the counting of
/// `ThemeMode.system` against the browser's own preference belongs to whoever
/// holds the cubit, not to a button. The same choice is therefore made in one
/// place for both surfaces, and this widget is pumpable in a test with no
/// provider.
///
/// **It says which palette a tap gives you**, in an icon (`light_mode` when the
/// dark palette is on, `dark_mode` when it is not) and in the tooltip's own
/// words — never by colour alone.
///
/// [buttonKey] is the flat `ValueKey` both surfaces share; a test that has two
/// of them on screen at once (Shell and, say, a dialog) scopes by ancestor
/// instead of inventing a second key.
library;

import 'package:flutter/material.dart';

/// The palette switch, sized by [IconButton]'s own 48px box — above the
/// Platform's 44px floor rather than exactly at it.
class PaletteToggle extends StatelessWidget {
  const PaletteToggle({
    super.key,
    required this.darkPalette,
    required this.onPressed,
    this.darkTooltip,
    this.lightTooltip,
  });

  /// Whether the dark palette is the one on screen right now.
  final bool darkPalette;

  /// Switches to the other one. The caller owns which palette that is.
  final VoidCallback onPressed;

  /// The words to offer when a tap gives the dark palette, or null for
  /// [toDarkTooltip]. The Shell passes its own catalogue's words, because it is
  /// drawn inside the app's language (issue t_c68dfd6e's review); the sign-in
  /// Screen passes nothing and keeps the English constants below until its own
  /// slice translates that Screen's copy.
  final String? darkTooltip;

  /// The words to offer when a tap gives the light palette, or null for
  /// [toLightTooltip].
  final String? lightTooltip;

  static const ValueKey<String> buttonKey = ValueKey<String>('app-palette-toggle');

  /// What a tap gives you, said in words for the tooltip and the screen reader.
  static const String toDarkTooltip = 'Switch to the dark palette';
  static const String toLightTooltip = 'Switch to the light palette';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      key: buttonKey,
      tooltip: darkPalette ? (lightTooltip ?? toLightTooltip) : (darkTooltip ?? toDarkTooltip),
      color: theme.colorScheme.onSurfaceVariant,
      onPressed: onPressed,
      // The icon names the palette a tap brings, not the one already on screen.
      icon: Icon(darkPalette ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
