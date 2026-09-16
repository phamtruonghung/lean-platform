/// The Asset register (issue #56), with the wire faked — the one client seam
/// (ADR-0012). The real app, the real router, the real Blocs, `MockClient` at
/// the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that the affordance to add is
/// absent for a caller the server would refuse. That is a different claim from
/// "the write is refused", which is proved on the backend in
/// `backend/test/integration/assets.test.js`, and neither substitutes for the
/// other (#55's Testing Decisions).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/asset.dart';
import 'package:lean_platform/maintenance/asset_form_dialog.dart';
import 'package:lean_platform/maintenance/asset_move_dialog.dart';
import 'package:lean_platform/maintenance/assets_bloc.dart';
import 'package:lean_platform/maintenance/assets_screen.dart';
import 'package:lean_platform/maintenance/maintenance_api.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String?, List<Map<String, dynamic>>>? orgUnits,
  Map<String, List<Map<String, dynamic>>>? assets,
  int assetsStatus = 200,
  int createAssetStatus = 201,
  int patchAssetStatus = 200,
  String patchAssetMessage = 'That Asset could not be changed.',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: orgUnits ??
          {
            null: [orgUnitJson('10', 'Assembly')],
            '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
          },
      assets: assets,
      assetsStatus: assetsStatus,
      createAssetStatus: createAssetStatus,
      patchAssetStatus: patchAssetStatus,
      patchAssetMessage: patchAssetMessage,
    );

