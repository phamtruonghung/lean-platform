/// The Quality Module's geometry, measured (issue #390).
///
/// Ten Screens were re-laid-out in this slice and this file pins what a reader
/// can see of the result, in the way `work_orders_geometry_test.dart` and
/// `register_geometry_support.dart` pin the maintenance registers:
///
/// - **The three registers** (Customer complaints, Non-conformances, Supplier
///   NCRs) are an `AppTableHeader` band and one `AppTableRow` per record at or
///   above their own breakpoint, and one card per record below it. Pinned: the
///   band is 32, a row is exactly 52 (the 44px control inside it plus the
///   `Spacing.xs` `AppTableRow` pads above and below), a band label starts where
///   its cells start, the Open action is the row's right-most cell, and the card
///   path still carries the record's own sentence.
/// - **The three detail pages** (complaint, Non-conformance, supplier NCR) put
///   their summary card first and their sections side by side from a 1000px page
///   box — 1280 window — and stacked below that.
/// - **The four catalogues** (Customers, Products, Suppliers, Defect codes) are
///   rows of at least 44 with the one action against the card's own right edge.
///
/// The app is pumped through the real router with the wire faked, as the
/// Module's own tests do; nothing here reaches into a Bloc. The app's real fonts
/// are loaded first, because the registers size their fixed columns from their
/// own content: in `flutter_test`'s placeholder font every glyph is a square
/// twice as wide as Roboto's, and a number measured there is a property of the
/// placeholder rather than of the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/quality/complaint_detail_screen.dart';
import 'package:lean_platform/quality/complaints_screen.dart';
import 'package:lean_platform/quality/customers_screen.dart';
import 'package:lean_platform/quality/defect_codes_screen.dart';
import 'package:lean_platform/quality/nonconformance_detail_screen.dart';
import 'package:lean_platform/quality/nonconformances_screen.dart';
import 'package:lean_platform/quality/products_screen.dart';
import 'package:lean_platform/quality/supplier_ncr_detail_screen.dart';
import 'package:lean_platform/quality/supplier_ncrs_screen.dart';
import 'package:lean_platform/quality/suppliers_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_list_card.dart';
import 'package:lean_platform/widgets/app_table.dart';

import 'harness.dart';

