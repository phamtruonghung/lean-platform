/// Sites and the Org Unit tree (issue #90): creating a Site, adding an Org
/// Unit beneath a parent (root-only for an administrator, ADR-0008),
/// retiring/reinstating one, searching a Site's tree by name, and importing a
/// branch in bulk — with the wire faked, the one client seam (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/org_unit_form_dialog.dart';
import 'package:lean_platform/people/org_unit_import_dialog.dart';
import 'package:lean_platform/people/org_units_screen.dart';
import 'package:lean_platform/people/site_form_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> openOrgUnits(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/org-units',
    );

void main() {
  testWidgets('the Org Unit tree renders for the Site an Account can see', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
    );
    await openOrgUnits(tester, wire);

    expect(find.byType(OrgUnitsScreen), findsOneWidget);
    expect(find.text('Line 1 · LINE-1'), findsOneWidget);
  });

  testWidgets('an administrator can create a Site, sending one request', (tester) async {
    final wire = FakeWire(sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));
    expect(find.byType(SiteFormDialog), findsOneWidget);

    await tester.enterText(find.byKey(SiteFormDialog.codeKey), 'NYC');
    await tester.enterText(find.byKey(SiteFormDialog.nameKey), 'New York');
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'America/New_York');
    await tapIn(tester, find.byKey(SiteFormDialog.submitKey));

    expect(wire.sitePosts.single, {
      'code': 'NYC',
      'name': 'New York',
      'timezone': 'America/New_York',
    });
    expect(find.byType(SiteFormDialog), findsNothing);
  });

  testWidgets('adding an Org Unit beneath a parent sends one request carrying parentId',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addChildKey('10')));
    expect(find.byType(OrgUnitFormDialog), findsOneWidget);

    await tester.enterText(find.byKey(OrgUnitFormDialog.codeKey), 'CELL1');
    await tester.enterText(find.byKey(OrgUnitFormDialog.nameKey), 'Cell 1');
    await tapIn(tester, find.byKey(OrgUnitFormDialog.submitKey));

    expect(wire.orgUnitPosts.single.$1, '1');
    expect(wire.orgUnitPosts.single.$2, {
      'parentId': '10',
      'code': 'CELL1',
      'name': 'Cell 1',
      'unitType': 'area',
    });
    expect(find.byType(OrgUnitFormDialog), findsNothing);
  });

  // ADR-0008: a root Org Unit is a whole new branch, and only an
  // administrator may start one — a non-administrator's own root-level rows
  // are their entry points, not real roots.
  testWidgets('an administrator is offered a root-level create', (tester) async {
    final wire = FakeWire(role: Roles.admin, sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openOrgUnits(tester, wire);

    expect(find.byKey(OrgUnitsScreen.addRootKey), findsOneWidget);
  });

  testWidgets('a non-administrator is offered no root-level create', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await openOrgUnits(tester, wire);

    expect(find.byKey(OrgUnitsScreen.addRootKey), findsNothing);
  });

  testWidgets('retiring sends a PATCH with isActive false, and the row reads as retired',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.retireKey('10')));
    expect(find.text('Retire this Org Unit?'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(FilledButton, 'Retire'));

    expect(wire.orgUnitPatches.single.$1, '10');
    expect(wire.orgUnitPatches.single.$2, {'isActive': false});
    // Never deleted — the row is still on screen, marked retired.
    expect(find.text('Line 1 · LINE-1'), findsOneWidget);
    expect(find.byKey(OrgUnitsScreen.retiredChipKey('10')), findsOneWidget);
    expect(find.byKey(OrgUnitsScreen.reinstateKey('10')), findsOneWidget);
  });

  testWidgets('search sends the search parameter, and a truncated result says so', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      orgUnitSearchResults: [orgUnitJson('20', 'Deep Cell')],
      orgUnitSearchTruncated: true,
    );
    await openOrgUnits(tester, wire);

    await tester.enterText(find.byKey(OrgUnitsScreen.searchFieldKey), 'Deep');
    await tapIn(tester, find.byKey(OrgUnitsScreen.searchSubmitKey));

    expect(wire.orgUnitSearchRequests.single, ('1', 'Deep'));
    expect(find.text('Deep Cell · DEEP-CELL'), findsOneWidget);
    expect(find.byKey(OrgUnitsScreen.searchTruncatedKey), findsOneWidget);
  });

  testWidgets('a bulk import sends one request, and a 422 renders every row error', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      importOrgUnitsStatus: 422,
      importOrgUnitsMessage: 'The import contains invalid rows',
      importOrgUnitsErrors: [
        {'row': 0, 'code': 'A1', 'field': 'unitType', 'message': 'unitType must be one of: area, department, line, cell, work_center'},
        {'row': 1, 'code': null, 'field': 'code', 'message': 'code is required'},
      ],
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.importKey));
    expect(find.byType(OrgUnitImportDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(OrgUnitImportDialog.payloadKey),
      '[{"code":"A1","name":"Area 1","unitType":"bogus"},{"name":"No code","unitType":"area"}]',
    );
    await tapIn(tester, find.byKey(OrgUnitImportDialog.submitKey));

    expect(wire.orgUnitImportPosts.single.$1, '1');
    expect(
      (wire.orgUnitImportPosts.single.$2['orgUnits'] as List).length,
      2,
    );
    // Every row's own reason, not only the first.
    expect(find.byKey(OrgUnitImportDialog.rowErrorKey(0)), findsOneWidget);
    expect(find.byKey(OrgUnitImportDialog.rowErrorKey(1)), findsOneWidget);
    expect(find.textContaining('unitType must be one of'), findsOneWidget);
    expect(find.textContaining('code is required'), findsOneWidget);
    // Nothing implies a partial import — the dialog stays open, unsubmitted.
    expect(find.byType(OrgUnitImportDialog), findsOneWidget);
  });

  testWidgets('a scope refusal on adding an Org Unit shows the API\'s own message', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      createOrgUnitStatus: 403,
      createOrgUnitMessage: 'This Account holds no Grant reaching that Org Unit.',
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addChildKey('10')));
    await tester.enterText(find.byKey(OrgUnitFormDialog.codeKey), 'CELL1');
    await tester.enterText(find.byKey(OrgUnitFormDialog.nameKey), 'Cell 1');
    await tapIn(tester, find.byKey(OrgUnitFormDialog.submitKey));

    expect(find.byType(OrgUnitFormDialog), findsOneWidget);
    // Shown both inside the still-open form and, since `OrgUnitAdminBloc`'s
    // mutation state is one shared flag, on the Screen's own banner behind
    // it — the dialog's own copy is what this assertion targets.
    expect(
      find.descendant(
        of: find.byType(OrgUnitFormDialog),
        matching: find.text('This Account holds no Grant reaching that Org Unit.'),
      ),
      findsOneWidget,
    );
  });
}
