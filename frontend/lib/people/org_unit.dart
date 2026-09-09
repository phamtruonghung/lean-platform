/// A Site and one Org Unit in its tree, as the picker needs them.
library;

import 'package:flutter/foundation.dart';

@immutable
class Site {
  const Site({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;
}

/// One row of `GET /api/people/sites/:siteId/org-units`.
///
/// [parentId] is carried because the API sends it, and for no other reason:
/// nothing in this client infers structure from it. A root-level response can
/// contain rows with a real, non-null parent — for a non-administrator those
/// rows are that caller's own entry points, several levels deep (ADR-0008) —
/// so "is this a top-level row" is answered by *which request returned it*,
/// never by `parentId == null`.
@immutable
class OrgUnitNode {
  const OrgUnitNode({
    required this.id,
    required this.parentId,
    required this.code,
    required this.name,
    required this.unitType,
    this.isActive = true,
  });

  final String id;
  final String? parentId;
  final String code;
  final String name;
  final String unitType;

  /// Deactivation, never deletion — CONTEXT.md's own Org Unit entry and
  /// `plant.js`'s `setOrgUnitActive`. Defaulted true because two of this
  /// class's three construction sites (`AccountGrant.toGranted`,
  /// `GrantedOrgUnit`'s own fixtures) build one from a shape that carries no
  /// such flag at all — a Grant is only ever held on an Org Unit that exists
  /// and has not been retired since it was granted.
  final bool isActive;
}

/// The `unit_type` values `plant.js`'s own `UNIT_TYPES` accepts
/// (`POST /sites/:siteId/org-units`, the bulk import, issue #90). Mirrored by
/// hand rather than read off an endpoint — there is none, and no backend
/// change is permitted for this ticket — so a change to the server's own list
/// must be brought here too.
abstract final class OrgUnitTypes {
  static const String area = 'area';
  static const String department = 'department';
  static const String line = 'line';
  static const String cell = 'cell';
  static const String workCenter = 'work_center';

  static const List<String> values = [area, department, line, cell, workCenter];
}

/// One `GET /api/people/sites/:siteId/org-units/search` response
/// (`plant.searchOrgUnits`, issue #90's own search route) — the matches and
/// whether the server's own limit (`ORG_UNIT_SEARCH_LIMIT`, plant.js) cut the
/// result short. [truncated] is surfaced, not dropped: a caller acting on an
/// incomplete list without knowing it is exactly the failure mode AC5 exists
/// to close.
@immutable
class OrgUnitSearchResult {
  const OrgUnitSearchResult({required this.orgUnits, required this.truncated});

  final List<OrgUnitNode> orgUnits;
  final bool truncated;
}

/// The two levels a Grant can hold, and nothing else — CONTEXT.md's Grant.
enum GrantLevel {
  view('View', false),
  viewAndEdit('View and edit', true);

  const GrantLevel(this.label, this.canWrite);

  final String label;
  final bool canWrite;
}

/// One Org Unit chosen in the picker, at the level chosen for it.
///
/// [where] is the breadcrumb captured when it was added — the Site and the
/// ancestors that were on screen above it at that moment. There is no Org Unit
/// search endpoint and no ancestor lookup, so this is the only honest way to
/// say where a granted Org Unit sits; for an entry point (no ancestors were
/// ever fetched) it is the Site alone, which is all the caller was told.
@immutable
class GrantedOrgUnit {
  const GrantedOrgUnit({required this.orgUnit, required this.level, required this.where});

  final OrgUnitNode orgUnit;
  final GrantLevel level;
  final String where;

  /// The wire shape `approveAccount` validates
  /// (`backend/src/modules/people/service.js`).
  Map<String, Object?> toJson() => {'orgUnitId': orgUnit.id, 'canWrite': level.canWrite};
}
