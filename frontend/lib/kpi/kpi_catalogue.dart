/// The KPI Module's records as the API sends them (ADR-0055), snake_case key
/// for key from `backend/src/modules/kpi/catalogue-routes.js` and
/// `review-routes.js`.
///
/// No number here is computed in Dart that the API already returns: Targets,
/// observed values, review state, `review_date`, `entered_at` and `app_user`
/// all come off the wire. [formatTarget] is formatting only, and `decimals` is
/// the API's own field.
library;

/// A KPI Target in force: from [validFrom] on, with the [note] of the entry
/// that decides. The API sends `null` instead of a [KpiTarget] when nothing is
/// in force and when the entry in force says "no target" — one fact, one
/// shape — so a [KpiTarget] always has a [target].
class KpiTarget {
  const KpiTarget({required this.validFrom, required this.target, this.note});

  final String validFrom;
  final double target;
  final String? note;

  static KpiTarget? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final target = (json['target'] as num?)?.toDouble();
    if (target == null) return null;
    return KpiTarget(
      validFrom: json['valid_from'] as String? ?? '',
      target: target,
      note: json['note'] as String?,
    );
  }
}

/// A KPI Review's saved state for one day: `met`, `missed` or `not_measured`,
/// by whom and when, as the server holds it.
class KpiReviewEntry {
  const KpiReviewEntry({
    required this.status,
    this.observed,
    this.note,
    this.appUser,
    this.enteredAt,
  });

  final String status;
  final double? observed;
  final String? note;
  final String? appUser;
  final String? enteredAt;

  static KpiReviewEntry? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final status = json['status'] as String?;
    if (status == null) return null;
    return KpiReviewEntry(
      status: status,
      observed: (json['observed'] as num?)?.toDouble(),
      note: json['note'] as String?,
      appUser: json['app_user'] as String?,
      enteredAt: json['entered_at'] as String?,
    );
  }
}

/// A KPI's own definition — the seven fields every KPI read carries.
class KpiSummary {
  const KpiSummary({
    required this.kpiId,
    required this.kpi,
    required this.title,
    required this.unit,
    required this.direction,
    required this.decimals,
    this.valueMeasure,
  });

  final int kpiId;

  /// The KPI's code (`OEE`, `MTTR`).
  final String kpi;
  final String title;
  final String unit;

  /// `'<='` or `'>='` for a new KPI; a seeded one (MTTR/MTBF) may carry `'<'`
  /// or `'>'`. Rendered as the string it is, never gated on the pair.
  final String direction;
  final int decimals;
  final String? valueMeasure;

  factory KpiSummary.fromJson(Map<String, dynamic> json) => KpiSummary(
        kpiId: (json['kpi_id'] as num).toInt(),
        kpi: json['kpi'] as String? ?? '',
        title: json['title'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        direction: json['direction'] as String? ?? '',
        decimals: (json['decimals'] as num?)?.toInt() ?? 0,
        valueMeasure: json['value_measure'] as String?,
      );
}

/// A KPI Target as a person reads it: `>= 95.0 %`. Formatting only —
/// `decimals` is the API's own field.
String formatTarget(KpiSummary kpi, double target) =>
    '${kpi.direction} ${target.toStringAsFixed(kpi.decimals)}${kpi.unit.isEmpty ? '' : ' ${kpi.unit}'}';

/// One row of `GET /api/kpi/catalogue`: the KPI, its three grains' Targets in
/// force and the review state of the day the read was made for.
class KpiRow extends KpiSummary {
  const KpiRow({
    required super.kpiId,
    required super.kpi,
    required super.title,
    required super.unit,
    required super.direction,
    required super.decimals,
    super.valueMeasure,
    this.daily,
    this.weekly,
    this.monthly,
    this.review,
  });

  final KpiTarget? daily;
  final KpiTarget? weekly;
  final KpiTarget? monthly;
  final KpiReviewEntry? review;

