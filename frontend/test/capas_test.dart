/// Opening a CAPA on a Concern and reading one (issue #209), with the wire
/// faked — the one client seam (ADR-0012). The real app, the real router, the
/// real Blocs, `MockClient` at the HTTP boundary and `FakeAuthGateway` at the
/// auth boundary.
///
/// What these tests claim and what they do not: that the Concern offers opening
/// a CAPA to a holder of Quality authority and to nobody else, that the form
/// collects the team and the problem description and sends exactly one request
/// carrying them, that the CAPA's own Screen renders the investigation and the
/// Concern's measures with their phases, and that a concern which already has
/// one names it instead of offering a second. Not that the server refuses a
/// caller without the authority, numbers the CAPA or keeps a Concern to one
/// investigation — that is proved in
/// `backend/test/integration/capas.test.js`, and neither substitutes for the
/// other (mirroring `actions_test.dart`'s own Testing Decisions).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/actions/capa_detail_screen.dart';
import 'package:lean_platform/actions/open_capa_dialog.dart';
import 'package:lean_platform/widgets/app_search_field.dart';

import 'harness.dart';

/// The team and the problem of the CAPA the fixture below describes, named once
/// so the widget and the wire cannot drift apart.
const String _capaNo = 'CA-HCM-2026-00001';

/// One measure as the Concern's own read sends it — an Action in its own right,
/// carrying the phases it has been round.
Map<String, dynamic> _measure(
  String id,
  String actionNo,
  String title,
  String actionType, {
  String openPhase = 'plan',
  List<Map<String, dynamic>> phases = const [],
}) =>
    actionJson(
      id,
      actionNo,
      title,
      actionType: actionType,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      parentId: '501',
      openPhase: phaseJson(1, openPhase),
      phases: phases,
    );

/// The Concern every test in this file starts from: raised on Line 1, with a
/// containment still on its Plan and a countermeasure whose Plan is done — what
/// ADR-0033's cycle looks like one step in.
Map<String, dynamic> _concern({Map<String, dynamic>? capa, List<Map<String, dynamic>>? measures}) =>
    actionJson(
      '501',
      'AC-HCM-2026-00001',
      'The guard keeps working loose',
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      description: 'Three occurrences this week.',
      capa: capa,
      measures: measures ??
          [
            _measure(
              '601',
              'AC-HCM-2026-00002',
              'Quarantined the batch',
              'containment',
              phases: [phaseJson(1, 'plan')],
            ),
            _measure(
              '602',
              'AC-HCM-2026-00003',
              'A captive fastener on the guard',
              'countermeasure',
              openPhase: 'do',
              phases: [
                phaseJson(1, 'plan',
                    completedAt: '2026-09-16T02:00:00.000Z',
                    note: 'Fitted and torqued to the standard.'),
                phaseJson(1, 'do'),
              ],
            ),
          ],
    )..['openPhase'] = phaseJson(1, 'plan');

/// One CAPA as its own address sends it, built from the Concern above so the
/// two fixtures describe the same investigation.
Map<String, dynamic> _capa({
  String? problemStatement = 'The guard comes loose after about 400 cycles.',
  Map<String, dynamic>? teamLead = const {'employeeId': '7', 'name': 'Ada Lead'},
  List<Map<String, dynamic>> teamMembers = const [
    {'employeeId': '8', 'name': 'Bo Member'},
  ],
  Map<String, dynamic>? concern,
}) =>
    capaJson(
      '801',
      _capaNo,
      'The guard keeps working loose',
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      problemStatement: problemStatement,
      teamLead: teamLead,
      teamMembers: teamMembers,
      concern: concern ??
          _concern(capa: {'id': '801', 'capaNo': _capaNo, 'status': 'open'}),
    );

