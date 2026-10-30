/// The KPI Module's client (ADR-0055): the catalogue, one KPI's Targets and the
/// daily KPI Review, with the wire faked — the one client seam (AGENTS.md §5).
/// Every assertion is on rendered text and widgets and on what `FakeWire`
/// recorded, never on a Bloc's state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/kpi/add_kpi_dialog.dart';
import 'package:lean_platform/kpi/change_target_dialog.dart';
import 'package:lean_platform/kpi/kpi_catalogue_screen.dart';
import 'package:lean_platform/kpi/kpi_review_screen.dart';
import 'package:lean_platform/kpi/kpi_targets_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'harness.dart';

const String _outside = "Outside the caller's granted Org Units";

final Map<String, dynamic> _oee = kpiCatalogueRowJson(
  1,
  'OEE',
  'Overall equipment effectiveness',
  unit: '%',
  decimals: 1,
  daily: kpiTargetEntryJson(target: 85),
  weekly: kpiTargetEntryJson(target: 82.5),
  monthly: kpiTargetEntryJson(target: 80),
  review: kpiReviewStateJson('met'),
);
final Map<String, dynamic> _scrap = kpiCatalogueRowJson(
  2,
  'SCRAP',
  'Scrap ratio',
  unit: '%',
  direction: '<=',
  decimals: 2,
  daily: kpiTargetEntryJson(target: 1.5),
  review: kpiReviewStateJson('missed', note: 'seal failure on line 2'),
);
final Map<String, dynamic> _mttr = kpiCatalogueRowJson(
  3,
  'MTTR',
  'Mean time to repair',
  unit: 'min',
  direction: '<',
  weekly: kpiTargetEntryJson(target: 45),
  monthly: kpiTargetEntryJson(target: 50),
);

FakeWire _wire({
  List<Map<String, dynamic>>? kpis,
  List<Map<String, dynamic>>? reviewRows,
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  int addKpiStatus = 201,
  String addKpiMessage = 'A KPI with that name already exists',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'MTU', 'MTU plant')],
      kpis: kpis ?? [_oee, _scrap, _mttr],
      kpiTargets: {
        3: kpiTargetsJson(
          _mttr,
          current: [kpiCurrentTargetJson('Weekly', 45, validFrom: '2026-02-01')],
          history: [
            kpiHistoryEntryJson(12, 'Monthly', '2026-03-01', 50, note: 'after the retrofit'),
            kpiHistoryEntryJson(11, 'Weekly', '2026-02-01', 45, appUser: 'C D'),
          ],
        ),
      },
      kpiReviewRows: reviewRows ??
          [
            kpiReviewRowJson(1, 'Overall equipment effectiveness', unit: '%', target: 85),
            kpiReviewRowJson(2, 'Scrap ratio', unit: '%', direction: '<=', target: 1.5),
            kpiReviewRowJson(3, 'Mean time to repair', unit: 'min', direction: '<'),
          ],
      kpiAddKpiStatus: addKpiStatus,
      kpiAddKpiMessage: addKpiMessage,
    );

