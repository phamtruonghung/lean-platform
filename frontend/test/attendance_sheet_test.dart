/// The attendance sheet (issue #249, ADR-0040): the pre-filled rows, marking
/// an exception, adding a stand-in, and confirming — with the wire faked,
/// the one client seam (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/attendance_record_dialog.dart';
import 'package:lean_platform/people/attendance_sheet_screen.dart';
import 'package:lean_platform/widgets/app_search_field.dart';

import 'harness.dart';

Future<void> openSheet(WidgetTester tester, FakeWire wire, {String shiftInstanceId = '501'}) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/attendance/$shiftInstanceId',
    );

void main() {
  testWidgets('the sheet shows the pre-filled rows, and the shift instance was asked for',
      (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
    );
    await openSheet(tester, wire);

    expect(find.text('Alice Nguyen'), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.rowKey('1000')), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.confirmKey), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.confirmedChipKey), findsNothing);
    expect(wire.attendanceSheetRequests, contains('501'));
  });

  testWidgets(
      'a caller who could not have started the sheet sees a read-only "not started yet" state, '
      'with no edit or confirm controls', (tester) async {
    // No `attendanceSheet` scripted — the server's own shape for a caller
    // whose GET could not create and pre-fill one (issue #249's Grant fix).
    final wire = FakeWire();
    await openSheet(tester, wire);

    expect(wire.attendanceSheetRequests, contains('501'));
    expect(find.byKey(AttendanceSheetScreen.notStartedKey), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.confirmKey), findsNothing);
    expect(find.byKey(AttendanceSheetScreen.confirmedChipKey), findsNothing);
    expect(find.byKey(AttendanceSheetScreen.standInFieldKey()), findsNothing);
    expect(find.byKey(AttendanceSheetScreen.markKey('1000')), findsNothing);
    expect(find.byKey(AttendanceSheetScreen.removeKey('1000')), findsNothing);
  });

  testWidgets('marking a row late sends a PATCH naming the status, and the row updates',
      (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
    );
    await openSheet(tester, wire);

    await tapIn(tester, find.byKey(AttendanceSheetScreen.markKey('1000')));
    expect(find.byType(AttendanceRecordDialog), findsOneWidget);

    await tapIn(tester, find.byKey(AttendanceRecordDialog.statusFieldKey));
    await tapIn(tester, find.text('Late').last);
    await tapIn(tester, find.byKey(AttendanceRecordDialog.saveKey));

    expect(wire.attendanceRecordPatches.single.$1, '1000');
    expect(wire.attendanceRecordPatches.single.$2['attendanceStatus'], 'late');
    expect(find.byType(AttendanceRecordDialog), findsNothing);
    // Re-read, not the PATCH's own response spliced in — the row now shows
    // the corrected status.
    expect(find.textContaining('Late'), findsOneWidget);
  });

  testWidgets('marking a row absent with a reason sends the reason id, forcing minutes to zero',
      (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
      absenceReasons: [absenceReasonJson('SICK', 'Sickness', id: '40')],
    );
    await openSheet(tester, wire);

    await tapIn(tester, find.byKey(AttendanceSheetScreen.markKey('1000')));
    await tapIn(tester, find.byKey(AttendanceRecordDialog.statusFieldKey));
    await tapIn(tester, find.text('Absent (unplanned)').last);
    await tapIn(tester, find.byKey(AttendanceRecordDialog.reasonFieldKey));
    await tapIn(tester, find.text('Sickness').last);
    await tapIn(tester, find.byKey(AttendanceRecordDialog.saveKey));

    final sent = wire.attendanceRecordPatches.single.$2;
    expect(sent['attendanceStatus'], 'absent_unplanned');
    expect(sent['absenceReasonId'], '40');
    expect(sent.containsKey('workedMinutes'), isFalse);
    expect(find.byType(AttendanceRecordDialog), findsNothing);
  });

  testWidgets('adding a stand-in from the Directory sends a POST, and the row appears',
      (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: const [],
      employees: [employeeJson('20', 'E-20', 'Priya Shah')],
    );
    await openSheet(tester, wire);

    expect(find.byKey(AttendanceSheetScreen.emptyKey), findsOneWidget);

    await pickSuggestion(
      tester,
      fieldKey: AttendanceSheetScreen.standInFieldKey(),
      term: 'Priya',
      suggestionKey: AppSearchField.suggestionKey(AttendanceSheetScreen.standInFieldName, '20'),
    );

    expect(wire.attendanceStandInPosts.single.$1, '501');
    expect(wire.attendanceStandInPosts.single.$2, {'employeeId': '20'});
    // Re-read, not the POST's own response spliced in isolation — the newly
    // added row now shows on the sheet.
    expect(find.text('Stand-in Employee'), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.emptyKey), findsNothing);
  });

  testWidgets('removing a row sends a DELETE, and the row disappears', (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
    );
    await openSheet(tester, wire);

    await tapIn(tester, find.byKey(AttendanceSheetScreen.removeKey('1000')));

    expect(wire.attendanceRecordDeletes, contains('1000'));
    expect(find.byKey(AttendanceSheetScreen.rowKey('1000')), findsNothing);
    expect(find.byKey(AttendanceSheetScreen.emptyKey), findsOneWidget);
  });

  testWidgets('confirming sends a POST, and the sheet shows Confirmed', (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
    );
    await openSheet(tester, wire);

    await tapIn(tester, find.byKey(AttendanceSheetScreen.confirmKey));

    expect(wire.attendanceConfirmRequests, contains('501'));
    expect(find.byKey(AttendanceSheetScreen.confirmedChipKey), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.confirmKey), findsNothing);
  });

  testWidgets('a confirmed sheet can still be corrected: the row can still be marked',
      (tester) async {
    final wire = FakeWire(
      attendanceSheet: attendanceSheetJson(
        '900',
        '501',
        confirmedAt: '2026-05-04T20:00:00.000Z',
        confirmedByAccountId: '1',
      ),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
    );
    await openSheet(tester, wire);

    expect(find.byKey(AttendanceSheetScreen.confirmedChipKey), findsOneWidget);
    expect(find.byKey(AttendanceSheetScreen.markKey('1000')), findsOneWidget);

    await tapIn(tester, find.byKey(AttendanceSheetScreen.markKey('1000')));
    await tapIn(tester, find.byKey(AttendanceRecordDialog.statusFieldKey));
    await tapIn(tester, find.text('Late').last);
    await tapIn(tester, find.byKey(AttendanceRecordDialog.saveKey));

    expect(wire.attendanceRecordPatches.single.$2['attendanceStatus'], 'late');
    // The confirmation is unaffected by the correction.
    expect(find.byKey(AttendanceSheetScreen.confirmedChipKey), findsOneWidget);
  });
}
