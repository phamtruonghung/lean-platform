/// `AppDialog`: the shell, its four widths, the sheet it becomes, and the
/// accessibility it guarantees.
///
/// Mounted like `app_toolbar_test.dart`: a small `MaterialApp` with the app's own
/// theme and no `FakeWire`, because the widget makes no request. The dialog is
/// opened through `showDialog` from a button, because a dialog is a route and what
/// the primitive promises about focus (trapped inside, restored to the invoker) is a
/// promise about the route. The **window** is the box: a dialog route is handed the
/// whole window, and `physicalSize` at a device pixel ratio of 1 is how a test sets
/// it. The geometry is measured (`getSize`, `getTopLeft`, `getBottomRight`) rather
/// than inferred from "it renders".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_dialog.dart';

import 'harness.dart';

const _invokerKey = ValueKey<String>('test-invoker');
const _fieldKey = ValueKey<String>('test-dialog-field');
const _backgroundFieldKey = ValueKey<String>('test-background-field');
const _goldenKey = ValueKey<String>('test-dialog-golden');

/// What a test counts: which action ran.
class _Calls {
  int dismiss = 0;
  int primary = 0;
  int destructive = 0;
}

List<AppDialogAction> _actions(_Calls calls, {bool primaryEnabled = true}) => [
      AppDialogAction(
        id: 'cancel',
        label: 'Keep it open',
        kind: AppDialogActionKind.dismiss,
        onPressed: () => calls.dismiss++,
      ),
      AppDialogAction(
        id: 'save',
        label: 'Move Work order',
        onPressed: primaryEnabled ? () => calls.primary++ : null,
      ),
    ];

AppDialog _dialog(
  _Calls calls, {
  AppDialogSize size = AppDialogSize.form,
  Widget? child = const Text('Body copy', key: ValueKey('test-body')),
  List<AppDialogAction>? actions,
  String? description = 'The Work order keeps its history.',
  Widget? trailing,
}) =>
    AppDialog(
      title: 'Move this Work order?',
      description: description,
      size: size,
      trailing: trailing,
      actions: actions ?? _actions(calls),
      child: child,
    );

