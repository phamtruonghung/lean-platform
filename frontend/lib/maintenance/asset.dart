/// One Asset as `GET /api/maintenance/sites/:siteId/assets` sends it.
library;

import 'package:flutter/foundation.dart';

/// The kinds of thing an Asset can be, mirroring the CHECK constraint on
/// `assets.asset_type` and the backend's own `ASSET_TYPES`.
enum AssetType {
  machine('machine', 'Machine'),
  cell('cell', 'Cell'),
  tool('tool', 'Tool'),
  utility('utility', 'Utility'),
  vehicle('vehicle', 'Vehicle'),
  other('other', 'Other');

  const AssetType(this.wire, this.label);

  final String wire;
  final String label;
}

/// Mirrors the CHECK constraint on `assets.criticality`.
enum Criticality {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  critical('critical', 'Critical');

  const Criticality(this.wire, this.label);

  final String wire;
  final String label;
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

  String get typeLabel => _labelFor(assetType, [for (final t in AssetType.values) (t.wire, t.label)]);
  String get criticalityLabel =>
      _labelFor(criticality, [for (final c in Criticality.values) (c.wire, c.label)]);

  static String _labelFor(String wire, List<(String, String)> known) {
    for (final (value, label) in known) {
      if (value == wire) return label;
    }
    return wire;
  }
}
