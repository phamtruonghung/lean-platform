/// Resetting an Account's password, and changing your own (issue #270), with
/// the wire faked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/account_password_dialog.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/platform/change_password_dialog.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart' show FakeAuthGateway, FakeWire, accountJson, pumpApp, tapIn;

Future<FakeAuthGateway> _open(WidgetTester tester, FakeWire wire) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  final gateway = FakeAuthGateway(accessToken: 'a-token');
  await pumpApp(tester, gateway: gateway, client: wire.client, initialLocation: Routes.accounts);
  return gateway;
}

FakeWire _wire() => FakeWire(accounts: [
      accountJson('1', 'me@b.c', role: 'admin'),
      accountJson('7', 'other@b.c'),
    ]);

void main() {
  group('an administrator resets another Account\'s password', () {
    testWidgets('the administrator\'s own row offers no reset', (tester) async {
      await _open(tester, _wire());
      expect(find.byKey(AccountsScreen.resetPasswordKey('7')), findsOneWidget);
      expect(find.byKey(AccountsScreen.resetPasswordKey('1')), findsNothing);
    });

    testWidgets('cancel sends nothing', (tester) async {
      final wire = _wire();
      await _open(tester, wire);
      await tapIn(tester, find.byKey(AccountsScreen.resetPasswordKey('7')));
      await tester.enterText(find.byKey(AccountPasswordDialog.passwordFieldKey), 'new-secret-1');
      await tapIn(tester, find.byKey(AccountPasswordDialog.cancelKey));

      expect(find.byKey(AccountPasswordDialog.submitKey), findsNothing);
      expect(wire.passwordResets, isEmpty);
    });

    testWidgets('confirm sends one POST with the typed password and closes', (tester) async {
      final wire = _wire();
      await _open(tester, wire);
      await tapIn(tester, find.byKey(AccountsScreen.resetPasswordKey('7')));
      await tester.enterText(find.byKey(AccountPasswordDialog.passwordFieldKey), 'new-secret-1');
      await tapIn(tester, find.byKey(AccountPasswordDialog.submitKey));

      expect(wire.passwordResets, hasLength(1));
      expect(wire.passwordResets.single.$1, '7');
      expect(wire.passwordResets.single.$2, {'password': 'new-secret-1'});
      expect(find.byKey(AccountPasswordDialog.submitKey), findsNothing);
      expect(find.byKey(AccountsScreen.noticeKey), findsOneWidget);
    });

    testWidgets('a refusal shows the server\'s message inside the dialog', (tester) async {
      final wire = _wire()
        ..resetPasswordStatus = 400
        ..resetPasswordMessage = 'Password must be at least 8 characters.';
      await _open(tester, wire);
      await tapIn(tester, find.byKey(AccountsScreen.resetPasswordKey('7')));
      await tester.enterText(find.byKey(AccountPasswordDialog.passwordFieldKey), 'long-enough');
      await tapIn(tester, find.byKey(AccountPasswordDialog.submitKey));

      expect(wire.passwordResets, hasLength(1));
      expect(find.byKey(AccountPasswordDialog.submitKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AccountPasswordDialog.failureKey),
          matching: find.text('Password must be at least 8 characters.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a password under 8 characters is caught before anything is sent', (tester) async {
      final wire = _wire();
      await _open(tester, wire);
      await tapIn(tester, find.byKey(AccountsScreen.resetPasswordKey('7')));
      await tester.enterText(find.byKey(AccountPasswordDialog.passwordFieldKey), 'short');
      await tapIn(tester, find.byKey(AccountPasswordDialog.submitKey));

      expect(wire.passwordResets, isEmpty);
      expect(find.byKey(AccountPasswordDialog.failureKey), findsOneWidget);
    });
  });

  group('a signed-in person changes their own password', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tapIn(tester, find.byKey(PlatformShell.accountMenuKey));
      await tapIn(tester, find.byKey(PlatformShell.changePasswordKey));
    }

    Future<void> fill(WidgetTester tester, String current, String next) async {
      await tester.enterText(find.byKey(ChangePasswordDialog.currentFieldKey), current);
      await tester.enterText(find.byKey(ChangePasswordDialog.newFieldKey), next);
    }

    testWidgets('cancel sends nothing', (tester) async {
      final wire = _wire();
      await _open(tester, wire);
      await openDialog(tester);
      await fill(tester, 'old-secret', 'new-secret-1');
      await tapIn(tester, find.byKey(ChangePasswordDialog.cancelKey));

      expect(find.byKey(ChangePasswordDialog.submitKey), findsNothing);
      expect(wire.passwordChanges, isEmpty);
    });

    testWidgets('a wrong current password shows the message and stays signed in', (tester) async {
      final wire = _wire()..changePasswordStatus = 400;
      final gateway = await _open(tester, wire);
      await openDialog(tester);
      await fill(tester, 'wrong-secret', 'new-secret-1');
      await tapIn(tester, find.byKey(ChangePasswordDialog.submitKey));

      expect(wire.passwordChanges, hasLength(1));
      expect(
        find.descendant(
          of: find.byKey(ChangePasswordDialog.failureKey),
          matching: find.text('Current password is not correct.'),
        ),
        findsOneWidget,
      );
      expect(gateway.currentAccessToken, 'a-token');
      expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    });

    testWidgets('success sends both fields, closes and confirms', (tester) async {
      final wire = _wire();
      final gateway = await _open(tester, wire);
      await openDialog(tester);
      await fill(tester, 'old-secret', 'new-secret-1');
      await tapIn(tester, find.byKey(ChangePasswordDialog.submitKey));

      expect(wire.passwordChanges, [
        {'currentPassword': 'old-secret', 'newPassword': 'new-secret-1'},
      ]);
      expect(find.byKey(ChangePasswordDialog.submitKey), findsNothing);
      expect(find.text(ChangePasswordDialog.changedMessage), findsOneWidget);
      expect(gateway.currentAccessToken, 'a-token');
    });
  });
}
