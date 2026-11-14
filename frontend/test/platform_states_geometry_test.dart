/// The platform's five "something is wrong" Screens, measured (issue #396's
/// design pass): not-found, access-denied, session-error, change-password and
/// awaiting-approval.
///
/// Each of them is a centred block by design — `page_alignment_test.dart`
/// records why they are the one kind of page that is not a one-left-edge
/// register — so what a widget test can pin is the *composition*: one bounded
/// card at 460, the title and the sentence in the shared `AppPageHeader`
/// rhythm, one row of actions at the 44px floor, and the same at twice the
/// text. Plus the one thing the ticket asks for and a mock would not prove:
/// the action that gets the reader out really navigates.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/l10n/app_localizations.dart';
import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/change_password_screen.dart';
import 'package:lean_platform/platform/not_found_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/session_error_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_dialog.dart' show AppDialog;
import 'package:lean_platform/widgets/app_page_header.dart';

import 'harness.dart';

/// The bounded card every one of the five states is drawn in. Its width is the
/// bound less the block's own `Spacing.xl` padding, and it is the *same* number
/// at every window — a card that divided whatever it was given would grow at
/// 1280, which is the defect this pins.
Finder _card() => find.ancestor(of: find.byType(AppPageHeader), matching: find.byType(Card)).first;

/// The card is 460 less the block's own `Spacing.xl` either side, at both
/// widths: `ConstrainedBox` around the block, never a card that divides
/// whatever it is given.
void _expectBoundedCard(WidgetTester tester, {String reason = '', double bound = 460}) {
  final width = tester.getSize(_card()).width;
  expect(width, closeTo(bound - 2 * Spacing.xl, 1.0),
      reason: 'the card is the bound less its own padding: $reason');
}

/// The title and the sentence are the shared header's, and they sit at the
/// card's own `Spacing.xl` gutter.
void _expectHeaderRhythm(WidgetTester tester, {String reason = ''}) {
  final card = tester.getTopLeft(_card());
  final title = tester.getTopLeft(find.byKey(AppPageHeader.titleKey));
  expect(title.dx, closeTo(card.dx + Spacing.xl, 1.0),
      reason: 'the title starts at the card\'s own padding: $reason');
  expect(find.byKey(AppPageHeader.ruleKey), findsOneWidget,
      reason: 'the header keeps its hairline: $reason');
}

