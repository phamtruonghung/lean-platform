/// An administrator sets a Signature for an Employee who cannot (issue #320,
/// ADR-0052) - the dialog on the Employee's own page, with the wire faked, the
/// one client seam (AGENTS.md section 5). Everything asserted is rendered text,
/// a Key, or a request the fake wire recorded.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/employee_signature_dialog.dart';

import 'harness.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const String _path = '/api/people/employees/7/signature';

Future<void> _open(WidgetTester tester, FakeWire wire, {FakeSignatureFilePicker? picker}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    signatureFilePicker: picker,
    initialLocation: '/directory',
  );
  await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
}

FakeWire _wire({String role = 'admin', bool isActive = true}) => FakeWire(
      role: role,
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen', isActive: isActive)},
    );

void main() {
  testWidgets('with none set it says so and offers to upload or draw one', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    expect(find.byKey(EmployeeSignatureDialog.emptyKey), findsOneWidget);
    expect(find.byKey(EmployeeSignatureDialog.uploadKey), findsOneWidget);
    expect(find.byKey(EmployeeSignatureDialog.drawKey), findsOneWidget);
    expect(find.byKey(EmployeeSignatureDialog.removeKey), findsNothing);
    expect(wire.employeeSignatureWrites, isEmpty);
  });

  testWidgets('a Signature set for them shows who set it', (tester) async {
    final wire = _wire();
    wire.employeeSignatures['7'] = _png;
    await _open(tester, wire);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    expect(find.byKey(EmployeeSignatureDialog.imageKey), findsOneWidget);
    expect(find.text('Set for Alice Nguyen by Test Admin'), findsOneWidget);
    expect(find.byKey(EmployeeSignatureDialog.removeKey), findsOneWidget);
    expect(find.text('Replace with a picture'), findsOneWidget);
  });

  testWidgets('a Signature set by the Employee says so', (tester) async {
    final wire = _wire();
    wire.employeeSignatures['7'] = _png;
    wire.employeeSignatureSetBy['7'] = {'setByName': 'Alice Nguyen', 'setForEmployee': false, 'origin': 'on_screen'};
    await _open(tester, wire);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    expect(find.text('Set by Alice Nguyen'), findsOneWidget);
  });

  testWidgets('uploading a picture issues one PUT with a base64 PNG, then shows who set it', (tester) async {
    final wire = _wire();
    final picker = FakeSignatureFilePicker(chosen: _png);
    await _open(tester, wire, picker: picker);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    await tapIn(tester, find.byKey(EmployeeSignatureDialog.uploadKey));

    expect(wire.employeeSignatureWrites.map((w) => w.$1), ['PUT $_path']);
    final sent = wire.employeeSignatureWrites.single.$2;
    expect(base64Decode(sent['image'] as String), _png);
    expect(sent['origin'], 'upload');
    expect(find.byKey(EmployeeSignatureDialog.currentKey), findsOneWidget);
    expect(find.text('Set for Alice Nguyen by Test Admin'), findsOneWidget);
  });

  testWidgets('removing issues one DELETE and leaves the empty state', (tester) async {
    final wire = _wire();
    wire.employeeSignatures['7'] = _png;
    await _open(tester, wire);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    await tapIn(tester, find.byKey(EmployeeSignatureDialog.removeKey));

    expect(wire.employeeSignatureWrites.map((w) => w.$1), ['DELETE $_path']);
    expect(find.byKey(EmployeeSignatureDialog.emptyKey), findsOneWidget);
  });

  testWidgets('once the Employee holds an Account the refusal is shown in the Module\'s own words', (tester) async {
    final wire = _wire()
      ..employeeSignatureWriteStatus = 409
      ..employeeSignatureWriteMessage =
          'This Employee holds an Account of their own, so only they can set their Signature';
    final picker = FakeSignatureFilePicker(chosen: _png);
    await _open(tester, wire, picker: picker);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    await tapIn(tester, find.byKey(EmployeeSignatureDialog.uploadKey));

    expect(find.byKey(EmployeeSignatureDialog.refusalKey), findsOneWidget);
    expect(
      find.text('This Employee holds an Account of their own, so only they can set their Signature'),
      findsOneWidget,
    );
    expect(find.byKey(EmployeeSignatureDialog.uploadKey), findsNothing);
    expect(find.byKey(EmployeeSignatureDialog.drawKey), findsNothing);

    await tapIn(tester, find.byKey(EmployeeSignatureDialog.closeKey));
    expect(find.byType(EmployeeSignatureDialog), findsNothing);
  });

  testWidgets('a drawn mark is sent as on_screen', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tapIn(tester, find.byKey(EmployeeDetailScreen.signatureKey));

    await tapIn(tester, find.byKey(EmployeeSignatureDialog.drawKey));
    await tester.drag(find.byKey(EmployeeSignatureDialog.padKey), const Offset(120, 40));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(EmployeeSignatureDialog.saveDrawnKey));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(wire.employeeSignatureWrites.single.$2['origin'], 'on_screen');
  });

  testWidgets('the door is for an administrator, and not offered for a Departed Employee', (tester) async {
    await _open(tester, _wire(role: 'operator'));
    expect(find.byKey(EmployeeDetailScreen.signatureKey), findsNothing);
  });

  testWidgets('no door on a Departed Employee', (tester) async {
    await _open(tester, _wire(isActive: false));
    expect(find.byKey(EmployeeDetailScreen.departedKey), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.signatureKey), findsNothing);
  });
}