void main() {
  testWidgets('the register renders what it is given, Org Unit included', (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1', orgUnitName: 'Line 1'),
          assetJson('8', 'CONV-2', 'Infeed conveyor', orgUnitName: 'Line 2'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.text('Press 1'), findsOneWidget);
    expect(find.text('PRESS-1 · Machine'), findsOneWidget);
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Infeed conveyor'), findsOneWidget);
    expect(find.byKey(AssetsScreen.rowKey('7')), findsOneWidget);
  });

  testWidgets('a list still loading shows placeholders in its own shape', (tester) async {
    final wire = wireWith(assets: {'1': []})..assetsGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(AssetsScreen.emptyKey), findsNothing);

    wire.assetsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty register says so, distinguishably from a failure', (tester) async {
    final wire = wireWith(assets: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byKey(AssetsScreen.emptyKey), findsOneWidget);
    expect(find.byKey(AssetsScreen.failedKey), findsNothing);
    expect(find.text('No Assets on the register yet'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = wireWith(assetsStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byKey(AssetsScreen.failedKey), findsOneWidget);
    expect(find.byKey(AssetsScreen.emptyKey), findsNothing);
    expect(find.text('The register is unavailable.'), findsOneWidget);

    wire.assetsStatus = 200;
    wire.assets = {
      '1': [assetJson('7', 'PRESS-1', 'Press 1')],
    };
    await tapIn(tester, find.byKey(AssetsScreen.retryKey));

    expect(find.byKey(AssetsScreen.failedKey), findsNothing);
    expect(find.text('Press 1'), findsOneWidget);
  });

  testWidgets('adding sends exactly one request, carrying the Org Unit chosen in the tree',
      (tester) async {
    final wire = wireWith(assets: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.addKey));
    await tester.enterText(find.byKey(AssetFormDialog.codeKey), 'PRESS-9');
    await tester.enterText(find.byKey(AssetFormDialog.nameKey), 'Press 9');
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(AssetFormDialog.typeKey));
    await tapIn(tester, find.text('Machine').last);

    // The tree is browsed, not typed: expanding Assembly is what fetches Line
    // 1 at all, which is the picker Bloc's own contract, reused unchanged.
    expect(wire.orgUnitRequests, [('1', null)]);
    await tapIn(tester, find.byKey(OrgUnitChooser.expandKey('10')));
    expect(wire.orgUnitRequests, [('1', null), ('1', '10')]);
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('11')));
    expect(find.byKey(AssetFormDialog.chosenKey), findsOneWidget);

    await tapIn(tester, find.byKey(AssetFormDialog.submitKey));

    expect(wire.assetPosts.length, 1);
    expect(wire.assetPosts.single['orgUnitId'], '11');
    expect(wire.assetPosts.single['code'], 'PRESS-9');
    expect(wire.assetPosts.single['name'], 'Press 9');
    expect(wire.assetPosts.single['assetType'], 'machine');
    expect(wire.assetPosts.single['criticality'], 'medium');
    // The register shows it without being re-read.
    expect(find.byType(AssetFormDialog), findsNothing);
    expect(find.text('Press 9'), findsOneWidget);
    expect(wire.requests.where((r) => r == 'GET /api/maintenance/sites/1/assets').length, 1);
  });

  testWidgets('a duplicate code is reported in the form, which stays open', (tester) async {
    final wire = wireWith(assets: {'1': []}, createAssetStatus: 409);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.addKey));
    await tester.enterText(find.byKey(AssetFormDialog.codeKey), 'PRESS-1');
    await tester.enterText(find.byKey(AssetFormDialog.nameKey), 'Press 1');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssetFormDialog.typeKey));
    await tapIn(tester, find.text('Machine').last);
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(AssetFormDialog.submitKey));

    expect(find.byType(AssetFormDialog), findsOneWidget);
    expect(find.byKey(AssetFormDialog.failureKey), findsOneWidget);
    expect(find.text('an Asset with this code already exists'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Correcting an Asset's own details (issue #173): the four fields the
  // register asks for at creation, and nothing else — the placement, the
  // nesting and the retirement all have their own actions.
  // -------------------------------------------------------------------------

  testWidgets("the row action opens the form pre-filled with that row's own four values",
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1', assetType: 'cell', criticality: 'high'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.correctKey('7')));

    expect(
      find.descendant(of: find.byType(AssetFormDialog), matching: find.text('Correct details')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byKey(AssetFormDialog.codeKey)).controller?.text, 'PRESS-1');
    expect(tester.widget<TextField>(find.byKey(AssetFormDialog.nameKey)).controller?.text, 'Press 1');
    expect(
      tester.widget<DropdownButtonFormField<AssetType>>(find.byKey(AssetFormDialog.typeKey)).initialValue,
      AssetType.cell,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<Criticality>>(find.byKey(AssetFormDialog.criticalityKey))
          .initialValue,
      Criticality.high,
    );
    // No Org Unit chooser — placement is its own action.
    expect(find.byType(OrgUnitChooser), findsNothing);
    expect(find.text('Where this Asset sits is changed with its own "Change Org Unit…" action.'),
        findsOneWidget);
  });

  testWidgets('saving sends exactly one PATCH carrying exactly the four fields, and the row '
      "re-renders corrected, staying in the register's own order", (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          // Both at the same Org Unit, so the register's own order (Org
          // Unit name, then code) turns on the code alone — the column a
          // correction changes.
          assetJson('7', 'AAA-1', 'Press 1', orgUnitId: '10', orgUnitName: 'Assembly'),
          assetJson('8', 'BBB-2', 'Infeed conveyor', orgUnitId: '10', orgUnitName: 'Assembly'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(
      tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dy,
      lessThan(tester.getTopLeft(find.byKey(AssetsScreen.rowKey('8'))).dy),
    );

    await tapIn(tester, find.byKey(AssetsScreen.correctKey('7')));
    await tester.enterText(find.byKey(AssetFormDialog.codeKey), 'ZZZ-9');
    await tester.enterText(find.byKey(AssetFormDialog.nameKey), 'Renamed Press');
    await tapIn(tester, find.byKey(AssetFormDialog.typeKey));
    await tapIn(tester, find.text('Utility').last);
    await tapIn(tester, find.byKey(AssetFormDialog.criticalityKey));
    await tapIn(tester, find.text('Critical').last);
    await tapIn(tester, find.byKey(AssetFormDialog.submitKey));

    expect(wire.assetPatches.length, 1);
    expect(wire.assetPatches.single.$1, '7');
    expect(wire.assetPatches.single.$2, {
      'code': 'ZZZ-9',
      'name': 'Renamed Press',
      'assetType': 'utility',
      'criticality': 'critical',
    });

    expect(find.byType(AssetFormDialog), findsNothing);
    expect(find.text('Renamed Press'), findsOneWidget);
    expect(find.text('ZZZ-9 · Utility'), findsOneWidget);
    // Both still at 'Assembly' (that column is untouched), ordered by code:
    // BBB-2 now sorts before ZZZ-9.
    expect(
      tester.getTopLeft(find.byKey(AssetsScreen.rowKey('8'))).dy,
      lessThan(tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dy),
    );
    // Patched from the response, never re-read.
    expect(wire.requests.where((r) => r == 'GET /api/maintenance/sites/1/assets').length, 1);
  });

  testWidgets('a 409 refusal is reported inside the form, which is still open, and the row is '
      'unchanged', (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      patchAssetStatus: 409,
      patchAssetMessage: 'an Asset with this code already exists',
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.correctKey('7')));
    await tester.enterText(find.byKey(AssetFormDialog.codeKey), 'TAKEN');
    await tapIn(tester, find.byKey(AssetFormDialog.submitKey));

    expect(find.byType(AssetFormDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AssetFormDialog.failureKey),
        matching: find.text('an Asset with this code already exists'),
      ),
      findsOneWidget,
    );
    // Closing the dialog shows the row exactly as it was.
    await tapIn(tester, find.byKey(AssetFormDialog.cancelKey));
    expect(find.text('Press 1'), findsOneWidget);
  });

  testWidgets('a caller holding no write Grant reaching the Org Unit is offered no such action',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1', orgUnitId: '10')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.text('Press 1'), findsOneWidget);
    expect(find.byKey(AssetsScreen.correctKey('7')), findsNothing);
  });

  testWidgets('an operator is offered neither the destination nor the Screen', (tester) async {
    final wire = wireWith(role: Roles.operator, assets: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(AssetsScreen), findsNothing);
    expect(find.widgetWithText(NavigationRail, 'Assets'), findsNothing);
    // Nothing was even asked of the register.
    expect(wire.requests.any((r) => r.contains('/api/maintenance/')), isFalse);
  });

  testWidgets('a supervisor gets the destination and the Screen', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      assets: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byType(AssetsScreen), findsOneWidget);
    expect(find.text('Assets'), findsWidgets);
    expect(find.byKey(AssetsScreen.addKey), findsOneWidget);
  });

  testWidgets('a supervisor with no write Grant is offered no way to add', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    // The register itself is Site-wide: they read every Asset regardless.
    expect(find.text('Press 1'), findsOneWidget);
    expect(find.byKey(AssetsScreen.addKey), findsNothing);
  });

  testWidgets(
      'switching the chooser to a different Site drops the Org Unit already chosen there',
      (tester) async {
    final wire = wireWith(
      assets: {'1': []},
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'DN', 'Da Nang')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.addKey));
    await tester.enterText(find.byKey(AssetFormDialog.codeKey), 'PRESS-9');
    await tester.enterText(find.byKey(AssetFormDialog.nameKey), 'Press 9');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssetFormDialog.typeKey));
    await tapIn(tester, find.text('Machine').last);
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(find.byKey(AssetFormDialog.chosenKey), findsOneWidget);
    var submit = tester.widget<FilledButton>(find.byKey(AssetFormDialog.submitKey));
    expect(submit.onPressed, isNotNull);

    // The chooser reloads on Da Nang's own roots; the node chosen in Ho Chi
    // Minh does not belong there any more.
    await tapIn(tester, find.byKey(OrgUnitChooser.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(find.byKey(AssetFormDialog.chosenKey), findsNothing);
    submit = tester.widget<FilledButton>(find.byKey(AssetFormDialog.submitKey));
    expect(submit.onPressed, isNull);
  });

  testWidgets(
      "a retry after switching Site re-opens on the caller's Site, not back on the first",
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'DN', 'Da Nang')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.text('Press 1'), findsOneWidget);

    wire.assetsStatus = 503;
    await tapIn(tester, find.byKey(AssetsScreen.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(find.byKey(AssetsScreen.failedKey), findsOneWidget);

    wire.assetsStatus = 200;
    wire.assets = {
      '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      '2': [assetJson('9', 'CONV-9', 'Da Nang conveyor')],
    };
    await tapIn(tester, find.byKey(AssetsScreen.retryKey));

    expect(find.byKey(AssetsScreen.failedKey), findsNothing);
    expect(find.text('Da Nang conveyor'), findsOneWidget);
    expect(find.text('Press 1'), findsNothing);
  });

  testWidgets('nesting is visible in the register, indented beneath its own machine',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1'),
          assetJson('8', 'MOTOR-1', 'Drive motor', parentId: '7'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byKey(AssetsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(AssetsScreen.rowKey('8')), findsOneWidget);

    final parentLeft = tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dx;
    final childLeft = tester.getTopLeft(find.byKey(AssetsScreen.rowKey('8'))).dx;
    expect(childLeft, greaterThan(parentLeft));
  });

  testWidgets('an Asset whose parent is not in this list still renders as a root',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1'),
          // '999' names an Asset in another Site, or a retired one filtered
          // out — either way, not a row this list was given.
          assetJson('9', 'ORPHAN-1', 'Orphan unit', parentId: '999'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byKey(AssetsScreen.rowKey('9')), findsOneWidget);
    final rootLeft = tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dx;
    final orphanLeft = tester.getTopLeft(find.byKey(AssetsScreen.rowKey('9'))).dx;
    expect(orphanLeft, rootLeft);
  });

  testWidgets(
      'a cycle in the parent links still renders every Asset, flattened rather than dropped',
      (tester) async {
    // The server refuses to create a cycle; this is defensive only, proving
    // the register does not silently lose rows if malformed data ever
    // reached the client some other way.
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1', parentId: '8'),
        assetJson('8', 'PRESS-2', 'Press 2', parentId: '7'),
      ],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.byKey(AssetsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(AssetsScreen.rowKey('8')), findsOneWidget);
  });

  testWidgets('a retired Asset is absent until asked for, then visibly marked as retired',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1'),
          assetJson('8', 'PRESS-2', 'Press 2', isActive: false),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.text('Press 1'), findsOneWidget);
    expect(find.text('Press 2'), findsNothing);
    expect(find.byKey(AssetsScreen.rowKey('8')), findsNothing);

    await tapIn(tester, find.byKey(AssetsScreen.showRetiredKey));

    expect(find.text('Press 2'), findsOneWidget);
    expect(find.byKey(AssetsScreen.retiredChipKey('8')), findsOneWidget);
    expect(find.byKey(AssetsScreen.retiredChipKey('7')), findsNothing);
  });

  testWidgets("showing retired survives a Site switch", (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1', isActive: false)],
        '2': [assetJson('9', 'CONV-9', 'Da Nang conveyor', isActive: false)],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'DN', 'Da Nang')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(find.text('Press 1'), findsNothing);
    await tapIn(tester, find.byKey(AssetsScreen.showRetiredKey));
    expect(find.text('Press 1'), findsOneWidget);

    await tapIn(tester, find.byKey(AssetsScreen.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(find.text('Da Nang conveyor'), findsOneWidget);
  });

  testWidgets(
      'retiring asks first, sends exactly one PATCH, and drops the row while retired ones '
      'are hidden', (tester) async {
    final wire = wireWith(assets: {
      '1': [assetJson('7', 'PRESS-1', 'Press 1')],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.retireKey('7')));
    expect(find.text('Retire this Asset?'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(wire.assetPatches, isEmpty);

    await tapIn(tester, find.byKey(AssetsScreen.retireKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Retire'));

    expect(wire.assetPatches.length, 1);
    expect(wire.assetPatches.single.$1, '7');
    expect(wire.assetPatches.single.$2, {'isActive': false});
    // Retired ones are hidden by default, so the row simply drops out.
    expect(find.byKey(AssetsScreen.rowKey('7')), findsNothing);
  });

  testWidgets('reinstating a shown retired Asset sends exactly one PATCH and asks nothing',
      (tester) async {
    final wire = wireWith(assets: {
      '1': [assetJson('7', 'PRESS-1', 'Press 1', isActive: false)],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );
    await tapIn(tester, find.byKey(AssetsScreen.showRetiredKey));
    expect(find.byKey(AssetsScreen.reinstateKey('7')), findsOneWidget);

    await tapIn(tester, find.byKey(AssetsScreen.reinstateKey('7')));

    expect(wire.assetPatches.length, 1);
    expect(wire.assetPatches.single.$1, '7');
    expect(wire.assetPatches.single.$2, {'isActive': true});
    expect(find.byKey(AssetsScreen.retiredChipKey('7')), findsNothing);
    expect(find.byKey(AssetsScreen.retireKey('7')), findsOneWidget);
  });

  testWidgets(
      'nesting under another Asset sends { parentId }, and detaching sends { parentId: null }',
      (tester) async {
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1'),
        assetJson('8', 'PRESS-2', 'Press 2'),
      ],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.nestKey('8')));
    expect(find.byKey(AssetsScreen.parentChooserKey), findsOneWidget);
    await tapIn(tester, find.byKey(AssetsScreen.parentOptionKey('7')));

    expect(wire.assetPatches.length, 1);
    expect(wire.assetPatches.single.$1, '8');
    expect(wire.assetPatches.single.$2, {'parentId': '7'});
    expect(find.byKey(AssetsScreen.detachKey('8')), findsOneWidget);

    await tapIn(tester, find.byKey(AssetsScreen.detachKey('8')));

    expect(wire.assetPatches.length, 2);
    expect(wire.assetPatches.last.$1, '8');
    expect(wire.assetPatches.last.$2, {'parentId': null});
    expect(find.byKey(AssetsScreen.nestKey('8')), findsOneWidget);
  });

  testWidgets('the parent chooser excludes the Asset itself and its own descendants',
      (tester) async {
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1'),
        assetJson('8', 'MOTOR-1', 'Drive motor', parentId: '7'),
        assetJson('9', 'PRESS-2', 'Press 2'),
      ],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.nestKey('7')));
    expect(find.byKey(AssetsScreen.parentOptionKey('7')), findsNothing);
    expect(find.byKey(AssetsScreen.parentOptionKey('8')), findsNothing);
    expect(find.byKey(AssetsScreen.parentOptionKey('9')), findsOneWidget);
  });

  testWidgets(
      'the parent chooser excludes a retired Asset too, even with "Show retired" on',
      (tester) async {
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1'),
        assetJson('8', 'PRESS-2', 'Press 2', isActive: false),
      ],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    // The retired Asset is only on screen at all once asked for.
    await tapIn(tester, find.byKey(AssetsScreen.showRetiredKey));
    expect(find.byKey(AssetsScreen.retiredChipKey('8')), findsOneWidget);

    await tapIn(tester, find.byKey(AssetsScreen.nestKey('7')));
    expect(find.byKey(AssetsScreen.parentChooserKey), findsOneWidget);
    // The backend rejects nesting under a retired Asset with 409 — not
    // offered here at all, rather than earning the caller a refusal after
    // they had already chosen it.
    expect(find.byKey(AssetsScreen.parentOptionKey('8')), findsNothing);
  });

  testWidgets(
      'a 409 refusal for parts still fitted surfaces its message and leaves the row as it was',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      patchAssetStatus: 409,
      patchAssetMessage: 'This Asset still has active parts fitted.',
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.retireKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Retire'));

    expect(find.text('This Asset still has active parts fitted.'), findsOneWidget);
    expect(find.byKey(AssetsScreen.retireKey('7')), findsOneWidget);
    expect(find.byKey(AssetsScreen.reinstateKey('7')), findsNothing);
  });

  // The two tests below replace a single prior test, "a second row's action
  // while one is already in flight is reported, not silently dropped", which
  // tapped a second row's action and expected the confirmation dialog to
  // open and then report a snackbar. That path is now unreachable from the
  // UI: row actions are disabled the moment any mutation is in flight (see
  // the fix to `_AssetsList`/`_AssetRow` below), so a widget test can no
  // longer reach a second row's confirm dialog at all. The coverage is split
  // honestly instead: a widget-level test that the other row's controls are
  // actually disabled, and a Bloc-level test — bypassing the UI, dispatching
  // straight at the Bloc — that pins the defence-in-depth guard in
  // `_onActiveToggled`/`_onParentChanged`, which still exists and still fires
  // even though the UI can no longer trigger it.

  testWidgets(
      "another row's actions are disabled while one mutation is already in flight, so its "
      'confirmation dialog cannot even be reached', (tester) async {
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1'),
        assetJson('8', 'PRESS-2', 'Press 2'),
      ],
    })
      ..assetPatchGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    // Row 7's retirement starts, and hangs on the gate.
    await tapIn(tester, find.byKey(AssetsScreen.retireKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Retire'));

    // Row 8's own actions are disabled outright while row 7 is still busy —
    // not merely reported after the fact.
    final row8Retire = tester.widget<OutlinedButton>(find.byKey(AssetsScreen.retireKey('8')));
    expect(row8Retire.onPressed, isNull);
    final row8Nest = tester.widget<OutlinedButton>(find.byKey(AssetsScreen.nestKey('8')));
    expect(row8Nest.onPressed, isNull);

    // Tapping a disabled control is a no-op: no dialog opens, no event
    // reaches the Bloc.
    await tapIn(tester, find.byKey(AssetsScreen.nestKey('8')));
    expect(find.byKey(AssetsScreen.parentChooserKey), findsNothing);
    expect(wire.assetPatches.length, 1);

    wire.assetPatchGate!.complete();
    await tester.pumpAndSettle();
    expect(wire.assetPatches.length, 1);
    expect(find.byKey(AssetsScreen.rowKey('7')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Changing where an Asset sits (issue #171): the Org Unit is the one field
  // the register set at creation and could not correct afterwards.
  // -------------------------------------------------------------------------

  testWidgets(
      'changing where an Asset sits names where it is now, sends exactly { orgUnitId }, and '
      'leaves the row where the register orders it', (tester) async {
    final wire = wireWith(assets: {
      '1': [
        // PRESS-1 at Assembly and CONV-2 at Line 1, so the register's own
        // order (Org Unit name, then code) has PRESS-1 first until it moves.
        assetJson('7', 'PRESS-1', 'Press 1', orgUnitId: '10', orgUnitName: 'Assembly'),
        assetJson('8', 'CONV-2', 'Infeed conveyor', orgUnitId: '11', orgUnitName: 'Line 1'),
      ],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    expect(
      tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dy,
      lessThan(tester.getTopLeft(find.byKey(AssetsScreen.rowKey('8'))).dy),
    );

    await tapIn(tester, find.byKey(AssetsScreen.orgUnitKey('7')));

    // The dialog says where the machine sits now, and the Org Unit it is at is
    // a standing choice rather than a destination: nothing has been chosen, so
    // there is nothing to submit.
    expect(find.text('Press 1 (PRESS-1) sits at Assembly now.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(AssetMoveDialog.submitKey)).onPressed,
      isNull,
    );

    // The tree is browsed, not typed — expanding Assembly is what fetches
    // Line 1 at all, the picker Bloc's own contract, reused unchanged.
    await tapIn(tester, find.byKey(OrgUnitChooser.expandKey('10')));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('11')));
    expect(find.text('This Asset will sit at Line 1.'), findsOneWidget);

    await tapIn(tester, find.byKey(AssetMoveDialog.submitKey));

    // One request, one field: a move is not a retirement and not a re-parent,
    // and the route refuses a body that names two of them.
    expect(wire.assetPatches.length, 1);
    expect(wire.assetPatches.single.$1, '7');
    expect(wire.assetPatches.single.$2, {'orgUnitId': '11'});

    expect(find.byType(AssetMoveDialog), findsNothing);
    expect(find.text('PRESS-1 now sits at Line 1.'), findsOneWidget);

    // The row re-renders at the Org Unit it arrived at, and the register's own
    // order puts it after CONV-2 — both now at Line 1, ordered by code.
    expect(
      find.descendant(of: find.byKey(AssetsScreen.rowKey('7')), matching: find.text('Line 1')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(AssetsScreen.rowKey('8'))).dy,
      lessThan(tester.getTopLeft(find.byKey(AssetsScreen.rowKey('7'))).dy),
    );
  });

  testWidgets('a move the server refuses leaves the row where it was and says why',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1', orgUnitId: '10', orgUnitName: 'Assembly')],
      },
      patchAssetStatus: 403,
      patchAssetMessage: "Outside the caller's granted Org Units",
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.orgUnitKey('7')));
    await tapIn(tester, find.byKey(OrgUnitChooser.expandKey('10')));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('11')));
    await tapIn(tester, find.byKey(AssetMoveDialog.submitKey));

    expect(wire.assetPatches.single.$2, {'orgUnitId': '11'});
    // The refusal is the server's own words, and the row still says Assembly:
    // the register is patched from the answer, never from the request.
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(AssetsScreen.rowKey('7')), matching: find.text('Assembly')),
      findsOneWidget,
    );
  });

  testWidgets('a move to another Site takes the row off this register and says where it went',
      (tester) async {
    // A taller surface than the default 800x600 (issue #171's own test only):
    // a caller with two Sites gets the register's Site chooser as well, and
    // once this move empties the register the empty state — whose content is
    // not scrollable — is 44px taller than what is left of the window. That is
    // a pre-existing shape of `_AssetsEmpty` at a short height, not something
    // this ticket changes, and the claim under test here is the notice and the
    // row, not the layout of an empty state.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'DNA', 'Da Nang')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly'), orgUnitJson('20', 'Elsewhere', siteId: '2')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1', orgUnitId: '10', orgUnitName: 'Assembly')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/assets',
    );

    await tapIn(tester, find.byKey(AssetsScreen.orgUnitKey('7')));
    await tapIn(tester, find.byKey(OrgUnitChooser.siteKey));
    await tapIn(tester, find.text('Da Nang').last);
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('20')));
    await tapIn(tester, find.byKey(AssetMoveDialog.submitKey));

    expect(wire.assetPatches.single.$2, {'orgUnitId': '20'});
    // This register is one Site's, and the machine has left it — so the row
    // goes, and the notice accounts for it rather than letting it vanish.
    expect(find.byKey(AssetsScreen.rowKey('7')), findsNothing);
    expect(
      find.text('PRESS-1 has left this Site — it now sits at Elsewhere, at Da Nang.'),
      findsOneWidget,
    );
  });

  test(
      'a racing event dispatched straight at the Bloc while a mutation is already in flight is '
      'still reported, not silently dropped — the UI-level guard above cannot reach this path, '
      'but the Bloc must still defend it on its own', () async {
    final wire = wireWith(assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1'),
        assetJson('8', 'PRESS-2', 'Press 2'),
      ],
    })
      ..assetPatchGate = Completer<void>();
    final bloc = AssetsBloc(
      maintenanceApi: MaintenanceApi(client: wire.client),
      peopleApi: PeopleApi(client: wire.client),
      authGateway: FakeAuthGateway(accessToken: 'a-token'),
    );
    addTearDown(bloc.close);

    bloc.add(const AssetsStarted());
    await pumpEventQueue();
    expect((bloc.state as AssetsLoaded).assets.length, 2);

    // Row 7's retirement starts, and hangs on the gate.
    bloc.add(const AssetActiveToggled(assetId: '7', isActive: false));
    await pumpEventQueue();
    expect((bloc.state as AssetsLoaded).mutatingAssetId, '7');

    // Row 8's own event races in directly, bypassing whatever the UI would
    // have disabled.
    bloc.add(const AssetActiveToggled(assetId: '8', isActive: false));
    await pumpEventQueue();

    expect(wire.assetPatches.length, 1);
    expect((bloc.state as AssetsLoaded).notice, AssetsBloc.inFlightMessage);

    wire.assetPatchGate!.complete();
    await pumpEventQueue();
  });
}