  factory KpiRow.fromJson(Map<String, dynamic> json) {
    final summary = KpiSummary.fromJson(json);
    final targets = json['targets'];
    final grains = targets is Map<String, dynamic> ? targets : const <String, dynamic>{};
    return KpiRow(
      kpiId: summary.kpiId,
      kpi: summary.kpi,
      title: summary.title,
      unit: summary.unit,
      direction: summary.direction,
      decimals: summary.decimals,
      valueMeasure: summary.valueMeasure,
      daily: KpiTarget.fromJsonOrNull(grains['Daily']),
      weekly: KpiTarget.fromJsonOrNull(grains['Weekly']),
      monthly: KpiTarget.fromJsonOrNull(grains['Monthly']),
      review: KpiReviewEntry.fromJsonOrNull(json['review']),
    );
  }
}

class KpiCatalogue {
  const KpiCatalogue({required this.siteId, required this.reviewDate, required this.kpis});

  final String siteId;

  /// The day [KpiRow.review] is for. Asked without a `date`, it is the Site's
  /// own today — the server's, never Dart's clock.
  final String reviewDate;
  final List<KpiRow> kpis;

  factory KpiCatalogue.fromJson(Map<String, dynamic> json) => KpiCatalogue(
        siteId: '${json['site_id']}',
        reviewDate: json['review_date'] as String? ?? '',
        kpis: [
          for (final kpi in json['kpis'] as List<dynamic>? ?? const [])
            KpiRow.fromJson(kpi as Map<String, dynamic>),
        ],
      );
}

/// A Target in force today, as `GET /api/kpi/targets`' `current` lists it. A
/// grain with no Target is not listed: the route sends it with a null `target`
/// and [fromJsonOrNull] drops it.
class KpiCurrentTarget {
  const KpiCurrentTarget({required this.grain, required this.validFrom, required this.target});

  final String grain;
  final String validFrom;
  final double target;

  factory KpiCurrentTarget.fromJson(Map<String, dynamic> json) => KpiCurrentTarget(
        grain: json['grain'] as String? ?? '',
        validFrom: json['valid_from'] as String? ?? '',
        target: (json['target'] as num?)?.toDouble() ?? 0,
      );

  /// Null when the grain has no Target (`target` is null).
  static KpiCurrentTarget? fromJsonOrNull(Map<String, dynamic> json) =>
      json['target'] == null ? null : KpiCurrentTarget.fromJson(json);
}

/// One entry of a KPI's Target history. [target] is null for a "no target
/// from that date on" entry.
class KpiHistoryEntry {
  const KpiHistoryEntry({
    required this.targetId,
    required this.grain,
    required this.validFrom,
    this.target,
    this.note,
    this.appUser,
    this.enteredAt,
    this.enteredBy,
    this.isEffective = false,
  });

  final int targetId;
  final String grain;
  final String validFrom;
  final double? target;
  final String? note;
  final String? appUser;
  final String? enteredAt;
  final String? enteredBy;
  final bool isEffective;

  factory KpiHistoryEntry.fromJson(Map<String, dynamic> json) => KpiHistoryEntry(
        targetId: (json['target_id'] as num?)?.toInt() ?? 0,
        grain: json['grain'] as String? ?? '',
        validFrom: json['valid_from'] as String? ?? '',
        target: (json['target'] as num?)?.toDouble(),
        note: json['note'] as String?,
        appUser: json['app_user'] as String?,
        enteredAt: json['entered_at'] as String?,
        enteredBy: json['entered_by']?.toString(),
        isEffective: json['is_effective'] as bool? ?? false,
      );
}

/// `GET /api/kpi/targets`: the KPI, what is in force today and the history,
/// newest first as the server orders it.
class KpiTargets {
  const KpiTargets({required this.kpi, required this.current, required this.history});

  final KpiSummary kpi;
  final List<KpiCurrentTarget> current;
  final List<KpiHistoryEntry> history;

