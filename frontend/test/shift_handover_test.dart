/// The Shift handover's client (issue #339, spec #332), driven through the
/// router against a faked wire — the same seam `complaints_test.dart` uses:
/// `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert on what
/// renders and on the requests the Screens actually sent. No Bloc's state is
/// read.
///
/// Covers the ticket's own criteria: the form renders one Machine status line
/// row per Asset with a state picker, and a line written `down` with a note
/// sends that body; a refused submit renders the gaps it named at the top of
/// the form; declaring "no change points this shift" and adding a man Change
/// point both render and post; an Action disposed of as `closed` sends nothing
/// until it says what closed it; the Section board renders a shift with no
/// handover, the late flag and the acknowledgement latency; and the
/// acknowledgement dialog posts the watch results and the board then shows the
/// handover acknowledged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/production/handover_acknowledge_dialog.dart';
import 'package:lean_platform/production/handover_vocabulary.dart';
import 'package:lean_platform/production/section_board_screen.dart';
import 'package:lean_platform/production/shift_handover_screen.dart';

import 'harness.dart';

const _section = '30';
const _shift = '500';
const _handoverAddress = '/production/sections/$_section/handover/$_shift?date=2026-05-05';
const _boardAddress = '/production/sections/$_section/board?date=2026-05-05';

/// One Section with two Assets and one shift. [handover], when given, is the
/// shift's live handover (resumed rather than opened); without it the form
/// opens a draft.
FakeWire _wire({Map<String, dynamic> Function()? handover}) {
  final live = handover?.call();
  return FakeWire(
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    sectionAssets: {
      _section: [
        sectionAssetJson('a1', 'PRESS-1', 'Press 1'),
        sectionAssetJson('a2', 'PRESS-2', 'Press 2'),
      ],
    },
    sectionDays: {
      _section: sectionDayJson(_section, shifts: [sectionShiftJson(_shift, handover: live)]),
    },
    handovers: {if (handover != null) live!['id'] as String: handover()},
  );
}

Map<String, dynamic> _draft({List<Map<String, dynamic>> openActions = const []}) =>
    shiftHandoverJson('h1', orgUnitId: _section, shiftInstanceId: _shift, openActions: openActions);

