/// Recording a CAPA's effectiveness check, and the CAPA list (issue #211), with
/// the wire faked — the one client seam (ADR-0012). The real app, the real
/// router, the real Blocs, `MockClient` at the HTTP boundary and
/// `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that the check is offered to a
/// holder of Quality authority who is not the team lead and to nobody else, that
/// the dialog is at its own address, sends exactly the verdict and the note the
/// form collected, and repaints the investigation behind it from the server's
/// own answer; that the list renders the investigations with their due dates and
/// marks the overdue checks, and that each filter sends the parameter it says.
/// Not that the server refuses the wrong caller, refuses an unclosed Concern or
/// refuses an effective verdict without a confirmed root cause in both chains —
/// that is proved in `backend/test/integration/capa-effectiveness.test.js`, and
/// neither substitutes for the other (mirroring `capas_test.dart`'s own Testing
/// Decisions).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/capa_detail_screen.dart';
import 'package:lean_platform/actions/capa_effectiveness_dialog.dart';
import 'package:lean_platform/actions/capa_org_unit_filter_dialog.dart';
import 'package:lean_platform/actions/capas_screen.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';

import 'harness.dart';

const String _capaNo = 'CA-HCM-2026-00001';

/// The Concern the CAPA was opened on, closed — which is the state the check
/// becomes due in, and the state every fixture here starts from.
Map<String, dynamic> _concern() => actionJson(
      '501',
      'AC-HCM-2026-00001',
      'The guard keeps working loose',
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      status: 'done',
    );

/// A CAPA waiting on its effectiveness check: both chains concluded, the Concern
/// closed, the date set — the state an investigation is in the day after its fix
/// went in.
Map<String, dynamic> _waiting({
  bool overdue = false,
  String? dueAt = '2026-10-16',
  int delayDays = 30,
}) =>
    capaJson(
      '801',
      _capaNo,
      'The guard keeps working loose',
      status: 'verifying',
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      problemStatement: 'The guard comes loose after about 400 cycles.',
      teamLead: const {'employeeId': '7', 'name': 'Ada Lead'},
      teamMembers: const [
        {'employeeId': '8', 'name': 'Bo Member'},
      ],
      whys: const [
        {'id': '901', 'chain': 'occurrence', 'sequence': 1, 'statement': 'The fastener was not torqued to the standard.', 'isRoot': true, 'createdAt': '2026-09-16T03:00:00.000Z', 'updatedAt': '2026-09-16T03:00:00.000Z'},
        {'id': '904', 'chain': 'escape', 'sequence': 1, 'statement': 'Nobody looks behind the machine between shifts.', 'isRoot': true, 'createdAt': '2026-09-16T03:00:00.000Z', 'updatedAt': '2026-09-16T03:00:00.000Z'},
      ],
      effectivenessCheckDelayDays: delayDays,
      effectivenessCheckDueAt: dueAt,
      effectivenessCheckOverdue: overdue,
      concern: _concern(),
    );

/// The wire every test in this file starts from: one Site, two lines, an
/// Employee directory, and one investigation waiting on its check.
///
/// [quality] and [selfEmployeeId] are the two halves of the rule that decides
/// who is offered the check — Quality authority at the CAPA's Org Unit, and not
/// the team lead's Account — so every test that asserts an offer or a refusal
/// turns on exactly one of them.
FakeWire _wire({
  bool write = true,
  bool quality = true,
  String? selfEmployeeId,
  Map<String, dynamic>? capa,
  Map<String, Map<String, dynamic>>? capas,
  int capaListStatus = 200,
  String capaListMessage = 'The CAPA list could not be read.',
  int effectivenessStatus = 200,
  String effectivenessMessage =
      "recording a CAPA's effectiveness check needs Quality authority at its Org Unit",
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('11', 'Line 1'), orgUnitJson('12', 'Line 2')],
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
      capas: capas ?? {'801': capa ?? _waiting()},
      capaListStatus: capaListStatus,
      capaListMessage: capaListMessage,
      effectivenessStatus: effectivenessStatus,
      effectivenessMessage: effectivenessMessage,
    );

/// A caller who holds nothing at all: no Grant anywhere and no Employee. The
/// investigation is readable (reading a CAPA is platform-wide) and the check is
/// not offered.
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
      capas: {'801': _waiting()},
    );

