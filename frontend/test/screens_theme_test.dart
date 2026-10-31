import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/theme.dart';

void main() {
  testWidgets('SignInScreen sits on the canvas background and keeps its copy',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const SignInScreen()),
    );

    final context = tester.element(find.byType(Scaffold));
    // Neither screen sets its own Scaffold background, so the effective
    // colour is whatever the theme resolves it to.
    expect(Theme.of(context).scaffoldBackgroundColor, AppPalette.light.canvas);

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('AwaitingApprovalScreen keeps its heading and the flattened card treatment',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const AwaitingApprovalScreen(email: 'a@b.c'),
      ),
    );

    expect(find.text('Awaiting approval'), findsOneWidget);

    final context = tester.element(find.byType(AwaitingApprovalScreen));
    final cardTheme = Theme.of(context).cardTheme;
    expect(cardTheme.elevation, 0);
    final shape = cardTheme.shape as RoundedRectangleBorder;
    expect(shape.side.color, AppPalette.light.edge);
  });

  // Issue #366: two palettes from one builder. Literal hexes, so these
  // assertions do not simply mirror the code that produces the values.
  group('the two themes resolve to their own palette', () {
    ThemeData resolve(Brightness brightness) => buildAppTheme(brightness);

    test('light is exactly what it was before the dark palette existed', () {
      final theme = resolve(Brightness.light);
      expect(buildAppTheme().colorScheme, theme.colorScheme);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect((theme.cardTheme.shape as RoundedRectangleBorder).side.color,
          const Color(0xFFDBEAFE));
      expect(theme.inputDecorationTheme.fillColor, const Color(0xFFFFFFFF));
      // The Card's fill is pinned directly: the only other guard is three
      // light-palette goldens.
      expect(theme.cardTheme.color, AppPalette.light.card);
      expect(theme.cardTheme.color, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF1E3A8A));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF475569));
      expect(theme.colorScheme.primary, const Color(0xFF1E40AF));
      expect(theme.colorScheme.outline, const Color(0xFF64748B));
      expect(theme.extension<AppPalette>(), AppPalette.light);
    });

    test('dark pins its canvas, card hairline and text to the dark palette', () {
      final theme = resolve(Brightness.dark);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F172A));
      expect((theme.cardTheme.shape as RoundedRectangleBorder).side.color,
          const Color(0xFF6B7D96));
      expect(theme.inputDecorationTheme.fillColor, const Color(0xFF1E293B));
      // The Card's fill is pinned directly: dark maps surfaceContainerLow to
      // the same primitive, so a dark cardTheme break would otherwise be silent.
      expect(theme.cardTheme.color, AppPalette.dark.card);
      expect(theme.cardTheme.color, const Color(0xFF1E293B));
      expect(theme.colorScheme.onSurface, const Color(0xFFF1F5F9));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFCBD5E1));
      expect(theme.colorScheme.primary, const Color(0xFF93C5FD));
      expect(theme.extension<AppPalette>(), AppPalette.dark);
    });

    testWidgets('a Screen reads the palette of the theme it is under', (tester) async {
      late BuildContext inner;
      for (final (theme, expected) in [
        (buildAppTheme(), AppPalette.light),
        (buildAppTheme(Brightness.dark), AppPalette.dark),
      ]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            inner = context;
            return const SizedBox();
          }),
        ));
        await tester.pumpAndSettle(); // MaterialApp animates a theme change
        expect(AppColors.of(inner), expected);
      }
    });
  });

  // `HomeScreen` used to be mounted bare here, back when it was a placeholder
  // with no Bloc of its own. Issue #101 makes it a real, Bloc-driven Screen —
  // the same shape every other Screen in this Module already has — so its
  // own welcome text and account-summary line are now covered where every
  // other Bloc-driven Screen's rendering is: pumped through the real seam in
  // `home_test.dart`, not mounted bare against a stand-alone `MaterialApp`
  // with no `HomeBloc` to answer its `BlocBuilder`.
}
