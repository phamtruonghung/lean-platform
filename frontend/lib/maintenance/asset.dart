/// One Asset as `GET /api/maintenance/sites/:siteId/assets` sends it.
library;

import 'package:flutter/foundation.dart';

/// The kinds of thing an Asset can be, mirroring the CHECK constraint on
/// `assets.asset_type` and the backend's own `ASSET_TYPES`. The wire is the
/// only thing here: the words are in `l10n/vocabulary.dart`
/// (`assetTypeLabel`, ADR-0062).
enum AssetType {
  machine('machine'),
  cell('cell'),
  tool('tool'),
  utility('utility'),
  vehicle('vehicle'),
  other('other');

  const AssetType(this.wire);

  final String wire;
}

/// Mirrors the CHECK constraint on `assets.criticality`, in wires only: the
/// words are in `l10n/vocabulary.dart` (`assetCriticalityLabel`).
enum Criticality {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const Criticality(this.wire);

  final String wire;
}

@immutable
class Asset {
  const Asset({
    required this.id,
    required this.code,
    required this.name,
    required this.assetType,
    required this.criticality,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.isActive,
    required this.parentId,
  });

  final String id;
  final String code;
  final String name;

  /// The wire strings, not the enums: an Asset the server describes with a
  /// value this build does not know about still renders rather than throwing.
  final String assetType;
  final String criticality;

  final String orgUnitId;
  final String orgUnitName;

  /// The Site the Org Unit above sits in — the server derives it, the client
  /// never sends it. Carried so the register can tell an Asset just created
  /// somewhere else from one belonging to the Site on screen.
  final String siteId;

  /// False once retired (issue #61). Retiring is not a deletion — the row
  /// stays on the register, only excluded from the default read.
  final bool isActive;

  /// The Asset it is nested beneath, or null for a top-level one. This may
  /// name an id that is not in whatever list this Asset arrived in — its
  /// parent can sit in another Site, or be retired and filtered out — so a
  /// non-null value here is never assumed to resolve.
  final String? parentId;
}
