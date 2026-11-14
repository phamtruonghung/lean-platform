/// The roles an Account can be given, as a person choosing one needs them.
///
/// Extracted from `admission_dialog.dart` (issue #41) when a second Screen —
/// correcting an admitted Account (issue #36) — had to offer the same list:
/// two copies of the role descriptions would drift the moment one was edited.
///
/// A choice carries the **role code and nothing else**: the words a person
/// reads for it are `l10n/vocabulary.dart`'s (`admissionRoleLabel`,
/// `admissionRoleDescription`), because a list of codes cannot know a
/// language — see ADR-0062.
library;

import 'package:flutter/foundation.dart';

import '../platform/destinations.dart';

@immutable
class RoleChoice {
  const RoleChoice({required this.role});

  final String role;
}

const List<RoleChoice> admissionRoles = [
  RoleChoice(role: Roles.operator),
  RoleChoice(role: Roles.supervisor),
  RoleChoice(role: Roles.engineer),
  RoleChoice(role: Roles.manager),
  RoleChoice(role: Roles.admin),
];
