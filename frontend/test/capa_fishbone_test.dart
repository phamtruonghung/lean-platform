/// The fishbone on a CAPA (issue #213), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs, `MockClient`
/// at the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that the CAPA's detail Screen
/// shows the fishbone by 6M category with each cause's verdict and the evidence
/// behind it, that a writer — edit access at the CAPA's Org Unit, or a place on
/// its team — records a cause under one bone, revises it, decides it with the
/// evidence, removes it and starts a chain from the one the evidence confirmed,
/// that the requests those acts send carry exactly what they say, and that each
/// address refuses what the CAPA or the caller cannot answer. Not that the
/// server keeps the 6M set, requires the evidence for a verdict, refuses a
/// chain from an unconfirmed cause or refuses a caller without access — that is
/// proved in `backend/test/integration/capa-fishbone.test.js`, and neither
/// substitutes for the other (mirroring `capa_whys_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/capa_cause_dialog.dart';
import 'package:lean_platform/actions/capa_detail_screen.dart';

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

/// One CAPA part-way through its reasoning, which is the state the fishbone
/// exists for: three causes recorded, one of them confirmed by its evidence,
/// one ruled out with the evidence that settled it, one still a candidate — and
/// neither chain started yet, so the confirmed cause is exactly what a chain
/// can begin with.
Map<String, dynamic> _capa({
  String status = 'open',
  List<Map<String, dynamic>>? causes,
  List<Map<String, dynamic>> whys = const [],
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
      whys: whys,
      causes: causes ??
          [
            capaCauseJson('41', 'machine', 1, 'The retaining bolt is not torqued.',
                verdict: 'confirmed',
                evidenceNote: 'The torque log is missing that cycle.'),
            capaCauseJson('42', 'machine', 2, 'The fixture is worn.',
                verdict: 'ruled_out',
                evidenceNote: 'Both fixtures measure in tolerance.'),
            capaCauseJson('43', 'man', 1, 'The operator skipped the step.'),
          ],
      concern: _concern(),
    );

/// The wire every test in this file starts from: one Site, one line, an
/// Employee directory, and one CAPA whose fishbone is half reasoned.
///
/// [write] and [selfEmployeeId] are the two halves of the rule that decides who
/// is offered the fishbone controls — edit access at the CAPA's Org Unit, or a
/// place on its team — and every test that asserts a refusal or an offer turns
/// on exactly one of them.
FakeWire _wire({
  bool write = true,
  bool quality = true,
  String? selfEmployeeId,
  Map<String, dynamic>? capa,
  int addCauseStatus = 201,
  String addCauseMessage =
      "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team",
  int changeCauseStatus = 200,
  String changeCauseMessage = 'That cause could not be changed.',
  int removeCauseStatus = 200,
  String removeCauseMessage = 'That cause could not be removed.',
  int startWhyFromCauseStatus = 201,
  String startWhyFromCauseMessage =
      'only a confirmed cause can start a chain, and this one is candidate',
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
      addCauseStatus: addCauseStatus,
      addCauseMessage: addCauseMessage,
      changeCauseStatus: changeCauseStatus,
      changeCauseMessage: changeCauseMessage,
      removeCauseStatus: removeCauseStatus,
      removeCauseMessage: removeCauseMessage,
      startWhyFromCauseStatus: startWhyFromCauseStatus,
      startWhyFromCauseMessage: startWhyFromCauseMessage,
    );

/// A caller who holds nothing at all: no Grant anywhere, and — unless a test
/// links one — no Employee either. The CAPA's fishbone is readable (reading is
/// Site-wide) and, with no Employee on the team, not writable.
FakeWire _strangerWire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('11', 'Line 1')],
      },
      employees: [
        employeeJson('7', 'E-7', 'Ada Lead'),
        employeeJson('8', 'E-8', 'Bo Member'),
      ],
      orgUnitScope: {'everywhere': false, 'grants': const <dynamic>[]},
      capas: {'801': _capa()},
    );

