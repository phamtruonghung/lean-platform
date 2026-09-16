/// The job role catalogue (issue #88): every job role the plant recognises,
/// and an administrator's own write surface over it — with the wire faked,
/// the one client seam (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/job_role_form_dialog.dart';
import 'package:lean_platform/people/job_roles_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/app_list_card.dart';
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

  // Issue #103: the shared empty/loading/error states, one of the three
  // migrations proving them — chosen because this Screen used to fall back
  // to a bare `CircularProgressIndicator` and a plain `Text` for its own
  // empty case, the most hand-rolled of the Screens not already worked by
  // #99's own reference Screen (Work orders).

  testWidgets('an empty catalogue carries the action to add one, for an administrator',
      (tester) async {
    await openJobRoles(tester, FakeWire(jobRoles: const []));

    expect(find.byKey(JobRolesScreen.emptyKey), findsOneWidget);
    expect(find.text('No job roles yet'), findsOneWidget);
    expect(find.byKey(JobRolesScreen.emptyAddKey), findsOneWidget);
  });

  testWidgets('an empty catalogue carries no action for a non-administrator', (tester) async {
    await openJobRoles(tester, FakeWire(role: Roles.supervisor, jobRoles: const []));

    expect(find.byKey(JobRolesScreen.emptyKey), findsOneWidget);
    expect(find.byKey(JobRolesScreen.emptyAddKey), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = FakeWire(jobRolesStatus: 503);
    await openJobRoles(tester, wire);

    expect(find.byKey(JobRolesScreen.failedKey), findsOneWidget);
    expect(find.text('Job roles are unavailable.'), findsOneWidget);
    expect(find.byKey(JobRolesScreen.emptyKey), findsNothing);

    wire.jobRolesStatus = 200;
    wire.jobRoles = [jobRoleJson('20', 'WELD', 'Welder')];
    await tapIn(tester, find.byKey(JobRolesScreen.retryKey));

    expect(find.byKey(JobRolesScreen.failedKey), findsNothing);
    expect(find.text('Welder · WELD'), findsOneWidget);
  });

  // The catalogue's rows and its page width (issue #189). This Screen's rows
  // used to sit in a bare `Card` with no rule between them, and its page was
  // 700px wide where the Directory and Org Units beside it were 900 — which is
  // what the user saw as a page that "is not ok".
  testWidgets('rows are ruled apart by the shared list card', (tester) async {
    final wire = FakeWire(
      jobRoles: [
        jobRoleJson('20', 'WELD', 'Welder'),
        jobRoleJson('21', 'FIT', 'Fitter'),
      ],
    );
    await openJobRoles(tester, wire);

    expect(find.byType(AppListCard), findsOneWidget);
    // Two rows, one rule between them — and still the rows' own keys. Scoped to
    // the card: the Shell draws a hairline of its own, so counting `Divider`s
    // page-wide would count that one too.
    expect(
      find.descendant(of: find.byType(AppListCard), matching: find.byType(Divider)),
      findsOneWidget,
    );
    expect(find.byKey(JobRolesScreen.rowKey('20')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.rowKey('21')), findsOneWidget);
  });

  testWidgets('the catalogue page is the Platform page width, not a narrower one',
      (tester) async {
    // A window wide enough for the 900px page to fit whole.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);

    final wire = FakeWire(jobRoles: [jobRoleJson('20', 'WELD', 'Welder')]);
    await openJobRoles(tester, wire);

    // 900 minus the page's own 16px insets is 868; the old 700px page could
    // not produce a catalogue wider than 668.
    expect(tester.getSize(find.byType(AppListCard)).width, greaterThan(800));
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets('the job role catalogue is narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(jobRoles: [
      jobRoleJson('20', 'WELD', 'Welder'),
      jobRoleJson('21', 'FIT', 'Fitter'),
    ]);
    await openJobRoles(tester, wire);

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(JobRolesScreen.rowKey('21')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.rowKey('20')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(JobRolesScreen.filterFieldKey), 'fitter');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(JobRolesScreen.rowKey('21')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.rowKey('20')), findsNothing);
    expect(find.byKey(JobRolesScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(JobRolesScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(JobRolesScreen.rowKey('21')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.rowKey('20')), findsOneWidget);
    expect(find.byKey(JobRolesScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });
}
