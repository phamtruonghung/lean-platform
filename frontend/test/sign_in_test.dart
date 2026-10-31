/// The sign-in Screen's two layouts (issue #375): an identity panel beside the
/// form at 900px and wider, and a compact brand header above it below that.
///
/// What these tests claim: which of the two renders at a given width, and
/// where the boundary is; that the copy, the three buttons' 44px touch targets,
/// the autofill hints, pasting, validation and the placement of a refusal
/// survive both layouts, in both palettes; and that 320px neither overflows nor
/// strands anything out of reach. They mount the Screen alone over a recording
/// `AuthGateway` rather than the whole app, because the Screen is the unit and
/// its layout does not depend on the router. Not claimed: that the real
/// gateways sign anyone in — `local_auth_test.dart` proves that.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/theme.dart';

/// Records what the Screen asked of it, and refuses on demand.
class RecordingAuthGateway implements AuthGateway {
  final List<String> calls = [];
  AuthRefusal? refusal;

  Future<void> _answer(String call) async {
    calls.add(call);
    if (refusal != null) throw refusal!;
  }

  @override
  String? get currentAccessToken => null;

  @override
  Stream<String?> get accessTokenChanges => const Stream.empty();

  @override
  Future<void> signInWithPassword({required String email, required String password}) =>
      _answer('signIn $email');

  @override
  Future<void> signUp({required String email, required String password}) => _answer('signUp $email');

  @override
  Future<void> signInWithGoogle() => _answer('google');

  @override
  Future<void> signOut() async {}
}

