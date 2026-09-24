/// The two cost catalogues (issue #252): the rates an hour is costed at and
/// what one unit of a Product is costed at, with an administrator's own write
/// surface over each — the wire faked, the one client seam (ADR-0012,
/// AGENTS.md §5).
///
/// `job_roles_test.dart`'s shape, plus what a versioned catalogue adds: a row
/// carries its period, a closed period is shown rather than hidden, and a new
/// amount from a date is a **revision** — a separate request that closes the old
/// row and opens a new one — not a correction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/cost_rate_form_dialog.dart';
import 'package:lean_platform/people/cost_rates_screen.dart';
import 'package:lean_platform/people/product_cost_form_dialog.dart';
import 'package:lean_platform/people/product_costs_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/app_date_field.dart';
import 'harness.dart';

Future<void> openCostRates(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.costRates,
    );

Future<void> openProductCosts(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.productCosts,
    );

/// The scope list both write tests pick from: a Site, a line beneath it and a
/// press on the line — one of each kind the schema accepts that a fixture can
/// reasonably carry.
List<Map<String, dynamic>> scopeFixtures() => [
      costRateScopeJson('site', '1', 'HCM', 'Ho Chi Minh', siteName: 'Ho Chi Minh'),
      costRateScopeJson('org_unit', '11', 'LINE-1', 'Line 1'),
      costRateScopeJson('asset', '7', 'PRESS-1', 'Press 1'),
      costRateScopeJson('cost_center', '3', 'CC-100', 'Assembly cost centre'),
    ];

/// Picks a date in the currently open `AppDateField` named [name] — the field
/// is read-only by design (ADR-0023), so a date is chosen through the picker
/// the way a person chooses one, never typed.
Future<void> pickDate(WidgetTester tester, String name) async {
  await tapIn(tester, find.byKey(AppDateField.fieldKey(name)));
  await tapIn(tester, find.text('OK'));
}

