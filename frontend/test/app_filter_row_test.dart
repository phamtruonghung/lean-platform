/// `AppFilterRow`: the controls in a filter row are one height, at every width
/// and every text size.
///
/// The defect this file guards (owner report, `/actions`): a dropdown sat 8px
/// taller than the button beside it, and 32px taller at 200% text, because a
/// labelled outline field reserves a line for its floating label that a
/// `ButtonStyleButton` does not. The geometry is **measured** (`getSize`,
/// `getTopLeft`) rather than inferred from "it renders", for the same reason
/// `app_toolbar_test.dart` measures: the wrong row renders perfectly.
///
/// Mounted like `app_toolbar_test.dart` — a small `MaterialApp` with the app's
/// own theme, no `FakeWire` (this row makes no request) — with the width given
/// by a `SizedBox` around it and the text scale set through the `MediaQuery`
/// inside the app, where a real reader's setting reaches the widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/app_filter_row.dart';

const _dropdownKey = ValueKey<String>('probe-dropdown');
const _buttonKey = ValueKey<String>('probe-button');
const _textButtonKey = ValueKey<String>('probe-text-button');
const _filterFieldName = 'probe';

/// The four kinds of control a filter row mixes, in the order `/actions` has
/// them.
Widget _dropdown() => SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: _dropdownKey,
        initialValue: 'a',
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem<String>(value: 'a', child: Text('Plant A')),
          DropdownMenuItem<String>(value: 'b', child: Text('Plant B')),
        ],
        onChanged: (_) {},
      ),
    );

Widget _row() => AppFilterRow(
      children: [
        _dropdown(),
        SizedBox(
          width: 260,
          child: AppFilterField(
            name: _filterFieldName,
            label: 'Filter Actions',
            helperText: 'By title.',
            term: '',
            onChanged: (_) {},
          ),
        ),
        OutlinedButton.icon(
          key: _buttonKey,
          onPressed: () {},
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('All Org Units'),
        ),
        TextButton(
          key: _textButtonKey,
          onPressed: () {},
          child: const Text('Clear filters'),
        ),
      ],
    );

Future<double> _pump(
  WidgetTester tester, {
  required Widget child,
  double width = 1280,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2400, 1200);
  addTearDown(tester.view.reset);
  late double controlHeight;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Builder(
                  builder: (inner) {
                    controlHeight = AppFilterRow.controlHeight(inner);
                    return child;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controlHeight;
}

/// The control box of the filter field — not the widget, which also carries the
/// helper caption under its box.
Finder get _filterFieldBox => find.byKey(AppFilterField.fieldKey(_filterFieldName));

void main() {
  for (final width in <double>[700, 900, 1280]) {
    for (final textScale in <double>[1, 2]) {
      testWidgets('every control in the row is one height — ${width}px, ${textScale}x',
          (tester) async {
        final controlHeight = await _pump(tester, child: _row(), width: width, textScale: textScale);

        expect(controlHeight, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'the row never goes under the platform tap floor');

        for (final finder in <Finder>[
          find.byKey(_dropdownKey),
          _filterFieldBox,
          find.byKey(_buttonKey),
          find.byKey(_textButtonKey),
        ]) {
          expect(tester.getSize(finder).height, controlHeight,
              reason: '$finder is not the row height at ${width}px, ${textScale}x');
        }
      });
    }
  }

  testWidgets('the controls share one top edge, so their boxes line up', (tester) async {
    await _pump(tester, child: _row());

    final top = tester.getTopLeft(find.byKey(_dropdownKey)).dy;
    for (final finder in <Finder>[
      _filterFieldBox,
      find.byKey(_buttonKey),
      find.byKey(_textButtonKey),
    ]) {
      expect(tester.getTopLeft(finder).dy, top, reason: '$finder is not level with the dropdown');
    }
  });

  testWidgets('the row wraps at 700px with 200% text, and stays one height', (tester) async {
    await _pump(tester, child: _row(), width: 700, textScale: 2);

    // More than one line: the dropdown's bottom is above the last control's top.
    final dropdownBottom = tester.getBottomLeft(find.byKey(_dropdownKey)).dy;
    final lastTop = tester.getTopLeft(find.byKey(_textButtonKey)).dy;
    expect(lastTop, greaterThan(dropdownBottom), reason: 'the row did not wrap, so this case proves nothing');
  });

  // **The number in `AppFilterRow.controlHeight` is Material's, measured.** If a
  // Material change moves the metric, the row's own floor is stale and would
  // clip a control — so this test compares the constant against a bare field's
  // own rendered height at five text scales, and names the divergence.
  for (final textScale in <double>[1, 1.25, 1.5, 1.75, 2]) {
    testWidgets('controlHeight is the labelled field\'s own height at ${textScale}x',
        (tester) async {
      final controlHeight = await _pump(tester, child: _dropdown(), textScale: textScale);
      expect(tester.getSize(find.byKey(_dropdownKey)).height, controlHeight,
          reason: 'a labelled dense outline field is no longer ${controlHeight}px at ${textScale}x '
              '— AppFilterRow.controlHeight needs re-measuring');
    });
  }

  // The reason the row is 56 at a text scale of 1 and not 44: at twice the text a
  // labelled field holds its value only if the box is this tall. Forcing it lower
  // runs the floating label through the value it labels.
  testWidgets('at 200% text the label and the value do not overlap', (tester) async {
    await _pump(tester, child: _row(), width: 1280, textScale: 2);

    final label = tester.getRect(find.text('Site'));
    final value = tester.getRect(find.text('Plant A').first);
    expect(value.top, greaterThanOrEqualTo(label.bottom),
        reason: 'the floating label runs into the value it labels');
  });

  testWidgets('a control narrower than the row keeps its own width', (tester) async {
    await _pump(tester, child: _row(), width: 1280);
    expect(tester.getSize(find.byKey(_dropdownKey)).width, 220);
  });
}
