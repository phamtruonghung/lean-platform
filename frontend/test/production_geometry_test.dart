/// The Production Module's geometry and its clock, pinned (issue #389).
///
/// **What this file is for.** The design pass on the Section board and the Shift
/// handover changed where things sit, so "it renders" proves nothing: these tests
/// measure. Every assertion below is a rectangle or a size read off the rendered
/// tree (`getTopLeft`, `getSize`, `getBottomRight`) at the three boxes the card
/// names (700, 900 and 1280 logical pixels) and at a text scale of 2, so a later pass
/// that moves the counts below the shifts, narrows a machine tile under a glove's
/// target, or lets the pinned submit creep over the form fails here rather than
/// looking subtly wrong on a floor tablet.
///
/// **Why the app's own fonts are loaded first.** Without them `flutter_test`
/// paints a placeholder font whose glyphs are twice as wide as Roboto's, and a
/// width pinned here would be a property of that placeholder (the reason
/// `register_geometry_support.dart` does the same).
///
/// **Why the clock is asserted separately.** The board says how far through a
/// shift the reader is, the one thing on either Screen derived from a clock. These
/// tests go through the router, so they read the real clock and assert the bar's
/// presence and geometry rather than its words; the words belong to
/// `formatShiftProgress` / `shiftProgressFraction`, asserted as a unit at a fixed
/// instant below (`SectionBoardScreen.now` is the injection point for a caller
/// that needs it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/production/handover_format.dart';
import 'package:lean_platform/production/section_board_screen.dart';
import 'package:lean_platform/production/shift_handover_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_dialog.dart';
import 'package:lean_platform/widgets/app_page_frame.dart';

import 'harness.dart';

const String _section = '30';
const String _boardAddress = '/production/sections/$_section/board?date=2026-05-05';
const String _handoverAddress = '/production/sections/$_section/handover/500?date=2026-05-05';

Map<String, dynamic> _machineLine(String assetId, String code, String name, String state) => {
      'id': 'ml-$assetId',
      'assetId': assetId,
      'assetCode': code,
      'assetName': name,
      'state': state,
      'abnormalityType': null,
      'note': null,
      'watchNote': null,
      'walked': false,
    };

/// One Section, two shifts. [drafted] true resumes a draft on the second shift
/// (so the handover form is editable and offers Submit); false leaves it
/// submitted (so the board offers Acknowledge and the board's own read is the
/// one under test). Either way the shift carries two machine lines, one of them
/// `down`, so the board's tiles have something to show.
FakeWire _wire({required bool drafted}) {
  final handover = shiftHandoverJson(
    'h1',
    orgUnitId: _section,
    shiftInstanceId: '500',
    status: drafted ? 'draft' : 'submitted',
    authorDisplayName: drafted ? null : 'B Team Leader',
    snapshot: drafted ? const {} : const {'oee': 0.82, 'availability': 0.9},
    machineLines: [
      _machineLine('a1', 'PRESS-1', 'Press 1', 'running'),
      _machineLine('a2', 'PRESS-2', 'Press 2', 'down'),
    ],
  );
  return FakeWire(
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    sectionAssets: {
      _section: [
        sectionAssetJson('a1', 'PRESS-1', 'Press 1'),
        sectionAssetJson('a2', 'PRESS-2', 'Press 2'),
      ],
    },
    sectionDays: {
      _section: sectionDayJson(
        _section,
        shifts: [
          sectionShiftJson('400', exceptions: const ['no_handover'], late: true),
          sectionShiftJson('500', handover: handover, acknowledgementLatencyMinutes: 45),
        ],
      ),
    },
    handovers: {handover['id'] as String: handover},
  );
}