/// The wire every test in this file starts from: one Site, one area with a line
/// beneath it, two Employees in the directory, and one Concern on the line with
/// a containment and a countermeasure answering it.
///
/// [quality] is what the caller's own Grant carries — the flag ADR-0035 puts
/// beside the level — and every test that asserts whether opening a CAPA is
/// offered turns on it. When it is false the caller still holds a write Grant
/// reaching the Concern's Org Unit, which is what raising a measure needs and
/// what makes the two independent.
FakeWire _wire({
  bool quality = false,
  Map<String, dynamic>? capa,
  Map<String, Map<String, dynamic>>? capas,
  int capasStatus = 200,
  String capaMessage = 'That CAPA could not be read.',
  int createCapaStatus = 201,
  String createCapaMessage = 'this Concern already has a CAPA',
}) {
  final concern = _concern(capa: capa);
  return FakeWire(
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('11', 'Line 1')],
    },
    employees: [
      employeeJson('7', 'E-7', 'Ada Lead'),
      employeeJson('8', 'E-8', 'Bo Member'),
    ],
    actions: {
      '1': [concern],
    },
    actionDetails: {'501': concern},
    orgUnitScope: {
      'everywhere': false,
      'grants': [scopeGrantJson('11', canWrite: true, qualityAuthority: quality)],
    },
    capas: capas ?? {},
    capasStatus: capasStatus,
    capaMessage: capaMessage,
    createCapaStatus: createCapaStatus,
    createCapaMessage: createCapaMessage,
  );
}

