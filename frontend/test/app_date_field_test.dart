/// `AppDateField` (issue #124, ADR-0023): the shared read-only date control.
/// No `FakeWire` is needed here — unlike every Bloc-driven Screen test in
/// this suite, `AppDateField` makes no request of its own; it is a pure
/// controlled widget (`value`/`onChanged`), pumped directly the same way
/// `theme_skeleton_test.dart` pumps `SkeletonList`/`SkeletonDetail` bare.
///
/// [_Harness] below plays the caller's own role for the tests that need a
/// value to actually change across a pick or a clear: it holds the state and
/// rebuilds `AppDateField` with the new `value` on every `onChanged`, the
/// same controlled-component shape a real call site (#126) will use.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/widgets/app_date_field.dart';

/// Wraps [AppDateField] the way a real call site will (#126): owns the
/// current value and feeds every `onChanged` back in, so a test can drive a
/// pick or a clear and observe the value the widget reports rather than
/// reaching into its private state.
class _Harness extends StatefulWidget {
  const _Harness({super.key, this.initialValue, this.optional = false});

  final String? initialValue;
  final bool optional;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late String? value = widget.initialValue;

  /// Every value this harness has been told about, in order — so a test can
  /// assert what `AppDateField` actually reported, not merely what ended up
  /// rendered.
  final List<String?> reported = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AppDateField(
          name: 'effective-from',
          label: 'Effective date',
          value: value,
          optional: widget.optional,
          onChanged: (next) {
            reported.add(next);
            setState(() => value = next);
          },
        ),
      ),
    );
  }
}

void main() {
  testWidgets('the field is read-only: entering text via the keyboard does not change its value',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateField(
            name: 'effective-from',
            label: 'Effective date',
            value: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(AppDateField.fieldKey('effective-from')), '2099-12-31');
    await tester.pump();

    expect(find.text('2099-12-31'), findsNothing);
    final field = tester.widget<TextField>(find.byKey(AppDateField.fieldKey('effective-from')));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('tapping the field opens a date picker', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateField(
            name: 'effective-from',
            label: 'Effective date',
            value: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(DatePickerDialog), findsNothing);

    await tester.tap(find.byKey(AppDateField.fieldKey('effective-from')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets(
      'picking a date through the picker fills the field as YYYY-MM-DD and reports that same string',
      (WidgetTester tester) async {
    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: harnessKey, initialValue: '2024-03-01'));

    await tester.tap(find.byKey(AppDateField.fieldKey('effective-from')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // The picker opens on March 2024 (the harness's own initial value), so
    // day 15 is unambiguous — every month has one.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2024-03-15'), findsOneWidget);
    expect(harnessKey.currentState!.reported, ['2024-03-15']);
    expect(harnessKey.currentState!.value, '2024-03-15');
  });

  testWidgets(
      'in optional mode the clear button appears only once a value is set, '
      'and tapping it returns the reported value to empty', (WidgetTester tester) async {
    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: harnessKey, optional: true, initialValue: null));

    expect(find.byKey(AppDateField.clearKey('effective-from')), findsNothing);

    await tester.tap(find.byKey(AppDateField.fieldKey('effective-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(harnessKey.currentState!.value, isNotNull);
    expect(find.byKey(AppDateField.clearKey('effective-from')), findsOneWidget);

    await tester.tap(find.byKey(AppDateField.clearKey('effective-from')));
    await tester.pump();

    expect(harnessKey.currentState!.reported.last, isNull);
    expect(harnessKey.currentState!.value, isNull);
    expect(find.byKey(AppDateField.clearKey('effective-from')), findsNothing);
    final field = tester.widget<TextField>(find.byKey(AppDateField.fieldKey('effective-from')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('required mode shows no clear button, even once a value is set',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateField(
            name: 'effective-from',
            label: 'Effective date',
            value: '2024-01-01',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(AppDateField.clearKey('effective-from')), findsNothing);
  });

  testWidgets('a pre-set initial value is displayed on first build', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateField(
            name: 'effective-from',
            label: 'Effective date',
            value: '2024-05-06',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('2024-05-06'), findsOneWidget);
  });
}
