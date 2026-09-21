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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_page_frame.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

/// A page to audit: where it is reached, the file that renders it, what its title
/// says, a phrase from its description (empty when the Screen writes none), the
/// page's own left inset (16 by default, `Spacing.lg` — Home pads by
/// `Spacing.xl`), and the largest inset its first row's own text may have inside
/// its card (20 by default, which is one row's own padding plus a pixel of
/// rounding; a row built around a 40px avatar is 68 in, and a tree indents by
/// depth).
class _Page {
  const _Page(
    this.route,
    this.screenFile,
    this.title,
    this.descriptionPrefix, {
    this.inset = Spacing.lg,
    this.maxRowInset = 20,
  });

  final String route;
  final String screenFile;
  final String title;
  final String descriptionPrefix;
  final double inset;
  final double maxRowInset;
}

const _pages = <_Page>[
  // Home's address is `/`, and its second line repeats the Shell's own footer
  // text, so it is asserted by title and card rather than by that line.
  _Page('/', 'lib/home_screen.dart', 'Welcome, A B', '', inset: Spacing.xl),
  _Page('/directory', 'lib/people/directory_screen.dart', 'Directory', 'Who works here',
      maxRowInset: 68),
  _Page('/job-roles', 'lib/people/job_roles_screen.dart', 'Job roles', 'What an Employee does'),
  _Page('/skills', 'lib/people/skills_screen.dart', 'Skills', 'What the plant qualifies'),
  // The tree indents by depth and leads with a disclosure control.
  _Page('/org-units', 'lib/people/org_units_screen.dart', 'Org Units', "A Site's own shape",
      maxRowInset: 44),
  _Page('/assets', 'lib/maintenance/assets_screen.dart', 'Assets', ''),
  _Page('/parts', 'lib/maintenance/parts_screen.dart', 'Parts', ''),
  _Page('/stores', 'lib/maintenance/stores_screen.dart', 'Stores', 'The shelves that hold parts'),
  _Page('/work-orders', 'lib/maintenance/work_orders_screen.dart', 'Work orders', ''),
  _Page('/my-requests', 'lib/maintenance/my_requests_screen.dart', 'My requests', ''),
  _Page('/requests', 'lib/maintenance/requests_screen.dart', 'Triage queue', ''),
  _Page('/downtime', 'lib/maintenance/downtime_screen.dart', 'Downtime', ''),
  _Page('/pm-schedules', 'lib/maintenance/pm_schedules_screen.dart', 'PM schedules', ''),
  _Page('/meters', 'lib/maintenance/meters_screen.dart', 'Meters', ''),
  _Page('/job-plans', 'lib/maintenance/job_plans_screen.dart', 'Job plans', ''),
  _Page('/accounts', 'lib/people/accounts_screen.dart', 'Accounts', ''),
  _Page('/approvals', 'lib/people/approval_queue_screen.dart', 'Approval queue', '',
      maxRowInset: 68),
  _Page('/actions', 'lib/actions/actions_screen.dart', 'Actions', ''),
  _Page('/tier-board', 'lib/maintenance/tier_board_screen.dart', 'Tier board', ''),
  _Page('/skill-coverage', 'lib/people/skill_coverage_screen.dart', 'Skill coverage', ''),
  // The Quality Module's two catalogues (issue #203). Defect codes is a tree,
  // so its rows indent by depth one level at a time — the first row is a root
  // at the card's own padding, which is why the default bound holds here where
  // the Org Units tree (whose first row leads with a disclosure control) needs
  // its own.
  _Page('/products', 'lib/quality/products_screen.dart', 'Products', 'What the plant makes'),
  _Page('/defect-codes', 'lib/quality/defect_codes_screen.dart', 'Defect codes',
      'The kinds of thing found wrong'),
  // The Non-conformance register (issue #205). Its rows are cards of text at
  // the card's own padding, so the default bound holds.
  _Page('/non-conformances', 'lib/quality/nonconformances_screen.dart', 'Non-conformances',
      'What was found not to conform'),
  // The CAPA list (issue #211). Its rows are cards of text at the card's own
  // padding too, so the default bound holds here as well.
  _Page('/actions/capas', 'lib/actions/capas_screen.dart', 'CAPAs',
      'The investigations opened on a Concern'),
  // The Customer list and the complaint register (issue #214). Both are pages
  // with a frame, a heading and rows at the card's own padding, so the default
  // bound holds for each.
  _Page('/customers', 'lib/quality/customers_screen.dart', 'Customers', 'Who the plant'),
  _Page('/complaints', 'lib/quality/complaints_screen.dart', 'Customer complaints',
      'What customers have complained about'),
  // The Supplier list and the supplier NCR register (issue #215) — the same
  // pair turned outward, and the same shape: a page with a frame, a heading and
  // rows at the card's own padding, so the default bound holds for each.
  _Page('/suppliers', 'lib/quality/suppliers_screen.dart', 'Suppliers', 'Who the plant buys'),
  _Page('/supplier-ncrs', 'lib/quality/supplier_ncrs_screen.dart', 'Supplier NCRs',
      'What arrived wrong'),
  // The CAPA report (issue #212). Audited rather than excluded, and the
  // audited shape is the point of the ticket: it is a page with a frame, a
  // heading and a column of cards even though it is reached outside the Shell,
  // so its title, its description and its first section must all start at the
  // frame's own left edge like any other page's. It pads by `Spacing.xl` (the
  // token its own `ListView`-free document layout spends) and its width is its
  // own 1100 rather than `AppLayout.pageWidth` — a width this test deliberately
  // does not assert, because page widths are not a rule here.
  // The Safety incident register (issue #226). Its rows are cards of text at
  // the card's own padding, so the default bound holds.
  _Page('/safety/incidents', 'lib/safety/incidents_screen.dart', 'Safety incidents',
      'What went wrong at this Site'),
  // The Safety Module's two catalogues (issue #224). Flat lists of rows at the
  // card's own padding, like the Product catalogue, so the default bound holds
  // for each. Audited rather than excluded even though their Destinations are
  // an administrator's: the addresses themselves are open to any active
  // Account (injury-type-routes.js/body-part-routes.js), and a page a reader
  // can reach is a page whose alignment is asserted.
  _Page('/safety/injury-types', 'lib/safety/injury_types_screen.dart', 'Injury types',
      'What an injury was'),
  _Page('/safety/body-parts', 'lib/safety/body_parts_screen.dart', 'Body parts',
      'Where on the body an injury was'),
  _Page('/actions/capas/801/report', 'lib/actions/capa_report_screen.dart',
      'The guard keeps working loose',
      'The 8D record of this investigation',
      inset: Spacing.xl),
];

