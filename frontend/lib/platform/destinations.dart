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
/// route guard cannot disagree about who is let in. Maintenance's decision
/// surfaces — Assets, Work orders, Triage — are offered to supervisor,
/// engineer, manager and administrator, and not to operator (issue #72): an
/// operator's whole Maintenance surface is the Requests Destination, which
/// every admitted Account earns, and which lets them ask and follow without
/// any decision surface that would refuse every write they could make (#55).
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
  // Requests is the one Maintenance Destination every admitted Account earns,
  // including an operator: it is how anyone on the floor asks maintenance to
  // look at something and follows what became of the ask (issue #72). The
  // maintenance-only surfaces — Assets, Work orders, Triage — sit behind
  // `ModuleRoles.maintenance`, so an operator is offered the asking surface
  // and never the deciding ones.
  Destination(
    label: 'Requests',
    icon: Icons.rule_folder_outlined,
    path: Routes.requests,
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
    label: 'Triage',
    icon: Icons.playlist_add_check_circle_outlined,
    path: Routes.triage,
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
