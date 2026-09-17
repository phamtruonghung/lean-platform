/// Raising a Concern from a Non-conformance, linking a further occurrence and
/// unlinking one — driven through the router against a faked wire (issue #208),
/// at the same two seams every other Quality and Actions widget test uses:
/// `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert on what
/// renders and on the requests the Screen actually sent.
///
/// Both Screens are covered here rather than in two files, because the ticket's
/// own criterion is that they show *each other*: a Non-conformance's detail
/// offers raising a Concern and lists the Concerns it is linked to, and a
/// Concern lists the Non-conformances it answers — each row linking to the
/// other record's address. Splitting that into two files would put the two
/// halves of one sentence in two places.
///
/// The second thing this file proves is which endpoint each act is sent to and
/// with what in it: raising a Concern is the Actions Module's own route
/// (`POST /api/actions/nonconformances/:id/concern`) and carries no `orgUnitId`
/// at all, because the Concern lands at the record's own Org Unit and the
/// Screen does not offer a choice the server would ignore; a link names the
/// concern in its path and the record in its body; and an unlink names both
/// ends in its path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/actions/action_unlink_nonconformance_dialog.dart';
import 'package:lean_platform/quality/nonconformance_detail_screen.dart';
import 'package:lean_platform/quality/nonconformance_link_concern_dialog.dart';
import 'package:lean_platform/quality/nonconformance_raise_concern_dialog.dart';

import 'harness.dart';

/// One Non-conformance as its own read returns it, with the Concerns it is
/// linked to named the way `toNonconformance` sends them. [concern] is a
/// `concernJson` row, or null for a record nothing is being done about.
Map<String, dynamic> _nonconformance({
  String id = '701',
  String issueNo = 'NC-HCM-2026-00001',
  List<Map<String, dynamic>> concerns = const [],
}) =>
    nonconformanceJson(
      id,
      issueNo,
      quantityAffected: 20,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      lotRef: 'LOT-2026-09',
      concerns: concerns,
    );

/// A Concern as the action log sends it — what the raise answers with, what the
/// link dialog picks from, and what the Concern Screen renders.
Map<String, dynamic> _concern({
  String id = '501',
  String actionNo = 'AC-HCM-2026-00001',
  String title = 'The press keeps drifting',
  String status = 'open',
  String? ownerName,
  List<Map<String, dynamic>> nonconformances = const [],
}) =>
    actionJson(
      id,
      actionNo,
      title,
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      ownerName: ownerName,
      description: 'The same dimensional failure three shifts running.',
      sourceNonconformanceId: nonconformances.isEmpty ? null : (nonconformances.first['id'] as String),
      nonconformances: nonconformances,
    );

/// The wire every test starts from: one Site, one area, one Product and one
/// Defect code, one Non-conformance with nothing being done about its cause,
/// and one Concern to link it to.
FakeWire _wire({
  List<Map<String, dynamic>> concernsOn701 = const [],
  Map<String, Map<String, dynamic>>? actionDetails,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [
        defectCodeJson('41', 'DIM-OOT', 'Out of tolerance', defaultSeverity: 'minor'),
        defectCodeJson('42', 'CRA-01', 'Cracked casting', defaultSeverity: 'major'),
      ],
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true)],
      },
      nonconformances: {
        '1': [
          _nonconformance(concerns: concernsOn701),
          _nonconformance(
            id: '702',
            issueNo: 'NC-HCM-2026-00002',
            concerns: concernsOn701,
          ),
        ],
      },
      actions: {
        '1': [
          _concern(),
          actionJson('502', 'AC-HCM-2026-00002', 'Guard latch is loose', orgUnitId: '11'),
        ],
      },
      actionDetails: actionDetails ??
          {
            '501': _concern(),
          },
    );

/// Pinned taller than the default 800x600: both Screens carry their
/// cross-linked section at the foot of a lazy `ListView`, and `find.byKey` on a
/// row a `ListView` has not built yet fails with "Found 0 widgets" — not a
/// missing feature but a viewport that never reached it.
Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/non-conformances/701',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2600);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