void main() {
  // -------------------------------------------------------------------------
  // The cost rate catalogue
  // -------------------------------------------------------------------------

  testWidgets('the cost rate catalogue renders every period, closed ones included, for an administrator',
      (tester) async {
    final wire = FakeWire(
      costRates: [
        costRateJson('900', amount: 30, effectiveFrom: '2026-01-01', effectiveTo: '2026-04-01'),
        costRateJson('901', amount: 36, effectiveFrom: '2026-04-01'),
      ],
      costRateScopes: scopeFixtures(),
    );
    await openCostRates(tester, wire);

    expect(find.byType(CostRatesScreen), findsOneWidget);
    // The amount, its currency and the rate type in the plant's own words.
    expect(find.textContaining('Labour, per hour · 30.0 USD'), findsOneWidget);
    expect(find.textContaining('Labour, per hour · 36.0 USD'), findsOneWidget);
    // Each row carries its period, and the closed one says so.
    expect(find.textContaining('2026-01-01 to 2026-04-01'), findsOneWidget);
    expect(find.textContaining('From 2026-04-01'), findsOneWidget);
    expect(find.byKey(CostRatesScreen.closedChipKey('900')), findsOneWidget);
    expect(find.byKey(CostRatesScreen.closedChipKey('901')), findsNothing);
    expect(find.byKey(CostRatesScreen.addKey), findsOneWidget);
  });

  testWidgets('an administrator adds a cost rate by choosing its scope and rate type',
      (tester) async {
    final wire = FakeWire(costRateScopes: scopeFixtures());
    await openCostRates(tester, wire);

    // Nothing set yet: the catalogue says so rather than showing an empty card.
    expect(find.byKey(CostRatesScreen.emptyKey), findsOneWidget);

    await tapIn(tester, find.byKey(CostRatesScreen.addKey));

    // The scope type is chosen from the schema's own four, never typed
    // (ADR-0023) — and choosing one narrows the picker beside it to that kind.
    await tester.tap(find.byKey(CostRateFormDialog.scopeTypeKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.text('Org Unit').last);

    await tester.enterText(find.byKey(CostRateFormDialog.scopeKey), 'Line');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // Only the Org Unit matches: the Site and the press are a different kind.
    expect(find.byKey(CostRateFormDialog.scopeSuggestionKey('11')), findsOneWidget);
    expect(find.byKey(CostRateFormDialog.scopeSuggestionKey('1')), findsNothing);
    await tapIn(tester, find.byKey(CostRateFormDialog.scopeSuggestionKey('11')));

    await tester.tap(find.byKey(CostRateFormDialog.rateTypeKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.text('Machine downtime, per hour').last);

    await tester.enterText(find.byKey(CostRateFormDialog.amountKey), '95');
    await pickDate(tester, 'cost-rate-effective-from');
    await tapIn(tester, find.byKey(CostRateFormDialog.submitKey));

    final sent = wire.costRatePosts.single;
    // The scope type and id come out of one pick, so they cannot disagree.
    expect(sent['scopeType'], 'org_unit');
    expect(sent['scopeId'], '11');
    expect(sent['rateType'], 'machine_downtime_per_hour');
    expect(sent['amount'], 95);
    expect(sent['currency'], 'USD');
    expect(sent['effectiveFrom'], isA<String>());
    // Left blank, the period is open — no `effectiveTo` is sent at all.
    expect(sent.containsKey('effectiveTo'), isFalse);

    expect(find.byType(CostRateFormDialog), findsNothing);
    expect(find.textContaining('Machine downtime, per hour · 95.0 USD'), findsOneWidget);
    expect(find.textContaining('Line 1 · Org Unit'), findsOneWidget);
  });

  testWidgets('correcting a rate sends only the changed field, and closing it sets the end date',
      (tester) async {
    final wire = FakeWire(
      costRates: [costRateJson('900', amount: 30)],
      costRateScopes: scopeFixtures(),
    );
    await openCostRates(tester, wire);

    await tapIn(tester, find.byKey(CostRatesScreen.correctKey('900')));
    expect(find.byType(CostRateFormDialog), findsOneWidget);
    // The two fields resolve_cost_rate finds a rate by are shown but not
    // offered as controls — there is no scope picker and no rate type dropdown
    // on a correction at all.
    expect(find.byKey(CostRateFormDialog.scopeTypeKey), findsNothing);
    expect(find.byKey(CostRateFormDialog.rateTypeKey), findsNothing);
    expect(find.byKey(CostRateFormDialog.scopeKey), findsNothing);
    expect(
      find.textContaining("A rate's scope and rate type cannot be corrected"),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(CostRateFormDialog.amountKey), '31.5');
    await tapIn(tester, find.byKey(CostRateFormDialog.submitKey));

    expect(wire.costRatePatches.single.$1, '900');
    expect(wire.costRatePatches.single.$2, {'amount': 31.5});
    expect(find.byType(CostRateFormDialog), findsNothing);
    expect(find.textContaining('Labour, per hour · 31.5 USD'), findsOneWidget);

    // Closing it is the same correction, setting the day it stops applying.
    await tapIn(tester, find.byKey(CostRatesScreen.correctKey('900')));
    await pickDate(tester, 'cost-rate-effective-to');
    await tapIn(tester, find.byKey(CostRateFormDialog.submitKey));

    expect(wire.costRatePatches.length, 2);
    expect(wire.costRatePatches.last.$2.keys.toList(), ['effectiveTo']);
    expect(wire.costRatePatches.last.$2['effectiveTo'], isA<String>());
    expect(find.byKey(CostRatesScreen.closedChipKey('900')), findsOneWidget);
  });

  testWidgets('revising a rate opens a new period and leaves the old one readable',
      (tester) async {
    final wire = FakeWire(
      costRates: [costRateJson('900', amount: 30, effectiveFrom: '2026-01-01')],
      costRateScopes: scopeFixtures(),
    );
    await openCostRates(tester, wire);

    await tapIn(tester, find.byKey(CostRatesScreen.reviseKey('900')));
    // A revision says what it does to the old row, because that is the whole
    // point of the act.
    expect(
      find.textContaining('It stays readable, and a cost asked for an earlier date'),
      findsOneWidget,
    );
    // It opens blank rather than pre-filled with the old amount: the whole
    // point is a new one.
    expect(find.widgetWithText(TextField, '30.0'), findsNothing);

    await tester.enterText(find.byKey(CostRateFormDialog.amountKey), '36');
    await pickDate(tester, 'cost-rate-effective-from');
    await tapIn(tester, find.byKey(CostRateFormDialog.submitKey));

    // A revision, not a correction — a different request to a different address.
    expect(wire.costRatePatches, isEmpty);
    expect(wire.costRateRevisions.single.$1, '900');
    expect(wire.costRateRevisions.single.$2['amount'], 36);
    expect(wire.costRateRevisions.single.$2['effectiveFrom'], isA<String>());

    // Both periods are on the page afterwards: the old amount is still readable.
    expect(find.textContaining('Labour, per hour · 30.0 USD'), findsOneWidget);
    expect(find.textContaining('Labour, per hour · 36.0 USD'), findsOneWidget);
    expect(find.byKey(CostRatesScreen.closedChipKey('900')), findsOneWidget);
  });

  testWidgets('a refused write keeps the form open and reports why', (tester) async {
    final wire = FakeWire(
      costRates: [costRateJson('900')],
      costRateScopes: scopeFixtures(),
      createCostRateStatus: 400,
      createCostRateMessage:
          'A labor_per_hour rate for this Site already covers part of 2026-06-01 onward.',
    );
    await openCostRates(tester, wire);

    await tapIn(tester, find.byKey(CostRatesScreen.addKey));
    await tester.enterText(find.byKey(CostRateFormDialog.scopeKey), 'Ho Chi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(CostRateFormDialog.scopeSuggestionKey('1')));
    await tester.enterText(find.byKey(CostRateFormDialog.amountKey), '22');
    await pickDate(tester, 'cost-rate-effective-from');
    await tapIn(tester, find.byKey(CostRateFormDialog.submitKey));

    expect(find.byType(CostRateFormDialog), findsOneWidget);
    expect(find.byKey(CostRateFormDialog.failureKey), findsOneWidget);
    expect(find.textContaining('already covers part of 2026-06-01 onward'), findsOneWidget);
  });

  testWidgets('a scope list that could not be read blocks the form rather than letting an id be typed',
      (tester) async {
    final wire = FakeWire(costRates: [costRateJson('900')], costRateScopesStatus: 500);
    await openCostRates(tester, wire);

    // The catalogue itself is perfectly readable — only the writes close.
    expect(find.textContaining('Labour, per hour · 22.5 USD'), findsOneWidget);

    await tapIn(tester, find.byKey(CostRatesScreen.addKey));
    expect(find.byKey(CostRateFormDialog.scopesFailureKey), findsOneWidget);
    final submit = tester.widget<FilledButton>(find.byKey(CostRateFormDialog.submitKey));
    expect(submit.onPressed, isNull);
  });

  testWidgets('a non-administrator sees the cost rate catalogue but no write control',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      costRates: [costRateJson('900')],
      costRateScopes: scopeFixtures(),
    );
    await openCostRates(tester, wire);

    expect(find.textContaining('Labour, per hour · 22.5 USD'), findsOneWidget);
    expect(find.byKey(CostRatesScreen.addKey), findsNothing);
    expect(find.byKey(CostRatesScreen.correctKey('900')), findsNothing);
    expect(find.byKey(CostRatesScreen.reviseKey('900')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // The product standard cost catalogue
  // -------------------------------------------------------------------------

  testWidgets('the standard cost catalogue renders every period, closed ones included',
      (tester) async {
    final wire = FakeWire(
      productCosts: [
        productCostJson('950', standardCost: 5, effectiveFrom: '2026-01-01', effectiveTo: '2026-06-01'),
        productCostJson('951', standardCost: 6, effectiveFrom: '2026-06-01'),
      ],
      costableProducts: [costableProductJson('40', 'PRD-1', 'Gearbox')],
    );
    await openProductCosts(tester, wire);

    expect(find.byType(ProductCostsScreen), findsOneWidget);
    expect(find.textContaining('Gearbox · PRD-1 · 5.0 USD'), findsOneWidget);
    expect(find.textContaining('Gearbox · PRD-1 · 6.0 USD'), findsOneWidget);
    expect(find.text('2026-01-01 to 2026-06-01'), findsOneWidget);
    expect(find.text('From 2026-06-01'), findsOneWidget);
    expect(find.byKey(ProductCostsScreen.closedChipKey('950')), findsOneWidget);
    expect(find.byKey(ProductCostsScreen.closedChipKey('951')), findsNothing);
  });

  testWidgets('an administrator adds a standard cost by choosing its Product', (tester) async {
    final wire = FakeWire(
      costableProducts: [
        costableProductJson('40', 'PRD-1', 'Gearbox'),
        costableProductJson('41', 'PRD-2', 'Housing'),
      ],
    );
    await openProductCosts(tester, wire);

    expect(find.byKey(ProductCostsScreen.emptyKey), findsOneWidget);
    await tapIn(tester, find.byKey(ProductCostsScreen.addKey));

    await tester.enterText(find.byKey(ProductCostFormDialog.productKey), 'Gear');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(ProductCostFormDialog.productSuggestionKey('40')), findsOneWidget);
    expect(find.byKey(ProductCostFormDialog.productSuggestionKey('41')), findsNothing);
    await tapIn(tester, find.byKey(ProductCostFormDialog.productSuggestionKey('40')));

    await tester.enterText(find.byKey(ProductCostFormDialog.costKey), '4.25');
    await tester.enterText(find.byKey(ProductCostFormDialog.currencyKey), 'eur');
    await pickDate(tester, 'product-cost-effective-from');
    await tapIn(tester, find.byKey(ProductCostFormDialog.submitKey));

    final sent = wire.productCostPosts.single;
    expect(sent['productId'], '40');
    expect(sent['standardCost'], 4.25);
    // Normalised on the way out, so the server's own three-letter code check
    // is never the first thing to notice a lower-case entry.
    expect(sent['currency'], 'EUR');
    expect(sent['effectiveFrom'], isA<String>());

    expect(find.byType(ProductCostFormDialog), findsNothing);
    expect(find.textContaining('Gearbox · PRD-1 · 4.25 EUR'), findsOneWidget);
  });

  testWidgets('correcting a standard cost sends only the changed field, and the Product is not offered',
      (tester) async {
    final wire = FakeWire(
      productCosts: [productCostJson('950', standardCost: 5)],
      costableProducts: [costableProductJson('40', 'PRD-1', 'Gearbox')],
    );
    await openProductCosts(tester, wire);

    await tapIn(tester, find.byKey(ProductCostsScreen.correctKey('950')));
    expect(find.byKey(ProductCostFormDialog.productKey), findsNothing);
    expect(
      find.textContaining('The Product a standard cost belongs to cannot be corrected'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(ProductCostFormDialog.costKey), '5.5');
    await tapIn(tester, find.byKey(ProductCostFormDialog.submitKey));

    expect(wire.productCostPatches.single.$1, '950');
    expect(wire.productCostPatches.single.$2, {'standardCost': 5.5});
    expect(find.textContaining('Gearbox · PRD-1 · 5.5 USD'), findsOneWidget);
  });

  testWidgets('revising a standard cost opens a new period and leaves the old one readable',
      (tester) async {
    final wire = FakeWire(
      productCosts: [productCostJson('950', standardCost: 5, effectiveFrom: '2026-01-01')],
      costableProducts: [costableProductJson('40', 'PRD-1', 'Gearbox')],
    );
    await openProductCosts(tester, wire);

    await tapIn(tester, find.byKey(ProductCostsScreen.reviseKey('950')));
    await tester.enterText(find.byKey(ProductCostFormDialog.costKey), '6');
    await pickDate(tester, 'product-cost-effective-from');
    await tapIn(tester, find.byKey(ProductCostFormDialog.submitKey));

    expect(wire.productCostPatches, isEmpty);
    expect(wire.productCostRevisions.single.$1, '950');
    expect(wire.productCostRevisions.single.$2['standardCost'], 6);

    expect(find.textContaining('Gearbox · PRD-1 · 5.0 USD'), findsOneWidget);
    expect(find.textContaining('Gearbox · PRD-1 · 6.0 USD'), findsOneWidget);
    expect(find.byKey(ProductCostsScreen.closedChipKey('950')), findsOneWidget);
  });

  testWidgets('a non-administrator sees the standard cost catalogue but no write control',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      productCosts: [productCostJson('950')],
      costableProducts: [costableProductJson('40', 'PRD-1', 'Gearbox')],
    );
    await openProductCosts(tester, wire);

    expect(find.textContaining('Gearbox · PRD-1 · 4.25 USD'), findsOneWidget);
    expect(find.byKey(ProductCostsScreen.addKey), findsNothing);
    expect(find.byKey(ProductCostsScreen.correctKey('950')), findsNothing);
    expect(find.byKey(ProductCostsScreen.reviseKey('950')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Where the two Screens live
  // -------------------------------------------------------------------------

  test('both Destinations sit under the People group, and only an administrator is offered them',
      () {
    final forAdmin = destinationsFor(role: Roles.admin);
    final costRates =
        forAdmin.firstWhere((destination) => destination.path == Routes.costRates);
    final productCosts =
        forAdmin.firstWhere((destination) => destination.path == Routes.productCosts);

    expect(costRates.group, DestinationGroupNames.people);
    expect(productCosts.group, DestinationGroupNames.people);

    // Filtered away for everyone else — a plant's labour rates are
    // commercially sensitive in a way a job role list is not. The Screens
    // themselves are not gated, because the reads behind them are not.
    for (final role in [Roles.operator, Roles.supervisor, Roles.engineer, Roles.manager]) {
      final paths = destinationsFor(role: role).map((d) => d.path).toSet();
      expect(paths.contains(Routes.costRates), isFalse, reason: '$role is offered Cost rates');
      expect(
        paths.contains(Routes.productCosts),
        isFalse,
        reason: '$role is offered Product standard costs',
      );
    }
  });
}
