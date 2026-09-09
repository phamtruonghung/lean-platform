/// The job role catalogue (issue #88): every job role the plant recognises,
/// and an administrator's own write surface over it — with the wire faked,
/// the one client seam (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/job_role_form_dialog.dart';
import 'package:lean_platform/people/job_roles_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> openJobRoles(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-roles',
    );

void main() {
  testWidgets('the job role catalogue renders, deactivated rows included, for an administrator',
      (tester) async {
    final wire = FakeWire(
      jobRoles: [
        jobRoleJson('20', 'WELD', 'Welder'),
        jobRoleJson('21', 'FIT', 'Fitter', isActive: false),
      ],
    );
    await openJobRoles(tester, wire);

    expect(find.byType(JobRolesScreen), findsOneWidget);
    expect(find.text('Welder · WELD'), findsOneWidget);
    expect(find.text('Fitter · FIT'), findsOneWidget);
    expect(find.byKey(JobRolesScreen.inactiveChipKey('21')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.addKey), findsOneWidget);
  });

  testWidgets('an administrator can add a job role, and it appears in the list', (tester) async {
    final wire = FakeWire(jobRoles: [jobRoleJson('20', 'WELD', 'Welder')]);
    await openJobRoles(tester, wire);

    await tapIn(tester, find.byKey(JobRolesScreen.addKey));
    await tester.enterText(find.byKey(JobRoleFormDialog.codeKey), 'MILL');
    await tester.enterText(find.byKey(JobRoleFormDialog.nameKey), 'Miller');
    await tapIn(tester, find.byKey(JobRoleFormDialog.submitKey));

    expect(wire.jobRolePosts.single, {'code': 'MILL', 'name': 'Miller'});
    expect(find.byType(JobRoleFormDialog), findsNothing);
    expect(find.text('Miller · MILL'), findsOneWidget);
  });

  testWidgets('an administrator can correct a job role, sending only the changed field',
      (tester) async {
    final wire = FakeWire(jobRoles: [jobRoleJson('20', 'WELD', 'Welder')]);
    await openJobRoles(tester, wire);

    await tapIn(tester, find.byKey(JobRolesScreen.correctKey('20')));
    expect(find.byType(JobRoleFormDialog), findsOneWidget);
    // Pre-filled from the row already on screen, not left blank.
    expect(find.text('Welder'), findsOneWidget);

    await tester.enterText(find.byKey(JobRoleFormDialog.nameKey), 'Senior Welder');
    await tapIn(tester, find.byKey(JobRoleFormDialog.submitKey));

    expect(wire.jobRolePatches.single.$1, '20');
    expect(wire.jobRolePatches.single.$2, {'name': 'Senior Welder'});
    expect(find.byType(JobRoleFormDialog), findsNothing);
    expect(find.text('Senior Welder · WELD'), findsOneWidget);
  });

  testWidgets('a non-administrator sees the catalogue but no write control', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, jobRoles: [jobRoleJson('20', 'WELD', 'Welder')]);
    await openJobRoles(tester, wire);

    expect(find.text('Welder · WELD'), findsOneWidget);
    expect(find.byKey(JobRolesScreen.addKey), findsNothing);
    expect(find.byKey(JobRolesScreen.correctKey('20')), findsNothing);
  });
}
