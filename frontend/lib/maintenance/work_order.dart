/// One Work order as `GET /api/maintenance/sites/:siteId/work-orders` sends
/// it — always an open one, since the server excludes completed/closed/
/// cancelled rows from that read (issue #57).
library;

import 'package:flutter/foundation.dart';

/// The kinds of work a Work order can be, mirroring the CHECK constraint on
/// `work_orders.work_type` and the backend's own `WORK_TYPES`.
enum WorkType {
  corrective('corrective', 'Corrective'),
  preventive('preventive', 'Preventive'),
  predictive('predictive', 'Predictive'),
  inspection('inspection', 'Inspection'),
  improvement('improvement', 'Improvement'),
  calibration('calibration', 'Calibration');

  const WorkType(this.wire, this.label);

  final String wire;
  final String label;
}

/// The kinds of state a Work order can be in, mirroring the CHECK constraint
/// on `work_orders.status`. Every row this endpoint sends is already open —
/// the server excludes completed/closed/cancelled — but the label mapping
/// covers the whole set anyway, since a later endpoint (a Work order's own
/// detail read, say) may not filter the same way.
const Map<String, String> _statusLabels = {
  'draft': 'Draft',
  'approved': 'Approved',
  'scheduled': 'Scheduled',
  'in_progress': 'In progress',
  'on_hold': 'On hold',
  'completed': 'Completed',
  'closed': 'Closed',
  'cancelled': 'Cancelled',
};

@immutable
class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.workOrderNo,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.summary,
    required this.workType,
    required this.priority,
    required this.status,
    required this.assignedTo,
    required this.assigneeName,
    this.actualStart,
    this.actualEnd,
    this.completionNote,
  });

  final String id;

  /// Issued by the Site's own sequence — the client never sends one.
  final String workOrderNo;

  /// The Asset this Work order is raised against, flattened onto the row
  /// exactly as `toWorkOrder` (work-orders.js) sends it — no nested `asset`
  /// map on the wire, so none here either.
  final String assetId;
  final String assetCode;
  final String assetName;

  /// The Org Unit this Work order sits at — derived server-side from its
  /// Asset, never sent by the client (issue #57's contract), and flattened
  /// onto the row the same way [assetId] and its siblings are.
  final String orgUnitId;
  final String orgUnitName;

  final String summary;

  /// The wire string, not the enum: a work type this build does not know
  /// about still renders rather than throwing — the same reasoning `Asset`
  /// keeps its own `assetType` as a wire string for.
  final String workType;

  /// 1 (most urgent) to 5 (least urgent), the CHECK constraint's own range —
  /// ascending priority sorts first, matching the server's own
  /// `ORDER BY wo.priority, wo.work_order_no`.
  final int priority;

  /// The wire status string. Every row this endpoint sends is already open —
  /// the server excludes completed/closed/cancelled — so this is shown
  /// through [statusLabel] rather than a closed enum the client would have to
  /// keep in lockstep with the backend's own status list.
  final String status;

  /// The Employee id holding this Work order, or null when nobody has it yet.
  final String? assignedTo;

  /// The Employee holding this Work order, or null when nobody has it yet.
  /// Never rendered as a blank — the Screen shows "Unassigned" instead.
  final String? assigneeName;

  /// When work actually began, or null until the Work order is started
  /// (issue #63). Always stamped by the server as `now()`, never by the
  /// client, so a duration is never invented.
  final DateTime? actualStart;

  /// When work actually ended, or null until the Work order is completed.
  /// Also stamped server-side. A completed Work order carries both this and
  /// [actualStart] — the pair the reliability views have been waiting to read.
  final DateTime? actualEnd;

  /// What was found on completion, or null until then (issue #63).
  final String? completionNote;

  String get workTypeLabel =>
      _labelFor(workType, [for (final t in WorkType.values) (t.wire, t.label)]);

  /// The human label for [status] — falls back to the wire string itself for
  /// a status this build does not know about, the same fallback
  /// [workTypeLabel] follows.
  String get statusLabel => _statusLabels[status] ?? status;

  /// Whether this row's status is one this slice (issue #63) offers as "live",
  /// i.e. a caller with a write Grant may act on it. `approved` (agreed) can be
  /// started or cancelled; `in_progress` can be completed or cancelled; a
  /// completed or cancelled Work order has no further action on this slice —
  /// it has left the open list, which is where it is shown from.
  bool get canStart => status == 'approved';
  bool get canComplete => status == 'in_progress';
  bool get canCancel => status == 'approved' || status == 'in_progress';

  static String _labelFor(String wire, List<(String, String)> known) {
    for (final (value, label) in known) {
      if (value == wire) return label;
    }
    return wire;
  }
}
