/// The places an admitted Account can go, and which Accounts earn them.
///
/// Destinations name what a person does — the Directory, the Approval queue —
/// never the Module they belong to: nobody navigates to "People" (issue #39).
library;

import 'package:flutter/material.dart';

import 'router.dart';

/// The role strings the API answers with, mirroring the backend's own `ROLES`
/// (`backend/src/modules/people/authorization.js`).
abstract final class Roles {
  static const String operator = 'operator';
  static const String supervisor = 'supervisor';
  static const String engineer = 'engineer';
  static const String manager = 'manager';
  static const String admin = 'admin';
}

/// The roles that earn a whole Module, named once so the sidebar and the
/// route guard cannot disagree about who is let in. Maintenance is offered to
/// supervisor, engineer, manager and administrator, and not to operator: the
/// workflow an operator needs is raising a request, which this Module does not
/// build yet, and a Screen where every write would be refused is exactly what
/// the Approval queue and the Accounts Screen already avoid (#55).
abstract final class ModuleRoles {
  static const Set<String> maintenance = {
    Roles.supervisor,
    Roles.engineer,
    Roles.manager,
    Roles.admin,
  };
}

/// One entry in the Shell's sidebar.
@immutable
class Destination {
  const Destination({
    required this.label,
    required this.icon,
    required this.path,
    this.roles,
  });

  final String label;
  final IconData icon;
  final String path;

  /// The roles that earn this destination, or null for one every admitted
  /// Account may reach.
  final Set<String>? roles;

  bool isVisibleTo(String role) => roles == null || roles!.contains(role);

  /// Whether [location] is this destination or something beneath it.
  bool matches(String location) =>
      location == path || (path != '/' && location.startsWith('$path/'));
}

const List<Destination> platformDestinations = [
  Destination(label: 'Home', icon: Icons.home_outlined, path: Routes.home),
  Destination(
    label: 'Approvals',
    icon: Icons.how_to_reg_outlined,
    path: Routes.approvals,
    roles: {Roles.admin},
  ),
  Destination(
    label: 'Assets',
    icon: Icons.precision_manufacturing_outlined,
    path: Routes.assets,
    roles: ModuleRoles.maintenance,
  ),
  Destination(
    label: 'Work orders',
    icon: Icons.build_outlined,
    path: Routes.workOrders,
    roles: ModuleRoles.maintenance,
  ),
  Destination(
    label: 'Accounts',
    icon: Icons.manage_accounts_outlined,
    path: Routes.accounts,
    roles: {Roles.admin},
  ),
];

/// The destinations an Account holding [role] may use.
List<Destination> destinationsFor({
  required String role,
  List<Destination> destinations = platformDestinations,
}) {
  return [
    for (final destination in destinations)
      if (destination.isVisibleTo(role)) destination,
  ];
}
