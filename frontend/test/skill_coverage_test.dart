/// A Site's skill coverage (issue #89, AC6) — administrator only, with the
/// wire faked, the one client seam (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/skill_coverage_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

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
  });

  testWidgets('a non-administrator reaches neither the destination nor the Screen', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openSkillCoverage(tester, wire);

    expect(find.byType(SkillCoverageScreen), findsNothing);
    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Skill coverage'), findsNothing);
  });
}