/// One Site, one Customer, one Supplier, one Product, one Defect code, and one
/// record of each kind — long enough in its own fields to exercise the columns
/// rather than fitting in them by luck.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      customers: [customerJson('60', 'CUST-1', 'Acme Bearings')],
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      suppliers: [supplierJson('50', 'SUP-1', 'Northwind Fasteners')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      nonconformances: {
        '1': [
          nonconformanceJson(
            '701',
            'NC-HCM-2026-00001',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            quantityAffected: 20,
          ),
        ],
      },
      complaints: {
        '1': [
          customerComplaintJson(
            '70',
            'CC-2026-00001',
            orgUnitId: '10',
            responseDueDate: '2020-06-01',
            isOverdue: true,
            daysOverdue: 12,
            nonconformance: complaintNonconformanceJson('950', 'NC-HCM-2026-00050'),
          ),
        ],
      },
      supplierNcrs: {
        '1': [
          supplierNcrJson(
            '80',
            'SN-2026-00001',
            supplierId: '50',
            supplierCode: 'SUP-1',
            supplierName: 'Northwind Fasteners',
            responseDueDate: '2020-06-01',
            isOverdue: true,
            daysOverdue: 5,
            nonconformance: supplierNcrNonconformanceJson('950', 'NC-HCM-2026-00050'),
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  required double width,
  double textScale = 1,
  double height = 1000,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire().client,
    initialLocation: location,
  );
}

/// One register, as this file sees it.
class _Register {
  const _Register({
    required this.name,
    required this.location,
    required this.id,
    required this.rowKey,
    required this.openKey,
    required this.bandLabel,
    required this.cardSentence,
  });

  final String name;
  final String location;
  final String id;
  final Key Function(String id) rowKey;
  final Key Function(String id) openKey;

  /// A band label whose cells must start at the same x as it does.
  final String bandLabel;

  /// A sentence only the card carries, so the narrow path is proved to render
  /// the record rather than an empty box.
  final String cardSentence;
}

final _registers = <_Register>[
  _Register(
    name: 'Customer complaints',
    location: '/complaints',
    id: '70',
    rowKey: ComplaintsScreen.rowKey,
    openKey: ComplaintsScreen.rowOpenKey,
    bandLabel: 'Complaint',
    cardSentence: 'Acme Bearings · Gearbox · Out of tolerance',
  ),
  _Register(
    name: 'Non-conformances',
    location: '/non-conformances',
    id: '701',
    rowKey: NonconformancesScreen.rowKey,
    openKey: NonconformancesScreen.rowOpenKey,
    bandLabel: 'Non-conformance',
    cardSentence: 'Gearbox · Out of tolerance · In process',
  ),
  _Register(
    name: 'Supplier NCRs',
    location: '/supplier-ncrs',
    id: '80',
    rowKey: SupplierNcrsScreen.rowKey,
    openKey: SupplierNcrsScreen.rowOpenKey,
    bandLabel: 'NCR',
    cardSentence: 'Northwind Fasteners · Gearbox · Out of tolerance',
  ),
];

Finder _cellIn(Key row, int index) => find.descendant(
      of: find.byKey(row),
      matching: find.byKey(AppTableRow.cellKey(index)),
    );

/// The card path, measured rather than assumed.
///
/// A register's card is a `Card` padded by `Spacing.md` with its Open control a
/// child of that padding — so the control's left edge is [Spacing.md] in from
/// the card's. That number is what separates a card from a table row: the same
/// control in the table sits in the end-aligned action column, a column's width
/// away from the left edge. A presence check alone cannot tell the two apart,
/// which is how a breakpoint that ignores the reader's text scale stayed green
/// through #379 and #381.
void _expectCardRow(WidgetTester tester, _Register register, String where) {
  final card = find.byKey(register.rowKey(register.id));
  expect(card, findsOneWidget, reason: '${register.name} $where: no card for the record');
  final open = find.byKey(register.openKey(register.id));
  expect(open, findsOneWidget, reason: '${register.name} $where: no Open control');
  expect(
    tester.getTopLeft(open).dx,
    closeTo(tester.getTopLeft(card).dx + Spacing.md, 1.5),
    reason: '${register.name} $where: the Open control is not inside the card\'s own '
        '${Spacing.md.toInt()}px padding (a table row puts it at the far right)',
  );
  expect(tester.getSize(open).height, greaterThanOrEqualTo(AppTouchTarget.min),
      reason: '${register.name} $where: the Open control is under '
          '${AppTouchTarget.min.toInt()}');
}

void main() {
  setUpAll(loadAppFonts);

  // ---------------------------------------------------------------------------
  // The three registers
  // ---------------------------------------------------------------------------

  for (final register in _registers) {
    testWidgets('${register.name}: at 1280 the band is ${AppTableHeader.height.toInt()}, the row '
        'is exactly ${AppTouchTarget.min + 2 * Spacing.xs} and the Open action ends the row',
        (tester) async {
      await _pump(tester, location: register.location, width: 1280);

      expect(find.byType(AppTableHeader), findsOneWidget);
      expect(tester.getSize(find.byType(AppTableHeader)).height, AppTableHeader.height);

      final row = find.byKey(register.rowKey(register.id));
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, AppTouchTarget.min + 2 * Spacing.xs);

      // The action column is the one a reader needs, so it is measured: a 44px
      // target, and it ends where `AppTableRow`'s own padding and the column
      // slot's gutter leave it — the same edge the band's own label ends on.
      final open = find.byKey(register.openKey(register.id));
      expect(open, findsOneWidget);
      expect(tester.getSize(open).height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(
        tester.getBottomRight(open).dx,
        closeTo(tester.getBottomRight(row).dx - Spacing.md - Spacing.sm, 1.5),
        reason: '${register.name}: the Open action is not the row\'s right-most cell',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('${register.name}: at 1280 every band label meets its own cells',
        (tester) async {
      await _pump(tester, location: register.location, width: 1280);

      // A start-aligned column's label and cell share a left edge.
      final label = find.byKey(AppTableHeader.labelKey(register.bandLabel));
      expect(label, findsOneWidget);
      final firstCell = _cellIn(register.rowKey(register.id), 0);
      expect(firstCell, findsOneWidget, reason: '${register.name}: cell 0');
      expect(
        (tester.getTopLeft(label).dx - tester.getTopLeft(firstCell).dx).abs(),
        lessThanOrEqualTo(1.0),
        reason: '${register.name}: "${register.bandLabel}" and cell 0 do not share a left edge',
      );

      // The action column is end-aligned, so its label and its control share a
      // RIGHT edge — the edge the alignment makes meaningful.
      final actions = find.byKey(AppTableHeader.labelKey('Actions'));
      expect(actions, findsOneWidget, reason: '${register.name}: no Actions band label');
      expect(
        (tester.getBottomRight(actions).dx -
                tester.getBottomRight(find.byKey(register.openKey(register.id))).dx)
            .abs(),
        lessThanOrEqualTo(1.0),
        reason: '${register.name}: the Actions label and the Open control do not share a right edge',
      );
      expect(tester.takeException(), isNull);
    });

    for (final width in [700.0, 900.0, 1100.0]) {
      testWidgets('${register.name}: at ${width.toInt()} it is a card per record, and the record '
          'still says what it is', (tester) async {
        await _pump(tester, location: register.location, width: width);

        expect(find.byType(AppTableHeader), findsNothing,
            reason: '${register.name} at $width: a table was drawn in a box that cannot hold it');
        expect(find.text(register.cardSentence), findsWidgets);
        _expectCardRow(tester, register, 'at ${width.toInt()}');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${register.name}: at twice the text, at 1280 and at 700, it is a card and the '
        'Open control is still reachable', (tester) async {
      for (final width in [1280.0, 700.0]) {
        await _pump(tester, location: register.location, width: width, textScale: 2);
        expect(tester.takeException(), isNull, reason: '${register.name} at $width x2');

        // The register compares `AppBreakpoints.effective(...)`, i.e. its own
        // breakpoint scaled by the reader's text setting, so twice the text
        // must move it below the box it is handed: at 1280 the page box is
        // 1020, under `900 x 2`. A raw constant leaves 1020 > 900 and draws the
        // six-column table into a box that cannot hold it — #379/#381 exactly.
        expect(find.byType(AppTableHeader), findsNothing,
            reason: '${register.name} at $width x2: a table was drawn at twice the text');
        _expectCardRow(tester, register, 'at ${width.toInt()} x2');

        final open = find.byKey(register.openKey(register.id));
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        expect(open.hitTestable(), findsOneWidget,
            reason: '${register.name}: Open is not hittable at $width x2');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // The three detail pages
  // ---------------------------------------------------------------------------

  final details = <(String, String, Key)>[
    ('Customer complaint', '/complaints/70', ComplaintDetailScreen.summaryKey),
    ('Non-conformance', '/non-conformances/701', NonconformanceDetailScreen.summaryKey),
    ('Supplier NCR', '/supplier-ncrs/80', SupplierNcrDetailScreen.summaryKey),
  ];

  for (final (name, location, summaryKey) in details) {
    testWidgets('$name: at 1280 the summary card leads and its sections sit side by side',
        (tester) async {
      await _pump(tester, location: location, width: 1280, height: 1400);

      final summary = find.byKey(summaryKey);
      expect(summary, findsOneWidget);
      final sections = find.byType(AppDetailSection);
      expect(sections, findsWidgets, reason: '$name: no sections');
      expect(
        tester.getTopLeft(sections.at(0)).dy,
        greaterThan(tester.getBottomRight(summary).dy - 1),
        reason: '$name: a section is drawn above the summary card',
      );
      if (sections.evaluate().length > 1) {
        final first = tester.getRect(sections.at(0));
        final second = tester.getRect(sections.at(1));
        expect(second.top, closeTo(first.top, 1.0),
            reason: '$name: the first two sections are not on one row at 1280');
        expect(second.left, greaterThan(first.right - 1),
            reason: '$name: the second section is not to the right of the first');
        expect((second.width - first.width).abs(), lessThanOrEqualTo(1.0));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: at 700 its sections stack, and at twice the text nothing overflows',
        (tester) async {
      await _pump(tester, location: location, width: 700, height: 1600);
      expect(find.byKey(summaryKey), findsOneWidget);
      final sections = find.byType(AppDetailSection);
      if (sections.evaluate().length > 1) {
        expect(tester.getTopLeft(sections.at(1)).dy, greaterThan(tester.getBottomRight(sections.at(0)).dy - 1),
            reason: '$name: two sections share a row at 700');
      }
      expect(tester.takeException(), isNull);

      for (final width in [1280.0, 700.0]) {
        // A taller surface at twice the text, so both of the first pair are
        // built and their rectangles can be compared: the page is a `ListView`,
        // and a section that was never laid out proves nothing.
        await _pump(tester, location: location, width: width, height: 2000, textScale: 2);
        expect(tester.takeException(), isNull, reason: '$name at $width x2');

        final summary = find.byKey(summaryKey);
        expect(summary, findsOneWidget, reason: '$name: summary at $width x2');
        final sections = find.byType(AppDetailSection);
        expect(sections, findsAtLeastNWidgets(2), reason: '$name at $width x2: no section pair');
        expect(
          tester.getTopLeft(sections.at(0)).dy,
          greaterThan(tester.getBottomRight(summary).dy - 1),
          reason: '$name at $width x2: a section is drawn above the summary card',
        );

        // Twice the text doubles `AppBreakpoints.detailTwoColumn` to 2000, so
        // neither a 1020px page box nor a 640px one can hold two columns: the
        // pair must stack. Two sections on one row here is the breakpoint
        // comparison that ignored the reader's own text setting.
        expect(
          tester.getTopLeft(sections.at(1)).dy,
          greaterThan(tester.getBottomRight(sections.at(0)).dy - 1),
          reason: '$name at $width x2: two sections share a row at twice the text',
        );
        expect(
          tester.getTopLeft(sections.at(1)).dx,
          closeTo(tester.getTopLeft(sections.at(0)).dx, 1.0),
          reason: '$name at $width x2: the stacked sections do not share a left edge',
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // The four catalogues
  // ---------------------------------------------------------------------------

  final catalogues = <(String, String, String, Key Function(String), Key Function(String))>[
    ('Customers', '/customers', '60', CustomersScreen.rowKey, CustomersScreen.correctKey),
    ('Products', '/products', '40', ProductsScreen.rowKey, ProductsScreen.correctKey),
    ('Suppliers', '/suppliers', '50', SuppliersScreen.rowKey, SuppliersScreen.correctKey),
    (
      'Defect codes',
      '/defect-codes',
      '41',
      DefectCodesScreen.rowKey,
      DefectCodesScreen.correctKey,
    ),
  ];

  for (final (name, location, id, rowKey, actionKey) in catalogues) {
    for (final width in [1280.0, 700.0]) {
      testWidgets('$name: at ${width.toInt()} a row is at least 44 and its action ends the card',
          (tester) async {
        await _pump(tester, location: location, width: width);

        final card = find.byType(AppListCard);
        expect(card, findsOneWidget, reason: '$name: no catalogue card');
        final row = find.byKey(rowKey(id));
        expect(row, findsOneWidget);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: '$name: a row that holds a control is under 44');

        final action = find.byKey(actionKey(id));
        expect(action, findsOneWidget);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(AppTouchTarget.min));
        expect(
          tester.getBottomRight(action).dx,
          closeTo(tester.getBottomRight(card).dx - Spacing.lg, 1.5),
          reason: '$name: the action is not against the card\'s own right edge',
        );

        // The name line starts at the row's own inset, not at the card's edge.
        final text = find.descendant(of: row, matching: find.byType(Text)).first;
        expect(
          tester.getTopLeft(text).dx,
          closeTo(tester.getTopLeft(card).dx + Spacing.lg, 1.5),
          reason: '$name: the name line is not at the row\'s inset',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$name: at twice the text nothing overflows and the action still ends the card',
        (tester) async {
      for (final width in [1280.0, 700.0]) {
        await _pump(tester, location: location, width: width, textScale: 2);
        expect(tester.takeException(), isNull, reason: '$name at $width x2');

        // The same measurement the 1x cases make, at the reader's text scale:
        // a catalogue row is not allowed to grow a second line that carries the
        // action off the card's own right edge.
        final card = find.byType(AppListCard);
        expect(card, findsOneWidget, reason: '$name at $width x2: no catalogue card');
        final row = find.byKey(rowKey(id));
        expect(row, findsOneWidget, reason: '$name at $width x2: no row');
        expect(tester.getSize(row).height, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: '$name at $width x2: a row that holds a control is under '
                '${AppTouchTarget.min.toInt()}');

        final action = find.byKey(actionKey(id));
        expect(action, findsOneWidget);
        expect(
          tester.getBottomRight(action).dx,
          closeTo(tester.getBottomRight(card).dx - Spacing.lg, 1.5),
          reason: '$name at $width x2: the action is not against the card\'s own right edge',
        );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget,
            reason: '$name at $width x2: the action is not reachable');
      }
    });
  }
}