/// Every Screen that is **not** audited, with the reason — so that a Screen this
/// table does not cover is a decision somebody made rather than an omission. The
/// coverage test below fails on a new `*_screen.dart` that is in neither this map
/// nor the table above, and on a stale entry here whose file has been renamed or
/// deleted.
const _excluded = <String, String>{
  'lib/actions/action_detail_screen.dart':
      "its title is the Action's own title, not a page heading",
  'lib/actions/capa_detail_screen.dart':
      "its title is the CAPA's own title, not a page heading",
  'lib/people/employee_detail_screen.dart':
      "its title is the Employee's own name, not a page heading",
  'lib/maintenance/work_order_detail_screen.dart':
      "its title is the Work order's own number, not a page heading",
  'lib/maintenance/store_stock_screen.dart':
      "its title is the Store's own name, not a page heading",
  'lib/quality/nonconformance_detail_screen.dart':
      "its title is the Non-conformance's own number, not a page heading",
  'lib/quality/complaint_detail_screen.dart':
      "its title is the complaint's own Customer and Product, not a page heading",
  'lib/quality/supplier_ncr_detail_screen.dart':
      "its title is the supplier NCR's own Supplier and Product, not a page heading",
  'lib/safety/incident_detail_screen.dart':
      "its title is the Safety incident's own number, not a page heading",
  'lib/maintenance/floor_screen.dart': 'no page frame: a floor surface, not a page',
  'lib/auth/sign_in_screen.dart': 'a centred card on purpose, and no page frame',
  'lib/auth/awaiting_approval_screen.dart': 'a centred card on purpose, and no page frame',
  'lib/platform/access_denied_screen.dart': 'a centred state on purpose',
  'lib/platform/not_found_screen.dart': 'a centred state on purpose',
  'lib/platform/session_error_screen.dart': 'a centred state on purpose',
};

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
      triageRequests: {
        '1': [requestJson('1', 'REQ-1', 'Motor running hot')],
      },
      actions: {
        '1': [actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose')],
      },
      // The Quality Module's two catalogues (issue #203), so both pages render
      // their card rather than an empty state and the row assertion actually
      // runs.
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      // The Customer list and one Site's complaints (issue #214), so both
      // pages render their rows rather than an empty state and the row
      // assertions actually run.
      customers: [customerJson('60', 'CUST-1', 'Acme Bearings')],
      // The Supplier list and one Site's supplier NCRs (issue #215), for the
      // same reason: both pages render their rows rather than an empty state.
      suppliers: [supplierJson('50', 'SUP-1', 'Northwind Fasteners')],
      supplierNcrs: {
        '1': [supplierNcrJson('80', 'SN-2026-00001', responseDueDate: '2099-01-01')],
      },
      // The Safety incident register (issue #226), so the page renders its
      // card rather than an empty state and the row assertion actually runs.
      safetyIncidents: {
        '1': [safetyIncidentJson('901', 'SI-HCM-2026-00001')],
      },
      // The Safety Module's two catalogues (issue #224), for the same reason:
      // each page renders its card rather than an empty state.
      injuryTypes: [injuryTypeJson('61', 'FRA', 'Fracture')],
      bodyParts: [bodyPartJson('71', 'HAND', 'Hand')],
      complaints: {
        '1': [
          customerComplaintJson('70', 'CC-2026-00001', responseDueDate: '2099-01-01'),
        ],
      },
      // The investigation the CAPA report reads (issue #212). Its own read is a
      // CAPA rather than a collection, so this table's one report page finds it
      // by id and renders its sections rather than a loading placeholder.
      capas: {
        '801': capaJson('801', 'CA-HCM-2026-00001', 'The guard keeps working loose',
            orgUnitId: '10', orgUnitName: 'Assembly'),
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
      final expected = box.left + page.inset;

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

  // Coverage, so that adding a Screen is a decision rather than an omission
  // (issue #195). Every Screen in the client is either audited above or named in
  // `_excluded` with a reason; a new file fails here until its author chooses.
  test('every Screen is either audited or excluded by name', () {
    final screens = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('_screen.dart'))
        .toList()
      ..sort();

    final audited = {for (final page in _pages) page.screenFile};
    final uncovered = [
      for (final path in screens)
        if (!audited.contains(path) && !_excluded.containsKey(path))
          '$path: neither audited in page_alignment_test.dart\'s table nor excluded '
              'with a reason. Add it to one of them — an audit means asserting where '
              'its title, description and first row start; an exclusion means saying why '
              'the rule does not apply to it.',
    ];
    expect(uncovered, isEmpty, reason: uncovered.join('\n'));

    // And the other direction: an exclusion for a file that no longer exists hides a
    // Screen from this test rather than describing it.
    final stale = [
      for (final path in _excluded.keys)
        if (!screens.contains(path)) '$path is excluded here but is not a Screen in lib/',
    ];
    expect(stale, isEmpty, reason: stale.join('\n'));
  });
}
