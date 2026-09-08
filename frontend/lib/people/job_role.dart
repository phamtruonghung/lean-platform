/// One row of the job role catalogue (`GET /api/people/job-roles`,
/// `backend/src/modules/people/job-roles.js`) — active job roles only, since
/// the Directory's own job role filter has no reason to offer a retired one
/// (job-role-routes.js's own `includeInactive` is never sent here).
///
/// Shared by every Site (ADR-0005's "one catalogue"), which is why fetching
/// it needs no Site or Org Unit at all — see `PeopleApi.fetchJobRoles`.
library;

import 'package:flutter/foundation.dart';

@immutable
class JobRole {
  const JobRole({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;
}
