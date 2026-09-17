/// The two 5 Why chains on a CAPA (issue #210), with the wire faked — the one
/// client seam (ADR-0012). The real app, the real router, the real Blocs,
/// `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
///
/// What these tests claim and what they do not: that the CAPA's detail Screen
/// shows both chains in the order they are reasoned, that a writer — edit
/// access at the CAPA's Org Unit or a place on its team — adds, revises, moves,
/// marks and removes Whys through this Screen with each dialog at its own
/// address, that the requests those acts send carry exactly what they say (a
/// chain and a statement, one field, one position, one mark, one id), and that
/// every address refuses what the CAPA or the caller cannot answer. Not that
/// the server keeps a chain contiguous, replaces a root cause or refuses a
/// caller without access — that is proved in
/// `backend/test/integration/capa-whys.test.js`, and neither substitutes for
/// the other (mirroring `capas_test.dart`'s own Testing Decisions).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/capa_detail_screen.dart';
import 'package:lean_platform/actions/capa_why_dialog.dart';

import 'harness.dart';

const String _capaNo = 'CA-HCM-2026-00001';

/// The Concern the CAPA was opened on, as the CAPA's own read carries it.
Map<String, dynamic> _concern() => actionJson(
      '501',
      'AC-HCM-2026-00001',
      'The guard keeps working loose',
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
    );

/// One CAPA with both chains under way: three Whys in the occurrence chain with
/// the second one confirmed as the root cause, and one in the escape chain with
/// no conclusion yet — the state an investigation is in halfway through D4.
Map<String, dynamic> _capa({
  String status = 'open',
  List<Map<String, dynamic>>? whys,
  Map<String, dynamic>? teamLead = const {'employeeId': '7', 'name': 'Ada Lead'},
  List<Map<String, dynamic>> teamMembers = const [
    {'employeeId': '8', 'name': 'Bo Member'},
  ],
}) =>
    capaJson(
      '801',
      _capaNo,
      'The guard keeps working loose',
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      problemStatement: 'The guard comes loose after about 400 cycles.',
      teamLead: teamLead,
      teamMembers: teamMembers,
      whys: whys ??
          [
            capaWhyJson('901', 1, 'The guard works loose after 400 cycles.'),
            capaWhyJson('902', 2, 'The fastener was not torqued to the standard.',
                isRoot: true),
            capaWhyJson('903', 3, 'The torque step is not on the check sheet.'),
            capaWhyJson('904', 1, 'Nobody looks behind the machine between shifts.',
                chain: 'escape'),
          ],
      concern: _concern(),
    );

/// The wire every test in this file starts from: one Site, one line, an
/// Employee directory, and one CAPA with both chains under way.
///
/// [write] and [selfEmployeeId] are the two halves of the rule that decides who
/// is offered the chain controls — edit access at the CAPA's Org Unit, or a
/// place on its team — and every test that asserts a refusal or an offer turns
/// on exactly one of them.
FakeWire _wire({
  bool write = true,
  bool quality = true,
  String? selfEmployeeId,
  Map<String, dynamic>? capa,
  int addWhyStatus = 201,
  String addWhyMessage =
      "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team",
  int changeWhyStatus = 200,
  String changeWhyMessage = 'That Why could not be changed.',
  int removeWhyStatus = 200,
  String removeWhyMessage = 'That Why could not be removed.',
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('11', 'Line 1')],
      },
      employees: [
        employeeJson('7', 'E-7', 'Ada Lead'),
        employeeJson('8', 'E-8', 'Bo Member'),
      ],
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: write, qualityAuthority: quality)],
      },
      selfEmployeeId: selfEmployeeId,
      capas: {'801': capa ?? _capa()},
      addWhyStatus: addWhyStatus,
      addWhyMessage: addWhyMessage,
      changeWhyStatus: changeWhyStatus,
      changeWhyMessage: changeWhyMessage,
      removeWhyStatus: removeWhyStatus,
      removeWhyMessage: removeWhyMessage,
    );

/// A caller who holds nothing at all: no Grant anywhere, and — unless a test
/// links one — no Employee either. The CAPA's chains are readable (reading is
/// Site-wide) and, with no Employee on the team, not writable.
FakeWire _strangerWire({int addWhyStatus = 201, String? selfEmployeeId}) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('11', 'Line 1')],
      },
      employees: [
        employeeJson('7', 'E-7', 'Ada Lead'),
        employeeJson('8', 'E-8', 'Bo Member'),
      ],
      orgUnitScope: {'everywhere': false, 'grants': const <dynamic>[]},
      selfEmployeeId: selfEmployeeId,
      capas: {'801': _capa()},
      addWhyStatus: addWhyStatus,
    );

