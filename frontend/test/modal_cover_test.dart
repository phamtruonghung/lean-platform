/// Every popup covers the whole window, the Shell's own column included.
///
/// A Screen is a route of the `ShellRoute`'s navigator, so a popup over it is a
/// route of that same navigator and its barrier fills the *content* box — the
/// 260px sidebar column stands outside it. Measured before the fix, at
/// 1280x900: the raise form's barrier read `(260, 0, 1280, 900)` and the
/// sidebar stayed bright and clickable under an open dialog.
///
/// The three cases below pin the property rather than one dialog's geometry: the
/// window has no unshaded column whichever way a popup was opened — by address
/// (`/leave-requests/new`, a `DialogPage`), by `showDialog` (the approval
/// queue's rejection), and at the 64px rail as well as the 260px sidebar. A
/// fourth pins the empty case: with nothing open the Shell shades nothing, so a
/// stray scrim cannot hide the chrome.
///
/// `modal_layer.dart` carries the reasoning; this file measures what a reader
/// sees, through the real router with the wire faked, as `focus_policy_test.dart`
/// does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/leave_requests_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/modal_layer.dart';
import 'package:lean_platform/platform/router.dart' show Routes;
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart';

final _readGrantScope = {
  'everywhere': false,
  'grants': [scopeGrantJson('10')],
};

List<Map<String, dynamic>> _leaveTypes() => [
      absenceReasonJson('HOL', 'Annual leave', isRequestable: true),
      absenceReasonJson('UNP', 'Unpaid leave', isRequestable: true),
      absenceReasonJson('SICK', 'Sickness'),
    ];

/// The window the app is pumped into, in logical pixels.
const Size _window = Size(1280, 900);

Future<void> _pump(WidgetTester tester, FakeWire wire, String location, {Size size = _window}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
  await tester.pumpAndSettle();
}

/// Every rect in the window that is a modal shade, the Shell's and the route's
/// alike.
List<Rect> _shaded(WidgetTester tester) => <Rect>[
      for (final Element element in <Element>[
        ...find.byType(ModalBarrier, skipOffstage: false).evaluate(),
        ...find.byType(AnimatedModalBarrier, skipOffstage: false).evaluate(),
      ])
        tester.getRect(find.byElementPredicate((Element e) => e == element)),
    ];

/// Whether the shade reaches [x] at the window's middle — the property the card
/// asks for, stated as the reader sees it rather than as a list of widgets.
void _expectShaded(WidgetTester tester, double x) {
  final double y = tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
  expect(
    _shaded(tester).any((Rect rect) => rect.contains(Offset(x, y))),
    isTrue,
    reason: 'x=$x at the window\'s middle is left unshaded: the popup does not '
        'cover the screen',
  );
}

FakeWire _leaveWire() => FakeWire(
      role: Roles.operator,
      orgUnitScope: _readGrantScope,
      absenceReasons: _leaveTypes(),
      leaveRequestsMine: [leaveRequestJson('1', note: 'Family trip', canCancel: true)],
    );

void main() {
  testWidgets('the raise form shades the sidebar the Screen does not own', (tester) async {
    await _pump(tester, _leaveWire(), Routes.leaveRequests);
    await tapIn(tester, find.byKey(LeaveRequestsScreen.requestKey));

    // The Shell's own share of the shade, and its width: exactly the sidebar.
    final Finder scrim = find.byKey(PlatformShell.modalScrimKey);
    expect(scrim, findsOneWidget);
    expect(
      tester.getRect(scrim),
      Rect.fromLTWH(0, 0, PlatformShell.expandedWidth, _window.height),
      reason: 'the Shell shades its own column and no more',
    );

    // The shade is the modal's own barrier, not a second colour: same token,
    // which is what makes the two read as one layer across the window.
    final ModalScrim drawn = tester.widget<ModalScrim>(scrim);
    final AnimatedModalBarrier barrier = tester.widget<AnimatedModalBarrier>(
      find.descendant(of: scrim, matching: find.byType(AnimatedModalBarrier)),
    );
    expect(barrier.color.value, drawn.route.barrierColor);

    // No column of the window is left out: the sidebar's left edge, the seam at
    // its border, and the Screen's full width.
    _expectShaded(tester, 0);
    _expectShaded(tester, PlatformShell.expandedWidth - 1);
    _expectShaded(tester, PlatformShell.expandedWidth);
    _expectShaded(tester, _window.width - 1);
  });

  testWidgets('a confirm dialog opened with showDialog shades it too', (tester) async {
    await _pump(
      tester,
      FakeWire(queue: [pendingJson('7', 'first@b.c', DateTime.now().subtract(const Duration(hours: 3)))]),
      Routes.approvals,
    );
    await tapIn(tester, find.byKey(ApprovalQueueScreen.rejectKey('7')));

    expect(find.byKey(PlatformShell.modalScrimKey), findsOneWidget);
    _expectShaded(tester, 0);
    _expectShaded(tester, _window.width - 1);
  });

  testWidgets('at the 64px rail the shade still reaches the window edge', (tester) async {
    await _pump(tester, _leaveWire(), Routes.leaveRequests, size: const Size(600, 900));
    await tapIn(tester, find.byKey(LeaveRequestsScreen.requestKey));

    final Finder scrim = find.byKey(PlatformShell.modalScrimKey);
    expect(
      tester.getRect(scrim),
      Rect.fromLTWH(0, 0, PlatformShell.collapsedWidth, 900),
      reason: 'the rail is what the Shell actually draws at this width',
    );
    _expectShaded(tester, 0);
    _expectShaded(tester, PlatformShell.collapsedWidth);
  });

  testWidgets('with nothing open the Shell shades nothing', (tester) async {
    await _pump(tester, _leaveWire(), Routes.leaveRequests);

    expect(find.byKey(PlatformShell.modalScrimKey), findsNothing);
    expect(find.byType(AnimatedModalBarrier, skipOffstage: false), findsNothing);
  });
}
