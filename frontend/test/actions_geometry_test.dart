/// The Action log, the CAPA list, their two detail Screens and the report,
/// measured (issue #396's design pass).
///
/// Each case pins something a reader can see and a stylesheet cannot: which
/// shape a register is at a given box, that a column label and its cells start
/// at the same x, that a detail page leads with its summary card under the
/// page head, and that at twice the text nothing clips and the register falls
/// back to cards rather than squeezing five columns into half a box.
///
/// **Why 700, 900 and 1280.** 700 is the narrowest box the register's cards are
/// drawn at; 900 is the box at which the register is still cards (`900 - 260` is
/// exactly the 700 breakpoint) and the width the brief names; 1280 is an
/// ordinary desktop. Every width is a *window*: the Shell's 260px rail comes off
/// first, so a register is handed `window - 260` and then loses this page's
/// `Spacing.lg` either side — which is why the table appears at 960 and above.
///
/// **Why a text scale of 2.** #379 and #381 were both a breakpoint that ignored
/// the reader's text size, so the same code read fine at 100% and squeezed at
/// 200%. A case at 2.0 that only renders would not catch that; the cases here
/// assert the *shape* (cards, not a table) and the measured geometry of what
/// moved.
///
/// The app is pumped through the real router with the wire faked, as
/// `safety_geometry_test.dart` does; nothing here reaches into a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/actions/actions_screen.dart';
import 'package:lean_platform/actions/capa_detail_screen.dart';
import 'package:lean_platform/actions/capa_report_screen.dart';
import 'package:lean_platform/actions/capas_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_page_header.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/failure_state.dart';

import 'harness.dart';

FakeWire _wire() => FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      actions: {
        '1': [
          actionJson(
            '501',
            'AC-HCM-2026-00001',
            'Guard keeps working loose',
            dueDate: '2026-09-01',
            isOverdue: true,
            daysOverdue: 14,
            ownerName: 'Ann Fitter',
            measureCount: 3,
            countermeasureCount: 1,
          ),
          actionJson(
            '502',
            'AC-HCM-2026-00002',
            'Pallet wrapper jams',
            actionType: 'containment',
            dueDate: '2026-10-01',
          ),
        ],
      },
      actionDetails: {
        '501': actionJson(
          '501',
          'AC-HCM-2026-00001',
          'Guard keeps working loose',
          dueDate: '2026-09-01',
          isOverdue: true,
          daysOverdue: 14,
          ownerName: 'Ann Fitter',
          description: 'The interlock guard works loose on every second shift.',
          phases: [phaseJson(1, 'plan')],
          openPhase: phaseJson(1, 'plan'),
        ),
      },
      capas: {
        '801': capaJson(
          '801',
          'CAPA-HCM-2026-00001',
          'Guard works loose on the press',
          problemStatement: 'The interlock guard works loose on every second shift.',
          dueDate: '2026-11-01',
        ),
        '802': capaJson(
          '802',
          'CAPA-HCM-2026-00002',
          'Wrapper jams on the pallet',
          status: 'actions',
          effectivenessCheckDueAt: '2026-10-01',
          effectivenessCheckOverdue: true,
        ),
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required String location,
  double textScale = 1,
  FakeWire? wire,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2200);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: (wire ?? _wire()).client,
    initialLocation: location,
  );
  await tester.pumpAndSettle();
}

/// A row that opens a record is a tap target, whatever it holds.
void _expectRowIsATapTarget(WidgetTester tester, Finder row) {
  expect(tester.getSize(row).height, greaterThanOrEqualTo(44.0),
      reason: 'a row that opens a record is a tap target');
}

