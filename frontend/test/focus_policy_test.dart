/// The Platform's keyboard policy, measured on six surfaces (issue #401).
///
/// `docs/design-language.md` §8 says one thing and this file checks it six
/// times: a Screen's controls are reachable in a stated order, a dialog traps
/// focus and gives it back, `Esc` and `Enter` do what the policy says, the Shell
/// can be skipped and its Destinations announce where the reader is, and the
/// focus ring is drawn from the token. The walk itself is `focus_order.dart` —
/// one helper, so the six cases cannot each check a slightly different thing.
///
/// The six are the ones the ticket names: a register, a detail, a form dialog,
/// a confirm dialog, the Shell and the sign-in Screen. Every reading here is
/// `FocusManager.instance.primaryFocus`, which is what a screen reader and a
/// keyboard both follow — no Bloc, no Screen state and no `FocusNode` the
/// Screen owns is inspected.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/change_password_bloc.dart';
import 'package:lean_platform/platform/change_password_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';
import 'package:lean_platform/widgets/app_dialog.dart';
import 'package:lean_platform/widgets/app_form_submit.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/palette_toggle.dart';

import 'focus_order.dart';
import 'harness.dart';

const _invokerKey = ValueKey<String>('focus-test-invoker');
const _homeDestinationKey = ValueKey<String>('nav-item-Home');

