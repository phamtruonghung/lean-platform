/// Every pair the two palettes hand out, measured (issue #366, ADR-0056): text
/// on its own surface at 4.5:1, anything that is not text at 3:1, and the five
/// status pairs at 4.5:1.
///
/// Reads the pairs off the two built `ThemeData`s rather than off the
/// primitives, so it measures what a Screen would resolve — the pinned
/// `ColorScheme` roles as well as the `AppPalette` tokens. Alpha colours are
/// composited over the surface they sit on before they are measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/status_tone.dart';
import 'package:lean_platform/theme.dart';

import 'contrast.dart';

class _Pair {
  const _Pair(this.name, this.foreground, this.background);

  final String name;
  final Color foreground;
  final Color background;

  double get ratio => contrastRatio(foreground, background);
}

/// Text on a surface it is actually drawn on: 4.5:1.
List<_Pair> _textPairs(ThemeData theme, {required bool pinnedImplicitRoles}) {
  final scheme = theme.colorScheme;
  final palette = theme.extension<AppPalette>()!;

  // A dialog, a menu and a date picker read `surfaceContainer*`. The dark
  // scheme pins those roles, so they are measured; the light one leaves them to
  // `fromSeed`, which this change does not touch (and on which
  // `colorScheme.error` happens to measure 3.94:1 — a pre-existing property of
  // the light palette that ADR-0056 records rather than fixes).
  final implicit = <String, Color>{
    if (pinnedImplicitRoles) 'dialog': scheme.surfaceContainerHigh,
    if (pinnedImplicitRoles) 'menu': scheme.surfaceContainer,
  };
  final surfaces = <String, Color>{
    'card': palette.card,
    'canvas': palette.canvas,
    'surfaceMuted': palette.surfaceMuted,
    'row hover over a card': compositeOver(palette.surfaceHover, palette.card),
    'row hover over the canvas': compositeOver(palette.surfaceHover, palette.canvas),
    ...implicit,
  };
  // Surfaces that carry an accent, a status or an error as plain text.
  final accentSurfaces = <String, Color>{
    'card': palette.card,
    'canvas': palette.canvas,
    ...implicit,
  };

  return [
    for (final MapEntry(key: surface, value: background) in surfaces.entries) ...[
      _Pair('textPrimary on $surface', palette.textPrimary, background),
      _Pair('textMuted on $surface', palette.textMuted, background),
      _Pair('colorScheme.onSurface on $surface', scheme.onSurface, background),
      _Pair('colorScheme.onSurfaceVariant on $surface', scheme.onSurfaceVariant, background),
    ],
    for (final MapEntry(key: surface, value: background) in accentSurfaces.entries) ...[
      _Pair('colorScheme.error on $surface', scheme.error, background),
      _Pair('colorScheme.primary on $surface', scheme.primary, background),
      _Pair('actionPrimary on $surface', palette.actionPrimary, background),
      _Pair('statusDanger as text on $surface', palette.statusDanger, background),
      _Pair('statusSuccess as text on $surface', palette.statusSuccess, background),
      _Pair('statusWarning as text on $surface', palette.statusWarning, background),
    ],
    _Pair('onPrimary on primary', scheme.onPrimary, scheme.primary),
    _Pair('onActionPrimary on actionPrimary', palette.onActionPrimary, palette.actionPrimary),
    _Pair('onError on error', scheme.onError, scheme.error),
    _Pair('onPrimaryContainer on primaryContainer', scheme.onPrimaryContainer,
        scheme.primaryContainer),
    _Pair('onErrorContainer on errorContainer', scheme.onErrorContainer, scheme.errorContainer),
    _Pair('onSecondaryContainer on secondaryContainer', scheme.onSecondaryContainer,
        scheme.secondaryContainer),
    _Pair('the selected Destination: foreground on fill', palette.navSelectedForeground,
        palette.navSelectedBackground),
    for (final tone in StatusTone.values)
      _Pair('status ${tone.name}: label on fill', palette.statusForeground(tone),
          palette.statusFill(tone)),
    // A snackbar. Pinned (and so measured) in the dark scheme; the light one
    // keeps what `fromSeed` generates, which this change does not touch.
    if (pinnedImplicitRoles) ...[
      _Pair('onInverseSurface on inverseSurface', scheme.onInverseSurface, scheme.inverseSurface),
      _Pair('inversePrimary on inverseSurface', scheme.inversePrimary, scheme.inverseSurface),
    ],
    _Pair(
      'onSignatureBackdrop on the Signature backdrop',
      palette.onSignatureBackdrop,
      compositeOver(palette.signatureBackdrop, palette.card),
    ),
  ];
}

/// Things that are not text: 3:1 (WCAG 1.4.11).
List<_Pair> _nonTextPairs(ThemeData theme, {required bool pinnedImplicitRoles}) {
  final scheme = theme.colorScheme;
  final palette = theme.extension<AppPalette>()!;
  return [
    for (final (surface, background) in [
      ('card', palette.card),
      ('canvas', palette.canvas),
      if (pinnedImplicitRoles) ('dialog', scheme.surfaceContainerHigh),
    ]) ...[
      _Pair('outline (an outlined control\'s rim) on $surface', scheme.outline, background),
      _Pair('focusRing on $surface', palette.focusRing, background),
    ],
    _Pair('navSelectedAccent on the selected Destination\'s fill', palette.navSelectedAccent,
        palette.navSelectedBackground),
  ];
}

