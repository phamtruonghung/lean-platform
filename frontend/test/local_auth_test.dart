import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/platform/auth_bootstrap.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/local_auth_gateway.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/sign_out_on_unauthorized.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart' show FakeAuthApi, FakeAuthGateway, FakeWire, pumpApp;

/// Issue #269: signing in against the API's own endpoints, chosen at boot.

Future<void> signInWith(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@b.c');
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret-pass');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('boot selects the gateway from /api/auth/mode', () {
    test('local selects the local gateway and never calls Supabase', () async {
      var supabaseCalls = 0;
      final gateway = await bootstrapAuth(
        client: FakeAuthApi(mode: 'local').client,
        supabase: () async {
          supabaseCalls++;
          return FakeAuthGateway();
        },
      );
      expect(gateway, isA<LocalAuthGateway>());
      expect(supabaseCalls, 0);
    });

    for (final (name, client) in <(String, http.Client)>[
      ('supabase', FakeAuthApi(mode: 'supabase').client),
      ('an unknown value', FakeAuthApi(mode: 'ldap').client),
      ('a 500', MockClient((_) async => http.Response('boom', 500))),
      ('garbage', MockClient((_) async => http.Response('<html>', 200))),
      ('an unreachable API', MockClient((_) async => throw Exception('offline'))),
    ]) {
      test('$name calls the Supabase path', () async {
        var supabaseCalls = 0;
        final gateway = await bootstrapAuth(
          client: client,
          supabase: () async {
            supabaseCalls++;
            return FakeAuthGateway();
          },
        );
        expect(gateway, isA<FakeAuthGateway>());
        expect(supabaseCalls, 1);
      });
    }
  });

  testWidgets('an API that never answers still reaches the sign-in screen', (tester) async {
    final neverAnswers = MockClient((_) => Completer<http.Response>().future);
    AuthGateway? gateway;
    unawaited(bootstrapAuth(client: neverAnswers, supabase: () async => FakeAuthGateway())
        .then((g) => gateway = g));
    await tester.pump(const Duration(seconds: 6));

    expect(gateway, isA<FakeAuthGateway>());
    await pumpApp(tester, gateway: gateway!, client: FakeAuthApi().client);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a refused login shows the API message verbatim', (tester) async {
    final api = FakeAuthApi(loginStatus: 401);
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client);

    await signInWith(tester);

    expect(find.text('Email or password is not recognised.'), findsOneWidget);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a good login lands past sign-in and sends the bearer token', (tester) async {
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client);

    await signInWith(tester);

    expect(find.byType(SignInScreen), findsNothing);
    expect(api.requests, contains('POST /api/auth/login'));
    expect(api.bearers, contains('Bearer opaque-token'));
  });

  testWidgets('Continue with Google says this deployment has none', (tester) async {
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('This deployment has no Google sign-in.'), findsOneWidget);
  });

  testWidgets('Create an account says an administrator creates them', (tester) async {
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@b.c');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret-pass');
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Accounts on this deployment are created by an administrator.'),
      findsOneWidget,
    );
  });

  testWidgets('a stored session survives a reload', (tester) async {
    SharedPreferences.setMockInitialValues({
      LocalAuthGateway.tokenKey: 'stored-token',
      LocalAuthGateway.expiresAtKey:
          DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client, initialLocation: '/');

    expect(gateway.currentAccessToken, 'stored-token');
    expect(find.byType(SignInScreen), findsNothing);
    expect(api.bearers, contains('Bearer stored-token'));
  });

  test('a stored session past its expiry is dropped on load', () async {
    SharedPreferences.setMockInitialValues({
      LocalAuthGateway.tokenKey: 'stale-token',
      LocalAuthGateway.expiresAtKey:
          DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String(),
    });
    final gateway = await LocalAuthGateway.load(client: FakeAuthApi().client);

    expect(gateway.currentAccessToken, isNull);
    expect((await SharedPreferences.getInstance()).getString(LocalAuthGateway.tokenKey), isNull);
  });

  testWidgets('signing out posts logout with the bearer, clears storage, shows sign-in',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      LocalAuthGateway.tokenKey: 'stored-token',
      LocalAuthGateway.expiresAtKey:
          DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(client: api.client);
    await pumpApp(tester, gateway: gateway, client: api.client, initialLocation: '/');

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(api.logoutBearers, ['Bearer stored-token']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalAuthGateway.tokenKey), isNull);
    expect(prefs.getString(LocalAuthGateway.expiresAtKey), isNull);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('sign-out still succeeds when the logout call fails', (tester) async {
    SharedPreferences.setMockInitialValues({
      LocalAuthGateway.tokenKey: 'stored-token',
      LocalAuthGateway.expiresAtKey:
          DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });
    final api = FakeAuthApi();
    final gateway = await LocalAuthGateway.load(
      client: MockClient((_) async => throw Exception('offline')),
    );
    await pumpApp(tester, gateway: gateway, client: api.client, initialLocation: '/');

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  group('a 401 from an API call signs the client out', () {

    Future<(FakeAuthApi, LocalAuthGateway)> signedIn(WidgetTester tester, FakeWire wire) async {
      SharedPreferences.setMockInitialValues({
        LocalAuthGateway.tokenKey: 'stored-token',
        LocalAuthGateway.expiresAtKey:
            DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
      });
      final api = FakeAuthApi(wire: wire);
      final gateway = await LocalAuthGateway.load(client: api.client);
      await pumpApp(
        tester,
        gateway: gateway,
        client: SignOutOnUnauthorized(api.client, gateway),
        initialLocation: Routes.approvals,
      );
      return (api, gateway);
    }

    testWidgets('and is not retried', (tester) async {
      final (api, _) = await signedIn(tester, FakeWire(queueStatus: 401));

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        api.requests.where((r) => r == 'GET /api/people/accounts/pending'),
        hasLength(1),
      );
    });

    testWidgets('but a 403 does not', (tester) async {
      await signedIn(tester, FakeWire(queueStatus: 403));

      expect(find.byType(SignInScreen), findsNothing);
    });
  });
}
