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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/l10n/app_localizations.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_camera_scan.dart';
import 'package:lean_platform/widgets/app_form_submit.dart';
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
    this.codeOf,
    this.onSubmitted,
  });

  final Future<List<_Record>> Function(String term) fetchSuggestions;
  final _Record? initialValue;
  final String Function(_Record record)? codeOf;
  final ValueChanged<String>? onSubmitted;

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

  /// Every term `onSubmitted` was called with, in order — the Directory's own
  /// "commit to this term and filter" path.
  final List<String> submitted = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(),
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
          codeOf: widget.codeOf,
          onSubmitted: widget.onSubmitted == null
              ? null
              : (term) {
                  submitted.add(term);
                  widget.onSubmitted!(term);
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

  // Issue #143 / ADR-0026: the widget bounds the list, so it is the one that
  // says when it has, rather than leaving the person unable to tell a missing
  // match from one past the tenth row.
  testWidgets('a term whose results were cut renders the bounded-list footer',
      (WidgetTester tester) async {
    Future<List<_Record>> fetch(String term) async {
      return List<_Record>.generate(15, (i) => (id: '${i + 1}', label: 'Record ${i + 1}'));
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'record');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(AppSearchField.truncatedKey('employee')), findsOneWidget);
    expect(
      find.text('There are more matches than are shown — keep typing to narrow the list.'),
      findsOneWidget,
    );
  });

  testWidgets('a term whose results all fit renders no bounded-list footer',
      (WidgetTester tester) async {
    Future<List<_Record>> fetch(String term) async {
      return const [(id: 'e1', label: 'Ada Lovelace')];
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ada');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(AppSearchField.truncatedKey('employee')), findsNothing);
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

  // Issue #144: a pick collapses the widget's own list, the same way the
  // submit path already does. Before this, the two call sites that wanted it
  // closed forced a remount by folding a generation counter into this
  // widget's outer `Key`.
  testWidgets(
      'tapping a suggestion collapses the list and cancels a pending debounce, so no later fetch reopens it',
      (WidgetTester tester) async {
    final calls = <String>[];
    Future<List<_Record>> fetch(String term) async {
      calls.add(term);
      return const [(id: 'e1', label: 'Ada Lovelace')];
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ada');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'e1')), findsOneWidget);
    expect(calls, ['ada']);

    // Start a new search but tap the still-visible suggestion before the
    // debounce fires — the pick must cancel that pending fetch, not merely
    // clear the list it would have landed into.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'adalovelace');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(AppSearchField.suggestionKey('employee', 'e1')));
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'e1')), findsNothing);

    // Waiting out the debounce issues no fetch for the term typed after the
    // pick.
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, ['ada']);
  });

  testWidgets('a fetch already in flight when a suggestion is picked cannot reopen the list',
      (WidgetTester tester) async {
    final completers = <String, Completer<List<_Record>>>{};
    Future<List<_Record>> fetch(String term) {
      final completer = Completer<List<_Record>>();
      completers[term] = completer;
      return completer.future;
    }

    await tester.pumpWidget(_Harness(fetchSuggestions: fetch));

    // A fetch for "aa" is issued and left in flight.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'aa');
    await tester.pump(const Duration(milliseconds: 350));
    expect(completers.containsKey('aa'), isTrue);

    // A newer fetch for "bb" resolves and shows its suggestion while "aa" is
    // still pending.
    await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'bb');
    await tester.pump(const Duration(milliseconds: 350));
    completers['bb']!.complete(const [(id: 'b1', label: 'Bravo')]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(AppSearchField.suggestionKey('employee', 'b1')), findsOneWidget);

    // Pick "b1" while "aa" is still in flight.
    await tester.tap(find.byKey(AppSearchField.suggestionKey('employee', 'b1')));
    await tester.pump();
    expect(find.byKey(AppSearchField.suggestionKey('employee', 'b1')), findsNothing);
    expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsNothing);

    // The in-flight fetch resolves after the pick: it must not reopen the
    // list the pick just closed.
    completers['aa']!.complete(const [(id: 'a1', label: 'Alpha')]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(AppSearchField.suggestionKey('employee', 'a1')), findsNothing);
    expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsNothing);
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

  group('a picker takes a scanner', () {
    /// The two records these tests pick between. `id` is what a reader would
    /// send — the same role an Asset's `code` plays at a real call site, which
    /// is why `codeOf` maps it.
    const records = [
      (id: 'ASSET-1', label: 'Pump house'),
      (id: 'ASSET-2', label: 'Compressor'),
    ];

    /// The caller's own dumb fetch: a case-insensitive substring match over the
    /// code and the label, exactly as the real pickers' in-memory filters are.
    Future<List<_Record>> fetch(String term) async {
      final lower = term.toLowerCase();
      return [
        for (final record in records)
          if (record.id.toLowerCase().contains(lower) || record.label.toLowerCase().contains(lower)) record,
      ];
    }

    testWidgets('a scan picks the record whose code it is, with no tap', (WidgetTester tester) async {
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harnessKey, fetchSuggestions: fetch, codeOf: (record) => record.id),
      );

      // A reader types the whole code as a burst and ends with Enter — a key
      // event, not the soft keyboard's action key.
      await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ASSET-2');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected.map((record) => record.id), ['ASSET-2']);
      // The search is over: the box is not left showing what has just been
      // chosen.
      expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsNothing);
    });

    testWidgets('the scanned code is matched case-insensitively, with the reader’s noise stripped',
        (WidgetTester tester) async {
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harnessKey, fetchSuggestions: fetch, codeOf: (record) => record.id),
      );

      // A reader prefixes a BOM in some configurations and appends a space in
      // others — neither is part of the code (`AppScanField.normalize`).
      await tester.enterText(
        find.byKey(AppSearchField.fieldKey('employee')),
        '\uFEFFasset-2 ',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected.map((record) => record.id), ['ASSET-2']);
    });

    testWidgets('a scan that names no record picks nothing, and leaves the matches on screen',
        (WidgetTester tester) async {
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harnessKey, fetchSuggestions: fetch, codeOf: (record) => record.id),
      );

      // Neither code *is* "ASSET": both merely contain it. A near miss must
      // cost a tap, never a wrong pick.
      await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'ASSET');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected, isEmpty);
      expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsOneWidget);
      expect(find.byKey(AppSearchField.suggestionKey('employee', 'ASSET-1')), findsOneWidget);
      expect(find.byKey(AppSearchField.suggestionKey('employee', 'ASSET-2')), findsOneWidget);
    });

    testWidgets('two records carrying one code pick nothing — ambiguity is shown, never guessed',
        (WidgetTester tester) async {
      const duplicated = [
        (id: 'DUP-1', label: 'First'),
        (id: 'DUP-1', label: 'Second'),
      ];
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harnessKey,
          fetchSuggestions: (term) async => [
            for (final record in duplicated)
              if (record.id.toLowerCase().contains(term.toLowerCase())) record,
          ],
          codeOf: (record) => record.id,
        ),
      );

      await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'dup-1');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected, isEmpty);
      expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsOneWidget);
    });

    testWidgets('a one-character scan issues no fetch at all (ADR-0023 point 5)',
        (WidgetTester tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _Harness(
          fetchSuggestions: (term) async {
            calls.add(term);
            return records;
          },
          codeOf: (record) => record.id,
        ),
      );

      await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });

    testWidgets('the reader’s Enter stops at the picker and never submits the form around it',
        (WidgetTester tester) async {
      var submits = 0;
      final picked = <_Record>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          // The field reads its own "No matches"/"Search failed" words from the
          // catalogue, so the app around it has to carry the delegates —
          // `nullable-getter: false` makes a missing localisation a tree bug.
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AppFormSubmit(
              onSubmit: () => submits++,
              child: AppSearchField<_Record>(
                name: 'asset',
                label: 'Asset',
                value: null,
                onChanged: (_) {},
                onSelected: picked.add,
                codeOf: (record) => record.id,
                fetchSuggestions: fetch,
                suggestionBuilder: (context, record) => Text(record.label),
                idOf: (record) => record.id,
                displayStringFor: (record) => '${record.label} (${record.id})',
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(AppSearchField.fieldKey('asset')), 'ASSET-1');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked.map((record) => record.id), ['ASSET-1']);
      // Mid-form: the value the key just named is set, but the form it sits in
      // has not been sent.
      expect(submits, 0);
    });

    testWidgets('with a submit caller the same Enter is that caller’s term, and picks nothing',
        (WidgetTester tester) async {
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harnessKey,
          fetchSuggestions: fetch,
          codeOf: (record) => record.id,
          onSubmitted: (_) {},
        ),
      );

      await tester.enterText(find.byKey(AppSearchField.fieldKey('employee')), 'asset-2');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // The Directory narrows its listing; it does not pick the Employee.
      expect(harnessKey.currentState!.submitted, ['asset-2']);
      expect(harnessKey.currentState!.selected, isEmpty);
    });
  });

  group('the camera beside the search', () {
    tearDown(() => AppCameraScan.reader = AppCameraScan.readWithCamera);

    testWidgets('a code the camera read picks the record it names, with no tap',
        (WidgetTester tester) async {
      AppCameraScan.reader = (_) async => 'ASSET-2';
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harnessKey,
          fetchSuggestions: (term) async => const [
            (id: 'ASSET-1', label: 'Pump house'),
            (id: 'ASSET-2', label: 'Compressor'),
          ],
          codeOf: (record) => record.id,
        ),
      );

      await tester.tap(find.byKey(AppCameraScanButton.keyOf('employee')));
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected.map((record) => record.id), ['ASSET-2']);
      expect(find.byKey(AppSearchField.suggestionListKey('employee')), findsNothing);
    });

    testWidgets('a camera the person closed picks nothing and leaves the field alone',
        (WidgetTester tester) async {
      AppCameraScan.reader = (_) async => null;
      final harnessKey = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harnessKey,
          fetchSuggestions: (term) async => const [(id: 'ASSET-2', label: 'Compressor')],
          codeOf: (record) => record.id,
        ),
      );

      await tester.tap(find.byKey(AppCameraScanButton.keyOf('employee')));
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.selected, isEmpty);
      expect(find.byKey(AppSearchField.fieldKey('employee')), findsOneWidget);
    });
  });
}
