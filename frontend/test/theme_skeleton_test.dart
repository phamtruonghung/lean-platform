import 'dart:io';

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

  test(
      'no raw Color literal or Colors.* constant appears outside theme.dart '
      '(issue #102)', () {
    // A Screen names a colour through AppColors / AppComponentColors, or
    // reaches Theme.of(context).colorScheme directly — never a Color(0x...)
    // literal or a Colors.* constant. This walks every Dart source file
    // under lib/, excluding theme.dart itself (the one file allowed to hold
    // the primitives everything else is named from), and fails the moment
    // one of those two patterns shows up anywhere else — a static check
    // that survives the next agent rather than relying on review to catch
    // a colour written by hand.
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'expected to run from frontend/ with a lib/ directory next to it');

    final colorLiteral = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');
    final colorsConstant = RegExp(r'\bColors\.');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.uri.pathSegments.last == 'theme.dart') continue;

      final source = entity.readAsStringSync();
      if (colorLiteral.hasMatch(source) || colorsConstant.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'raw colour literal(s) found outside theme.dart: ${offenders.join(', ')} — '
            'route colour through theme.dart\'s AppColors / AppComponentColors '
            'tokens instead (issue #102).');
  });
}
