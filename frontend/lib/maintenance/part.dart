/// One Part as `GET /api/maintenance/parts` sends it (issue #80) — the shared
/// catalogue CONTEXT.md defines: a stocked item consumed doing a job, defined
/// once and reused, with one unit of measure.
library;

import 'package:flutter/foundation.dart';

// The baseline `UnitOfMeasure` catalogue is defined once, in meter.dart
// (issue #79); the Part form (issue #80) chooses from the same catalogue, so
// the one type is re-exported here rather than declared twice.
export 'meter.dart' show UnitOfMeasure;

@immutable
class Part {
  const Part({
    required this.id,
    required this.partNo,
    required this.description,
    required this.uomCode,
    required this.isActive,
  });

  final String id;
  final String partNo;
  final String description;

  /// The unit's `units_of_measure.code` — the same unit every movement of
  /// this part uses. Never a second notion of a unit.
  final String uomCode;

  final bool isActive;

  String get label => '$partNo · $description';
}
