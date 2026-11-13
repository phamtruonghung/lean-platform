/// `AppScanField` — the code-entry field a shop-floor reader fills.
///
/// The reader is simulated the way a browser sees one: text arrives through the
/// text-input connection (what a keyboard-wedge reader produces), then a
/// hardware `Enter` arrives as a **key event** — `tester.sendKeyEvent`, not
/// `onSubmitted`, because that is the path a hardware key actually takes (see
/// `widgets/app_form_submit.dart`'s own measurement, and the test below that
/// proves this widget sees it). The soft-keyboard route is tested separately
/// with `tester.testTextInput.receiveAction`, so both doors are covered.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_form_submit.dart';
import 'package:lean_platform/widgets/app_scan_field.dart';

const _codeKey = ValueKey<String>('scan-test-code');
const _pinKey = ValueKey<String>('scan-test-pin');

Widget _app(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    );

/// The text field focus currently sits in, read the way a Keyboard user's next
/// keystroke would find it — `FocusManager.instance.primaryFocus`, not a
/// `FocusNode` this file owns.
TextEditingController? _focusedFieldController() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  EditableText? field;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is EditableText) {
      field = widget;
      return false;
    }
    return true;
  });
  return field?.controller;
}

void main() {
  group('normalize', () {
    test('strips a reader\'s terminator, a BOM and zero-width characters', () {
      expect(AppScanField.normalize('AST-0042\r\n'), 'AST-0042');
      expect(AppScanField.normalize('\uFEFFAST-0042'), 'AST-0042');
      expect(AppScanField.normalize('AST-0042\u200B\u2060'), 'AST-0042');
      // GS1's own field separator, what a DataMatrix with several AI fields
      // sends between them.
      expect(AppScanField.normalize('01\u001D0042'), '010042');
    });

    test('trims a trailing space a reader was configured to append', () {
      expect(AppScanField.normalize('  AST-0042  '), 'AST-0042');
      expect(AppScanField.normalize('AST-0042\u00A0'), 'AST-0042');
    });

    test('leaves the code itself exactly as read, interior spacing included', () {
      expect(AppScanField.normalize('A 12/B'), 'A 12/B');
      expect(AppScanField.normalize(''), '');
    });
  });

  testWidgets('a hardware Enter commits the burst as the code, cleaned', (WidgetTester tester) async {
    final controller = TextEditingController();
    final scanned = <String>[];
    final reported = <String>[];

    await tester.pumpWidget(_app(AppScanField(
      key: _codeKey,
      controller: controller,
      label: 'Code',
      autofocus: true,
      onChanged: reported.add,
      onScanned: scanned.add,
    )));
    await tester.pump();

    // Not `enterText` alone: that is a pair of keystrokes, what a person does
    // slowly. A reader's burst is the whole code at once, then Enter.
    await tester.enterText(find.byKey(_codeKey), 'AST-0042\r\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(scanned, ['AST-0042']);
    expect(controller.text, 'AST-0042');
    // The clean-up is reported, not just written: a caller gating submission on
    // the field's text has to see what the form would now post.
    expect(reported.last, 'AST-0042');
  });

  testWidgets('a soft keyboard\'s done action commits by the other door', (WidgetTester tester) async {
    final controller = TextEditingController();
    final scanned = <String>[];

    await tester.pumpWidget(_app(AppScanField(
      key: _codeKey,
      controller: controller,
      label: 'Code',
      onScanned: scanned.add,
    )));

    await tester.enterText(find.byKey(_codeKey), ' AST-0042 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(scanned, ['AST-0042']);
    expect(controller.text, 'AST-0042');
  });

  testWidgets('an empty field commits nothing', (WidgetTester tester) async {
    final controller = TextEditingController();
    final scanned = <String>[];

    await tester.pumpWidget(_app(AppScanField(
      key: _codeKey,
      controller: controller,
      label: 'Code',
      autofocus: true,
      onScanned: scanned.add,
    )));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(scanned, isEmpty);
  });

  testWidgets('autofocus is what lets a scan land without a tap', (WidgetTester tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_app(AppScanField(
      key: _codeKey,
      controller: controller,
      label: 'Code',
      autofocus: true,
    )));
    await tester.pump();

    expect(_focusedFieldController(), same(controller));
    expect(AppFormSubmit.focusIsInSingleLineField(), isTrue);
  });

  testWidgets('a badge scan moves focus on to the next field', (WidgetTester tester) async {
    final badge = TextEditingController();
    final pin = TextEditingController();
    final scanned = <String>[];

    await tester.pumpWidget(_app(Column(
      children: [
        AppScanField(
          key: _codeKey,
          controller: badge,
          label: 'Employee number',
          autofocus: true,
          advanceFocusOnScan: true,
          onScanned: scanned.add,
        ),
        AppScanField(key: _pinKey, controller: pin, label: 'PIN'),
      ],
    )));
    await tester.pump();

    await tester.enterText(find.byKey(_codeKey), 'E-0042\r\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(scanned, ['E-0042']);
    expect(_focusedFieldController(), same(pin));
  });

  testWidgets('the reader\'s Enter stops at the field, not at the form\'s primary action',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    var submits = 0;

    await tester.pumpWidget(_app(AppFormSubmit(
      onSubmit: () => submits++,
      child: AppScanField(
        key: _codeKey,
        controller: controller,
        label: 'Code',
        autofocus: true,
      ),
    )));
    await tester.pump();

    await tester.enterText(find.byKey(_codeKey), 'AST-0042');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // A terminator is the code's own `Enter`: submitting the form on it would
    // send a form mid-scan, so the field handles the key before the form's rule
    // (design-language §8's Enter-submits) can see it.
    expect(submits, 0);
  });

  testWidgets('the caller\'s key stays on the TextField, and a disabled field commits nothing',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    final scanned = <String>[];

    await tester.pumpWidget(_app(AppScanField(
      key: _codeKey,
      controller: controller,
      label: 'Code',
      enabled: false,
      autofocus: true,
      onScanned: scanned.add,
    )));
    await tester.pump();

    // Every existing dialog test finds its code field this way — the key must
    // not move onto a wrapper (one key matching two widgets is not findable).
    final field = tester.widget<TextField>(find.byKey(_codeKey));
    expect(field.enabled, isFalse);
    expect(field.controller, same(controller));
    expect(field.textInputAction, TextInputAction.done);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(scanned, isEmpty);
  });
}
