/// Golden tests over the reworked Work orders Screen (issue #105, #99's own
/// reference Screen from #104) — the same seam every other test here uses,
/// `pumpApp` with the wire faked, asserting on pixels instead of text. No
/// state widget is mounted in isolation; every golden below is a Screen
/// pumped through the real app, exactly as `work_orders_test.dart`'s own
/// `wireWith`/`pumpApp` pairing already proves the Screen's behaviour with.
///
/// Scope is deliberately narrow, per #105's own ticket text: the populated
/// Screen at two widths either side of its own 800px-of-content breakpoint
/// (`WorkOrdersScreen.narrowBreakpoint`), plus one golden per shared state —
/// both empty variants, loading, a failed read, and a scope refusal — plus
/// one further golden the coordinator's own review of this ticket added: the
/// 700px-window "collision" width where this Screen's breakpoint and
/// `PlatformShell`'s rail breakpoint used to coincide (see
/// `WorkOrdersScreen.narrowBreakpoint`'s own doc comment). That is a
/// deliberate, re-opened extension of #105's stated golden list, recorded
/// here and in `GOLDENS.md` rather than added quietly. No other Screen is
/// goldened here.
///
/// The three populated-list goldens are also recorded in Vietnamese
/// (`work_orders_wide_vi.png`, `work_orders_narrow_vi.png`,
/// `work_orders_collision_700_vi.png`; t_0ac0eb9e batch 1 translated this
/// Screen without one). Vietnamese labels are wider, and a clipped or
/// ellipsised column raises no exception, so only pixels can catch it. The
/// English goldens keep their unsuffixed names and are never re-recorded by
/// this; the five state goldens stay English-only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/widgets/app_table.dart';

import 'harness.dart';