  factory KpiTargets.fromJson(Map<String, dynamic> json) => KpiTargets(
        kpi: KpiSummary.fromJson(json['kpi'] as Map<String, dynamic>),
        current: [
          for (final entry in json['current'] as List<dynamic>? ?? const [])
            ?KpiCurrentTarget.fromJsonOrNull(entry as Map<String, dynamic>),
        ],
        history: [
          for (final entry in json['history'] as List<dynamic>? ?? const [])
            KpiHistoryEntry.fromJson(entry as Map<String, dynamic>),
        ],
      );
}

/// One row of `GET /api/kpi/review`. [target] is the Daily Target in force on
/// the day read (null when there was none); [status] is null until the KPI is
/// reviewed.
class ReviewRow {
  const ReviewRow({
    required this.kpiId,
    required this.title,
    required this.unit,
    required this.direction,
    this.target,
    this.status,
    this.observed,
    this.note,
    this.appUser,
    this.enteredAt,
  });

  final int kpiId;
  final String title;
  final String unit;
  final String direction;
  final double? target;
  final String? status;
  final double? observed;
  final String? note;
  final String? appUser;
  final String? enteredAt;

  factory ReviewRow.fromJson(Map<String, dynamic> json) => ReviewRow(
        kpiId: (json['kpi_id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        direction: json['direction'] as String? ?? '',
        target: (json['target'] as num?)?.toDouble(),
        status: json['status'] as String?,
        observed: (json['observed'] as num?)?.toDouble(),
        note: json['note'] as String?,
        appUser: json['app_user'] as String?,
        enteredAt: json['entered_at'] as String?,
      );
}

class KpiReview {
  const KpiReview({required this.reviewDate, required this.rows});

  final String reviewDate;
  final List<ReviewRow> rows;

  factory KpiReview.fromJson(Map<String, dynamic> json) => KpiReview(
        reviewDate: json['review_date'] as String? ?? '',
        rows: [
          for (final row in json['rows'] as List<dynamic>? ?? const [])
            ReviewRow.fromJson(row as Map<String, dynamic>),
        ],
      );
}

/// The three statuses a KPI Review can take, as the API spells them.
abstract final class ReviewStatus {
  static const String met = 'met';
  static const String missed = 'missed';
  static const String notMeasured = 'not_measured';

  static const List<String> all = [met, missed, notMeasured];

  static String label(String status) => switch (status) {
        met => 'Met',
        missed => 'Missed',
        notMeasured => 'Not measured',
        _ => status,
      };
}

/// One entry of `POST /api/kpi/review`'s `entries`. The server writes the
/// Account's own name as `app_user`; none is sent.
class ReviewEntryInput {
  const ReviewEntryInput({required this.kpiId, required this.status, this.observed, this.note});

  final int kpiId;
  final String status;
  final double? observed;
  final String? note;

  Map<String, Object?> toJson() => {
        'kpi_id': kpiId,
        'status': status,
        'observed': observed,
        'note': note,
      };
}

/// The fields of a KPI to add (`POST /api/kpi/catalogue`).
class NewKpi {
  const NewKpi({
    required this.kpi,
    required this.title,
    required this.unit,
    required this.direction,
    required this.decimals,
    this.valueMeasure,
  });

  final String kpi;
  final String title;
  final String unit;
  final String direction;
  final int decimals;
  final String? valueMeasure;
}

/// A wire `timestamptz` as `YYYY-MM-DD HH:MM` in the device's own local time,
/// formatted by hand the way `AppDateField` formats its dates (no `intl`). A
/// value that is not a timestamp is shown as it came.
String formatEnteredAt(String enteredAt) {
  final parsed = DateTime.tryParse(enteredAt);
  if (parsed == null) return enteredAt;
  final local = parsed.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}

/// A Review row's Target as a person reads it: `>= 95 %`. The review read
/// carries no `decimals`, so a whole number is shown whole and any other as the
/// API sent it.
String formatReviewTarget(ReviewRow row, double target) {
  final number = target == target.roundToDouble() ? target.toStringAsFixed(0) : '$target';
  return '${row.direction} $number${row.unit.isEmpty ? '' : ' ${row.unit}'}';
}
