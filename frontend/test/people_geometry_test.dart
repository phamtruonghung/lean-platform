/// The People Module's first six Screens' geometry, measured (issue #392).
///
/// Seven Screens were re-laid-out in this slice, and this file pins what a
/// reader can see of the result — the way `quality_geometry_test.dart` pinned
/// #390's and `production_geometry_test.dart` pinned #389's:
///
/// - **The Directory** is a register at a 1280 window: an `AppTableHeader`
///   band and one 44px `AppTableRow` per Employee, whose first cell is the
///   initials block the name sits beside. At 700 it is one card per Employee,
///   and at twice the reader's text at 1280 it is cards again — because the
///   breakpoint is forced through `AppBreakpoints.effective` (§10, the bug
///   class of #379 and #381).
/// - **Accounts** and the **Approval queue** are registers on the same terms,
///   and the queue's row carries both of its decision controls at the 44px
///   floor (`AppTouchTarget.min`), visible without opening anything.
/// - **Org Units** holds at 700: the tree's row is at least 44 tall, its depth
///   indent is the only thing that grows with depth, and an expanded branch
///   states the count it has actually read.
/// - **Cost rates** and **Product costs** are money registers: the amount is
///   the right-most content of its own column, in tabular figures, under a
///   label that names the currency, and the period reads §13's way.
/// - **The Employee detail** is a summary card first, then two sections side by
///   side at a 1280 window and stacked at 700.
/// - **The states** are the shared ones (#103): `SkeletonList`/`SkeletonDetail`
///   while a read is in flight and `PlatformEmptyState` for a Site list that is
///   empty — never a bare spinner or a lone `Text`. The wire's three gates
///   (`sitesGate`, `orgUnitTreeGate`, `employeeDetailGate`) hold those reads
///   open so the loading state is a thing this file can measure.
///
/// The app is pumped through the real router with the wire faked, as the
/// Module's own tests do; nothing here reaches into a Bloc. The app's real fonts
/// are loaded first, because a register measures its fixed columns from its own
/// content — in `flutter_test`'s placeholder font every glyph is a square, and a
/// width measured there is a property of the placeholder rather than of the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/cost_rates_screen.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/org_units_screen.dart';
import 'package:lean_platform/people/product_costs_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/empty_state.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

/// One Site, two Org Units, and one record of each kind this slice renders —
/// long enough in its own fields to exercise the columns rather than fitting in
/// them by luck.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [
          orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line'),
          orgUnitJson('12', 'Line 2', parentId: '10', unitType: 'line'),
        ],
      },
      employees: [
        employeeJson('7', 'EMP-2026-0007', 'Alice Nguyen'),
        employeeJson('8', 'EMP-2026-0008', 'Bao Tran'),
      ],
      // The detail page's own read (#392's employee detail): the summary card
      // takes its Org Unit from the current Assignment, so the fixture carries
      // one.
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'EMP-2026-0007',
          'Alice Nguyen',
          jobRole: jobRoleJson('20', 'WELD', 'Welder'),
          assignments: [
            employeeAssignmentJson(
              '99',
              orgUnitId: '10',
              orgUnitName: 'Assembly',
              jobRoleName: 'Welder',
              effectiveFrom: '2024-01-01',
              isCurrent: true,
            ),
          ],
        ),
      },
      jobRoles: [jobRoleJson('20', 'WELD', 'Welder')],
      accounts: [
        accountJson('1', 'admin@b.c', role: Roles.admin),
        accountJson('7', 'admitted@b.c', role: Roles.supervisor),
      ],
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
      costRates: [
        costRateJson('900', amount: 30, effectiveFrom: '2026-01-01', effectiveTo: '2026-04-01'),
        costRateJson('901', amount: 1200, effectiveFrom: '2026-04-01'),
      ],
      costRateScopes: [
        costRateScopeJson('site', '1', 'HCM', 'Ho Chi Minh', siteName: 'Ho Chi Minh'),
      ],
      productCosts: [
        productCostJson('950', standardCost: 5, effectiveFrom: '2026-01-01'),
      ],
      costableProducts: [costableProductJson('40', 'PRD-1', 'Gearbox')],
    );

