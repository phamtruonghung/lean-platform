/// `AppToolbar`: filters, a count and actions in one row that wraps.
///
/// Mounted like `app_page_header_test.dart`: a small `MaterialApp` with the
/// app's own theme and no `FakeWire`, because the widget makes no request. The
/// width tests wrap the toolbar in a `SizedBox` so that the **box** is what it
/// sees; the window is a fixed size wider than any box used, and the text scale
/// is set with a `MediaQuery` inside the app, where a real reader's setting
/// reaches the widget.
///
/// The geometry is measured (`getTopLeft`, `getSize`, `getBottomRight`) rather
/// than inferred from "it renders", because the defect this widget exists to
/// prevent (#379, #381) was a layout that rendered perfectly and was simply the
/// wrong shape at one width and one text size.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_toolbar.dart';

import 'harness.dart';

const _filterAKey = ValueKey<String>('test-filter-a');
const _filterBKey = ValueKey<String>('test-filter-b');
const _countTextKey = ValueKey<String>('test-count');
const _addKey = ValueKey<String>('test-add');
const _exportKey = ValueKey<String>('test-export');
const _goldenKey = ValueKey<String>('test-toolbar-golden');

Widget _filter(Key key) => SizedBox(key: key, width: 160, height: 44);

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 900,
  double textScale = 1,
  List<Widget>? filters,
  Widget? count = const Text('12 work orders', key: _countTextKey),
  List<Widget>? actions,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2300, 900);
  addTearDown(tester.view.reset);
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
                width: boxWidth,
                child: AppToolbar(
                  filters: filters ?? [_filter(_filterAKey), _filter(_filterBKey)],
                  count: count,
                  actions: actions ??
                      [
                        OutlinedButton(key: _exportKey, onPressed: () {}, child: const Text('Export')),
                        FilledButton(key: _addKey, onPressed: () {}, child: const Text('Add work order')),
                      ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// True when the actions sit under the filters rather than beside them.
bool _wrapped(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(AppToolbar.actionsKey)).dy >=
    tester.getBottomRight(find.byKey(AppToolbar.filtersKey)).dy;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('at 1280 of box the filters, count and actions share one row', (tester) async {
    await _pump(tester, boxWidth: 1280);
    final filters = find.byKey(AppToolbar.filtersKey);
    final actions = find.byKey(AppToolbar.actionsKey);
    expect(_wrapped(tester), isFalse);
    expect(tester.getCenter(actions).dy, closeTo(tester.getCenter(filters).dy, 1));
    expect(tester.getCenter(find.byKey(AppToolbar.countKey)).dy, closeTo(tester.getCenter(filters).dy, 1));
    // Left to right: filters, then the count, then the actions at the far end.
    expect(tester.getTopLeft(find.byKey(AppToolbar.countKey)).dx,
        greaterThan(tester.getBottomRight(filters).dx - 1));
    expect(tester.getTopLeft(actions).dx, greaterThan(tester.getBottomRight(find.byKey(AppToolbar.countKey)).dx));
    expect(
      tester.getBottomRight(actions).dx,
      closeTo(tester.getBottomRight(find.byType(AppToolbar)).dx, 1),
      reason: 'the actions end at the toolbar\'s right edge',
    );
    expect(tester.getBottomRight(find.byType(AppToolbar)).dx, 1280);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 700 of box one row still holds, and the actions end at its right edge',
      (tester) async {
    await _pump(tester, boxWidth: 700);
    final filters = find.byKey(AppToolbar.filtersKey);
    final count = find.byKey(AppToolbar.countKey);
    final actions = find.byKey(AppToolbar.actionsKey);
    expect(_wrapped(tester), isFalse);
    expect(tester.getTopLeft(actions).dy, lessThan(tester.getBottomRight(filters).dy),
        reason: 'the actions share the filters\' row');
    expect(tester.getCenter(actions).dy, closeTo(tester.getCenter(filters).dy, 1));
    expect(tester.getTopLeft(count).dx, greaterThan(tester.getBottomRight(filters).dx - 1));
    expect(tester.getBottomRight(actions).dx,
        closeTo(tester.getBottomRight(find.byType(AppToolbar)).dx, 1));
    expect(tester.getBottomRight(find.byType(AppToolbar)).dx, 700);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the toolbar wraps by the box, not the window: a 500 box in a 2300 window wraps',
      (tester) async {
    await _pump(tester, boxWidth: 500);
    expect(tester.view.physicalSize.width, 2300);
    expect(_wrapped(tester), isTrue);
  });

  testWidgets('the actions wrap under the filters below 640 of box width, not at it', (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap - 1);
    expect(_wrapped(tester), isTrue);
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap);
    expect(_wrapped(tester), isFalse);
  });

  testWidgets('below 1x text the breakpoint is not lowered: 640 still holds one row at 0.8',
      (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap, textScale: 0.8);
    expect(_wrapped(tester), isFalse);
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap - 1, textScale: 0.8);
    expect(_wrapped(tester), isTrue, reason: 'the clamp holds the breakpoint at its 1x value');
  });

  testWidgets('at 2x text, 700 of box is still wrapped, nothing overflows and every action is found',
      (tester) async {
    await _pump(tester, boxWidth: 700, textScale: 2);
    expect(_wrapped(tester), isTrue);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_exportKey), findsOneWidget);
    expect(find.byKey(_addKey), findsOneWidget);
    expect(find.byKey(_filterAKey), findsOneWidget);
    expect(find.byKey(_filterBKey), findsOneWidget);
    expect(find.text('12 work orders'), findsOneWidget);
    expect(tester.getBottomRight(find.byKey(_addKey)).dx, lessThanOrEqualTo(700));
  });

  testWidgets('at 2x text the breakpoint doubles: one row at 1280 of box, wrapped one pixel under it',
      (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap * 2 - 1, textScale: 2);
    expect(_wrapped(tester), isTrue);
    expect(tester.takeException(), isNull);
    await _pump(tester, boxWidth: AppBreakpoints.toolbarWrap * 2, textScale: 2);
    expect(_wrapped(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped, a long run of actions wraps among themselves and none is dropped',
      (tester) async {
    await _pump(
      tester,
      boxWidth: 440,
      actions: [
        for (var i = 0; i < 4; i++)
          OutlinedButton(onPressed: () {}, child: Text('Action number $i')),
      ],
    );
    for (var i = 0; i < 4; i++) {
      expect(find.text('Action number $i'), findsOneWidget);
    }
    expect(tester.getSize(find.byKey(AppToolbar.actionsKey)).width, lessThanOrEqualTo(440));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with nothing to show the toolbar takes no space', (tester) async {
    await _pump(tester, filters: const [], count: null, actions: const []);
    expect(tester.getSize(find.byType(AppToolbar)).height, 0);
    expect(find.byKey(AppToolbar.filtersKey), findsNothing);
    expect(find.byKey(AppToolbar.actionsKey), findsNothing);
  });

  testWidgets('with no count the count slot is absent, wide and wrapped', (tester) async {
    await _pump(tester, boxWidth: 1280, count: null);
    expect(find.byKey(AppToolbar.countKey), findsNothing);
    await _pump(tester, boxWidth: 440, count: null);
    expect(find.byKey(AppToolbar.countKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped with no filters and no count the actions start at the toolbar top',
      (tester) async {
    await _pump(tester, boxWidth: 440, filters: const [], count: null);
    expect(
      tester.getTopLeft(find.byKey(AppToolbar.actionsKey)).dy,
      tester.getTopLeft(find.byType(AppToolbar)).dy,
    );
    expect(find.byKey(AppToolbar.filtersKey), findsNothing);
  });

  testWidgets('with no actions the actions slot is absent', (tester) async {
    await _pump(tester, boxWidth: 1280, actions: const []);
    expect(find.byKey(AppToolbar.actionsKey), findsNothing);
    expect(find.byKey(AppToolbar.filtersKey), findsOneWidget);
  });

  testWidgets('the actions are at least 44 tall, wide and wrapped', (tester) async {
    await _pump(tester, boxWidth: 1280);
    expect(tester.getSize(find.byKey(AppToolbar.actionsKey)).height, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(tester.getSize(find.byKey(_addKey)).height, greaterThanOrEqualTo(AppTouchTarget.min));
    await _pump(tester, boxWidth: 440);
    expect(tester.getSize(find.byKey(_addKey)).height, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(tester.getSize(find.byKey(_exportKey)).height, greaterThanOrEqualTo(AppTouchTarget.min));
  });

  testWidgets('an icon-only action keeps the label its caller gave it, and is still 44 tall',
      (tester) async {
    await _pump(
      tester,
      boxWidth: 1280,
      actions: [
        IconButton(key: _exportKey, tooltip: 'Export', onPressed: () {}, icon: const Icon(Icons.download)),
      ],
    );
    expect(find.byTooltip('Export'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(_exportKey)).tooltip, 'Export');
    expect(tester.getSize(find.byKey(_exportKey)).height, greaterThanOrEqualTo(AppTouchTarget.min));
  });

  testWidgets('it adds no outer padding: the first filter starts at the left edge of the box', (tester) async {
    await _pump(tester, boxWidth: 900);
    expect(tester.getTopLeft(find.byKey(AppToolbar.filtersKey)).dx, 0);
  });

  testWidgets('filters are Spacing.md apart', (tester) async {
    await _pump(tester, boxWidth: 900);
    expect(
      tester.getTopLeft(find.byKey(_filterBKey)).dx - tester.getBottomRight(find.byKey(_filterAKey)).dx,
      Spacing.md,
    );
  });

  testWidgets('the wide toolbar matches its golden', (tester) async {
    await _pumpGolden(tester, boxWidth: 900);
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_toolbar_wide.png'));
  });

  testWidgets('the wrapped toolbar matches its golden at 440, the narrowest box a page gets',
      (tester) async {
    await _pumpGolden(tester, boxWidth: 440);
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_toolbar_wrapped.png'));
  });
}

Future<void> _pumpGolden(WidgetTester tester, {required double boxWidth}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(boxWidth + 100, 400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _goldenKey,
          child: Material(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: SizedBox(
                width: boxWidth,
                child: AppToolbar(
                  filters: [
                    FilterChip(label: const Text('Open'), selected: true, onSelected: (_) {}),
                    FilterChip(label: const Text('Assigned to me'), selected: false, onSelected: (_) {}),
                    FilterChip(label: const Text('Overdue'), selected: false, onSelected: (_) {}),
                  ],
                  count: const Text('12 work orders'),
                  actions: [
                    OutlinedButton(onPressed: () {}, child: const Text('Export')),
                    FilledButton(onPressed: () {}, child: const Text('Raise work order')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
