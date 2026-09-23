/// The tier board (issue #76), with the wire faked — the one client seam
/// (ADR-0012). The real app, the real router, the real Blocs, `MockClient` at
/// the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that all five Pillars render
/// from a scripted board; that a KPI with no data is visibly distinguished from
/// one measured as zero and is never formatted as a number; that changing the
/// Org Unit or the period type dispatches exactly one board request carrying
/// the new value; and that the loading, empty and failure-with-retry states
/// render. Not that the server resolves the period per Site, rolls up the
/// subtree, or evaluates a target — those are proved on the backend, and
/// neither substitutes for the other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/tier_board_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

/// The five Pillars the server always returns, in its own catalogue order
/// (Safety, Quality, Delivery, Cost, People), with a measured MTBF under
/// Delivery by default so the board has something real in it.
List<Map<String, dynamic>> fivePillars({
  List<Map<String, dynamic>>? deliveryKpis,
}) =>
    [
      boardPillarJson('S', 'Safety', sortOrder: 1, kpis: const []),
      boardPillarJson('Q', 'Quality', sortOrder: 2, kpis: const []),
      boardPillarJson(
        'D',
        'Delivery',
        sortOrder: 3,
        kpis: deliveryKpis ??
            [
              boardKpiJson(
                'MNT_MTBF',
                'Mean time between failures',
                unit: 'hours',
                decimalPlaces: 1,
                value: 7,
                status: 'no_target',
              ),
            ],
      ),
      boardPillarJson('C', 'Cost', sortOrder: 4, kpis: const []),
      boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
    ];

Map<String, dynamic> boardBody({
  String siteId = '1',
  String? orgUnitId,
  String periodType = 'day',
  String date = '2026-03-10',
  List<Map<String, dynamic>>? pillars,
}) =>
    {
      'site': {'id': siteId, 'name': 'Ho Chi Minh', 'timezone': 'Asia/Ho_Chi_Minh'},
      'orgUnit': orgUnitId == null
          ? null
          : {'id': orgUnitId, 'name': 'Assembly', 'path': 'n$orgUnitId'},
      'period': {'type': periodType, 'start': date, 'end': date},
      'pillars': pillars ?? fivePillars(),
    };

FakeWire boardWire({
  String role = Roles.supervisor,
  Map<String, dynamic>? board,
  int boardStatus = 200,
  List<Map<String, dynamic>>? sites,
  Map<String?, List<Map<String, dynamic>>>? orgUnits,
}) =>
    FakeWire(
      role: role,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: orgUnits ?? const {},
      board: board ?? boardBody(),
      boardStatus: boardStatus,
    );

