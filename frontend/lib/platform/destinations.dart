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
  // Offered to every approved Account — no `roles` set, the same "everyone
  // admitted may reach this" shape Home already uses. ADR-0009 is exactly
  // the decision that a plant directory is not a secret gated by role.
  Destination(label: 'Directory', icon: Icons.people_outline, path: Routes.directory),
  // Also offered to every approved Account, for the same reason (issue #88):
  // `GET /job-roles` carries no admin or scope check of its own
  // (job-role-routes.js's own header), and it is what the Directory's own
  // job role filter and every Assignment's job role choice already read —
  // hiding the destination behind a role would gate a Screen the route
  // itself never refuses. Only the write affordances inside the Screen are
  // gated to an administrator.
  Destination(label: 'Job roles', icon: Icons.badge_outlined, path: Routes.jobRoles),
  // Also offered to every approved Account, for the same reason (issue #89):
  // `GET /skills` carries no admin or scope check of its own
  // (skill-routes.js's own header). Only the write affordances inside the
  // Screen are gated to an administrator.
  Destination(label: 'Skills', icon: Icons.verified_outlined, path: Routes.skills),
  // Also offered to every approved Account, for the same reason (issue #90):
  // neither `GET /sites` nor `GET .../org-units` carries an admin or scope
  // check of its own (ADR-0009's "a plant directory is not a secret" applies
  // here too). Only the write affordances inside the Screen are gated —
  // creating a root Org Unit to an administrator (ADR-0008), everything else
  // to the server's own scope check.
  Destination(label: 'Org Units', icon: Icons.account_tree_outlined, path: Routes.orgUnits),
  Destination(
    label: 'Approvals',
    icon: Icons.how_to_reg_outlined,
    path: Routes.approvals,
    roles: {Roles.admin},
  ),
  // Administrator only (issue #89) — `GET .../skill-coverage` is deliberately
  // narrower than every other Site-shaped read in the People Module
  // (skill-routes.js's own header: "how the plant is being run", not "who
  // works here"), the same reasoning that keeps `Accounts` administrator-only
  // below.
  Destination(
    label: 'Skill coverage',
    icon: Icons.query_stats_outlined,
    path: Routes.skillCoverage,
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
