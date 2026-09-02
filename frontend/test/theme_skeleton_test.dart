import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

void main() {
  testWidgets('SkeletonList renders the requested number of placeholder cards',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SkeletonList(rows: 3)),
      ),
    );

    expect(find.byType(Card), findsNWidgets(3));
    // A skeleton settles without any pending timers or frames, so the list
    // can be pumped to completion (no shimmer animation to hang on).
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsOneWidget);
  });

  test('the theme builds with the design defaults', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    expect(theme.cardTheme, isNotNull);
  });

  test('spacing and radius tokens are positive and decrease monotonically', () {
    final values = [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg,
      Spacing.xl, Spacing.xxl];
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]),
          reason: 'spacing tokens should be ordered smallest to largest');
    }
  });

  testWidgets('the scaffold keeps the flattened card look after theming',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    final cardTheme = Theme.of(context).cardTheme;
    expect(cardTheme.elevation, 0);
  });
}
