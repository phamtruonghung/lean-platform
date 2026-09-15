/// The action log (issue #176), with the wire faked — the one client seam
/// (ADR-0012). The real app, the real router, the real Blocs, `MockClient` at
/// the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that the register renders what
/// it is given in the order the server sends it, that every narrowing control
/// sends the query it says it does, and that raising sends exactly one request
/// carrying what the form collected. Not that the server orders, filters,
/// scopes or validates any of it — that is proved in
/// `backend/test/integration/actions.test.js`, and neither substitutes for the
/// other (mirroring `assets_test.dart`'s own Testing Decisions).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/action.dart' hide Action;
import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/actions/action_measure_dialog.dart';
import 'package:lean_platform/actions/action_phase_complete_dialog.dart';
import 'package:lean_platform/actions/action_form_dialog.dart';
import 'package:lean_platform/actions/actions_screen.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  Map<String, List<Map<String, dynamic>>>? actions,
  int actionsStatus = 200,
  Map<String, Map<String, dynamic>>? actionDetails,
  int createActionStatus = 201,
  String createActionMessage = 'That concern could not be raised.',
  int completePhaseStatus = 200,
  String completePhaseMessage = 'this Action is waiting on its plan phase, not its do',
  int createMeasureStatus = 201,
  String createMeasureMessage = 'a measure answers a Concern, and that Action is not one',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [
          orgUnitJson('10', 'Assembly'),
          orgUnitJson('12', 'Packaging'),
        ],
      },
      actions: actions ?? {'1': []},
      actionsStatus: actionsStatus,
      actionDetails: actionDetails,
      createActionStatus: createActionStatus,
      createActionMessage: createActionMessage,
      completePhaseStatus: completePhaseStatus,
      completePhaseMessage: completePhaseMessage,
      createMeasureStatus: createMeasureStatus,
      createMeasureMessage: createMeasureMessage,
    );

