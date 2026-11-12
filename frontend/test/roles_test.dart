/// The roles editor and the Assign dialog (issue #492, ADR-0061), with the
/// wire faked — the Platform's own frontend test seam (AGENTS.md §5).
///
/// What these tests are for: the sidebar's door is now a **permission code**
/// rather than the role string, and a role's contents are editable. Both are
/// things a person can observe, so both are asserted here — the Shell draws
/// `Roles` for a caller whose `/me` carries `ADM_ROLES_DISPLAY` and not for one
/// whose codes omit it, the editor sends the whole set (not a patch), and the
/// Assign button sends the role id it ticked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/account_roles_dialog.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/role_form_dialog.dart';
import 'package:lean_platform/people/role_permissions_dialog.dart';
import 'package:lean_platform/people/roles_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/status_chip.dart';

import 'harness.dart'
    show
        FakeAuthGateway,
        FakeWire,
        accountJson,
        accountRolesJson,
        appRoleJson,
        permissionJson,
        pumpApp,
        tapIn;

/// The catalogue the fake wire carries: enough to draw two Modules, and the
/// two administration codes the Roles Screen itself is reached through.
List<Map<String, dynamic>> get _catalogue => [
      permissionJson('PPL_DIRECTORY_DISPLAY', module: 'People', label: 'Directory'),
      permissionJson('MTN_WORK_ORDERS_DISPLAY', label: 'Work orders'),
      permissionJson('MTN_WORK_ORDERS_CHANGE', label: 'Maintain Work orders'),
      permissionJson('ADM_ROLES_DISPLAY', module: 'Administration', label: 'Roles'),
      permissionJson('ADM_ROLES_CHANGE', module: 'Administration', label: 'Maintain roles'),
    ];

/// The seeded shape, cut down: the default group, one automatic role, and one
/// ordinary role an administrator could assign.
List<Map<String, dynamic>> _roles() => [
      appRoleJson('1', 'ROLE_STANDARD',
          name: 'Standard',
          isDefault: true,
          permissionCodes: ['PPL_DIRECTORY_DISPLAY'],
          holderCount: 4),
      appRoleJson('2', 'ROLE_SUPERVISOR',
          name: 'Supervisor',
          legacyRole: 'supervisor',
          permissionCodes: ['PPL_DIRECTORY_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY'],
          holderCount: 2),
      appRoleJson('3', 'ROLE_STORE_ROOM',
          name: 'Store room',
          description: 'Counts stock.',
          permissionCodes: ['MTN_WORK_ORDERS_DISPLAY'],
          holderCount: 1),
    ];

/// An administrator whose `/me` carries all five codes, so the Shell's own
/// permission filter offers `Roles`.
FakeWire _wire({
  List<String>? mePermissions,
  List<Map<String, dynamic>>? roles,
  Map<String, Map<String, dynamic>>? accountRoles,
  int setRolePermissionsStatus = 200,
  String setRolePermissionsMessage = 'That role could not be changed.',
  int assignAccountRolesStatus = 200,
}) =>
    FakeWire(
      role: Roles.admin,
      mePermissions: mePermissions ??
          const [
            'PPL_DIRECTORY_DISPLAY',
            'MTN_WORK_ORDERS_DISPLAY',
            'MTN_WORK_ORDERS_CHANGE',
            'ADM_ROLES_DISPLAY',
            'ADM_ROLES_CHANGE',
          ],
      meRoleCodes: const ['ROLE_ADMIN', 'ROLE_STANDARD'],
      roles: roles ?? _roles(),
      permissions: _catalogue,
      accountRoles: accountRoles,
      setRolePermissionsStatus: setRolePermissionsStatus,
      setRolePermissionsMessage: setRolePermissionsMessage,
      assignAccountRolesStatus: assignAccountRolesStatus,
    );

Future<void> _openRoles(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.roles,
    );

Future<void> _openPermissions(WidgetTester tester, String id) =>
    tapIn(tester, find.byKey(RolesScreen.permissionsKey(id)));

