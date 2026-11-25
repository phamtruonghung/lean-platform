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
/// **Vietnamese (t_e5226530).** The three populated-list goldens are also
/// recorded in Vietnamese (`*_vi.png`). Vietnamese labels are wider, and this
/// Screen's table measures its columns from their labels, so a width that
/// holds in English can break in Vietnamese; only pixels show that. The
/// English PNGs are unchanged. The other state goldens stay English only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/locale_cubit.dart';

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

/// Seeds the mocked `SharedPreferences` the app reads its language from. The
/// mock is static, so every test seeds it — an English one with the empty map —
/// or a Vietnamese seed from an earlier test would leak into the next.
void _seedLanguage(String code) => SharedPreferences.setMockInitialValues(
      code == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
    );

/// Asserts the render really is Vietnamese before a `_vi` golden is compared,
/// so a golden recorded in English under a `_vi` name cannot pass.
///
/// `navWorkOrders` (app_vi.arb:101) is the sidebar entry and the Screen's
/// title; `workOrdersDescription` (app_vi.arb:301) is the Screen header's
/// description, drawn at every width; 'Work orders' is `navWorkOrders`'s
/// English value (app_en.arb:101).
void _expectVietnamese() {
  expect(find.text('Lệnh công việc'), findsWidgets);
  expect(
    find.text('Công việc được tạo tại Nhà máy này, gắn với Thiết bị nào và ai đang phụ trách.'),
    findsOneWidget,
  );
  expect(find.text('Work orders'), findsNothing);
}

void main() {
  // Real Roboto, not `flutter_test`'s placeholder-box font — every
  // `testWidgets` in this file is a golden, so this is loaded once for the
  // whole file rather than per test. See `loadAppFonts`'s own header in
  // `harness.dart` for why a golden needs this.
  setUpAll(loadAppFonts);

  for (final (code, suffix) in [('en', ''), ('vi', '_vi')]) {
    /// Pumps the populated list at [width] in this iteration's language.
    Future<void> pumpPopulated(WidgetTester tester, double width) async {
      _seedLanguage(code);
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
      if (code == 'vi') _expectVietnamese();
    }

    testWidgets('the populated list, $code, at or above the 800px-content breakpoint (a table)',
        (tester) async {
      await pumpPopulated(tester, 1200);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/work_orders_wide$suffix.png'),
      );
    });

    testWidgets('the populated list, $code, below the 800px-content breakpoint (cards)',
        (tester) async {
      await pumpPopulated(tester, 600);

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
    testWidgets('at the 700px window where the two breakpoints used to collide, $code, cards '
        'render cleanly, not a corrupted table', (tester) async {
      await pumpPopulated(tester, 700);

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
    _seedLanguage('en');
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
    _seedLanguage('en');
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
    _seedLanguage('en');
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
    _seedLanguage('en');
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
    _seedLanguage('en');
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
