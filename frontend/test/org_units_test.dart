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
import 'package:lean_platform/widgets/failure_state.dart';

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

  // The timezone field is `AppSearchField` (issue #127, ADR-0023), fed by
  // `GET /api/people/timezones` (issue #123) — no free-text timezone input
  // remains, so every one of these types a term, waits out the debounce, and
  // taps the suggestion rather than sending whatever was typed.
  testWidgets('an administrator can create a Site, sending one request', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezones: const ['America/New_York', 'Europe/London'],
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));
    expect(find.byType(SiteFormDialog), findsOneWidget);

    await tester.enterText(find.byKey(SiteFormDialog.codeKey), 'NYC');
    await tester.enterText(find.byKey(SiteFormDialog.nameKey), 'New York');
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'new_york');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byKey(SiteFormDialog.timezoneSuggestionKey('America/New_York')));
    await tester.pump();
    await tapIn(tester, find.byKey(SiteFormDialog.submitKey));

    expect(wire.sitePosts.single, {
      'code': 'NYC',
      'name': 'New York',
      'timezone': 'America/New_York',
    });
    expect(find.byType(SiteFormDialog), findsNothing);
  });

  testWidgets('typing "lon" shows Europe/London, and picking it sends Europe/London through FakeWire',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezones: const ['Europe/London', 'Europe/Paris', 'US/Eastern', 'Asia/Ho_Chi_Minh'],
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));
    await tester.enterText(find.byKey(SiteFormDialog.codeKey), 'LON');
    await tester.enterText(find.byKey(SiteFormDialog.nameKey), 'London');
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'lon');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Europe/London'), findsOneWidget);

    await tester.tap(find.byKey(SiteFormDialog.timezoneSuggestionKey('Europe/London')));
    await tester.pump();
    await tapIn(tester, find.byKey(SiteFormDialog.submitKey));

    expect(wire.sitePosts.single['timezone'], 'Europe/London');
  });

  // AC: a chosen zone is not silently lost the moment a later, unrelated
  // term stops matching anything — picking is what sets the value
  // (`AppSearchField`'s own contract, app_search_field.dart), typing after
  // the fact narrows the *suggestion list* only. This is the reachable half
  // of the ticket's "a stored value not in the fetched list still displays"
  // concern: `SiteFormDialog` has no Site-correction surface to open on an
  // existing Site at all (this dialog is Add-only, no `PATCH /sites/:id`
  // exists) — `AppSearchField`'s own "an initial value is displayed on first
  // build, before any fetch happens" test (app_search_field_test.dart) is
  // what actually covers a caller-seeded value surviving a filtered-out
  // list; there is no real call site here to seed one from.
  testWidgets('a chosen zone survives a later term that matches nothing, and submits unchanged',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezones: const ['Europe/London', 'US/Eastern'],
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));
    await tester.enterText(find.byKey(SiteFormDialog.codeKey), 'LON');
    await tester.enterText(find.byKey(SiteFormDialog.nameKey), 'London');
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'lon');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byKey(SiteFormDialog.timezoneSuggestionKey('Europe/London')));
    await tester.pump();

    // A later term that matches nothing narrows the suggestion list only —
    // it never clears the already-picked value.
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'zzzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byKey(SiteFormDialog.submitKey)).onPressed,
      isNotNull,
    );

    await tapIn(tester, find.byKey(SiteFormDialog.submitKey));

    expect(wire.sitePosts.single['timezone'], 'Europe/London');
  });

  testWidgets(
      'the timezone list is fetched once when the dialog opens, not once per keystroke',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezones: const ['Europe/London', 'Europe/Paris', 'US/Eastern'],
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));
    expect(wire.requests.where((r) => r == 'GET /api/people/timezones').length, 1);

    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'e');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'eu');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byKey(SiteFormDialog.timezoneKey), 'eur');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // Still exactly one — every keystroke above filtered the same
    // already-fetched list in memory rather than asking the wire again.
    expect(wire.requests.where((r) => r == 'GET /api/people/timezones').length, 1);
  });

  testWidgets(
      'when the timezone list fetch fails, FailureState renders and blocks submission; typed text is never accepted as a value',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezonesStatus: 503,
    );
    await openOrgUnits(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));

    expect(find.byType(PlatformFailureState), findsOneWidget);
    // No free-text fallback: the search field itself is not even on screen.
    expect(find.byKey(SiteFormDialog.timezoneKey), findsNothing);

    await tester.enterText(find.byKey(SiteFormDialog.codeKey), 'NYC');
    await tester.enterText(find.byKey(SiteFormDialog.nameKey), 'New York');

    expect(tester.widget<FilledButton>(find.byKey(SiteFormDialog.submitKey)).onPressed, isNull);
  });

  testWidgets('retrying a failed timezone fetch re-fetches, and success makes the control usable',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      timezonesStatus: 503,
    );
    await openOrgUnits(tester, wire);
    await tapIn(tester, find.byKey(OrgUnitsScreen.addSiteKey));

    expect(find.byType(PlatformFailureState), findsOneWidget);

    wire.timezonesStatus = 200;
    wire.timezones = const ['Europe/London'];
    await tapIn(tester, find.byKey(SiteFormDialog.timezoneRetryKey));

    expect(find.byType(PlatformFailureState), findsNothing);
    expect(find.byKey(SiteFormDialog.timezoneKey), findsOneWidget);
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