void main() {
  final palettes = <String, ThemeData>{
    'light': buildAppTheme(),
    'dark': buildAppTheme(Brightness.dark),
  };

  for (final MapEntry(key: name, value: theme) in palettes.entries) {
    group('the $name palette', () {
      test('every text pair measures at least 4.5:1', () {
        for (final pair in _textPairs(theme, pinnedImplicitRoles: name == 'dark')) {
          expect(
            pair.ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${pair.name} measured ${pair.ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('everything that is not text measures at least 3:1', () {
        for (final pair in _nonTextPairs(theme, pinnedImplicitRoles: name == 'dark')) {
          expect(
            pair.ratio,
            greaterThanOrEqualTo(3.0),
            reason: '${pair.name} measured ${pair.ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });
  }

  group('the hairline (edge)', () {
    test('dark clears 3:1 on both a card and the canvas', () {
      final palette = AppPalette.dark;
      expect(contrastRatio(palette.edge, palette.card), greaterThanOrEqualTo(3.0));
      expect(contrastRatio(palette.edge, palette.canvas), greaterThanOrEqualTo(3.0));
    });

    // A named, documented exception (ADR-0056): the light hairline is a
    // deliberately quiet 1.22:1, and the light palette must not move a pixel,
    // so it cannot be held to 3:1. Pinned to its measured value so it can
    // only get no quieter, rather than being silently excused.
    test('light is the documented exception, pinned to its measured 1.22:1', () {
      final palette = AppPalette.light;
      expect(contrastRatio(palette.edge, palette.card), closeTo(1.22, 0.005));
      expect(contrastRatio(palette.edge, palette.canvas), closeTo(1.17, 0.005));
    });
  });

  test('every palette field is interpolated, so a theme change does not snap', () {
    // `MaterialApp` lerps the two themes when the mode changes; a field missed
    // in `lerp` would jump rather than fade. Half-way must differ from both
    // ends wherever the two ends differ.
    final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);
    final light = AppPalette.light;
    final dark = AppPalette.dark;
    expect(mid.canvas, isNot(light.canvas));
    expect(mid.canvas, isNot(dark.canvas));
    expect(mid.card, isNot(light.card));
    expect(mid.edge, isNot(light.edge));
    expect(mid.textPrimary, isNot(light.textPrimary));
    expect(mid.textMuted, isNot(light.textMuted));
    expect(mid.surfaceMuted, isNot(light.surfaceMuted));
    expect(mid.surfaceHover, isNot(light.surfaceHover));
    expect(mid.actionPrimary, isNot(light.actionPrimary));
    expect(mid.onActionPrimary, isNot(light.onActionPrimary));
    expect(mid.statusDanger, isNot(light.statusDanger));
    expect(mid.statusSuccess, isNot(light.statusSuccess));
    expect(mid.statusWarning, isNot(light.statusWarning));
    expect(mid.statusNeutralFill, isNot(light.statusNeutralFill));
    expect(mid.statusInfoFill, isNot(light.statusInfoFill));
    expect(mid.statusSuccessFill, isNot(light.statusSuccessFill));
    expect(mid.statusWarningFill, isNot(light.statusWarningFill));
    expect(mid.statusDangerFill, isNot(light.statusDangerFill));
    expect(mid.statusInfoForeground, isNot(light.statusInfoForeground));
    expect(mid.signatureBackdrop, isNot(light.signatureBackdrop));
    // And `copyWith` carries every field through unchanged.
    expect(light.copyWith(), light);
    expect(light.lerp(dark, 1), dark);
    expect(light.lerp(dark, 0), light);
    expect(dark.copyWith(canvas: light.canvas).canvas, light.canvas);
    expect(dark.copyWith().statusDangerFill, dark.statusDangerFill);
  });

  test('a Signature is drawn the same in both palettes', () {
    // The exported mark is a legal one: its ink, and the paper it is collected
    // on, do not depend on the palette.
    expect(AppPalette.dark.signatureInk, AppPalette.light.signatureInk);
    expect(AppPalette.dark.signaturePaper, AppPalette.light.signaturePaper);
    expect(
      contrastRatio(AppPalette.dark.signatureInk, AppPalette.dark.signaturePaper),
      greaterThanOrEqualTo(4.5),
    );
    // And the backdrop that shows a stored Signature is white in dark, where
    // the card behind it would swallow dark ink, and invisible in light.
    expect(AppPalette.dark.signatureBackdrop, const Color(0xFFFFFFFF));
    expect(AppPalette.light.signatureBackdrop.a, 0);
    expect(AppPalette.dark.onSignatureBackdrop, const Color(0xFF475569));
    expect(AppPalette.light.onSignatureBackdrop, const Color(0xFF475569));
  });
}
