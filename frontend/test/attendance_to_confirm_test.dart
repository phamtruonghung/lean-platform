/// The attendance-to-confirm worklist (issue #250): the list itself, its
/// empty state, and following an entry through to its sheet — with the wire
/// faked, the one client seam (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/attendance_picker_screen.dart';
import 'package:lean_platform/people/attendance_sheet_screen.dart';
import 'package:lean_platform/people/attendance_to_confirm_screen.dart';

import 'harness.dart';

Future<void> openWorklist(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/attendance/to-confirm',
    );

void main() {
  testWidgets('the worklist shows each entry, naming the shift, its production day, its Org Unit '
      'and whether the sheet is missing or unconfirmed', (tester) async {
    final wire = FakeWire(
      attendanceToConfirm: [
        attendanceToConfirmEntryJson(
          '501',
          orgUnitName: 'Line 1',
          shiftDefinitionName: 'Day shift',
          productionDate: '2026-05-04',
          sheetState: 'missing',
        ),
        attendanceToConfirmEntryJson(
          '502',
          orgUnitName: 'Line 2',
          shiftDefinitionName: 'Night shift',
          productionDate: '2026-05-05',
          sheetState: 'unconfirmed',
        ),
      ],
    );
    await openWorklist(tester, wire);

    expect(find.byKey(AttendanceToConfirmScreen.entryKey('501')), findsOneWidget);
    expect(find.byKey(AttendanceToConfirmScreen.entryKey('502')), findsOneWidget);
    expect(find.textContaining('Day shift'), findsOneWidget);
    expect(find.textContaining('2026-05-04'), findsOneWidget);
    expect(find.textContaining('Line 1'), findsOneWidget);
    expect(find.textContaining('Not opened yet'), findsOneWidget);
    expect(find.textContaining('Night shift'), findsOneWidget);
    expect(find.textContaining('Started, not yet confirmed'), findsOneWidget);
    expect(find.byKey(AttendanceToConfirmScreen.emptyKey), findsNothing);
    // No filters were set, so the request carried none.
    expect(wire.attendanceToConfirmRequests.single, isEmpty);
  });

  testWidgets('an empty worklist shows the empty state, not a blank list', (tester) async {
    final wire = FakeWire(); // attendanceToConfirm defaults to [].
    await openWorklist(tester, wire);

    expect(find.byKey(AttendanceToConfirmScreen.emptyKey), findsOneWidget);
    expect(find.text('Nothing to confirm here.'), findsOneWidget);
  });

  testWidgets('following an entry opens the shift\'s own attendance sheet', (tester) async {
    final wire = FakeWire(
      attendanceToConfirm: [attendanceToConfirmEntryJson('501')],
      // No `attendanceSheet` scripted — the sheet Screen's own read-only
      // "not started yet" state, which is enough to prove the navigation
      // reached the real sheet address and asked for the right shift
      // instance (attendance_sheet_test.dart's own precedent).
    );
    await openWorklist(tester, wire);

    await tapIn(tester, find.byKey(AttendanceToConfirmScreen.entryKey('501')));

    expect(find.byType(AttendanceSheetScreen), findsOneWidget);
    expect(wire.attendanceSheetRequests, contains('501'));
    expect(locationOf(tester, find.byType(AttendanceSheetScreen)), '/attendance/501');
  });

  testWidgets('the Attendance picker links to the worklist at its own nested address', (tester) async {
    final wire = FakeWire(attendanceToConfirm: [attendanceToConfirmEntryJson('501')]);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/attendance',
    );

    await tapIn(tester, find.byKey(AttendancePickerScreen.toConfirmLinkKey));

    expect(find.byType(AttendanceToConfirmScreen), findsOneWidget);
    expect(locationOf(tester, find.byType(AttendanceToConfirmScreen)), '/attendance/to-confirm');
    expect(find.byKey(AttendanceToConfirmScreen.entryKey('501')), findsOneWidget);
  });

  testWidgets('choosing a From date sends it as a filter on the next read', (tester) async {
    final wire = FakeWire(attendanceToConfirm: [attendanceToConfirmEntryJson('501')]);
    await openWorklist(tester, wire);
    expect(wire.attendanceToConfirmRequests.single, isEmpty);

    await tapIn(tester, find.byKey(AttendanceToConfirmScreen.fromFieldKey));
    // AppDateField opens a real showDatePicker; confirming today's default
    // selection is enough to prove a value reaches the Bloc and a second
    // request is sent carrying it — the exact date is incidental here.
    await tapIn(tester, find.text('OK'));

    expect(wire.attendanceToConfirmRequests.length, 2);
    expect(wire.attendanceToConfirmRequests.last.containsKey('from'), isTrue);
  });
}
