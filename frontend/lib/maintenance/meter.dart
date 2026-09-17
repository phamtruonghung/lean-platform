/// An Asset's meter and the readings taken against it (issue #79), as
/// `GET /api/maintenance/sites/:siteId/meters` sends one.
///
/// CONTEXT.md's PM schedule entry is the point: elapsed time and accumulated
/// use are two mechanisms sharing one word, and this is the second one's
/// instrument. A meter is cumulative (an hour counter, a cycle count) or a
/// gauge (a temperature), and only a cumulative meter can drive a schedule.
///
/// `reading` is what is physically on the counter; `accumulatedUse` is
/// `reading + rolloverOffset` and is the number PM due-ness compares. The
/// server computes both, so the client never re-derives the offset and gets
/// ADR-0029 wrong.
library;

import 'package:flutter/foundation.dart';

/// The kinds of meter, mirroring the CHECK constraint on
/// `asset_meters.meter_type` and meters.js's own `METER_TYPES`.
enum MeterType {
  cumulative(
    'cumulative',
    'Cumulative',
    'Only ever goes up — an hour counter or a cycle count. Only a cumulative '
        'meter can drive a PM schedule.',
  ),
  gauge(
    'gauge',
    'Gauge',
    'May go either way — a temperature, a pressure, an oil level. Recorded, '
        'but never scheduled against.',
  );

  const MeterType(this.wire, this.label, this.explanation);

  final String wire;
  final String label;
  final String explanation;
}

/// One unit of measure from the baseline catalogue the meter form chooses
/// from (ADR-0023: a value with a known set is chosen, never typed). The Part
/// form (#80) chooses from the same catalogue, and so does the Quality
/// Module's Product form (#203) — which is why this model is reached through
/// `maintenance.dart`'s entry point rather than by importing this file.
@immutable
class UnitOfMeasure {
  const UnitOfMeasure({required this.code, required this.name, required this.dimension});

  /// The row `GET /api/maintenance/units-of-measure` sends — the same shape
  /// this Module's own client parses, defined here so a second reader of that
  /// address shares one reading of it.
  factory UnitOfMeasure.fromJson(Map<String, dynamic> unit) => UnitOfMeasure(
        code: unit['code'] as String,
        name: unit['name'] as String,
        dimension: unit['dimension'] as String,
      );

  final String code;
  final String name;
  final String dimension;

  String get label => '$name ($code)';
}

@immutable
class AssetMeter {
  const AssetMeter({
    required this.id,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.code,
    required this.name,
    required this.uomCode,
    required this.uomName,
    required this.meterType,
    required this.rolloverOffset,
    required this.isActive,
    required this.latestReading,
    required this.latestReadAt,
    required this.accumulatedUse,
  });

  final String id;
  final String assetId;
  final String assetCode;
  final String assetName;
  final String orgUnitId;
  final String orgUnitName;
  final String siteId;
  final String code;
  final String name;
  final String uomCode;
  final String uomName;

  /// The wire string, not the enum: a type this build does not know about
  /// still renders rather than throwing.
  final String meterType;

  /// The total carried forward from counters this one replaced (ADR-0029).
  final num rolloverOffset;

  final bool isActive;

  /// What is physically on the counter, or null when no reading exists yet.
  final num? latestReading;

  /// When the latest reading was taken, as the server's own timestamp.
  final String? latestReadAt;

  /// `latestReading + rolloverOffset`, or the offset when there is no reading
  /// — the number a meter-driven PM schedule comes due on.
  final num accumulatedUse;

  bool get isCumulative => meterType == 'cumulative';

  String get meterTypeLabel {
    for (final candidate in MeterType.values) {
      if (candidate.wire == meterType) return candidate.label;
    }
    return meterType;
  }

  /// The latest reading in words, with the unit — or a plain "No reading yet".
  String get latestReadingLabel =>
      latestReading == null ? 'No reading yet' : '${_trim(latestReading!)} $uomCode';

  String get accumulatedLabel => '${_trim(accumulatedUse)} $uomCode';

  static String _trim(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