/// Pumps one address at a stated window and text scale — the two variables
/// every measurement here is a function of.
Future<void> _pumpAt(
  WidgetTester tester, {
  required String location,
  required double width,
  double textScale = 1,
  double height = 1200,
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

/// The widths every case is measured at: the two the ticket names, 700 and 1280,
/// and the 900 between them a register switches at.
const List<double> _widths = [700, 900, 1280];

void main() {
  setUpAll(loadAppFonts);

  group('the Directory register', () {
    for (final width in _widths) {
      testWidgets('at ${width.toInt()}px the register is a table or cards, and holds at either',
          (tester) async {
        await _pumpAt(tester, location: Routes.directory, width: width);
        expect(tester.takeException(), isNull, reason: 'Directory at $width');

        final table = find.byType(AppTableHeader);
        final row = find.byKey(DirectoryScreen.rowKey('7'));
        expect(row, findsOneWidget, reason: 'Directory at $width: no first Employee');

        if (width >= 1280) {
          // 1280: the Shell leaves 1020, the page hands this list 988, which is
          // over the register's own 900 — so the band is drawn and every row is
          // the 44px tap target `AppTableRow` gives an `onTap`.
          expect(table, findsOneWidget, reason: 'Directory at $width: no column band');
          expect(
            tester.getSize(row).height,
            greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Directory at $width: the row is shorter than the tap floor',
          );
          // The band's first label and the first row's first cell start at the
          // same x — one column spec builds both (§6).
          final label = find.byKey(AppTableHeader.labelKey('Employee'));
          expect(
            tester.getTopLeft(label).dx,
            closeTo(tester.getTopLeft(row).dx + Spacing.md, 1.5),
            reason: 'Directory at $width: the band and the row disagree on the first column',
          );
        } else {
          // 900 hands the page 640 and 700 hands it 440; both are under 900.
          expect(table, findsNothing, reason: 'Directory at $width: a table was drawn too narrow');
          expect(
            tester.getSize(row).height,
            greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Directory at $width: the card lost its tap target',
          );
        }
      });
    }

    testWidgets('at 1280 with twice the text the cards come back, never a squeezed table',
        (tester) async {
      await _pumpAt(tester, location: Routes.directory, width: 1280, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'Directory at 1280 x2');
      // 988 of box against 900 x2 = 1800: a raw constant would draw six columns
      // into a box that cannot hold them — exactly #379/#381.
      expect(find.byType(AppTableHeader), findsNothing,
          reason: 'Directory at 1280 x2: a table was drawn at twice the text');
      expect(find.byKey(DirectoryScreen.rowKey('7')), findsOneWidget);
    });
  });

  group('the Accounts register', () {
    for (final width in _widths) {
      testWidgets('at ${width.toInt()}px the role and the standing are two chips on the row',
          (tester) async {
        await _pumpAt(tester, location: Routes.accounts, width: width);
        expect(tester.takeException(), isNull, reason: 'Accounts at $width');

        final row = find.byKey(AccountsScreen.rowKey('7'));
        expect(row, findsOneWidget, reason: 'Accounts at $width: no row');
        expect(
          tester.getSize(row).height,
          greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Accounts at $width: the row is shorter than the tap floor',
        );
        for (final chip in ['Supervisor', 'Active']) {
          expect(
            find.descendant(of: row, matching: find.text(chip)),
            findsOneWidget,
            reason: 'Accounts at $width: "$chip" is not a chip on the row',
          );
        }
        expect(find.byType(AppTableHeader), width >= 1280 ? findsOneWidget : findsNothing,
            reason: 'Accounts at $width: the register drew the wrong shape');
      });
    }

    testWidgets('at 1280px with twice the text the cards come back, both chips intact',
        (tester) async {
      await _pumpAt(tester, location: Routes.accounts, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'Accounts at 1280 x2');

      // 988 of box against 900 x 2 = 1800: the register takes its own narrow
      // branch and the row becomes a card, rather than a four-column table
      // squeezed into half the width it was measured for (§10, #379/#381).
      expect(find.byType(AppTableHeader), findsNothing,
          reason: 'Accounts at 1280 x2: a table was drawn at twice the text');
      final row = find.byKey(AccountsScreen.rowKey('7'));
      expect(row, findsOneWidget, reason: 'Accounts at 1280 x2: no row');
      expect(tester.getSize(row).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Accounts at 1280 x2: the row lost its tap target');
      for (final chip in ['Supervisor', 'Active']) {
        final chipFinder = find.descendant(of: row, matching: find.text(chip));
        expect(chipFinder, findsOneWidget,
            reason: 'Accounts at 1280 x2: "$chip" is not a chip on the row');
        // Both chips stay inside the card's own box rather than running off it.
        expect(tester.getBottomRight(chipFinder).dx,
            lessThanOrEqualTo(tester.getBottomRight(row).dx),
            reason: 'Accounts at 1280 x2: the "$chip" chip runs past the row');
      }
    });
  });

  group('the Approval queue is a decision surface', () {
    for (final width in _widths) {
      testWidgets('at ${width.toInt()}px both decisions are on the row, at the tap floor',
          (tester) async {
        await _pumpAt(tester, location: Routes.approvals, width: width);
        expect(tester.takeException(), isNull, reason: 'Approval queue at $width');

        final reject = find.byKey(ApprovalQueueScreen.rejectKey('7'));
        final admit = find.byKey(ApprovalQueueScreen.admitKey('7'));
        expect(reject, findsOneWidget, reason: 'Approval queue at $width: no Reject');
        expect(admit, findsOneWidget, reason: 'Approval queue at $width: no Admit');
        // A decision must not need a row tap first: both controls are laid out
        // in the row itself, at the 44px floor.
        expect(tester.getSize(reject).height, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Approval queue at $width: Reject is under the tap floor');
        expect(tester.getSize(admit).height, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Approval queue at $width: Admit is under the tap floor');
        // Admit is the row's right-most control, and Reject sits before it.
        expect(
          tester.getTopLeft(reject).dx,
          lessThan(tester.getTopLeft(admit).dx),
          reason: 'Approval queue at $width: the two decisions are out of order',
        );
      });
    }

    testWidgets('at 1280px with twice the text both decisions are still on the row',
        (tester) async {
      await _pumpAt(tester, location: Routes.approvals, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'Approval queue at 1280 x2');

      final reject = find.byKey(ApprovalQueueScreen.rejectKey('7'));
      final admit = find.byKey(ApprovalQueueScreen.admitKey('7'));
      expect(reject, findsOneWidget, reason: 'Approval queue at 1280 x2: no Reject');
      expect(admit, findsOneWidget, reason: 'Approval queue at 1280 x2: no Admit');
      // The decision surface keeps deciding at twice the text: neither control
      // drops under the tap floor, and neither runs out of the window.
      expect(tester.getSize(reject).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Approval queue at 1280 x2: Reject is under the tap floor');
      expect(tester.getSize(admit).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Approval queue at 1280 x2: Admit is under the tap floor');
      expect(tester.getTopLeft(reject).dx, lessThan(tester.getTopLeft(admit).dx),
          reason: 'Approval queue at 1280 x2: the two decisions are out of order');
      expect(tester.getBottomRight(admit).dx, lessThanOrEqualTo(1280),
          reason: 'Approval queue at 1280 x2: a decision runs past the window');
    });
  });

  group('the Org Units tree holds at 700 and at 1280', () {
    testWidgets('at 700px the tree row is a tap target and its count is on its own line',
        (tester) async {
      await _pumpAt(tester, location: Routes.orgUnits, width: 700);
      expect(tester.takeException(), isNull, reason: 'Org Units at 700');

      final expand = find.byKey(OrgUnitsScreen.expandKey('10'));
      expect(expand, findsOneWidget, reason: 'Org Units at 700: no disclosure control');
      expect(
        tester.getSize(find.byKey(OrgUnitsScreen.retireKey('10'))).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'Org Units at 700: Retire is under the tap floor',
      );
      // The indent is the only thing that grows with depth: the disclosure
      // control leads, the row's own controls follow it, and nothing reaches
      // past the page.
      expect(tester.getTopLeft(expand).dx, lessThan(tester.getTopLeft(find.byKey(OrgUnitsScreen.retireKey('10'))).dx),
          reason: 'Org Units at 700: the disclosure control does not lead the row');
      expect(
        tester.getBottomRight(find.byKey(OrgUnitsScreen.retireKey('10'))).dx,
        lessThanOrEqualTo(700),
        reason: 'Org Units at 700: the row runs past the window',
      );
    });

    testWidgets('at 1280px the expanded branch states its count on its own line, under the name',
        (tester) async {
      await _pumpAt(tester, location: Routes.orgUnits, width: 1280);
      expect(tester.takeException(), isNull, reason: 'Org Units at 1280');
      // The fixture's Assembly holds two Org Units. Expanding it is what makes
      // the count a measured fact rather than an assumption (§13).
      await tapIn(tester, find.byKey(OrgUnitsScreen.expandKey('10')));

      final name = find.textContaining('Assembly');
      final count = find.text('2 below');
      expect(count, findsOneWidget,
          reason: 'Org Units at 1280: an expanded branch does not state its count');
      expect(
        tester.getTopLeft(count).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(name).dy - 1),
        reason: 'Org Units at 1280: the count is not on a line of its own',
      );
      expect(
        tester.getTopLeft(count).dx,
        closeTo(tester.getTopLeft(name).dx, 1.5),
        reason: 'Org Units at 1280: the count does not start at the name\'s own left edge',
      );
      // The indent is the only thing that grows with depth: a child's name
      // starts inside its parent's, and the row's own action still holds the
      // tap floor and stays inside the page.
      expect(
        tester.getTopLeft(find.textContaining('Line 1')).dx,
        greaterThan(tester.getTopLeft(name).dx),
        reason: 'Org Units at 1280: a child row is not drawn under its parent',
      );
      final retire = find.byKey(OrgUnitsScreen.retireKey('10'));
      expect(tester.getSize(retire).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Org Units at 1280: Retire is under the tap floor');
      expect(tester.getBottomRight(retire).dx, lessThanOrEqualTo(1280),
          reason: 'Org Units at 1280: the row runs past the window');
    });

    testWidgets('at 1280px with twice the text the row keeps both its name and its action',
        (tester) async {
      await _pumpAt(tester, location: Routes.orgUnits, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'Org Units at 1280 x2');
      await tapIn(tester, find.byKey(OrgUnitsScreen.expandKey('10')));

      final name = find.textContaining('Assembly');
      final count = find.text('2 below');
      expect(count, findsOneWidget,
          reason: 'Org Units at 1280 x2: the count is lost at twice the text');
      expect(
        tester.getTopLeft(count).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(name).dy - 1),
        reason: 'Org Units at 1280 x2: the count is squeezed onto the name\'s line',
      );
      final retire = find.byKey(OrgUnitsScreen.retireKey('10'));
      expect(tester.getSize(retire).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Org Units at 1280 x2: Retire is under the tap floor');
      expect(tester.getBottomRight(retire).dx, lessThanOrEqualTo(1280),
          reason: 'Org Units at 1280 x2: the row runs past the window');
    });
  });

  group('the two money registers', () {
    for (final width in _widths) {
      testWidgets('cost rates at ${width.toInt()}px: the money column is end-aligned in tabular figures',
          (tester) async {
        await _pumpAt(tester, location: Routes.costRates, width: width);
        expect(tester.takeException(), isNull, reason: 'Cost rates at $width');

        expect(find.byKey(CostRatesScreen.rowKey('900')), findsOneWidget,
            reason: 'Cost rates at $width: no row');
        // §13's wording, on the row itself.
        expect(find.text('1 Jan 2026 – 1 Apr 2026'), findsOneWidget,
            reason: 'Cost rates at $width: the period is not worded as a date');

        if (width < 1280) {
          // Below 1280 the register is one card per rate. The same three rules
          // still hold — the figure sits at the card's own right edge, in
          // tabular figures, and carries its own unit because a card has no
          // column label to put it in (§13).
          expect(find.byType(AppTableHeader), findsNothing,
              reason: 'Cost rates at $width: a table was drawn too narrow');
          final cardAmount = find.text('30.0 USD');
          expect(cardAmount, findsOneWidget,
              reason: 'Cost rates at $width: the card does not carry the amount with its unit');
          expect(
            tester.widget<Text>(cardAmount).style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
            reason: 'Cost rates at $width: the amount is not in tabular figures',
          );
          final card = find.byKey(CostRatesScreen.rowKey('900'));
          expect(
            tester.getBottomRight(cardAmount).dx,
            closeTo(tester.getBottomRight(card).dx - Spacing.md, 1.5),
            reason: 'Cost rates at $width: the amount is not at the card\'s own right edge',
          );
          expect(
            tester.getSize(find.byKey(CostRatesScreen.correctKey('900'))).height,
            greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Cost rates at $width: Correct is under the tap floor',
          );
          return;
        }

        final amount = find.text('30.0');
        expect(amount, findsOneWidget, reason: 'Cost rates at $width: no bare figure in the column');
        // A quantity's style: `AppTableRow.numberStyle` is dense + tabular.
        final style = tester.widget<Text>(amount).style;
        expect(
          style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Cost rates at $width: the amount is not in tabular figures',
        );
        // The unit belongs to the column label, never to the cell.
        expect(find.textContaining('Amount (USD)'), findsOneWidget,
            reason: 'Cost rates at $width: the column label does not name the currency');
        // End-aligned: two figures of different widths share one right edge, so
        // the column compares down that edge (§6, §13).
        final narrow = tester.getBottomRight(find.text('30.0')).dx;
        final wide = tester.getBottomRight(find.text('1200.0')).dx;
        expect(narrow, closeTo(wide, 1.5),
            reason: 'Cost rates at $width: the amount column is not end-aligned');
        expect(tester.getTopLeft(find.text('30.0')).dx,
            greaterThan(tester.getTopLeft(find.text('1200.0')).dx),
            reason: 'Cost rates at $width: the figures are not right-aligned');
      });
    }

    testWidgets('product costs at 1280px: the same three rules', (tester) async {
      await _pumpAt(tester, location: Routes.productCosts, width: 1280);
      expect(tester.takeException(), isNull, reason: 'Product costs at 1280');

      expect(find.byKey(ProductCostsScreen.rowKey('950')), findsOneWidget);
      final amount = find.text('5.0');
      expect(amount, findsOneWidget);
      expect(
        tester.widget<Text>(amount).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'Product costs at 1280: the amount is not in tabular figures',
      );
      // The label names the unit, and the figure ends on the label's own right
      // edge — one column spec builds both, so they cannot drift apart (§6).
      final label = find.textContaining('Amount (USD)');
      expect(label, findsOneWidget,
          reason: 'Product costs at 1280: the column label does not name the currency');
      expect(
        tester.getBottomRight(amount).dx,
        closeTo(tester.getBottomRight(label).dx, 1.5),
        reason: 'Product costs at 1280: the figure does not end on its own column edge',
      );
      expect(find.text('From 1 Jan 2026'), findsOneWidget,
          reason: 'Product costs at 1280: the open period is not worded as a date');
    });

    for (final width in _widths) {
      if (width >= 1280) continue;
      testWidgets('product costs at ${width.toInt()}px: the card keeps the figure end-aligned',
          (tester) async {
        await _pumpAt(tester, location: Routes.productCosts, width: width);
        expect(tester.takeException(), isNull, reason: 'Product costs at $width');

        expect(find.byKey(ProductCostsScreen.rowKey('950')), findsOneWidget,
            reason: 'Product costs at $width: no row');
        expect(find.text('From 1 Jan 2026'), findsOneWidget,
            reason: 'Product costs at $width: the open period is not worded as a date');
        expect(find.byType(AppTableHeader), findsNothing,
            reason: 'Product costs at $width: a table was drawn too narrow');

        final amount = find.text('5.0 USD');
        expect(amount, findsOneWidget,
            reason: 'Product costs at $width: the card does not carry the amount with its unit');
        expect(
          tester.widget<Text>(amount).style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Product costs at $width: the amount is not in tabular figures',
        );
        final card = find.byKey(ProductCostsScreen.rowKey('950'));
        expect(
          tester.getBottomRight(amount).dx,
          closeTo(tester.getBottomRight(card).dx - Spacing.md, 1.5),
          reason: 'Product costs at $width: the amount is not at the card\'s own right edge',
        );
        expect(
          tester.getSize(find.byKey(ProductCostsScreen.reviseKey('950'))).height,
          greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'Product costs at $width: Revise is under the tap floor',
        );
      });
    }

    testWidgets('cost rates at 1280px with twice the text are cards, the figure still end-aligned',
        (tester) async {
      await _pumpAt(tester, location: Routes.costRates, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'Cost rates at 1280 x2');
      // 988 of box against 700 x 2 = 1400: cards, never a five-column table
      // drawn at half the width it was measured for (§10, #379/#381).
      expect(find.byType(AppTableHeader), findsNothing,
          reason: 'Cost rates at 1280 x2: a table was drawn at twice the text');
      final amount = find.text('30.0 USD');
      expect(amount, findsOneWidget, reason: 'Cost rates at 1280 x2: no amount on the card');
      expect(
        tester.widget<Text>(amount).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'Cost rates at 1280 x2: the amount is not in tabular figures',
      );
      final card = find.byKey(CostRatesScreen.rowKey('900'));
      expect(
        tester.getBottomRight(amount).dx,
        closeTo(tester.getBottomRight(card).dx - Spacing.md, 1.5),
        reason: 'Cost rates at 1280 x2: the amount is not at the card\'s own right edge',
      );
      for (final key in [CostRatesScreen.correctKey('900'), CostRatesScreen.reviseKey('900')]) {
        expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'Cost rates at 1280 x2: an action is under the tap floor');
      }
    });

    testWidgets('product costs at 1280px with twice the text are cards too', (tester) async {
      await _pumpAt(tester, location: Routes.productCosts, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'Product costs at 1280 x2');
      expect(find.byType(AppTableHeader), findsNothing,
          reason: 'Product costs at 1280 x2: a table was drawn at twice the text');
      final amount = find.text('5.0 USD');
      expect(amount, findsOneWidget, reason: 'Product costs at 1280 x2: no amount on the card');
      expect(
        tester.widget<Text>(amount).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'Product costs at 1280 x2: the amount is not in tabular figures',
      );
      final card = find.byKey(ProductCostsScreen.rowKey('950'));
      expect(
        tester.getBottomRight(amount).dx,
        closeTo(tester.getBottomRight(card).dx - Spacing.md, 1.5),
        reason: 'Product costs at 1280 x2: the amount is not at the card\'s own right edge',
      );
    });
  });

  group('the Employee detail', () {
    testWidgets('at 1280px the summary card comes first and the sections share a row',
        (tester) async {
      await _pumpAt(tester, location: '${Routes.directory}/7', width: 1280);
      expect(tester.takeException(), isNull, reason: 'Employee detail at 1280');

      final sections = find.byType(AppDetailSection);
      expect(sections, findsAtLeastNWidgets(2), reason: 'Employee detail at 1280: no section pair');
      // Two columns: the second section starts to the right of the first, on
      // the same line. The choice is made on the page's own box — 1020 at a
      // 1280 window, before the list's `Spacing.lg` inset — read through
      // `AppBreakpoints.effective` inside `_SectionPair`, never from the window.
      expect(
        tester.getTopLeft(sections.at(1)).dx,
        greaterThan(tester.getTopRight(sections.at(0)).dx - 1),
        reason: 'Employee detail at 1280: the sections did not share a row',
      );
      expect(
        tester.getTopLeft(sections.at(1)).dy,
        closeTo(tester.getTopLeft(sections.at(0)).dy, 1.5),
        reason: 'Employee detail at 1280: the two sections do not start on one line',
      );
      // The name is the page's title and a 1.3× ceiling applies to it (#367).
      final title = find.descendant(
        of: find.byType(EmployeeDetailScreen),
        matching: find.text('Alice Nguyen'),
      );
      expect(title, findsOneWidget, reason: 'Employee detail at 1280: no summary title');
    });

    testWidgets('at 700px the sections stack, and nothing overflows', (tester) async {
      await _pumpAt(tester, location: '${Routes.directory}/7', width: 700);
      expect(tester.takeException(), isNull, reason: 'Employee detail at 700');

      final sections = find.byType(AppDetailSection);
      expect(sections, findsAtLeastNWidgets(2));
      expect(
        tester.getTopLeft(sections.at(1)).dy,
        greaterThan(tester.getBottomRight(sections.at(0)).dy - 1),
        reason: 'Employee detail at 700: a section is drawn beside another in a 440px page',
      );
      expect(find.byKey(EmployeeDetailScreen.correctKey), findsOneWidget,
          reason: 'Employee detail at 700: an action was lost on the narrow page');
    });

    testWidgets('at 1280px with twice the text the sections stack rather than squeeze',
        (tester) async {
      await _pumpAt(tester, location: '${Routes.directory}/7', width: 1280, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'Employee detail at 1280 x2');
      final sections = find.byType(AppDetailSection);
      expect(
        tester.getTopLeft(sections.at(1)).dy,
        greaterThan(tester.getBottomRight(sections.at(0)).dy - 1),
        reason: 'Employee detail at 1280 x2: two sections still share a row at twice the text',
      );
    });
  });

  group('the states these Screens show', () {
    testWidgets('org units with no Site yet says so through the shared empty state',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1200);
      addTearDown(tester.view.reset);
      final wire = FakeWire(sites: []);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: Routes.orgUnits,
      );

      expect(tester.takeException(), isNull, reason: 'Org Units with no Site');
      // "There are no Sites yet." is the sentence this branch has always shown;
      // it is now the shared empty state's title rather than a lone `Text`
      // (§9's state vocabulary, #103).
      expect(find.byType(PlatformEmptyState), findsOneWidget,
          reason: 'Org Units with no Site: not the shared empty state');
      expect(find.byKey(OrgUnitsScreen.emptySitesKey), findsOneWidget,
          reason: 'Org Units with no Site: the empty state lost its Key');
      expect(find.text('There are no Sites yet.'), findsOneWidget,
          reason: 'Org Units with no Site: the copy changed');
    });

    testWidgets('org units loads both its panels as the shared skeleton, never a spinner',
        (tester) async {
      final wire = _wire()..sitesGate = Completer<void>();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1200);
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: Routes.orgUnits,
      );

      expect(find.byType(SkeletonList), findsOneWidget,
          reason: 'Org Units: the Site panel does not load as the shared skeleton');
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Org Units: a bare spinner is still a loading state');

      wire.sitesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing,
          reason: 'Org Units: the skeleton stayed after the Site list arrived');
    });

    testWidgets("the Org Unit tree's roots load as the shared skeleton, never a spinner",
        (tester) async {
      // The Site panel's own skeleton is pinned by the case above; this is the
      // tree's, whose placeholder a bare `CircularProgressIndicator` could
      // replace with the whole suite still green (S6's own review, #392).
      final wire = _wire()..orgUnitTreeGate = Completer<void>();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1200);
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: Routes.orgUnits,
      );

      // One Site, so the picker opens it by itself: the Site panel has
      // finished reading, and the only loading state left on the page is the
      // tree's own.
      expect(wire.orgUnitRequests, contains(('1', null)),
          reason: "Org Units: the tree never asked for its Site's roots");
      expect(find.byType(SkeletonList), findsOneWidget,
          reason: "Org Units: the tree's roots do not load as the shared skeleton");
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Org Units: a bare spinner is still a loading state');

      wire.orgUnitTreeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing,
          reason: 'Org Units: the tree skeleton stayed after the roots arrived');
      // The row's own control, not its prose: `_TreeRow` draws `name · code`,
      // so the row is proved arrived by the `Key` it is found by everywhere
      // else in the suite.
      expect(find.byKey(OrgUnitsScreen.expandKey('10')), findsOneWidget,
          reason: "Org Units: the tree's own rows did not arrive after the roots");
    });

    testWidgets('the Employee detail loads as the shared skeleton, never a spinner',
        (tester) async {
      final wire = _wire()..employeeDetailGate = Completer<void>();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1200);
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '${Routes.directory}/7',
      );

      expect(find.byType(SkeletonDetail), findsOneWidget,
          reason: 'Employee detail: the loading state is not the shared skeleton');
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Employee detail: a bare spinner is still the loading state');

      wire.employeeDetailGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonDetail), findsNothing,
          reason: 'Employee detail: the skeleton stayed after the record arrived');
    });
  });
}
