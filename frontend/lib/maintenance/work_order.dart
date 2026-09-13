/// One Work order as `GET /api/maintenance/sites/:siteId/work-orders` sends
/// it — an open one by default, since the server excludes completed/closed/
/// cancelled rows from that read (issue #57); a completed or cancelled row
/// too when the caller asks for history (issue #63). `closed` stays
/// unreachable through this endpoint either way.
///
/// `GET /api/maintenance/work-orders/:id` (issue #74) sends the same flat row
/// plus the [tasks] copied from the Job plan that raised it. The list read
/// deliberately omits them — attaching every row's tasks would be an N+1 — so
/// [tasks] is empty on a row that came from the list and populated only on a
/// detail read.
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
    required this.siteId,
    required this.summary,
    required this.workType,
    required this.priority,
    required this.status,
    required this.assignedTo,
    required this.assigneeName,
    this.tasks = const [],
    this.cost,
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

  /// The Site the Work order's Org Unit belongs to. Resolved server-side and
  /// carried so the parts booking dialog can offer that Site's stores without
  /// reading the list Bloc's own state.
  final String siteId;

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

  /// The steps copied from the Job plan that raised this Work order, in
  /// `stepNo` order — populated only by the detail read (issue #74). Empty
  /// on a row that came from the Site-wide list, which deliberately carries
  /// none.
  final List<WorkOrderTask> tasks;

  /// What the job has cost so far (issue #75) — hours by activity and the
  /// parts fitted, each its own fact. Null on a row that came from the
  /// Site-wide list, which carries no cost; populated only by the detail
  /// read, the same way [tasks] is.
  final WorkOrderCost? cost;

  String get workTypeLabel =>
      _labelFor(workType, [for (final t in WorkType.values) (t.wire, t.label)]);

  /// The human label for [status] — falls back to the wire string itself for
  /// a status this build does not know about, the same fallback
  /// [workTypeLabel] follows.
  String get statusLabel => _statusLabels[status] ?? status;

  /// Every label [statusLabel] can produce for a status this build knows
  /// about (issue #105) — the wide table's own Status column reads this to
  /// size itself to the longest one, rather than a width tuned to whichever
  /// label happens to be longest today, so a status added to
  /// [_statusLabels] later is sized for automatically rather than clipped.
  /// The wire-string fallback [statusLabel] falls back to for an unknown
  /// status is deliberately not included: that string is unbounded, and
  /// only known labels are worth sizing a fixed column against.
  static List<String> get knownStatusLabels => _statusLabels.values.toList(growable: false);

  static String _labelFor(String wire, List<(String, String)> known) {
    for (final (value, label) in known) {
      if (value == wire) return label;
    }
    return wire;
  }
}

/// The states one step inside a Work order can be in, mirroring the CHECK
/// constraint on `work_order_tasks.status`. `pending` is the default a copied
/// task starts at; the other three record how the step actually went.
const Map<String, String> _taskStatusLabels = {
  'pending': 'Pending',
  'done': 'Done',
  'skipped': 'Skipped',
  'failed': 'Failed',
};

/// One step copied onto a Work order from the Job plan that raised it, as
/// `GET /api/maintenance/work-orders/:id` sends it (issue #74). Mirrors the
/// Job plan task shape plus the three execution fields a task carries once it
/// has been worked — [status], [note] and [reading] — and, like the plan's
/// own task, carries the required Skill's name resolved by the server's join,
/// so nothing is looked up separately on the client.
@immutable
class WorkOrderTask {
  const WorkOrderTask({
    required this.id,
    required this.stepNo,
    required this.instruction,
    required this.skillId,
    required this.skillName,
    required this.status,
    required this.note,
    required this.reading,
  });

  final String id;
  final int stepNo;
  final String instruction;

  /// The required Skill's id, or null when the step requires none.
  final String? skillId;
  final String? skillName;

  /// The wire status string, shown through [statusLabel].
  final String status;
  final String? note;
  final num? reading;