void main() {
  setUpAll(loadAppFonts);

  group('the Action log is a register', () {
    testWidgets('at 1280 the log is a table, and a column label lines up with its cells',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions');

      expect(find.byKey(ActionsScreen.tableKey), findsOneWidget);
      expect(find.byKey(ActionsScreen.cardsKey), findsNothing);
      expect(find.byType(AppTableHeader), findsOneWidget);

      final row = find.byKey(ActionsScreen.rowKey('501'));
      expect(find.descendant(of: row, matching: find.byType(AppTableRow)), findsOneWidget);
      _expectRowIsATapTarget(tester, row);

      // One column spec spends twice (§4): the Owner label and the first
      // Owner cell start at the same x because both are built from it.
      final label = tester.getTopLeft(find.text('Owner'));
      final cell = tester.getTopLeft(find.byKey(ActionsScreen.ownerKey('501')));
      expect(cell.dx, closeTo(label.dx, 1.0),
          reason: 'the Owner label and its cells share one column spec');

      // The overdue reading is a sentence in the row, not arithmetic on a date.
      expect(find.text('Overdue by 14 days'), findsOneWidget);
      // A record nobody owns says so, rather than leaving the cell blank.
      expect(find.text('Nobody yet'), findsOneWidget);
    });

    testWidgets('at 700 and at 900 the log is a card per Action', (tester) async {
      for (final width in const [700.0, 900.0]) {
        await _pump(tester, width: width, location: '/actions');

        expect(find.byKey(ActionsScreen.cardsKey), findsOneWidget, reason: 'window $width');
        expect(find.byKey(ActionsScreen.tableKey), findsNothing, reason: 'window $width');
        expect(find.byType(AppTableHeader), findsNothing, reason: 'window $width');
        _expectRowIsATapTarget(tester, find.byKey(ActionsScreen.rowKey('501')));
      }
    });

    testWidgets('at twice the text the log is cards, and the readings stay inside one',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions', textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ActionsScreen.cardsKey), findsOneWidget,
          reason: 'five columns at twice the text need twice the box');
      expect(find.byKey(ActionsScreen.tableKey), findsNothing);
      expect(find.byKey(ActionsScreen.rowStatusKey('501')), findsOneWidget,
          reason: 'no state chip is lost at 200%');

      // Measured rather than present: at 200% the card is taller than a 1x row
      // (a 2x line is 28px against 14), and every reading the card carries
      // stays inside the card's own box.
      final card = tester.getRect(find.byKey(ActionsScreen.rowKey('501')));
      expect(card.height, greaterThan(88.0),
          reason: 'a card at twice the text is taller than the 1x row');
      for (final (name, part) in [
        ('state chip', ActionsScreen.rowStatusKey('501')),
        ('owner', ActionsScreen.ownerKey('501')),
        ('due', ActionsScreen.dueKey('501')),
      ]) {
        final rect = tester.getRect(find.byKey(part));
        expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: '$name inside the card');
        expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: '$name inside the card');
        expect(rect.bottom, lessThanOrEqualTo(card.bottom + 0.5), reason: '$name inside the card');
      }
    });

    testWidgets('the page head and the register share one left edge', (tester) async {
      await _pump(tester, width: 1280, location: '/actions');

      final title = tester.getTopLeft(find.byKey(AppPageHeader.titleKey));
      final card = tester.getTopLeft(
        find.descendant(of: find.byKey(ActionsScreen.tableKey), matching: find.byType(Card)).first,
      );
      expect(card.dx, closeTo(title.dx, 1.0),
          reason: 'the title, the filters and the first row begin at one left edge');
    });
  });

  group('the CAPA list is a register', () {
    testWidgets('at 1280 it is a table whose check column carries the overdue mark',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions/capas');

      expect(find.byType(AppTableHeader), findsOneWidget);
      final row = find.byKey(CapasScreen.rowKey('802'));
      expect(find.descendant(of: row, matching: find.byType(AppTableRow)), findsOneWidget);
      _expectRowIsATapTarget(tester, row);
      expect(find.byKey(CapasScreen.rowOverdueKey('802')), findsOneWidget);
      // The investigation whose check has not fallen due still says when it is.
      expect(find.byKey(CapasScreen.rowKey('801')), findsOneWidget);
    });

    testWidgets('at 700 it is a card per investigation, and at 900 and 2x it still is',
        (tester) async {
      await _pump(tester, width: 700, location: '/actions/capas');
      expect(find.byType(AppTableHeader), findsNothing, reason: 'window 700');
      _expectRowIsATapTarget(tester, find.byKey(CapasScreen.rowKey('801')));

      await _pump(tester, width: 900, location: '/actions/capas');
      expect(find.byType(AppTableHeader), findsNothing, reason: 'window 900');
      _expectRowIsATapTarget(tester, find.byKey(CapasScreen.rowKey('801')));

      await _pump(tester, width: 1280, location: '/actions/capas', textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(AppTableHeader), findsNothing, reason: '200% text');
      expect(find.byKey(CapasScreen.rowKey('801')), findsOneWidget);

      // Measured at 200%: the card is taller than a 1x row, and the overdue
      // mark and the check date stay inside the card that carries them.
      final card = tester.getRect(find.byKey(CapasScreen.rowKey('802')));
      expect(card.height, greaterThan(88.0),
          reason: 'a card at twice the text is taller than the 1x row');
      for (final (name, part) in [
        ('overdue mark', CapasScreen.rowOverdueKey('802')),
        ('check date', CapasScreen.rowDueKey('802')),
      ]) {
        final rect = tester.getRect(find.byKey(part));
        expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: '$name inside the card');
        expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: '$name inside the card');
        expect(rect.bottom, lessThanOrEqualTo(card.bottom + 0.5), reason: '$name inside the card');
      }
    });
  });

  group('the Action detail page', () {
    testWidgets('the page head sits above a summary card, and the sections follow it',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions/501');

      final head = find.byKey(AppPageHeader.titleKey);
      expect(head, findsOneWidget);
      expect(find.byKey(ActionDetailScreen.backKey), findsOneWidget);

      final summary = find.byKey(ActionDetailScreen.summaryKey);
      expect(summary, findsOneWidget);
      expect(tester.getTopLeft(head).dy, lessThan(tester.getTopLeft(summary).dy),
          reason: 'the page head is the first thing on the page');

      // The record's own identity is inside the summary card, and the sections
      // under it are the shared ones, so their headings share one gutter.
      expect(find.text('AC-HCM-2026-00001'), findsWidgets);
      final sectionTitle = find.byKey(AppDetailSection.titleKey('Where it stands'));
      expect(sectionTitle, findsOneWidget);
      // One left edge: the summary card and the first section card below it
      // begin at the same x (their own headings sit a gutter inside).
      final sectionCard =
          find.ancestor(of: sectionTitle, matching: find.byType(Card)).first;
      expect(tester.getTopLeft(summary).dx, closeTo(tester.getTopLeft(sectionCard).dx, 1.0));

      // The two acts on the record are the header's own actions.
      expect(find.byKey(ActionDetailScreen.escalateKey), findsOneWidget);
      expect(find.byKey(ActionDetailScreen.cancelKey), findsOneWidget);
    });

    testWidgets('a failed read still carries the page head and the back control',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions/999');

      expect(find.byType(PlatformFailureState), findsOneWidget);
      expect(find.byKey(ActionDetailScreen.failedKey), findsOneWidget);
      expect(find.byKey(AppPageHeader.titleKey), findsOneWidget,
          reason: 'a failed read renders the same page head as the record');
      expect(find.byKey(ActionDetailScreen.backKey), findsOneWidget);
    });

    testWidgets('at 700, at 900 and at twice the text one left edge holds and the sections follow',
        (tester) async {
      for (final (width, scale) in const [(700.0, 1.0), (900.0, 1.0), (1280.0, 2.0)]) {
        await _pump(tester, width: width, location: '/actions/501', textScale: scale);
        final why = 'window $width at ${scale}x';
        expect(tester.takeException(), isNull, reason: why);
        expect(find.byKey(ActionDetailScreen.summaryKey), findsOneWidget, reason: why);
        expect(find.byKey(AppDetailSection.titleKey('Where it stands')), findsOneWidget,
            reason: why);

        // Measured: the summary card, the section under it and the page head
        // start at one left edge, and the section sits below the card.
        final head = tester.getTopLeft(find.byKey(AppPageHeader.titleKey));
        final summary = tester.getRect(find.byKey(ActionDetailScreen.summaryKey));
        final section = tester.getRect(
          find
              .ancestor(
                of: find.byKey(AppDetailSection.titleKey('Where it stands')),
                matching: find.byType(Card),
              )
              .first,
        );
        expect(summary.left, closeTo(head.dx, 1.0), reason: 'one left edge: $why');
        expect(section.left, closeTo(summary.left, 1.0), reason: 'one left edge: $why');
        expect(section.width, closeTo(summary.width, 1.0), reason: 'one column: $why');
        expect(section.top, greaterThanOrEqualTo(summary.bottom - 1.0),
            reason: 'the sections follow the summary card: $why');
      }
    });
  });

  group('the CAPA detail page', () {
    testWidgets('the page head sits above a summary card, and its sections follow',
        (tester) async {
      await _pump(tester, width: 1280, location: '/actions/capas/801');

      final head = find.byKey(AppPageHeader.titleKey);
      expect(head, findsOneWidget);
      expect(find.byKey(CapaDetailScreen.backKey), findsOneWidget);
      expect(find.byKey(CapaDetailScreen.reportKey), findsOneWidget);

      final team = find.byKey(AppDetailSection.titleKey('Team'));
      expect(team, findsOneWidget);
      expect(tester.getTopLeft(head).dy, lessThan(tester.getTopLeft(team).dy));
      // One gutter for every section and for the head: the page head starts at
      // the frame's inset and so does the first section card under it.
      final teamCard = find.ancestor(of: team, matching: find.byType(Card)).first;
      expect(tester.getTopLeft(head).dx, closeTo(tester.getTopLeft(teamCard).dx, 1.0));

      // The sections a reader arrives to: the summary and the first of them.
      expect(find.byKey(AppDetailSection.titleKey('The problem')), findsWidgets);
    });

    testWidgets('at 700, at 900 and at twice the text one left edge holds and the sections follow',
        (tester) async {
      for (final (width, scale) in const [(700.0, 1.0), (900.0, 1.0), (1280.0, 2.0)]) {
        await _pump(tester, width: width, location: '/actions/capas/801', textScale: scale);
        final why = 'window $width at ${scale}x';
        expect(tester.takeException(), isNull, reason: why);
        // The sections the page opens with; the ones further down a lazy list
        // are not built until a reader scrolls to them, which is the list's
        // business rather than the layout's.
        expect(find.byKey(AppDetailSection.titleKey('Team')), findsOneWidget, reason: why);
        expect(find.byKey(CapaDetailScreen.backKey), findsOneWidget);

        // Measured: the page head and the first section card under it begin at
        // one left edge, and the section is below the head.
        final head = tester.getTopLeft(find.byKey(AppPageHeader.titleKey));
        final team = tester.getRect(
          find
              .ancestor(
                of: find.byKey(AppDetailSection.titleKey('Team')),
                matching: find.byType(Card),
              )
              .first,
        );
        expect(team.left, closeTo(head.dx, 1.0), reason: 'one left edge: $why');
        expect(team.top, greaterThan(head.dy), reason: 'the sections follow the head: $why');
        expect(team.width, greaterThan(0.0), reason: why);
      }
    });
  });

  group('the CAPA report is a document', () {
    testWidgets('nothing on it is a card, and its sections are ruled', (tester) async {
      await _pump(tester, width: 1280, location: '/actions/capas/801/report');

      expect(find.byKey(AppPageHeader.titleKey), findsOneWidget);
      expect(find.byKey(CapaReportScreen.metaKey), findsOneWidget);
      // The paper claim, asserted rather than described: a card's fill and
      // rounded corners are what a printer turns into grey panels around every
      // 8D step, so the report body holds none.
      expect(
        find.descendant(
          of: find.byKey(CapaReportScreen.loadedKey),
          matching: find.byType(Card),
        ),
        findsNothing,
        reason: 'the report prints as ruled sections, not as a stack of cards',
      );
      expect(find.byKey(AppDetailSection.titleKey('D1 · Team')), findsNothing);
      expect(find.text('D1 · Team'), findsOneWidget);
    });

    testWidgets('it holds at 700, at 900 and at twice the text, and its rules share the page edge',
        (tester) async {
      for (final (width, scale) in const [(700.0, 1.0), (900.0, 1.0), (1280.0, 2.0)]) {
        await _pump(tester, width: width, location: '/actions/capas/801/report', textScale: scale);
        final why = 'window $width at ${scale}x';
        expect(tester.takeException(), isNull, reason: why);
        expect(find.text('D1 · Team'), findsOneWidget, reason: why);

        // Measured: the meta line and the page head share the left edge, and
        // the document's rules stay inside the page's own width — which is
        // what makes the printed sheet one column rather than a cropped one.
        final head = tester.getTopLeft(find.byKey(AppPageHeader.titleKey));
        final meta = tester.getRect(find.byKey(CapaReportScreen.metaKey));
        final loaded = tester.getRect(find.byKey(CapaReportScreen.loadedKey));
        expect(meta.left, closeTo(head.dx, 1.0), reason: 'one left edge: $why');
        expect(meta.left, greaterThanOrEqualTo(loaded.left - 0.5), reason: why);
        expect(meta.right, lessThanOrEqualTo(loaded.right + 0.5), reason: why);
      }
    });
  });
}
