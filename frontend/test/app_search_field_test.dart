/// `AppSearchField` (issue #125, ADR-0023): the shared as-you-type
/// suggestion box. Unlike every Bloc-driven Screen test in this suite, this
/// widget makes no request of its own through the app's real HTTP wiring —
/// it is handed a caller-supplied `fetchSuggestions` callback — so this file
/// builds its own small fake fetch functions rather than reaching for
/// `harness.dart`'s `FakeWire`, which stubs real HTTP endpoints this widget
/// never calls. `Completer`s stand in wherever a test needs to control
/// exactly when a fetch resolves (the debounce and out-of-order tests).
///
/// [_Harness] plays the caller's own role, the same shape
/// `app_date_field_test.dart`'s own `_Harness` uses for `AppDateField`: it
/// owns the controlled `value` and feeds every `onChanged` back in, and
/// separately records every `onSelected` pick, since the two are distinct
/// callbacks on this widget (see `app_search_field.dart`'s own doc comment
/// on why).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/widgets/app_search_field.dart';
import 'package:lean_platform/widgets/empty_state.dart';
import 'package:lean_platform/widgets/failure_state.dart';

/// The suggestion shape used across this file — a plain Dart record, so
/// equality is structural for free and `onSelected`/`value` assertions can
/// compare records directly.
typedef _Record = ({String id, String label});

/// Wraps [AppSearchField] the way a real call site will (#128/#129/#130):
/// owns the current [value] and feeds every `onChanged` back in, and reacts
/// to `onSelected` however that call site chooses to (here: recording the
/// pick and, by default, also adopting it as the new controlled value —
/// exactly the choice a caller like the Employee link picker, #129, would
/// make).
class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.fetchSuggestions,
    this.initialValue,
  });

  final Future<List<_Record>> Function(String term) fetchSuggestions;
  final _Record? initialValue;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late _Record? value = widget.initialValue;

  /// Every value this harness has been told about via `onChanged`, in
  /// order — so a test can assert what the widget actually reported.
  final List<_Record?> reported = [];

  /// Every record `onSelected` was called with, in order.
  final List<_Record> selected = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AppSearchField<_Record>(
          name: 'employee',
          label: 'Search employees',
          value: value,
          onChanged: (next) {
            reported.add(next);
            setState(() => value = next);
          },
          onSelected: (record) {
            selected.add(record);
            setState(() => value = record);
          },
          fetchSuggestions: widget.fetchSuggestions,
          suggestionBuilder: (context, record) => Text(record.label),
          idOf: (record) => record.id,
          displayStringFor: (record) => record.label,
        ),
      ),
    );
  }
}