/// Every control on the state is a tap target.
void _expectActionsAreTapTargets(WidgetTester tester, {String reason = ''}) {
  final buttons = find.byWidgetPredicate((widget) => widget is ButtonStyleButton);
  expect(buttons, findsWidgets, reason: 'the state offers a way out: $reason');
  for (final box in tester.renderObjectList<RenderBox>(buttons)) {
    expect(box.size.height, greaterThanOrEqualTo(AppTouchTarget.min),
        reason: 'every action is a 44px target: $reason');
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1600);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(),
    home: screen,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('not found', () {
    testWidgets('at 700, 900 and 1280 it is one 460 card in the header rhythm', (tester) async {
      for (final width in const [700.0, 900.0, 1280.0]) {
        await _pumpScreen(tester, const NotFoundScreen(location: '/no/such/page'), width: width);
        _expectBoundedCard(tester, reason: 'window $width');
        _expectHeaderRhythm(tester, reason: 'window $width');
        _expectActionsAreTapTargets(tester, reason: 'window $width');
        expect(find.text('There is nothing at /no/such/page.'), findsOneWidget);
        expect(find.byKey(NotFoundScreen.homeKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('at twice the text the card holds and keeps its way out', (tester) async {
      await _pumpScreen(tester, const NotFoundScreen(location: '/no/such/page'),
          width: 1280, textScale: 2);
      expect(tester.takeException(), isNull);
      _expectBoundedCard(tester, reason: '200% text');
      _expectHeaderRhythm(tester, reason: '200% text');
      _expectActionsAreTapTargets(tester, reason: '200% text');
      expect(find.byKey(NotFoundScreen.homeKey), findsOneWidget);
    });

    testWidgets('Back to Home really goes Home', (tester) async {
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: FakeWire(
          role: Roles.admin,
          sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
          orgUnits: {
            null: [orgUnitJson('10', 'Line 1')],
          },
        ).client,
        initialLocation: '/no/such/page',
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotFoundScreen), findsOneWidget);

      await tester.tap(find.byKey(NotFoundScreen.homeKey));
      await tester.pumpAndSettle();
      expect(find.byType(NotFoundScreen), findsNothing, reason: 'the way out leads somewhere');
    });
  });

  group('access denied', () {
    Future<void> pumpDenied(WidgetTester tester,
        {required double width, double textScale = 1}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 1600);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: FakeWire(
          role: Roles.operator,
          sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
          orgUnits: {
            null: [orgUnitJson('10', 'Line 1')],
          },
        ).client,
        initialLocation: '/approvals',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('at 700, 900 and 1280 it is one 460 card in the header rhythm', (tester) async {
      for (final width in const [700.0, 900.0, 1280.0]) {
        await pumpDenied(tester, width: width);
        expect(find.byType(AccessDeniedScreen), findsOneWidget, reason: 'window $width');
        // This route renders inside the Shell, so a 700px window hands the
        // state 440px and the block is bounded by that rather than by 460 —
        // and still does not grow when the window does.
        _expectBoundedCard(tester,
            reason: 'window $width', bound: width - 260 < 460 ? width - 260 : 460);
        _expectHeaderRhythm(tester, reason: 'window $width');
        _expectActionsAreTapTargets(tester, reason: 'window $width');
        expect(find.byKey(AccessDeniedScreen.homeKey), findsOneWidget);
      }
    });

    testWidgets('at twice the text the card holds and keeps its way out', (tester) async {
      await pumpDenied(tester, width: 1280, textScale: 2);
      expect(tester.takeException(), isNull);
      _expectBoundedCard(tester, reason: '200% text');
      _expectHeaderRhythm(tester, reason: '200% text');
      _expectActionsAreTapTargets(tester, reason: '200% text');
      expect(find.byKey(AccessDeniedScreen.homeKey), findsOneWidget);
    });
  });

  group('session error', () {
    testWidgets('is one 460 card with both actions at the floor', (tester) async {
      for (final width in const [700.0, 900.0, 1280.0]) {
        await _pumpScreen(
          tester,
          const SessionErrorScreen(message: 'the request timed out'),
          width: width,
        );
        _expectBoundedCard(tester, reason: 'window $width');
        _expectHeaderRhythm(tester, reason: 'window $width');
        _expectActionsAreTapTargets(tester, reason: 'window $width');
        expect(find.textContaining('Could not check this Account\'s status'), findsOneWidget);
        expect(find.byKey(SessionErrorScreen.retryKey), findsOneWidget);
        expect(find.byKey(SessionErrorScreen.signOutKey), findsOneWidget);
      }
    });

    testWidgets('at twice the text it holds and still offers both ways out', (tester) async {
      await _pumpScreen(
        tester,
        const SessionErrorScreen(message: 'the request timed out'),
        width: 1280,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      _expectBoundedCard(tester, reason: '200% text');
      _expectHeaderRhythm(tester, reason: '200% text');
      _expectActionsAreTapTargets(tester, reason: '200% text');
      expect(find.byKey(SessionErrorScreen.retryKey), findsOneWidget);
      expect(find.byKey(SessionErrorScreen.signOutKey), findsOneWidget);
    });
  });

  group('awaiting approval', () {
    testWidgets('at 700, 900 and 1280 it is one 460 card, and it survives twice the text',
        (tester) async {
      for (final width in const [700.0, 900.0, 1280.0]) {
        await _pumpScreen(
          tester,
          const AwaitingApprovalScreen(email: 'a@b.c'),
          width: width,
        );
        _expectBoundedCard(tester, reason: 'window $width');
        _expectHeaderRhythm(tester, reason: 'window $width');
        _expectActionsAreTapTargets(tester, reason: 'window $width');
        expect(find.byKey(AwaitingApprovalScreen.checkAgainKey), findsOneWidget);
      }

      await _pumpScreen(
        tester,
        const AwaitingApprovalScreen(email: 'a@b.c'),
        width: 1280,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      _expectBoundedCard(tester, reason: '200% text');
      _expectHeaderRhythm(tester, reason: '200% text');
      _expectActionsAreTapTargets(tester, reason: '200% text');
      expect(find.byKey(AwaitingApprovalScreen.checkAgainKey), findsOneWidget);
    });
  });

  group('change password', () {
    testWidgets('is one 460 card whose fields and actions survive both widths',
        (tester) async {
      Map<String, dynamic> body() => {
            'status': 'active',
            'account': {
              'id': '1',
              'email': 'a@b.c',
              'displayName': 'A B',
              'role': 'administrator',
              'mustChangePassword': true,
            },
          };

      for (final width in const [700.0, 900.0, 1280.0]) {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 1600);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await pumpApp(
          tester,
          gateway: FakeAuthGateway(accessToken: 'a-token'),
          client: meClient(body),
          initialLocation: '/',
        );
        await tester.pumpAndSettle();

        expect(find.byType(ChangePasswordScreen), findsOneWidget, reason: 'window $width');
        _expectBoundedCard(tester, reason: 'window $width');
        _expectHeaderRhythm(tester, reason: 'window $width');
        expect(find.byKey(ChangePasswordScreen.currentFieldKey), findsOneWidget);
        expect(find.byKey(ChangePasswordScreen.newFieldKey), findsOneWidget);
        expect(find.byKey(ChangePasswordScreen.submitKey), findsOneWidget);
        expect(find.byKey(ChangePasswordScreen.signOutKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('at twice the text the fields and the way out stay inside the card',
        (tester) async {
      Map<String, dynamic> body() => {
            'status': 'active',
            'account': {
              'id': '1',
              'email': 'a@b.c',
              'displayName': 'A B',
              'role': 'administrator',
              'mustChangePassword': true,
            },
          };
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1600);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: meClient(body),
        initialLocation: '/',
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectBoundedCard(tester, reason: '200% text');
      _expectHeaderRhythm(tester, reason: '200% text');
      _expectActionsAreTapTargets(tester, reason: '200% text');

      // Measured at 200%: both fields and the submit control stay inside the
      // card's own box, so no field is clipped by a hand-typed width.
      final card = tester.getRect(find.byKey(ChangePasswordScreen.cardKey));
      for (final field in [
        ChangePasswordScreen.currentFieldKey,
        ChangePasswordScreen.newFieldKey,
        ChangePasswordScreen.submitKey,
      ]) {
        final rect = tester.getRect(find.byKey(field));
        expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: 'inside the card');
        expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: 'inside the card');
      }
    });
  });

  test('the five states share one composition, not five hand-rolled ones', () {
    // A source-level claim, so it is a test and not a review note: every one of
    // the five draws the shared page header, and none of them sets its own
    // hand-typed colour.
    final sources = <String>[
      'lib/platform/not_found_screen.dart',
      'lib/platform/access_denied_screen.dart',
      'lib/platform/session_error_screen.dart',
      'lib/platform/change_password_screen.dart',
      'lib/auth/awaiting_approval_screen.dart',
    ];
    for (final path in sources) {
      final source = File(path).readAsStringSync();
      expect(source.contains('AppPageHeader('), isTrue, reason: '$path keeps the header rhythm');
      expect(source.contains('maxWidth: 460'), isTrue, reason: '$path keeps the 460 bound');
      expect(RegExp(r'Color\(0x').hasMatch(source), isFalse, reason: '$path uses tokens');
      // A bare `Colors.*`, not `AppColors.of` — the palette extension is the
      // token layer, the Material constant is the literal this forbids.
      expect(RegExp(r'(?<!App)Colors\.').hasMatch(source), isFalse, reason: '$path uses tokens');
    }
    // The shared dialog shell is not part of any of them, and the sanity check
    // that this file still imports what it names.
    expect(AppDialog.actionKey('x').value, 'app-dialog-action-x');
  });
}
