/// The roles an Account can be given, as a person choosing one needs them.
///
/// Extracted from `admission_dialog.dart` (issue #41) when a second Screen —
/// correcting an admitted Account (issue #36) — had to offer the same list:
/// two copies of the role descriptions would drift the moment one was edited.
library;

import 'package:flutter/foundation.dart';

import '../platform/destinations.dart';

@immutable
class RoleChoice {
  const RoleChoice({required this.role, required this.label, required this.description});

  final String role;
  final String label;
  final String description;
}

const List<RoleChoice> admissionRoles = [
  RoleChoice(
    role: Roles.operator,
    label: 'Operator',
    description: 'Works in the Org Units this Account is granted.',
  ),
  RoleChoice(
    role: Roles.supervisor,
    label: 'Supervisor',
    description: 'Runs the Org Units this Account is granted, and the people in them.',
  ),
  RoleChoice(
    role: Roles.engineer,
    label: 'Engineer',
    description: 'Improves the Org Units this Account is granted.',
  ),
  RoleChoice(
    role: Roles.manager,
    label: 'Manager',
    description: 'Oversees the Org Units this Account is granted.',
  ),
  RoleChoice(
    role: Roles.admin,
    label: 'Administrator',
    description: 'Acts everywhere, in every Site, with no Org Unit Grants at all.',
  ),
];

/// The label for [role], or the raw string when the server sends one this
/// client does not know.
String roleLabel(String role) {
  for (final choice in admissionRoles) {
    if (choice.role == role) return choice.label;
  }
  return role;
}
