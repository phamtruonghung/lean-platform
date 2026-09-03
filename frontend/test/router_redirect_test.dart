import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/not_found_screen.dart';
import 'package:lean_platform/platform/platform_app.dart';

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({String? accessToken}) : _token = accessToken;

  String? _token;
  final StreamController<String?> _controller = StreamController<String?>.broadcast();

  @override
  String? get currentAccessToken => _token;

  /// Honours [AuthGateway]'s contract: the current token first, then every
  /// change after it.
  @override
  Stream<String?> get accessTokenChanges async* {
    yield _token;
    yield* _controller.stream;
  }

  void emitToken(String? token) {
    _token = token;
    _controller.add(token);
  }

  @override
  Future<void> signInWithPassword({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signUp({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signInWithGoogle() async => emitToken('token-for-google');

  @override
  Future<void> signOut() async => emitToken(null);
}

http.Client meClient(Map<String, dynamic> Function() body, {int status = 200}) {
  return MockClient((request) async => http.Response(jsonEncode(body()), status));
}

Map<String, dynamic> activeBody = {
  'status': 'active',
  'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'administrator'},
};

Map<String, dynamic> pendingBody = {
  'status': 'pending_approval',
  'account': {'email': 'a@b.c'},
};

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthGateway gateway,
  required http.Client client,
  String? initialLocation,
}) async {
  await tester.pumpWidget(
    PlatformApp(
      authGateway: gateway,
      peopleApi: PeopleApi(client: client),
      initialLocation: initialLocation,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a signed-out caller reaching a protected address arrives at sign-in',
      (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: meClient(() => activeBody),
      initialLocation: '/',
    );

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('after signing in the caller is delivered to the address they asked for',
      (tester) async {
    final gateway = FakeAuthGateway();
    await pumpApp(
      tester,
      gateway: gateway,
      client: meClient(() => activeBody),
      initialLocation: '/deep/link',
    );

    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'a@b.c');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // /deep/link matches no route, so the caller is delivered there and gets
    // the not-found Screen — which is the point: they were delivered, not
    // dumped on the home Screen.
    expect(find.byType(NotFoundScreen), findsOneWidget);
  });

  testWidgets('an Account awaiting Approval is sent to the awaiting-Approval Screen '
      'from every address', (tester) async {
    for (final location in ['/', '/some/deep/link']) {
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: meClient(() => pendingBody),
        initialLocation: location,
      );

      expect(find.byType(AwaitingApprovalScreen), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
    }
  });

  testWidgets('an admitted Account reaching a protected address is not redirected',
      (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => activeBody),
      initialLocation: '/',
    );

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Welcome, A B'), findsOneWidget);
  });

  testWidgets('an address matching no Screen renders the not-found Screen', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => activeBody),
      initialLocation: '/nowhere',
    );

    expect(find.byType(NotFoundScreen), findsOneWidget);
  });

  testWidgets('a reload with an existing session restores the Screen with no sign-in flash',
      (tester) async {
    final gateway = FakeAuthGateway(accessToken: 'a-token');
    await tester.pumpWidget(
      PlatformApp(
        authGateway: gateway,
        peopleApi: PeopleApi(client: meClient(() => activeBody)),
        initialLocation: '/',
      ),
    );
    // First frame only, before /me has resolved. AccountBloc computes its
    // initial state from the gateway's current token directly, so a caller
    // reloading with a live session never passes through AccountSignedOut —
    // if it had, this frame would show SignInScreen.
    expect(find.byType(SignInScreen), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('signing out clears the Account and returns to sign-in', (tester) async {
    final gateway = FakeAuthGateway(accessToken: 'a-token');
    await pumpApp(
      tester,
      gateway: gateway,
      client: meClient(() => activeBody),
      initialLocation: '/',
    );
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a rejected session returns to sign-in rather than an error', (tester) async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response(jsonEncode(<String, dynamic>{}), 401);
    });

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-stale-token'),
      client: client,
      initialLocation: '/',
    );

    expect(find.byType(SignInScreen), findsOneWidget);
    // Not a retry loop: exactly one call for the one token this session ever
    // had.
    expect(callCount, 1);
  });

  testWidgets('a role changed on the server takes effect on the next token', (tester) async {
    var body = pendingBody;
    final gateway = FakeAuthGateway(accessToken: 'token-1');
    await pumpApp(
      tester,
      gateway: gateway,
      client: meClient(() => body),
      initialLocation: '/',
    );
    expect(find.byType(AwaitingApprovalScreen), findsOneWidget);

    body = activeBody;
    gateway.emitToken('token-2');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
