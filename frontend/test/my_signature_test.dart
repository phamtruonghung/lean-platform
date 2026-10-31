/// An Employee keeps a Signature (issue #317, ADR-0052) - the My signature
/// Screen, with the wire faked, the one client seam (AGENTS.md section 5).
/// Everything asserted is rendered text, a Key, or a request the fake wire
/// recorded; the browser's file input is replaced by a fake picker.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/my_signature_screen.dart';
import 'package:lean_platform/theme.dart';

import 'harness.dart';

/// A real 1 x 1 PNG, so what reaches the wire starts with the PNG signature.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const String _signaturePath = '/api/people/me/signature';

Future<void> _open(WidgetTester tester, FakeWire wire, {FakeSignatureFilePicker? picker}) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    signatureFilePicker: picker,
    initialLocation: '/me/signature',
  );
}

List<String> _writes(FakeWire wire) => [
      for (final request in wire.requests)
        if (!request.startsWith('GET ')) request,
    ];

void main() {
  testWidgets('with no Signature kept it says so and offers to upload or draw one', (tester) async {
    final wire = FakeWire();
    await _open(tester, wire);

    expect(find.byKey(MySignatureScreen.emptyKey), findsOneWidget);
    expect(find.text('No Signature kept'), findsOneWidget);
    expect(find.byKey(MySignatureScreen.uploadKey), findsOneWidget);
    expect(find.byKey(MySignatureScreen.drawKey), findsOneWidget);
    expect(find.byKey(MySignatureScreen.removeKey), findsNothing);
    expect(_writes(wire), isEmpty);
  });

  testWidgets('a Signature that cannot be decoded says so in the ink drawn for its backdrop in dark',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final wire = FakeWire()..mySignature = Uint8List.fromList([1, 2, 3, 4]);
    await _open(tester, wire);
    await tester.pumpAndSettle();
    // The decode failure is reported to FlutterError; it is the point here.
    tester.takeException();

    final message = tester.widget<Text>(find.text('This Signature could not be shown.'));
    expect(message.style?.color, AppPalette.dark.onSignatureBackdrop);
  });

  testWidgets('with a Signature kept it shows it, with replace and remove controls', (tester) async {
    final wire = FakeWire()..mySignature = _png;
    await _open(tester, wire);

    expect(find.byKey(MySignatureScreen.emptyKey), findsNothing);
    expect(find.byKey(MySignatureScreen.currentKey), findsOneWidget);
    expect(find.byKey(MySignatureScreen.imageKey), findsOneWidget);
    expect(find.text('Replace with a picture'), findsOneWidget);
    expect(find.byKey(MySignatureScreen.removeKey), findsOneWidget);
  });

  testWidgets('a failed read shows the failure state, and retry reads again', (tester) async {
    final wire = FakeWire()..mySignatureStatus = 500;
    await _open(tester, wire);

    expect(find.byKey(MySignatureScreen.failureKey), findsOneWidget);
    expect(find.text('Your Signature could not be read'), findsOneWidget);
    expect(find.text('Your Signature is unavailable.'), findsOneWidget);
    expect(find.byKey(MySignatureScreen.emptyKey), findsNothing);

    wire
      ..mySignatureStatus = 200
      ..mySignature = _png;
    await tapIn(tester, find.byKey(MySignatureScreen.retryKey));
    expect(find.byKey(MySignatureScreen.currentKey), findsOneWidget);
  });

  testWidgets('uploading a picture issues exactly one PUT with a base64 PNG and no other write',
      (tester) async {
    final wire = FakeWire();
    final picker = FakeSignatureFilePicker(chosen: _png);
    await _open(tester, wire, picker: picker);

    await tapIn(tester, find.byKey(MySignatureScreen.uploadKey));

    expect(picker.asked, 1);
    expect(_writes(wire), ['PUT $_signaturePath']);
    expect(wire.signatureWrites, hasLength(1));
    final sent = wire.signatureWrites.single.$2;
    expect(base64Decode(sent['image'] as String), _png);
    expect(sent['origin'], 'upload');
    expect(find.byKey(MySignatureScreen.currentKey), findsOneWidget);
  });

  testWidgets('choosing nothing in the file input sends nothing', (tester) async {
    final wire = FakeWire();
    await _open(tester, wire, picker: FakeSignatureFilePicker());

    await tapIn(tester, find.byKey(MySignatureScreen.uploadKey));

    expect(_writes(wire), isEmpty);
    expect(find.byKey(MySignatureScreen.emptyKey), findsOneWidget);
  });

  testWidgets('a refused Signature is shown in the Module\'s own words and the old one stays',
      (tester) async {
    final wire = FakeWire()
      ..mySignature = _png
      ..keepSignatureStatus = 400
      ..keepSignatureMessage = 'image must be a PNG';
    await _open(tester, wire, picker: FakeSignatureFilePicker(chosen: _png));

    await tapIn(tester, find.byKey(MySignatureScreen.uploadKey));

    expect(find.byKey(MySignatureScreen.writeFailureKey), findsOneWidget);
    expect(find.text('image must be a PNG'), findsOneWidget);
    expect(find.byKey(MySignatureScreen.currentKey), findsOneWidget);
  });

  testWidgets('nothing is sent while the pad is untouched', (tester) async {
    final wire = FakeWire();
    await _open(tester, wire);

    await tapIn(tester, find.byKey(MySignatureScreen.drawKey));
    expect(find.byKey(MySignatureScreen.padKey), findsOneWidget);

    final save = tester.widget<FilledButton>(find.byKey(MySignatureScreen.saveDrawnKey));
    expect(save.onPressed, isNull);
    expect(_writes(wire), isEmpty);
  });

  testWidgets('a drawn Signature issues exactly one PUT, recorded as drawn on screen', (tester) async {
    final wire = FakeWire();
    await _open(tester, wire);

    await tapIn(tester, find.byKey(MySignatureScreen.drawKey));
    await tester.drag(find.byKey(MySignatureScreen.padKey), const Offset(120, 40));
    await tester.pumpAndSettle();

    final save = find.byKey(MySignatureScreen.saveDrawnKey);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(_writes(wire), isEmpty);

    // Rendering the strokes to a PNG goes through the engine, which a
    // fake-async test clock does not drive.
    await tester.runAsync(() async {
      await tester.tap(save);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(_writes(wire), ['PUT $_signaturePath']);
    final sent = wire.signatureWrites.single.$2;
    expect(sent['origin'], 'on_screen');
    final bytes = base64Decode(sent['image'] as String);
    expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    expect(find.byKey(MySignatureScreen.currentKey), findsOneWidget);
    expect(find.byKey(MySignatureScreen.padKey), findsNothing);
  });

  testWidgets('removing the Signature issues one DELETE and leaves the empty state', (tester) async {
    final wire = FakeWire()..mySignature = _png;
    await _open(tester, wire);

    await tapIn(tester, find.byKey(MySignatureScreen.removeKey));

    expect(_writes(wire), ['DELETE $_signaturePath']);
    expect(find.byKey(MySignatureScreen.emptyKey), findsOneWidget);
    expect(find.byKey(MySignatureScreen.removeKey), findsNothing);
  });

  testWidgets('My signature is a Destination in the sidebar for any approved role', (tester) async {
    final wire = FakeWire(role: 'operator');
    await _open(tester, wire);

    expect(find.text('My signature'), findsWidgets);
    expect(find.byKey(MySignatureScreen.emptyKey), findsOneWidget);
  });
}
