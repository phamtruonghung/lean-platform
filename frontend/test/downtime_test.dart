/// Breakdowns and Downtime (issue #73), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs, `MockClient`
/// at the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that a supervisor is offered
/// the Downtime Destination and not an operator; that reporting a Breakdown
/// sends exactly one `POST /api/maintenance/downtime` carrying the chosen
/// Asset; that a duplicate report shows the server's own actionable message and
/// sends no second request; that closing a row sends the close route and the
/// row stops being open; that classifying sends the chosen reason and a
/// `requiresComment` reason blocks submission without a description; and that
/// the list's loading, empty and failure states render. Not that the server
/// enforces scope, derives the Org Unit, or owns the duration — those are
/// proved on the backend, and neither substitutes for the other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/breakdown_report_dialog.dart';
import 'package:lean_platform/maintenance/downtime_classify_dialog.dart';
import 'package:lean_platform/maintenance/downtime_close_dialog.dart';
import 'package:lean_platform/maintenance/downtime_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/empty_state.dart';
import 'package:lean_platform/widgets/failure_state.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';
import 'harness.dart';

FakeWire wireWith({
  String role = Roles.supervisor,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? assets,
  Map<String, List<Map<String, dynamic>>>? downtime,
  List<Map<String, dynamic>>? downtimeReasons,
  int downtimeStatus = 200,
  int downtimeReasonsStatus = 200,
  int createDowntimeStatus = 201,
  String createDowntimeMessage = 'That Breakdown could not be reported.',
  int closeDowntimeStatus = 200,
  int classifyDowntimeStatus = 200,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: assets ?? {'1': []},
      downtime: downtime,
      downtimeReasons: downtimeReasons,
      downtimeStatus: downtimeStatus,
      downtimeReasonsStatus: downtimeReasonsStatus,
      createDowntimeStatus: createDowntimeStatus,
      createDowntimeMessage: createDowntimeMessage,
      closeDowntimeStatus: closeDowntimeStatus,
      classifyDowntimeStatus: classifyDowntimeStatus,
    );

/// A supervisor holding a write Grant at Org Unit 10 — the caller every action
/// test uses.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

void main() {
  testWidgets('a supervisor is offered the Downtime Destination, and an operator is not',
      (tester) async {
    final wire = wireWith(role: Roles.supervisor, orgUnitScope: _writeGrant, downtime: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byKey(const ValueKey('nav-item-Downtime')), findsOneWidget);
    expect(find.byType(DowntimeScreen), findsOneWidget);
  });

  testWidgets('a capped Downtime list says so on screen', (tester) async {
    final wire = wireWith(role: Roles.supervisor, orgUnitScope: _writeGrant, downtime: {'1': []});
    wire.downtimeTruncated = true;
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byKey(DowntimeScreen.truncatedKey), findsOneWidget);
  });

  testWidgets('an operator who types the Downtime address is refused it', (tester) async {
    final wire = wireWith(role: Roles.operator, downtime: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(DowntimeScreen), findsNothing);
    expect(wire.downtimeSites, isEmpty);
  });

  testWidgets('reporting a breakdown sends exactly one POST with the chosen Asset',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      downtime: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    await tapIn(tester, find.byKey(DowntimeScreen.reportKey));
    await tester.pumpAndSettle();

    await pickSuggestion(
      tester,
      fieldKey: BreakdownReportDialog.assetKey,
      term: 'Press',
      suggestionKey: BreakdownReportDialog.assetSuggestionKey('7'),
    );
    await tapIn(tester, find.byKey(BreakdownReportDialog.submitKey));

    expect(wire.downtimePosts.length, 1);
    final sent = wire.downtimePosts.single;
    expect(sent['assetId'], '7');
    // The client sends neither the derived Org Unit nor a Work order number.
    expect(sent.containsKey('orgUnitId'), isFalse);
    expect(sent.containsKey('workOrderNo'), isFalse);

    expect(find.byType(BreakdownReportDialog), findsNothing);
    expect(find.byKey(DowntimeScreen.rowKey('900')), findsOneWidget);
  });

  testWidgets('a duplicate report shows the server message and sends no second request',
      (tester) async {
    const message =
        'Press 1 is already recorded as down since 2024-01-01T00:00:00.000Z. '
        'Close that stop before reporting another.';
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      downtime: {'1': []},
      createDowntimeStatus: 409,
      createDowntimeMessage: message,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    await tapIn(tester, find.byKey(DowntimeScreen.reportKey));
    await tester.pumpAndSettle();
    await pickSuggestion(
      tester,
      fieldKey: BreakdownReportDialog.assetKey,
      term: 'Press',
      suggestionKey: BreakdownReportDialog.assetSuggestionKey('7'),
    );
    await tapIn(tester, find.byKey(BreakdownReportDialog.submitKey));

    // The dialog stays open and the server's actionable sentence is shown.
    expect(find.byType(BreakdownReportDialog), findsOneWidget);
    expect(find.byKey(BreakdownReportDialog.failureKey), findsOneWidget);
    expect(find.textContaining('already recorded as down since'), findsOneWidget);
    expect(wire.downtimePosts.length, 1);

    // Dismissing and reopening does not send another in the background.
    await tapIn(tester, find.byKey(BreakdownReportDialog.cancelKey));
    expect(wire.downtimePosts.length, 1);
  });

  testWidgets('closing a row sends the close route and the row is no longer open',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtime: {
        '1': [downtimeJson('500', status: 'open')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byKey(DowntimeScreen.rowKey('500')), findsOneWidget);
    await tapIn(tester, find.byKey(DowntimeScreen.closeKey('500')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(DowntimeCloseDialog.submitKey));

    expect(wire.downtimeCloses.length, 1);
    final (id, body) = wire.downtimeCloses.single;
    expect(id, '500');
    // No end time chosen means the server records now(), so nothing is sent.
    expect(body.containsKey('endedAt'), isFalse);

    expect(find.byType(DowntimeCloseDialog), findsNothing);
    // The row stays visible but is no longer open: Close is gone, the status
    // the server sent is shown, and Classify is still offered.
    expect(find.byKey(DowntimeScreen.closeKey('500')), findsNothing);
    expect(find.text('Unclassified'), findsOneWidget);
    expect(find.byKey(DowntimeScreen.classifyKey('500')), findsOneWidget);
  });

  testWidgets('classifying sends the chosen reason, and requiresComment blocks an empty description',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtime: {
        '1': [
          downtimeJson('500'),
        ],
      },
      downtimeReasons: [
        downtimeReasonJson('3', 'ELEC', 'Electrical', requiresComment: true),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    await tapIn(tester, find.byKey(DowntimeScreen.classifyKey('500')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(DowntimeClassifyDialog.reasonKey));
    await tapIn(tester, find.text('Electrical').last);

    // A reason that requires a comment blocks submission until one is given.
    final submit = tester.widget<FilledButton>(find.byKey(DowntimeClassifyDialog.submitKey));
    expect(submit.onPressed, isNull);
    expect(wire.downtimeClassifications, isEmpty);

    await tester.enterText(
      find.byKey(DowntimeClassifyDialog.descriptionKey),
      'Contactor burnt out',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(DowntimeClassifyDialog.submitKey));

    expect(wire.downtimeClassifications.length, 1);
    final (id, body) = wire.downtimeClassifications.single;
    expect(id, '500');
    expect(body['downtimeReasonId'], '3');
    expect(body['description'], 'Contactor burnt out');
    expect(find.byType(DowntimeClassifyDialog), findsNothing);
  });

  testWidgets('the list shows placeholders while it loads', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtime: {'1': []},
    )..downtimeGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(DowntimeScreen.emptyKey), findsNothing);

    wire.downtimeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty list says plainly that nothing is down', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtime: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byKey(DowntimeScreen.emptyKey), findsOneWidget);
    expect(find.byKey(DowntimeScreen.failedKey), findsNothing);
    expect(find.byType(PlatformEmptyState), findsOneWidget);
    expect(find.byType(PlatformFailureState), findsNothing);
    expect(find.text('Nothing is down'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtimeStatus: 503,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    expect(find.byKey(DowntimeScreen.failedKey), findsOneWidget);
    expect(find.byKey(DowntimeScreen.emptyKey), findsNothing);
    expect(find.byType(PlatformFailureState), findsOneWidget);
    expect(find.byType(PlatformEmptyState), findsNothing);
    expect(find.text('The downtime events are unavailable.'), findsOneWidget);

    wire.downtimeStatus = 200;
    wire.downtime = {
      '1': [downtimeJson('500')],
    };
    await tapIn(tester, find.byKey(DowntimeScreen.retryKey));

    expect(find.byKey(DowntimeScreen.failedKey), findsNothing);
    expect(find.byType(PlatformFailureState), findsNothing);
    expect(find.byKey(DowntimeScreen.rowKey('500')), findsOneWidget);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets('the downtime list is narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      downtime: {
        '1': [
          downtimeJson('301'),
          downtimeJson('302', assetCode: 'CONV-2', assetName: 'Infeed conveyor'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(DowntimeScreen.rowKey('302')), findsOneWidget);
    expect(find.byKey(DowntimeScreen.rowKey('301')), findsOneWidget);
    expect(find.byKey(DowntimeScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(DowntimeScreen.filterFieldKey), 'conveyor');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(DowntimeScreen.rowKey('302')), findsOneWidget);
    expect(find.byKey(DowntimeScreen.rowKey('301')), findsNothing);
    expect(find.byKey(DowntimeScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(DowntimeScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(DowntimeScreen.rowKey('302')), findsOneWidget);
    expect(find.byKey(DowntimeScreen.rowKey('301')), findsOneWidget);
    expect(find.byKey(DowntimeScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });
  testWidgets('a failed reasons read blocks the classify dialog\'s submit', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      downtime: {
        '1': [downtimeJson('500')],
      },
      downtimeReasonsStatus: 500,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/downtime',
    );

    await tapIn(tester, find.byKey(DowntimeScreen.classifyKey('500')));
    await tester.pumpAndSettle();

    expect(find.byKey(DowntimeClassifyDialog.reasonsFailedKey), findsOneWidget);
    final submit = tester.widget<FilledButton>(find.byKey(DowntimeClassifyDialog.submitKey));
    expect(submit.onPressed, isNull);
  });

  group('the register at 1280 wide', () {
    void wide(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.reset);
    }

    Future<FakeWire> pumpRegister(
      WidgetTester tester, {
      Map<String, dynamic>? scope = _writeGrant,
      List<Map<String, dynamic>>? events,
    }) async {
      wide(tester);
      final wire = wireWith(
        role: Roles.supervisor,
        orgUnitScope: scope,
        downtime: {
          '1': events ??
              [
                downtimeJson('500', status: 'open', description: 'Belt snapped on line 2'),
              ],
        },
      );
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/downtime',
      );
      return wire;
    }

    testWidgets('draws a band and a table row, 52 tall', (tester) async {
      await pumpRegister(tester);
      expect(find.byType(AppTableHeader), findsOneWidget);
      expect(find.byType(AppTableRow), findsOneWidget);
      expect(
        tester.getSize(find.byKey(DowntimeScreen.rowKey('500'))).height,
        AppTouchTarget.min + 2 * Spacing.xs,
      );
    });

    testWidgets('an open unclassified row has Close inline and Classify only in the kebab',
        (tester) async {
      await pumpRegister(tester);
      expect(find.byKey(DowntimeScreen.closeKey('500')), findsOneWidget);
      expect(find.byKey(DowntimeScreen.classifyKey('500')), findsNothing);

      await tapIn(tester, find.byKey(DowntimeScreen.rowActionsKey('500')));
      expect(find.byKey(DowntimeScreen.classifyKey('500')), findsOneWidget);
    });

    testWidgets('Close and the kebab are enabled, disabled while a close is in flight, and enabled again',
        (tester) async {
      final wire = await pumpRegister(
        tester,
        events: [
          downtimeJson('500', status: 'open'),
          downtimeJson('501', status: 'open', assetId: '8', assetCode: 'CONV-2', assetName: 'Conveyor 2'),
        ],
      );
      wire.downtimeCloseGate = Completer<void>();

      VoidCallback? close(String id) =>
          tester.widget<FilledButton>(find.byKey(DowntimeScreen.closeKey(id))).onPressed;
      VoidCallback? kebab(String id) =>
          tester.widget<IconButton>(find.byKey(DowntimeScreen.rowActionsKey(id))).onPressed;

      expect(close('500'), isNotNull);
      expect(close('501'), isNotNull);
      expect(kebab('500'), isNotNull);
      expect(kebab('501'), isNotNull);

      await tapIn(tester, find.byKey(DowntimeScreen.closeKey('500')));
      await tester.pumpAndSettle();
      await tapIn(tester, find.byKey(DowntimeCloseDialog.submitKey));

      expect(close('501'), isNull);
      expect(kebab('501'), isNull);
      expect(close('500'), isNull);
      expect(kebab('500'), isNull);

      wire.downtimeCloseGate!.complete();
      await tester.pumpAndSettle();
      expect(close('501'), isNotNull);
      expect(kebab('501'), isNotNull);
    });

    testWidgets('a caller who cannot act has neither Close nor the kebab', (tester) async {
      await pumpRegister(tester, scope: const {'everywhere': false, 'grants': []});
      expect(find.byType(AppTableRow), findsOneWidget);
      expect(find.byKey(DowntimeScreen.closeKey('500')), findsNothing);
      expect(find.byKey(DowntimeScreen.rowActionsKey('500')), findsNothing);
    });

    testWidgets('a closed unclassified row has the kebab alone, and a closed classified row nothing',
        (tester) async {
      await pumpRegister(
        tester,
        events: [
          downtimeJson('500', status: 'unclassified'),
          downtimeJson('501',
              status: 'closed', downtimeReasonId: '3', downtimeReasonName: 'Electrical'),
        ],
      );
      expect(find.byKey(DowntimeScreen.closeKey('500')), findsNothing);
      expect(find.byKey(DowntimeScreen.rowActionsKey('500')), findsOneWidget);
      expect(find.byKey(DowntimeScreen.closeKey('501')), findsNothing);
      expect(find.byKey(DowntimeScreen.rowActionsKey('501')), findsNothing);
    });

    testWidgets('a description is behind the disclosure, and a row without one has no toggle',
        (tester) async {
      await pumpRegister(
        tester,
        events: [
          downtimeJson('500', description: 'Belt snapped on line 2'),
          downtimeJson('501', assetId: '8', assetCode: 'CONV-2', assetName: 'Conveyor 2'),
        ],
      );
      expect(find.text('Belt snapped on line 2'), findsNothing);
      expect(find.byKey(DowntimeScreen.detailsKey('501')), findsNothing);

      await tapIn(tester, find.byKey(DowntimeScreen.detailsKey('500')));
      expect(find.text('Belt snapped on line 2'), findsOneWidget);
    });
  });
}
