/// The People Module's attendance family, the worked-hours table, the leave
/// queue and the Signature, measured (issue #393).
///
/// Six Screens were re-laid-out in this slice, and this file pins what a reader
/// can see of the result — the way `people_geometry_test.dart` pinned #392's,
/// `quality_geometry_test.dart` #390's and `production_geometry_test.dart`
/// #389's:
///
/// - **The attendance sheet is a matrix with a frozen name column.** At a 700px
///   window the Shell leaves the page 440, so the sheet's columns do not fit and
///   scroll sideways *inside* the frozen column: this file drags the scroll view
///   and proves the name cell's left edge did not move while a column beside it
///   did. A row is the tap floor (it holds two controls), and every cell's state
///   is a `StatusChip` whose word is always rendered, under a legend that names
///   the tones the sheet actually paints.
/// - **The picker** keeps one left edge: the title, the description and the
///   shifts below them start at the same x, and the worklist action wraps under
///   the title below the header's own `wrapBreakpoint` — the box, not the
///   window.
/// - **The two confirm queues** and the **leave queue** put the state and the
///   act in the row: inline and at the row's right end when the box can hold
///   them, under the record when it cannot, and never below the 44px floor.
/// - **Worked hours is a table that sums visibly**: a band, a 32px row per day
///   with its quantities end-aligned in tabular figures, and the window's totals
///   as the same table's footer row rather than a second card.
/// - **The Signature** is a plate: a named band, a [MySignatureScreen]
///   `imagePanelHeight` body on the Signature's own backdrop, the mark drawn
///   inside it at no more than `imageMeasure`, and the three acts under it.
/// - **The states** are the shared ones (#103): `SkeletonList`/`SkeletonDetail`
///   while a read is in flight, `PlatformEmptyState` when there is nothing, and
///   `PlatformFailureState` when a read failed — never a bare spinner or a lone
///   `Text`.
///
/// The app is pumped through the real router with the wire faked, as the
/// Module's own tests do; nothing here reaches into a Bloc. The app's real fonts
/// are loaded first, because the sheet measures its frozen column and its own
/// columns from their content — in `flutter_test`'s placeholder font every glyph
/// is a square, and a width measured there is a property of the placeholder
/// rather than of the app.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/attendance_picker_screen.dart';
import 'package:lean_platform/people/attendance_sheet_screen.dart';
import 'package:lean_platform/people/attendance_to_confirm_screen.dart';
import 'package:lean_platform/people/leave_requests_screen.dart';
import 'package:lean_platform/people/my_signature_screen.dart';
import 'package:lean_platform/people/worked_hours_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_page_header.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/empty_state.dart';
import 'package:lean_platform/widgets/failure_state.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

/// A 1x1 transparent PNG — the bytes `GET /api/people/me/signature` answers.
final List<int> _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0xDA, 0x63, 0x60, 0x60, 0x60, 0x60,
  0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x5E, 0xF5,
  0x95, 0x1E, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// One Org Unit, one production day with two shifts, a started sheet with two
/// people on it — one present, one on planned leave — a worked-hours window, two
/// leave requests, and a kept Signature.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      shiftInstances: [
        shiftInstanceSummaryJson('501', shiftDefinitionName: 'Day shift'),
        shiftInstanceSummaryJson(
          '502',
          shiftDefinitionName: 'Night shift',
          shiftDefinitionCode: 'NIGHT',
          hasSheet: true,
          confirmedAt: '2026-05-04T14:10:00.000Z',
        ),
      ],
      attendanceToConfirm: [
        attendanceToConfirmEntryJson('501', orgUnitName: 'Assembly', sheetState: 'missing'),
      ],
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [
        attendanceRecordJson('1000', '7', 'Alice Nguyen', employeeNo: 'EMP-2026-0007'),
        attendanceRecordJson(
          '1001',
          '8',
          'Bao Tran',
          employeeNo: 'EMP-2026-0008',
          attendanceStatus: 'absent_planned',
          absenceReasonId: 'HOL',
          workedMinutes: 0,
        ),
      ],
      employeeWorkedHours: workedHoursSummaryJson(
        days: [
          workedHoursDayJson('2026-05-04', workedMinutes: 450),
          workedHoursDayJson('2026-05-05', workedMinutes: 540, overtimeMinutes: 60),
        ],
        scheduledMinutes: 900,
        workedMinutes: 990,
        overtimeMinutes: 60,
      ),
      leaveRequestsMine: [
        leaveRequestJson('1', canDecide: true, canCancel: false),
        leaveRequestJson(
          '2',
          employeeName: 'Grace Hopper',
          leaveTypeName: 'Unpaid leave',
          status: 'pending',
          canDecide: true,
          canCancel: true,
          note: 'Family trip',
        ),
      ],
    )..mySignature = Uint8List.fromList(_png);