/// The fishbone sits above the chains, but each cause row is a card with its
/// own message, evidence and controls and the Screen is a lazily-built
/// `ListView` — so at the default 800x600 surface the lower bones are not in
/// the widget tree at all and `find.byKey` fails for a row that is really
/// there. Pinned tall for every test that reads or drives the fishbone.
void _tallWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
}

/// Everything the widgets under [key] render, joined — the shape a keyed
/// container's own sentence or chip label is read by, since a key sits on the
/// container (`Padding`, `StatusChip`) and not always on the `Text` inside it.
String _textUnder(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

void main() {
  testWidgets('the CAPA detail shows the fishbone by 6M category, with every verdict and its evidence',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.fishboneKey), findsOneWidget);

    // All six bones are drawn, whether or not anything hangs from them: which
    // category nobody has considered is what a fishbone is read for.
    for (final category in const [
      'man',
      'machine',
      'method',
      'material',
      'measurement',
      'environment',
    ]) {
      expect(
        find.byKey(CapaDetailScreen.causeCategoryKey(category)),
        findsOneWidget,
        reason: 'the fishbone has no $category bone',
      );
    }
    expect(find.text('Machine (2)'), findsOneWidget);
    expect(find.text('Man (1)'), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeCategoryEmptyKey('method')), findsOneWidget);
    expect(
      _textUnder(tester, CapaDetailScreen.causeCategoryEmptyKey('method')),
      'Nothing is recorded under Method.',
    );

    // Each cause in its bone, in the order it was recorded, with its verdict
    // and the evidence the verdict rests on.
    expect(find.byKey(CapaDetailScreen.causeKey('41')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeKey('42')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeKey('43')), findsOneWidget);
    expect(find.text('The retaining bolt is not torqued.'), findsOneWidget);
    expect(find.text('Evidence: The torque log is missing that cycle.'), findsOneWidget);
    expect(find.text('Evidence: Both fixtures measure in tolerance.'), findsOneWidget);
    expect(_textUnder(tester, CapaDetailScreen.causeVerdictKey('41')), 'Confirmed');
    expect(_textUnder(tester, CapaDetailScreen.causeVerdictKey('42')), 'Ruled out');
    expect(_textUnder(tester, CapaDetailScreen.causeVerdictKey('43')), 'Candidate');
    // A cause nobody has decided has no evidence line at all.
    expect(find.byKey(CapaDetailScreen.causeEvidenceKey('43')), findsNothing);

    // Reading the fishbone asks for nothing.
    expect(wire.causePosts, isEmpty);
    expect(wire.causePatches, isEmpty);
    expect(wire.causeDeletions, isEmpty);
    expect(wire.causeWhyPosts, isEmpty);
  });

  testWidgets('only a confirmed cause whose chain is open offers to start one', (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // The confirmed cause offers it — both chains are still empty — and neither
    // the ruled-out one nor the candidate does: the server would refuse both.
    expect(find.byKey(CapaDetailScreen.causeStartWhyKey('41')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeStartWhyKey('42')), findsNothing);
    expect(find.byKey(CapaDetailScreen.causeStartWhyKey('43')), findsNothing);
  });

  testWidgets('a cause whose every chain has started offers nothing: a chain begins once',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      capa: _capa(whys: [
        capaWhyJson('901', 1, 'The retaining bolt is not torqued.'),
        capaWhyJson('902', 1, 'Nobody looks behind the machine between shifts.',
            chain: 'escape'),
      ]),
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // Both chains have their first Why, so no cause may begin one: the server
    // would refuse the request, and the Screen does not offer it.
    expect(find.byKey(CapaDetailScreen.whyKey('901')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeVerdictKey('41')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeStartWhyKey('41')), findsNothing);
  });

  testWidgets('recording a cause sends it under the bone the address named', (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.addCauseKey('method')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/causes/method/new',
    );

    // The submit gate is the API's own rule: a cause has to say something.
    expect(
      tester.widget<FilledButton>(find.byKey(CapaCauseDialog.submitKey)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(CapaCauseDialog.statementKey),
      'The check sheet has no torque step on it.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePosts, hasLength(1));
    final (capaId, body) = wire.causePosts.single;
    expect(capaId, '801');
    // One category and what it says, and nothing else: the position is the
    // server's to compute and the verdict is always `candidate` on a new cause.
    expect(body, {
      'category': 'method',
      'statement': 'The check sheet has no torque step on it.',
    });

    // The form closed, the cause is on its bone as a candidate, and the Screen
    // says what happened.
    expect(find.byKey(CapaCauseDialog.statementKey), findsNothing);
    expect(find.text('Method (1)'), findsOneWidget);
    expect(find.text('The check sheet has no torque step on it.'), findsOneWidget);
    expect(find.text('The candidate cause is on the fishbone.'), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeCategoryEmptyKey('method')), findsNothing);
  });

  testWidgets('deciding a cause sends the verdict with its evidence, and the button stays closed without one',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // The candidate on the Man bone is decided as confirmed.
    await tapIn(tester, find.byKey(CapaDetailScreen.causeDecideKey('43')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/causes/man/43/verdict',
    );

    // `confirmed` is offered first, and the evidence is required: the API
    // refuses a verdict without it, so the button does not open until it is
    // there.
    expect(
      tester.widget<FilledButton>(find.byKey(CapaCauseVerdictDialog.submitKey)).onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(CapaCauseVerdictDialog.evidenceKey),
      'The torque log is signed off for every cycle that shift.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseVerdictDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePatches, hasLength(1));
    final (capaId, causeId, body) = wire.causePatches.single;
    expect(capaId, '801');
    expect(causeId, '43');
    expect(body, {
      'verdict': 'confirmed',
      'evidenceNote': 'The torque log is signed off for every cycle that shift.',
    });
    expect(find.text('That cause is confirmed by its evidence.'), findsOneWidget);
    expect(
      find.text('Evidence: The torque log is signed off for every cycle that shift.'),
      findsOneWidget,
    );

    // Ruling a cause out is the same form, and the decision is what is sent.
    await tapIn(tester, find.byKey(CapaDetailScreen.causeDecideKey('42')));
    await tester.tap(find.byKey(CapaCauseVerdictDialog.verdictKey('ruled_out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseVerdictDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePatches, hasLength(2));
    expect(wire.causePatches.last.$2, '42');
    expect(wire.causePatches.last.$3, {
      'verdict': 'ruled_out',
      // The evidence the cause already carried travels with the new verdict: a
      // decision keeps the note it was made with.
      'evidenceNote': 'Both fixtures measure in tolerance.',
    });
    expect(find.text('That cause is ruled out by its evidence.'), findsOneWidget);
  });

  testWidgets('revising a cause sends one field, and moving it re-files it under another bone',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.causeEditKey('43')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/causes/man/43/edit',
    );
    // The form is filled with what the cause says now: a revision starts from
    // the row, not from a blank field.
    expect(
      tester.widget<TextField>(find.byKey(CapaCauseEditDialog.statementKey)).controller?.text,
      'The operator skipped the step.',
    );

    await tester.enterText(
      find.byKey(CapaCauseEditDialog.statementKey),
      'The operator was never shown the torque step.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseEditDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePatches, hasLength(1));
    // One field, and only the one: a revision does not restate the category.
    expect(wire.causePatches.single.$3, {
      'statement': 'The operator was never shown the torque step.',
    });
    expect(find.text('The operator was never shown the torque step.'), findsOneWidget);
    expect(find.text('The cause was revised.'), findsOneWidget);

    // The same form re-files it: the team argues about whether it is Man or
    // Method, and the address says where it is now while the form says where it
    // should be.
    await tapIn(tester, find.byKey(CapaDetailScreen.causeEditKey('43')));
    await tester.tap(find.byKey(CapaCauseEditDialog.categoryKey('method')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseEditDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePatches, hasLength(2));
    expect(wire.causePatches.last.$3, {
      'category': 'method',
      'statement': 'The operator was never shown the torque step.',
    });
    expect(find.text('The cause was re-filed under another category.'), findsOneWidget);
    expect(find.text('Method (1)'), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeCategoryEmptyKey('man')), findsOneWidget);
  });

  testWidgets('starting a chain from a confirmed cause sends the chain and the first Why',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.causeStartWhyKey('41')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/causes/machine/41/why',
    );

    // The field starts at the cause's own sentence: a chain started from a
    // confirmed cause begins with it, unless the team phrases it differently.
    expect(
      tester
          .widget<TextField>(find.byKey(CapaWhyFromCauseDialog.statementKey))
          .controller
          ?.text,
      'The retaining bolt is not torqued.',
    );

    await tester.tap(find.byKey(CapaWhyFromCauseDialog.chainKey('occurrence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaWhyFromCauseDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causeWhyPosts, hasLength(1));
    final (capaId, causeId, body) = wire.causeWhyPosts.single;
    expect(capaId, '801');
    expect(causeId, '41');
    expect(body, {
      'chain': 'occurrence',
      'statement': 'The retaining bolt is not torqued.',
    });

    // The chain behind the dialog now has its first Why, and the fishbone is
    // still there beside it with its verdict. The notice above the sections is
    // deliberately not asserted here: the tap that opened the form scrolled the
    // list (the cause rows sit below the notice), so a lazily-built `ListView`
    // has culled it — what the tap left visible is asserted instead.
    expect(find.byKey(CapaWhyFromCauseDialog.statementKey), findsNothing);
    expect(find.text('Why it happened (1)'), findsOneWidget);
    expect(find.text('The retaining bolt is not torqued.'), findsWidgets);
    expect(find.byKey(CapaDetailScreen.causeVerdictKey('41')), findsOneWidget);
  });

  testWidgets('removing a cause asks first, then deletes it alone', (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.causeRemoveKey('43')));
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/causes/man/43/remove',
    );
    // The confirmation shows what is about to go, and cancelling sends nothing.
    expect(find.text('The operator skipped the step.'), findsWidgets);
    await tester.tap(find.byKey(CapaCauseRemoveDialog.cancelKey));
    await tester.pumpAndSettle();
    expect(wire.causeDeletions, isEmpty);
    expect(find.byKey(CapaDetailScreen.causeKey('43')), findsOneWidget);

    await tapIn(tester, find.byKey(CapaDetailScreen.causeRemoveKey('43')));
    await tester.tap(find.byKey(CapaCauseRemoveDialog.confirmKey));
    await tester.pumpAndSettle();

    expect(wire.causeDeletions, hasLength(1));
    expect(wire.causeDeletions.single, ('801', '43'));
    expect(find.byKey(CapaDetailScreen.causeKey('43')), findsNothing);
    expect(find.byKey(CapaDetailScreen.causeCategoryEmptyKey('man')), findsOneWidget);
    expect(find.text('The cause was removed from the fishbone.'), findsOneWidget);
    // The causes on the other bones are untouched.
    expect(find.byKey(CapaDetailScreen.causeKey('41')), findsOneWidget);
  });

  testWidgets('each fishbone address refuses what the CAPA or the caller cannot answer',
      (tester) async {
    // A caller with no edit access at the Org Unit and no place on the team:
    // the add address refuses rather than showing a form whose submit would be
    // refused.
    final stranger = _strangerWire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: stranger.client,
      initialLocation: '/actions/capas/801/causes/machine/new',
    );
    expect(find.byKey(CapaCauseKeys.refusedKey), findsOneWidget);
    expect(find.byKey(CapaCauseDialog.statementKey), findsNothing);
    expect(stranger.causePosts, isEmpty);

    // And the refusal has a way out of its own: a `DialogPage` does not close
    // on a tap outside it, so the address would otherwise be a dead end.
    await tester.tap(find.byKey(CapaCauseKeys.dismissKey));
    await tester.pumpAndSettle();
    expect(locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)), '/actions/capas/801');
    expect(find.byKey(CapaDetailScreen.fishboneReadOnlyKey), findsOneWidget);
  });

  testWidgets('an address naming a category that is not one of the six is refused',
      (tester) async {
    _tallWindow(tester);

    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/people/new',
    );

    expect(find.byKey(CapaCauseKeys.unknownCategoryKey), findsOneWidget);
    expect(find.byKey(CapaCauseDialog.statementKey), findsNothing);
    expect(wire.causePosts, isEmpty);
  });

  testWidgets('an address naming a cause that is not on the bone it names is refused',
      (tester) async {
    _tallWindow(tester);

    // A real cause, on another bone — the case a stale link produces.
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/method/41/edit',
    );

    expect(find.byKey(CapaCauseKeys.missingCauseKey), findsOneWidget);
    expect(find.byKey(CapaCauseEditDialog.statementKey), findsNothing);
    expect(wire.causePatches, isEmpty);
  });

  testWidgets('a closed investigation refuses every fishbone address, and shows its fishbone as a record',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire(capa: _capa(status: 'closed'));

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/machine/41/verdict',
    );
    expect(find.byKey(CapaCauseKeys.closedKey), findsOneWidget);
    expect(find.byKey(CapaCauseVerdictDialog.evidenceKey), findsNothing);

    await tester.tap(find.byKey(CapaCauseKeys.dismissKey));
    await tester.pumpAndSettle();

    // The fishbone itself is still read — a closed investigation is a record,
    // and its verdicts are what an auditor came for. No control is offered.
    expect(find.byKey(CapaDetailScreen.fishboneClosedKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.causeVerdictKey('41')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.addCauseKey('machine')), findsNothing);
    expect(find.byKey(CapaDetailScreen.causeDecideKey('41')), findsNothing);
    expect(find.byKey(CapaDetailScreen.causeRemoveKey('41')), findsNothing);
  });

  testWidgets('a refused change stays in the dialog with the server own reason', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      changeCauseStatus: 400,
      changeCauseMessage:
          'a cause cannot be confirmed without the evidence: send an evidenceNote saying what it was',
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/man/43/verdict',
    );

    await tester.enterText(
      find.byKey(CapaCauseVerdictDialog.evidenceKey),
      'Some evidence, which the server did not want.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaCauseVerdictDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causePatches, hasLength(1));
    // The form is still there, with what was written and the reason. The
    // message is on screen twice — once in the dialog, once under the fishbone
    // behind it — which is the Screen keeping the refusal a reader can still
    // see after dismissing the form.
    expect(find.byKey(CapaCauseVerdictDialog.evidenceKey), findsOneWidget);
    expect(find.byKey(CapaCauseVerdictDialog.failureKey), findsOneWidget);
    expect(
      find.textContaining('a cause cannot be confirmed without the evidence'),
      findsWidgets,
    );
  });

  testWidgets('a start-a-chain address whose chains have all started says so rather than offering nothing',
      (tester) async {
    _tallWindow(tester);
    // Both chains under way: there is no head for a newly confirmed cause to
    // begin, and the honest answer is the sentence rather than a form with
    // nothing to choose.
    final wire = _wire(
      capa: _capa(
        whys: [
          capaWhyJson('901', 1, 'The retaining bolt is not torqued.'),
          capaWhyJson('902', 1, 'Nobody looks behind the machine between shifts.',
              chain: 'escape'),
        ],
      ),
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/machine/41/why',
    );

    expect(find.byKey(CapaWhyFromCauseDialog.noChainKey), findsOneWidget);
    expect(find.byKey(CapaWhyFromCauseDialog.statementKey), findsNothing);
    expect(wire.causeWhyPosts, isEmpty);
  });

  testWidgets('a refusal the server sends for a chain start is reported in the form', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      startWhyFromCauseStatus: 409,
      startWhyFromCauseMessage:
          'only a confirmed cause can start a chain, and this one is ruled_out',
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/causes/machine/41/why',
    );

    await tester.tap(find.byKey(CapaWhyFromCauseDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.causeWhyPosts, hasLength(1));
    expect(find.byKey(CapaWhyFromCauseDialog.failureKey), findsOneWidget);
    expect(find.textContaining('only a confirmed cause can start a chain'), findsWidgets);
  });
}
