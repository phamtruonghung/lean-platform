/// Every page's title, description and content start at the same left edge
/// (issue #193).
///
/// **What this test is for.** A `Center` around a `ConstrainedBox` sizes itself
/// to its child, and a `Column` of `Text`s sizes itself to its longest line — so
/// a page whose content is a title, a description and a row of buttons
/// shrink-wrapped to the width of its own longest sentence and floated to the
/// middle of the window. Measured before the fix: `/stores`' title and
/// description began 142px right of the card beneath them, `/approval-queue`'s
/// 106px, and `/skills`' rows sat 43px inside their own card with their actions
/// against the text rather than at the row's right-hand end. Which pages showed
/// it depended on whether their content happened to contain something that
/// forces a width, so it read as "some pages look wrong" rather than as one bug.
///
/// **What it claims.** For every Screen in the table: its title starts at the
/// page frame's own left inset; its description starts at the same place; the
/// first card on the page starts there too; and the left-most text inside that
/// card is inset only by the row's own padding. A page that drifts — by
/// shrink-wrapping its header, by centring a list block, or by moving its
/// content frame — fails here rather than being noticed by eye on whichever page
/// happens to be looked at next.
///
/// **What it does not claim.** Anything about a page's vertical rhythm, its
/// copy, or the deliberate insets that belong to a row's own shape: the
/// Directory's and the Approval queue's rows carry a 40px avatar and are 68px
/// in, and the Org Units tree indents by depth, so those name their own bound
/// below. Nor anything about the centred shared states (an empty or failed read
/// is centred on purpose, and is not a page header).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_page_frame.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

/// A page to audit: where it is reached, what its title says, a phrase from its
/// description (empty when the Screen writes none), and the largest inset its
/// first row's own text may have inside its card — 20 by default, which is one
/// row's own padding plus a pixel of rounding.
class _Page {
  const _Page(this.route, this.title, this.descriptionPrefix, {this.maxRowInset = 20});

  final String route;
  final String title;
  final String descriptionPrefix;
  final double maxRowInset;
}

const _pages = <_Page>[
  _Page('/directory', 'Directory', 'Who works here', maxRowInset: 68),
  _Page('/job-roles', 'Job roles', 'What an Employee does'),
  _Page('/skills', 'Skills', 'What the plant qualifies'),
  // The tree indents by depth and leads with a disclosure control.
  _Page('/org-units', 'Org Units', "A Site's own shape", maxRowInset: 44),
  _Page('/assets', 'Assets', ''),
  _Page('/parts', 'Parts', ''),
  _Page('/stores', 'Stores', 'The shelves that hold parts'),
  _Page('/work-orders', 'Work orders', ''),
  _Page('/my-requests', 'My requests', ''),
  _Page('/downtime', 'Downtime', ''),
  _Page('/pm-schedules', 'PM schedules', ''),
  _Page('/meters', 'Meters', ''),
  _Page('/job-plans', 'Job plans', ''),
  _Page('/accounts', 'Accounts', ''),
  _Page('/approvals', 'Approval queue', '', maxRowInset: 68),
  _Page('/actions', 'Actions', ''),
  _Page('/tier-board', 'Tier board', ''),
  _Page('/skill-coverage', 'Skill coverage', ''),
];

/// One wire for every page in the table: each Screen finds the collection it
/// reads, so what is measured is a rendered page rather than a loading
/// placeholder or a failed read.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {
        '1': [assetJson('1', 'PRESS-1', 'Press 1')],
      },
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      parts: [partJson('1', 'PART-1', 'Bearing')],
      stores: {
        '1': [storeJson('1', 'HCM-STORE', 'Main store')],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      jobRoles: [jobRoleJson('20', 'WELD', 'Welder')],
      skills: [skillJson('30', 'WELD', 'Welding')],
      jobPlans: [jobPlanJson('1', 'JP-1', 'Monthly check')],
      meters: {
        '1': [meterJson('1', 'M-1', 'Hours')],
      },
      accounts: [accountJson('1', 'admin@b.c', role: Roles.admin)],
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
      actions: {
        '1': [actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose')],
      },
    );

void main() {
  for (final page in _pages) {
    testWidgets('${page.route} starts its title, description and rows at one left edge',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);

      final wire = _wire();
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: page.route,
      );

      // The page's own frame — the box the Screen laid its content out in.
      final frame = find.byType(AppPageFrame);
      expect(frame, findsWidgets, reason: '${page.route} renders no page frame');
      final box = tester.getRect(frame.first);
      final expected = box.left + Spacing.lg;

      // The Screen's own title, not the sidebar's label of the same word: a
      // title is `headlineSmall` (24px), the rail's label is `bodyMedium`.
      final title = find.byWidgetPredicate(
        (w) => w is Text && w.data == page.title && w.style?.fontSize == 24,
      );
      expect(title, findsOneWidget, reason: '${page.route} shows no title');
      expect(
        tester.getTopLeft(title.first).dx,
        closeTo(expected, 1.5),
        reason: '${page.route}: the title does not start at the page frame\'s own inset',
      );

      if (page.descriptionPrefix.isNotEmpty) {
        final desc = find.textContaining(page.descriptionPrefix);
        expect(desc, findsWidgets, reason: '${page.route} shows no description');
        expect(
          tester.getTopLeft(desc.first).dx,
          closeTo(expected, 1.5),
          reason: '${page.route}: the description is not flush with the title',
        );
      }

      // The first card and the left-most text inside it, where the page has one
      // (a page that lays out a table has no card, and is covered by the two
      // assertions above).
      final cards = find.byType(Card);
      if (cards.evaluate().isEmpty) return;
      var minCardX = double.infinity;
      Widget? firstCard;
      for (final element in cards.evaluate()) {
        final x = tester.getTopLeft(find.byWidget(element.widget)).dx;
        if (x < minCardX) {
          minCardX = x;
          firstCard = element.widget;
        }
      }
      expect(
        minCardX,
        closeTo(expected, 1.5),
        reason: '${page.route}: the first card does not start at the title\'s left edge',
      );

      final texts = find.descendant(of: find.byWidget(firstCard!), matching: find.byType(Text));
      var minTextX = double.infinity;
      for (final element in texts.evaluate()) {
        final x = tester.getTopLeft(find.byWidget(element.widget)).dx;
        if (x < minTextX) minTextX = x;
      }
      if (minTextX == double.infinity) return;
      expect(
        minTextX - minCardX,
        lessThanOrEqualTo(page.maxRowInset),
        reason: '${page.route}: the first row\'s own text is inset ${(minTextX - minCardX).round()}px '
            'inside its card — a row that shrink-wraps inside a centre-aligned column',
      );
    });
  }
}
