/// The tier board as `GET /api/maintenance/sites/:siteId/board` sends it
/// (issue #76).
///
/// CONTEXT.md's distinction is the whole reason this model exists: a **Pillar**
/// is one of the five KPI categories the numbers report under (Safety, Quality,
/// Cost, Delivery, People), and a **KPI** is one number under a Pillar. Which
/// Module produced a KPI and which Pillar it reports under are independent —
/// the server resolves that in `kpi_definitions.pillar_code`, and this client
/// only ever renders whatever Pillars arrive, in order.
///
/// The single most important field here is [BoardKpi.value] being nullable:
/// `null` means nothing was measured, which is a different fact from a measured
/// zero (issue #76's own acceptance criterion). [BoardKpi.formattedValue] never
/// turns a null into a number.
///
/// A date or a production day is carried as the `YYYY-MM-DD` string the wire
/// sends, never parsed into a `DateTime`: the Site's own timezone decides what
/// that day means (ADR-0017), and the client has no business re-deriving it.
library;

import 'package:flutter/foundation.dart';

/// The period a board is bounded to, mirroring the server's own four
/// `period_type` values. [selectable] is what the Screen offers: `shift` needs
/// a shift instance chosen from the Site's calendar, and no such picker exists
/// in this slice, so it is parsed and carried but not chosen from the UI (the
/// request shape and this model still accept it, so a later ticket can wire a
/// picker without a wire or model change).
enum BoardPeriodType {
  shift('shift', 'Shift'),
  day('day', 'Day'),
  week('week', 'Week'),
  month('month', 'Month');

  const BoardPeriodType(this.wire, this.label);

  final String wire;
  final String label;

  /// The period types the Screen's own selector offers, in render order.
  static const List<BoardPeriodType> selectable = [day, week, month];

  /// The enum for a wire string, or null for one this build does not know —
  /// the same honest fallback `DowntimeEvent` keeps for an unknown status.
  static BoardPeriodType? fromWire(String wire) {
    for (final candidate in BoardPeriodType.values) {
      if (candidate.wire == wire) return candidate;
    }
    return null;
  }
}

/// Where the board's numbers come from: the Site in the path, as the board
/// response carries it.
@immutable
class BoardSite {
  const BoardSite({required this.id, required this.name, required this.timezone});

  final String id;
  final String name;

  /// The IANA zone this Site's production day resolves against (ADR-0017).
  final String timezone;
}

/// The Org Unit a board was narrowed to, or null for the whole Site.
@immutable
class BoardOrgUnit {
  const BoardOrgUnit({required this.id, required this.name, required this.path});

  final String id;
  final String name;

  /// The `ltree` path the server's rollup filters on — carried so a later
  /// drill-down can use it, never used for arithmetic on the client.
  final String path;
}

/// The bounded period the board covers, exactly as the server resolved it from
/// the Site's own calendar.
@immutable
class BoardPeriod {
  const BoardPeriod({required this.type, required this.start, required this.end});

  /// The wire period type — one of [BoardPeriodType]'s own `wire` values.
  final String type;

  /// `YYYY-MM-DD`, the first production day in the period.
  final String start;

  /// `YYYY-MM-DD`, the last production day in the period.
  final String end;

  String get label {
    if (type == BoardPeriodType.day.wire) return start;
    return '$start – $end';
  }
}

/// One KPI as the board sends it: its identity, its display precision, its
/// measured value (nullable, never defaulted to zero) and its standing.
@immutable
class BoardKpi {
  const BoardKpi({
    required this.code,
    required this.name,
    required this.unit,
    required this.direction,
    required this.decimalPlaces,
    required this.formulaText,
    required this.value,
    required this.status,
    required this.targetValue,
  });

  final String code;
  final String name;
  final String unit;

  /// `higher_better` or `lower_better` — the server has already evaluated the
  /// standing, so this is carried only so the client can explain a target if
  /// it ever needs to. It never inverts anything here.
  final String direction;

  /// How many decimal places [value] renders with.
  final int decimalPlaces;

  /// The plain-language formula, e.g. `scheduled uptime / breakdown count`.
  final String formulaText;

  /// The measured number, or null when nothing was measured. Never treated as
  /// zero anywhere on this client.
  final double? value;

  /// One of [greenStatus], [amberStatus], [redStatus], [noTargetStatus] or
  /// [noDataStatus], and the fallback for one this build does not know.
  final String status;

  /// The target the value was measured against, or null when none applies.
  final double? targetValue;

  static const String greenStatus = 'green';
  static const String amberStatus = 'amber';
  static const String redStatus = 'red';
  static const String noTargetStatus = 'no_target';
  static const String noDataStatus = 'no_data';

  /// Whether anything was actually measured — the one distinction this whole
  /// Screen turns on.
  bool get hasValue => value != null;

  bool get isNoData => status == noDataStatus;

  /// The value to show, or an em dash when nothing was measured — never `0`
  /// for an unmeasured KPI.
  String get formattedValue =>
      value == null ? '—' : value!.toStringAsFixed(decimalPlaces);

  /// The standing in words, for the status indicator.
  String get statusLabel {
    switch (status) {
      case greenStatus:
        return 'On target';
      case amberStatus:
        return 'Near target';
      case redStatus:
        return 'Off target';
      case noTargetStatus:
        return 'No target';
      case noDataStatus:
        return 'No data';
      default:
        return status;
    }
  }
}

/// One Pillar and the KPIs that report under it, in the order the server sent
/// them.
@immutable
class Pillar {
  const Pillar({
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.hasData,
    required this.kpis,
  });

  final String code;
  final String name;
  final int sortOrder;

  /// False when none of this Pillar's KPIs has a measured value — the board
  /// says so plainly rather than rendering a row of dashes unattended.
  final bool hasData;

  final List<BoardKpi> kpis;
}

/// The board as a whole: where it is, what it is bounded to, and the five
/// Pillars that always arrive whether or not anything reports under them.
@immutable
class TierBoard {
  const TierBoard({
    required this.site,
    required this.orgUnit,
    required this.period,
    required this.pillars,
  });

  final BoardSite site;

  /// Null means the whole Site.
  final BoardOrgUnit? orgUnit;

  final BoardPeriod period;
  final List<Pillar> pillars;
}
