import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';

/// One role of the type scale (issue #367): what Material 3's 2021 default gave
/// it, the size [buildAppTheme] pins it at, and the line height that size
/// resolves to under Material's own ratio.
typedef _Role = ({
  String name,
  TextStyle? Function(TextTheme) read,
  double material,
  double size,
  double lineHeight,
});

final List<_Role> _roles = [
  (name: 'headlineLarge', read: (t) => t.headlineLarge, material: 32, size: 26, lineHeight: 32.5),
  (name: 'headlineMedium', read: (t) => t.headlineMedium, material: 28, size: 22, lineHeight: 28.4),
  (name: 'headlineSmall', read: (t) => t.headlineSmall, material: 24, size: 18, lineHeight: 23.9),
  (name: 'titleLarge', read: (t) => t.titleLarge, material: 22, size: 18, lineHeight: 22.9),
  (name: 'titleMedium', read: (t) => t.titleMedium, material: 16, size: 16, lineHeight: 24.0),
  (name: 'titleSmall', read: (t) => t.titleSmall, material: 14, size: 14, lineHeight: 20.0),
  (name: 'bodyLarge', read: (t) => t.bodyLarge, material: 16, size: 16, lineHeight: 24.0),
  (name: 'bodyMedium', read: (t) => t.bodyMedium, material: 14, size: 14, lineHeight: 20.0),
  (name: 'bodySmall', read: (t) => t.bodySmall, material: 12, size: 12, lineHeight: 16.0),
  (name: 'labelLarge', read: (t) => t.labelLarge, material: 14, size: 14, lineHeight: 20.0),
  (name: 'labelMedium', read: (t) => t.labelMedium, material: 12, size: 12, lineHeight: 16.0),
  (name: 'labelSmall', read: (t) => t.labelSmall, material: 11, size: 12, lineHeight: 17.4),
];

/// The text theme a Screen actually reads. Material's line heights are not on
/// the object [buildAppTheme] returns: `Theme.of` merges them in, from the
/// locale's own text geometry, so a resolved line height has to be read there.
Future<TextTheme> _resolved(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  return Theme.of(tester.element(find.byType(Scaffold))).textTheme;
}

void main() {
  testWidgets('every role resolves to its pinned size and line height',
      (WidgetTester tester) async {
    final theme = await _resolved(tester);

    for (final role in _roles) {
      final style = role.read(theme)!;
      expect(style.fontSize, role.size, reason: '${role.name} font size');
      expect(
        (style.height! * style.fontSize!).toStringAsFixed(1),
        role.lineHeight.toStringAsFixed(1),
        reason: '${role.name} line height',
      );
    }
  });

  testWidgets('no moved role still resolves to the Material default it used to be',
      (WidgetTester tester) async {
    final theme = await _resolved(tester);

    final moved = _roles.where((role) => role.size != role.material).toList();
    expect(
      moved.map((role) => role.name),
      ['headlineLarge', 'headlineMedium', 'headlineSmall', 'titleLarge', 'labelSmall'],
    );
    for (final role in moved) {
      expect(role.read(theme)!.fontSize, isNot(role.material), reason: role.name);
    }
  });

  test('the theme itself pins each role\'s size, and only its size', () {
    // Before `Theme.of` merges Material's geometry in, a role carries what
    // `buildAppTheme` wrote down and nothing else: a role left to Material's
    // default has no size here, and one restating Material's line height has
    // a height.
    final theme = buildAppTheme().textTheme;

    for (final role in _roles) {
      final style = role.read(theme)!;
      expect(style.fontSize, role.size, reason: '${role.name} is not pinned');
      expect(style.height, isNull, reason: '${role.name} restates its line height');
      expect(style.letterSpacing, isNull, reason: '${role.name} restates its letter spacing');
    }
  });
}
