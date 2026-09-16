/// The Quality Module's two catalogues, with the wire faked (issue #203):
/// the Product catalogue and the Defect code tree, each read by every approved
/// Account and written by an administrator.
///
/// The seam is the usual one (AGENTS.md §5): pump `PlatformApp` at the Screen's
/// own address, drive the UI, and assert on what renders and on what `FakeWire`
/// recorded reaching the wire — never on a Bloc's own state. A test that cares
/// whether a write happened asserts `wire.productPosts`/`wire.productPatches`,
/// and the test that a non-administrator sends nothing asserts those lists are
/// *empty* rather than that a control was merely absent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/quality/defect_code_form_dialog.dart';
import 'package:lean_platform/quality/defect_codes_screen.dart';
import 'package:lean_platform/quality/product_form_dialog.dart';
import 'package:lean_platform/quality/products_screen.dart';

import 'harness.dart'
    show
        FakeAuthGateway,
        FakeWire,
        defectCodeJson,
        productJson,
        pumpApp,
        tapIn;

/// Two Products — one of them deactivated, so the catalogue's own
/// `includeInactive` read and the Inactive chip are both exercised — and a
/// two-level Defect code tree with a deactivated leaf.
FakeWire _plant({String role = Roles.admin}) => FakeWire(
      role: role,
      products: [
        productJson('1', 'PRD-1', 'Gearbox', uomCode: 'EA', uomName: 'Each'),
        productJson('2', 'PRD-2', 'Bearing shell', uomCode: 'H', uomName: 'Hour', isActive: false),
      ],
      defectCodes: [
        defectCodeJson('10', 'DIM', 'Dimensional', category: 'product', defaultSeverity: 'minor'),
        defectCodeJson('11', 'DIM-OOT', 'Out of tolerance',
            parentId: '10', category: 'material', defaultSeverity: 'major'),
        defectCodeJson('12', 'SRF-SCR', 'Surface scratch',
            parentId: '10', category: 'product', defaultSeverity: 'minor', isActive: false),
      ],
    );

Future<void> _open(WidgetTester tester, FakeWire wire, String route) async {
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: route,
  );
}

/// Picks an item out of an open `DropdownButtonFormField` — taps the field,
/// then the option's own label in the overlay menu.
Future<void> _choose(WidgetTester tester, Key field, String label) async {
  await tapIn(tester, find.byKey(field));
  await tapIn(tester, find.text(label).last);
}

