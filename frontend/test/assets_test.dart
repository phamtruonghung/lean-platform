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
import 'package:lean_platform/maintenance/asset_form_dialog.dart';
import 'package:lean_platform/maintenance/assets_screen.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? assets,
  int assetsStatus = 200,
  int createAssetStatus = 201,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: assets,
      assetsStatus: assetsStatus,
      createAssetStatus: createAssetStatus,
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
}
