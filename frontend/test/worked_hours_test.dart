/// The per-Employee worked-hours summary (issue #263): its day rows, its
/// totals, the empty state, and how a From/To re-read sends the two filters
/// to the wire — with the one client seam faked (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/worked_hours_screen.dart';

import 'harness.dart';

Future<void> openWorkedHours(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/directory/42/work-hours',
    );

void main() {
  testWidgets('shows each confirmed day and the window totals', (tester) async {
    final wire = FakeWire(
      employeeWorkedHours: workedHoursSummaryJson(
        days: [
          workedHoursDayJson('2026-05-04'),
          workedHoursDayJson('2026-05-05', workedMinutes: 540, overtimeMinutes: 60),
        ],
        scheduledMinutes: 990,
        workedMinutes: 990,
        overtimeMinutes: 60,
      ),
    );
    await openWorkedHours(tester, wire);

    expect(find.byKey(WorkedHoursScreen.rowKey('2026-05-04')), findsOneWidget);
    expect(find.byKey(WorkedHoursScreen.rowKey('2026-05-05')), findsOneWidget);
    // 450 minutes renders as "7h 30m", set on the second day's row too by the
    // 540+60 overtime pair, so assert the totals card's bottom line is the
    // server's own numbers, not a client re-derivation.
    expect(find.byKey(WorkedHoursScreen.totalsKey), findsOneWidget);
    expect(find.text('16h 30m worked'), findsOneWidget);
    expect(find.text('1h 0m overtime'), findsOneWidget);
    expect(find.text('of 16h 30m scheduled'), findsOneWidget);
    expect(find.byKey(WorkedHoursScreen.emptyKey), findsNothing);
    // The initial read carried no filters.
    expect(wire.employeeWorkedHoursRequests.single.$2, isEmpty);
  });

  testWidgets('naming the overtime a day earned', (tester) async {
    final wire = FakeWire(
      employeeWorkedHours: workedHoursSummaryJson(
        days: [workedHoursDayJson('2026-05-05', workedMinutes: 540, overtimeMinutes: 60)],
        workedMinutes: 540,
        scheduledMinutes: 450,
        overtimeMinutes: 60,
      ),
    );
    await openWorkedHours(tester, wire);

    // The day row carries a "(+1h 0m OT)" suffix only when overtime > 0.
    expect(find.textContaining('(+'), findsOneWidget);
    expect(find.textContaining('OT)'), findsOneWidget);
  });

  testWidgets('an empty window shows the empty state, not a blank section', (tester) async {
    final wire = FakeWire(); // employeeWorkedHours defaults to empty days.
    await openWorkedHours(tester, wire);

    expect(find.byKey(WorkedHoursScreen.emptyKey), findsOneWidget);
    expect(find.text('No confirmed worked hours in this window.'), findsOneWidget);
    expect(find.byKey(WorkedHoursScreen.totalsKey), findsNothing);
  });

  testWidgets('choosing From and To re-reads, sending both filters to the wire', (tester) async {
    final wire = FakeWire(
      employeeWorkedHours: workedHoursSummaryJson(days: [workedHoursDayJson('2026-05-04')]),
    );
    await openWorkedHours(tester, wire);

    await tapIn(tester, find.byKey(WorkedHoursScreen.fromFieldKey));
    // AppDateField opens a real showDatePicker; confirming today's default
    // selection is enough to prove a value reaches the Bloc and the next
    // read carries a `from` bound (attendance_to_confirm_test.dart's own
    // precedent) — the exact date is incidental here.
    await tapIn(tester, find.text('OK'));

    await tapIn(tester, find.byKey(WorkedHoursScreen.toFieldKey));
    await tapIn(tester, find.text('OK'));

    expect(wire.employeeWorkedHoursRequests.length, 3);
    expect(wire.employeeWorkedHoursRequests[1].$2.containsKey('from'), isTrue);
    expect(wire.employeeWorkedHoursRequests[2].$2.containsKey('to'), isTrue);
  });

  testWidgets('a failed read shows the failure, not the rows', (tester) async {
    final wire = FakeWire(
      employeeWorkedHoursStatus: 500,
      employeeWorkedHoursMessage: 'The worked-hours summary is unavailable.',
    );
    await openWorkedHours(tester, wire);

    expect(find.byKey(WorkedHoursScreen.failureKey), findsOneWidget);
    expect(find.text('You can retry.'), findsNothing);
    expect(find.byKey(WorkedHoursScreen.rowKey('2026-05-04')), findsNothing);
  });
}