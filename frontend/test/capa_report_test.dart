/// The CAPA report Screen (issue #212), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs, `MockClient`
/// at the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not. They claim that the report
/// renders every 8D section from the one read the CAPA's own address answers,
/// in the order an 8D asks for them; that an investigation nobody has finished
/// reads with each unfinished part marked rather than blank; that the report is
/// reached at its own address **without the Shell's navigation** (which is what
/// makes the browser's own print produce the report rather than the chrome
/// around it) and survives signing in when somebody shares the link; that it is
/// offered to any Account that may read the CAPA at all; and that the read it
/// makes is one request for the record the address names. They do not claim
/// that the server refuses anyone, numbers anything, or sends the Dispositions
/// the report prints — that is proved in
/// `backend/test/integration/capa-report.test.js`, and neither substitutes for
/// the other.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/actions/capa_detail_screen.dart';
import 'package:lean_platform/actions/capa_report_screen.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart';

/// The investigation the fixtures below describe, named once so the assertions
/// and the wire cannot drift apart.
const String _capaNo = 'CA-HCM-2026-00001';
const String _capaTitle = 'The guard keeps working loose';
const String _problem = 'The guard comes loose after about 400 cycles.';
const String _occurrenceRoot = 'The fastener was not torqued to the standard.';
const String _escapeRoot = 'Nobody looks behind the machine between shifts.';
const String _effectivenessNote = 'Ran 500 cycles on the line and the guard held.';

/// One measure as the Concern's own read sends it — an Action in its own right,
/// carrying every phase it has been round.
Map<String, dynamic> _measure(
  String id,
  String actionNo,
  String title,
  String actionType, {
  String status = 'done',
  String openPhase = 'act',
  List<Map<String, dynamic>> phases = const [],
}) =>
    actionJson(
      id,
      actionNo,
      title,
      actionType: actionType,
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      parentId: '501',
      ownerName: 'Ann Fitter',
      openPhase: phaseJson(1, openPhase),
      phases: phases,
    );

/// The four phases of one completed cycle, with the Check's own outcome — what
/// D5-D7 read for "what happened, and did it hold".
List<Map<String, dynamic>> _walkedCycle({String outcome = 'effective', String? note}) => [
      phaseJson(1, 'plan', completedAt: '2026-09-16T02:00:00.000Z', note: 'Planned.'),
      phaseJson(1, 'do', completedAt: '2026-09-17T02:00:00.000Z', note: 'Done.'),
      phaseJson(1, 'check',
          completedAt: '2026-09-18T02:00:00.000Z',
          outcome: outcome,
          note: note ?? 'It held on the line.'),
      phaseJson(1, 'act', completedAt: '2026-09-19T02:00:00.000Z', note: 'Acted.'),
    ];

/// The occurrence the Concern answers, with two Dispositions on it — a scrap and
/// the Concession an auditor always asks about. [dispositions] overrides them,
/// because "nothing has been decided about this product yet" is a state the
/// report has to render too.
Map<String, dynamic> _occurrence({List<Map<String, dynamic>>? dispositions}) =>
    linkedNonconformanceJson(
      nonconformanceJson(
        '901',
        'NC-HCM-2026-00001',
        status: 'closed',
        quantityAffected: 20,
        quantityDispositioned: 20,
        productCode: 'PRD-1',
        productName: 'Gearbox',
        defectCodeCode: 'DIM-OOT',
        defectCodeName: 'Out of tolerance',
        immediateContainment: 'Tagged and quarantined at the line.',
        dispositions: dispositions ??
            [
              dispositionJson('1',
                  quantity: 12,
                  decidedByAccountName: 'Ann Operator',
                  decidedAt: '2026-09-15T03:00:00.000Z',
                  note: 'Cut up and back to the furnace.'),
              dispositionJson('2',
                  dispositionType: 'use_as_is',
                  quantity: 8,
                  reference: 'DEV-2026-0014',
                  decidedByAccountName: 'Pat Quality',
                  decidedAt: '2026-09-16T03:00:00.000Z'),
            ],
      ),
    );

