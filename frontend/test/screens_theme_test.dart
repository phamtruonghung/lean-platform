import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/theme.dart';

void main() {
  testWidgets('SignInScreen sits on the canvas background and keeps its copy',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const SignInScreen()),
    );

    final context = tester.element(find.byType(Scaffold));
    // Neither screen sets its own Scaffold background, so the effective
    // colour is whatever the theme resolves it to.
    expect(Theme.of(context).scaffoldBackgroundColor, AppColors.canvas);

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('AwaitingApprovalScreen keeps its heading and the flattened card treatment',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const AwaitingApprovalScreen(email: 'a@b.c'),
      ),
    );

    expect(find.text('Awaiting approval'), findsOneWidget);

    final context = tester.element(find.byType(AwaitingApprovalScreen));
    final cardTheme = Theme.of(context).cardTheme;
    expect(cardTheme.elevation, 0);
    final shape = cardTheme.shape as RoundedRectangleBorder;
    expect(shape.side.color, AppColors.edge);
  });

  testWidgets('HomeScreen renders the welcome and account-summary text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const HomeScreen(
          account: AccountActive(email: 'a@b.c', displayName: 'A B', role: 'administrator'),
        ),
      ),
    );

    expect(find.text('Welcome, A B'), findsOneWidget);
    expect(find.text('a@b.c · administrator'), findsOneWidget);
  });
}
