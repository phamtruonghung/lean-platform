/// Where an Account may work, as `GET /api/people/me` answers it.
///
/// An administrator reaches every Site by virtue of the role and holds no
/// Grants at all, so [everywhere] is the answer and [grants] is empty — never
/// read an empty [grants] as "nowhere" without checking [everywhere] first.
///
/// These are the caller's raw Grants, not their entry points. "Where does my
/// scope begin in *this* Site's tree" is a per-Site question the API answers
/// on demand from `GET /sites/:siteId/org-units` with no parentId (ADR-0008);
/// nothing here re-derives it.
library;

import 'package:flutter/foundation.dart';

@immutable
class OrgUnitGrant {
  const OrgUnitGrant({
    required this.orgUnitId,
    required this.siteId,
    required this.canWrite,
  });

  final String orgUnitId;
  final String siteId;
  final bool canWrite;
}

@immutable
class OrgUnitScope {
  const OrgUnitScope({required this.everywhere, required this.grants});

  /// No Grants and not an administrator: this Account reaches nothing yet.
  const OrgUnitScope.nowhere()
      : everywhere = false,
        grants = const [];

  final bool everywhere;
  final List<OrgUnitGrant> grants;

  /// Whether this Account may edit anything, anywhere — the everywhere-first
  /// rule expressed once so no Screen has to remember it.
  bool get canWriteSomewhere => everywhere || grants.any((grant) => grant.canWrite);
}