void main() {
  testWidgets('typing 1 character fires no fetch; typing 2 characters does',
      (WidgetTester tester) async {
    final calls = <String>[];
    Future<List<_Record>> fetch(String term) async {
      calls.add(term);
      return const [];
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'a');
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, isEmpty);

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ab');
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, ['ab']);
  });

  testWidgets(
      'rapid typing within the debounce window results in exactly one fetch, carrying the final term',
      (WidgetTester tester) async {
    final calls = <String>[];
    Future<List<_Record>> fetch(String term) async {
      calls.add(term);
      return const [];
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ab');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'abc');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'abcd');
    await tester.pump(const Duration(milliseconds: 350));

    expect(calls, ['abcd']);
  });

  testWidgets(
      'an out-of-order response does not overwrite the newer suggestions already on screen',
      (WidgetTester tester) async {
    final completers = <String, Completer<List<_Record>>>{};
    Future<List<_Record>> fetch(String term) {
      final completer = Completer<List<_Record>>();
      completers[term] = completer;
      return completer.future;
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    // Issue the first (stale) request, for "aa".
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'aa');
    await tester.pump(const Duration(milliseconds: 350));
    expect(completers.containsKey('aa'), isTrue);

    // Issue the second (fresh) request, for "bb", while "aa" is still
    // pending — a later-issued request outstanding at the same time as an
    // earlier one that has not yet resolved.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'bb');
    await tester.pump(const Duration(milliseconds: 350));
    expect(completers.containsKey('bb'), isTrue);

    // The newer request resolves first.
    completers['bb']!.complete(const [(id: 'b1', label: 'Bravo')]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'b1')), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    // The older, stale request resolves after — it must be discarded rather
    // than overwriting what the newer request already produced.
    completers['aa']!.complete(const [(id: 'a1', label: 'Alpha')]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'b1')), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.byKey(AppSearchField.suggestionKey('employee', 'a1')), findsNothing);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('at most 10 suggestion rows render even when the fetch returns more',
      (WidgetTester tester) async {
    Future<List<_Record>> fetch(String term) async {
      return List<_Record>.generate(15, (i) => (id: '${i + 1}', label: 'Record ${i + 1}'));
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'record');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    for (var i = 1; i <= 10; i++) {
      expect(find.byKey(AppSearchField.suggestionKey('employee', '$i')), findsOneWidget);
    }
    for (var i = 11; i <= 15; i++) {
      expect(find.byKey(AppSearchField.suggestionKey('employee', '$i')), findsNothing);
    }
  });

  testWidgets('tapping a suggestion invokes onSelected with that exact record, and does nothing navigational',
      (WidgetTester tester) async {
    const record = (id: 'e1', label: 'Ada Lovelace');
    Future<List<_Record>> fetch(String term) async => const [record];

    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: harnessKey, fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ada');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'e1')), findsOneWidget);

    await tester.tap(find.byKey(AppSearchField.suggestionKey('employee', 'e1')));
    await tester.pump();

    expect(harnessKey.currentState!.selected, [record]);
    // Nothing navigational happened — the same field is still on screen,
    // not replaced by a pushed route.
    expect(find.byKey(AppSearchField.fieldKey('employee')), findsOneWidget);
  });

  testWidgets('a zero-result term (2+ characters) renders the shared PlatformEmptyState',
      (WidgetTester tester) async {
    Future<List<_Record>> fetch(String term) async => const [];

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(PlatformEmptyState), findsOneWidget);
  });

  testWidgets('a failed fetch renders PlatformFailureState, and tapping retry re-issues the fetch and can recover',
      (WidgetTester tester) async {
    var attempt = 0;
    Future<List<_Record>> fetch(String term) async {
      attempt++;
      if (attempt == 1) {
        throw Exception('boom');
      }
      return const [(id: 'e1', label: 'Ada Lovelace')];
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ada');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(PlatformFailureState), findsOneWidget);

    await tester.tap(find.byKey(AppSearchField.retryKey('employee')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PlatformFailureState), findsNothing);
    expect(find.byType(PlatformEmptyState), findsNothing);
    expect(find.byKey(AppSearchField.suggestionKey('employee', 'e1')), findsOneWidget);
  });

  testWidgets(
      'while PlatformFailureState is showing the reported value is null, and further typing does not make it usable on its own',
      (WidgetTester tester) async {
    const initial = (id: 'e0', label: 'Grace Hopper');
    Future<List<_Record>> fetch(String term) async {
      throw Exception('boom');
    }

    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: harnessKey, fetchSuggestions: fetch, initialValue: initial),
    );

    expect(harnessKey.currentState!.value, initial);

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ada');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(PlatformFailureState), findsOneWidget);
    expect(harnessKey.currentState!.reported.last, isNull);
    expect(harnessKey.currentState!.value, isNull);

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'adam');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(PlatformFailureState), findsOneWidget);
    expect(harnessKey.currentState!.value, isNull);
  });

  testWidgets('an initial value is displayed on first build, before any fetch happens',
      (WidgetTester tester) async {
    var calls = 0;
    Future<List<_Record>> fetch(String term) async {
      calls++;
      return const [];
    }

    const initial = (id: 'e1', label: 'Ada Lovelace');
    await tester.pumpWidget(_Harness(fetchSuggestions: fetch, initialValue: initial));

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(calls, 0);
  });

  // Defect fix: typed text is never itself a value, but a confirmed [value]
  // must not go on being reported once the text on screen no longer matches
  // it — see `app_search_field.dart`'s own "Typing over a confirmed
  // selection retires it" doc comment. Before this fix, `SiteFormDialog`
  // (issue #127) would submit a picked timezone the field had stopped
  // displaying, which is exactly the valid-but-wrong hazard ADR-0017 warns
  // about for a Site's production-day boundary.
  testWidgets(
      'typing over a confirmed selection clears it exactly once, leaving the typed text on screen',
      (WidgetTester tester) async {
    const initial = (id: 'e0', label: 'Grace Hopper');
    Future<List<_Record>> fetch(String term) async => const [];

    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: harnessKey, fetchSuggestions: fetch, initialValue: initial),
    );

    expect(harnessKey.currentState!.value, initial);

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'Gr');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(harnessKey.currentState!.reported, [null]);
    expect(harnessKey.currentState!.value, isNull);
    // The typed text stays on screen — `didUpdateWidget` skips re-seeding for
    // a self-reported change, so this widget's own fix does not wipe out
    // whatever the person is mid-typing.
    expect(find.text('Gr'), findsOneWidget);

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'Gra');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // Still exactly one report: once `value` is null there is nothing left
    // to diverge from, so every later keystroke is a no-op on this front.
    expect(harnessKey.currentState!.reported, [null]);
  });

  testWidgets('typing that still matches the confirmed selection leaves it in place',
      (WidgetTester tester) async {
    const initial = (id: 'e0', label: 'Grace Hopper');
    Future<List<_Record>> fetch(String term) async => const [];

    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: harnessKey, fetchSuggestions: fetch, initialValue: initial),
    );

    // Typing the exact same text back — one keystroke at a time reaching the
    // same string a real typist would land on — is not itself a pick, but it
    // is also not a divergence: nothing is reported and the value survives.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'Grace Hopper');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(harnessKey.currentState!.reported, isEmpty);
    expect(harnessKey.currentState!.value, initial);

    // A trailing space is not a different record either.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'Grace Hopper ');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(harnessKey.currentState!.reported, isEmpty);
    expect(harnessKey.currentState!.value, initial);
  });
}