/// The chains sit below the team, the problem and the header in a lazily-built
/// `ListView`, and each Why's own row carries five controls — so at the default
/// 800x600 surface the lower chain is not in the widget tree at all and
/// `find.byKey` fails for a control that is really there. Pinned tall for every
/// test that reads or drives the chains.
void _tallWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the CAPA detail shows both chains in order, with the confirmed root cause marked',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.chainsKey), findsOneWidget);
    // Both chains are there, whatever the caller may do with them.
    expect(find.byKey(CapaDetailScreen.chainKey('occurrence')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.chainKey('escape')), findsOneWidget);
    expect(find.text('Why it happened (3)'), findsOneWidget);
    expect(find.text('Why it was not detected (1)'), findsOneWidget);

    // Each Why is in its row, in its chain's own order, carrying what it says.
    expect(find.byKey(CapaDetailScreen.whyKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyKey('902')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyKey('903')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyKey('904')), findsOneWidget);
    expect(find.text('The fastener was not torqued to the standard.'), findsOneWidget);
    expect(find.text('Nobody looks behind the machine between shifts.'), findsOneWidget);

    // The chain that has concluded says where it stopped; the one that has not
    // says so, which is the state #211 refuses to close a CAPA on.
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('902')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('901')), findsNothing);
    expect(
      find.text('Confirmed root cause: The fastener was not torqued to the standard.'),
      findsOneWidget,
    );
    expect(find.text('This chain has no confirmed root cause yet.'), findsOneWidget);

    // Reading them asks for nothing.
    expect(wire.whyPosts, isEmpty);
    expect(wire.whyPatches, isEmpty);
    expect(wire.whyDeletions, isEmpty);
  });

  testWidgets('a caller with edit access at the CAPA Org Unit is offered the chain controls',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.addWhyKey('occurrence')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.addWhyKey('escape')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyEditKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyRemoveKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyMarkRootKey('903')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.chainsReadOnlyKey), findsNothing);

    // The ends of a chain offer no move: there is nowhere to go, and the
    // position sent is a position in the chain.
    expect(tester.widget<IconButton>(find.byKey(CapaDetailScreen.whyEarlierKey('901'))).onPressed,
        isNull);
    expect(tester.widget<IconButton>(find.byKey(CapaDetailScreen.whyLaterKey('901'))).onPressed,
        isNotNull);
    expect(tester.widget<IconButton>(find.byKey(CapaDetailScreen.whyLaterKey('903'))).onPressed,
        isNull);
  });

  testWidgets('a reader who may not write sees both chains and no controls, and sends nothing',
      (tester) async {
    _tallWindow(tester);
    // A read Grant reaching the CAPA's Org Unit: the caller can read the
    // investigation anywhere, and may not write its chains.
    final wire = _wire(write: false);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // The chains themselves are never hidden — reading is Site-wide.
    expect(find.byKey(CapaDetailScreen.whyKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.chainKey('escape')), findsOneWidget);
    // ...and the Screen says what would be needed rather than offering buttons
    // whose requests would come back 403.
    expect(find.byKey(CapaDetailScreen.chainsReadOnlyKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.addWhyKey('occurrence')), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyEditKey('901')), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyRemoveKey('901')), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyMarkRootKey('901')), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyEarlierKey('901')), findsNothing);
    expect(wire.whyPosts, isEmpty);
    expect(wire.whyPatches, isEmpty);
    expect(wire.whyDeletions, isEmpty);
  });

  testWidgets('a place on the CAPA team is enough on its own to write the chains', (tester) async {
    _tallWindow(tester);
    // No Grant anywhere — the caller's Account is linked to the Employee who is
    // a member of this CAPA's team, and that is the whole second half of the
    // rule: an engineer on the investigation is not necessarily a Grant-holder.
    final wire = _strangerWire(selfEmployeeId: '8');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.addWhyKey('occurrence')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyEditKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.chainsReadOnlyKey), findsNothing);
  });

  testWidgets('adding a Why is its own address, sends the chain it names, and lands on the chain',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.addWhyKey('escape')));

    // The address is the whole request: this is the escape chain's own form.
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/whys/escape/new',
    );
    expect(find.byKey(CapaWhyDialog.statementKey), findsOneWidget);
    // Opening the form is not adding anything.
    expect(wire.whyPosts, isEmpty);

    await tester.enterText(
      find.byKey(CapaWhyDialog.statementKey),
      'The start-up check stops at the operator panel.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaWhyDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.whyPosts, hasLength(1));
    final (capaId, body) = wire.whyPosts.single;
    expect(capaId, '801');
    expect(body['chain'], 'escape');
    expect(body['statement'], 'The start-up check stops at the operator panel.');

    // The Screen behind now shows it, in its own chain and at the next position
    // of it — the answer the server sent, not a state the dialog kept.
    expect(find.byKey(CapaWhyDialog.statementKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyKey('900')), findsOneWidget);
    expect(find.text('Why it was not detected (2)'), findsOneWidget);
    // The notice is the page's own (issue #211 moved it out of the chains
    // section, which is no longer the only thing this Screen writes), so it is
    // found once however long the page is.
    expect(find.byKey(CapaDetailScreen.noticeKey), findsOneWidget);
    expect(find.text('The Why was added to the chain.'), findsOneWidget);
  });

  testWidgets('revising a Why sends the one field that changed, and the chain shows it',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.whyEditKey('902')));

    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/whys/occurrence/902/edit',
    );
    // The form is filled with what the Why says now: a revision starts from the
    // row, not from a blank field.
    expect(
      tester.widget<TextField>(find.byKey(CapaWhyEditDialog.statementKey)).controller?.text,
      'The fastener was not torqued to the standard.',
    );

    await tester.enterText(
      find.byKey(CapaWhyEditDialog.statementKey),
      'The fastener was not torqued to the standard, on the left fixture.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaWhyEditDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.whyPatches, hasLength(1));
    final (capaId, whyId, body) = wire.whyPatches.single;
    expect(capaId, '801');
    expect(whyId, '902');
    // One field, and only the one: a revision does not restate the position or
    // the root-cause mark.
    expect(body, {'statement': 'The fastener was not torqued to the standard, on the left fixture.'});

    expect(
      find.text('The fastener was not torqued to the standard, on the left fixture.'),
      findsOneWidget,
    );
    expect(find.text('The Why was revised.'), findsOneWidget);
  });

  testWidgets('removing a Why asks first, then sends a delete for that Why alone', (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.whyRemoveKey('902')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/whys/occurrence/902/remove',
    );
    // The confirmation shows what is about to go, and cancelling sends nothing.
    expect(find.text('The fastener was not torqued to the standard.'), findsWidgets);
    await tester.tap(find.byKey(CapaWhyRemoveDialog.cancelKey));
    await tester.pumpAndSettle();
    expect(wire.whyDeletions, isEmpty);
    expect(find.byKey(CapaDetailScreen.whyKey('902')), findsOneWidget);

    await tapIn(tester, find.byKey(CapaDetailScreen.whyRemoveKey('902')));
    await tester.tap(find.byKey(CapaWhyRemoveDialog.confirmKey));
    await tester.pumpAndSettle();

    expect(wire.whyDeletions, hasLength(1));
    expect(wire.whyDeletions.single, ('801', '902'));
    // The Why is gone from the screen, the chain is renumbered around the gap,
    // and the chain that was concluded has no root cause any more.
    expect(find.byKey(CapaDetailScreen.whyKey('902')), findsNothing);
    expect(find.text('Why it happened (2)'), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('903')), findsNothing);
    expect(find.text('This chain has no confirmed root cause yet.'), findsWidgets);
    expect(
      find.text('The Why was removed, and the chain renumbered around the gap.'),
      findsOneWidget,
    );
  });

  testWidgets('marking a root cause sends the mark, and marking another replaces it',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // The chain already ends at Why 2; Why 3 becomes the conclusion instead.
    await tapIn(tester, find.byKey(CapaDetailScreen.whyMarkRootKey('903')));
    expect(wire.whyPatches, hasLength(1));
    expect(wire.whyPatches.single.$3, {'isRoot': true});
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('903')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('902')), findsNothing);
    expect(find.text('That Why is the confirmed root cause of its chain.'), findsOneWidget);

    // And it can be undone while the investigation is open.
    await tapIn(tester, find.byKey(CapaDetailScreen.whyMarkRootKey('903')));
    expect(wire.whyPatches, hasLength(2));
    expect(wire.whyPatches.last.$3, {'isRoot': false});
    expect(find.byKey(CapaDetailScreen.whyRootChipKey('903')), findsNothing);
    expect(find.text('The confirmed root cause was cleared.'), findsOneWidget);
  });

  testWidgets('moving a Why sends its new position, and the chain is renumbered around it',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // Why 3 moves up one place.
    await tapIn(tester, find.byKey(CapaDetailScreen.whyEarlierKey('903')));
    expect(wire.whyPatches, hasLength(1));
    expect(wire.whyPatches.single.$2, '903');
    expect(wire.whyPatches.single.$3, {'sequence': 2});

    // The chain reads 1, 2, 3 still — the position is a place in the chain, not
    // a number the Screen assembles.
    expect(find.text('Why it happened (3)'), findsOneWidget);
    expect(find.text('The torque step is not on the check sheet.'), findsOneWidget);
    expect(find.text('The chain was reordered.'), findsOneWidget);
  });

  testWidgets('a refused change stays in the dialog with the server own reason', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      addWhyStatus: 409,
      addWhyMessage: 'this CAPA is closed, so nothing about it can be changed',
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/whys/occurrence/new',
    );

    await tester.enterText(
      find.byKey(CapaWhyDialog.statementKey),
      'Nothing may be written here any more.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaWhyDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.whyPosts, hasLength(1));
    // The form is still there, with what was written and the reason. The
    // message is on screen twice — once in the dialog, once under the chains
    // behind it — which is the Screen keeping the refusal a reader can still
    // see after dismissing the form.
    expect(find.byKey(CapaWhyDialog.statementKey), findsOneWidget);
    expect(find.byKey(CapaWhyDialog.failureKey), findsOneWidget);
    expect(find.text('this CAPA is closed, so nothing about it can be changed'), findsWidgets);
  });

  testWidgets('each chain address refuses what the CAPA or the caller cannot answer',
      (tester) async {
    // Taller than the default surface, because #213's fishbone sits above the
    // chains and a shorter window leaves the read-only sentence below the fold
    // of the lazily-built list.
    _tallWindow(tester);
    // A caller with no edit access at the Org Unit and no place on the team:
    // the add address refuses rather than showing a form whose submit would be
    // refused.
    final stranger = _strangerWire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: stranger.client,
      initialLocation: '/actions/capas/801/whys/occurrence/new',
    );
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/whys/occurrence/new',
    );
    expect(find.byKey(CapaWhyKeys.refusedKey), findsOneWidget);
    expect(find.byKey(CapaWhyDialog.statementKey), findsNothing);
    expect(stranger.whyPosts, isEmpty);

    // And the refusal has a way out of its own: a `DialogPage` does not close
    // on a tap outside it, so the address would otherwise be a dead end.
    await tester.tap(find.byKey(CapaWhyKeys.dismissKey));
    await tester.pumpAndSettle();
    expect(locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)), '/actions/capas/801');
    expect(find.byKey(CapaDetailScreen.chainsReadOnlyKey), findsOneWidget);
  });

  testWidgets('a closed investigation refuses every chain address, and shows its chains as a record',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire(capa: _capa(status: 'closed'));

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/whys/occurrence/902/edit',
    );

    expect(find.byKey(CapaWhyKeys.closedKey), findsOneWidget);
    expect(find.byKey(CapaWhyEditDialog.statementKey), findsNothing);

    await tester.tap(find.byKey(CapaWhyKeys.dismissKey));
    await tester.pumpAndSettle();
    expect(locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)), '/actions/capas/801');

    // Behind the refusal the chains are still readable — reading a CAPA is
    // Site-wide — with no controls over them and a sentence saying why.
    expect(find.byKey(CapaDetailScreen.whyKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.chainsClosedKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.addWhyKey('occurrence')), findsNothing);
    expect(find.byKey(CapaDetailScreen.whyEditKey('901')), findsNothing);
    expect(wire.whyPatches, isEmpty);
  });

  testWidgets('an address naming a chain that is not one, or a Why that is not in the chain, is refused',
      (tester) async {
    final unknownChain = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: unknownChain.client,
      initialLocation: '/actions/capas/801/whys/detection/new',
    );
    expect(find.byKey(CapaWhyKeys.unknownChainKey), findsOneWidget);
    expect(find.byKey(CapaWhyDialog.statementKey), findsNothing);
    expect(unknownChain.whyPosts, isEmpty);
  });

  testWidgets('an edit address naming a Why of the other chain is refused', (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      // Why 904 is in the escape chain, and this address says occurrence: the
      // address is the whole request, so it is refused rather than quietly
      // editing a row the address does not name.
      initialLocation: '/actions/capas/801/whys/occurrence/904/edit',
    );

    expect(find.byKey(CapaWhyKeys.missingWhyKey), findsOneWidget);
    expect(find.byKey(CapaWhyEditDialog.statementKey), findsNothing);
    expect(wire.whyPatches, isEmpty);
  });
}