Future<void> _open(WidgetTester tester, FakeWire wire, String location) async {
  // Tall enough that nothing in a Screen is below the fold of a lazy list.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

bool _enabled(WidgetTester tester, Key key) => tester.widget<FilledButton>(find.byKey(key)).onPressed != null;

Future<void> _fillAddKpi(WidgetTester tester, {String title = 'Overall equipment effectiveness'}) async {
  await tester.enterText(find.byKey(AddKpiDialog.nameKey), 'OEE');
  await tester.enterText(find.byKey(AddKpiDialog.titleKey), title);
  await tester.enterText(find.byKey(AddKpiDialog.unitKey), '%');
  await tester.enterText(find.byKey(AddKpiDialog.decimalsKey), '1');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the catalogue table renders every KPI the API returned', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpi);

    expect(find.byType(KpiCatalogueScreen), findsOneWidget);
    for (final text in [
      'OEE', 'Overall equipment effectiveness',
      'SCRAP', 'Scrap ratio',
      'MTTR', 'Mean time to repair',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // A target renders `direction target(decimals) unit`.
    expect(find.text('>= 85.0 %'), findsOneWidget);
    expect(find.text('>= 82.5 %'), findsOneWidget);
    expect(find.text('>= 80.0 %'), findsOneWidget);
    expect(find.text('<= 1.50 %'), findsOneWidget);
    expect(find.text('< 45 min'), findsOneWidget);
    expect(find.text('< 50 min'), findsOneWidget);
    // MTTR has no Daily Target, SCRAP no Weekly or Monthly one: `—` each.
    expect(
      find.descendant(of: find.byKey(KpiCatalogueScreen.rowKey(3)), matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(KpiCatalogueScreen.rowKey(2)), matching: find.text('—')),
      findsNWidgets(2),
    );
    // Today's review state, the server's day.
    expect(find.text('Met'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Not reviewed'), findsOneWidget);
    expect(
      wire.kpiReads.single.queryParameters,
      {'site_id': '1'},
      reason: 'no date: "today" is the Site\'s, from the server',
    );
  });

  testWidgets('a KPI row opens its Targets Screen', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpi);

    await tapIn(tester, find.byKey(KpiCatalogueScreen.rowKey(3)));

    expect(find.byType(KpiTargetsScreen), findsOneWidget);
    expect(find.text('MTTR · Mean time to repair'), findsOneWidget);
    expect(find.text('Weekly: < 45 min (from 2026-02-01)'), findsOneWidget);
    expect(find.text('after the retrofit'), findsOneWidget);
    expect(find.text('C D'), findsOneWidget);
    expect(find.text('2026-10-30 08:12'), findsNWidgets(2));
    final targetReads = wire.kpiReads.where((uri) => uri.path == '/api/kpi/targets').toList();
    expect(targetReads, hasLength(1));
    expect(targetReads.single.queryParameters, {'site_id': '1', 'kpi_id': '3'});
  });

  testWidgets('a KPI with no Target in any grain says none is in force', (tester) async {
    final wire = _wire();
    wire.kpiTargets[2] = kpiTargetsJson(
      _scrap,
      current: [
        for (final grain in ['Daily', 'Weekly', 'Monthly']) kpiCurrentTargetJson(grain, null, validFrom: null),
      ],
    );
    await _open(tester, wire, Routes.kpiTargets(2));

    expect(find.byType(KpiTargetsScreen), findsOneWidget);
    expect(find.text('No Target is in force today.'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
    for (final grain in ['Daily', 'Weekly', 'Monthly']) {
      expect(find.byKey(KpiTargetsScreen.currentRowKey(grain)), findsNothing, reason: grain);
    }
  });

  testWidgets('a grain with no Target is not listed beside one that has a Target', (tester) async {
    final wire = _wire();
    wire.kpiTargets[3] = kpiTargetsJson(
      _mttr,
      current: [
        kpiCurrentTargetJson('Daily', null, validFrom: null),
        kpiCurrentTargetJson('Weekly', 45, validFrom: '2026-02-01'),
      ],
    );
    await _open(tester, wire, Routes.kpiTargets(3));

    expect(find.text('Weekly: < 45 min (from 2026-02-01)'), findsOneWidget);
    expect(find.byKey(KpiTargetsScreen.currentRowKey('Weekly')), findsOneWidget);
    expect(find.byKey(KpiTargetsScreen.currentRowKey('Daily')), findsNothing);
    expect(find.textContaining('Daily:'), findsNothing);
    expect(find.text('No Target is in force today.'), findsNothing);
  });

  testWidgets('Add KPI validates and posts the exact body', (tester) async {
    final wire = _wire(kpis: []);
    await _open(tester, wire, Routes.kpi);

    await tapIn(tester, find.byKey(KpiCatalogueScreen.addKpiKey));
    expect(_enabled(tester, AddKpiDialog.submitKey), isFalse);

    // A blank title keeps Add disabled.
    await _fillAddKpi(tester, title: '   ');
    expect(_enabled(tester, AddKpiDialog.submitKey), isFalse);

    // So does a Decimals value that is not a whole number from 0 to 6.
    await tester.enterText(find.byKey(AddKpiDialog.titleKey), 'Overall equipment effectiveness');
    await tester.enterText(find.byKey(AddKpiDialog.decimalsKey), '7');
    await tester.pumpAndSettle();
    expect(_enabled(tester, AddKpiDialog.submitKey), isFalse);
    expect(find.text('Decimals must be a whole number from 0 to 6'), findsOneWidget);

    await tester.enterText(find.byKey(AddKpiDialog.decimalsKey), '1');
    await tester.pumpAndSettle();
    expect(_enabled(tester, AddKpiDialog.submitKey), isTrue);

    await tapIn(tester, find.byKey(AddKpiDialog.submitKey));

    expect(wire.requests.where((request) => request == 'POST /api/kpi/catalogue'), hasLength(1));
    expect(wire.kpiPosts, [
      {
        'site_id': '1',
        'kpi': 'OEE',
        'title': 'Overall equipment effectiveness',
        'unit': '%',
        'direction': '>=',
        'decimals': 1,
        'value_measure': null,
      },
    ]);
    // The dialog closed and the catalogue was read again, showing the server's KPI.
    expect(find.byKey(AddKpiDialog.submitKey), findsNothing);
    expect(find.text('OEE'), findsOneWidget);
  });

  testWidgets('the Change Target dialog refuses a date before the Site\'s today', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiTargets(3));

    await tapIn(tester, find.byKey(KpiTargetsScreen.changeTargetKey));
    expect(find.text(ChangeTargetDialog.rule), findsOneWidget);
    // The date is the Site's today (the server's `review_date`), and says so.
    expect(tester.widget<TextField>(find.byKey(ChangeTargetDialog.validFromKey)).controller!.text, '2026-10-30');
    expect(find.textContaining('Today at this Site is 2026-10-30'), findsOneWidget);

    // The picker's earliest day is that today: the day before is out of range.
    await pickDate(tester, ChangeTargetDialog.validFromKey, DateTime(2026, 10, 29));
    expect(find.text('Out of range.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();

    // The field kept today, and nothing reached the wire.
    expect(tester.widget<TextField>(find.byKey(ChangeTargetDialog.validFromKey)).controller!.text, '2026-10-30');
    expect(wire.targetPosts, isEmpty);
    expect(wire.requests, isNot(contains('POST /api/kpi/targets')));
  });

  testWidgets('a blank target is sent as target: null', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiTargets(3));

    await tapIn(tester, find.byKey(KpiTargetsScreen.changeTargetKey));
    await tapIn(tester, find.byKey(ChangeTargetDialog.grainKey));
    await tapIn(tester, find.text('Weekly').last);
    expect(_enabled(tester, ChangeTargetDialog.submitKey), isTrue);
    await tapIn(tester, find.byKey(ChangeTargetDialog.submitKey));

    expect(wire.targetPosts, hasLength(1));
    final body = wire.targetPosts.single;
    expect(body, containsPair('target', null));
    expect(body.containsKey('target'), isTrue);
    expect(body, containsPair('grain', 'Weekly'));
    expect(body, containsPair('valid_from', '2026-10-30'));
    expect(body, containsPair('kpi_id', 3));
    expect(body, containsPair('site_id', '1'));
    expect(find.byKey(ChangeTargetDialog.submitKey), findsNothing);
  });

  testWidgets("the Review Screen refuses a Missed row's short note and enables Save at 10", (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    expect(find.text('KPI Review for 2026-10-30'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse, reason: 'nothing changed yet');

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    // The note area names the Target that was missed.
    expect(find.text('Why was the Target (>= 85 %) missed?'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);

    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'broken');
    await tester.pumpAndSettle();
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);
    expect(find.textContaining('at least 10 characters'), findsOneWidget);

    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'broken seal');
    await tester.pumpAndSettle();
    expect(_enabled(tester, KpiReviewScreen.saveKey), isTrue);

    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));

    expect(wire.reviewPosts, hasLength(1));
    expect(wire.reviewPosts.single, containsPair('site_id', '1'));
    expect(wire.reviewPosts.single, containsPair('date', '2026-10-30'));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'missed', 'observed': null, 'note': 'broken seal'},
    ]);
    // Read again: the saved state shown is the server's, and Save is spent.
    expect(find.byKey(KpiReviewScreen.savedKey), findsOneWidget);
    expect(find.text('Missed · A B · 2026-10-30 08:12'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);
  });

  testWidgets('a 403 from the API renders the refusal sentence', (tester) async {
    final wire = _wire(addKpiStatus: 403, addKpiMessage: _outside);
    await _open(tester, wire, Routes.kpi);

    await tapIn(tester, find.byKey(KpiCatalogueScreen.addKpiKey));
    await _fillAddKpi(tester);
    await tapIn(tester, find.byKey(AddKpiDialog.submitKey));

    expect(find.text(_outside), findsOneWidget);
    expect(find.byKey(AddKpiDialog.failureKey), findsOneWidget);
    expect(find.textContaining('KpiApiException'), findsNothing);
    expect(find.textContaining('403'), findsNothing);
    // The dialog stayed open for another try.
    expect(find.byKey(AddKpiDialog.submitKey), findsOneWidget);
  });

  test('the KPI Destinations are filtered by role', () {
    for (final role in [Roles.supervisor, Roles.engineer, Roles.manager, Roles.admin]) {
      final paths = destinationsFor(role: role).map((d) => d.path).toSet();
      expect(paths, containsAll([Routes.kpi, Routes.kpiReview]), reason: role);
    }
    final operator = destinationsFor(role: Roles.operator).map((d) => d.path).toSet();
    expect(operator, isNot(contains(Routes.kpi)));
    expect(operator, isNot(contains(Routes.kpiReview)));

    final all = destinationsFor(role: Roles.manager);
    for (final path in [Routes.kpi, Routes.kpiReview]) {
      expect(all.singleWhere((d) => d.path == path).group, DestinationGroupNames.insights);
    }
    expect(selectedDestinationPath(all, '/kpi/review'), '/kpi/review');
    expect(selectedDestinationPath(all, '/kpi/7/targets'), '/kpi');
    expect(selectedDestinationPath(all, '/kpi'), '/kpi');
  });

  testWidgets('a KPI with no Target is still reviewable', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    expect(find.byKey(KpiReviewScreen.noTargetHintKey(3)), findsOneWidget);
    expect(find.text('No target — set one first'), findsOneWidget);
    expect(find.byKey(KpiReviewScreen.noTargetHintKey(1)), findsNothing);

    ChoiceChip chip(String status) =>
        tester.widget<ChoiceChip>(find.byKey(KpiReviewScreen.statusKey(3, status)));
    expect(chip('met').onSelected, isNull, reason: 'Met is disabled');
    expect(chip('missed').onSelected, isNotNull);
    expect(chip('not_measured').onSelected, isNotNull);

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(3, 'not_measured')));
    expect(_enabled(tester, KpiReviewScreen.saveKey), isTrue);
    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));

    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 3, 'status': 'not_measured', 'observed': null, 'note': null},
    ]);
    expect(find.text('Not measured · A B · 2026-10-30 08:12'), findsOneWidget);
  });

  testWidgets('the Review date picker opens a past day, never later than the Site\'s today',
      (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    await pickDate(tester, KpiReviewScreen.dateKey, DateTime(2026, 10, 29));

    expect(find.text('KPI Review for 2026-10-29'), findsOneWidget);
    expect(wire.kpiReads.last.path, '/api/kpi/review');
    expect(wire.kpiReads.last.queryParameters, {'site_id': '1', 'date': '2026-10-29'});

    // Tomorrow is out of range, and the way forward to today is still open.
    await pickDate(tester, KpiReviewScreen.dateKey, DateTime(2026, 10, 31));
    expect(find.text('Out of range.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    await pickDate(tester, KpiReviewScreen.dateKey, DateTime(2026, 10, 30));
    expect(find.text('KPI Review for 2026-10-30'), findsOneWidget);
  });

  testWidgets('a read failure renders the API\'s own sentence, with a retry', (tester) async {
    final wire = _wire();
    wire.kpiCatalogueStatus = 503;
    wire.kpiCatalogueMessage = 'The KPI catalogue is not set up on this deployment';
    await _open(tester, wire, Routes.kpi);

    expect(find.byKey(KpiCatalogueScreen.failedKey), findsOneWidget);
    expect(find.text('The KPI catalogue is not set up on this deployment'), findsOneWidget);

    wire.kpiCatalogueStatus = 200;
    await tapIn(tester, find.byKey(KpiCatalogueScreen.retryKey));
    expect(find.byKey(KpiCatalogueScreen.failedKey), findsNothing);
    expect(find.text('OEE'), findsOneWidget);
  });

  testWidgets('without write authority there is no Add KPI and no Change Target', (tester) async {
    final wire = _wire(role: Roles.supervisor, orgUnitScope: {'everywhere': false, 'grants': const <dynamic>[]});
    await _open(tester, wire, Routes.kpi);
    expect(find.byKey(KpiCatalogueScreen.addKpiKey), findsNothing);

    await tapIn(tester, find.byKey(KpiCatalogueScreen.rowKey(3)));
    expect(find.byType(KpiTargetsScreen), findsOneWidget);
    expect(find.byKey(KpiTargetsScreen.changeTargetKey), findsNothing);
  });
}
