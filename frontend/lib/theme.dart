import 'package:flutter/material.dart';

/// Design tokens for the app.
///
/// The scaffold's theme and the per-screen `EdgeInsets` literals used to be
/// scattered through `main.dart`. Putting the rhythm in one place means a
/// screen no longer invents its own padding, and a future "scale by text size"
/// adjustment is a one-line change here instead of a sweep through the code.
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

/// The application surface colours, extracted from `main.dart` so the shell,
/// cards and content agree even as the palette grows.
abstract final class AppColors {
  /// The scaffold background — a cool off-white that lets cards read as one
  /// surface next to the tinted sidebar.
  static const Color canvas = Color(0xFFF7F7FB);

  /// The hairline border every flattened card uses.
  static const Color edge = Color(0xFFE3E3EC);
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
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF0F172A),
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.canvas,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.edge),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
    ),
  );
}