Future<void> _pump(WidgetTester tester, FakeWire wire, String location) async {
  // Tall enough that the handover's six blocks are all built: a lazy
  // `ListView` does not build a row that is off screen.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 3200);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

/// One dropdown choice, the way a person makes it: open the field, tap the
/// option. `last` because the closed field can already be showing the word.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The writes whose path ends with [suffix], each as `[method, path, body]` —
/// a list rather than the recorded tuple, so `equals` compares the body's
/// contents rather than its identity.
List<List<Object?>> _writesTo(FakeWire wire, String suffix) => [
      for (final write in wire.productionWrites)
        if (write.$2.endsWith(suffix)) [write.$1, write.$2, write.$3],
    ];

void main() {
  group('the Shift handover form', () {
    testWidgets('opens a draft and renders one row per Asset with a state picker; a down line posts its note',
        (tester) async {
      final wire = _wire();
      await _pump(tester, wire, _handoverAddress);

      // No live handover on the day, so a draft was opened for the pair.
      expect(_writesTo(wire, '/api/production/handovers'), [
        ['POST', '/api/production/handovers', {'orgUnitId': _section, 'shiftInstanceId': _shift}],
      ]);
      // The day the board was showing is the day that was read.
      expect(
        wire.productionReads.any(
          (uri) => uri.path.endsWith('/sections/$_section/handovers') && uri.queryParameters['date'] == '2026-05-05',
        ),
        isTrue,
      );

      for (final asset in ['a1', 'a2']) {
        expect(find.byKey(ShiftHandoverScreen.machineRowKey(asset)), findsOneWidget);
        expect(find.byKey(ShiftHandoverScreen.machineStateKey(asset)), findsOneWidget);
      }
      // The frozen numbers are not there yet on a draft.
      expect(
        find.descendant(of: find.byKey(ShiftHandoverScreen.statusCardKey('oee')), matching: find.text('—')),
        findsOneWidget,
      );

      // The picker offers the API's eight states.
      await tapIn(tester, find.byKey(ShiftHandoverScreen.machineStateKey('a1')));
      for (final state in HandoverVocabulary.machineStates) {
        expect(find.text(state.label), findsWidgets);
      }
      await tester.tap(find.text('Down').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(ShiftHandoverScreen.machineNoteKey('a1')), 'Feed belt slipping');
      await tapIn(tester, find.byKey(ShiftHandoverScreen.machineSaveKey('a1')));

      expect(_writesTo(wire, '/machine-lines/a1'), [
        ['PUT', '/api/production/handovers/h1/machine-lines/a1', {
          'state': 'down',
          'abnormalityType': null,
          'note': 'Feed belt slipping',
          'watchNote': null,
          'walked': false,
        }],
      ]);
      // Nothing was written for the Asset that was not touched.
      expect(_writesTo(wire, '/machine-lines/a2'), isEmpty);
    });

    testWidgets('a refused submit renders the named gaps at the top of the form, and Submit stays live',
        (tester) async {
      final wire = _wire(handover: _draft)
        ..submitHandoverStatus = 409
        ..submitHandoverRefusal = {
          'message': 'This handover cannot be submitted: no machine status line for PRESS-2',
          'code': 'INCOMPLETE_HANDOVER',
          'missingAssets': [
            {'id': 'a2', 'code': 'PRESS-2', 'name': 'Press 2'},
          ],
          'incompleteLines': [],
          'unansweredBlocks': ['changePoints'],
          'undispositionedActions': [],
        };
      await _pump(tester, wire, _handoverAddress);

      // A live draft is resumed, never opened a second time.
      expect(_writesTo(wire, '/api/production/handovers'), isEmpty);

      final submit = find.byKey(ShiftHandoverScreen.submitKey);
      await tapIn(tester, submit);

      expect(_writesTo(wire, '/submit'), [['POST', '/api/production/handovers/h1/submit', null]]);
      final refusal = find.byKey(ShiftHandoverScreen.refusalKey);
      expect(refusal, findsOneWidget);
      expect(
        find.descendant(of: refusal, matching: find.text('• No machine status line for PRESS-2 · Press 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: refusal, matching: find.textContaining('change points are unanswered')),
        findsOneWidget,
      );
      // Above the first block of the form, where the person who pressed it reads first.
      expect(
        tester.getTopLeft(refusal).dy,
        lessThan(tester.getTopLeft(find.byKey(ShiftHandoverScreen.statusCardKey('oee'))).dy),
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    });

    testWidgets('declaring no change points and adding a man change point both post and render', (tester) async {
      final wire = _wire(handover: _draft);
      await _pump(tester, wire, _handoverAddress);

      await tapIn(tester, find.byKey(ShiftHandoverScreen.changePointsNoneKey));
      expect(_writesTo(wire, '/handovers/h1'), [
        ['PATCH', '/api/production/handovers/h1', {'changePointsNone': true}],
      ]);
      expect(tester.widget<CheckboxListTile>(find.byKey(ShiftHandoverScreen.changePointsNoneKey)).value, isTrue);

      await _choose(tester, ShiftHandoverScreen.changePointDimensionKey, 'Man');
      await tester.enterText(
        find.byKey(ShiftHandoverScreen.changePointDescriptionKey),
        'New operator on PRESS-1 from tonight',
      );
      await tester.enterText(
        find.byKey(ShiftHandoverScreen.changePointWatchKey),
        'First-off check on the first three coils',
      );
      await tester.pumpAndSettle();
      await tapIn(tester, find.byKey(ShiftHandoverScreen.changePointAddKey));

      expect(_writesTo(wire, '/change-points'), [
        ['POST', '/api/production/handovers/h1/change-points', {
          'dimension': 'man',
          'description': 'New operator on PRESS-1 from tonight',
          'watchNote': 'First-off check on the first three coils',
        }],
      ]);
      expect(
        find.descendant(
          of: find.byKey(ShiftHandoverScreen.changePointGroupKey('man')),
          matching: find.text('New operator on PRESS-1 from tonight'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an action disposed of as closed sends nothing until it says what closed it', (tester) async {
      final wire = _wire(
        handover: () => _draft(openActions: [handoverOpenActionJson('900', 'AC-SC-2026-00012', 'Guard keeps working loose')]),
      );
      await _pump(tester, wire, _handoverAddress);

      await _choose(tester, ShiftHandoverScreen.actionDispositionKey('900'), 'Closed');
      await tapIn(tester, find.byKey(ShiftHandoverScreen.actionRecordKey('900')));

      expect(_writesTo(wire, '/actions'), isEmpty);
      expect(find.byKey(ShiftHandoverScreen.actionErrorKey('900')), findsOneWidget);

      await tester.enterText(
        find.byKey(ShiftHandoverScreen.actionClosureNoteKey('900')),
        'Guard re-fixed with thread lock; held all shift',
      );
      await tapIn(tester, find.byKey(ShiftHandoverScreen.actionRecordKey('900')));

      final sent = _writesTo(wire, '/actions');
      expect(sent, [
        ['POST', '/api/production/handovers/h1/actions', {
          'actionId': '900',
          'disposition': 'closed',
          'closureNote': 'Guard re-fixed with thread lock; held all shift',
        }],
      ]);
      // The Action now reads as this handover's word about it.
      expect(find.byKey(ShiftHandoverScreen.openActionKey('900')), findsNothing);
      expect(find.textContaining('Closed · Guard re-fixed with thread lock'), findsOneWidget);
    });
  });

  group('the Section board', () {
    FakeWire boardWire({Map<String?, List<Map<String, dynamic>>>? orgUnits}) => FakeWire(
          sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
          orgUnits: orgUnits,
          sectionDays: {
            _section: sectionDayJson(_section, shifts: [
              sectionShiftJson('s1', exceptions: ['no_handover']),
              sectionShiftJson(
                's2',
                handover: shiftHandoverJson(
                  'h2',
                  orgUnitId: _section,
                  shiftInstanceId: 's2',
                  status: 'submitted',
                  late: true,
                  authorDisplayName: 'Lan Tran',
                ),
                late: true,
                exceptions: ['unacknowledged'],
              ),
              sectionShiftJson(
                's3',
                handover: shiftHandoverJson('h3', orgUnitId: _section, shiftInstanceId: 's3', status: 'acknowledged'),
                late: false,
                acknowledgementLatencyMinutes: 512.5,
              ),
            ]),
          },
          handovers: {
            'h2': shiftHandoverJson(
              'h2',
              orgUnitId: _section,
              shiftInstanceId: 's2',
              status: 'submitted',
              late: true,
              authorDisplayName: 'Lan Tran',
              changePoints: {
                'man': [
                  changePointJson(
                    'cp1',
                    dimension: 'man',
                    description: 'New operator on PRESS-1',
                    watchNote: 'First-off check on the first three coils',
                  ),
                ],
              },
            ),
          },
        );

    testWidgets('renders no handover recorded, the late flag and the acknowledgement latency', (tester) async {
      final wire = boardWire();
      await _pump(tester, wire, _boardAddress);

      expect(
        wire.productionReads.single.queryParameters['date'],
        '2026-05-05',
      );
      expect(
        find.descendant(
          of: find.byKey(SectionBoardScreen.exceptionKey('s1', 'no_handover')),
          matching: find.text('No handover recorded'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(SectionBoardScreen.handoverStatusKey('s1')), findsNothing);
      expect(find.byKey(SectionBoardScreen.lateKey('s2')), findsOneWidget);
      expect(find.byKey(SectionBoardScreen.exceptionKey('s2', 'unacknowledged')), findsOneWidget);
      expect(find.byKey(SectionBoardScreen.lateKey('s3')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(SectionBoardScreen.latencyKey('s3'))).data,
        contains('acknowledged 8 h 33 min after the shift began'),
      );
      // Acknowledging is offered on the submitted handover, and only there.
      expect(find.byKey(SectionBoardScreen.acknowledgeKey('s2')), findsOneWidget);
      expect(find.byKey(SectionBoardScreen.acknowledgeKey('s1')), findsNothing);
      expect(find.byKey(SectionBoardScreen.acknowledgeKey('s3')), findsNothing);
    });

    testWidgets('the acknowledge dialog posts the watch results, then the board shows it acknowledged',
        (tester) async {
      final wire = boardWire();
      await _pump(tester, wire, _boardAddress);

      await tapIn(tester, find.byKey(SectionBoardScreen.acknowledgeKey('s2')));
      expect(find.byType(HandoverAcknowledgeDialog), findsOneWidget);
      expect(find.textContaining('New operator on PRESS-1'), findsOneWidget);

      await _choose(tester, HandoverAcknowledgeDialog.resultKey('cp1'), 'Concern');
      await tester.enterText(
        find.byKey(HandoverAcknowledgeDialog.resultNoteKey('cp1')),
        'Second coil out of tolerance; reset',
      );
      await tester.enterText(find.byKey(HandoverAcknowledgeDialog.noteKey), 'Walked with Lan');
      await tapIn(tester, find.byKey(HandoverAcknowledgeDialog.submitKey));

      expect(_writesTo(wire, '/acknowledge'), [
        ['POST', '/api/production/handovers/h2/acknowledge', {
          'note': 'Walked with Lan',
          'changePointResults': [
            {'changePointId': 'cp1', 'result': 'concern', 'note': 'Second coil out of tolerance; reset'},
          ],
        }],
      ]);
      expect(find.byType(HandoverAcknowledgeDialog), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(SectionBoardScreen.handoverStatusKey('s2')),
          matching: find.text('Acknowledged'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(SectionBoardScreen.exceptionKey('s2', 'unacknowledged')), findsNothing);
      expect(find.byKey(SectionBoardScreen.acknowledgeKey('s2')), findsNothing);
      expect(find.byKey(SectionBoardScreen.latencyKey('s2')), findsOneWidget);
      // The day was read again, for the same day.
      expect(wire.productionReads.where((uri) => uri.path.endsWith('/handovers')).length, 2);
      expect(wire.productionReads.last.queryParameters['date'], '2026-05-05');
    });

    testWidgets('the Production Destination opens a Section chooser, and a Section opens its board', (tester) async {
      final wire = boardWire(
        orgUnits: {
          null: [orgUnitJson('20', 'Weaving', unitType: 'department')],
          '20': [orgUnitJson(_section, 'Self-Closing', parentId: '20', unitType: 'section')],
        },
      );
      await _pump(tester, wire, '/');

      // The Shell renders a group heading in capitals.
      expect(find.text(DestinationGroupNames.production.toUpperCase()), findsOneWidget);
      await tapIn(tester, find.text('Shift handovers'));
      expect(find.byKey(SectionBoardScreen.chooserKey), findsOneWidget);

      // A department only expands; the Section beneath it opens the board.
      await tapIn(
        tester,
        find.descendant(of: find.byKey(SectionBoardScreen.chooserKey), matching: find.byTooltip('Expand')).first,
      );
      await tapIn(tester, find.byKey(SectionBoardScreen.sectionRowKey(_section)));
      expect(find.byKey(SectionBoardScreen.loadedKey), findsOneWidget);
      expect(find.byKey(SectionBoardScreen.shiftRowKey('s1')), findsOneWidget);
    });
  });
}