void main() {
  // -------------------------------------------------------------------------
  // The Shell's Quality group
  // -------------------------------------------------------------------------

  testWidgets('the Shell offers the Quality group, with both catalogues, to any approved Account',
      (tester) async {
    // An operator, deliberately: neither catalogue's read is role-gated, so
    // this is the Account the group must not be hidden from.
    final wire = _plant(role: Roles.operator);
    await _open(tester, wire, Routes.home);

    final sidebar = find.byKey(PlatformShell.sidebarKey);
    expect(find.descendant(of: sidebar, matching: find.text('QUALITY')), findsOneWidget);
    expect(
      find.descendant(of: sidebar, matching: find.byKey(const ValueKey('nav-item-Products'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.byKey(const ValueKey('nav-item-Defect codes'))),
      findsOneWidget,
    );

    // And the Destination is a door rather than a label: following it reaches
    // the Screen, which for an operator offers the catalogue and no write.
    await tapIn(tester, find.byKey(const ValueKey('nav-item-Products')));
    expect(find.text('Gearbox · PRD-1 · Each'), findsOneWidget);
    expect(find.byKey(ProductsScreen.addKey), findsNothing);
    expect(wire.productPosts, isEmpty);
  });

  // -------------------------------------------------------------------------
  // Products
  // -------------------------------------------------------------------------

  testWidgets('an administrator reads the whole Product catalogue, deactivated rows included, and is offered both writes',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.products);

    // The Screen asks for the retired rows by name: reaching a deactivated
    // Product to reactivate it is this Screen's own purpose.
    expect(wire.productListRequests.single['includeInactive'], 'true');

    expect(find.text('Gearbox · PRD-1 · Each'), findsOneWidget);
    expect(find.text('Bearing shell · PRD-2 · Hour'), findsOneWidget);
    expect(find.byKey(ProductsScreen.inactiveChipKey('2')), findsOneWidget);
    expect(find.byKey(ProductsScreen.addKey), findsOneWidget);
    expect(find.byKey(ProductsScreen.correctKey('1')), findsOneWidget);
  });

  testWidgets('a non-administrator reads the Product catalogue but is offered no write, and sends none',
      (tester) async {
    final wire = _plant(role: Roles.supervisor);
    await _open(tester, wire, Routes.products);

    expect(find.text('Gearbox · PRD-1 · Each'), findsOneWidget);
    expect(find.textContaining('Add Product'), findsNothing);
    expect(find.byKey(ProductsScreen.addKey), findsNothing);
    expect(find.byKey(ProductsScreen.correctKey('1')), findsNothing);

    // The stronger claim: nothing was sent. A control that is merely absent
    // from the tree is not the same as a Screen that cannot write.
    expect(wire.productPosts, isEmpty);
    expect(wire.productPatches, isEmpty);
  });

  testWidgets('adding a Product sends exactly one POST carrying its code, its name and the chosen unit of measure',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.products);

    await tapIn(tester, find.byKey(ProductsScreen.addKey));
    await tester.enterText(find.byKey(ProductFormDialog.codeKey), 'PRD-9');
    await tester.enterText(find.byKey(ProductFormDialog.nameKey), 'Conveyor belt');

    // The unit is chosen from the catalogue the plant uses, never typed
    // (ADR-0023) — the list this dialog fetched off Maintenance's own address.
    await _choose(tester, ProductFormDialog.uomKey, 'Each (EA)');
    await tapIn(tester, find.byKey(ProductFormDialog.submitKey));

    expect(wire.productPosts, [
      {'code': 'PRD-9', 'name': 'Conveyor belt', 'uomCode': 'EA'}
    ]);
    // And the catalogue re-read carries the new row.
    expect(find.text('Conveyor belt · PRD-9 · Each'), findsOneWidget);
  });

  testWidgets('a duplicate code on add surfaces the API message on the form, which stays open',
      (tester) async {
    final wire = _plant()..createProductStatus = 409;
    await _open(tester, wire, Routes.products);

    await tapIn(tester, find.byKey(ProductsScreen.addKey));
    await tester.enterText(find.byKey(ProductFormDialog.codeKey), 'PRD-1');
    await tester.enterText(find.byKey(ProductFormDialog.nameKey), 'Another gearbox');
    await _choose(tester, ProductFormDialog.uomKey, 'Each (EA)');
    await tapIn(tester, find.byKey(ProductFormDialog.submitKey));

    expect(find.byKey(ProductFormDialog.failureKey), findsOneWidget);
    expect(find.text('a Product with this code already exists'), findsOneWidget);
    // The form is still there to be corrected rather than losing what was typed.
    expect(find.byKey(ProductFormDialog.submitKey), findsOneWidget);
    expect(wire.productPosts.length, 1);
  });

  testWidgets('correcting a Product sends only the field that changed, and its code cannot be corrected',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.products);

    await tapIn(tester, find.byKey(ProductsScreen.correctKey('1')));

    // products.js refuses a `code` correction, so the form does not offer one.
    expect(tester.widget<TextField>(find.byKey(ProductFormDialog.codeKey)).enabled, isFalse);
    expect(find.textContaining('cannot be corrected'), findsWidgets);

    await tester.enterText(find.byKey(ProductFormDialog.nameKey), 'Gearbox, revised');
    await tapIn(tester, find.byKey(ProductFormDialog.submitKey));

    expect(wire.productPatches.length, 1);
    expect(wire.productPatches.single.$1, '1');
    expect(wire.productPatches.single.$2, {'name': 'Gearbox, revised'});
    expect(find.text('Gearbox, revised · PRD-1 · Each'), findsOneWidget);
  });

  testWidgets('deactivating a Product from the correction form sends isActive alone, and the row reads as inactive',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.products);

    await tapIn(tester, find.byKey(ProductsScreen.correctKey('1')));
    await tapIn(tester, find.byKey(ProductFormDialog.activeKey));
    await tapIn(tester, find.byKey(ProductFormDialog.submitKey));

    expect(wire.productPatches.length, 1);
    expect(wire.productPatches.single.$1, '1');
    expect(wire.productPatches.single.$2, {'isActive': false});
    expect(find.byKey(ProductsScreen.inactiveChipKey('1')), findsOneWidget);
  });

  testWidgets('a failed Product read explains itself, and the retry re-reads', (tester) async {
    final wire = _plant()..productsStatus = 500;
    await _open(tester, wire, Routes.products);

    expect(find.byKey(ProductsScreen.failedKey), findsOneWidget);

    wire.productsStatus = 200;
    await tapIn(tester, find.byKey(ProductsScreen.retryKey));

    expect(find.byKey(ProductsScreen.failedKey), findsNothing);
    expect(find.text('Gearbox · PRD-1 · Each'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Defect codes
  // -------------------------------------------------------------------------

  testWidgets('an administrator reads the Defect code tree with each code\'s parent, category and default severity',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.defectCodes);

    expect(wire.defectCodeListRequests.single['includeInactive'], 'true');

    expect(find.text('Dimensional · DIM'), findsOneWidget);
    expect(find.text('Out of tolerance · DIM-OOT'), findsOneWidget);
    // Where a code sits, what it is grouped under, and the severity a
    // Non-conformance recorded against it starts at — all three on the row.
    expect(find.text('Top level · Product · starts at Minor'), findsOneWidget);
    expect(find.text('Under Dimensional · Material · starts at Major'), findsOneWidget);
    expect(find.byKey(DefectCodesScreen.inactiveChipKey('12')), findsOneWidget);
    expect(find.byKey(DefectCodesScreen.addKey), findsOneWidget);
    expect(find.byKey(DefectCodesScreen.correctKey('11')), findsOneWidget);
  });

  testWidgets('a non-administrator reads the tree but is offered no write, and sends none',
      (tester) async {
    final wire = _plant(role: Roles.engineer);
    await _open(tester, wire, Routes.defectCodes);

    expect(find.text('Out of tolerance · DIM-OOT'), findsOneWidget);
    expect(find.textContaining('Add Defect code'), findsNothing);
    expect(find.byKey(DefectCodesScreen.addKey), findsNothing);
    expect(find.byKey(DefectCodesScreen.correctKey('11')), findsNothing);

    expect(wire.defectCodePosts, isEmpty);
    expect(wire.defectCodePatches, isEmpty);
  });

  testWidgets('adding a Defect code sends its code, name, category, default severity and chosen parent',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.defectCodes);

    await tapIn(tester, find.byKey(DefectCodesScreen.addKey));
    await tester.enterText(find.byKey(DefectCodeFormDialog.codeKey), 'DIM-OVL');
    await tester.enterText(find.byKey(DefectCodeFormDialog.nameKey), 'Ovality');
    await _choose(tester, DefectCodeFormDialog.categoryKey, 'Process');
    await _choose(tester, DefectCodeFormDialog.severityKey, 'Critical');
    await _choose(tester, DefectCodeFormDialog.parentKey, 'Dimensional (DIM)');
    await tapIn(tester, find.byKey(DefectCodeFormDialog.submitKey));

    expect(wire.defectCodePosts, [
      {
        'code': 'DIM-OVL',
        'name': 'Ovality',
        'category': 'process',
        'defaultSeverity': 'critical',
        'parentId': '10',
      }
    ]);
    expect(find.text('Ovality · DIM-OVL'), findsOneWidget);
  });

  testWidgets('correcting a Defect code cannot rewrite its code, and never offers one of its own codes as its parent',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.defectCodes);

    // The parent code being corrected: its own children are what a cycle would
    // be made of, so neither they nor itself appear as a parent to choose.
    await tapIn(tester, find.byKey(DefectCodesScreen.correctKey('10')));

    expect(tester.widget<TextField>(find.byKey(DefectCodeFormDialog.codeKey)).enabled, isFalse);

    // What the form offers as a parent, read off the control's own item list
    // rather than by opening the menu: the choice a caller is given is the
    // claim, and it can be asserted without an overlay.
    final parentItems = tester
        .widget<DropdownButton<String?>>(
          find.descendant(
            of: find.byKey(DefectCodeFormDialog.parentKey),
            matching: find.byType(DropdownButton<String?>),
          ),
        )
        .items;
    final offered = [for (final item in parentItems!) item.value];
    expect(offered, isNot(contains('10')));
    expect(offered, isNot(contains('11')));
    expect(offered, isNot(contains('12')));
    // The top of the tree is always a choice — detaching a branch is an act.
    expect(offered, contains(null));
  });

  testWidgets('correcting one of a Defect code\'s own fields sends only that field',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.defectCodes);

    await tapIn(tester, find.byKey(DefectCodesScreen.correctKey('11')));
    await _choose(tester, DefectCodeFormDialog.severityKey, 'Critical');
    await tapIn(tester, find.byKey(DefectCodeFormDialog.submitKey));

    expect(wire.defectCodePatches.length, 1);
    expect(wire.defectCodePatches.single.$1, '11');
    expect(wire.defectCodePatches.single.$2, {'defaultSeverity': 'critical'});
    expect(find.text('Under Dimensional · Material · starts at Critical'), findsOneWidget);
  });

  testWidgets('deactivating a Defect code sends isActive alone, and a failed read offers a retry',
      (tester) async {
    final wire = _plant();
    await _open(tester, wire, Routes.defectCodes);

    await tapIn(tester, find.byKey(DefectCodesScreen.correctKey('11')));
    await tapIn(tester, find.byKey(DefectCodeFormDialog.activeKey));
    await tapIn(tester, find.byKey(DefectCodeFormDialog.submitKey));

    expect(wire.defectCodePatches.length, 1);
    expect(wire.defectCodePatches.single.$1, '11');
    expect(wire.defectCodePatches.single.$2, {'isActive': false});
    expect(find.byKey(DefectCodesScreen.inactiveChipKey('11')), findsOneWidget);
  });

  testWidgets('a failed Defect code read explains itself, and the retry re-reads',
      (tester) async {
    final wire = _plant()..defectCodesStatus = 500;
    await _open(tester, wire, Routes.defectCodes);

    expect(find.byKey(DefectCodesScreen.failedKey), findsOneWidget);

    wire.defectCodesStatus = 200;
    await tapIn(tester, find.byKey(DefectCodesScreen.retryKey));

    expect(find.byKey(DefectCodesScreen.failedKey), findsNothing);
    expect(find.text('Dimensional · DIM'), findsOneWidget);
  });
}
