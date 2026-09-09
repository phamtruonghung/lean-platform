/// One Work order as `GET /api/maintenance/sites/:siteId/work-orders` sends
/// it — an open one by default, since the server excludes completed/closed/
/// cancelled rows from that read (issue #57); a completed or cancelled row
/// too when the caller asks for history (issue #63). `closed` stays
/// unreachable through this endpoint either way.
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

  /// The wire status string. Every row this endpoint sends is open by
  /// default — completed/closed/cancelled are excluded unless history was
  /// asked for (issue #63) — so this is shown through [statusLabel] rather
  /// than a closed enum the client would have to keep in lockstep with the
  /// backend's own status list.
  final String status;

  /// The Employee id holding this Work order, or null when nobody has it yet.
  final String? assignedTo;

  /// The Employee holding this Work order, or null when nobody has it yet.
  /// Never rendered as a blank — the Screen shows "Unassigned" instead.
  final String? assigneeName;

  String get workTypeLabel =>
      _labelFor(workType, [for (final t in WorkType.values) (t.wire, t.label)]);

  /// The human label for [status] — falls back to the wire string itself for
  /// a status this build does not know about, the same fallback
  /// [workTypeLabel] follows.
  String get statusLabel => _statusLabels[status] ?? status;

  static String _labelFor(String wire, List<(String, String)> known) {
    for (final (value, label) in known) {
      if (value == wire) return label;
    }
    return wire;
  }
}

/// The transitions offered from a status (issue #63) — `approved` offers
/// Start, `in_progress` offers Complete; both offer Cancel. Every other
/// status, reachable only through history, offers none of the three: a
/// completed or cancelled Work order is terminal, and the four the schema
/// allows but this slice does not offer (`draft`, `scheduled`, `on_hold`,
/// `closed`) are unreachable through the list anyway.
///
/// Top-level and public (issue #104) rather than private to
/// `work_orders_screen.dart`, its pre-#104 home: `router.dart`'s own dialog
/// routes need the same rule to refuse a stale `/complete`/`/cancel`
/// address on a row whose status has since moved on (`WorkOrderDialogHost`'s
/// own status guard) — the same fact about a Work order, asked from two
/// places, stays one function rather than two copies that could drift.
bool offersStart(String status) => status == 'approved';
bool offersComplete(String status) => status == 'in_progress';
bool offersCancel(String status) => status == 'approved' || status == 'in_progress';
