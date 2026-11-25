/// The Work orders table at 1200x800 never ellipsises its Org Unit header or an
/// unassigned Work order's Assignee cell, in either language.
///
/// Vietnamese "Đơn vị tổ chức" and "Chưa phân công" are wider than English
/// "Org Unit" and "Unassigned", and the flex shares of `flex: 2` and `flex: 4`
/// were narrower than they are: the header read "Đơn vị…" and the cell
/// "Chưa phân c…". `_columns()` now measures each column's minimum from the
/// translated words. The check reads the rendered paragraph's own
/// `didExceedMaxLines`, so it holds whatever the font or the share, and real
/// Roboto is loaded because the placeholder test font has no Vietnamese widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/widgets/app_table.dart';

import 'harness.dart';

RenderParagraph _paragraph(WidgetTester tester, Finder within) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: within, matching: find.byType(RichText)).first,
    );

void main() {
  setUpAll(loadAppFonts);

  for (final (code, orgUnit, assignee, unassigned) in [
    ('en', 'Org Unit', 'Assignee', 'Unassigned'),
    ('vi', 'Đơn vị tổ chức', 'Người phụ trách', 'Chưa phân công'),
  ]) {
    testWidgets('at 1200x800 in $code, the Org Unit header and an unassigned Assignee cell '
        'are not ellipsised', (tester) async {
      SharedPreferences.setMockInitialValues(
        code == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);

      final wire = FakeWire(
        sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
        orgUnits: {
          null: [orgUnitJson('10', 'Assembly')],
        },
        assets: {'1': []},
        workOrders: {
          '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
        },
      );
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/work-orders',
      );

      // The render really is in the language the case names.
      expect(find.byKey(AppTableHeader.labelKey(orgUnit)), findsOneWidget);
      expect(find.text(unassigned), findsOneWidget);

      // All seven headers of the table, not only the two this fix began with.
      final headers = code == 'vi'
          ? ['Số WO', 'Nội dung', 'Tài sản', orgUnit, 'Trạng thái', assignee, 'Thao tác']
          : ['WO#', 'Summary', 'Asset', orgUnit, 'Status', assignee, 'Actions'];
      for (final label in headers) {
        final header = _paragraph(tester, find.byKey(AppTableHeader.labelKey(label)));
        expect(header.didExceedMaxLines, isFalse, reason: 'the "$label" header is ellipsised');
      }
      // Cell 5 is the Assignee; the Work order is unassigned.
      final cell = _paragraph(
        tester,
        find.descendant(
          of: find.byKey(WorkOrdersScreen.rowKey('101')),
          matching: find.byKey(AppTableRow.cellKey(5)),
        ),
      );
      expect(cell.didExceedMaxLines, isFalse, reason: 'the "$unassigned" cell is ellipsised');

      // English keeps its flex shares: the slots of Org Unit (2) and Assignee (4)
      // are one third and two thirds of Summary's (6), as `flex` spends them.
      if (code == 'en') {
        // The slot is the `Expanded` a flex column becomes, so its width is the share.
        double slot(int i) => tester
            .getSize(find
                .ancestor(
                  of: find.descendant(
                    of: find.byKey(WorkOrdersScreen.rowKey('101')),
                    matching: find.byKey(AppTableRow.cellKey(i)),
                  ),
                  matching: find.byType(Expanded),
                )
                .first)
            .width;
        expect(slot(3), closeTo(slot(1) / 3, 0.01), reason: 'Org Unit is still flex: 2');
        expect(slot(5), closeTo(slot(1) * 2 / 3, 0.01), reason: 'Assignee is still flex: 4');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
