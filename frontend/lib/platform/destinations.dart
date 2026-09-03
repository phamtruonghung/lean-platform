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
