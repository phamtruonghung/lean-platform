/// An Account as the accounts-management Screen needs it (issue #36): the
/// decision an administrator has already made about it, and the Grants it
/// currently holds.
library;

import 'package:flutter/foundation.dart';

import 'org_unit.dart';

/// The three values `approval_status` can take
/// (`backend/src/modules/people/service.js`).
abstract final class ApprovalStatuses {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
}

/// One Grant an Account currently holds, as `GET /api/people/accounts` sends
/// it: the Org Unit itself, the Site it sits in, and the level.
@immutable
class AccountGrant {
  const AccountGrant({
    required this.orgUnitId,
    required this.parentId,
    required this.code,
    required this.name,
    required this.unitType,
    required this.siteId,
    required this.siteName,
    required this.canWrite,
  });

  final String orgUnitId;
  final String? parentId;
  final String code;
  final String name;
  final String unitType;
  final String siteId;
  final String siteName;
  final bool canWrite;

  GrantLevel get level => canWrite ? GrantLevel.viewAndEdit : GrantLevel.view;

  /// This Grant as the picker holds one, so an existing Grant set can be the
  /// state the picker starts in rather than something replayed into it.
  ///
  /// [GrantedOrgUnit.where] is the Site alone, deliberately: ancestor names
  /// are only ever known by walking the tree (see `org_unit.dart`), and a
  /// pre-filled Grant was never walked to. That is exactly what an entry
  /// point's breadcrumb already is today.
  GrantedOrgUnit toGranted() => GrantedOrgUnit(
        orgUnit: OrgUnitNode(
          id: orgUnitId,
          parentId: parentId,
          code: code,
          name: name,
          unitType: unitType,
        ),
        level: level,
        where: siteName,
      );
}

@immutable
class ManagedAccount {
  const ManagedAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.isActive,
    required this.approvalStatus,
    required this.createdAt,
    this.grants = const [],
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final bool isActive;
  final String approvalStatus;

  /// When this Account was created — the Accounts Screen's `Since` column
  /// (issue #112, Decision C). `GET /accounts` has always sent this; nothing
  /// read it client-side until that Screen needed it.
  final DateTime createdAt;
  final List<AccountGrant> grants;

  bool get isPending => approvalStatus == ApprovalStatuses.pending;
  bool get isApproved => approvalStatus == ApprovalStatuses.approved;

  /// What this Account's standing is, in one phrase.
  String get standing => switch (approvalStatus) {
        ApprovalStatuses.rejected => 'Rejected',
        ApprovalStatuses.approved when isActive => 'Active',
        ApprovalStatuses.approved => 'Deactivated',
        _ => 'Awaiting Approval',
      };
}