/// Mirrors `work_orders_test.dart`'s own `wireWith` (not imported — no test
/// file here imports another test file for its helpers other than
/// `harness.dart` itself, so this stays a small local duplicate rather than
/// reaching across files).
FakeWire wireWith({
  Map<String, List<Map<String, dynamic>>>? workOrders,
  int workOrdersStatus = 200,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {'1': []},
      workOrders: workOrders,
      workOrdersStatus: workOrdersStatus,
    );

/// A fixed window at a given width, with a fixed `devicePixelRatio` — the
/// same device `shell_test.dart`'s own `_useNarrowWindow`/`_useWideWindow`
/// use, needed so a golden renders a deterministic pixel size rather than
/// whatever `flutter test`'s own default test surface happens to be.
void _useWindow(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
}

void main() {
  // Real Roboto, not `flutter_test`'s placeholder-box font — every
  // `testWidgets` in this file is a golden, so this is loaded once for the
  // whole file rather than per test. See `loadAppFonts`'s own header in
  // `harness.dart` for why a golden needs this.
  setUpAll(loadAppFonts);

  // Every test starts from an empty store, so the Vietnamese tests below
  // cannot leave `vi` behind for the English-only state goldens after them.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // The three populated-list goldens, each in both languages. English keeps
  // its original PNG names (no suffix); Vietnamese adds `_vi`. English sets
  // empty preferences explicitly so a `vi` left in the mock store by an
  // earlier test cannot leak into it.
  for (final (code, suffix) in [('en', ''), ('vi', '_vi')]) {
    final lang = code == 'vi' ? ', in Vietnamese' : '';

    Future<void> pumpPopulated(WidgetTester tester, double width) async {
      SharedPreferences.setMockInitialValues(
        code == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
      );
      _useWindow(tester, width);
      final wire = wireWith(
        workOrders: {
          '1': [
            workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe'),
            workOrderJson('102', 'WO-102', 'Guard is loose',
                assetCode: 'CONV-2', assetName: 'Infeed conveyor'),
          ],
        },
      );
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/work-orders',
      );
    }

    // A Vietnamese golden that silently rendered English would be a second
    // English golden: prove the words before the pixels.
    void expectLanguage(WidgetTester tester, {required bool table}) {
      if (code != 'vi') return;
      expect(find.text('Lệnh công việc'), findsWidgets);
      expect(find.text('2 lệnh công việc'), findsOneWidget);
      expect(find.text('Work orders'), findsNothing);
      expect(find.text('2 Work orders'), findsNothing);
      if (table) {
        expect(find.text('Số WO'), findsWidgets);
        expect(find.text('Người phụ trách'), findsWidgets);
        expect(find.text('Summary'), findsNothing);
        // The translated words that were once ellipsised ("Đơn vị…", "Chưa phân
        // c…") are drawn whole: their columns are floored at the label's width.
        for (final finder in [
          find.byKey(AppTableHeader.labelKey('Đơn vị tổ chức')),
          find.byKey(AppTableHeader.labelKey('Tài sản')),
          find.byKey(AppTableHeader.labelKey('Người phụ trách')),
          find.text('Chưa phân công'),
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: finder, matching: find.byType(RichText)).first,
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: 'clipped: $finder');
        }
      }
    }

    testWidgets('the populated list, at or above the 800px-content breakpoint (a table)$lang',
        (tester) async {
      await pumpPopulated(tester, 1200);
      expectLanguage(tester, table: true);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/work_orders_wide$suffix.png'),
      );
    });

    testWidgets('the populated list, below the 800px-content breakpoint (cards)$lang',
        (tester) async {
      await pumpPopulated(tester, 600);
      expectLanguage(tester, table: false);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/work_orders_narrow$suffix.png'),
      );
    });

    // The 700px-window collision golden — a deliberate, re-opened extension
    // of #105's own golden list (see this file's own header, and `GOLDENS.md`
    // for the same note in the regenerate-and-scope document). At exactly
    // 700px of *window*, `PlatformShell`'s own rail breakpoint switches to its
    // 260px expanded sidebar, leaving 440px of actual content — below this
    // Screen's 800px-of-content breakpoint, so cards are correct here. Before
    // issue #105's fix, this Screen measured the window instead and concluded
    // it had 700px to work with, rendering a table that had nowhere near
    // enough room and corrupted its own header. This golden exists so that
    // regression is visible on sight, not only provable by reading a widget
    // test's assertions.
    testWidgets('at the 700px window where the two breakpoints used to collide, cards render '
        'cleanly, not a corrupted table$lang', (tester) async {
      await pumpPopulated(tester, 700);
      expectLanguage(tester, table: false);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/work_orders_collision_700$suffix.png'),
      );
    });
  }

  // Shared states (issue #103), each reached through this pumped Screen —
  // the fifth, narrower mount `theme_skeleton_test.dart`'s own header
  // reserves for exactly this file, `job_roles_test.dart` and
  // `skill_coverage_test.dart` to cover.

  testWidgets('the whole-Site empty state — nothing has ever been raised', (tester) async {
    _useWindow(tester, 1200);
    final wire = wireWith(workOrders: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.emptyKey), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/work_orders_empty_none_exist.png'),
    );
  });

  testWidgets("a filter that matches nothing — the caller's own filter, not an empty plant",
      (tester) async {
    _useWindow(tester, 1200);
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    wire.workOrdersByFilter['1|10'] = [];
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.filterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(find.byKey(WorkOrdersScreen.emptyFilteredKey), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/work_orders_empty_none_matched.png'),
    );
  });

  testWidgets('the loading placeholder, in its own shape', (tester) async {
    _useWindow(tester, 1200);
    final wire = wireWith(workOrders: {'1': []})..workOrdersGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
      settle: false,
    );

    // `SkeletonList` is deliberately unanimated (its own header in
    // `widgets/skeleton_list.dart`) precisely so a golden — or any
    // `pumpAndSettle` — never hangs on a running animation; a few fixed
    // frames are still pumped here rather than `pumpAndSettle`, since the
    // gated request itself never resolves and `pumpAndSettle` would wait on
    // it forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/work_orders_loading.png'),
    );

    // Completed so no gated request is left pending when the test ends.
    wire.workOrdersGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed read, explained', (tester) async {
    _useWindow(tester, 1200);
    final wire = wireWith(workOrdersStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.failedKey), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/work_orders_failed.png'),
    );
  });

  testWidgets('a scope refusal — never mistaken for an empty plant', (tester) async {
    _useWindow(tester, 1200);
    final wire = wireWith(workOrders: {'1': []}, workOrdersStatus: 403);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.scopeRefusedKey), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/work_orders_scope_refused.png'),
    );
  });
}
