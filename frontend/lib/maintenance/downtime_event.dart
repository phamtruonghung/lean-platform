/// One Downtime event as `GET /api/maintenance/sites/:siteId/downtime`, the
/// Breakdown report and the two row actions send it (issue #73).
///
/// CONTEXT.md's own distinction is the whole point of this model: a Breakdown
/// is a machine stopping unplanned, and the *Downtime* it produces is the
/// period the machine was not running — a different fact from the Work order's
/// own duration, which is how long the repair took. The server owns both: this
/// model never derives a duration, it only carries the one the server sent.
///
/// `status` is generated server-side and is exactly one of [openStatus],
/// [unclassifiedStatus] or [closedStatus]: a stop is open while `ended_at` is
/// null, unclassified once closed with no reason, and closed otherwise.
library;

import 'package:flutter/foundation.dart';

/// The Downtime event states, mirroring the GENERATED `downtime_events.status`
/// column. A label for each known value, with the wire string itself as the
/// fallback for one this build does not know about — the same fallback
/// `WorkOrder.statusLabel` and `Request.statusLabel` follow.
const Map<String, String> _statusLabels = {
  'open': 'Open',
  'unclassified': 'Unclassified',
  'closed': 'Closed',
};

/// One Downtime reason from `GET /api/maintenance/downtime-reasons` — the
/// classify picker's own catalogue. A shared global catalogue (ADR-0005), not
/// an Org-Unit-scoped record, which is why any approved Account may read it.
@immutable
class DowntimeReason {
  const DowntimeReason({
    required this.id,
    required this.code,
    required this.name,
    required this.lossCategory,
    required this.isPlanned,
    required this.requiresComment,
  });

  final String id;
  final String code;
  final String name;
  final String lossCategory;
  final bool isPlanned;

  /// When true the server refuses a classification with no description
  /// (a 400), so the classify dialog must require one before submitting.
  final bool requiresComment;
}

@immutable
class DowntimeEvent {
  const DowntimeEvent({
    required this.id,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMinutes,
    required this.status,
    required this.downtimeReasonId,
    required this.downtimeReasonName,
    required this.description,
    required this.reportedBy,
    required this.reporterName,
    required this.classifiedAt,
    required this.source,
  });

  final String id;

  /// The Asset this stop is against, flattened onto the row exactly as
  /// `toDowntimeEvent` (downtime.js) sends it — no nested `asset` map.
  final String assetId;
  final String assetCode;
  final String assetName;

  /// The Org Unit derived by trigger from the Asset at report time, never
  /// sent by the client.
  final String orgUnitId;
  final String orgUnitName;

  final String? startedAt;
  final String? endedAt;

  /// The server's own generated duration. Null while the stop is open. Never
  /// recomputed here.
  final num? durationMinutes;

  /// The wire status, shown through [statusLabel].
  final String status;

  /// The reason this stop was classified against, or null while unclassified.
  final String? downtimeReasonId;
  final String? downtimeReasonName;

  final String? description;

  /// The Account's linked Employee id, or null when it names none.
  final String? reportedBy;
  final String? reporterName;

  final String? classifiedAt;

  /// How this stop was recorded — `manual` for one reported through this app.
  final String source;

  static const String openStatus = 'open';
  static const String unclassifiedStatus = 'unclassified';
  static const String closedStatus = 'closed';

  String get statusLabel => _statusLabels[status] ?? status;

  /// Whether the stop is still running — the one state Close is offered in.
  bool get isOpen => status == openStatus;

  /// Whether a reason has been recorded yet — the one state Classify is
  /// offered in.
  bool get isClassified => downtimeReasonId != null;
}
