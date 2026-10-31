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
import 'package:lean_platform/widgets/app_date_field.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/empty_state.dart';
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
  List<Map<String, dynamic>>? sites,
  Map<String, dynamic>? orgUnitScope,
  int addKpiStatus = 201,
  String addKpiMessage = 'A KPI with that name already exists',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'MTU', 'MTU plant')],
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

Future<void> _open(
  WidgetTester tester,
  FakeWire wire,
  String location, {
  Size size = const Size(1200, 1600),
}) async {
  // Tall enough that nothing in a Screen is below the fold of a lazy list.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

bool _enabled(WidgetTester tester, Key key) => tester.widget<FilledButton>(find.byKey(key)).onPressed != null;

IconButton _icon(WidgetTester tester, int kpiId, String status) =>
    tester.widget<IconButton>(find.byKey(KpiReviewScreen.statusKey(kpiId, status)));

/// The icon a judgement button draws right now.
IconData? _glyph(WidgetTester tester, int kpiId, String status) => (_icon(tester, kpiId, status).icon as Icon).icon;

/// [count] KPIs, ids from 1, each with a Target, so every cell is the same height.
List<Map<String, dynamic>> _targetedRows(int count) => [
      for (var id = 1; id <= count; id++) kpiReviewRowJson(id, 'KPI $id', unit: '%', target: 85),
    ];

/// Where the first [count] KPI cells landed, in order.
List<Rect> _cellRects(WidgetTester tester, int count) => [
      for (var id = 1; id <= count; id++) tester.getRect(find.byKey(KpiReviewScreen.rowKey(id))),
    ];

/// Chooses Missed for [kpiId], writes [note] in the popup and confirms it.
Future<void> _missWith(WidgetTester tester, int kpiId, String note) async {
  await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(kpiId, 'missed')));
  await tester.enterText(find.byKey(KpiReviewScreen.noteKey(kpiId)), note);
  await tester.pumpAndSettle();
  await tapIn(tester, find.byKey(KpiReviewScreen.noteSaveKey(kpiId)));
}

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

  testWidgets('each KPI cell shows its three judgement icons, none chosen before a Review', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);

    for (final id in [1, 2, 3]) {
      expect(_glyph(tester, id, 'met'), Icons.check_circle_outline, reason: 'KPI $id');
      expect(_glyph(tester, id, 'missed'), Icons.cancel_outlined, reason: 'KPI $id');
      expect(_glyph(tester, id, 'not_measured'), Icons.remove_circle_outline, reason: 'KPI $id');
    }
    expect(_icon(tester, 1, 'met').tooltip, 'Met');
    expect(_icon(tester, 1, 'missed').tooltip, 'Missed');
    expect(_icon(tester, 1, 'not_measured').tooltip, 'Not measured');
    expect(find.text('Daily target: >= 85 %'), findsOneWidget);
    expect(find.text('Daily target: <= 1.5 %'), findsOneWidget);
    expect(find.text('No target'), findsOneWidget);
    expect(find.byKey(KpiReviewScreen.notePopupKey(1)), findsNothing, reason: 'no note yet');
  });

  testWidgets('the chosen icon is filled and coloured by its own meaning, the rest outline', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);
    final context = tester.element(find.byKey(KpiReviewScreen.rowKey(1)));
    final colors = Theme.of(context).colorScheme;

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'met')));
    expect(_glyph(tester, 1, 'met'), Icons.check_circle);
    expect(_icon(tester, 1, 'met').color, colors.primary);
    expect(_icon(tester, 1, 'met').isSelected, isTrue);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel_outlined);
    expect(_glyph(tester, 1, 'not_measured'), Icons.remove_circle_outline);

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'not_measured')));
    expect(_glyph(tester, 1, 'met'), Icons.check_circle_outline);
    expect(_glyph(tester, 1, 'not_measured'), Icons.remove_circle);
    expect(_icon(tester, 1, 'not_measured').color, colors.onSurfaceVariant);

    await _missWith(tester, 1, 'broken seal on line');
    expect(_glyph(tester, 1, 'not_measured'), Icons.remove_circle_outline);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel);
    expect(_icon(tester, 1, 'missed').color, colors.error);
  });

  testWidgets("choosing Missed opens the popup, which refuses a short note, and Save holds until it's confirmed",
      (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    expect(find.text('KPI Review for 2026-10-30'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse, reason: 'nothing changed yet');

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    expect(find.byKey(KpiReviewScreen.noteDialogKey(1)), findsOneWidget);
    // The popup names the Target that was missed.
    expect(find.text('Why was the Target (>= 85 %) missed?'), findsOneWidget);
    expect(
      find.text('A note of at least 10 characters is required when a KPI is missed (0 so far).'),
      findsOneWidget,
    );
    expect(_enabled(tester, KpiReviewScreen.noteSaveKey(1)), isFalse);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);

    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'broken');
    await tester.pumpAndSettle();
    expect(find.textContaining('(6 so far)'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.noteSaveKey(1)), isFalse);

    // Ten characters only with the padding: it counts after trimming.
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), '   broken   ');
    await tester.pumpAndSettle();
    expect(find.textContaining('(6 so far)'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.noteSaveKey(1)), isFalse);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);

    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), '  broken seal ');
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 10 characters'), findsNothing);
    expect(_enabled(tester, KpiReviewScreen.noteSaveKey(1)), isTrue);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse, reason: 'not drafted until confirmed');

    await tapIn(tester, find.byKey(KpiReviewScreen.noteSaveKey(1)));
    expect(find.byKey(KpiReviewScreen.noteDialogKey(1)), findsNothing);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isTrue);
    expect(wire.reviewPosts, isEmpty, reason: 'the popup keeps a draft; only Save posts');

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

  testWidgets('a popup with no Target to name asks why it was missed', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);
    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(3, 'missed')));
    expect(find.text('Why was it missed?'), findsOneWidget);
  });

  testWidgets('Save posts every changed KPI in one request', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'met')));
    await _missWith(tester, 2, 'seal failure on line 2');
    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(3, 'not_measured')));
    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));

    expect(wire.reviewPosts, hasLength(1));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'met', 'observed': null, 'note': null},
      {'kpi_id': 2, 'status': 'missed', 'observed': null, 'note': 'seal failure on line 2'},
      {'kpi_id': 3, 'status': 'not_measured', 'observed': null, 'note': null},
    ]);
  });

  testWidgets('cancelling the popup leaves a saved judgement and its note as they were', (tester) async {
    final wire = _wire(
      reviewRows: [
        kpiReviewRowJson(1, 'Overall equipment effectiveness', unit: '%', target: 85, status: 'met'),
      ],
    );
    await _open(tester, wire, Routes.kpiReview);

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'broken seal on line');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCancelKey(1)));

    expect(find.byKey(KpiReviewScreen.noteDialogKey(1)), findsNothing);
    expect(_glyph(tester, 1, 'met'), Icons.check_circle);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel_outlined);
    expect(find.byKey(KpiReviewScreen.notePopupKey(1)), findsNothing);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);
  });

  testWidgets('cancelling the popup leaves an earlier draft as it was, and Save posts that', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'not_measured')));
    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'short');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCancelKey(1)));

    expect(_glyph(tester, 1, 'not_measured'), Icons.remove_circle);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel_outlined);
    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'not_measured', 'observed': null, 'note': null},
    ]);
  });

  testWidgets('cancelling an edit keeps the note already drafted', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);
    await _missWith(tester, 1, 'broken seal on line');

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    expect(tester.widget<TextField>(find.byKey(KpiReviewScreen.noteKey(1))).controller!.text, 'broken seal on line');
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'x');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCancelKey(1)));

    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'missed', 'observed': null, 'note': 'broken seal on line'},
    ]);
  });

  final missedRow = kpiReviewRowJson(
    1,
    'Overall equipment effectiveness',
    unit: '%',
    target: 85,
    status: 'missed',
    note: 'seal failure on line 2',
    appUser: 'C D',
    enteredAt: '2026-10-30T08:12:00',
  );

  testWidgets('a saved note opens in the read-only popup with its Target and author', (tester) async {
    await _open(tester, _wire(reviewRows: [missedRow]), Routes.kpiReview);
    expect(find.text('seal failure on line 2'), findsNothing, reason: 'a note lives in its popup');

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));

    final popup = find.byKey(KpiReviewScreen.noteReadDialogKey(1));
    expect(popup, findsOneWidget);
    expect(find.descendant(of: popup, matching: find.text('seal failure on line 2')), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.text('Daily target: >= 85 %')), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.text('C D · 2026-10-30 08:12')), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.byType(TextField)), findsNothing);

    await tapIn(tester, find.byKey(KpiReviewScreen.noteCloseKey(1)));
    expect(popup, findsNothing);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);
  });

  testWidgets('a Missed note is edited from its read-only popup, and the draft names no author', (tester) async {
    final wire = _wire(reviewRows: [missedRow]);
    await _open(tester, wire, Routes.kpiReview);

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    await tapIn(tester, find.byKey(KpiReviewScreen.noteEditKey(1)));
    expect(find.byKey(KpiReviewScreen.noteReadDialogKey(1)), findsNothing);
    expect(find.byKey(KpiReviewScreen.noteDialogKey(1)), findsOneWidget);
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'the seal failed again');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiReviewScreen.noteSaveKey(1)));

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    final popup = find.byKey(KpiReviewScreen.noteReadDialogKey(1));
    expect(find.descendant(of: popup, matching: find.text('the seal failed again')), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.textContaining('C D')), findsNothing);
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCloseKey(1)));

    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'missed', 'observed': null, 'note': 'the seal failed again'},
    ]);
  });

  testWidgets('a note that is no longer Missed reads without an Edit button', (tester) async {
    await _open(tester, _wire(reviewRows: [missedRow]), Routes.kpiReview);
    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'not_measured')));

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    expect(find.byKey(KpiReviewScreen.noteReadDialogKey(1)), findsOneWidget);
    expect(find.byKey(KpiReviewScreen.noteEditKey(1)), findsNothing);
  });

  testWidgets('a note that Save will clear says so, and a Missed note does not', (tester) async {
    await _open(tester, _wire(reviewRows: [missedRow]), Routes.kpiReview);

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    expect(find.byKey(KpiReviewScreen.noteClearsKey(1)), findsNothing, reason: 'Save keeps a Missed note');
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCloseKey(1)));

    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'met')));
    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));

    final popup = find.byKey(KpiReviewScreen.noteReadDialogKey(1));
    expect(
      find.descendant(of: popup, matching: find.byKey(KpiReviewScreen.noteClearsKey(1))),
      findsOneWidget,
      reason: 'Met posts no note, so Save will clear this one',
    );
    expect(find.descendant(of: popup, matching: find.text(KpiReviewScreen.clearsNoteText)), findsOneWidget);
    expect(find.descendant(of: popup, matching: find.text('seal failure on line 2')), findsOneWidget, reason: 'the note itself stays readable');
    expect(find.byKey(KpiReviewScreen.noteEditKey(1)), findsNothing, reason: 'only a Missed note is edited');
  });

  testWidgets('without write authority the Review is read-only, and a note still opens', (tester) async {
    final wire = _wire(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': const <dynamic>[]},
      reviewRows: [missedRow],
    );
    await _open(tester, wire, Routes.kpiReview);
    final context = tester.element(find.byKey(KpiReviewScreen.rowKey(1)));

    for (final status in ['met', 'missed', 'not_measured']) {
      expect(_icon(tester, 1, status).onPressed, isNull, reason: status);
    }
    // What was judged stays readable: filled, in its own colour.
    expect(_glyph(tester, 1, 'missed'), Icons.cancel);
    expect(_icon(tester, 1, 'missed').disabledColor, Theme.of(context).colorScheme.error);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);

    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    expect(find.text('seal failure on line 2'), findsOneWidget);
    expect(find.byKey(KpiReviewScreen.noteEditKey(1)), findsNothing);
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

    expect(_icon(tester, 3, 'met').onPressed, isNull, reason: 'Met is disabled');
    expect(_icon(tester, 3, 'missed').onPressed, isNotNull);
    expect(_icon(tester, 3, 'not_measured').onPressed, isNotNull);

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

  testWidgets('with no date the Review shows the last working day and the picker ends at the Site\'s today',
      (tester) async {
    final wire = _wire()
      ..kpiSiteToday = '2026-10-30'
      ..kpiReviewDate = '2026-10-29';
    await _open(tester, wire, Routes.kpiReview);

    expect(find.text('KPI Review for 2026-10-29'), findsOneWidget);
    expect(find.text('Overall equipment effectiveness'), findsOneWidget);
    expect(
      tester
          .widget<AppDateField>(find.ancestor(of: find.byKey(KpiReviewScreen.dateKey), matching: find.byType(AppDateField)))
          .lastDate,
      DateTime(2026, 10, 30),
    );

    await pickDate(tester, KpiReviewScreen.dateKey, DateTime(2026, 10, 30));

    expect(wire.kpiReads.last.queryParameters, {'site_id': '1', 'date': '2026-10-30'});
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

  const catalogueColumns = ['KPI', 'Unit', 'Direction', 'Daily', 'Weekly', 'Monthly', 'Today'];

  List<String> headerLabels(WidgetTester tester, Key headerRowKey) => [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byKey(headerRowKey), matching: find.byType(Text)),
        ))
          text.data!,
      ];

  testWidgets('the catalogue matrix labels its columns, in order', (tester) async {
    await _open(tester, _wire(), Routes.kpi);
    expect(headerLabels(tester, KpiCatalogueScreen.headerRowKey), catalogueColumns);
  });

  testWidgets('a header label and its cells start at the same x, on /kpi', (tester) async {
    await _open(tester, _wire(), Routes.kpi);
    for (final column in catalogueColumns) {
      final header = tester.getTopLeft(
        find.descendant(
          of: find.byKey(KpiCatalogueScreen.columnHeaderKey(column)),
          matching: find.byType(Text),
        ),
      );
      final cell = tester.getTopLeft(find.byKey(KpiCatalogueScreen.cellKey(1, column)));
      // Equality, not "a row renders": a header that drifts from its column renders fine.
      expect((header.dx - cell.dx).abs(), lessThan(1.0), reason: '$column header ${header.dx} cell ${cell.dx}');
    }
  });

  testWidgets('the catalogue filter folds diacritics and clears', (tester) async {
    final hs = kpiCatalogueRowJson(4, 'HS', 'Hiệu suất');
    final wire = _wire(kpis: [_oee, _scrap, _mttr, hs]);
    await _open(tester, wire, Routes.kpi);
    expect(find.byKey(KpiCatalogueScreen.filterCountKey), findsNothing);

    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'hieu suat');
    await tester.pumpAndSettle();

    expect(find.byKey(KpiCatalogueScreen.rowKey(4)), findsOneWidget);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(KpiCatalogueScreen.rowKey(id)), findsNothing, reason: 'KPI $id');
    }
    expect(find.text(AppFilterField.countLabel(1, 4)), findsOneWidget);

    // By code, case-insensitively.
    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'oee');
    await tester.pumpAndSettle();
    expect(find.byKey(KpiCatalogueScreen.rowKey(1)), findsOneWidget);
    expect(find.byKey(KpiCatalogueScreen.rowKey(4)), findsNothing);

    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'hieu suat');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiCatalogueScreen.filterClearKey));
    for (final id in [1, 2, 3, 4]) {
      expect(find.byKey(KpiCatalogueScreen.rowKey(id)), findsOneWidget, reason: 'KPI $id');
    }
    expect(find.byKey(KpiCatalogueScreen.filterCountKey), findsNothing);
    // The filter is the client's: it asked the server for nothing more.
    expect(wire.kpiReads, hasLength(1));
  });

  testWidgets('typing in the filter keeps the caret at the end of the term', (tester) async {
    await _open(tester, _wire(), Routes.kpi);
    final field = find.byKey(KpiCatalogueScreen.filterFieldKey);

    await tester.enterText(field, 'hie');
    await tester.pump();
    await tester.enterText(field, 'hieu');
    await tester.pump();

    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'hieu');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('a term matching nothing is the none-matched state, on /kpi', (tester) async {
    await _open(tester, _wire(), Routes.kpi);
    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'zzqx');
    await tester.pumpAndSettle();
    final empty = tester.widget<PlatformEmptyState>(find.byKey(KpiCatalogueScreen.noMatchKey));
    expect(empty.variant, EmptyStateVariant.noneMatched);
    expect(empty.message, contains('"zzqx"'));
    expect(find.byKey(KpiCatalogueScreen.emptyKey), findsNothing);
  });

  testWidgets('a term matching nothing is the none-matched state, on /kpi/review', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);
    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'zzqx');
    await tester.pumpAndSettle();
    final empty = tester.widget<PlatformEmptyState>(find.byKey(KpiReviewScreen.noMatchKey));
    expect(empty.variant, EmptyStateVariant.noneMatched);
    expect(empty.message, contains('"zzqx"'));
    expect(find.byKey(KpiReviewScreen.emptyKey), findsNothing);
  });

  testWidgets('a changed row the filter hides is still saved', (tester) async {
    final wire = _wire();
    await _open(tester, wire, Routes.kpiReview);

    await _missWith(tester, 1, 'broken seal on line');

    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();
    expect(find.byKey(KpiReviewScreen.rowKey(1)), findsNothing);
    expect(find.byKey(KpiReviewScreen.rowKey(2)), findsOneWidget);
    expect(find.text('1 changed KPI is hidden by the search.'), findsOneWidget);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isTrue);

    // The draft survived: clearing the term shows the edit, not the server's value.
    await tapIn(tester, find.byKey(KpiReviewScreen.filterClearKey));
    expect(find.byKey(KpiReviewScreen.hiddenChangesKey), findsNothing);
    expect(_glyph(tester, 1, 'missed'), Icons.cancel);
    await tapIn(tester, find.byKey(KpiReviewScreen.notePopupKey(1)));
    expect(find.text('broken seal on line'), findsOneWidget);
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCloseKey(1)));

    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(KpiReviewScreen.saveKey));
    expect(wire.reviewPosts.single['entries'], [
      {'kpi_id': 1, 'status': 'missed', 'observed': null, 'note': 'broken seal on line'},
    ]);
  });

  final twoSites = [siteJson('1', 'MTU', 'MTU plant'), siteJson('2', 'DN', 'Da Nang')];

  String filterText(WidgetTester tester, Key fieldKey) => tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;

  testWidgets('the review filter term survives a day change', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);
    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();

    await pickDate(tester, KpiReviewScreen.dateKey, DateTime(2026, 10, 29));

    expect(find.text('KPI Review for 2026-10-29'), findsOneWidget);
    expect(filterText(tester, KpiReviewScreen.filterFieldKey), 'scrap');
    expect(find.byKey(KpiReviewScreen.rowKey(2)), findsOneWidget);
    expect(find.byKey(KpiReviewScreen.rowKey(1)), findsNothing);
    expect(find.text(AppFilterField.countLabel(1, 3)), findsOneWidget);
  });

  testWidgets('a Site change clears the review filter term', (tester) async {
    await _open(tester, _wire(sites: twoSites), Routes.kpiReview);
    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();
    expect(find.byKey(KpiReviewScreen.rowKey(1)), findsNothing);

    await tapIn(tester, find.byKey(KpiReviewScreen.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(filterText(tester, KpiReviewScreen.filterFieldKey), isEmpty);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(KpiReviewScreen.rowKey(id)), findsOneWidget, reason: 'KPI $id');
    }
    expect(find.byKey(KpiReviewScreen.filterCountKey), findsNothing);
  });

  testWidgets('a Site change clears the catalogue filter term', (tester) async {
    await _open(tester, _wire(sites: twoSites), Routes.kpi);
    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();
    expect(find.byKey(KpiCatalogueScreen.rowKey(1)), findsNothing);

    await tapIn(tester, find.byKey(KpiCatalogueScreen.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(filterText(tester, KpiCatalogueScreen.filterFieldKey), isEmpty);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(KpiCatalogueScreen.rowKey(id)), findsOneWidget, reason: 'KPI $id');
    }
    expect(find.byKey(KpiCatalogueScreen.filterCountKey), findsNothing);
  });

  // A short note can no longer become a draft, so what the filter could hide is
  // gone with it: the popup refuses the note, and cancelling it changes nothing.
  testWidgets('a refused short note leaves no changed KPI for the filter to hide', (tester) async {
    await _open(tester, _wire(), Routes.kpiReview);
    await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
    await tester.enterText(find.byKey(KpiReviewScreen.noteKey(1)), 'short');
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 10 characters'), findsOneWidget);
    await tapIn(tester, find.byKey(KpiReviewScreen.noteCancelKey(1)));

    await tester.enterText(find.byKey(KpiReviewScreen.filterFieldKey), 'scrap');
    await tester.pumpAndSettle();
    expect(find.byKey(KpiReviewScreen.hiddenChangesKey), findsNothing);
    expect(_enabled(tester, KpiReviewScreen.saveKey), isFalse);
  });

  testWidgets('an uppercase diacritic term folds', (tester) async {
    final hs = kpiCatalogueRowJson(4, 'HS', 'Hiệu suất');
    await _open(tester, _wire(kpis: [_oee, _scrap, _mttr, hs]), Routes.kpi);

    await tester.enterText(find.byKey(KpiCatalogueScreen.filterFieldKey), 'HIỆU SUẤT');
    await tester.pumpAndSettle();

    expect(find.byKey(KpiCatalogueScreen.rowKey(4)), findsOneWidget);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(KpiCatalogueScreen.rowKey(id)), findsNothing, reason: 'KPI $id');
    }
  });

  for (final size in [const Size(1366, 768), const Size(700, 768)]) {
    testWidgets('/kpi renders without overflow at ${size.width.toInt()}px', (tester) async {
      await _open(tester, _wire(), Routes.kpi, size: size);
      expect(find.byKey(KpiCatalogueScreen.headerRowKey), findsOneWidget);
      expect(find.byKey(KpiCatalogueScreen.rowKey(1)), findsOneWidget);
    });

    testWidgets('/kpi/review renders without overflow at ${size.width.toInt()}px', (tester) async {
      await _open(tester, _wire(), Routes.kpiReview, size: size);
      for (final id in [1, 2, 3]) {
        expect(find.byKey(KpiReviewScreen.rowKey(id)), findsOneWidget, reason: 'KPI $id');
      }
      // The widest state: Missed opens the popup, with its inline error.
      await tapIn(tester, find.byKey(KpiReviewScreen.statusKey(1, 'missed')));
      expect(find.byKey(KpiReviewScreen.noteKey(1)), findsOneWidget);
    });
  }

  testWidgets('at 1400px the KPI cells tile four across and the fifth starts the second row', (tester) async {
    await _open(tester, _wire(reviewRows: _targetedRows(5)), Routes.kpiReview, size: const Size(1400, 1600));
    final cells = _cellRects(tester, 5);

    for (final i in [1, 2, 3]) {
      expect(cells[i].top, cells[0].top, reason: 'cell ${i + 1} shares the first row');
      expect(cells[i].left, greaterThan(cells[i - 1].right), reason: 'cell ${i + 1} sits right of cell $i');
      expect(cells[i].width, cells[0].width, reason: 'cell ${i + 1} is as wide as the first');
    }
    for (final i in [0, 1, 2, 3]) {
      expect(cells[4].top, greaterThan(cells[i].bottom), reason: 'the fifth cell starts the second row');
    }
    expect(cells[4].left, cells[0].left, reason: 'the second row starts at the first column');
  });

  testWidgets('at 1200px the KPI cells tile three across and the fourth starts the second row', (tester) async {
    await _open(tester, _wire(reviewRows: _targetedRows(4)), Routes.kpiReview, size: const Size(1200, 1600));
    final cells = _cellRects(tester, 4);

    for (final i in [1, 2]) {
      expect(cells[i].top, cells[0].top, reason: 'cell ${i + 1} shares the first row');
      expect(cells[i].left, greaterThan(cells[i - 1].right), reason: 'cell ${i + 1} sits right of cell $i');
      expect(cells[i].width, cells[0].width, reason: 'cell ${i + 1} is as wide as the first');
    }
    expect(cells[3].top, greaterThan(cells[0].bottom), reason: 'the fourth cell starts the second row');
    expect(cells[3].left, cells[0].left, reason: 'the second row starts at the first column');
  });

  // Two across, not three: the sidebar leaves 740 of a 1000px window and the list
  // pads 32, so the grid sees 708 and three columns' 820 is out of reach.
  testWidgets('at 1000px the KPI cells tile two across, two to a row', (tester) async {
    await _open(tester, _wire(reviewRows: _targetedRows(4)), Routes.kpiReview, size: const Size(1000, 1600));
    final cells = _cellRects(tester, 4);

    expect(cells[1].top, cells[0].top, reason: 'the second cell shares the first row');
    expect(cells[1].left, greaterThan(cells[0].right), reason: 'the second cell sits right of the first');
    expect(cells[1].width, cells[0].width, reason: 'the second cell is as wide as the first');
    expect(cells[2].top, greaterThan(cells[0].bottom), reason: 'the third cell starts the second row');
    expect(cells[2].left, cells[0].left, reason: 'the second row starts at the first column');
    expect(cells[3].top, cells[2].top, reason: 'the fourth cell shares the second row');
    expect(cells[3].left, cells[1].left, reason: 'the second column lines up across rows');
  });

  testWidgets('at 700px the KPI cells stack one to a row, still one cell per KPI', (tester) async {
    await _open(tester, _wire(reviewRows: _targetedRows(4)), Routes.kpiReview, size: const Size(700, 1600));
    final cells = _cellRects(tester, 4);

    for (final i in [1, 2, 3]) {
      expect(cells[i].top, greaterThan(cells[i - 1].bottom), reason: 'cell ${i + 1} starts below cell $i');
      expect(cells[i].left, cells[0].left, reason: 'the columns line up');
      expect(cells[i].width, cells[0].width, reason: 'cell ${i + 1} is as wide as the first');
    }
  });
}