/// The Shell on a real router, for the measurements that need no app: the skip
/// control's own height under `MaterialTapTargetSize.shrinkWrap`.
Widget _shellHarness({MaterialTapTargetSize tapTargetSize = MaterialTapTargetSize.padded}) {
  final router = GoRouter(
    initialLocation: '/directory',
    routes: [
      ShellRoute(
        builder: (context, state, child) => PlatformShell(
          destinations: const [
            Destination(label: 'Directory', icon: Icons.badge_outlined, path: '/directory'),
          ],
          currentLocation: state.uri.path,
          onDestinationSelected: (destination) => context.go(destination.path),
          account: const AccountActive(id: '1', email: 'a@b.c', displayName: 'A B', role: Roles.admin),
          onSignOut: () {},
          darkPalette: false,
          onToggleDarkPalette: () {},
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/directory',
            builder: (context, state) => const Center(child: Text('Directory Screen')),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    theme: buildAppTheme(Brightness.light).copyWith(materialTapTargetSize: tapTargetSize),
    routerConfig: router,
  );
}

/// Walks `Tab` out of [screen] and then through the Shell's chrome, returning
/// every chrome stop — the skip control first, the Screen's first control
/// closing the loop. Everything here is a key press; nothing calls a callback.
Future<List<FocusStop>> _walkOutOfTheScreen(
  WidgetTester tester,
  FocusWalker walker,
  Finder screen, {
  int leaveLimit = 25,
}) async {
  final region = tester.element(screen.first);
  final stops = <FocusStop>[];
  var left = false;
  for (var i = 0; i < leaveLimit; i++) {
    await walker.forward();
    if (walker.now.key == PlatformShell.skipToContentKey) {
      left = true;
      break;
    }
  }
  if (!left) fail('Tab never left the Screen for the Shell within $leaveLimit presses');
  stops.add(walker.now);
  for (var i = 0; i < 80; i++) {
    await walker.forward();
    final context = FocusManager.instance.primaryFocus?.context;
    if (context is Element && _isInside(context, region)) return stops;
    stops.add(walker.now);
  }
  fail('the chrome run never handed back to the Screen');
}

bool _isDestinationKey(Widget widget) =>
    widget.key is ValueKey<String> &&
    (widget.key! as ValueKey<String>).value.startsWith('nav-item-');

bool _isInside(Element element, Element region) {
  if (identical(element, region)) return true;
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (identical(ancestor, region)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// A wire with two Work orders, enough of a Site and Org Unit for the register,
/// and one Work order's detail behind it.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe'),
          workOrderJson('102', 'WO-102', 'Guard is loose'),
        ],
      },
      workOrderTasks: {
        '101': [
          workOrderTaskJson('t1', 1, 'Isolate the press', status: 'done'),
          // A metered task, so the detail offers its Record control too.
          workOrderTaskJson('t2', 2, 'Record vibration',
              assetMeterId: '5', meterName: 'Vibration', status: 'pending'),
        ],
      },
      workOrderCosts: {
        '101': workOrderCostJson(labourHours: 3, partsCost: 0),
      },
    );

Future<void> _pumpApp(WidgetTester tester, {String? at, Size size = const Size(1280, 1000)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire().client,
    initialLocation: at,
  );
}

void main() {
  testWidgets('a register: its rows are stops, a focused row wears the ring, and nothing is pointer-only',
      (tester) async {
    await _pumpApp(tester, at: '/work-orders');
    final walker = FocusWalker(tester);

    // Walked from the register's own first control, in the order a keyboard
    // meets it: the header's controls and the filter, then row 101 — the row
    // before the two controls inside it. `forward` fails on a press that leaves
    // `primaryFocus` on the same `FocusNode`, so each of these four is a live
    // press on a different control: the filter field appears once because the
    // keyboard leaves it once.
    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final head = (await walker.forward(4)).map((stop) => stop.key).toList();
    expect(head, [
      WorkOrdersScreen.filterKey,
      WorkOrdersScreen.showHistoryKey,
      AppFilterField.fieldKey('work-orders-filter'),
      WorkOrdersScreen.detailsKey('101'),
    ]);
    // The row is where the reader is, and it says so without a tint.
    expect(walker.ringIsVisible, isTrue,
        reason: 'a focused row must show the 2px token ring, not a tint');

    // The controls inside the row follow it, so a row is never a pointer-only
    // way into a record.
    final inside = (await walker.forward(2)).map((stop) => stop.key).toList();
    expect(inside, [
      WorkOrdersScreen.startKey('101'),
      WorkOrdersScreen.rowActionsKey('101'),
    ]);
  });

  testWidgets('a detail: its controls are one run in the tab order, starting at the way back',
      (tester) async {
    await _pumpApp(tester, at: '/work-orders/101');
    expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
    final walker = FocusWalker(tester);

    final entered = await walker.enter(find.byType(WorkOrderDetailScreen));
    expect(entered.key, WorkOrderDetailScreen.backKey,
        reason: 'the page starts where a keyboard leaves it: the way back');

    // The page is one contiguous run of stops in the order a reader meets them,
    // and its end hands over to the Shell (issue #401) rather than looping back
    // to its own first control.
    final stops = await walker.within(find.byType(WorkOrderDetailScreen), limit: 14);
    expect(stops.map((stop) => stop.key).toList(), [
      WorkOrderDetailScreen.bookLabourKey,
      WorkOrderDetailScreen.bookPartKey,
      WorkOrderDetailScreen.recordReadingKey('t2'),
    ]);
    expect(walker.now.key, PlatformShell.skipToContentKey,
        reason: 'the last control of the page hands over to the Shell, by Tab alone');

    // And the seam closes in the other direction on this page too, not only on
    // the register: `Shift+Tab` from the page's first control hands back to the
    // chrome instead of stopping at the page's own edge (issue #401).
    await walker.enter(find.byType(WorkOrderDetailScreen));
    expect(walker.now.key, WorkOrderDetailScreen.backKey);
    final sidebar = tester.element(find.byKey(PlatformShell.sidebarKey));
    await walker.backward();
    final backwards = FocusManager.instance.primaryFocus?.context;
    expect(backwards is Element && _isInside(backwards, sidebar), isTrue,
        reason: 'Shift+Tab from the first control of a detail page lands in the Shell');
  });

  testWidgets('a form dialog: focus starts in the field, Enter submits, and Tab cannot leave',
      (tester) async {
    final invoker = FocusNode(debugLabel: 'form dialog invoker');
    addTearDown(invoker.dispose);
    final wire = FakeWire(sites: [siteJson('1', 'HCM', 'Ho Chi Minh')]);
    await tester.pumpWidget(
      RepositoryProvider<PeopleApi>(
        create: (_) => PeopleApi(client: wire.client),
        child: RepositoryProvider<AuthGateway>(
          create: (_) => FakeAuthGateway(),
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: _invokerKey,
                  focusNode: invoker,
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => BlocProvider<ChangePasswordBloc>(
                      create: (dialogContext) => ChangePasswordBloc(
                        peopleApi: dialogContext.read<PeopleApi>(),
                        authGateway: dialogContext.read<AuthGateway>(),
                      ),
                      child: const ChangePasswordDialog(),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    invoker.requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(_invokerKey));
    await tester.pumpAndSettle();

    final walker = FocusWalker(tester);
    // First focus is the dialog's own first field, inside the dialog — not the
    // button that opened it.
    expect(walker.now.key, ChangePasswordDialog.currentFieldKey);
    expect(walker.now.field, isTrue);
    expect(await walker.staysInside(find.byType(ChangePasswordDialog), tabs: 12), isTrue,
        reason: 'twelve Tab presses must never leave the dialog');

    // `Enter` in a single-line field runs the form's own submit — which refuses,
    // in the dialog's own words, exactly as the button does.
    expect(AppFormSubmit.focusIsInSingleLineField(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Enter your current password.'), findsOneWidget);

    // And it acts only from a field: with nothing focused there is nothing to
    // submit.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(AppFormSubmit.focusIsInSingleLineField(), isFalse);
  });

  testWidgets('a confirm dialog: it traps, Esc dismisses it, and focus comes back to the invoker',
      (tester) async {
    final invoker = FocusNode(debugLabel: 'confirm invoker');
    addTearDown(invoker.dispose);
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: _invokerKey,
              focusNode: invoker,
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => AppConfirmDialog(
                  title: 'Cancel this Work order?',
                  description: 'The record keeps its history.',
                  confirmLabel: 'Cancel it',
                  dismissLabel: 'Keep it open',
                  onConfirm: () => Navigator.of(dialogContext).pop(),
                  onDismiss: () {
                    dismissed++;
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    invoker.requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(_invokerKey));
    await tester.pumpAndSettle();

    final walker = FocusWalker(tester);
    // A dialog whose only act is destructive opens on its dismiss, so `Enter`
    // on opening cancels rather than confirms.
    expect(walker.now.key, AppConfirmDialog.dismissKey);
    expect(await walker.staysInside(find.byKey(AppDialog.surfaceKey), tabs: 12), isTrue,
        reason: "the trap is the dialog's promise");

    // `Esc` runs that same dismiss action, and focus goes back to the invoker.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(find.byType(AppConfirmDialog), findsNothing);
    expect(walker.now.key, _invokerKey);
    expect(invoker.hasPrimaryFocus, isTrue);
  });

  testWidgets('the Shell: the Screen hands over to the skip control, and every Destination is a stop',
      (tester) async {
    await _pumpApp(tester, at: '/work-orders');
    // A ring is only worn under traditional highlight mode, which a real key
    // press sets; this case enters the control programmatically.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final walker = FocusWalker(tester);

    final skip = find.byKey(PlatformShell.skipToContentKey);
    expect(skip, findsOneWidget);
    expect(find.descendant(of: skip, matching: find.text('Skip to content')), findsOneWidget);

    // The Screen's run, walked by key presses only: within 25 presses `Tab`
    // leaves the register for the Shell's skip control, walks the chrome, and
    // hands back to the Screen's first control.
    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final chrome = await _walkOutOfTheScreen(tester, walker, find.byType(WorkOrdersScreen));
    expect(chrome.first.key, PlatformShell.skipToContentKey,
        reason: 'the last control of a Screen hands over to the Shell, by Tab alone');
    final destinations = [
      for (final stop in chrome)
        if (stop.key is ValueKey<String> &&
            (stop.key! as ValueKey<String>).value.startsWith('nav-item-'))
          (stop.key! as ValueKey<String>).value,
    ];
    expect(destinations.first, 'nav-item-Home',
        reason: 'a Destination comes straight after the skip control');
    expect(destinations.toSet().length, destinations.length,
        reason: 'the run visits each Destination once, no repeats');
    // Every Destination the Shell was handed is on that run — the set is read
    // off the widget tree, so a Destination the walk missed fails the case.
    final rendered = {
      for (final element in find.byWidgetPredicate(_isDestinationKey).evaluate())
        (element.widget.key! as ValueKey<String>).value,
    };
    expect(destinations.toSet(), rendered,
        reason: 'every Destination is a stop of the run, none is pointer-only');
    // The account footer follows them, and the Screen's first control closes
    // the loop.
    expect(chrome.length, greaterThan(destinations.length),
        reason: 'the account footer is part of the chrome run');
    expect(walker.now.key, WorkOrdersScreen.raiseKey,
        reason: 'the last chrome stop hands over to the Screen first control');

    // The seam works in both directions: `Shift+Tab` from the Screen's first
    // control lands back in the chrome, and again walks towards the skip
    // control rather than looping inside the Screen.
    final sidebar = tester.element(find.byKey(PlatformShell.sidebarKey));
    await walker.backward();
    final backwards = FocusManager.instance.primaryFocus?.context;
    expect(backwards is Element && _isInside(backwards, sidebar), isTrue,
        reason: 'Shift+Tab from the first Screen control lands in the chrome');
    await walker.backward();
    final furtherBack = FocusManager.instance.primaryFocus?.context;
    expect(furtherBack is Element && _isInside(furtherBack, sidebar), isTrue,
        reason: 'and keeps walking the chrome backwards');

    // A Destination is a stop: it takes the focus, it wears the ring, and
    // `Enter` on it goes there — the keyboard reaches every Screen.
    await walker.enter(find.byKey(_homeDestinationKey));
    expect(walker.now.key, _homeDestinationKey);
    expect(walker.ringIsVisible, isTrue,
        reason: 'a focused Destination wears the same 2px token ring');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(locationOf(tester, find.byType(PlatformShell)), '/',
        reason: 'Enter on a focused Destination must go there — Home is `/`');

    // The current Destination says so, rather than only looking different.
    final announcement = tester
        .widgetList<Semantics>(
          find.descendant(of: find.byKey(_homeDestinationKey), matching: find.byType(Semantics)),
        )
        .firstWhere((node) => node.properties.selected != null);
    expect(announcement.properties.selected, isTrue);
  });

  testWidgets('the Shell at the 700px breakpoint: the expanded sidebar is one run', (tester) async {
    // Exactly the breakpoint, which is the *expanded* sidebar (`< railBreakpoint`
    // collapses, so 700 does not): the narrowest window that still draws the
    // 260px sidebar and its labels. The rail below it is the next case.
    await _pumpApp(tester, at: '/work-orders', size: const Size(700, 1000));
    final walker = FocusWalker(tester);

    final sidebar = find.byKey(PlatformShell.sidebarKey);
    expect(tester.getSize(sidebar).width, PlatformShell.expandedWidth,
        reason: '700 is not below the breakpoint: the sidebar, not the rail');

    final skip = find.byKey(PlatformShell.skipToContentKey);
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the skip control keeps its 44px target on the narrow box');

    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final chrome = await _walkOutOfTheScreen(tester, walker, find.byType(WorkOrdersScreen));
    expect(chrome.first.key, PlatformShell.skipToContentKey);
    final destinations = [
      for (final stop in chrome)
        if (stop.key is ValueKey<String> &&
            (stop.key! as ValueKey<String>).value.startsWith('nav-item-'))
          (stop.key! as ValueKey<String>).value,
    ];
    expect(destinations.first, 'nav-item-Home');
    expect(destinations.toSet().length, destinations.length);
    expect(chrome.length, greaterThan(destinations.length));
    expect(walker.now.key, WorkOrdersScreen.raiseKey);
  });

  testWidgets('the Shell below the 700px breakpoint: the rail is one run too', (tester) async {
    // 640 is under `railBreakpoint`, so every Destination is its icon alone and
    // its label comes back as a `Tooltip` — the surface the 700px case above
    // does *not* walk, whatever its old name said.
    await _pumpApp(tester, at: '/work-orders', size: const Size(640, 1000));
    final walker = FocusWalker(tester);

    final sidebar = find.byKey(PlatformShell.sidebarKey);
    expect(tester.getSize(sidebar).width, PlatformShell.collapsedWidth,
        reason: 'below the breakpoint the Shell draws the 64px rail');

    // The rail's Destination is its icon; the label is the tooltip's job.
    final home = find.byKey(_homeDestinationKey);
    expect(find.descendant(of: home, matching: find.byType(Text)), findsNothing,
        reason: 'on the rail a Destination draws no label at all');
    final homeTooltip = tester.widget<Tooltip>(
      find.descendant(of: home, matching: find.byType(Tooltip)).first,
    );
    expect(homeTooltip.message, 'Home',
        reason: 'the label the rail drops is still announced, by the tooltip');

    final skip = find.byKey(PlatformShell.skipToContentKey);
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the skip control keeps its 44px target on the rail too');

    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final chrome = await _walkOutOfTheScreen(tester, walker, find.byType(WorkOrdersScreen));
    expect(chrome.first.key, PlatformShell.skipToContentKey);
    final destinations = [
      for (final stop in chrome)
        if (stop.key is ValueKey<String> &&
            (stop.key! as ValueKey<String>).value.startsWith('nav-item-'))
          (stop.key! as ValueKey<String>).value,
    ];
    // Every Destination the rail draws is on the run — read off the tree, so a
    // rail item the walk missed fails here rather than passing quietly.
    final rendered = {
      for (final element in find.byWidgetPredicate(_isDestinationKey).evaluate())
        (element.widget.key! as ValueKey<String>).value,
    };
    expect(rendered, isNotEmpty);
    expect(destinations.toSet(), rendered,
        reason: 'every Destination on the rail is a stop, none is pointer-only');
    expect(destinations.toSet().length, destinations.length);
    expect(chrome.length, greaterThan(destinations.length),
        reason: 'the account footer follows them on the rail as well');
    expect(walker.now.key, WorkOrdersScreen.raiseKey,
        reason: 'the last chrome stop hands over to the Screen first control');
  });

  testWidgets('the Shell at twice the text: the run holds', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, at: '/work-orders');
    final walker = FocusWalker(tester);

    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final chrome = await _walkOutOfTheScreen(tester, walker, find.byType(WorkOrdersScreen));
    expect(chrome.first.key, PlatformShell.skipToContentKey);
    final destinations = [
      for (final stop in chrome)
        if (stop.key is ValueKey<String> &&
            (stop.key! as ValueKey<String>).value.startsWith('nav-item-'))
          (stop.key! as ValueKey<String>).value,
    ];
    expect(destinations.first, 'nav-item-Home');
    expect(destinations.toSet().length, destinations.length);
    expect(chrome.length, greaterThan(destinations.length));
    expect(walker.now.key, WorkOrdersScreen.raiseKey);
  });

  testWidgets('the skip control is 44px tall when Material does not pad it', (tester) async {
    // `MaterialTapTargetSize.padded` silently lifts a 40px minimum to 48, which
    // is exactly how a `minimumSize` regression stays green. `shrinkWrap` shows
    // the control's own height.
    await tester.pumpWidget(_shellHarness(tapTargetSize: MaterialTapTargetSize.shrinkWrap));
    await tester.pumpAndSettle();
    final skip = find.byKey(PlatformShell.skipToContentKey);
    expect(skip, findsOneWidget);
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'the control draws its own 44px, not Material padding');
  });

  testWidgets('the sign-in Screen: the form is a run of stops and Enter signs in from a field',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<AuthGateway>.value(
        value: FakeAuthGateway(),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: SignInScreen(darkPalette: false, onToggleDarkPalette: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final walker = FocusWalker(tester);

    // The front door's own run: the palette switch first (the one control
    // outside the form, and in reach before anything is typed), then six stops
    // of the form itself.
    final stops = await walker.within(find.byType(SignInScreen), limit: 7);
    expect(stops.first.describe(), PaletteToggle.buttonKey.toString());
    expect(stops.length, 7);

    // The two fields are the form's first two stops after the switch, and the
    // keyboard meets them in the order they are read.
    final email = await walker.enter(find.byType(TextFormField).first);
    expect(email.field, isTrue, reason: 'the Email field is a stop of its own');
    final next = (await walker.forward())[0];
    expect(next.field, isTrue, reason: 'the Password field follows it');

    // `Enter` in the email field submits the form, and the form's own validator
    // is what refuses — which is the proof that the submit ran.
    await walker.enter(find.byType(TextFormField).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
  });
}