/// The effectiveness section is the *last* thing the CAPA's route list holds —
/// after the header, the team, the problem, both chains and the Concern's own
/// measures — and a lazily-built `ListView` has not built it at the default
/// 800x600 surface, so `find.byKey` would fail for a control that is really
/// there. Pinned tall for every test that reads or drives it.
void _tallWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2600);
  addTearDown(tester.view.reset);
}

/// The sentence a keyed `Text` renders — for a key that is on the `Text` itself,
/// where `find.descendant` cannot be used (a widget is not its own descendant).
String _sentence(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

/// Picks an option out of a `DropdownButtonFormField`, the way the status
/// filters' own tests do: the open menu renders the label a second time.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The list is a lazily-built `ListView` and a third investigation sits below
/// the fold at the default 800x600 surface — where `find.byKey` fails for a row
/// that is really there. Pinned for the tests that read more than two rows.
void _listWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.reset);
}

void main() {
  // -------------------------------------------------------------------------
  // Who is offered the check, and who is refused it
  // -------------------------------------------------------------------------

  testWidgets('the CAPA offers the check to a holder of Quality authority who is not the team lead',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.effectivenessKey), findsOneWidget);
    // The Concern has closed, so the date is on the record and the Screen says
    // it — which is the fact this whole Step turns on.
    expect(_sentence(tester, CapaDetailScreen.effectivenessDueKey), contains('due on 2026-10-16'));
    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsOneWidget);
    // Neither of the two sentences that say why somebody cannot record it.
    expect(find.byKey(CapaDetailScreen.effectivenessTeamLeadKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.effectivenessNotYoursKey), findsNothing);

    // Offering it asks for nothing: the form is a separate address.
    expect(wire.effectivenessPosts, isEmpty);
    expect(wire.whyPosts, isEmpty);
    expect(wire.whyPatches, isEmpty);
  });

  testWidgets('nothing is due while the Concern is open, and the Screen says which number decides that',
      (tester) async {
    _tallWindow(tester);
    // A CAPA whose check has not become due: the Concern has not closed, so
    // there is no date yet and nothing to record.
    final wire = _wire(capa: _waiting(dueAt: null, delayDays: 45)..['status'] = 'open');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(
      _sentence(tester, CapaDetailScreen.effectivenessNotYetKey),
      contains('45 days after the Concern closes'),
    );
    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsNothing);
    expect(wire.effectivenessPosts, isEmpty);
  });

  testWidgets('the team lead is not offered the check on their own investigation', (tester) async {
    _tallWindow(tester);
    // The lead's own Account, holding Quality authority at the CAPA's Org Unit:
    // the one caller whose verdict is not evidence.
    final wire = _wire(selfEmployeeId: '7');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    // The record is still there to read — every fact about the check is shown —
    // and the control is not, with a sentence saying why.
    expect(find.byKey(CapaDetailScreen.effectivenessDueKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.effectivenessTeamLeadKey), findsOneWidget);
    expect(wire.effectivenessPosts, isEmpty);
  });

  testWidgets('the check address refuses the team lead, and sends no request', (tester) async {
    _tallWindow(tester);
    final wire = _wire(selfEmployeeId: '7');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/effectiveness',
    );

    expect(find.byKey(CapaEffectivenessKeys.teamLeadKey), findsOneWidget);
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsNothing);
    expect(wire.effectivenessPosts, isEmpty);

    // And the refusal has a way out of its own: a `DialogPage` does not close
    // on a tap outside it, so the address would otherwise be a dead end.
    await tester.tap(find.byKey(CapaEffectivenessKeys.dismissKey));
    await tester.pumpAndSettle();
    expect(locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)), '/actions/capas/801');
    expect(find.byKey(CapaDetailScreen.effectivenessTeamLeadKey), findsOneWidget);
  });

  testWidgets('a caller without Quality authority is not offered the check', (tester) async {
    _tallWindow(tester);
    // Edit access at the Org Unit and no Quality authority: the supervisor who
    // works the line may write it and does not decide the fix held (ADR-0035).
    final wire = _wire(quality: false);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.effectivenessNotYoursKey), findsOneWidget);
    expect(wire.effectivenessPosts, isEmpty);
  });

  testWidgets('the check address refuses a caller without Quality authority', (tester) async {
    _tallWindow(tester);
    final wire = _strangerWire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/effectiveness',
    );

    expect(find.byKey(CapaEffectivenessKeys.refusedKey), findsOneWidget);
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsNothing);
    expect(wire.effectivenessPosts, isEmpty);
  });

  testWidgets('a closed investigation refuses the check address', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      capa: _waiting(dueAt: null)
        ..['status'] = 'closed'
        ..['effectivenessVerifiedAt'] = '2026-10-20T02:00:00.000Z'
        ..['effectivenessVerifiedBy'] = const {'accountId': '9', 'name': 'Pat Verifier'}
        ..['effectivenessNote'] = 'Ran 500 cycles and the guard held.',
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/effectiveness',
    );

    expect(find.byKey(CapaEffectivenessKeys.closedKey), findsOneWidget);
    expect(wire.effectivenessPosts, isEmpty);

    // Behind the refusal the record is what a reader of a closed investigation
    // came for: the verdict, who recorded it, and the note.
    await tester.tap(find.byKey(CapaEffectivenessKeys.dismissKey));
    await tester.pumpAndSettle();
    expect(find.byKey(CapaDetailScreen.effectivenessOutcomeKey), findsOneWidget);
    expect(find.text('The fix held'), findsWidgets);
    expect(
      _sentence(tester, CapaDetailScreen.effectivenessVerifiedByKey),
      contains('recorded by Pat Verifier'),
    );
    expect(find.text('Ran 500 cycles and the guard held.'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Recording the check
  // -------------------------------------------------------------------------

  testWidgets('recording a check that held closes the investigation, and the address is its own',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    await tapIn(tester, find.byKey(CapaDetailScreen.effectivenessCheckKey));

    // The address is the whole request: this is the investigation's own form.
    expect(
      locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)),
      '/actions/capas/801/effectiveness',
    );
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsOneWidget);
    // Opening the form is not recording anything, and the submit is closed
    // until the note says something — the same rule the server enforces with a
    // 400, said where the caller can see it.
    expect(wire.effectivenessPosts, isEmpty);
    expect(
      tester.widget<FilledButton>(find.byKey(CapaEffectivenessDialog.submitKey)).onPressed,
      isNull,
    );

    const note = 'Ran 500 cycles on the line and the guard held; the torque step is on the sheet.';
    await tester.enterText(find.byKey(CapaEffectivenessDialog.noteKey), note);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaEffectivenessDialog.submitKey));
    await tester.pumpAndSettle();

    // Exactly one request, carrying the verdict and the note and nothing else:
    // the verifier is the caller's own Account and the time is the server's.
    expect(wire.effectivenessPosts, hasLength(1));
    final (capaId, body) = wire.effectivenessPosts.single;
    expect(capaId, '801');
    expect(body, {'outcome': 'effective', 'note': note});

    // The form is gone and the Screen behind it carries what the server
    // answered: the investigation closed, with the verdict, the verifier and
    // the note.
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.effectivenessOutcomeKey), findsOneWidget);
    expect(find.text('The fix held'), findsWidgets);
    expect(find.text(note), findsOneWidget);
    expect(find.text('Closed'), findsWidgets);
    // The due date is gone from the "waiting" sentence: the check is answered.
    expect(find.byKey(CapaDetailScreen.effectivenessDueKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsNothing);
    expect(find.byKey(CapaDetailScreen.noticeKey), findsOneWidget);
    expect(
      find.text('The investigation is closed, and the fix is recorded as having held.'),
      findsOneWidget,
    );
  });

  testWidgets('a check that did not hold records it and says the Concern is open again', (tester) async {
    _tallWindow(tester);
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/effectiveness',
    );

    // A value with a known set is chosen, never typed (ADR-0023): the verdict
    // is the two values the schema has, labelled in the plant's words.
    await _choose(tester, CapaEffectivenessDialog.outcomeKey, 'The fix did not hold');

    const note = 'It came loose again after 300 cycles, on the second shift.';
    await tester.enterText(find.byKey(CapaEffectivenessDialog.noteKey), note);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaEffectivenessDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.effectivenessPosts, hasLength(1));
    expect(wire.effectivenessPosts.single.$2, {'outcome': 'not_effective', 'note': note});

    // The investigation is open, its check has no date any more, and the Screen
    // says what happened: the Concern is working its next cycle (ADR-0033).
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsNothing);
    expect(find.text('The fix did not hold'), findsWidgets);
    expect(find.text(note), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.effectivenessReopenedKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.effectivenessCheckKey), findsNothing);
    expect(
      find.text('The check did not hold, so the Concern is open again in its next cycle.'),
      findsOneWidget,
    );
  });

  testWidgets('a refused check stays in the form with the server own reason', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      effectivenessStatus: 409,
      effectivenessMessage: "this CAPA's Concern is not closed, so there is nothing to check yet",
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/effectiveness',
    );

    await tester.enterText(find.byKey(CapaEffectivenessDialog.noteKey), 'Good enough.');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CapaEffectivenessDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.effectivenessPosts, hasLength(1));
    // The form is still there, with what was written still in it, and the
    // reason beside it — a refusal a caller can act on rather than a dead end.
    expect(find.byKey(CapaEffectivenessDialog.noteKey), findsOneWidget);
    expect(find.byKey(CapaEffectivenessDialog.failureKey), findsOneWidget);
    expect(
      find.text("this CAPA's Concern is not closed, so there is nothing to check yet"),
      findsWidgets,
    );
    // ...and the Screen behind it carries the refusal too, so a reader who
    // dismissed the form can still see it.
    expect(find.byKey(CapaDetailScreen.failureKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The list
  // -------------------------------------------------------------------------

  testWidgets('the CAPA list shows the investigations and marks the ones whose check is overdue',
      (tester) async {
    _listWindow(tester);
    final wire = _wire(
      capas: {
        '801': _waiting(overdue: true, dueAt: '2026-09-28'),
        '802': capaJson('802', 'CA-HCM-2026-00002', 'The label is on the wrong side',
            status: 'verifying',
            orgUnitId: '12',
            orgUnitName: 'Line 2',
            siteId: '1',
            effectivenessCheckDueAt: '2026-10-16'),
        '803': capaJson('803', 'CA-HCM-2026-00003', 'The pallet count is short',
            status: 'closed',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            siteId: '1',
            effectivenessVerifiedAt: '2026-10-20T02:00:00.000Z',
            effectivenessVerifiedBy: const {'accountId': '9', 'name': 'Pat Verifier'},
            effectivenessNote: 'Counted the pallets twice.'),
      },
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    // The first read asks for everything: no Org Unit, no status, no overdue.
    expect(wire.capaListRequests.first, isEmpty);

    for (final id in ['801', '802', '803']) {
      expect(find.byKey(CapasScreen.rowKey(id)), findsOneWidget);
    }
    expect(find.text('CA-HCM-2026-00002'), findsOneWidget);
    expect(find.text('The label is on the wrong side'), findsOneWidget);

    // The mark this list exists to make, on the row that earned it and no
    // other.
    expect(find.byKey(CapasScreen.rowOverdueKey('801')), findsOneWidget);
    expect(find.byKey(CapasScreen.rowOverdueKey('802')), findsNothing);
    expect(find.byKey(CapasScreen.rowOverdueKey('803')), findsNothing);
    expect(find.text('Overdue check'), findsOneWidget);
    // These three keys are on the row's `Padding`s rather than on the `Text`s
    // themselves, so the sentence is looked for beneath them.
    expect(
      find.descendant(
        of: find.byKey(CapasScreen.rowDueKey('801')),
        matching: find.textContaining('was due on 2026-09-28'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(CapasScreen.rowDueKey('802')),
        matching: find.textContaining('is due on 2026-10-16'),
      ),
      findsOneWidget,
    );

    // A closed investigation shows the verdict and who recorded it, which is
    // what the report #212 renders reads back off this list (issue #211 returns
    // it; it does not build that Screen).
    expect(
      find.descendant(
        of: find.byKey(CapasScreen.rowVerifiedKey('803')),
        matching: find.textContaining('recorded by Pat Verifier'),
      ),
      findsOneWidget,
    );
    // And a row carries no way to record a check — the act is on the
    // investigation's own Screen, where the record and its gate are. Scoped to
    // the row rather than searched page-wide, because the Shell's own sidebar
    // carries an icon for every Destination.
    expect(
      find.descendant(
        of: find.byKey(CapasScreen.rowKey('801')),
        matching: find.byType(ButtonStyleButton),
      ),
      findsNothing,
    );
  });

  testWidgets('each filter on the CAPA list sends the parameter it says', (tester) async {
    final wire = _wire(
      capas: {
        '801': _waiting(overdue: true),
        '802': capaJson('802', 'CA-HCM-2026-00002', 'The label is on the wrong side',
            status: 'verifying', orgUnitId: '12', orgUnitName: 'Line 2', siteId: '1'),
      },
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    // The first read asks for everything: no Org Unit, no status, no overdue.
    expect(wire.capaListRequests.first, isEmpty);

    // By status: the value is carried in the address, not a client-side hide.
    await _choose(tester, CapasScreen.statusFilterKey, 'Closed');
    expect(wire.capaListRequests.last, {'status': 'closed'});

    // Then what is late, which cuts across the investigations' own states.
    await tapIn(tester, find.byKey(CapasScreen.overdueFilterKey));
    expect(wire.capaListRequests.last, {'status': 'closed', 'overdue': 'true'});

    // The two together match nothing, and the empty state says which story
    // this is rather than pretending the Platform has no investigations.
    expect(find.byKey(CapasScreen.emptyMatchedKey), findsOneWidget);

    // Clearing sends both away again.
    await tapIn(tester, find.byKey(CapasScreen.emptyClearFiltersKey));
    expect(wire.capaListRequests.last, isEmpty);
    expect(find.byKey(CapasScreen.rowKey('801')), findsOneWidget);

    // And the Org Unit filter, chosen by browsing the tree: the name the button
    // then shows is the Org Unit that was picked, and the request carries its
    // id — which is what narrows the list to that area *and everything beneath
    // it*, the server's own ltree walk.
    await tapIn(tester, find.byKey(CapasScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('11')));
    expect(wire.capaListRequests.last, {'orgUnitId': '11'});
    expect(find.text('Line 1'), findsWidgets);

    // Clearing it sends no orgUnitId at all, which is the whole list again.
    await tapIn(tester, find.byKey(CapasScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(CapaOrgUnitFilterDialog.allOrgUnitsKey));
    expect(wire.capaListRequests.last, isEmpty);
  });

  testWidgets('the CAPA list is readable by a caller with no Grant at all', (tester) async {
    final wire = _strangerWire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    // Reading is platform-wide, so the investigation is on the list — the same
    // asymmetry the CAPA's own read has (ADR-0009), and the same one the action
    // log and the Non-conformance register already have.
    expect(find.byKey(CapasScreen.rowKey('801')), findsOneWidget);
    expect(find.text('CA-HCM-2026-00001'), findsOneWidget);
  });

  testWidgets('a CAPA list with nothing on it says so, and offers no way to invent one', (tester) async {
    final wire = _wire(capas: const {});

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    expect(find.byKey(CapasScreen.emptyKey), findsOneWidget);
    // A CAPA is opened from a Concern (ADR-0034), so this Screen offers no
    // "new one" — the address that opens one is the Concern's own.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('CAPAs'), findsWidgets);
  });

  testWidgets('a CAPA list that cannot be read offers a retry, and a row opens the investigation',
      (tester) async {
    final wire = _wire(capaListStatus: 503, capaListMessage: 'The API is unavailable.');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    expect(find.byKey(CapasScreen.failedKey), findsOneWidget);
    expect(find.text('The API is unavailable.'), findsOneWidget);

    final readsBefore = wire.capaListRequests.length;
    await tapIn(tester, find.byKey(CapasScreen.retryKey));
    expect(wire.capaListRequests.length, greaterThan(readsBefore));
  });

  testWidgets('a row on the list opens the investigation, where the check is recorded',
      (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas',
    );

    await tapIn(tester, find.byKey(CapasScreen.rowKey('801')));
    expect(locationOf(tester, find.byKey(CapaDetailScreen.loadedKey)), '/actions/capas/801');
    // At the default window the effectiveness section is below the fold, which
    // is the list row's own job: it says when the check is due, and the act is
    // on the record.
    expect(find.text('The guard keeps working loose'), findsWidgets);
  });
}
