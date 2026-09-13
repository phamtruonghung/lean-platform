/// One Part as `GET /api/maintenance/parts` sends it (issue #80) — the shared
/// catalogue CONTEXT.md defines: a stocked item consumed doing a job, defined
/// once and reused, with one unit of measure.
library;

import 'package:flutter/foundation.dart';

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

/// One unit of measure as `GET /api/maintenance/units-of-measure` sends it —
/// the existing baseline catalogue, read-only, so the Part form chooses a unit
/// rather than typing one (ADR-0023).
@immutable
class UnitOfMeasure {
  const UnitOfMeasure({required this.code, required this.name, required this.dimension});

  final String code;
  final String name;
  final String dimension;
}
