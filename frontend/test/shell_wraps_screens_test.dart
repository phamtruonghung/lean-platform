import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/not_found_screen.dart';
import 'package:lean_platform/platform/shell.dart';

// The Account fakes already used by the redirect tests, rather than a second
// copy of them. `show` keeps that file's own `main` out of this one.
import 'router_redirect_test.dart' show FakeAuthGateway, meClient, pumpApp;

final Map<String, dynamic> _adminBody = {
  'status': 'active',
  'account': {'email': 'a@b.c', 'displayName': 'A B', 'role': Roles.admin},
};

final Map<String, dynamic> _pendingBody = {
  'status': 'pending_approval',
  'account': {'email': 'a@b.c'},
};

void main() {
  testWidgets('the Shell wraps the Screen an admitted Account reaches', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => _adminBody),
      initialLocation: '/',
    );

    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    // The footer identifies who is signed in, on the Screen itself.
    expect(find.text('A B'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
  });

  // One `pumpApp` per test on purpose: pumping a second PlatformApp into the
  // same tester reuses the existing State, so the second gateway and client
  // would be ignored.
  testWidgets('the sign-in Screen renders outside the Shell', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: meClient(() => _adminBody),
      initialLocation: '/',
    );

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
  });

  testWidgets('the awaiting-Approval Screen renders outside the Shell', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => _pendingBody),
      initialLocation: '/',
    );

    expect(find.byType(AwaitingApprovalScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
  });

  testWidgets('the not-found Screen renders outside the Shell', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => _adminBody),
      initialLocation: '/nowhere',
    );

    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
  });
}