/// Pumps one address at a stated window and text scale — the two variables every
/// measurement here is a function of.
Future<void> _pumpAt(
  WidgetTester tester, {
  required String location,
  required double width,
  FakeWire? wire,
  double textScale = 1,
  double height = 1400,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: (wire ?? _wire()).client,
    initialLocation: location,
  );
}

const String _sheet = '/attendance/501';
const String _picker = '/attendance';
const String _toConfirm = '/attendance/to-confirm';
const String _workedHours = '/directory/42/work-hours';
const String _leave = '/leave-requests';
const String _signature = '/me/signature';

/// The widths the ticket names: a phone-class window, the middle width a
/// laptop gives a half-width pane, and a wide one.
const List<double> _widths = [700, 900, 1280];

void main() {
  setUpAll(loadAppFonts);

  group('the attendance sheet is a matrix with a frozen name column', () {
    testWidgets('at 700 the columns scroll under a name column that does not move',
        (tester) async {
      await _pumpAt(tester, location: _sheet, width: 700);
      expect(tester.takeException(), isNull, reason: 'the sheet at 700');

      final row = find.byKey(AttendanceSheetScreen.rowKey('1000'));
      expect(row, findsOneWidget, reason: 'the sheet at 700: no first row');
      // The row holds two controls, so it is the tap floor rather than 32.
      expect(
        tester.getSize(row).height,
        AppTouchTarget.min,
        reason: 'the sheet at 700: the row is not the tap floor',
      );

      // The state is a chip, and its word is rendered (colour is never the only
      // carrier). Scoped to the matrix so the legend's own 'Present' does not
      // answer for it.
      final status = find.descendant(
        of: find.byKey(AttendanceSheetScreen.matrixKey),
        matching: find.text('Present'),
      );
      expect(status, findsOneWidget, reason: 'the sheet at 700: the status chip');

      final frozenBefore = tester.getTopLeft(row).dx;
      final statusBefore = tester.getTopLeft(status).dx;
      // 440 of page against the columns' own width: the answer at 700 is a
      // sideways scroll inside the frozen column, not a squeezed table.
      await tester.drag(find.byKey(AttendanceSheetScreen.scrollKey), const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(row).dx,
        frozenBefore,
        reason: 'the sheet at 700: the name column moved with the scroll',
      );
      expect(
        tester.getTopLeft(status).dx,
        lessThan(statusBefore),
        reason: 'the sheet at 700: the columns did not scroll at all',
      );
    });

    testWidgets('at 1280 every column fits, and the band and the row share the first column',
        (tester) async {
      await _pumpAt(tester, location: _sheet, width: 1280);
      expect(tester.takeException(), isNull, reason: 'the sheet at 1280');

      expect(find.byType(AppTableHeader), findsOneWidget, reason: 'the sheet at 1280: no band');
      final row = find.byKey(AttendanceSheetScreen.rowKey('1000'));
      final card = find.byKey(AttendanceSheetScreen.matrixKey);
      // 1020 of page will hold the frozen column and the four after it: the last
      // column's own label sits inside the card rather than past its edge.
      final actions = find.byKey(AppTableHeader.labelKey('Actions'));
      expect(actions, findsOneWidget, reason: 'the sheet at 1280: no Actions column');
      expect(
        tester.getTopRight(actions).dx,
        lessThanOrEqualTo(tester.getTopRight(card).dx),
        reason: 'the sheet at 1280: the last column runs past the matrix',
      );
      // One left edge: the frozen band's label and the frozen cell's text.
      expect(
        tester.getTopLeft(find.byKey(AppTableHeader.labelKey('Employee'))).dx,
        closeTo(Spacing.md + tester.getTopLeft(card).dx, 1.5),
        reason: 'the sheet at 1280: the frozen band is not at the matrix left edge',
      );
      expect(
        tester.getTopLeft(row).dx,
        closeTo(tester.getTopLeft(card).dx, 1.5),
        reason: 'the sheet at 1280: the frozen column is not at the matrix left edge',
      );
    });

    testWidgets('at 900 the matrix fits, and the slack goes to the name column',
        (tester) async {
      // The narrow width first: the frozen column's own width there is its
      // content's, because nothing is spare to give it.
      await _pumpAt(tester, location: _sheet, width: 700);
      final narrowFrozen =
          tester.getSize(find.byKey(AttendanceSheetScreen.rowKey('1000'))).width;

      await _pumpAt(tester, location: _sheet, width: 900);
      expect(tester.takeException(), isNull, reason: 'the sheet at 900');

      final matrix = find.byKey(AttendanceSheetScreen.matrixKey);
      final row = find.byKey(AttendanceSheetScreen.rowKey('1000'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: matrix, matching: find.byType(Scrollable)),
      );
      // 900 of window leaves the page 640 and this card 608, while the matrix
      // needs 560.9 at a text scale of 1 (a 108.4px name column plus 452.5px of
      // columns) — so the middle width is where the sideways scroll stops. A
      // breakpoint read off the window, or prose claiming this box still
      // scrolls, is caught here.
      expect(
        scrollable.position.maxScrollExtent,
        0,
        reason: 'the sheet at 900: the columns still scroll',
      );
      // What the columns do not need goes to the frozen name column rather than
      // to a gutter, so it is wider here than at 700, where it is only as wide
      // as its content.
      expect(
        tester.getSize(row).width,
        greaterThan(narrowFrozen + 1),
        reason: 'the sheet at 900: the name column did not take the slack',
      );
      expect(
        tester.getSize(row).height,
        AppTouchTarget.min,
        reason: 'the sheet at 900: the row is not the tap floor',
      );
      expect(find.byKey(AttendanceSheetScreen.legendKey), findsOneWidget,
          reason: 'the sheet at 900: the legend is gone');
    });

    testWidgets('at twice the text the frozen column still holds, at 700 and at 1280',
        (tester) async {
      for (final width in _widths) {
        await _pumpAt(tester, location: _sheet, width: width, textScale: 2, height: 2400);
        expect(tester.takeException(), isNull, reason: 'the sheet at $width x2');

        final row = find.byKey(AttendanceSheetScreen.rowKey('1000'));
        expect(row, findsOneWidget, reason: 'the sheet at $width x2: no row');
        // The row grows with the text rather than clipping what is in it, and
        // both halves of the matrix grow together.
        expect(
          tester.getSize(row).height,
          AppTouchTarget.min * 2,
          reason: 'the sheet at $width x2: the row did not grow with the text',
        );
        expect(find.byKey(AttendanceSheetScreen.legendKey), findsOneWidget,
            reason: 'the sheet at $width x2: the legend is gone');
      }
    });

    testWidgets('an unopened sheet says so through the shared empty state', (tester) async {
      final empty = FakeWire(
        attendanceSheet: attendanceSheetJson('900', '501'),
        attendanceRecords: const [],
      );
      await _pumpAt(tester, location: _sheet, width: 1280, wire: empty);
      expect(tester.takeException(), isNull, reason: 'the sheet with nobody on it');
      expect(find.byKey(AttendanceSheetScreen.emptyKey), findsOneWidget);
      expect(find.byType(PlatformEmptyState), findsOneWidget);
      expect(find.byKey(AttendanceSheetScreen.legendKey), findsNothing);
    });

    testWidgets('a failed read offers the shared retry, not a bare sentence', (tester) async {
      // Its own pump: a second `pumpApp` on the same address would reuse the
      // Screen's Bloc and never issue the read this case is about.
      await _pumpAt(tester, location: _sheet, width: 1280, wire: FakeWire(attendanceSheetStatus: 500));
      expect(tester.takeException(), isNull, reason: 'the sheet after a failed read');
      expect(find.byKey(AttendanceSheetScreen.failedKey), findsOneWidget);
      expect(find.byKey(AttendanceSheetScreen.retryKey), findsOneWidget);
      expect(find.byType(PlatformFailureState), findsOneWidget);
      expect(find.byKey(AttendanceSheetScreen.matrixKey), findsNothing);
    });
  });

  group('the attendance picker keeps one left edge', () {
    Future<void> openShifts(WidgetTester tester) async {
      // Choose the Org Unit, then a production day: the two choices the read
      // waits for.
      await tapIn(tester, find.byKey(AttendancePickerScreen.orgUnitRowKey('10')));
      await tapIn(tester, find.byKey(AttendancePickerScreen.dateFieldKey));
      await tapIn(tester, find.text('OK'));
    }

    testWidgets('at 1280 the action sits on the title row and the shifts are one card',
        (tester) async {
      await _pumpAt(tester, location: _picker, width: 1280);
      expect(tester.takeException(), isNull, reason: 'the picker at 1280');
      await openShifts(tester);
      expect(tester.takeException(), isNull, reason: 'the picker at 1280 with shifts');

      final title = find.byKey(AppPageHeader.titleKey);
      final action = find.byKey(AttendancePickerScreen.toConfirmLinkKey);
      final description = find.byKey(AppPageHeader.descriptionKey);
      // One left edge for the title and the description.
      expect(
        tester.getTopLeft(description).dx,
        closeTo(tester.getTopLeft(title).dx, 1.5),
        reason: 'the picker at 1280: the description does not start at the title',
      );
      // 1020 of page is over the header's own 560, so the action is beside the
      // title rather than under it.
      expect(
        tester.getTopLeft(action).dx,
        greaterThan(tester.getTopRight(title).dx),
        reason: 'the picker at 1280: the action did not stay at the row end',
      );
      final row = find.byKey(AttendancePickerScreen.shiftRowKey('501'));
      expect(row, findsOneWidget, reason: 'the picker at 1280: no shift row');
      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the picker at 1280: the shift row is under the tap floor',
      );
      // The three sentences are chips now, still rendered.
      expect(find.descendant(of: row, matching: find.text('Not opened yet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AttendancePickerScreen.shiftRowKey('502')),
          matching: find.text('Confirmed'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(AttendancePickerScreen.catalogueKey), findsOneWidget);
    });

    testWidgets('at 900 the action is back on the title row, and the shifts are reached',
        (tester) async {
      await _pumpAt(tester, location: _picker, width: 900, height: 2400);
      expect(tester.takeException(), isNull, reason: 'the picker at 900');

      final title = find.byKey(AppPageHeader.titleKey);
      final action = find.byKey(AttendancePickerScreen.toConfirmLinkKey);
      // 900 of window gives the header 608, over the 560 it wraps at, so the
      // middle width sits on the other side of that breakpoint from 700, where
      // the action drops under the title. Compared on the title's own bottom
      // edge rather than a hard-coded y.
      expect(
        tester.getTopLeft(action).dy,
        lessThan(tester.getBottomLeft(title).dy),
        reason: 'the picker at 900: the action dropped under the title',
      );
      expect(
        tester.getSize(action).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the picker at 900: the action is under the tap floor',
      );
      await openShifts(tester);
      expect(tester.takeException(), isNull, reason: 'the picker at 900 with shifts');
      expect(find.byKey(AttendancePickerScreen.shiftRowKey('501')), findsOneWidget,
          reason: 'the picker at 900: no shift row');
    });

    testWidgets('at 700 the action wraps under the title, and at twice the text it still holds',
        (tester) async {
      for (final scale in [1.0, 2.0]) {
        await _pumpAt(tester, location: _picker, width: 700, textScale: scale, height: 2400);
        expect(tester.takeException(), isNull, reason: 'the picker at 700 x$scale');

        final title = find.byKey(AppPageHeader.titleKey);
        final action = find.byKey(AttendancePickerScreen.toConfirmLinkKey);
        // 440 of page is under the 560 the header wraps at, scaled by the
        // reader's text: the action drops under the title.
        expect(
          tester.getTopLeft(action).dy,
          greaterThan(tester.getTopLeft(title).dy),
          reason: 'the picker at 700 x$scale: the action did not wrap',
        );
        expect(
          tester.getSize(action).height,
          greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'the picker at 700 x$scale: the action is under the tap floor',
        );
        // One left edge there too: the wrapped action starts at the title's x.
        expect(
          tester.getTopLeft(action).dx,
          closeTo(tester.getTopLeft(title).dx, 1.5),
          reason: 'the picker at 700 x$scale: the wrapped action is not on the title edge',
        );
      }
    });

    testWidgets('at 1280 with twice the text the action drops under the title',
        (tester) async {
      await _pumpAt(tester, location: _picker, width: 1280, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull, reason: 'the picker at 1280 x2');
      // 1020 of page against a 560 breakpoint at twice the text (1120): the box
      // is over the raw number and under the scaled one, which is exactly the
      // case #379/#381 shipped wrong — the action must wrap here. The shape is
      // read off its x, not its y: a centred action in an unwrapped row can sit
      // lower than the title's own top line, so only the left edge tells the two
      // layouts apart.
      final title = find.byKey(AppPageHeader.titleKey);
      final action = find.byKey(AttendancePickerScreen.toConfirmLinkKey);
      expect(
        tester.getTopLeft(action).dx,
        closeTo(tester.getTopLeft(title).dx, 1.5),
        reason: 'the picker at 1280 x2: the action did not wrap at twice the text',
      );
    });

    testWidgets('the browser at 700 still reaches the shifts, and nothing overflows',
        (tester) async {
      await _pumpAt(tester, location: _picker, width: 700, height: 2400);
      expect(tester.takeException(), isNull, reason: 'the picker at 700 with a browser');
      await openShifts(tester);
      expect(tester.takeException(), isNull, reason: 'the picker at 700 with shifts');
      final row = find.byKey(AttendancePickerScreen.shiftRowKey('501'));
      expect(row, findsOneWidget, reason: 'the picker at 700: no shift row');
      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the picker at 700: the shift row is under the tap floor',
      );
      // The chip and the chevron stay inside the row rather than running off it.
      expect(
        tester.getTopRight(find.descendant(of: row, matching: find.text('Not opened yet'))).dx,
        lessThanOrEqualTo(tester.getTopRight(row).dx),
        reason: 'the picker at 700: the state chip runs past the row',
      );
    });

    testWidgets('a day with no shifts is the shared empty state, not a bare sentence',
        (tester) async {
      await _pumpAt(tester, location: _picker, width: 1280, wire: FakeWire(
        sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
        orgUnits: {
          null: [orgUnitJson('10', 'Assembly')],
        },
      ));
      await openShifts(tester);
      expect(tester.takeException(), isNull, reason: 'the picker with no shifts');
      expect(find.byKey(AttendancePickerScreen.emptyKey), findsOneWidget);
      expect(find.byType(PlatformEmptyState), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);
    });

    testWidgets('a failed read offers the shared retry, not a bare sentence',
        (tester) async {
      // Its own pump: the read has to fail on the way in, and a second pump on
      // the same address would reuse the Screen's Bloc — the sheet's own
      // failed-read case makes the same point.
      await _pumpAt(tester, location: _picker, width: 1280, wire: FakeWire(
        sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
        orgUnits: {
          null: [orgUnitJson('10', 'Assembly')],
        },
        shiftInstancesStatus: 500,
      ));
      await openShifts(tester);
      expect(tester.takeException(), isNull, reason: 'the picker after a failed read');
      expect(find.byKey(AttendancePickerScreen.failureKey), findsOneWidget);
      expect(find.byKey(AttendancePickerScreen.retryKey), findsOneWidget);
      expect(find.byType(PlatformFailureState), findsOneWidget);
      expect(find.byKey(AttendancePickerScreen.catalogueKey), findsNothing);
      expect(find.byType(SkeletonList), findsNothing);
    });
  });

  group('the to-confirm queue puts the state and the act in the row', () {
    testWidgets('at 1280 the act is against the row end, and at 700 it drops under the shift',
        (tester) async {
      await _pumpAt(tester, location: _toConfirm, width: 1280);
      expect(tester.takeException(), isNull, reason: 'the queue at 1280');

      final row = find.byKey(AttendanceToConfirmScreen.entryKey('501'));
      final open = find.byKey(AttendanceToConfirmScreen.openKey('501'));
      expect(row, findsOneWidget, reason: 'the queue at 1280: no entry');
      expect(open, findsOneWidget, reason: 'the queue at 1280: no act');
      expect(
        tester.getSize(open).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the queue at 1280: the act is under the tap floor',
      );
      expect(
        tester.getTopRight(open).dx,
        closeTo(tester.getTopRight(row).dx - Spacing.md, 1.5),
        reason: 'the queue at 1280: the act is not against the row end',
      );
      // The state is a chip on the row, and its word is rendered.
      expect(find.descendant(of: row, matching: find.text('Not opened yet')), findsOneWidget);

      await _pumpAt(tester, location: _toConfirm, width: 700);
      expect(tester.takeException(), isNull, reason: 'the queue at 700');
      final narrowRow = find.byKey(AttendanceToConfirmScreen.entryKey('501'));
      final narrowOpen = find.byKey(AttendanceToConfirmScreen.openKey('501'));
      final shift = find.descendant(of: narrowRow, matching: find.textContaining('Day shift'));
      expect(
        tester.getTopLeft(narrowOpen).dy,
        greaterThan(tester.getBottomLeft(shift).dy),
        reason: 'the queue at 700: the act did not drop under the shift',
      );
    });

    testWidgets('at 900 the row still takes the narrow shape', (tester) async {
      await _pumpAt(tester, location: _toConfirm, width: 900, height: 2400);
      expect(tester.takeException(), isNull, reason: 'the queue at 900');
      final row = find.byKey(AttendanceToConfirmScreen.entryKey('501'));
      final act = find.byKey(AttendanceToConfirmScreen.openKey('501'));
      final shift = find.descendant(of: row, matching: find.textContaining('Day shift'));
      // 900 of window gives this row 608, under the 640 it splits at — the
      // middle width is on the narrow side of the breakpoint, and it has to stay
      // there from the box rather than drift to the inline shape as the window
      // grows.
      expect(
        tester.getTopLeft(act).dy,
        greaterThan(tester.getBottomLeft(shift).dy),
        reason: 'the queue at 900: the act did not drop under the shift',
      );
      expect(
        tester.getSize(act).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the queue at 900: the act is under the tap floor',
      );
    });

    testWidgets('at twice the text the row holds at 700 and at 1280', (tester) async {
      for (final width in _widths) {
        await _pumpAt(tester, location: _toConfirm, width: width, textScale: 2, height: 2400);
        expect(tester.takeException(), isNull, reason: 'the queue at $width x2');
        expect(find.byKey(AttendanceToConfirmScreen.entryKey('501')), findsOneWidget,
            reason: 'the queue at $width x2: no entry');
        expect(find.byKey(AttendanceToConfirmScreen.openKey('501')), findsOneWidget,
            reason: 'the queue at $width x2: the act is lost');
        // The shape, not just the presence: 988 of box at twice the text is an
        // effective 494, under the 640 the row splits at, so the act drops under
        // the shift rather than squeezing it (#379/#381's bug class).
        final row = find.byKey(AttendanceToConfirmScreen.entryKey('501'));
        final shift = find.descendant(of: row, matching: find.textContaining('Day shift'));
        expect(
          tester.getTopLeft(find.byKey(AttendanceToConfirmScreen.openKey('501'))).dy,
          greaterThan(tester.getBottomLeft(shift).dy),
          reason: 'the queue at $width x2: the row did not take the narrow shape',
        );
      }
    });

    testWidgets('nothing to confirm is the shared empty state, not a bare sentence',
        (tester) async {
      await _pumpAt(tester, location: _toConfirm, width: 1280, wire: FakeWire());
      expect(tester.takeException(), isNull, reason: 'the empty queue');
      expect(find.byKey(AttendanceToConfirmScreen.emptyKey), findsOneWidget);
      expect(find.byType(PlatformEmptyState), findsOneWidget);
      // Nothing has been filtered, so this is the good-news story: nothing is
      // outstanding anywhere this caller may act, not "your filter matched
      // none".
      expect(
        tester.widget<PlatformEmptyState>(find.byKey(AttendanceToConfirmScreen.emptyKey)).variant,
        EmptyStateVariant.noneExist,
        reason: 'the unfiltered empty queue claimed a filter had matched nothing',
      );
    });

    testWidgets('an empty queue inside a window is the none-matched variant',
        (tester) async {
      await _pumpAt(tester, location: _toConfirm, width: 1280, height: 2400, wire: FakeWire());
      expect(tester.takeException(), isNull, reason: 'the empty queue');
      // Narrow the window: an empty read now means "nothing in this window",
      // which is a different story from "nothing is outstanding anywhere" — and
      // only the second is what "every past shift has a confirmed sheet" says.
      await tapIn(tester, find.byKey(AttendanceToConfirmScreen.fromFieldKey));
      await tapIn(tester, find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the empty queue, filtered');
      expect(
        tester.widget<PlatformEmptyState>(find.byKey(AttendanceToConfirmScreen.emptyKey)).variant,
        EmptyStateVariant.noneMatched,
        reason: 'a filtered empty queue still claimed every past shift was confirmed',
      );
      expect(
        find.text('Every past shift you can confirm has a confirmed sheet.'),
        findsNothing,
        reason: 'a filtered empty queue kept the unfiltered sentence',
      );
    });
  });

  group('worked hours is a table that sums visibly', () {
    for (final width in _widths) {
      testWidgets('at ${width.toInt()}px the band, the rows and the totals share their columns',
          (tester) async {
        await _pumpAt(tester, location: _workedHours, width: width);
        expect(tester.takeException(), isNull, reason: 'worked hours at $width');

        expect(find.byType(AppTableHeader), findsOneWidget,
            reason: 'worked hours at $width: no band');
        expect(
          tester.getSize(find.byType(AppTableHeader)).height,
          AppTableHeader.height,
          reason: 'worked hours at $width: the band is not its own height',
        );
        final first = find.byKey(WorkedHoursScreen.rowKey('2026-05-04'));
        final second = find.byKey(WorkedHoursScreen.rowKey('2026-05-05'));
        final totals = find.byKey(WorkedHoursScreen.totalsKey);
        expect(first, findsOneWidget, reason: 'worked hours at $width: no first day');
        expect(second, findsOneWidget, reason: 'worked hours at $width: no second day');
        expect(
          tester.getSize(first).height,
          AppTableRow.height,
          reason: 'worked hours at $width: a day row is not its own height',
        );
        // The totals are the same table's footer: below the last day, inside the
        // same card, wearing the band's own fill.
        expect(
          tester.getTopLeft(totals).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(second).dy - 0.5),
          reason: 'worked hours at $width: the totals are not under the last day',
        );
        // Two durations of different lengths end at the same x — a column of
        // figures compares down its right edge.
        expect(
          tester.getTopRight(find.byKey(const ValueKey<String>('work-hours-worked-2026-05-04'))).dx,
          closeTo(
            tester.getTopRight(find.byKey(const ValueKey<String>('work-hours-worked-2026-05-05'))).dx,
            1,
          ),
          reason: 'worked hours at $width: the quantities are not end-aligned',
        );
      });
    }

    testWidgets('at twice the text the table still holds, at 700 and at 1280', (tester) async {
      for (final width in _widths) {
        await _pumpAt(tester, location: _workedHours, width: width, textScale: 2, height: 2400);
        expect(tester.takeException(), isNull, reason: 'worked hours at $width x2');
        expect(find.byKey(WorkedHoursScreen.totalsKey), findsOneWidget,
            reason: 'worked hours at $width x2: the totals are gone');
        expect(find.text('1h 0m overtime'), findsOneWidget,
            reason: 'worked hours at $width x2: the overtime total is gone');
      }
    });

    testWidgets('an empty window is the shared empty state and has no totals row',
        (tester) async {
      await _pumpAt(tester, location: _workedHours, width: 1280, wire: FakeWire());
      expect(tester.takeException(), isNull, reason: 'worked hours with no days');
      expect(find.byKey(WorkedHoursScreen.emptyKey), findsOneWidget);
      expect(find.byType(PlatformEmptyState), findsOneWidget);
      expect(find.byKey(WorkedHoursScreen.totalsKey), findsNothing);
    });
  });

  group('the leave queue puts the decision in the row', () {
    testWidgets('at 1280 the decisions are against the row end, at 700 under the record',
        (tester) async {
      await _pumpAt(tester, location: _leave, width: 1280);
      expect(tester.takeException(), isNull, reason: 'leave at 1280');

      final row = find.byKey(LeaveRequestsScreen.rowKey('1'));
      final approve = find.byKey(LeaveRequestsScreen.approveKey('1'));
      expect(row, findsOneWidget, reason: 'leave at 1280: no row');
      expect(approve, findsOneWidget, reason: 'leave at 1280: no Approve');
      expect(find.descendant(of: row, matching: find.text('Pending')), findsOneWidget,
          reason: 'leave at 1280: the state is not a chip on the row');
      expect(
        tester.getSize(approve).height,
        greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'leave at 1280: the decision is under the tap floor',
      );
      expect(
        tester.getTopRight(find.byKey(LeaveRequestsScreen.rejectKey('1'))).dx,
        closeTo(tester.getTopRight(row).dx - Spacing.md, 1.5),
        reason: 'leave at 1280: the decisions are not against the row end',
      );

      await _pumpAt(tester, location: _leave, width: 700);
      expect(tester.takeException(), isNull, reason: 'leave at 700');
      final narrowRow = find.byKey(LeaveRequestsScreen.rowKey('2'));
      final narrowApprove = find.byKey(LeaveRequestsScreen.approveKey('2'));
      final name = find.descendant(of: narrowRow, matching: find.textContaining('Grace Hopper'));
      expect(
        tester.getTopLeft(narrowApprove).dy,
        greaterThan(tester.getBottomLeft(name).dy),
        reason: 'leave at 700: the decisions did not drop under the record',
      );
      expect(
        tester.getSize(narrowRow).height,
        greaterThan(AppTouchTarget.min),
        reason: 'leave at 700: the two-line row did not grow for its actions',
      );
    });

    testWidgets('at 900 the decisions still drop under the record', (tester) async {
      await _pumpAt(tester, location: _leave, width: 900, height: 2400);
      expect(tester.takeException(), isNull, reason: 'leave at 900');
      final row = find.byKey(LeaveRequestsScreen.rowKey('2'));
      final approve = find.byKey(LeaveRequestsScreen.approveKey('2'));
      final name = find.descendant(of: row, matching: find.textContaining('Grace Hopper'));
      expect(
        tester.getTopLeft(approve).dy,
        greaterThan(tester.getBottomLeft(name).dy),
        reason: 'leave at 900: the decisions did not drop under the record',
      );
      expect(
        tester.getSize(row).height,
        greaterThan(AppTouchTarget.min),
        reason: 'leave at 900: the two-line row did not grow for its actions',
      );
    });

    testWidgets('at twice the text the decisions stay reachable at 700 and at 1280',
        (tester) async {
      for (final width in _widths) {
        await _pumpAt(tester, location: _leave, width: width, textScale: 2, height: 2400);
        expect(tester.takeException(), isNull, reason: 'leave at $width x2');
        expect(find.byKey(LeaveRequestsScreen.approveKey('2')), findsOneWidget,
            reason: 'leave at $width x2: Approve is lost');
        expect(find.byKey(LeaveRequestsScreen.cancelKey('2')), findsOneWidget,
            reason: 'leave at $width x2: Cancel request is lost');
        // The shape, not just the presence: 988 of box at twice the text is an
        // effective 494, under the 640 the row splits at — so the decisions drop
        // under the record. A breakpoint compared raw would keep them inline and
        // still "pass" a presence-only check (#379/#381's bug class).
        final row = find.byKey(LeaveRequestsScreen.rowKey('2'));
        final name = find.descendant(of: row, matching: find.textContaining('Grace Hopper'));
        expect(
          tester.getTopLeft(find.byKey(LeaveRequestsScreen.approveKey('2'))).dy,
          greaterThan(tester.getBottomLeft(name).dy),
          reason: 'leave at $width x2: the decisions did not take the narrow shape',
        );
      }
    });
  });

  group('the Signature is a plate with its acts under it', () {
    for (final width in _widths) {
      testWidgets('at ${width.toInt()}px the mark is drawn inside a named plate',
          (tester) async {
        await _pumpAt(tester, location: _signature, width: width);
        expect(tester.takeException(), isNull, reason: 'signature at $width');

        final plate = find.byKey(MySignatureScreen.imagePlateKey);
        final image = find.byKey(MySignatureScreen.imageKey);
        expect(plate, findsOneWidget, reason: 'signature at $width: no plate');
        expect(
          tester.getSize(plate).height,
          MySignatureScreen.imagePanelHeight,
          reason: 'signature at $width: the plate is not its own height',
        );
        expect(image, findsOneWidget, reason: 'signature at $width: no mark');
        // The mark stays inside the plate, and no wider than the measure.
        expect(
          tester.getBottomRight(image).dx,
          lessThanOrEqualTo(tester.getBottomRight(plate).dx),
          reason: 'signature at $width: the mark runs past its plate',
        );
        expect(
          tester.getSize(image).width,
          lessThanOrEqualTo(MySignatureScreen.imageMeasure),
          reason: 'signature at $width: the mark is wider than the measure',
        );
        // The three acts sit under the plate, at the tap floor.
        final upload = find.byKey(MySignatureScreen.uploadKey);
        expect(
          tester.getTopLeft(upload).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(plate).dy),
          reason: 'signature at $width: the acts are not under the plate',
        );
        expect(
          tester.getSize(upload).height,
          greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'signature at $width: the act is under the tap floor',
        );
      });
    }

    testWidgets('at twice the text the plate holds at 700 and at 1280', (tester) async {
      for (final width in _widths) {
        await _pumpAt(tester, location: _signature, width: width, textScale: 2, height: 2400);
        expect(tester.takeException(), isNull, reason: 'signature at $width x2');
        expect(find.byKey(MySignatureScreen.imagePlateKey), findsOneWidget,
            reason: 'signature at $width x2: the plate is gone');
        expect(find.byKey(MySignatureScreen.removeKey), findsOneWidget,
            reason: 'signature at $width x2: Remove is lost');
      }
    });

    testWidgets('reading the Signature is the shared detail skeleton, never a spinner',
        (tester) async {
      final wire = FakeWire()..mySignatureGate = Completer<void>();
      await _pumpAt(tester, location: _signature, width: 1280, wire: wire);
      expect(find.byKey(MySignatureScreen.loadingKey), findsOneWidget);
      expect(find.byType(SkeletonDetail), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      wire.mySignatureGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(MySignatureScreen.loadingKey), findsNothing);
    });
  });
}
