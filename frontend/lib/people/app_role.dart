/// What an Account may do, as the roles editor and the Assign dialog read it
/// (issue #492, ADR-0061).
///
/// Three shapes, matching the backend's own three:
///
///   - [Permission] — one entry of the catalogue (`GET /api/people/permissions`).
///     A **code** the Platform's code checks against, with the Module it files
///     under and the sentence an administrator reads. Never created from this
///     client: `permissions.js` is where a code comes into existence.
///   - [AppRole] — a group of those codes with a code of its own (`ROLE_…`),
///     which is the thing an administrator edits and assigns.
///   - [AccountRoles] — one Account's view of every role: which it holds
///     automatically ([AppRole.isAutomatic] — the default group and the role
///     its own `app_users.role` earns), which an administrator assigned
///     ([AppRole.isAssigned]), and which are on offer.
library;

import 'package:flutter/foundation.dart';

/// One permission in the catalogue.
@immutable
class Permission {
  const Permission({
    required this.code,
    required this.module,
    required this.label,
    required this.description,
  });

  /// The stable identifier — `PPL_DIRECTORY_DISPLAY`, `ADM_ROLES_CHANGE`. What
  /// the server checks and what a test asserts on; a label may be reworded.
  final String code;

  /// The Module that owns the function, in the sidebar's own words
  /// (`People`, `Maintenance`, …). The editor groups by this.
  final String module;

  /// What the function is called on a Screen.
  final String label;

  /// The one sentence an administrator reads before ticking it.
  final String description;
}

/// A role: a code, a name, and the permissions it carries.
@immutable
class AppRole {
  const AppRole({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.isDefault,
    required this.legacyRole,
    required this.isActive,
    required this.permissionCodes,
    required this.holderCount,
    this.isAutomatic = false,
    this.isAssigned = false,
  });

  final String id;
  final String code;
  final String name;
  final String description;

  /// The group every Account holds whether or not anything was assigned —
  /// "nhóm chức năng mặc định". At most one role carries this.
  final bool isDefault;

  /// The `app_users.role` value this role is granted by, or null for a role an
  /// administrator assigns one Account at a time.
  final String? legacyRole;

  final bool isActive;

  /// The codes this role carries, as the server last stored them.
  final Set<String> permissionCodes;

  /// How many Accounts the role reaches: every Account for the default role,
  /// every Account holding that account role for an automatic one, and the
  /// assignments for an ordinary one.
  final int holderCount;

  /// Whether an Account's own `app_users.role` (or the default group) already
  /// earns this role. Only meaningful in an [AccountRoles] answer, where a
  /// checkbox for it is drawn ticked and disabled.
  final bool isAutomatic;

  /// Whether an administrator has assigned this role to the Account in
  /// question. Only meaningful in an [AccountRoles] answer.
  final bool isAssigned;

  bool get carriesAdministration => permissionCodes.any((code) => code.startsWith('ADM_'));

  AppRole copyWith({Set<String>? permissionCodes}) => AppRole(
        id: id,
        code: code,
        name: name,
        description: description,
        isDefault: isDefault,
        legacyRole: legacyRole,
        isActive: isActive,
        permissionCodes: permissionCodes ?? this.permissionCodes,
        holderCount: holderCount,
        isAutomatic: isAutomatic,
        isAssigned: isAssigned,
      );
}

/// One Account's roles, as `GET /api/people/accounts/:id/roles` answers.
@immutable
class AccountRoles {
  const AccountRoles({
    required this.accountId,
    required this.accountRole,
    required this.roles,
  });

  final String accountId;

  /// The Account's own `app_users.role` — what the automatic roles are derived
  /// from, shown so the dialog can say why a box is already ticked.
  final String accountRole;

  final List<AppRole> roles;

  /// The roles an administrator can actually give or take away.
  List<AppRole> get assignable => roles.where((role) => !role.isAutomatic).toList(growable: false);

  /// The roles this Account holds automatically, in the server's order.
  List<AppRole> get automatic => roles.where((role) => role.isAutomatic).toList(growable: false);

  /// The explicit assignments as they stand — what the dialog's checkboxes
  /// start on and what the Assign button sends back.
  List<String> get assignedIds =>
      [for (final role in roles) if (role.isAssigned) role.id];

  /// The effective permission codes, for showing what the Account can do after
  /// an assignment without asking `/me` again: the union of every role it
  /// holds, automatic ones included.
  Set<String> get effectivePermissionCodes => {
        for (final role in roles)
          if (role.isAutomatic || role.isAssigned) ...role.permissionCodes,
      };
}