Future<RecordingAuthGateway> pumpSignIn(
  WidgetTester tester,
  Size size, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final gateway = RecordingAuthGateway();
  await tester.pumpWidget(
    RepositoryProvider<AuthGateway>.value(
      value: gateway,
      child: MaterialApp(theme: buildAppTheme(brightness), home: const SignInScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

const _contextWords = ['Work orders', 'KPI Review', 'Shift handover', 'Actions'];
const _sentence = 'One application for running several manufacturing plants.';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('at 1200x900 the identity panel carries the wordmark, the sentence and the contents',
      (tester) async {
    await pumpSignIn(tester, const Size(1200, 900));

    final panel = find.byKey(SignInScreen.identityPanelKey);
    expect(panel, findsOneWidget);
    expect(find.byKey(SignInScreen.compactBrandKey), findsNothing);
    expect(find.descendant(of: panel, matching: find.text('Platform')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byIcon(Icons.dashboard_outlined)),
        findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text(_sentence)), findsOneWidget);
    for (final word in _contextWords) {
      expect(find.descendant(of: panel, matching: find.text(word)), findsOneWidget, reason: word);
    }
    expect(find.byKey(SignInScreen.formCardKey), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('at 375x812 the panel is gone, the compact brand is there and the form remains',
      (tester) async {
    await pumpSignIn(tester, const Size(375, 812));

    expect(find.byKey(SignInScreen.identityPanelKey), findsNothing);
    expect(find.byKey(SignInScreen.compactBrandKey), findsOneWidget);
    expect(find.byKey(SignInScreen.formCardKey), findsOneWidget);
    expect(_field('Email'), findsOneWidget);
    expect(_field('Password'), findsOneWidget);
  });

  testWidgets('899 is compact and 900 is two panels', (tester) async {
    await pumpSignIn(tester, const Size(899, 800));
    expect(find.byKey(SignInScreen.identityPanelKey), findsNothing);
    expect(find.byKey(SignInScreen.compactBrandKey), findsOneWidget);

    await pumpSignIn(tester, const Size(900, 800));
    expect(find.byKey(SignInScreen.identityPanelKey), findsOneWidget);
    expect(find.byKey(SignInScreen.compactBrandKey), findsNothing);
  });

  testWidgets('at 320x568 nothing overflows, the form fits the width and all of it can be reached',
      (tester) async {
    await pumpSignIn(tester, const Size(320, 568));

    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byKey(SignInScreen.formCardKey));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(320));
    // A short window scrolls: the last control can be brought into view.
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final google = tester.getRect(find.text('Continue with Google'));
    expect(google.bottom, lessThanOrEqualTo(568));
    expect(google.top, greaterThanOrEqualTo(0));
    await tester.ensureVisible(find.byKey(SignInScreen.compactBrandKey));
    await tester.pump();
    expect(tester.getRect(find.byKey(SignInScreen.compactBrandKey)).top, greaterThanOrEqualTo(0));
  });

  testWidgets('a short two-panel window scrolls the identity panel rather than overflowing',
      (tester) async {
    await pumpSignIn(tester, const Size(1000, 200));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in const [Size(1200, 900), Size(375, 812)]) {
      testWidgets('the copy is kept at ${size.width.round()}px in ${brightness.name}',
          (tester) async {
        await pumpSignIn(tester, size, brightness: brightness);

        expect(find.text('Sign in'), findsNWidgets(2));
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
        expect(find.text('Create an account'), findsOneWidget);
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the Sign in heading is a semantic header', (tester) async {
    await pumpSignIn(tester, const Size(375, 812));
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Sign in').first),
      matchesSemantics(label: 'Sign in', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('the three buttons are at least 44px tall at 375px', (tester) async {
    await pumpSignIn(tester, const Size(375, 812));

    for (final button in [
      find.widgetWithText(FilledButton, 'Sign in'),
      find.widgetWithText(OutlinedButton, 'Create an account'),
      find.widgetWithText(OutlinedButton, 'Continue with Google'),
    ]) {
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a button\'s own minimumSize leaves the theme\'s focus ring in force', (tester) async {
    await pumpSignIn(tester, const Size(375, 812));

    final context = tester.element(find.byType(Scaffold));
    final themed = Theme.of(context).outlinedButtonTheme.style!;
    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Create an account'));
    // The local style only sets the size; the theme's side and overlay are
    // not shadowed by it.
    expect(button.style!.side, isNull);
    expect(button.style!.overlayColor, isNull);
    final focused = <WidgetState>{WidgetState.focused};
    expect(themed.side!.resolve(focused)!.width, 2);
    expect(themed.side!.resolve(focused)!.color, AppColors.of(context).focusRing);
  });

  testWidgets('autofill hints are kept on both fields', (tester) async {
    await pumpSignIn(tester, const Size(375, 812));

    EditableText editable(String label) =>
        tester.widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText)));
    expect(editable('Email').autofillHints, [AutofillHints.email]);
    expect(editable('Password').autofillHints, [AutofillHints.password]);
  });

  testWidgets('pasting into either field is not blocked', (tester) async {
    await pumpSignIn(tester, const Size(375, 812));
    var clipboard = 'pasted@b.c';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboard};
      // `pasteEnabled` asks the clipboard whether it holds anything.
      if (call.method == 'Clipboard.hasStrings') return <String, dynamic>{'value': true};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    for (final (label, text) in [('Email', 'pasted@b.c'), ('Password', 'pasted-secret')]) {
      clipboard = text;
      await tester.tap(_field(label));
      await tester.pump();
      final state = tester.state<EditableTextState>(
        find.descendant(of: _field(label), matching: find.byType(EditableText)),
      );
      expect(state.widget.readOnly, isFalse, reason: label);
      await state.clipboardStatus.update();
      await tester.pump();
      expect(state.pasteEnabled, isTrue, reason: label);
      await state.pasteText(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(state.widget.controller.text, text, reason: label);
    }
  });

  for (final size in const [Size(1200, 900), Size(375, 812)]) {
    testWidgets('validation refuses before the gateway is called, at ${size.width.round()}px',
        (tester) async {
      final gateway = await pumpSignIn(tester, size);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create an account'));
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsWidgets);
      expect(find.text('At least 6 characters'), findsWidgets);
      expect(gateway.calls, isEmpty);
    });

    testWidgets('a refusal renders under the password field, at ${size.width.round()}px',
        (tester) async {
      final gateway = await pumpSignIn(tester, size);
      gateway.refusal = const AuthRefusal('Email or password is not recognised.');

      await tester.enterText(_field('Email'), 'a@b.c');
      await tester.enterText(_field('Password'), 'secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(gateway.calls, ['signIn a@b.c']);
      final message = find.text('Email or password is not recognised.');
      expect(message, findsOneWidget);
      expect(tester.getTopLeft(message).dy, greaterThan(tester.getBottomLeft(_field('Password')).dy));
    });
  }
}
