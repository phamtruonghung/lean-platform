/// A Site's skill coverage (issue #89, AC6) — administrator only, with the
/// wire faked, the one client seam (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/skill_coverage_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'harness.dart';

Future<void> openSkillCoverage(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.skillCoverage,
    );

void main() {
  testWidgets('an administrator reaches the skill coverage Screen, and sees the destination',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      skillCoverage: {
        '1': [skillCoverageEntryJson('10', 'Line 1', '30', 'WELD', 'Welding', shortfall: 2)],
      },
    );
    await openSkillCoverage(tester, wire);

    expect(find.byType(SkillCoverageScreen), findsOneWidget);
    expect(find.text('Skill coverage'), findsWidgets);
    expect(find.text('Line 1 · Welding'), findsOneWidget);
    expect(wire.skillCoverageRequests, ['1']);
  });

  testWidgets('a Site with every requirement met shows the empty state, not an empty list',
      (tester) async {
    final wire = FakeWire(sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openSkillCoverage(tester, wire);

    expect(find.byKey(SkillCoverageScreen.emptyKey), findsOneWidget);
    expect(find.text('Every requirement is met'), findsOneWidget);
  });

  // Issue #103: the shared empty/loading/error states — this Screen is the
  // second migration proving them, chosen for the same reason `JobRolesScreen`
  // was: it fell back to a bare `CircularProgressIndicator` and a plain
  // `Text` for its own empty case before #103.

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      skillCoverageStatus: 503,
    );
    await openSkillCoverage(tester, wire);

    expect(find.byKey(SkillCoverageScreen.failedKey), findsOneWidget);
    expect(find.text('Skill coverage is unavailable.'), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.emptyKey), findsNothing);

    wire.skillCoverageStatus = 200;
    wire.skillCoverage = {
      '1': [skillCoverageEntryJson('10', 'Line 1', '30', 'WELD', 'Welding', shortfall: 2)],
    };
    await tapIn(tester, find.byKey(SkillCoverageScreen.retryKey));

    expect(find.byKey(SkillCoverageScreen.failedKey), findsNothing);
    expect(find.text('Line 1 · Welding'), findsOneWidget);
  });

  testWidgets('a non-administrator reaches neither the destination nor the Screen', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openSkillCoverage(tester, wire);

    expect(find.byType(SkillCoverageScreen), findsNothing);
    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Skill coverage'), findsNothing);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets("a Site's skill coverage is narrowed by a typed term, and typing costs no request",
      (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      skillCoverage: {
        '1': [
          skillCoverageEntryJson('10', 'Line 1', '30', 'WELD', 'Welding', shortfall: 2),
          skillCoverageEntryJson('11', 'Line 2', '31', 'FORK', 'Forklift operation',
              shortfall: 1),
        ],
      },
    );
    await openSkillCoverage(tester, wire);

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(SkillCoverageScreen.rowKey('11', '31')), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.rowKey('10', '30')), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(SkillCoverageScreen.filterFieldKey), 'forklift');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(SkillCoverageScreen.rowKey('11', '31')), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.rowKey('10', '30')), findsNothing);
    expect(find.byKey(SkillCoverageScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(SkillCoverageScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(SkillCoverageScreen.rowKey('11', '31')), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.rowKey('10', '30')), findsOneWidget);
    expect(find.byKey(SkillCoverageScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });
}
