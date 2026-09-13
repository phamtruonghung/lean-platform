/// A Site and one Org Unit in its tree, as the picker needs them.
library;

import 'package:flutter/foundation.dart';

@immutable
class Site {
  const Site({
    required this.id,
    required this.code,
    required this.name,
    this.timezone = '',
    this.countryCode,
  });

  final String id;
  final String code;
  final String name;

  /// The IANA zone a Site's production days resolve against (ADR-0017).
  /// Defaulted to `''` because two fixtures build a `Site` from a shape that
  /// carries none; the list this client actually reads
  /// (`GET /api/people/sites`) always sends one, and it is what
  /// `SiteFormDialog`'s edit mode seeds its timezone field from (issue #137).
  final String timezone;

  /// The optional ISO country code, as the create/correct routes carry it.
  final String? countryCode;
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
    this.path = '',
    this.ancestorNames = const [],
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

  /// The `ltree` path column every `plant.js` row carries (`ORG_UNIT_COLUMNS`),
  /// as the wire sends it: dot-separated labels, root-first, each one `n`
  /// followed by that ancestor's own id (`n<id>`, per the baseline's
  /// compute-path trigger) — never names, since the tree stores no
  /// materialised ancestor name anywhere. Defaulted to `''` for the same two
  /// construction sites [isActive]'s own doc comment names, which build an
  /// `OrgUnitNode` from a shape — an Account's own Grant row — that carries no
  /// path at all.
  final String path;

  /// The names of the ancestors [path] points at, root-first, excluding this
  /// node itself — resolved **on the server** and carried only on a search hit
  /// (`plant.searchOrgUnits`, issue #145, ADR-0024), because [path] is a chain
  /// of ids and no materialised ancestor name exists to look up. Empty for a
  /// node built from any other response: browsing a level (`fetchOrgUnits`)
  /// sends no names, and an Account's own Grant row carries no path at all.
  ///
  /// Scoped server-side to the ancestors the caller's Grants reach, so a
  /// non-administrator's first entry here is their own granted Org Unit, never
  /// an ancestor above it (ADR-0008, ADR-0024).
  final List<String> ancestorNames;

  /// The ordered ancestor ids [path] implies, root-first, excluding this
  /// node's own final segment — parsed by stripping each label's leading
  /// non-digit run (issue #130). This is id-only, and deliberately still so:
  /// revealing a picked Org Unit in the tree is a walk of
  /// `OrgUnitPickerBloc`'s own per-level fetch, by id, exactly as expanding a
  /// row by hand already does — [ancestorNames] answers the different
  /// question of what to write *above* the hit.
  List<String> get ancestorIds {
    if (path.isEmpty) return const [];
    final segments = path.split('.');
    if (segments.length <= 1) return const [];
    return [
      for (final segment in segments.sublist(0, segments.length - 1))
        segment.replaceFirst(RegExp(r'^[^0-9]+'), ''),
    ];
  }
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
/// result short. [truncated] is parsed off the wire here but deliberately not
/// rendered: `AppSearchField` says when it is showing fewer matches than it
/// was given (ADR-0026, issue #143), and its own ten-row bound binds before
/// the server's fifty ever does, so this flag would never change what a person
/// sees. It is kept parsed for the day a server bound falls below the
/// widget's, or a caller wants to say how many more there are.
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
/// ancestors that were on screen above it at that moment. A Grant records the
/// location it was made at rather than re-deriving it later, and for an entry
/// point (no ancestors were ever fetched) that is the Site alone, which is all
/// the caller was told.
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
