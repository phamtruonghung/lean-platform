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

import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/change_password_bloc.dart';
import 'package:lean_platform/platform/change_password_dialog.dart';
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
    // before the two controls inside it.
    await walker.enter(find.byKey(WorkOrdersScreen.raiseKey));
    final head = (await walker.forward(5)).map((stop) => stop.key).toList();
    expect(head, [
      WorkOrdersScreen.filterKey,
      WorkOrdersScreen.showHistoryKey,
      AppFilterField.fieldKey('work-orders-filter'),
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

    // The page is one contiguous run of stops that returns to its own start: the
    // keyboard never leaves the page's scope (a Screen is a route of its own —
    // see `docs/design-language.md` §8 on what that costs).
    final stops = await walker.within(find.byType(WorkOrderDetailScreen), limit: 14);
    expect(stops.take(4).map((stop) => stop.key).toList(), [
      WorkOrderDetailScreen.bookLabourKey,
      WorkOrderDetailScreen.bookPartKey,
      WorkOrderDetailScreen.recordReadingKey('t2'),
      WorkOrderDetailScreen.backKey,
    ]);
    expect(stops.length, greaterThan(4),
        reason: 'a page of four controls is a run, not a single stop');
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

  testWidgets('the Shell: the skip control leads, the Destinations walk, and the current one is announced',
      (tester) async {
    await _pumpApp(tester, at: '/work-orders');
    // A ring is only worn under traditional highlight mode, which a real key
    // press sets; this case enters the control programmatically.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final walker = FocusWalker(tester);

    // The skip control is drawn before everything, is a 44px control, and its
    // action puts focus inside the Screen rather than on a Destination.
    final skip = find.byKey(PlatformShell.skipToContentKey);
    expect(skip, findsOneWidget);
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(find.descendant(of: skip, matching: find.text('Skip to content')), findsOneWidget);
    await tester.runAsync(() async {});
    tester.widget<TextButton>(find.descendant(of: skip, matching: find.byType(TextButton)))
        .onPressed!();
    await tester.pumpAndSettle();
    // The first control the Screen itself offers, in the order it is built.
    expect(walker.now.key, AppFilterField.fieldKey('work-orders-filter'),
        reason: 'skipping the chrome lands on the first control the Screen offers');

    // A Destination is a stop: it takes the focus, it wears the ring, and `Enter`
    // on it goes there — the keyboard reaches every Screen.
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