/// Every line inside a keyed row, joined — a linked Concern or Non-conformance
/// row is several `Text`s, so asserting on one of them would miss half of it.
String _rowText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

/// The address the router is sitting on, read off a widget the Screen being
/// asserted on actually renders — the same helper `nonconformance_dispositions_
/// test.dart` uses, and the only way to prove where a row's tap went.
String _locationOf(WidgetTester tester, Finder finder) => locationOf(tester, finder);

void main() {
  // -------------------------------------------------------------------------
  // The Non-conformance detail Screen (issue #208)
  // -------------------------------------------------------------------------

  testWidgets('the Non-conformance detail offers raising a Concern, and says when nothing is being done about the cause',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(NonconformanceDetailScreen.concernsKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.noConcernsKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.raiseConcernKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.linkConcernKey), findsOneWidget);
    // Nothing has been asked of the action log yet.
    expect(wire.concernRaisePosts, isEmpty);
  });

  testWidgets('the detail shows the Concerns the record is linked to, with their status, and each links to the Concern\'s own address',
      (tester) async {
    final concern = _concern(ownerName: 'Ann Fitter');
    final wire = _wire(concernsOn701: [concernJson(concern, isSource: true)]);
    await _pump(tester, wire);

    expect(find.byKey(NonconformanceDetailScreen.noConcernsKey), findsNothing);
    final row = _rowText(tester, NonconformanceDetailScreen.concernRowKey('501'));
    expect(row, contains('The press keeps drifting'));
    expect(row, contains('AC-HCM-2026-00001'));
    expect(row, contains('raised from this record'));
    // The status is the action log's own five words, through the Actions
    // Module's entry point rather than a second copy of the map.
    expect(row, contains('Open'));

    // And the row goes to the Concern's own address — the half of "each record
    // shows the other" that lives on this Screen.
    await tapIn(tester, find.byKey(NonconformanceDetailScreen.concernRowKey('501')));
    expect(
      _locationOf(tester, find.byKey(ActionDetailScreen.loadedKey)),
      '/actions/501',
    );
  });

  testWidgets('raising a Concern sends its title, its note and its priority, and nothing about the Org Unit',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.raiseConcernKey));
    expect(find.byKey(NonconformanceRaiseConcernDialog.titleKey), findsOneWidget);
    // Nothing can be sent until there is a title, which is the one field the
    // Action log's own rules refuse without — the submit button is closed.
    expect(
      tester.widget<FilledButton>(find.byKey(NonconformanceRaiseConcernDialog.submitKey)).onPressed,
      isNull,
    );
    expect(wire.concernRaisePosts, isEmpty);

    await tester.enterText(
      find.byKey(NonconformanceRaiseConcernDialog.titleKey),
      'The press keeps drifting',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(NonconformanceRaiseConcernDialog.descriptionKey),
      'Three shifts running, same dimension.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceRaiseConcernDialog.priorityKey));
    await tapIn(tester, find.text('P2').last);
    await tapIn(tester, find.byKey(NonconformanceRaiseConcernDialog.submitKey));

    // One request, to the Action log's own route for raising a Concern from a
    // record — and no `orgUnitId` in it, because the Concern lands at the
    // record's own Org Unit.
    expect(wire.concernRaisePosts.length, 1);
    expect(wire.concernRaisePosts.single.$1, '701');
    expect(wire.concernRaisePosts.single.$2, {
      'title': 'The press keeps drifting',
      'description': 'Three shifts running, same dimension.',
      'priority': 2,
    });
    expect(wire.concernRaisePosts.single.$2.containsKey('orgUnitId'), isFalse);

    // The dialog has closed and the Screen the raise was made from now names
    // the Concern — read back from the record, not inferred from the answer.
    expect(find.byKey(NonconformanceRaiseConcernDialog.submitKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.concernNoticeKey), findsOneWidget);
    expect(
      _rowText(tester, NonconformanceDetailScreen.concernRowKey('901')),
      contains('AC-TEST-2026-00009'),
    );
  });

  testWidgets('a refused raise keeps the dialog open with the server\'s own sentence, and sends nothing else',
      (tester) async {
    final wire = _wire()
      ..raiseConcernStatus = 409
      ..raiseConcernMessage = 'this Non-conformance was cancelled, so no Concern can be raised from it';
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.raiseConcernKey));
    await tester.enterText(
      find.byKey(NonconformanceRaiseConcernDialog.titleKey),
      'Nothing to solve',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceRaiseConcernDialog.submitKey));

    expect(wire.concernRaisePosts.length, 1);
    expect(
      find.text('this Non-conformance was cancelled, so no Concern can be raised from it'),
      findsOneWidget,
    );
    // The Screen's own copy of the failure is not a second one: the dialog that
    // asked is still open, holding the sentence, and the form is still usable.
    expect(find.byKey(NonconformanceRaiseConcernDialog.submitKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.noConcernsKey), findsOneWidget);
  });

  testWidgets('the link dialog offers the Site\'s open Concerns, filters them in memory, and links the record to the picked one',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.linkConcernKey));
    expect(find.byKey(NonconformanceLinkConcernDialog.concernFieldKey), findsOneWidget);
    // The submit gate is closed while nothing is picked.
    expect(
      tester
          .widget<FilledButton>(find.byKey(NonconformanceLinkConcernDialog.submitKey))
          .onPressed,
      isNull,
    );
    // The dialog read the Site's action log once, on opening.
    expect(wire.actionReads.length, 1);
    expect(wire.actionReads.single.path, '/api/actions/sites/1/actions');

    // Typing narrows the list the dialog already holds and issues no request at
    // all (ADR-0023's reading half — the counts prove it).
    final requestsBefore = wire.requests.length;
    await typeInSearchField(
      tester,
      NonconformanceLinkConcernDialog.concernFieldKey,
      'guard',
    );
    expect(wire.requests.length, requestsBefore);
    expect(
      find.byKey(NonconformanceLinkConcernDialog.concernSuggestionKey('502')),
      findsOneWidget,
    );
    expect(
      find.byKey(NonconformanceLinkConcernDialog.concernSuggestionKey('501')),
      findsNothing,
    );

    await tapIn(
      tester,
      find.byKey(NonconformanceLinkConcernDialog.concernSuggestionKey('502')),
    );
    await tapIn(tester, find.byKey(NonconformanceLinkConcernDialog.submitKey));

    // The concern is in the path — the act is on the Concern — and the record
    // is in the body.
    expect(wire.nonconformanceLinkPosts.length, 1);
    expect(wire.nonconformanceLinkPosts.single.$1, '502');
    expect(wire.nonconformanceLinkPosts.single.$2, {'nonconformanceId': '701'});
  });

  // -------------------------------------------------------------------------
  // The Concern Screen (issue #208)
  // -------------------------------------------------------------------------

  testWidgets('the Concern Screen shows the Non-conformances it answers, with number, Product, Defect code and quantity',
      (tester) async {
    final record = _nonconformance();
    final second = _nonconformance(id: '702', issueNo: 'NC-HCM-2026-00002');
    final wire = _wire(
      actionDetails: {
        '501': _concern(nonconformances: [
          linkedNonconformanceJson(record, isSource: true),
          linkedNonconformanceJson(second),
        ]),
      },
    );
    await _pump(tester, wire, location: '/actions/501');

    final first = _rowText(tester, ActionDetailScreen.nonconformanceKey('701'));
    expect(first, contains('NC-HCM-2026-00001'));
    expect(first, contains('Gearbox · PRD-1'));
    expect(first, contains('Out of tolerance · DIM-OOT'));
    expect(first, contains('20 EA'));
    // The one the Concern was raised from says so, and offers no unlink: the
    // service refuses that one, so offering it would be offering a refusal.
    expect(find.byKey(ActionDetailScreen.raisedFromKey), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.unlinkNonconformanceKey('701')), findsNothing);

    // The further occurrence offers the unlink and no "raised from" marker.
    expect(find.byKey(ActionDetailScreen.unlinkNonconformanceKey('702')), findsOneWidget);
    expect(_rowText(tester, ActionDetailScreen.nonconformanceKey('702')), contains(
      'NC-HCM-2026-00002',
    ));
  });

  testWidgets('an occurrence\'s row links to the Non-conformance\'s own address', (tester) async {
    final wire = _wire(
      actionDetails: {
        '501': _concern(nonconformances: [
          linkedNonconformanceJson(_nonconformance(), isSource: true),
        ]),
      },
    );
    await _pump(tester, wire, location: '/actions/501');

    await tapIn(tester, find.byKey(ActionDetailScreen.nonconformanceKey('701')));
    expect(
      _locationOf(tester, find.byKey(NonconformanceDetailScreen.backKey)),
      '/non-conformances/701',
    );
  });

  testWidgets('a Concern with nothing linked says so, rather than showing an empty section',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/actions/501');

    expect(find.byKey(ActionDetailScreen.noNonconformancesKey), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.nonconformanceKey('701')), findsNothing);
  });

  testWidgets('unlinking an occurrence sends both ids and leaves the Concern listing the rest',
      (tester) async {
    final record = _nonconformance();
    final second = _nonconformance(id: '702', issueNo: 'NC-HCM-2026-00002');
    final wire = _wire(
      actionDetails: {
        '501': _concern(nonconformances: [
          linkedNonconformanceJson(record, isSource: true),
          linkedNonconformanceJson(second),
        ]),
      },
    );
    await _pump(tester, wire, location: '/actions/501');

    await tapIn(tester, find.byKey(ActionDetailScreen.unlinkNonconformanceKey('702')));
    expect(find.byKey(ActionUnlinkNonconformanceDialog.submitKey), findsOneWidget);
    // Confirming is what sends it — the address alone unlinks nothing.
    expect(wire.nonconformanceUnlinkPosts, isEmpty);

    await tapIn(tester, find.byKey(ActionUnlinkNonconformanceDialog.submitKey));

    expect(wire.nonconformanceUnlinkPosts.single, ('501', '702'));
    expect(find.byKey(ActionUnlinkNonconformanceDialog.submitKey), findsNothing);
    expect(find.byKey(ActionDetailScreen.nonconformanceKey('702')), findsNothing);
    // The occurrence it was raised from is still there, and so is the record.
    expect(find.byKey(ActionDetailScreen.nonconformanceKey('701')), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.unlinkNonconformanceKey('701')), findsNothing);
  });

  testWidgets('a refused unlink keeps the dialog open with the server\'s own sentence',
      (tester) async {
    final record = _nonconformance();
    final wire = _wire(
      actionDetails: {
        '501': _concern(nonconformances: [linkedNonconformanceJson(record, isSource: true)]),
      },
    )
      ..unlinkNonconformanceStatus = 409
      ..unlinkNonconformanceMessage =
          'the Non-conformance this Concern was raised from cannot be unlinked: the Concern records where it came from';
    // Reached by its own address, which is how a refresh lands on it: the
    // Screen does not offer an unlink for the source occurrence at all.
    await _pump(tester, wire, location: '/actions/501/nonconformances/701/unlink');

    await tapIn(tester, find.byKey(ActionUnlinkNonconformanceDialog.submitKey));

    expect(wire.nonconformanceUnlinkPosts.single, ('501', '701'));
    expect(
      find.text(
        'the Non-conformance this Concern was raised from cannot be unlinked: the Concern records '
        'where it came from',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ActionUnlinkNonconformanceDialog.submitKey), findsOneWidget);
    expect(find.byKey(ActionDetailScreen.nonconformanceKey('701')), findsOneWidget);
  });
}