  /// Whether this step names a required Skill worth showing.
  bool get hasSkill => skillName != null && skillName!.isNotEmpty;

  String get statusLabel => _taskStatusLabels[status] ?? status;
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

/// The kinds of activity a booked window records, mirroring the CHECK on
/// `work_order_labour.activity` and the backend's own `LABOUR_ACTIVITIES`.
/// All five are offered by the booking dialog; a plant whose technicians
/// spend a third of the job waiting for a permit has a scheduling problem,
/// not a staffing one, so `waiting` is worth keeping honest.
enum LabourActivity {
  work('work', 'Work'),
  travel('travel', 'Travel'),
  waiting('waiting', 'Waiting'),
  diagnosis('diagnosis', 'Diagnosis'),
  documentation('documentation', 'Documentation');

  const LabourActivity(this.wire, this.label);

  final String wire;
  final String label;

  static String labelFor(String wire) {
    for (final activity in LabourActivity.values) {
      if (activity.wire == wire) return activity.label;
    }
    return wire;
  }
}

/// How a fitted part reached the job, mirroring the CHECK on
/// `work_order_parts.sourced`. Only `stores` draws down inventory (ADR-0015);
/// the other three are a cost line with no shelf behind them.
enum PartSource {
  stores('stores', 'Stores'),
  purchased('purchased', 'Purchased'),
  refurbished('refurbished', 'Refurbished'),
  cannibalised('cannibalised', 'Cannibalised');

  const PartSource(this.wire, this.label);

  final String wire;
  final String label;

  static String labelFor(String wire) {
    for (final source in PartSource.values) {
      if (source.wire == wire) return source.label;
    }
    return wire;
  }
}

/// One activity's booked hours on a Work order, with overtime split out so it
/// is distinguishable from ordinary hours at the point of reading.
@immutable
class WorkOrderLabourActivity {
  const WorkOrderLabourActivity({
    required this.activity,
    required this.hours,
    required this.overtimeHours,
  });

  final String activity;
  final num hours;
  final num overtimeHours;

  String get label => LabourActivity.labelFor(activity);
}

/// One part fitted to a Work order (issue #75) — mirrors `toBookedPart`
/// (work-order-cost.js) key for key. [totalCost] is generated server-side from
/// [quantity] and [unitCost], null when no cost was recorded.
@immutable
class WorkOrderPartLine {
  const WorkOrderPartLine({
    required this.id,
    required this.partNo,
    required this.description,
    required this.quantity,
    required this.uomCode,
    required this.unitCost,
    required this.currency,
    required this.totalCost,
    required this.sourced,
  });

  final String id;
  final String? partNo;
  final String description;
  final num quantity;
  final String uomCode;
  final num? unitCost;
  final String currency;
  final num? totalCost;
  final String sourced;

  String get sourcedLabel => PartSource.labelFor(sourced);

  String get name => partNo == null || partNo!.isEmpty ? description : '$partNo · $description';
}

/// What a Work order has cost so far (issue #75): hours by activity and the
/// parts fitted with their total. [labourHours] and [partsCost] are two
/// separate facts, never summed: labour booked here is a slice of plant
/// labour cost, already costed from attendance, while parts are the one
/// component of maintenance cost that adds.
@immutable
class WorkOrderCost {
  const WorkOrderCost({
    required this.labourHours,
    required this.overtimeHours,
    required this.labourByActivity,
    required this.parts,
    required this.partsCost,
  });

  const WorkOrderCost.empty()
      : labourHours = 0,
        overtimeHours = 0,
        labourByActivity = const [],
        parts = const [],
        partsCost = null;

  final num labourHours;
  final num overtimeHours;
  final List<WorkOrderLabourActivity> labourByActivity;
  final List<WorkOrderPartLine> parts;

  /// The sum of the parts' own totals, or null when no part carries a cost —
  /// an unpriced shelf is a gap in the data, not a measured zero.
  final num? partsCost;

  bool get hasLabour => labourByActivity.isNotEmpty;
  bool get hasParts => parts.isNotEmpty;
}