/// The Concern the CAPA answers: its measures are the CAPA's own D3 and D5-D7
/// (ADR-0034), and the occurrence above is its evidence.
Map<String, dynamic> _concern({
  List<Map<String, dynamic>>? measures,
  List<Map<String, dynamic>>? nonconformances,
}) =>
    actionJson(
      '501',
      'AC-HCM-2026-00001',
      _capaTitle,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      description: 'Three occurrences this week.',
      status: 'done',
      capa: {'id': '801', 'capaNo': _capaNo, 'status': 'closed'},
      measures: measures ??
          [
            _measure('601', 'AC-HCM-2026-00002', 'Quarantined the batch', 'containment',
                phases: _walkedCycle()),
            _measure('602', 'AC-HCM-2026-00003', 'A captive fastener on the guard',
                'countermeasure',
                phases: _walkedCycle()),
            _measure('603', 'AC-HCM-2026-00004', 'Add the torque step to the shift handover',
                'preventive',
                phases: _walkedCycle(
                    outcome: 'not_effective', note: 'The first wording was ignored.')),
          ],
      nonconformances: nonconformances ?? [_occurrence()],
    );

/// One CAPA as its own address sends it. The default is the closed, finished
/// investigation; the open one below differs only in what the record holds,
/// which is the point of a report that renders one read twice.
Map<String, dynamic> _capa({
  String status = 'closed',
  String? problemStatement = _problem,
  Map<String, dynamic>? teamLead = const {'employeeId': '7', 'name': 'Ada Lead'},
  List<Map<String, dynamic>> teamMembers = const [
    {'employeeId': '8', 'name': 'Bo Member'},
  ],
  List<Map<String, dynamic>>? whys,
  List<Map<String, dynamic>>? causes,
  String? effectivenessVerifiedAt = '2026-09-30T02:00:00.000Z',
  Map<String, dynamic>? effectivenessVerifiedBy = const {
    'accountId': '3',
    'name': 'Pat Verifier',
  },
  String? effectivenessNote = _effectivenessNote,
  String? effectivenessCheckDueAt,
  bool effectivenessCheckOverdue = false,
  Map<String, dynamic>? concern,
}) =>
    capaJson(
      '801',
      _capaNo,
      _capaTitle,
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      problemStatement: problemStatement,
      teamLead: teamLead,
      teamMembers: teamMembers,
      whys: whys ??
          [
            capaWhyJson('1', 1, 'The vibration loosened it.'),
            capaWhyJson('2', 2, _occurrenceRoot, isRoot: true),
            capaWhyJson('3', 1, _escapeRoot, chain: 'escape', isRoot: true),
          ],
      // The fishbone (issue #213): the causes the team considered before it
      // decided, one of them confirmed by its evidence and one ruled out — the
      // state a finished 8D's D4 is read for.
      causes: causes ??
          [
            capaCauseJson('41', 'machine', 1, 'The retaining bolt is not torqued.',
                verdict: 'confirmed', evidenceNote: 'The torque log is missing that cycle.'),
            capaCauseJson('42', 'machine', 2, 'The fixture is worn.',
                verdict: 'ruled_out', evidenceNote: 'Both fixtures measure in tolerance.'),
            capaCauseJson('43', 'man', 1, 'The operator skipped the step.'),
          ],
      effectivenessVerifiedAt: effectivenessVerifiedAt,
      effectivenessVerifiedBy: effectivenessVerifiedBy,
      effectivenessNote: effectivenessNote,
      effectivenessCheckDueAt: effectivenessCheckDueAt,
      effectivenessCheckOverdue: effectivenessCheckOverdue,
      concern: concern ?? _concern(),
    );

/// A CAPA nobody has got anywhere with: no team, no problem description, no
/// chain started, nothing recorded on the Concern, nothing decided about the
/// product and no check. Every section of the report has to say so rather than
/// render blank — the open-CAPA half of the ticket.
Map<String, dynamic> _openCapa() => _capa(
      status: 'open',
      problemStatement: null,
      teamLead: null,
      teamMembers: const [],
      whys: const [],
      // No fishbone either: a report that has not been reasoned on says so in
      // one sentence rather than printing six empty bones (issue #213).
      causes: const [],
      effectivenessVerifiedAt: null,
      effectivenessVerifiedBy: null,
      effectivenessNote: null,
      concern: _concern(measures: const [], nonconformances: const []),
    );

