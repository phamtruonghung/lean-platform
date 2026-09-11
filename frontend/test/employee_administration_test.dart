/// Adding, correcting and departing an Employee (issue #87), with the wire
/// faked — the one client seam (ADR-0012). The real app, the real router, the
/// real Blocs, `MockClient` at the HTTP boundary and `FakeAuthGateway` at the
/// auth boundary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_correction_dialog.dart';
import 'package:lean_platform/people/employee_departure_dialog.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/employee_form_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_date_field.dart';

import 'harness.dart';

Future<void> openDirectory(WidgetTester tester, FakeWire wire, {String location = '/directory'}) =>
    pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: location,
    );

void main() {
  testWidgets('an administrator can add an Employee, and the new row appears in the list',
      (tester) async {
    final wire = FakeWire(employees: [employeeJson('7', 'E-7', 'Alice Nguyen')]);
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.addKey));
    await tester.enterText(find.byKey(EmployeeFormDialog.employeeNoKey), 'E-99');
    await tester.enterText(find.byKey(EmployeeFormDialog.firstNameKey), 'Bao');
    await tester.enterText(find.byKey(EmployeeFormDialog.lastNameKey), 'Tran');
    await tapIn(tester, find.byKey(EmployeeFormDialog.submitKey));

    // Exactly one request, carrying what was typed.
    expect(wire.employeePosts.single, {
      'employeeNo': 'E-99',
      'firstName': 'Bao',
      'lastName': 'Tran',
      'employmentType': 'permanent',
    });
    expect(find.byType(EmployeeFormDialog), findsNothing);
    // The Directory re-read to pick the new row up, rather than trusting the
    // create response — which carries no orgUnit/jobRole at all.
    expect(find.text('Bao Tran'), findsOneWidget);
  });

  testWidgets('a duplicate employeeNo on add surfaces the API message on the form, not swallowed',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      createEmployeeStatus: 409,
      createEmployeeMessage: 'an Employee with this employee_no already exists',
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.addKey));
    await tester.enterText(find.byKey(EmployeeFormDialog.employeeNoKey), 'E-7');
    await tester.enterText(find.byKey(EmployeeFormDialog.firstNameKey), 'Bao');
    await tester.enterText(find.byKey(EmployeeFormDialog.lastNameKey), 'Tran');
    await tapIn(tester, find.byKey(EmployeeFormDialog.submitKey));

    expect(find.byType(EmployeeFormDialog), findsOneWidget);
    expect(find.byKey(EmployeeFormDialog.failureKey), findsOneWidget);
    expect(find.text('an Employee with this employee_no already exists'), findsOneWidget);
  });

  testWidgets('a duplicate workEmail on add surfaces the API message on the form, not swallowed',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      createEmployeeStatus: 409,
      createEmployeeMessage: 'an Employee with this work_email already exists',
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.addKey));
    await tester.enterText(find.byKey(EmployeeFormDialog.employeeNoKey), 'E-99');
    await tester.enterText(find.byKey(EmployeeFormDialog.firstNameKey), 'Bao');
    await tester.enterText(find.byKey(EmployeeFormDialog.lastNameKey), 'Tran');
    await tester.enterText(find.byKey(EmployeeFormDialog.workEmailKey), 'alice@b.c');
    await tapIn(tester, find.byKey(EmployeeFormDialog.submitKey));

    expect(find.byType(EmployeeFormDialog), findsOneWidget);
    expect(find.text('an Employee with this work_email already exists'), findsOneWidget);
  });

  testWidgets('a non-administrator sees none of the four write controls', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);

    expect(find.byKey(DirectoryScreen.addKey), findsNothing);

    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    expect(find.byType(EmployeeDetailScreen), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.correctKey), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.departKey), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.reinstateKey), findsNothing);
  });

  testWidgets(
      'correcting sends a PATCH carrying only the changed field, and the corrected '
      'record shows', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    await tapIn(tester, find.byKey(EmployeeDetailScreen.correctKey));
    expect(find.byType(EmployeeCorrectionDialog), findsOneWidget);
    // Pre-filled from the record already on screen, not left blank.
    expect(find.text('Nguyen'), findsOneWidget);

    await tester.enterText(find.byKey(EmployeeCorrectionDialog.lastNameKey), 'Tran');
    await tapIn(tester, find.byKey(EmployeeCorrectionDialog.submitKey));

    expect(wire.employeePatches.length, 1);
    expect(wire.employeePatches.single.$1, '7');
    expect(wire.employeePatches.single.$2, {'lastName': 'Tran'});
    expect(find.byType(EmployeeCorrectionDialog), findsNothing);
    expect(find.text('Alice Tran'), findsOneWidget);
  });

  testWidgets('a duplicate employeeNo on correction surfaces the API message on the form',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      updateEmployeeStatus: 409,
      updateEmployeeMessage: 'an Employee with this employee_no already exists',
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.correctKey));

    await tester.enterText(find.byKey(EmployeeCorrectionDialog.employeeNoKey), 'E-8');
    await tapIn(tester, find.byKey(EmployeeCorrectionDialog.submitKey));

    expect(find.byType(EmployeeCorrectionDialog), findsOneWidget);
    expect(find.byKey(EmployeeCorrectionDialog.failureKey), findsOneWidget);
    expect(find.text('an Employee with this employee_no already exists'), findsOneWidget);
  });

  testWidgets('a duplicate workEmail on correction surfaces the API message on the form',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      updateEmployeeStatus: 409,
      updateEmployeeMessage: 'an Employee with this work_email already exists',
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.correctKey));

    await tester.enterText(find.byKey(EmployeeCorrectionDialog.workEmailKey), 'taken@b.c');
    await tapIn(tester, find.byKey(EmployeeCorrectionDialog.submitKey));

    expect(find.byType(EmployeeCorrectionDialog), findsOneWidget);
    expect(find.text('an Employee with this work_email already exists'), findsOneWidget);
  });

  testWidgets('departure sends its own request with the date, and the record reads as Departed',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));
    expect(find.byType(EmployeeDepartureDialog), findsOneWidget);
    await pickDate(tester, EmployeeDepartureDialog.terminatedOnKey, DateTime(2024, 7, 1));
    await tapIn(tester, find.byKey(EmployeeDepartureDialog.submitKey));

    expect(wire.employeeDepartures.length, 1);
    expect(wire.employeeDepartures.single.$1, '7');
    expect(wire.employeeDepartures.single.$2, {'terminatedOn': '2024-07-01'});
    expect(find.byType(EmployeeDepartureDialog), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.departedKey), findsOneWidget);
    // "Departed", never "deleted" or "removed" (CONTEXT.md's own Departed
    // entry) — the record is still on screen, reading as gone, not gone.
    expect(find.byKey(EmployeeDetailScreen.reinstateKey), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.departKey), findsNothing);
    // No linked Account was scripted (issue #116): no warning, no extra step.
    expect(find.byKey(EmployeeDepartureDialog.linkedAccountWarningKey), findsNothing);
  });

  // The Employee link's other half (issue #116, ADR-0022): departing an
  // Employee who has a linked Account warns about it, without blocking or
  // silently deactivating.

  testWidgets(
      'departing an Employee with a linked Account warns, names the Account, and does not '
      'deactivate it silently', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      employeeLinkedAccounts: {'7': linkedAccountJson('50', 'alice@b.c')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));
    await tapIn(tester, find.byKey(EmployeeDepartureDialog.submitKey));

    // The departure already landed — the dialog stays open only to warn, not
    // to gate it.
    expect(wire.employeeDepartures.length, 1);
    expect(find.byKey(EmployeeDetailScreen.departedKey), findsOneWidget);

    expect(find.byType(EmployeeDepartureDialog), findsOneWidget);
    expect(find.byKey(EmployeeDepartureDialog.linkedAccountWarningKey), findsOneWidget);
    expect(find.textContaining('alice@b.c'), findsOneWidget);
    expect(wire.activations, isEmpty);

    await tapIn(tester, find.byKey(EmployeeDepartureDialog.deactivateLinkedAccountKey));

    expect(wire.activations, [('50', false)]);
    expect(find.byType(EmployeeDepartureDialog), findsNothing);
  });

  testWidgets('choosing "Not now" on the linked-Account warning closes without deactivating',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      employeeLinkedAccounts: {'7': linkedAccountJson('50', 'alice@b.c')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));
    await tapIn(tester, find.byKey(EmployeeDepartureDialog.submitKey));

    await tapIn(tester, find.byKey(EmployeeDepartureDialog.skipDeactivationKey));

    expect(find.byType(EmployeeDepartureDialog), findsNothing);
    expect(wire.activations, isEmpty);
    // The departure itself was not undone by declining to deactivate.
    expect(find.byKey(EmployeeDetailScreen.departedKey), findsOneWidget);
  });

  testWidgets('a terminatedOn before hiredOn surfaces the API\'s 400 on the departure form',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      departEmployeeStatus: 400,
      departEmployeeMessage: 'terminatedOn cannot be before hiredOn',
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));

    await pickDate(tester, EmployeeDepartureDialog.terminatedOnKey, DateTime(2019, 1, 1));
    await tapIn(tester, find.byKey(EmployeeDepartureDialog.submitKey));

    expect(find.byType(EmployeeDepartureDialog), findsOneWidget);
    expect(find.byKey(EmployeeDepartureDialog.failureKey), findsOneWidget);
    expect(find.text('terminatedOn cannot be before hiredOn'), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeDepartureDialog.cancelKey));
  });

  // AppDateField (issue #126, ADR-0023) at the departure date: optional,
  // blank meaning "the server records today" — a clear affordance is the
  // only way back to that genuine blank once a date has been picked.

  testWidgets(
      'the departure date field opens a date picker on tap, and picking a date fills it '
      'displayed as YYYY-MM-DD', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));

    expect(find.byType(DatePickerDialog), findsNothing);
    await tapIn(tester, find.byKey(EmployeeDepartureDialog.terminatedOnKey));
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '07/01/2024');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2024-07-01'), findsOneWidget);
  });

  testWidgets('the departure date field cannot be filled by typing', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));

    final fieldKey = AppDateField.fieldKey('departure-terminated-on');
    await tester.enterText(find.byKey(fieldKey), '2099-12-31');
    await tester.pump();

    expect(find.text('2099-12-31'), findsNothing);
    final field = tester.widget<TextField>(find.byKey(fieldKey));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets(
      'clearing a picked departure date returns it to empty, and the request omits '
      'terminatedOn exactly as a never-picked one does', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.departKey));

    expect(find.byKey(AppDateField.clearKey('departure-terminated-on')), findsNothing);

    await pickDate(tester, EmployeeDepartureDialog.terminatedOnKey, DateTime(2024, 7, 1));
    expect(find.text('2024-07-01'), findsOneWidget);
    expect(find.byKey(AppDateField.clearKey('departure-terminated-on')), findsOneWidget);

    await tapIn(tester, find.byKey(AppDateField.clearKey('departure-terminated-on')));

    expect(find.text('2024-07-01'), findsNothing);
    expect(find.byKey(AppDateField.clearKey('departure-terminated-on')), findsNothing);

    await tapIn(tester, find.byKey(EmployeeDepartureDialog.submitKey));

    // Genuinely blank on the wire — no `terminatedOn` key at all, exactly
    // what a departure never touching this field also sends.
    expect(wire.employeeDepartures.single.$2, isEmpty);
  });

  testWidgets('reinstatement sends its own request, with no body, and the record reads as active',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('8', 'E-8', 'Bao Tran', isActive: false)],
      employeeDetails: {'8': employeeDetailJson('8', 'E-8', 'Bao Tran', isActive: false)},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.includeDepartedKey));
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('8')));

    expect(find.byKey(EmployeeDetailScreen.reinstateKey), findsOneWidget);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.reinstateKey));

    expect(wire.employeeReinstatements, ['8']);
    expect(find.byKey(EmployeeDetailScreen.departedKey), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.departKey), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.reinstateKey), findsNothing);
  });
}