void main() {
  testWidgets('a supervisor is offered the Tier board Destination', (tester) async {
    final wire = boardWire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    expect(find.byKey(const ValueKey('nav-item-Tier board')), findsOneWidget);
    expect(find.byType(TierBoardScreen), findsOneWidget);
  });

  testWidgets('all five Pillars render from a scripted board', (tester) async {
    final wire = boardWire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    for (final code in ['S', 'Q', 'D', 'C', 'P']) {
      expect(find.byKey(TierBoardScreen.pillarKey(code)), findsOneWidget);
    }
    for (final name in ['Safety', 'Quality', 'Delivery', 'Cost', 'People']) {
      expect(find.text(name), findsOneWidget);
    }
    // Safety has no KPI and no data behind it: it says so rather than standing
    // as an empty box.
    expect(find.byKey(TierBoardScreen.pillarNoDataKey('S')), findsOneWidget);
    expect(find.text('No data yet'), findsWidgets);
    // Exactly one board read for the initial load.
    expect(wire.boardRequests.length, 1);
  });

  testWidgets('a KPI with no data is distinguished from a KPI reading zero',
      (tester) async {
    final wire = boardWire(
      board: boardBody(
        pillars: [
          boardPillarJson('S', 'Safety', sortOrder: 1, kpis: const []),
          boardPillarJson('Q', 'Quality', sortOrder: 2, kpis: const []),
          boardPillarJson(
            'D',
            'Delivery',
            sortOrder: 3,
            kpis: [
              boardKpiJson(
                'MNT_MTBF',
                'Mean time between failures',
                unit: 'hours',
                decimalPlaces: 1,
                value: null,
                status: 'no_data',
              ),
              boardKpiJson(
                'MNT_PARTS_COST',
                'Parts cost',
                unit: 'GBP',
                decimalPlaces: 0,
                value: 0,
                status: 'no_target',
              ),
            ],
          ),
          boardPillarJson('C', 'Cost', sortOrder: 4, kpis: const []),
          boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
        ],
      ),
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    final noDataCard = find.byKey(TierBoardScreen.kpiKey('MNT_MTBF'));
    expect(noDataCard, findsOneWidget);
    // The unmeasured KPI shows the no-data affordance and an em dash, and
    // never a zero.
    expect(
      find.descendant(of: noDataCard, matching: find.text('No data')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: noDataCard, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: noDataCard, matching: find.text('0')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('MNT_MTBF'))).data,
      '—',
    );

    final zeroCard = find.byKey(TierBoardScreen.kpiKey('MNT_PARTS_COST'));
    expect(zeroCard, findsOneWidget);
    // A measured zero is a real value and reads as one.
    expect(
      find.descendant(of: zeroCard, matching: find.text('0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zeroCard, matching: find.text('No data')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('MNT_PARTS_COST'))).data,
      '0',
    );
  });

  testWidgets("the Quality Pillar renders the numbers Quality's own records answer, and still says "
      'no data for the ones that need production counts', (tester) async {
    // The board the server answers once Quality contributes its own entries
    // (issue #216): the three counts and the two cost-of-poor-quality figures
    // are measured, and the four ratios against quantity produced — with no
    // Production Module to count it — are not.
    final wire = boardWire(
      board: boardBody(
        pillars: [
          boardPillarJson('S', 'Safety', sortOrder: 1, kpis: const []),
          boardPillarJson(
            'Q',
            'Quality',
            sortOrder: 2,
            kpis: [
              boardKpiJson(
                'QUA_OPEN_NC',
                'Open non-conformances',
                unit: 'count',
                direction: 'lower_better',
                decimalPlaces: 0,
                value: 3,
                status: 'green',
                targetValue: 3,
              ),
              boardKpiJson(
                'QUA_OVERDUE_CAPA',
                'Overdue CAPAs',
                unit: 'count',
                direction: 'lower_better',
                decimalPlaces: 0,
                value: 1,
                status: 'amber',
                targetValue: 0,
              ),
              boardKpiJson(
                'QUA_COMPLAINTS',
                'Customer complaints',
                unit: 'count',
                direction: 'lower_better',
                decimalPlaces: 0,
                value: 2,
                status: 'no_target',
              ),
              boardKpiJson(
                'QUA_FPY',
                'First pass yield',
                unit: '%',
                decimalPlaces: 1,
                value: null,
                status: 'no_data',
              ),
            ],
          ),
          boardPillarJson(
            'D',
            'Delivery',
            sortOrder: 3,
            kpis: [
              boardKpiJson(
                'MNT_MTBF',
                'Mean time between failures',
                unit: 'hours',
                decimalPlaces: 1,
                value: 7,
                status: 'no_target',
              ),
            ],
          ),
          boardPillarJson(
            'C',
            'Cost',
            sortOrder: 4,
            kpis: [
              boardKpiJson(
                'COST_COPQ',
                'Cost of poor quality',
                unit: 'currency',
                direction: 'lower_better',
                decimalPlaces: 2,
                value: 84.5,
                status: 'no_target',
              ),
              boardKpiJson(
                'COST_SCRAP',
                'Scrap cost',
                unit: 'currency',
                direction: 'lower_better',
                decimalPlaces: 2,
                value: 51.0,
                status: 'no_target',
              ),
            ],
          ),
          boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
        ],
      ),
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    // The Quality Pillar is a Pillar with data behind it, and each of its
    // numbers is on its own card, toned by the target the definition carries.
    final quality = find.byKey(TierBoardScreen.pillarKey('Q'));
    expect(quality, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('QUA_OPEN_NC'))).data,
      '3',
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('QUA_OVERDUE_CAPA'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('QUA_COMPLAINTS'))).data,
      '2',
    );

    // The ratio that needs a quantity produced is still not a number: it reads
    // as no data, exactly as it did before Quality contributed anything.
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('QUA_FPY'))).data,
      '—',
    );
    expect(
      find.descendant(
        of: find.byKey(TierBoardScreen.kpiKey('QUA_FPY')),
        matching: find.text('No data'),
      ),
      findsOneWidget,
    );

    // And the Cost Pillar's cost-of-poor-quality figures are rendered in the
    // currency the definition declares.
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('COST_COPQ'))).data,
      '84.50',
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('COST_SCRAP'))).data,
      '51.00',
    );
  });

  testWidgets(
      "the Safety Pillar renders SAF_TRIR and SAF_LTIFR from confirmed attendance, "
      'and no_data for the rate an unconfirmed shift still blocks', (tester) async {
    // The board the server answers once attendance is confirmed (issue #233,
    // ADR-0041): SAF_TRIR is a real rate over the rolling 12-month window,
    // while SAF_LTIFR — computed the same way, over the same window and
    // subtree — still reads no_data here, exactly as it would for a caller
    // whose subtree has a past shift instance still waiting to be confirmed.
    // Both are rates per worked hour this client never computes itself; it
    // only ever renders whatever `value`/`status` the board already resolved.
    final wire = boardWire(
      board: boardBody(
        pillars: [
          boardPillarJson(
            'S',
            'Safety',
            sortOrder: 1,
            kpis: [
              boardKpiJson(
                'SAF_TRIR',
                'Recordable injury rate (TRIR)',
                unit: 'per 200k hrs',
                direction: 'lower_better',
                decimalPlaces: 2,
                value: 5.71,
                status: 'red',
                targetValue: 3,
              ),
              boardKpiJson(
                'SAF_LTIFR',
                'Lost time injury frequency (LTIFR)',
                unit: 'per 1M hrs',
                direction: 'lower_better',
                decimalPlaces: 2,
                value: null,
                status: 'no_data',
              ),
              boardKpiJson(
                'SAF_INCIDENTS',
                'Safety incidents',
                unit: 'count',
                direction: 'lower_better',
                decimalPlaces: 0,
                value: 2,
                status: 'amber',
                targetValue: 0,
              ),
              boardKpiJson(
                'SAF_NEARMISS',
                'Near misses reported',
                unit: 'count',
                direction: 'higher_better',
                decimalPlaces: 0,
                value: 5,
                status: 'green',
                targetValue: 3,
              ),
              boardKpiJson(
                'SAF_OBSERVATIONS',
                'Safety observations',
                unit: 'count',
                direction: 'higher_better',
                decimalPlaces: 0,
                value: 12,
                status: 'no_target',
              ),
            ],
          ),
          boardPillarJson('Q', 'Quality', sortOrder: 2, kpis: const []),
          boardPillarJson(
            'D',
            'Delivery',
            sortOrder: 3,
            kpis: [
              boardKpiJson(
                'MNT_MTBF',
                'Mean time between failures',
                unit: 'hours',
                decimalPlaces: 1,
                value: 7,
                status: 'no_target',
              ),
            ],
          ),
          boardPillarJson('C', 'Cost', sortOrder: 4, kpis: const []),
          boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
        ],
      ),
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    // The Safety Pillar is a Pillar with data behind it, and each of its
    // measured numbers is on its own card, toned by the target the
    // definition carries.
    final safety = find.byKey(TierBoardScreen.pillarKey('S'));
    expect(safety, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('SAF_INCIDENTS'))).data,
      '2',
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('SAF_NEARMISS'))).data,
      '5',
    );
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('SAF_OBSERVATIONS'))).data,
      '12',
    );

    // SAF_TRIR is a real, measured rate now — never rendered as no data or
    // as an em dash — and its own card is toned red against its target.
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('SAF_TRIR'))).data,
      '5.71',
    );
    expect(
      find.descendant(
        of: find.byKey(TierBoardScreen.kpiKey('SAF_TRIR')),
        matching: find.text('No data'),
      ),
      findsNothing,
    );

    // SAF_LTIFR still reads no data — the board's own vocabulary for it is
    // unchanged by #233: a rate can still be `no_data` on a subtree with an
    // unconfirmed shift, exactly as one with no exposure hours at all read
    // before this ticket.
    expect(
      tester.widget<Text>(find.byKey(TierBoardScreen.kpiValueKey('SAF_LTIFR'))).data,
      '—',
    );
    expect(
      find.descendant(
        of: find.byKey(TierBoardScreen.kpiKey('SAF_LTIFR')),
        matching: find.text('No data'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('changing the Org Unit sends exactly one board request with the new orgUnitId',
      (tester) async {
    final wire = boardWire(
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    expect(wire.boardRequests.length, 1);
    expect(wire.boardRequests.single.$2, isNull);

    await tapIn(tester, find.byKey(TierBoardScreen.orgUnitFilterKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(wire.boardRequests.length, 2);
    expect(wire.boardRequests.last.$2, '10');
  });

  testWidgets('changing the period type sends exactly one board request with the new periodType',
      (tester) async {
    final wire = boardWire();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    expect(wire.boardRequests.length, 1);
    expect(wire.boardRequests.single.$3, 'day');

    await tapIn(tester, find.byKey(TierBoardScreen.periodTypeKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.text('Week').last);

    expect(wire.boardRequests.length, 2);
    expect(wire.boardRequests.last.$3, 'week');
  });

  testWidgets('the board shows placeholders in its own shape while it loads',
      (tester) async {
    final wire = boardWire()..boardGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
      settle: false,
    );

    expect(find.byKey(TierBoardScreen.loadingKey), findsOneWidget);
    expect(find.byType(SkeletonGrid), findsOneWidget);
    expect(find.byKey(TierBoardScreen.emptyKey), findsNothing);

    wire.boardGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(TierBoardScreen.loadingKey), findsNothing);
    expect(find.byKey(TierBoardScreen.pillarKey('D')), findsOneWidget);
  });

  testWidgets('a board with no Pillars says so plainly', (tester) async {
    final wire = boardWire(board: boardBody(pillars: const []));
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    expect(find.byKey(TierBoardScreen.emptyKey), findsOneWidget);
    expect(find.byKey(TierBoardScreen.failedKey), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = boardWire(boardStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/tier-board',
    );

    expect(find.byKey(TierBoardScreen.failedKey), findsOneWidget);
    expect(find.byKey(TierBoardScreen.emptyKey), findsNothing);
    expect(find.text('The tier board is unavailable.'), findsOneWidget);

    wire.boardStatus = 200;
    await tapIn(tester, find.byKey(TierBoardScreen.retryKey));

    expect(find.byKey(TierBoardScreen.failedKey), findsNothing);
    expect(find.byKey(TierBoardScreen.pillarKey('S')), findsOneWidget);
  });
}