/// Pump the app at [width] and [textScale]. [now] is handed to a directly built
/// board only; through the router the Screen reads the clock, so the board's
/// own tests assert the words' shape rather than a minute count.
Future<void> _pump(
  WidgetTester tester, {
  required String at,
  required double width,
  required bool drafted,
  double textScale = 1,
  double height = 1200,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire(drafted: drafted).client,
    initialLocation: at,
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('the shift position', () {
    // A pure formatter, so the board's one clock reading is asserted exactly
    // rather than through a rendered sentence and the hour the suite ran.
    test('says how far in, how far to go, not yet, and over', () {
      const starts = '2026-05-05T23:00:00Z';
      const ends = '2026-05-06T07:00:00Z';
      expect(formatShiftProgress(DateTime.utc(2026, 5, 6, 2), starts, ends), '3 h in · 5 h to go');
      expect(formatShiftProgress(DateTime.utc(2026, 5, 6, 7, 30), starts, ends), 'Ended 30 min ago');
      expect(formatShiftProgress(DateTime.utc(2026, 5, 5, 21), starts, ends), 'Starts in 2 h');
      expect(formatShiftProgress(DateTime.utc(2026, 5, 6, 2), null, ends), '—');
    });

    test('fills the bar from 0 to 1 across the shift, and nothing without a span', () {
      const starts = '2026-05-05T23:00:00Z';
      const ends = '2026-05-06T07:00:00Z';
      expect(shiftProgressFraction(DateTime.utc(2026, 5, 5, 22), starts, ends), 0);
      expect(shiftProgressFraction(DateTime.utc(2026, 5, 6, 3), starts, ends), closeTo(0.5, 0.001));
      expect(shiftProgressFraction(DateTime.utc(2026, 5, 6, 9), starts, ends), 1);
      expect(shiftProgressFraction(DateTime.utc(2026, 5, 6, 9), starts, null), isNull);
      // A shift that ends before it starts is not a bar half full.
      expect(shiftProgressFraction(DateTime.utc(2026, 5, 6, 9), ends, starts), isNull);
    });
  });

  group('the Section board', () {
    testWidgets('at 1280 the counts sit above the shifts, and each machine tile is a 44px target '
        'four targets wide with its state in words', (tester) async {
      await _pump(tester, at: _boardAddress, width: 1280, drafted: false);

      final counts = find.byKey(SectionBoardScreen.countsKey);
      expect(counts, findsOneWidget);
      // Above the fold, and above the first shift card rather than under it.
      expect(
        tester.getBottomLeft(counts).dy,
        lessThan(tester.getTopLeft(find.byKey(SectionBoardScreen.shiftRowKey('500'))).dy),
        reason: 'the counts row must be read before the shifts',
      );
      // The four counts are the day's own tally of what the server flagged.
      expect(
        find.descendant(of: find.byKey(SectionBoardScreen.countKey('shifts')), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(SectionBoardScreen.countKey('no_handover')), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(SectionBoardScreen.countKey('late')), matching: find.text('1')),
        findsOneWidget,
      );

      final tile = find.byKey(SectionBoardScreen.machineTileKey('500', 'a2'));
      expect(tile, findsOneWidget);
      final size = tester.getSize(tile);
      expect(size.height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(size.width, greaterThanOrEqualTo(AppTouchTarget.min * 4));
      // The state is a word, not only a tint.
      expect(find.descendant(of: tile, matching: find.text('Down')), findsOneWidget);
      // One left edge: the first tile starts where the card's own text starts.
      expect(
        tester.getTopLeft(find.byKey(SectionBoardScreen.machineTileKey('500', 'a1'))).dx,
        closeTo(tester.getTopLeft(find.byKey(SectionBoardScreen.shiftTitleKey('500'))).dx, 0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 700 the board keeps one left edge, the counts fall to two columns, and the '
        'date control sits under the title', (tester) async {
      await _pump(tester, at: _boardAddress, width: 700, drafted: false);

      final frame = find.byType(AppPageFrame);
      expect(frame, findsOneWidget);
      final left = tester.getRect(frame).left + Spacing.lg;

      // The title, the date control and the counts row share the page's edge.
      final title = find.text('Self-Closing');
      expect(tester.getTopLeft(title).dx, closeTo(left, 1.5));
      expect(tester.getTopLeft(find.byKey(SectionBoardScreen.dateFieldKey)).dx, closeTo(left, 1.5));
      expect(tester.getTopLeft(find.byKey(SectionBoardScreen.countsKey)).dx, closeTo(left, 1.5));
      // The date control is on its own line, under the title's block.
      expect(
        tester.getTopLeft(find.byKey(SectionBoardScreen.dateFieldKey)).dy,
        greaterThan(tester.getBottomLeft(find.textContaining('Every shift of the production day')).dy),
      );

      // Two columns, not three: the second tile of the first row shares a top
      // with the first, and the third starts a new row.
      final shiftsTile = find.byKey(SectionBoardScreen.countKey('shifts'));
      final noHandover = find.byKey(SectionBoardScreen.countKey('no_handover'));
      final unacknowledged = find.byKey(SectionBoardScreen.countKey('unacknowledged'));
      expect(tester.getTopLeft(noHandover).dy, closeTo(tester.getTopLeft(shiftsTile).dy, 0.5));
      expect(tester.getTopLeft(unacknowledged).dy, greaterThan(tester.getBottomLeft(shiftsTile).dy));

      // The tile still holds a 44px target at the narrow box.
      final tile = find.byKey(SectionBoardScreen.machineTileKey('500', 'a1'));
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(tester.getSize(tile).width, lessThanOrEqualTo(tester.getSize(frame).width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 900 the board still takes the narrow shape: the counts fall to two columns, the '
        'page keeps one left edge and a machine tile is a 44px target', (tester) async {
      await _pump(tester, at: _boardAddress, width: 900, drafted: false);

      final frame = find.byType(AppPageFrame);
      expect(frame, findsOneWidget);
      final left = tester.getRect(frame).left + Spacing.lg;
      expect(tester.getTopLeft(find.byKey(SectionBoardScreen.countsKey)).dx, closeTo(left, 1.5));

      // The Shell's rail leaves a 640px page here, so the counts row is handed
      // 608 of it (640 − 2×`Spacing.lg`) — under its 704 floor, so two columns
      // rather than four. This is the width closest to that floor, which is why
      // it is worth its own case.
      final shiftsTile = find.byKey(SectionBoardScreen.countKey('shifts'));
      expect(
        tester.getTopLeft(find.byKey(SectionBoardScreen.countKey('no_handover'))).dy,
        closeTo(tester.getTopLeft(shiftsTile).dy, 0.5),
        reason: 'the second count shares the first row',
      );
      expect(
        tester.getTopLeft(find.byKey(SectionBoardScreen.countKey('unacknowledged'))).dy,
        greaterThan(tester.getBottomLeft(shiftsTile).dy),
        reason: 'the third count starts a new row',
      );

      final tile = find.byKey(SectionBoardScreen.machineTileKey('500', 'a1'));
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at a text scale of 2, at 1280, 900 and at 700, nothing overflows, the counts still '
        'fall to two columns and a shift\'s own action is still reachable', (tester) async {
      for (final width in [1280.0, 900.0, 700.0]) {
        await _pump(tester, at: _boardAddress, width: width, drafted: false, textScale: 2);
        expect(tester.takeException(), isNull, reason: 'board at $width x2');

        // The breakpoint is a function of the reader's text size as well as of
        // the box: at 2x the counts row's 704 floor becomes 1408, so even this
        // Screen's widest content box (868 at a 1280 window) sits under it and
        // two columns is right at all three widths. Compare a raw
        // `tileFloor * 4`, which puts four across at 1280 and overflows the
        // captions.
        final shiftsTile = find.byKey(SectionBoardScreen.countKey('shifts'));
        expect(
          tester.getTopLeft(find.byKey(SectionBoardScreen.countKey('no_handover'))).dy,
          closeTo(tester.getTopLeft(shiftsTile).dy, 0.5),
          reason: 'board counts two-across at $width x2',
        );
        expect(
          tester.getTopLeft(find.byKey(SectionBoardScreen.countKey('unacknowledged'))).dy,
          greaterThan(tester.getBottomLeft(shiftsTile).dy),
          reason: 'board counts two-across at $width x2: the third starts a new row',
        );
        // A machine tile still holds a glove's target with the text doubled.
        expect(
          tester.getSize(find.byKey(SectionBoardScreen.machineTileKey('500', 'a2'))).height,
          greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'board tile at $width x2',
        );

        final open = find.byKey(SectionBoardScreen.openHandoverKey('500'));
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        expect(open.hitTestable(), findsOneWidget, reason: 'board action at $width x2');
      }
    });
  });

  group('the Shift handover', () {
    testWidgets('at 1280 Submit is a bar pinned to the page frame\'s own bottom edge, and the '
        'scroll view ends where the bar begins', (tester) async {
      await _pump(tester, at: _handoverAddress, width: 1280, drafted: true, height: 1000);

      final frame = find.byType(AppPageFrame);
      final bar = find.byKey(ShiftHandoverScreen.submitBarKey);
      expect(frame, findsOneWidget);
      expect(bar, findsOneWidget);
      expect(
        tester.getBottomRight(bar).dy,
        closeTo(tester.getBottomRight(frame).dy, 1),
        reason: 'the bar is pinned to the frame\'s bottom',
      );
      expect(
        tester.getTopLeft(bar).dx,
        closeTo(tester.getTopLeft(frame).dx, 1),
        reason: 'the bar spans the page frame, not the window',
      );
      // A sibling, not an overlay: the form's viewport stops at the bar, so the
      // bar can hide nothing and the form owes it no bottom padding.
      expect(
        tester.getBottomLeft(find.byKey(ShiftHandoverScreen.loadedKey)).dy,
        closeTo(tester.getTopLeft(bar).dy, 1),
      );
      // The one act is in the bar, at a 44px target.
      final submit = find.byKey(ShiftHandoverScreen.submitKey);
      expect(find.descendant(of: bar, matching: submit), findsOneWidget);
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(AppTouchTarget.min));
      // Wide, the anchors are not drawn: the bar is the way to the act.
      expect(find.byKey(ShiftHandoverScreen.anchorsKey), findsNothing);
      // And the field grid is two across, the other side of the same
      // breakpoint: 'State' and 'Abnormality' share a row here and stack at 2x.
      expect(
        tester.getTopLeft(find.byKey(ShiftHandoverScreen.machineAbnormalityKey('a1'))).dy,
        closeTo(tester.getTopLeft(find.byKey(ShiftHandoverScreen.machineStateKey('a1'))).dy, 0.5),
        reason: 'wide, two fields of one machine line share a row',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 900 the handover is still narrow: section anchors in the header, no pinned bar, '
        'and the one act inline inside the scrolled form at a 44px target', (tester) async {
      await _pump(tester, at: _handoverAddress, width: 900, drafted: true, height: 1000);

      // The Shell's rail leaves a 640px box (608 of content), under the form's
      // 900px two-column point: the anchors are the way through the form and
      // nothing is pinned.
      expect(find.byKey(ShiftHandoverScreen.submitBarKey), findsNothing);
      expect(find.byKey(ShiftHandoverScreen.anchorsKey), findsOneWidget);
      final submit = find.byKey(ShiftHandoverScreen.submitKey);
      expect(
        find.descendant(of: find.byKey(ShiftHandoverScreen.loadedKey), matching: submit),
        findsOneWidget,
        reason: 'narrow, the act is inside the form rather than a bar under it',
      );
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 700 there is no bar: the header carries anchors, Submit is inline at the '
        'form\'s end, and an anchor brings its section to the top of the viewport', (tester) async {
      await _pump(tester, at: _handoverAddress, width: 700, drafted: true, height: 1000);

      expect(find.byKey(ShiftHandoverScreen.submitBarKey), findsNothing);
      expect(find.byKey(ShiftHandoverScreen.anchorsKey), findsOneWidget);
      final submit = find.byKey(ShiftHandoverScreen.submitKey);
      expect(submit, findsOneWidget);

      final viewportTop = tester.getTopLeft(find.byKey(ShiftHandoverScreen.loadedKey)).dy;
      final machinesTitle = find.byKey(AppDetailSection.titleKey('Machines'));
      // Before the jump the form is at its top, so Machines is well below it.
      expect(tester.getTopLeft(machinesTitle).dy, greaterThan(viewportTop + 100));

      await tapIn(tester, find.byKey(ShiftHandoverScreen.anchorKey('machines')));

      // The section's card is aligned to the viewport's top, so its title sits
      // one card padding under it.
      expect(
        tester.getTopLeft(machinesTitle).dy - viewportTop,
        closeTo(Spacing.md, 2),
        reason: 'the Machines anchor must bring the Machines section to the top',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('across the band #440 named, the pinned bar is drawn exactly when the fields share '
        'a row: not at 1200, yes at 1240', (tester) async {
      // The bar and the field grid decide "wide" on the same box now: the page
      // less the form's own 64px inset (the scroll view's `Spacing.lg` each side
      // plus `AppDetailSection`'s). A 1200 window hands the page 940 and its
      // field rows 876, under the form's 900 two-column point; a 1240 window
      // hands them 916, over it. Comparing the page box instead drew the bar at
      // 1200 over stacked fields — the residue of #389, measured in #440.
      for (final (width, wide) in [(1200.0, false), (1240.0, true)]) {
        await _pump(tester, at: _handoverAddress, width: width, drafted: true, height: 1000);

        final bar = find.byKey(ShiftHandoverScreen.submitBarKey);
        final anchors = find.byKey(ShiftHandoverScreen.anchorsKey);
        final submit = find.byKey(ShiftHandoverScreen.submitKey);
        final sharedRow = tester
                .getTopLeft(find.byKey(ShiftHandoverScreen.machineAbnormalityKey('a1')))
                .dy -
            tester.getTopLeft(find.byKey(ShiftHandoverScreen.machineStateKey('a1'))).dy;

        expect(
          (sharedRow.abs() < 0.5),
          wide,
          reason: 'at $width the field grid is ${wide ? 'two across' : 'stacked'}',
        );
        expect(
          bar,
          wide ? findsOneWidget : findsNothing,
          reason: 'at $width the bar is ${wide ? 'drawn' : 'not drawn — the fields are stacked'}',
        );
        expect(
          anchors,
          wide ? findsNothing : findsOneWidget,
          reason: 'at $width the anchors are ${wide ? 'not drawn' : 'in the header'}',
        );
        // The one act lives in whichever place the box made right.
        expect(
          find.descendant(of: wide ? bar : find.byKey(ShiftHandoverScreen.loadedKey), matching: submit),
          findsOneWidget,
          reason: 'at $width the one act is inside the ${wide ? 'bar' : 'form'}',
        );
        expect(tester.getSize(submit).height, greaterThanOrEqualTo(AppTouchTarget.min));
        expect(tester.takeException(), isNull, reason: 'handover at $width');
      }
    });

    testWidgets('at a text scale of 2, at 1280, 900 and at 700, nothing overflows, the narrow shape '
        'is taken, the fields are still there and the act is still reachable', (tester) async {
      for (final width in [1280.0, 900.0, 700.0]) {
        await _pump(tester, at: _handoverAddress, width: width, drafted: true, textScale: 2, height: 1400);
        expect(tester.takeException(), isNull, reason: 'handover at $width x2');
        // At 2x the form's 900px two-column point is 1800, so even the widest
        // box here (1020 — the 1100 page inside the Shell's content area at a
        // 1280 window) is narrow: the anchors are drawn and nothing is pinned.
        // Compare a raw `AppBreakpoints.formTwoColumn`, which paints the wide
        // bar at 1280 over fields that are stacked — the exact bug #379 and
        // #381 shipped.
        expect(
          find.byKey(ShiftHandoverScreen.anchorsKey),
          findsOneWidget,
          reason: 'handover anchors at $width x2',
        );
        expect(
          find.byKey(ShiftHandoverScreen.submitBarKey),
          findsNothing,
          reason: 'handover has no pinned bar at $width x2',
        );
        // A field of the first machine line, and the one act.
        expect(find.byKey(ShiftHandoverScreen.machineStateKey('a1')), findsOneWidget);
        // The field grid is stacked as well: 'State' and 'Abnormality' share a
        // row only when the box beats the 900 point *at the reader's scale*.
        // A raw `AppBreakpoints.formTwoColumn` here keeps them side by side at
        // 2x, half a row each, which is the clipping #379/#381 shipped.
        expect(
          tester.getTopLeft(find.byKey(ShiftHandoverScreen.machineAbnormalityKey('a1'))).dy,
          greaterThan(tester.getBottomLeft(find.byKey(ShiftHandoverScreen.machineStateKey('a1'))).dy),
          reason: 'handover fields stacked at $width x2',
        );
        final submit = find.byKey(ShiftHandoverScreen.submitKey);
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget, reason: 'submit at $width x2');
        expect(tester.getSize(submit).height, greaterThanOrEqualTo(AppTouchTarget.min));
      }
    });

    testWidgets('the five form sections are the five the anchors name', (tester) async {
      // At a narrow box, where the anchors exist: the row names exactly the
      // sections the form actually renders.
      await _pump(tester, at: _handoverAddress, width: 700, drafted: true);

      for (final (id, label) in ShiftHandoverScreen.sections) {
        expect(find.byKey(ShiftHandoverScreen.anchorKey(id)), findsOneWidget, reason: 'anchor $id');
        expect(find.text(label), findsWidgets, reason: 'anchor label $label');
      }
      expect(find.byType(AppDetailSection), findsNWidgets(ShiftHandoverScreen.sections.length));
    });
  });

  group('the acknowledgement dialog', () {
    // One test per box rather than one loop: `pumpApp` reuses the app's own
    // state between pumps, so a dialog left open in one case would still be
    // over the next case's board.
    //
    // **900 is a sheet, and that is measured rather than assumed.** The
    // acknowledge dialog is a `DialogPage` on a route nested inside the Shell, so
    // the box it is handed is the content area, not the window: at a 900 window
    // that box is 640 (the rail takes 260), under `AppBreakpoints.dialogSheet`'s
    // 700. It reports "surfaceW=640 frameW=640" — the same number as the page
    // frame beneath it. Left as it is: the address is the dialog's (ADR-0019) and
    // moving it out from under the Shell is not a presentation change.
    for (final (width, textScale, sheet) in [
      (1280.0, 1.0, false),
      (900.0, 1.0, true),
      (700.0, 1.0, true),
      (1280.0, 2.0, true),
    ]) {
      testWidgets('at $width x$textScale the acknowledgement is ${sheet ? 'a sheet' : 'the 640 dialog'}',
          (tester) async {
        await _pump(tester, at: _boardAddress, width: width, drafted: false, textScale: textScale);
        await tapIn(tester, find.byKey(SectionBoardScreen.acknowledgeKey('500')));

        final surface = find.byKey(AppDialog.surfaceKey);
        expect(surface, findsOneWidget, reason: 'dialog at $width x$textScale');
        if (sheet) {
          expect(find.byKey(AppDialog.sheetKey), findsOneWidget, reason: 'sheet at $width x$textScale');
          // Full width of the box it was handed — at least the page beneath it,
          // never wider than the window.
          final sheetWidth = tester.getSize(surface).width;
          expect(sheetWidth, greaterThanOrEqualTo(tester.getSize(find.byType(AppPageFrame)).width - 1));
          expect(sheetWidth, lessThanOrEqualTo(width));
        } else {
          expect(find.byKey(AppDialog.sheetKey), findsNothing);
          expect(tester.getSize(surface).width, closeTo(AppDialogSize.wide.width, 1));
        }
        // Its two actions are the caller's, in the documented order.
        expect(find.byKey(AppDialog.actionKey('handover-acknowledge-cancel')), findsOneWidget);
        expect(find.byKey(AppDialog.actionKey('handover-acknowledge-submit')), findsOneWidget);
        expect(
          tester.getBottomRight(find.byKey(AppDialog.actionKey('handover-acknowledge-submit'))).dy,
          isNotNull,
        );
        expect(
          tester.getTopLeft(find.byKey(AppDialog.actionKey('handover-acknowledge-cancel'))).dx,
          lessThan(tester.getTopLeft(find.byKey(AppDialog.actionKey('handover-acknowledge-submit'))).dx),
          reason: 'dismiss before primary',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