void main() {
  // -------------------------------------------------------------------------
  // 1. The sidebar's door is a permission code, not the role string.
  // -------------------------------------------------------------------------

  testWidgets('the Roles destination is offered when the caller holds its code', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: _wire().client,
    );

    expect(find.text('Roles'), findsWidgets);
  });

  testWidgets('the Roles destination is withheld when the codes omit it', (tester) async {
    // An administrator whose codes do not carry ADM_ROLES_DISPLAY: the role
    // string alone no longer opens the door, which is the whole point of
    // ADR-0061. The rest of the Shell is untouched.
    final wire = _wire(mePermissions: const ['PPL_DIRECTORY_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY']);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
    );

    expect(find.text('Directory'), findsWidgets);
    expect(find.text('Roles'), findsNothing);
  });

  testWidgets('the Roles address is locked for a caller without the code', (tester) async {
    final wire = _wire(mePermissions: const ['PPL_DIRECTORY_DISPLAY']);

    await _openRoles(tester, wire);

    // AccessDeniedScreen, not the editor: the address is locked even though the
    // sidebar would have hidden it.
    expect(find.byKey(RolesScreen.addKey), findsNothing);
    expect(find.text('Not available to you'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 2. The editor draws the roles and what they carry.
  // -------------------------------------------------------------------------

  testWidgets('the roles are listed with their codes, identity and size', (tester) async {
    await _openRoles(tester, _wire());

    // Name · CODE, one line per role.
    expect(find.byKey(RolesScreen.nameKey('1')), findsOneWidget);
    expect(find.textContaining('ROLE_STANDARD'), findsWidgets);
    expect(find.textContaining('ROLE_SUPERVISOR'), findsWidgets);

    // The default group is named as such, and the automatic role says what
    // earns it — the two facts that tell an administrator why a box is ticked.
    expect(find.byKey(RolesScreen.defaultChipKey('1')), findsOneWidget);
    expect(find.byKey(RolesScreen.automaticChipKey('2')), findsOneWidget);
    expect(find.text('Automatic: supervisor'), findsWidgets);

    // How much each carries, and who it reaches.
    expect(find.text('1 permission · reaches 4 Accounts'), findsWidgets);
    expect(find.text('2 permissions · reaches 2 Accounts'), findsWidgets);

    // The ordinary role has neither badge.
    expect(find.byKey(RolesScreen.defaultChipKey('3')), findsNothing);
    expect(find.byKey(RolesScreen.automaticChipKey('3')), findsNothing);
  });

  testWidgets('a role with no permissions still reads as a role', (tester) async {
    final wire = _wire(roles: [
      appRoleJson('9', 'ROLE_EMPTY', name: 'Empty', holderCount: 0),
    ]);

    await _openRoles(tester, wire);

    expect(find.text('0 permissions · reaches 0 Accounts'), findsWidgets);
  });

  // -------------------------------------------------------------------------
  // 3. Editing what a role carries — the whole set, replaced.
  // -------------------------------------------------------------------------

  testWidgets('the permission editor starts on the role\'s own set and sends the whole set',
      (tester) async {
    final wire = _wire();
    await _openRoles(tester, wire);
    await _openPermissions(tester, '3');

    // The catalogue is grouped by Module in the server's own order.
    expect(find.byKey(RolePermissionsDialog.moduleKey('People')), findsOneWidget);
    expect(find.byKey(RolePermissionsDialog.moduleKey('Maintenance')), findsOneWidget);
    expect(find.byKey(RolePermissionsDialog.moduleKey('Administration')), findsOneWidget);

    // ROLE_STORE_ROOM carries MTN_WORK_ORDERS_DISPLAY and nothing else.
    expect(tester.widget<CheckboxListTile>(
      find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_DISPLAY')),
    ).value, isTrue);
    expect(tester.widget<CheckboxListTile>(
      find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_CHANGE')),
    ).value, isFalse);
    expect(find.text('1 of 5 permissions'), findsOneWidget);

    // Ticking one more, and unticking the one it had, then Save.
    await tapIn(tester, find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_CHANGE')));
    await tapIn(tester, find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_DISPLAY')));
    expect(find.text('1 of 5 permissions'), findsOneWidget);

    await tapIn(tester, find.byKey(RolePermissionsDialog.submitKey));

    // The whole set, sorted, and only the codes this image knows. Read field by
    // field: a record holding a list compares its fields by identity, so
    // asserting on a literal would be asserting on two different lists.
    expect(wire.rolePermissionPuts.length, 1);
    expect(wire.rolePermissionPuts.single.$1, '3');
    expect(wire.rolePermissionPuts.single.$2, ['MTN_WORK_ORDERS_CHANGE']);

    // The dialog closed and the Screen re-read: the row now says one, and the
    // notice says what happened.
    expect(find.byKey(RolePermissionsDialog.countKey), findsNothing);
    expect(find.byKey(RolesScreen.noticeKey), findsOneWidget);
  });

  testWidgets('Save is disabled until something is actually changed', (tester) async {
    final wire = _wire();
    await _openRoles(tester, wire);
    await _openPermissions(tester, '3');

    expect(
      tester.widget<ButtonStyleButton>(find.byKey(RolePermissionsDialog.submitKey)).onPressed,
      isNull,
    );

    await tapIn(tester, find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_CHANGE')));

    expect(
      tester.widget<ButtonStyleButton>(find.byKey(RolePermissionsDialog.submitKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a refused permission save keeps the dialog open and says why', (tester) async {
    final wire = _wire(
      setRolePermissionsStatus: 403,
      setRolePermissionsMessage: 'This action requires the ADM_ROLES_CHANGE permission.',
    );
    await _openRoles(tester, wire);
    await _openPermissions(tester, '3');

    await tapIn(tester, find.byKey(RolePermissionsDialog.checkboxKey('MTN_WORK_ORDERS_CHANGE')));
    await tapIn(tester, find.byKey(RolePermissionsDialog.submitKey));

    expect(find.byKey(RolePermissionsDialog.failureKey), findsOneWidget);
    expect(find.text('This action requires the ADM_ROLES_CHANGE permission.'), findsOneWidget);
    // Still open, so the administrator can see what they had ticked.
    expect(find.byKey(RolePermissionsDialog.countKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 4. Creating a role, and retiring one.
  // -------------------------------------------------------------------------

  testWidgets('a new role is created from a code and a name', (tester) async {
    final wire = _wire();
    await _openRoles(tester, wire);

    await tapIn(tester, find.byKey(RolesScreen.addKey));
    await tester.enterText(find.byKey(RoleFormDialog.codeKey), 'role_tool_crib');
    await tester.enterText(find.byKey(RoleFormDialog.nameKey), 'Tool crib');
    await tester.enterText(find.byKey(RoleFormDialog.descriptionKey), 'Issues tools.');
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(RoleFormDialog.submitKey));

    expect(wire.rolePosts, [
      {'code': 'role_tool_crib', 'name': 'Tool crib', 'description': 'Issues tools.', 'permissions': []},
    ]);
    // The server's own normalisation is what the row shows.
    expect(find.textContaining('ROLE_TOOL_CRIB'), findsWidgets);
  });

  testWidgets('Add is disabled until both a code and a name are present', (tester) async {
    final wire = _wire();
    await _openRoles(tester, wire);
    await tapIn(tester, find.byKey(RolesScreen.addKey));

    expect(
      tester.widget<ButtonStyleButton>(find.byKey(RoleFormDialog.submitKey)).onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(RoleFormDialog.codeKey), 'ROLE_HALF');
    await tester.pumpAndSettle();

    expect(
      tester.widget<ButtonStyleButton>(find.byKey(RoleFormDialog.submitKey)).onPressed,
      isNull,
    );
  });

  testWidgets('retiring a role sends only the flag that changed', (tester) async {
    final wire = _wire();
    await _openRoles(tester, wire);

    await tapIn(tester, find.byKey(RolesScreen.correctKey('3')));
    // The code is the role's identity: it is shown but not editable.
    expect(
      tester.widget<TextField>(find.byKey(RoleFormDialog.codeKey)).enabled,
      isFalse,
    );
    await tapIn(tester, find.byKey(RoleFormDialog.activeKey));
    await tapIn(tester, find.byKey(RoleFormDialog.submitKey));

    expect(wire.rolePatches.length, 1);
    expect(wire.rolePatches.single.$1, '3');
    expect(wire.rolePatches.single.$2, <String, Object?>{'isActive': false});
    expect(find.byKey(RolesScreen.inactiveChipKey('3')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 5. The Assign dialog on the Accounts Screen.
  // -------------------------------------------------------------------------

  testWidgets('assigning a role sends the role id, and the automatic ones are not assignable',
      (tester) async {
    final wire = _wire(
      accountRoles: {
        '8': accountRolesJson(
          '8',
          accountRole: 'operator',
          roles: [
            appRoleJson('1', 'ROLE_STANDARD',
                name: 'Standard', isDefault: true, isAutomatic: true, holderCount: 4),
            appRoleJson('2', 'ROLE_OPERATOR',
                name: 'Operator', legacyRole: 'operator', isAutomatic: true, holderCount: 2),
            appRoleJson('3', 'ROLE_STORE_ROOM', name: 'Store room', holderCount: 1),
          ],
        ),
      },
    );
    wire.accounts = [
      accountJson('8', 'store@example.com'),
    ];

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

    await tapIn(tester, find.byKey(AccountsScreen.rolesKey('8')));

    // The two automatic groups are drawn ticked and disabled; the ordinary one
    // is an ordinary checkbox.
    expect(tester.widget<CheckboxListTile>(
      find.byKey(AccountRolesDialog.automaticKey('1')),
    ).onChanged, isNull);
    expect(tester.widget<CheckboxListTile>(
      find.byKey(AccountRolesDialog.checkboxKey('3')),
    ).value, isFalse);
    expect(find.text('0 roles assigned'), findsOneWidget);

    await tapIn(tester, find.byKey(AccountRolesDialog.checkboxKey('3')));
    await tapIn(tester, find.byKey(AccountRolesDialog.submitKey));

    expect(wire.accountRolePuts.length, 1);
    expect(wire.accountRolePuts.single.$1, '8');
    expect(wire.accountRolePuts.single.$2, ['3']);
  });

  testWidgets('a refused assignment says why and stays open', (tester) async {
    final wire = _wire(
      assignAccountRolesStatus: 400,
      accountRoles: {
        '8': accountRolesJson('8', roles: [
          appRoleJson('3', 'ROLE_STORE_ROOM', name: 'Store room'),
        ]),
      },
    );
    wire.accounts = [accountJson('8', 'store@example.com')];
    wire.assignAccountRolesMessage =
        'ROLE_STANDARD is held automatically by the Accounts it applies to and is not assignable';

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

    await tapIn(tester, find.byKey(AccountsScreen.rolesKey('8')));
    await tapIn(tester, find.byKey(AccountRolesDialog.checkboxKey('3')));
    await tapIn(tester, find.byKey(AccountRolesDialog.submitKey));

    expect(find.byKey(AccountRolesDialog.failureKey), findsOneWidget);
    expect(
      find.text('ROLE_STANDARD is held automatically by the Accounts it applies to and is not assignable'),
      findsOneWidget,
    );
  });

  testWidgets('the Roles control is absent on the caller\'s own row', (tester) async {
    final wire = _wire();
    wire.accounts = [
      accountJson('1', 'me@example.com', role: Roles.admin),
      accountJson('8', 'store@example.com'),
    ];

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

    expect(find.byKey(AccountsScreen.rolesKey('1')), findsNothing);
    expect(find.byKey(AccountsScreen.rolesKey('8')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 6. The badges are `StatusChip`s — read through the widget, not the string,
  //    so a test above cannot pass on prose that merely looks like a badge.
  // -------------------------------------------------------------------------

  testWidgets('the default and automatic badges are chips, not prose', (tester) async {
    await _openRoles(tester, _wire());

    expect(tester.widget<StatusChip>(find.byKey(RolesScreen.defaultChipKey('1'))).label,
        'Default group');
    expect(tester.widget<StatusChip>(find.byKey(RolesScreen.automaticChipKey('2'))).label,
        'Automatic: supervisor');
  });
}