/// Mounts an app whose only control opens [build]'s dialog, with the window at
/// [window] and the reader's text at [textScale], and opens it.
Future<void> _open(
  WidgetTester tester,
  WidgetBuilder build, {
  Size window = const Size(1280, 900),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  FocusNode? invoker,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = window;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TextField(key: _backgroundFieldKey),
              FilledButton(
                key: _invokerKey,
                focusNode: invoker,
                onPressed: () => showDialog<void>(context: context, builder: build),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (invoker != null) {
    invoker.requestFocus();
    await tester.pump();
  }
  await tester.tap(find.byKey(_invokerKey));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder get _surface => find.byKey(AppDialog.surfaceKey);

Size _size(WidgetTester tester, Finder finder) => tester.getSize(finder);

/// The primary focus, as a `Finder`-comparable element, or null.
BuildContext? _focused() => FocusManager.instance.primaryFocus?.context;

bool _focusIsInsideDialog(WidgetTester tester) {
  final context = _focused();
  if (context == null) return false;
  return find
      .descendant(
        of: _surface,
        matching: find.byElementPredicate((element) => identical(element, context)),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  setUpAll(loadAppFonts);

  for (final size in AppDialogSize.values) {
    testWidgets('at 1280 of box a ${size.name} dialog is exactly ${size.width.toInt()} wide',
        (tester) async {
      await _open(tester, (_) => _dialog(_Calls(), size: size));
      expect(_size(tester, _surface).width, size.width);
      expect(_size(tester, _surface).width, lessThanOrEqualTo(1280 - 2 * Spacing.xl));
      expect(find.byKey(AppDialog.sheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('title, description, content and actions stack in that order, top to bottom',
      (tester) async {
    await _open(tester, (_) => _dialog(_Calls()));
    final title = tester.getTopLeft(find.byKey(AppDialog.titleKey)).dy;
    final description = tester.getTopLeft(find.byKey(AppDialog.descriptionKey)).dy;
    final content = tester.getTopLeft(find.byKey(AppDialog.contentKey)).dy;
    final actions = tester.getTopLeft(find.byKey(AppDialog.actionsKey)).dy;
    expect(title, lessThan(description));
    expect(description, lessThan(content));
    expect(content, lessThan(actions));
    // The paddings, in Spacing values.
    final surface = tester.getTopLeft(_surface);
    expect(tester.getTopLeft(find.byKey(AppDialog.titleKey)).dx - surface.dx, Spacing.lg);
    expect(tester.getTopLeft(find.byKey(AppDialog.titleKey)).dy - surface.dy, Spacing.lg);
    expect(
      tester.getTopLeft(find.byKey(AppDialog.descriptionKey)).dy -
          tester.getBottomRight(find.byKey(AppDialog.titleKey)).dy,
      Spacing.xs,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('test-body'))).dx - surface.dx,
      Spacing.lg,
    );
    expect(
      content - tester.getBottomRight(find.byKey(AppDialog.descriptionKey)).dy,
      Spacing.md,
      reason: 'the gap from the title block to the content',
    );
    expect(
      actions - tester.getBottomRight(find.byKey(AppDialog.contentKey)).dy,
      Spacing.lg,
      reason: 'the gap from the content to the action row',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the content area is the only scroll view in the dialog', (tester) async {
    await _open(tester, (_) => _dialog(_Calls()));
    final scrollables = find.descendant(of: _surface, matching: find.byType(Scrollable));
    expect(scrollables, findsOneWidget);
    expect(
      find.descendant(of: find.byKey(AppDialog.contentKey), matching: find.byType(Scrollable)),
      findsOneWidget,
    );
  });

  testWidgets('the shell is the card fill, the edge hairline and AppRadius.card, with no elevation',
      (tester) async {
    await _open(tester, (_) => _dialog(_Calls()));
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    final palette = AppPalette.light;
    expect(dialog.backgroundColor, palette.card);
    expect(dialog.elevation, 0);
    final shape = dialog.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
    expect(shape.side.color, palette.edge);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('at 700 of box the dialog is a sheet: full width, bottom-anchored, top corners rounded',
      (tester) async {
    await _open(tester, (_) => _dialog(_Calls()), window: const Size(700, 800));
    expect(find.byKey(AppDialog.sheetKey), findsOneWidget);
    expect(_size(tester, _surface).width, 700);
    expect(tester.getTopLeft(_surface).dx, 0);
    expect(tester.getBottomRight(_surface).dy, 800, reason: 'anchored to the bottom edge');
    final shape = tester.widget<Dialog>(find.byType(Dialog)).shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      reason: 'the top corners are rounded and the bottom ones are square',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 701 of box the dialog is not a sheet', (tester) async {
    await _open(tester, (_) => _dialog(_Calls(), size: AppDialogSize.wide),
        window: const Size(701, 800));
    expect(find.byKey(AppDialog.sheetKey), findsNothing);
    expect(_size(tester, _surface).width, 640);
    expect(tester.getBottomRight(_surface).dy, lessThan(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet keeps its title and action row pinned, and the action row fills the width',
      (tester) async {
    await _open(tester, (_) => _dialog(_Calls()), window: const Size(440, 800));
    final surface = tester.getTopLeft(_surface);
    expect(tester.getTopLeft(find.byKey(AppDialog.titleKey)).dx - surface.dx, Spacing.lg);
    final dismiss = find.byKey(AppDialog.actionKey('cancel'));
    final primary = find.byKey(AppDialog.actionKey('save'));
    expect(tester.getTopLeft(dismiss).dx - surface.dx, Spacing.lg);
    expect(
      tester.getBottomRight(primary).dx,
      tester.getBottomRight(_surface).dx - Spacing.lg,
      reason: 'the primary action fills the inline end',
    );
    expect(
      tester.getTopLeft(primary).dx - tester.getBottomRight(dismiss).dx,
      Spacing.lg,
      reason: 'the gap between the groups in a sheet',
    );
    expect(tester.getSize(primary).width, greaterThan(tester.getSize(dismiss).width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at textScaler 2.0 at 1280 it is still a sheet, nothing overflows, both labels read',
      (tester) async {
    await _open(tester, (_) => _dialog(_Calls()), textScale: 2);
    expect(find.byKey(AppDialog.sheetKey), findsOneWidget);
    expect(_size(tester, _surface).width, 1280);
    expect(find.text('Keep it open'), findsOneWidget);
    expect(find.text('Move Work order'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at textScaler 1.49 at 1280 it is a dialog, and at 1.5 it is a sheet', (tester) async {
    await _open(tester, (_) => _dialog(_Calls()), textScale: 1.49);
    expect(find.byKey(AppDialog.sheetKey), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, (_) => _dialog(_Calls()), textScale: 1.5);
    expect(find.byKey(AppDialog.sheetKey), findsOneWidget);
  });

  testWidgets('a long label wraps inside its button at textScaler 1.49 in the narrowest dialog',
      (tester) async {
    await _open(
      tester,
      (_) => _dialog(
        _Calls(),
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: 'cancel',
            label: 'Keep it open',
            kind: AppDialogActionKind.dismiss,
            onPressed: () {},
          ),
          AppDialogAction(id: 'save', label: 'Cancel this Work order', onPressed: () {}),
        ],
      ),
      textScale: 1.49,
    );
    expect(find.byKey(AppDialog.sheetKey), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(find.byKey(AppDialog.actionKey('save'))).dx,
        lessThanOrEqualTo(tester.getBottomRight(_surface).dx));
  });

  testWidgets('with a child long enough to scroll, the action row stays in view and the content scrolls',
      (tester) async {
    await _open(
      tester,
      (_) => _dialog(
        _Calls(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('Row $i')),
          ],
        ),
      ),
      window: const Size(1280, 600),
    );
    expect(tester.getBottomRight(find.byKey(AppDialog.actionsKey)).dy, lessThanOrEqualTo(600));
    expect(tester.getBottomRight(_surface).dy, lessThanOrEqualTo(600));
    expect(tester.getSize(find.byKey(AppDialog.contentKey)).height, lessThanOrEqualTo(600 * 0.6));
    expect(find.text('Row 39').hitTestable(), findsNothing, reason: 'the end of the content is off');
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(AppDialog.contentKey), matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, 0);
    await tester.drag(find.byKey(AppDialog.contentKey), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('Row 39').hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(find.byKey(AppDialog.actionsKey)).dy, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every action is at least AppTouchTarget.min tall, and a disabled one is not tappable',
      (tester) async {
    final calls = _Calls();
    await _open(tester, (_) => _dialog(calls, actions: _actions(calls, primaryEnabled: false)));
    for (final id in ['cancel', 'save']) {
      expect(tester.getSize(find.byKey(AppDialog.actionKey(id))).height,
          greaterThanOrEqualTo(AppTouchTarget.min));
    }
    final save = tester.widget<FilledButton>(find.byKey(AppDialog.actionKey('save')));
    expect(save.onPressed, isNull, reason: 'onPressed == null renders it disabled');
    await tester.tap(find.byKey(AppDialog.actionKey('save')), warnIfMissed: false);
    await tester.pump();
    expect(calls.primary, 0);
    await tester.tap(find.byKey(AppDialog.actionKey('cancel')));
    await tester.pump();
    expect(calls.dismiss, 1);
  });

  testWidgets('dismiss sits left of primary, primary is right-most, and the caller\'s labels are verbatim',
      (tester) async {
    final calls = _Calls();
    await _open(
      tester,
      (_) => _dialog(calls, actions: [
        AppDialogAction(
            id: 'save', label: 'Move Work order', onPressed: () => calls.primary++),
        AppDialogAction(
          id: 'delete',
          label: 'Delete it',
          kind: AppDialogActionKind.destructive,
          onPressed: () => calls.destructive++,
        ),
        AppDialogAction(
          id: 'cancel',
          label: 'Keep it open',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => calls.dismiss++,
        ),
      ]),
    );
    double left(String id) => tester.getTopLeft(find.byKey(AppDialog.actionKey(id))).dx;
    double right(String id) => tester.getBottomRight(find.byKey(AppDialog.actionKey(id))).dx;
    expect(left('cancel'), lessThan(left('delete')), reason: 'destructive is never first');
    expect(left('delete'), lessThan(left('save')));
    expect(right('save'), greaterThan(right('delete')));
    expect(right('save'), tester.getBottomRight(_surface).dx - Spacing.lg,
        reason: 'primary is right-most, Spacing.lg in from the edge');
    expect(left('cancel'), tester.getTopLeft(_surface).dx + Spacing.lg);
    expect(left('save') - right('delete'), Spacing.lg,
        reason: 'the destructive group is separated from the primary');
    expect(left('delete') - right('cancel'), greaterThanOrEqualTo(Spacing.lg),
        reason: 'at least Spacing.lg between the dismiss group and the end group');
    expect(find.text('Move Work order'), findsOneWidget);
    expect(find.text('Delete it'), findsOneWidget);
    expect(find.text('Keep it open'), findsOneWidget);
  });

  testWidgets('a trailing control sits in the title row at 44px', (tester) async {
    await _open(
      tester,
      (_) => _dialog(
        _Calls(),
        trailing: IconButton(
          key: const ValueKey('test-trailing'),
          tooltip: 'Help',
          onPressed: () {},
          icon: const Icon(Icons.help_outline),
        ),
      ),
    );
    final trailing = tester.getSize(find.byKey(const ValueKey('test-trailing')));
    expect(trailing.height, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(trailing.width, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(tester.getBottomRight(find.byKey(const ValueKey('test-trailing'))).dx,
        tester.getBottomRight(_surface).dx - Spacing.lg);
    expect(tester.takeException(), isNull);
  });

  group('focus', () {
    testWidgets('with a field in the child, opening puts focus inside the dialog, on that field',
        (tester) async {
      await _open(
        tester,
        (_) => _dialog(_Calls(), child: const TextField(key: _fieldKey)),
      );
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(_focusIsInsideDialog(tester), isTrue);
      final field = tester.widget<EditableText>(
          find.descendant(of: find.byKey(_fieldKey), matching: find.byType(EditableText)));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('an action-only dialog opens with focus on the primary action', (tester) async {
      await _open(tester, (_) => _dialog(_Calls(), child: null));
      expect(_focusIsInsideDialog(tester), isTrue);
      final primary = tester.widget<FilledButton>(find.byKey(AppDialog.actionKey('save')));
      expect(primary.focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('a dialog whose only act is destructive opens with focus on the dismiss action',
        (tester) async {
      final calls = _Calls();
      await _open(
        tester,
        (_) => _dialog(calls, child: null, actions: [
          AppDialogAction(
            id: 'delete',
            label: 'Delete it',
            kind: AppDialogActionKind.destructive,
            onPressed: () => calls.destructive++,
          ),
          AppDialogAction(
            id: 'cancel',
            label: 'Keep it open',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => calls.dismiss++,
          ),
        ]),
      );
      final dismiss = tester.widget<OutlinedButton>(find.byKey(AppDialog.actionKey('cancel')));
      expect(dismiss.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls.destructive, 0, reason: 'Enter on opening does not confirm');
    });

    testWidgets('initial focus skips a disabled action: a disabled primary leaves it on the dismiss',
        (tester) async {
      final calls = _Calls();
      await _open(tester, (_) => _dialog(calls, child: null, actions: _actions(calls, primaryEnabled: false)));
      final dismiss = tester.widget<OutlinedButton>(find.byKey(AppDialog.actionKey('cancel')));
      expect(dismiss.focusNode!.hasPrimaryFocus, isTrue);
      expect(_focusIsInsideDialog(tester), isTrue);
    });

    testWidgets('with every action disabled, focus still sits inside the dialog', (tester) async {
      await _open(
        tester,
        (_) => _dialog(_Calls(), child: null, actions: const [
          AppDialogAction(id: 'cancel', label: 'Keep it open', kind: AppDialogActionKind.dismiss),
          AppDialogAction(id: 'save', label: 'Move Work order'),
        ]),
      );
      expect(_focusIsInsideDialog(tester), isTrue);
    });

    testWidgets('Tab never leaves the dialog, and a field behind it never takes focus',
        (tester) async {
      await _open(
        tester,
        (_) => _dialog(_Calls(), child: const TextField(key: _fieldKey)),
      );
      final background = tester.widget<EditableText>(find.descendant(
          of: find.byKey(_backgroundFieldKey), matching: find.byType(EditableText)));
      final visited = <BuildContext>{};
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusIsInsideDialog(tester), isTrue, reason: 'after Tab number ${i + 1}');
        expect(background.focusNode.hasFocus, isFalse);
        visited.add(_focused()!);
      }
      // The field, the dismiss action and the primary action: three stops, cycled.
      expect(visited.length, 3);
    });

    testWidgets('focus returns to the control that opened the dialog when it closes', (tester) async {
      final invoker = FocusNode(debugLabel: 'invoker');
      addTearDown(invoker.dispose);
      await _open(
        tester,
        (context) => _dialog(_Calls(), actions: [
          AppDialogAction(
            id: 'cancel',
            label: 'Keep it open',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
        invoker: invoker,
      );
      expect(invoker.hasFocus, isFalse, reason: 'the dialog has focus while it is open');
      await tester.tap(find.byKey(AppDialog.actionKey('cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(invoker.hasFocus, isTrue);
    });

    testWidgets('a field keeps its text and its focus when the box crosses the sheet breakpoint',
        (tester) async {
      await _open(tester, (_) => _dialog(_Calls(), child: const TextField(key: _fieldKey)));
      await tester.enterText(find.byKey(_fieldKey), 'WO-1042');
      expect(find.byKey(AppDialog.sheetKey), findsNothing);
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(AppDialog.sheetKey), findsOneWidget);
      expect(find.text('WO-1042'), findsOneWidget);
      final field = tester.widget<EditableText>(
          find.descendant(of: find.byKey(_fieldKey), matching: find.byType(EditableText)));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Esc', () {
    testWidgets('runs the dismiss action and never the primary', (tester) async {
      final calls = _Calls();
      await _open(tester, (_) => _dialog(calls));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls.dismiss, 1);
      expect(calls.primary, 0);
    });

    testWidgets('runs the dismiss action from inside a field', (tester) async {
      final calls = _Calls();
      await _open(tester, (_) => _dialog(calls, child: const TextField(key: _fieldKey)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls.dismiss, 1);
      expect(calls.primary, 0);
    });

    testWidgets('works when the primary is disabled and focus would have had nowhere to land',
        (tester) async {
      final calls = _Calls();
      await _open(tester, (_) => _dialog(calls, child: null, actions: _actions(calls, primaryEnabled: false)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls.dismiss, 1);
      expect(calls.primary, 0);
    });

    testWidgets('still works after the focused primary is disabled by a rebuild and re-enabled',
        (tester) async {
      final calls = _Calls();
      late StateSetter rebuild;
      var busy = false;
      await _open(
        tester,
        (_) => StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return _dialog(calls, child: null, actions: [
            AppDialogAction(
              id: 'cancel',
              label: 'Keep it open',
              kind: AppDialogActionKind.dismiss,
              onPressed: busy ? null : () => calls.dismiss++,
            ),
            AppDialogAction(
              id: 'save',
              label: 'Move Work order',
              onPressed: busy ? null : () => rebuild(() => busy = true),
            ),
          ]);
        }),
      );
      // Enter on the focused primary starts the request; both actions disable.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(busy, isTrue);
      expect(_focusIsInsideDialog(tester), isTrue, reason: 'orphaned focus stays under the dialog');
      rebuild(() => busy = false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls.dismiss, 1);
    });

    testWidgets('does nothing while the dismiss action is disabled', (tester) async {
      final calls = _Calls();
      await _open(
        tester,
        (_) => _dialog(calls, actions: [
          const AppDialogAction(id: 'cancel', label: 'Keep it open', kind: AppDialogActionKind.dismiss),
          AppDialogAction(id: 'save', label: 'Move Work order', onPressed: () => calls.primary++),
        ]),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(calls.primary, 0);
    });

    testWidgets('with no dismiss action, pops the route', (tester) async {
      final calls = _Calls();
      await _open(
        tester,
        (_) => _dialog(calls, actions: [
          AppDialogAction(id: 'save', label: 'Move Work order', onPressed: () => calls.primary++),
        ]),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(calls.primary, 0);
    });
  });

  testWidgets('the surface is one semantics node that scopes and names the route, labelled with the title',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, (_) => _dialog(_Calls()));
    final node = tester.getSemantics(_surface);
    expect(node.label, 'Move this Work order?');
    expect(node.flagsCollection.scopesRoute, isTrue);
    expect(node.flagsCollection.namesRoute, isTrue);
    handle.dispose();
  });

  group('goldens', () {
    Future<void> pour(WidgetTester tester, Brightness brightness) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 420);
      addTearDown(tester.view.reset);
      final calls = _Calls();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          debugShowCheckedModeBanner: false,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _goldenKey,
              child: Material(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: SizedBox(
                    // Wide enough to be a dialog rather than a sheet: 701 and up.
                    width: 768,
                    height: 388,
                    // Built directly rather than through a route, so the golden is
                    // the shell alone: the route's barrier is not what is pinned.
                    child: _GoldenDialog(
                      calls: calls,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the form dialog matches its light golden', (tester) async {
      await pour(tester, Brightness.light);
      await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_dialog_light.png'));
    });

    testWidgets('the form dialog matches its dark golden', (tester) async {
      await pour(tester, Brightness.dark);
      await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_dialog_dark.png'));
    });
  });
}

/// The dialog's shell, laid out in a box of its own rather than in a route: an
/// `AppDialog` reads its box from a `LayoutBuilder`, so a `SizedBox` is its window.
class _GoldenDialog extends StatelessWidget {
  const _GoldenDialog({required this.calls});

  final _Calls calls;

  @override
  Widget build(BuildContext context) => AppDialog(
        title: 'Move this Work order?',
        description: 'The Work order keeps its history and its Assignee.',
        actions: [
          AppDialogAction(
            id: 'cancel',
            label: 'Keep it open',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => calls.dismiss++,
          ),
          AppDialogAction(id: 'save', label: 'Move Work order', onPressed: () => calls.primary++),
        ],
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(decoration: InputDecoration(labelText: 'Reason (optional)')),
          ],
        ),
      );
}
