/// One row of the job role catalogue (`GET /api/people/job-roles`,
/// `backend/src/modules/people/job-roles.js`) — active job roles only by
/// default, since the Directory's own job role filter and an Assignment's own
/// job role choice have no reason to offer a retired one. The job role
/// catalogue Screen (issue #88) is the one caller that widens this with
/// `includeInactive: true` — an administrator correcting the catalogue needs
/// to reach a deactivated row to reactivate it.
///
/// Shared by every Site (ADR-0005's "one catalogue"), which is why fetching
/// it needs no Site or Org Unit at all — see `PeopleApi.fetchJobRoles`.
library;

import 'package:flutter/foundation.dart';

@immutable
class JobRole {
  const JobRole({required this.id, required this.code, required this.name, this.isActive = true});

  final String id;
  final String code;
  final String name;

  /// False for a deactivated job role (job-roles.js's own header: "deactivated,
  /// never deleted") — defaults true so every existing caller of this model,
  /// none of which ever asked for a retired row before issue #88, keeps
  /// reading exactly as it did.
  final bool isActive;
}