/// The wire every test starts from: one Site, one line, two Employees in the
/// directory, one CAPA at its own address, and the Account's own scope.
///
/// [scope] is what the caller holds (ADR-0027): the default is the operator
/// with a Grant on the line, and the "any Account" test passes the empty scope
/// an approved Account with no Grants at all really has — which must not change
/// what the report shows, because reading a CAPA is a platform-wide read.
FakeWire _wire({
  Map<String, dynamic>? capa,
  Map<String, Map<String, dynamic>>? capas,
  Map<String, dynamic>? scope,
  int capasStatus = 200,
  String capaMessage = 'That CAPA could not be read.',
  String role = 'operator',
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
      orgUnitScope: scope ??
          {
            'everywhere': false,
            'grants': [scopeGrantJson('11', canWrite: true)],
          },
      role: role,
      capas: capas ?? {'801': capa ?? _capa()},
      capasStatus: capasStatus,
      capaMessage: capaMessage,
    );

/// Every section of the report, in the order an 8D reads them — the order each
/// test below asserts rather than trusting the widget list to stay sorted.
const List<ValueKey<String>> _sectionOrder = [
  CapaReportScreen.teamKey,
  CapaReportScreen.problemKey,
  CapaReportScreen.containmentKey,
  CapaReportScreen.rootCauseKey,
  CapaReportScreen.countermeasuresKey,
  CapaReportScreen.preventiveKey,
  CapaReportScreen.effectivenessKey,
  CapaReportScreen.nonconformancesKey,
];

/// Everything the widgets under [key] render, joined — a section is a `Column`
/// of `Text`s, so reading them one at a time would be reading the layout rather
/// than the report. The key has to sit on a container: a `Text` is its own
/// descendant-free subtree, which is what [_textOf] is for.
String _textUnder(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

/// The text a keyed `Text` itself renders — the shape the report's own "not
/// yet" sentences take, each carrying its own key.
String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

void main() {
  testWidgets('the report lays a finished investigation out in 8D order, section by section',
      (tester) async {
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byKey(CapaReportScreen.loadedKey), findsOneWidget);
    expect(find.text(_capaNo), findsOneWidget);
    expect(find.text(_capaTitle), findsOneWidget);

    // Every section rendered, and in the order an 8D asks for. Each is measured
    // rather than assumed: a section moved below another one fails here.
    var previous = double.negativeInfinity;
    for (final section in _sectionOrder) {
      expect(find.byKey(section), findsOneWidget, reason: 'the report has no $section');
      final top = tester.getTopLeft(find.byKey(section)).dy;
      expect(top, greaterThan(previous), reason: '$section is out of 8D order');
      previous = top;
    }

    // D1 — the team, the lead as a role and the member beside them.
    expect(_textUnder(tester, CapaReportScreen.teamKey), contains('Ada Lead · team lead'));
    expect(_textUnder(tester, CapaReportScreen.teamKey), contains('Bo Member'));

    // D2 — the problem description.
    expect(_textUnder(tester, CapaReportScreen.problemKey), contains(_problem));

    // D3 — the containment, with the phase of its cycle it is at.
    expect(_textUnder(tester, CapaReportScreen.containmentKey),
        contains('Quarantined the batch'));
    expect(_textUnder(tester, CapaReportScreen.containmentKey), contains('Cycle 1 · Plan'));

    // D4 — the fishbone the team reasoned on, then both chains in the order they
    // are reasoned, each with its steps and where it stopped.
    final rootCause = _textUnder(tester, CapaReportScreen.rootCauseKey);
    expect(rootCause, contains('The candidate causes considered'));
    expect(rootCause, contains('Machine'));
    expect(rootCause, contains('The retaining bolt is not torqued.'));
    expect(rootCause, contains('Confirmed'));
    expect(rootCause, contains('Evidence: The torque log is missing that cycle.'));
    expect(rootCause, contains('The fixture is worn.'));
    expect(rootCause, contains('Ruled out'));
    expect(rootCause, contains('Evidence: Both fixtures measure in tolerance.'));
    expect(rootCause, contains('Man'));
    expect(rootCause, contains('The operator skipped the step.'));
    expect(rootCause, contains('Candidate'));
    // The bones read in the 6M's own order — Man first, then Machine — and the
    // fishbone reads above the chains it begins: a reader meets what the team
    // suspected before what it concluded.
    expect(rootCause.indexOf('Man'), lessThan(rootCause.indexOf('Machine')));
    expect(
      rootCause.indexOf('The candidate causes considered'),
      lessThan(rootCause.indexOf('Why it happened')),
    );
    // A cause nobody has decided carries no evidence sentence at all: the note
    // and the verdict travel together.
    expect(
      _textUnder(tester, CapaReportScreen.causeKey('43')),
      isNot(contains('Evidence:')),
    );
    expect(rootCause, contains('Why it happened'));
    expect(rootCause, contains('Why 1 · The vibration loosened it.'));
    expect(rootCause, contains('Why 2 · $_occurrenceRoot'));
    expect(rootCause, contains('Confirmed root cause: $_occurrenceRoot'));
    expect(rootCause, contains('Why it was not detected'));
    expect(rootCause, contains('Confirmed root cause: $_escapeRoot'));
    expect(
      rootCause.indexOf('Why it happened'),
      lessThan(rootCause.indexOf('Why it was not detected')),
      reason: 'the report reads the escape chain before the occurrence one',
    );

    // D5-D6 and D7 — the countermeasures and the preventive actions, with the
    // Check's own outcome on each (ADR-0033: the round that failed is kept).
    final countermeasures = _textUnder(tester, CapaReportScreen.countermeasuresKey);
    expect(countermeasures, contains('A captive fastener on the guard'));
    expect(countermeasures, contains('Cycle 1 · Check · done · It held'));
    final preventive = _textUnder(tester, CapaReportScreen.preventiveKey);
    expect(preventive, contains('Add the torque step to the shift handover'));
    expect(preventive, contains('Cycle 1 · Check · done · It did not hold'));
    expect(preventive, contains('The first wording was ignored.'));

    // D8 — the effectiveness check, with its verifier, its date and its note.
    final effectiveness = _textUnder(tester, CapaReportScreen.effectivenessKey);
    expect(effectiveness, contains('The fix held'));
    expect(effectiveness, contains('verified by Pat Verifier on 2026-09-30'));
    expect(effectiveness, contains(_effectivenessNote));

    // The evidence — the occurrence with its number, Product, Defect code,
    // quantity and Dispositions.
    final evidence = _textUnder(tester, CapaReportScreen.nonconformancesKey);
    expect(evidence, contains('NC-HCM-2026-00001'));
    expect(evidence, contains('Gearbox · PRD-1'));
    expect(evidence, contains('Out of tolerance · DIM-OOT'));
    expect(evidence, contains('20 EA'));
    final dispositions = _textUnder(tester, CapaReportScreen.dispositionsKey('901'));
    expect(dispositions, contains('Scrap · 12 EA · decided by Ann Operator · 2026-09-15'));
    expect(dispositions, contains('Concession · 8 EA'));
    expect(dispositions, contains('DEV-2026-0014'));

    // A finished investigation is waiting for nothing, so the report does not
    // carry the list at all.
    expect(find.byKey(CapaReportScreen.outstandingKey), findsNothing);
  });

  testWidgets('an open CAPA reads with every unfinished part marked, and nothing blank',
      (tester) async {
    final wire = _wire(capa: _openCapa());
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byKey(CapaReportScreen.loadedKey), findsOneWidget);

    // The list a reader sees first: exactly what this investigation has not
    // done, in the 8D's own order.
    final outstanding = _textUnder(tester, CapaReportScreen.outstandingKey);
    expect(outstanding, contains('Not yet done'));
    expect(outstanding, contains('The team has not been named.'));
    expect(outstanding, contains('The problem description has not been written.'));
    expect(outstanding, contains('No containment action is recorded on the Concern.'));
    expect(outstanding, contains('Why it happened has not been started.'));
    expect(outstanding, contains('Why it was not detected has not been started.'));
    expect(outstanding, contains('No countermeasure is recorded on the Concern.'));
    expect(outstanding, contains('No preventive action is recorded on the Concern.'));
    expect(outstanding, contains('The effectiveness check has not been recorded.'));

    // And each section says the same thing where it stands, rather than leaving
    // a blank an auditor would read as an omission.
    expect(find.byKey(CapaReportScreen.noTeamKey), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.noTeamKey),
        contains('Nobody is on this investigation yet.'));
    expect(find.byKey(CapaReportScreen.noProblemKey), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.noProblemKey),
        contains('Nobody has written the problem description yet.'));
    expect(find.byKey(CapaReportScreen.noContainmentKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.noCountermeasuresKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.noPreventiveKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.chainEmptyKey('occurrence')), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.chainRootKey('occurrence')),
        contains('This chain has no confirmed root cause yet.'));
    expect(find.byKey(CapaReportScreen.noCausesKey), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.noCausesKey),
        contains('No candidate cause is recorded, so no fishbone was worked.'));
    expect(find.byKey(CapaReportScreen.effectivenessNotRecordedKey), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.effectivenessNotRecordedKey),
        contains('the Concern has not closed yet'));
    expect(find.byKey(CapaReportScreen.noNonconformancesKey), findsOneWidget);

    // The sections are still all there: an unfinished investigation is read in
    // the same shape as a finished one.
    for (final section in _sectionOrder) {
      expect(find.byKey(section), findsOneWidget, reason: 'the open report has no $section');
    }
    expect(find.byKey(CapaReportScreen.outstandingKey), findsOneWidget);
  });

  testWidgets('an open CAPA with a chain but no confirmed root cause says so, section by section',
      (tester) async {
    // The middle state, which is neither "nothing yet" nor "finished": a Why was
    // written and nobody has concluded the chain, which is exactly what #211
    // refuses to close a CAPA on.
    final wire = _wire(
      capa: _capa(
        status: 'open',
        teamLead: null,
        teamMembers: const [],
        problemStatement: null,
        whys: [capaWhyJson('1', 1, 'Something is loose.')],
        effectivenessVerifiedAt: null,
        effectivenessVerifiedBy: null,
        effectivenessNote: null,
        effectivenessCheckDueAt: '2026-10-14',
        effectivenessCheckOverdue: true,
        concern: _concern(measures: const [], nonconformances: [_occurrence(dispositions: [])]),
      ),
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(_textUnder(tester, CapaReportScreen.chainKey('occurrence')),
        contains('Why 1 · Something is loose.'));
    expect(_textOf(tester, CapaReportScreen.chainRootKey('occurrence')),
        contains('This chain has no confirmed root cause yet.'));
    expect(find.byKey(CapaReportScreen.chainEmptyKey('escape')), findsOneWidget);

    final outstanding = _textUnder(tester, CapaReportScreen.outstandingKey);
    expect(outstanding, contains('Why it happened has no confirmed root cause.'));
    expect(outstanding, contains('Why it was not detected has not been started.'));

    // The check is due and overdue, and the report says the date and the mark
    // rather than a verdict nobody recorded.
    expect(_textOf(tester, CapaReportScreen.effectivenessDueKey),
        contains('the effectiveness check is due on 2026-10-14'));
    expect(find.byKey(CapaReportScreen.effectivenessOverdueKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.effectivenessRecordedKey), findsNothing);

    // The occurrence has no Disposition yet, which is a real state rather than
    // an empty cell.
    expect(find.byKey(CapaReportScreen.noDispositionsKey('901')), findsOneWidget);
    expect(_textOf(tester, CapaReportScreen.noDispositionsKey('901')),
        contains('No product from this occurrence has a Disposition yet.'));
  });

  testWidgets('the report is reached at its own address without the Shell, and asks for the one CAPA',
      (tester) async {
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    // No Shell at all: no sidebar, no brand header, no account footer. This is
    // what makes the browser's own print produce the report rather than the
    // navigation around it, and it is a fact about the widget tree rather than
    // about a stylesheet.
    expect(find.byType(PlatformShell), findsNothing);
    expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    // One read, of the record the address names, and no other request.
    expect(wire.capaReads, ['801']);

    // The one way back is the CAPA itself, by address — the same rule every
    // Screen in this client follows (`context.go`, never a pop).
    await tester.tap(find.byKey(CapaReportScreen.backKey));
    await tester.pumpAndSettle();
    expect(find.byType(CapaReportScreen), findsNothing);
    expect(find.byType(CapaDetailScreen), findsOneWidget);
    expect(locationOf(tester, find.byType(CapaDetailScreen)), '/actions/capas/801');
  });

  testWidgets('the CAPA own Screen offers the report, and opening it moves to the report address',
      (tester) async {
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801',
    );

    expect(find.byType(CapaDetailScreen), findsOneWidget);
    await tapIn(tester, find.byKey(CapaDetailScreen.reportKey));

    expect(find.byType(CapaReportScreen), findsOneWidget);
    expect(locationOf(tester, find.byType(CapaReportScreen)), '/actions/capas/801/report');
    // The report read the record the address names, whether or not the detail
    // Screen behind it had already done so.
    expect(wire.capaReads, everyElement('801'));
    expect(wire.capaReads, isNotEmpty);
  });

  testWidgets('an Account that holds nothing anywhere still reads the report', (tester) async {
    // An approved Account with no Grant at all: it cannot write anything, holds
    // no Quality authority, and is not on any Site's team. Reading a CAPA is a
    // platform-wide read (ADR-0009), so the report shows it everything — a
    // report that hid the evidence from this caller would be a second, stricter
    // rule for one record's own Screen.
    final wire = _wire(scope: {'everywhere': false, 'grants': const <dynamic>[]});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byKey(CapaReportScreen.loadedKey), findsOneWidget);
    expect(_textUnder(tester, CapaReportScreen.teamKey), contains('Ada Lead · team lead'));
    expect(_textUnder(tester, CapaReportScreen.effectivenessKey), contains('Pat Verifier'));
    expect(_textUnder(tester, CapaReportScreen.dispositionsKey('901')), contains('Concession'));
  });

  testWidgets('a shared link to the report delivers the signed-in reader to the report',
      (tester) async {
    // A link sent to a colleague: the address is the report's, the reader is not
    // signed in yet, and what they asked for is what they get — `accountRedirect`
    // carries the address through sign-in as `?from=`.
    final gateway = FakeAuthGateway();
    final wire = _wire();
    await pumpApp(
      tester,
      gateway: gateway,
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(CapaReportScreen), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'a@b.c');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(CapaReportScreen), findsOneWidget);
    expect(find.text(_capaNo), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
  });

  testWidgets('a report that could not be read says so, and offers to read it again',
      (tester) async {
    final wire = _wire(capasStatus: 500, capaMessage: 'The register is unavailable.');
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byKey(CapaReportScreen.failedKey), findsOneWidget);
    expect(find.text('The register is unavailable.'), findsOneWidget);
    expect(find.byKey(CapaReportScreen.retryKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.loadedKey), findsNothing);
    // It still asked for the record by the address's own id, which is what a
    // reader's retry asks for again.
    expect(wire.capaReads, ['801']);
  });

  testWidgets(
      'a CAPA opened on a Concern raised from a Safety incident names the incident where it names a Non-conformance today (issue #229)',
      (tester) async {
    final safetySourcedConcern = actionJson(
      '501',
      'AC-HCM-2026-00001',
      _capaTitle,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      siteId: '1',
      description: 'The guard interlock does not hold under load.',
      status: 'done',
      capa: {'id': '801', 'capaNo': _capaNo, 'status': 'closed'},
      // No measures and no Non-conformances at all: the single-source rule
      // means a Concern raised from a Safety incident never carries either
      // the evidence or the source columns a quality-sourced Concern would.
      sourceSafetyIncidentId: '901',
      safetyIncident: linkedSafetyIncidentJson('901', 'SI-HCM-2026-00001', severityLevel: 'lost_time'),
    );
    final wire = _wire(capa: _capa(concern: safetySourcedConcern));
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/capas/801/report',
    );

    expect(find.byKey(CapaReportScreen.loadedKey), findsOneWidget);

    // The safety-incident section replaces the Non-conformances one — the
    // single-source rule means a Concern is never both.
    expect(find.byKey(CapaReportScreen.safetyIncidentKey), findsOneWidget);
    expect(find.byKey(CapaReportScreen.nonconformancesKey), findsNothing);
    expect(find.byKey(CapaReportScreen.noNonconformancesKey), findsNothing);

    final evidence = _textUnder(tester, CapaReportScreen.safetyIncidentKey);
    expect(evidence, contains('SI-HCM-2026-00001'));
    expect(evidence, contains('Lost time'));
  });
}