/// The Concern's detail read is a lazily-built `ListView`: the CAPA section sits
/// below the cycle and the facts, so at the default 800x600 surface it is not in
/// the tree at all and `find.byKey` would fail for a control that is really
/// there. Pinned taller for every test that reads the Concern.
void _tallWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the Concern offers no way to open a CAPA without Quality authority, and asks for nothing',
      (tester) async {
    _tallWindow(tester);

    // A caller with a write Grant reaching the Org Unit but no Quality
    // authority is offered no control at all (issue #48, ADR-0035) — and
    // nothing is asked of the API on their behalf.
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );
    expect(find.byKey(ActionDetailScreen.openCapaKey), findsNothing);
    expect(find.byKey(ActionDetailScreen.noCapaKey), findsOneWidget);
    expect(wire.capaPosts, isEmpty);
  });

  testWidgets('a holder of Quality authority is offered opening a CAPA, at its own address',
      (tester) async {
    _tallWindow(tester);

    final wire = _wire(quality: true);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );
    expect(find.byKey(ActionDetailScreen.openCapaKey), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.noCapaKey), findsNothing);

    await tapIn(tester, find.byKey(ActionDetailScreen.openCapaKey));
    expect(find.byKey(OpenCapaDialog.descriptionKey), findsOneWidget);
    // Opening the form is not opening a CAPA: nothing has been asked for yet.
    expect(wire.capaPosts, isEmpty);
  });

  testWidgets('the open address refuses a caller without Quality authority rather than rendering a form',
      (tester) async {
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501/capa',
    );

    // Reachable by address (ADR-0021) and it says why, rather than showing a
    // form whose submit would be refused.
    expect(find.byKey(OpenCapaDialog.refusedKey), findsOneWidget);
    expect(find.byKey(OpenCapaDialog.submitKey), findsNothing);
    expect(wire.capaPosts, isEmpty);
  });

  testWidgets('opening a CAPA collects the team and the problem, sends exactly one request, and lands on the CAPA',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire(quality: true)
      ..openedCapa = {'id': '801', 'capaNo': _capaNo};

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501/capa',
    );
    expect(find.byKey(OpenCapaDialog.descriptionKey), findsOneWidget);

    await tester.enterText(
      find.byKey(OpenCapaDialog.descriptionKey),
      'Two shifts running, on the same fixture.',
    );
    // The lead and a member, both chosen out of the Employee directory — a
    // value with a known set is chosen, never typed (ADR-0023).
    await pickSuggestion(
      tester,
      fieldKey: OpenCapaDialog.teamLeadKey,
      term: 'Ada',
      suggestionKey: AppSearchField.suggestionKey('open-capa-team-lead', '7'),
    );
    await pickSuggestion(
      tester,
      fieldKey: OpenCapaDialog.memberSearchKey(0),
      term: 'Bo',
      suggestionKey: AppSearchField.suggestionKey('open-capa-members-0', '8'),
    );
    expect(find.byKey(OpenCapaDialog.memberRowKey('8')), findsOneWidget);

    await tapIn(tester, find.byKey(OpenCapaDialog.submitKey));

    expect(wire.capaPosts, hasLength(1));
    final (concernId, body) = wire.capaPosts.single;
    expect(concernId, '501');
    expect(body['problemStatement'], 'Two shifts running, on the same fixture.');
    expect(body['teamLeadEmployeeId'], '7');
    expect(body['teamMemberEmployeeIds'], ['8']);

    // And the caller is taken to the investigation that was just opened, which
    // is the thing they will send to somebody else.
    expect(find.byKey(CapaDetailScreen.loadedKey), findsOneWidget);
    expect(find.text(_capaNo), findsWidgets);
  });

  testWidgets('a refused open stays in the form, with the server own reason', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      quality: true,
      createCapaStatus: 409,
      createCapaMessage: 'this Concern already has a CAPA',
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501/capa',
    );
    await tester.enterText(
      find.byKey(OpenCapaDialog.descriptionKey),
      'A second investigation nobody asked for.',
    );
    await tapIn(tester, find.byKey(OpenCapaDialog.submitKey));

    expect(wire.capaPosts, hasLength(1));
    // The form is still there, with the values and the reason.
    expect(find.byKey(OpenCapaDialog.descriptionKey), findsOneWidget);
    expect(find.byKey(OpenCapaDialog.failureKey), findsOneWidget);
    expect(find.text('this Concern already has a CAPA'), findsWidgets);
  });

  testWidgets('the CAPA detail shows its number, its team, the problem, and the Concern actions with their phases',
      (tester) async {
    _tallWindow(tester);
    final wire = _wire(capas: {'801': _capa()});

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.loadedKey), findsOneWidget);
    expect(find.text(_capaNo), findsWidgets);
    expect(find.text('The guard keeps working loose'), findsWidgets);
    // D1: the team, and which of them is the lead.
    expect(find.text('Ada Lead · team lead'), findsOneWidget);
    expect(find.text('Bo Member'), findsOneWidget);
    // D2: the problem description.
    expect(find.text('The guard comes loose after about 400 cycles.'), findsOneWidget);

    // D3-D7: the Concern's own actions, each an Action of its own with the
    // phase it is waiting on and the rounds it has been round.
    expect(find.byKey(CapaDetailScreen.measureKey('601')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.measureKey('602')), findsOneWidget);
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(CapaDetailScreen.measureKey('601')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join(' · '),
      contains('waiting on its plan'),
    );
    // The countermeasure's own cycle: a Plan that is done and the Do it is on.
    expect(find.byKey(CapaDetailScreen.measurePhaseKey('602', 1, 'plan')), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.measurePhaseKey('602', 1, 'do')), findsOneWidget);
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(CapaDetailScreen.measurePhaseKey('602', 1, 'plan')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join(' · '),
      contains('Fitted and torqued to the standard.'),
    );

    // And the Concern itself, so a reader can go back to the problem.
    expect(find.byKey(CapaDetailScreen.concernKey), findsOneWidget);
  });

  testWidgets('a CAPA that cannot be read says so and offers a retry', (tester) async {
    _tallWindow(tester);
    final wire = _wire(capasStatus: 404, capaMessage: 'CAPA not found');

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byKey(CapaDetailScreen.failedKey), findsOneWidget);
    expect(find.byKey(CapaDetailScreen.retryKey), findsOneWidget);
    expect(find.text('CAPA not found'), findsOneWidget);
  });

  testWidgets('a Concern that already has a CAPA names it, and offers no second', (tester) async {
    _tallWindow(tester);
    final wire = _wire(
      quality: true,
      capa: {'id': '801', 'capaNo': _capaNo, 'status': 'open'},
      capas: {'801': _capa()},
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    expect(find.byKey(ActionDetailScreen.capaLinkKey), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.openCapaKey), findsNothing);
    expect(find.text('Under investigation: $_capaNo'), findsOneWidget);

    // And the link goes to the investigation's own address.
    await tapIn(tester, find.byKey(ActionDetailScreen.capaLinkKey));
    expect(find.byKey(CapaDetailScreen.loadedKey), findsOneWidget);
    expect(wire.capaPosts, isEmpty);
  });
}