void main() {
  test('the Actions Destination is offered to every role, under its own heading', () {
    for (final role in [
      Roles.operator,
      Roles.supervisor,
      Roles.engineer,
      Roles.manager,
      Roles.admin,
    ]) {
      final destinations = destinationsFor(role: role);
      expect(
        destinations.any((destination) => destination.path == Routes.actions),
        isTrue,
        reason: '$role should be offered the action log',
      );
    }
    // The group order is what the sidebar renders by, and Actions sits between
    // the groups where work is done and the groups where the plant is read
    // about (ADR-0032).
    expect(
      DestinationGroupNames.order.indexOf(DestinationGroupNames.actions),
      DestinationGroupNames.order.indexOf(DestinationGroupNames.maintenance) + 1,
    );
  });

  testWidgets('the register renders what it is given, worst first, nobody-owned included',
      (tester) async {
    final wire = wireWith(
      actions: {
        '1': [
          // The server's own order: overdue, then due soonest, then undated.
          actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose',
              dueDate: '2026-09-01', isOverdue: true, daysOverdue: 14, ownerName: 'Ann Fitter'),
          actionJson('502', 'AC-HCM-2026-00002', 'Pallet wrapper jams',
              actionType: 'containment', dueDate: '2026-10-01'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    expect(find.byKey(ActionsScreen.rowKey('501')), findsOneWidget);
    expect(find.byKey(ActionsScreen.rowKey('502')), findsOneWidget);
    expect(find.text('Guard keeps working loose'), findsOneWidget);
    expect(find.text('Containment'), findsOneWidget);
    expect(find.text('Overdue by 14 days'), findsOneWidget);
    // Nobody owns row 502 yet — said plainly, never as a blank.
    expect(find.text('Nobody yet'), findsOneWidget);
    expect(find.text('Ann Fitter'), findsOneWidget);

    // The order on screen is the order off the wire, which is the order the
    // server orders by: the assertion a reshuffling client would fail.
    final rows = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(rows.length, 2);
    expect(find.byKey(ActionsScreen.dueKey('502')), findsOneWidget);
  });

  testWidgets('the log still loading shows placeholders in its own shape', (tester) async {
    final wire = wireWith()..actionsGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(ActionsScreen.emptyKey), findsNothing);

    wire.actionsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
    expect(find.byKey(ActionsScreen.emptyKey), findsOneWidget);
  });

  testWidgets('a failed read names the failure and offers a retry', (tester) async {
    final wire = wireWith(actionsStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    expect(find.byKey(ActionsScreen.failedKey), findsOneWidget);
    expect(find.text('The action log is unavailable.'), findsOneWidget);
    expect(find.byKey(ActionsScreen.retryKey), findsOneWidget);
  });

  testWidgets('an empty Site says so plainly, and a filter that matched nothing says that instead',
      (tester) async {
    final wire = wireWith();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    expect(find.byKey(ActionsScreen.emptyKey), findsOneWidget);
    expect(find.text('No Action has been raised at this Site yet.'), findsOneWidget);

    // Narrowing to a status nothing holds: the other empty story, with the one
    // action that resolves it.
    await tapIn(tester, find.byKey(ActionsScreen.statusFilterKey));
    await tapIn(tester, find.text('Done').last);

    expect(find.text('Nothing matches these filters'), findsOneWidget);
    expect(find.byKey(ActionsScreen.emptyClearFiltersKey), findsOneWidget);
    expect(wire.actionReads.last.queryParameters['status'], 'done');
  });

  testWidgets('the history switch asks the server for the closed Actions', (tester) async {
    final wire = wireWith(
      actions: {
        '1': [
          actionJson('501', 'AC-HCM-2026-00001', 'Still open'),
          actionJson('502', 'AC-HCM-2026-00002', 'Finished', status: 'done'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    expect(find.text('Finished'), findsNothing);
    expect(wire.actionReads.single.queryParameters['includeHistory'], isNull);

    await tapIn(tester, find.byKey(ActionsScreen.historyKey));

    expect(wire.actionReads.last.queryParameters['includeHistory'], 'true');
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('raising a concern needs a title and an Org Unit, and sends exactly one request',
      (tester) async {
    final wire = wireWith();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    await tapIn(tester, find.byKey(ActionsScreen.raiseKey));
    expect(find.byType(ActionFormDialog), findsOneWidget);

    // Nothing submit-worthy yet: no title, no Org Unit.
    await tapIn(tester, find.byKey(ActionFormDialog.submitKey));
    expect(wire.actionPosts, isEmpty);

    await tester.enterText(find.byKey(ActionFormDialog.titleKey), 'Bearing is singing');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ActionFormDialog.submitKey));
    expect(wire.actionPosts, isEmpty);

    // The tree is browsed, not typed (ADR-0023).
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(find.byKey(ActionFormDialog.chosenKey), findsOneWidget);

    await tapIn(tester, find.byKey(ActionFormDialog.typeKey));
    await tapIn(tester, find.text('Countermeasure').last);
    await tapIn(tester, find.byKey(ActionFormDialog.submitKey));

    expect(wire.actionPosts.length, 1);
    expect(wire.actionPosts.single['title'], 'Bearing is singing');
    expect(wire.actionPosts.single['orgUnitId'], '10');
    expect(wire.actionPosts.single['actionType'], 'countermeasure');
    // The raise is Site-scoped in its own path, so the register and the form
    // cannot disagree about which Site's log this is.
    expect(wire.actionReads.last.path, '/api/actions/sites/1/actions');

    // The register shows it without being re-read, and says so.
    expect(find.byType(ActionFormDialog), findsNothing);
    expect(find.text('Bearing is singing'), findsOneWidget);
    expect(find.byKey(ActionsScreen.noticeKey), findsOneWidget);
  });

  testWidgets('a refused raise stays in the form with its values and the reason', (tester) async {
    final wire = wireWith(
      createActionStatus: 403,
      createActionMessage: "Outside the caller's granted Org Units",
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    await tapIn(tester, find.byKey(ActionsScreen.raiseKey));
    await tester.enterText(find.byKey(ActionFormDialog.titleKey), 'Out of reach');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(ActionFormDialog.submitKey));

    expect(find.byType(ActionFormDialog), findsOneWidget);
    expect(find.byKey(ActionFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    // The typed title is still there, so the fix is one field and not the form.
    expect(find.text('Out of reach'), findsOneWidget);
  });

  testWidgets('one Action reads back on its own address, with its measures collection empty',
      (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          orgUnitName: 'Assembly',
          ownerName: 'Ann Fitter',
          dueDate: '2026-09-01',
          isOverdue: true,
          daysOverdue: 14,
          pillarCode: 'S',
          description: 'The guard on the infeed end works loose every shift.',
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    expect(find.byKey(ActionDetailScreen.loadedKey), findsOneWidget);
    expect(find.text('AC-HCM-2026-00001'), findsOneWidget);
    expect(find.text('Guard keeps working loose'), findsOneWidget);
    expect(find.text('The guard on the infeed end works loose every shift.'), findsOneWidget);
    expect(find.text('Assembly'), findsOneWidget);
    expect(find.text('Pillar S'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.measuresEmptyKey), findsOneWidget);
  });

  testWidgets('the cycle rail shows the open phase, and earlier rounds beneath it', (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          status: 'in_progress',
          phases: [
            phaseJson(1, 'plan', note: 'Clamp it and find out why', completedAt: '2026-09-01T02:00:00.000Z'),
            phaseJson(1, 'do', note: 'Clamped', completedAt: '2026-09-02T02:00:00.000Z'),
            phaseJson(1, 'check', note: 'It came back after four days', completedAt: '2026-09-06T02:00:00.000Z', outcome: 'not_effective'),
            phaseJson(2, 'plan'),
          ],
          openPhase: phaseJson(2, 'plan'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    expect(find.byKey(ActionDetailScreen.phaseKey(2, 'plan')), findsOneWidget);
    expect(find.text('Cycle 2'), findsOneWidget);
    // The round that failed is still on the record, which is the whole reason
    // the phases are kept.
    expect(find.byKey(ActionDetailScreen.cycleHistoryKey), findsOneWidget);
    // The verdict reads inside the phase's own line, beside its date.
    expect(find.textContaining('It did not hold'), findsWidgets);
    expect(find.byKey(ActionDetailScreen.completePhaseKey), findsOneWidget);
    expect(find.text('Complete the Plan'), findsOneWidget);
  });

  testWidgets('completing a phase sends the note and nothing else, and the rail follows the answer',
      (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          phases: [phaseJson(1, 'plan', dueDate: '2026-09-30')],
          openPhase: phaseJson(1, 'plan', dueDate: '2026-09-30'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    await tapIn(tester, find.byKey(ActionDetailScreen.completePhaseKey));
    expect(find.byType(ActionPhaseCompleteDialog), findsOneWidget);

    // A phase cannot be completed by a click: the note is required.
    await tapIn(tester, find.byKey(ActionPhaseCompleteDialog.submitKey));
    expect(wire.phaseCompletions, isEmpty);

    await tester.enterText(
      find.byKey(ActionPhaseCompleteDialog.noteKey),
      'Clamp the guard, then find out why it works loose',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ActionPhaseCompleteDialog.submitKey));

    expect(wire.phaseCompletions.length, 1);
    final (id, phase, body) = wire.phaseCompletions.single;
    expect(id, '501');
    expect(phase, 'plan');
    expect(body['note'], 'Clamp the guard, then find out why it works loose');
    // No verdict is invented for a phase that has none.
    expect(body.containsKey('outcome'), isFalse);

    expect(find.byType(ActionPhaseCompleteDialog), findsNothing);
    expect(find.text('Complete the Do'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.noticeKey), findsOneWidget);
  });

  testWidgets('a Check asks whether it held, and a failure opens the next cycle', (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'It came back',
          status: 'in_progress',
          phases: [
            phaseJson(1, 'plan', note: 'Plan one', completedAt: '2026-09-01T02:00:00.000Z'),
            phaseJson(1, 'do', note: 'Do one', completedAt: '2026-09-02T02:00:00.000Z'),
            phaseJson(1, 'check'),
          ],
          openPhase: phaseJson(1, 'check'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    await tapIn(tester, find.byKey(ActionDetailScreen.completePhaseKey));
    await tester.enterText(
      find.byKey(ActionPhaseCompleteDialog.noteKey),
      'Jam returned after four days',
    );
    await tester.pumpAndSettle();

    // The verdict is a choice, never a typed word (ADR-0023).
    await tapIn(tester, find.byKey(ActionPhaseCompleteDialog.outcomeOptionKey('not_effective')));
    await tapIn(tester, find.byKey(ActionPhaseCompleteDialog.submitKey));

    expect(wire.phaseCompletions.single.$3['outcome'], 'not_effective');
    expect(find.text('Cycle 2'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.cycleHistoryKey), findsOneWidget);
    expect(find.text('Complete the Plan'), findsOneWidget);
  });

  testWidgets('a phase that is not the open one is refused by the address itself', (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501/phases/act/complete',
    );

    expect(find.byKey(ActionPhaseCompleteDialogHost.notOpenKey), findsOneWidget);
    expect(find.textContaining('waiting on its plan phase'), findsOneWidget);
    expect(wire.phaseCompletions, isEmpty);
  });

  testWidgets('a refused completion stays in the dialog with its note and the reason',
      (tester) async {
    final wire = wireWith(
      completePhaseStatus: 409,
      completePhaseMessage: 'this Action is waiting on its plan phase, not its do',
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    await tapIn(tester, find.byKey(ActionDetailScreen.completePhaseKey));
    await tester.enterText(find.byKey(ActionPhaseCompleteDialog.noteKey), 'Only one person saw it');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ActionPhaseCompleteDialog.submitKey));

    expect(find.byType(ActionPhaseCompleteDialog), findsOneWidget);
    expect(find.byKey(ActionPhaseCompleteDialog.failureKey), findsOneWidget);
    expect(find.text('this Action is waiting on its plan phase, not its do'), findsOneWidget);
    expect(find.text('Only one person saw it'), findsOneWidget);
  });

  testWidgets('a Concern shows the measures answering it, and the counts on the register row',
      (tester) async {
    final wire = wireWith(
      actions: {
        '1': [
          actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose',
              measureCount: 2, countermeasureCount: 1),
        ],
      },
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          status: 'in_progress',
          measureCount: 2,
          countermeasureCount: 1,
          measures: [
            actionJson('601', 'AC-HCM-2026-00006', 'Clamp the guard',
                actionType: 'containment', ownerName: 'Ann Fitter',
                openPhase: phaseJson(1, 'do')),
            actionJson('602', 'AC-HCM-2026-00007', 'Change the pre-start check',
                actionType: 'countermeasure'),
          ],
          phases: [phaseJson(1, 'plan', completedAt: '2026-09-01T02:00:00.000Z', note: 'Planned'), phaseJson(1, 'do')],
          openPhase: phaseJson(1, 'do'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    expect(find.text('Measures (2, 1 of them countermeasures)'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.measureKey('601')), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.measureKey('602')), findsOneWidget);
    expect(find.textContaining('Containment · Open · Ann Fitter'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.measuresEmptyKey), findsNothing);
  });

  testWidgets('raising a containment needs a title, and the kind comes off the address',
      (tester) async {
    final wire = wireWith(
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    await tapIn(tester, find.byKey(ActionDetailScreen.addMeasureKey));
    await tapIn(tester, find.byKey(ActionDetailScreen.addMeasureKindKey('containment')));

    expect(find.byType(ActionMeasureDialog), findsOneWidget);
    // The kind is stated, never choosable inside the form.
    expect(find.textContaining('What stops its effect now'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<ActionType>), findsNothing);

    await tapIn(tester, find.byKey(ActionMeasureDialog.submitKey));
    expect(wire.measurePosts, isEmpty);

    await tester.enterText(find.byKey(ActionMeasureDialog.titleKey), 'Clamp the guard');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ActionMeasureDialog.submitKey));

    expect(wire.measurePosts.length, 1);
    final (concernId, body) = wire.measurePosts.single;
    expect(concernId, '501');
    expect(body['actionType'], 'containment');
    expect(body['title'], 'Clamp the guard');
    // Nothing optional was invented: no Org Unit (the Concern's is the default),
    // no owner, no date, no priority.
    expect(body.containsKey('orgUnitId'), isFalse);
    expect(body.containsKey('ownerEmployeeId'), isFalse);
    expect(body.containsKey('dueDate'), isFalse);

    // The Concern was re-read, so the new measure is in its list.
    expect(find.byType(ActionMeasureDialog), findsNothing);
    expect(find.byKey(ActionDetailScreen.measureKey('800')), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.noticeKey), findsOneWidget);
  });

  testWidgets('a measure a caller may not raise is refused inside the dialog that asked',
      (tester) async {
    final wire = wireWith(
      createMeasureStatus: 403,
      createMeasureMessage: "Outside the caller's granted Org Units",
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/501',
    );

    await tapIn(tester, find.byKey(ActionDetailScreen.addMeasureKey));
    await tapIn(tester, find.byKey(ActionDetailScreen.addMeasureKindKey('countermeasure')));
    await tester.enterText(find.byKey(ActionMeasureDialog.titleKey), 'Change the process');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ActionMeasureDialog.submitKey));

    expect(find.byType(ActionMeasureDialog), findsOneWidget);
    expect(find.byKey(ActionMeasureDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
  });

  testWidgets('a measure says which Concern it answers, and offers no measures of its own',
      (tester) async {
    final wire = wireWith(
      actionDetails: {
        '601': actionJson(
          '601',
          'AC-HCM-2026-00006',
          'Clamp the guard',
          actionType: 'containment',
          parentId: '501',
          parent: {
            'id': '501',
            'actionNo': 'AC-HCM-2026-00001',
            'title': 'Guard keeps working loose',
            'actionType': 'concern',
            'status': 'in_progress',
          },
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
    );
    // A taller window than the default 800x600: the detail read is a scrolling
    // `ListView`, and the measures section sits below the fold at the default
    // size — where it would be built lazily and the key would not exist yet.
    // Pinning the window is cheaper than driving a scroll, and says why.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/601',
    );

    expect(find.byKey(ActionDetailScreen.parentKey), findsOneWidget);
    expect(find.text('Answers AC-HCM-2026-00001'), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.measuresEmptyKey), findsOneWidget);
    expect(find.text('This Action answers no Concern of its own.'), findsOneWidget);
  });

  testWidgets('the register row says what answers it, and how much of that is a fix',
      (tester) async {
    final wire = wireWith(
      actions: {
        '1': [
          actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose',
              measureCount: 3, countermeasureCount: 1),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions',
    );

    expect(find.byKey(ActionsScreen.measuresKey('501')), findsOneWidget);
    expect(find.textContaining('3 measures, 1 of them countermeasures'), findsOneWidget);
  });

  testWidgets('an Action that is not there reports it rather than an empty Screen', (tester) async {
    final wire = wireWith();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/actions/999999',
    );

    expect(find.byKey(ActionDetailScreen.failedKey), findsOneWidget);
    expect(find.text('Action not found'), findsOneWidget);
  });
}
