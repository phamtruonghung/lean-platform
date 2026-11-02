/// What the browser tab says above each address (issue #399).
///
/// Driven through `PlatformApp`, because the title is the router's and the
/// palette's — not a Screen's — and the seam a test can observe is the one the
/// browser itself would see: [DocumentChrome]. `RecordingDocumentChrome` stands
/// in for the document (there is none on the Dart VM), so every assertion here
/// is on the exact string the browser would have been told, in the order it was
/// told it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/theme.dart';

import 'harness.dart' show FakeAuthGateway, FakeWire, RecordingDocumentChrome, pumpApp;

/// Pumps the app at [location] as an admitted administrator, with a document
/// recorder standing in for the browser's own, and returns that recorder.
Future<RecordingDocumentChrome> _open(
  WidgetTester tester, {
  String? location,
  FakeAuthGateway? gateway,
}) async {
  final chrome = RecordingDocumentChrome();
  await pumpApp(
    tester,
    gateway: gateway ?? FakeAuthGateway(accessToken: 'a-token'),
    client: FakeWire().client,
    documentChrome: chrome,
    initialLocation: location,
  );
  return chrome;
}

/// The router, reached through a Screen — the idiom `locationOf` already uses.
/// Captured before navigating away, because the Screen it was read off is then
/// gone (a detail page replaces the register).
GoRouter _routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(WorkOrdersScreen).first));

void main() {
  group('the tab is titled by the address', () {
    testWidgets('a Destination reads its Screen\'s own heading, then Platform', (tester) async {
      final chrome = await _open(tester, location: Routes.workOrders);

      expect(chrome.title, 'Work orders · Platform');
    });

    testWidgets('a record beneath it is titled in its own right', (tester) async {
      final chrome = await _open(tester, location: '${Routes.workOrders}/42');

      expect(chrome.title, 'Work order · Platform');
    });

    testWidgets('the front door is titled before anyone signs in', (tester) async {
      final chrome = await _open(tester, location: Routes.signIn, gateway: FakeAuthGateway());

      expect(chrome.title, 'Sign in · Platform');
    });

    testWidgets('an address nothing answers to is the app\'s own name', (tester) async {
      final chrome = await _open(tester, location: '/no-such-address');

      expect(chrome.title, 'Platform');
    });
  });

  group('moving between addresses', () {
    testWidgets('the title follows the address forward, and back again on a pop', (tester) async {
      final chrome = await _open(tester, location: Routes.workOrders);
      final router = _routerOf(tester);
      expect(chrome.title, 'Work orders · Platform');

      router.go('${Routes.workOrders}/42');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/work-orders/42');
      expect(chrome.title, 'Work order · Platform');

      router.pop();
      await tester.pumpAndSettle();
      // Restored to the Screen that was underneath: the tab is the address's
      // name, so nothing has to remember what it used to be.
      expect(router.routerDelegate.currentConfiguration.uri.toString(), Routes.workOrders);
      expect(chrome.title, 'Work orders · Platform');
    });

    testWidgets('a dialog keeps the title of the Screen it was opened over', (tester) async {
      final chrome = await _open(tester, location: Routes.workOrders);
      final router = _routerOf(tester);
      expect(chrome.title, 'Work orders · Platform');

      router.go('${Routes.workOrders}/new');
      // Frames, not `pumpAndSettle`: a dialog whose own data is still arriving
      // shows a progress indicator, and that animates forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // A transition dialog is an address of its own (ADR-0021) and has no row
      // in the title table: blanking the tab here would be a worse title than
      // the Screen's own, so the enclosing Screen answers.
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/work-orders/new');
      expect(chrome.title, 'Work orders · Platform');

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routerDelegate.currentConfiguration.uri.toString(), Routes.workOrders);
      expect(chrome.title, 'Work orders · Platform');
    });
  });

  group('the browser\'s chrome colour follows the palette', () {
    testWidgets('the light palette is the canvas it declares', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final chrome = await _open(tester, location: Routes.workOrders);

      expect(chrome.themeColor, AppPalette.light.canvas);
    });

    testWidgets('a browser that asks for dark gets the dark palette\'s canvas', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final chrome = await _open(tester, location: Routes.workOrders);
      expect(chrome.themeColor, AppPalette.light.canvas);

      // The mode is `system` until somebody chooses, so this is the browser
      // changing its mind under an open app — the same path a stored choice or
      // the palette toggle takes through the theme below `MaterialApp`.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      expect(chrome.themeColor, AppPalette.dark.canvas);
    });
  });

  group('documentTitle names a declared path, not an address', () {
    test('a Screen\'s own row is used as it stands', () {
      expect(documentTitle('/'), 'Welcome · Platform');
      expect(documentTitle('/work-orders'), 'Work orders · Platform');
      expect(documentTitle('/work-orders/:id'), 'Work order · Platform');
      expect(documentTitle('/kpi/:kpiId/targets'), 'KPI targets · Platform');
    });

    test('a path with no row falls back to its enclosing Screen, however deep', () {
      expect(documentTitle('/work-orders/new'), 'Work orders · Platform');
      expect(documentTitle('/leave-requests/:id/approve'), 'Leave requests · Platform');
      expect(
        documentTitle('/actions/capas/:id/causes/:category/:causeId/verdict'),
        'CAPA · Platform',
      );
      expect(documentTitle('/non-conformances/:id/quantity'), 'Non-conformance · Platform');
    });

    test('a path nothing matches, or nothing encloses, is the bare app name', () {
      expect(documentTitle(''), 'Platform');
      expect(documentTitle('/not-a-screen'), 'Platform');
    });
  });
}
