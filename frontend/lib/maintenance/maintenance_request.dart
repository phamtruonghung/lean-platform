/// One Request as the API sends it — what anyone on the floor asks maintenance
/// for, before there is a Work order (issue #72). Mirrors `toRequest`
/// (backend/src/modules/maintenance/maintenance-requests.js) key for key, in
/// its own field order.
library;

import 'package:flutter/foundation.dart';

/// How urgent the requester judges the ask — the operator's judgement, kept
/// separate from the priority maintenance later assigns: the gap between the
/// two is a real signal about how the plant is run, so the client never copies
/// one into the other.
const Map<String, String> _urgencyLabels = {
  'low': 'Low',
  'normal': 'Normal',
  'high': 'High',
  'immediate': 'Immediate',
};

/// The states a Request moves through, mirroring the CHECK constraint on
/// `maintenance_requests.status`. `new` and `triaged` are open (in the queue,
/// awaiting a decision); `accepted`, `rejected` and `duplicate` are decided.
const Map<String, String> _statusLabels = {
  'new': 'New',
  'triaged': 'Triaged',
  'accepted': 'Accepted',
  'rejected': 'Rejected',
  'duplicate': 'Duplicate',
};

/// The Work order an accepted Request became, flattened off the Request row —
/// ADR-0014's backward reference made visible. Present only when the Request
/// was accepted; null otherwise (the Request is still awaiting a decision, or
/// was declined/marked duplicate and never produced a Work order at all).
@immutable
class RequestedWorkOrder {
  const RequestedWorkOrder({
    required this.id,
    required this.workOrderNo,
    required this.status,
    this.assignedTo,
    this.actualEnd,
  });

  final String id;
  final String workOrderNo;
  final String status;
  final String? assignedTo;
  final DateTime? actualEnd;

  String? get statusLabel => switch (status) {
        'approved' => 'Approved',
        'scheduled' => 'Scheduled',
        'in_progress' => 'In progress',
        'on_hold' => 'On hold',
        'completed' => 'Completed',
        'closed' => 'Closed',
        'cancelled' => 'Cancelled',
        _ => null,
      };
}

@immutable
class MaintenanceRequest {
  const MaintenanceRequest({
    required this.id,
    required this.requestNo,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.summary,
    required this.urgency,
    required this.productionStopped,
    required this.status,
    required this.requestedByName,
    required this.reportedAt,
    this.description,
    this.rejectionReason,
    this.duplicateOfId,
    this.duplicateOfNo,
    this.workOrder,
  });

  final String id;

  /// Issued by the Site's own RQT sequence — the client never sends one.
  final String requestNo;

  final String assetId;
  final String assetCode;
  final String assetName;

  final String orgUnitId;
  final String orgUnitName;

  final String summary;

  final String? description;

  /// The wire string for the operator's judgement of urgency.
  final String urgency;

  /// Whether production is stopped right now — the reporter's own assessment.
  final bool productionStopped;

  /// The wire status string.
  final String status;

  /// Who raised it — the display name of the Account that reported it.
  final String? requestedByName;

  final DateTime reportedAt;

  final String? rejectionReason;

  /// The Request this one is a duplicate of, when it is one.
  final String? duplicateOfId;
  final String? duplicateOfNo;

  /// The Work order this accepted Request became, when it was accepted.
  final RequestedWorkOrder? workOrder;

  String get urgencyLabel => _urgencyLabels[urgency] ?? urgency;
  String get statusLabel => _statusLabels[status] ?? status;

  /// Whether this Request is still awaiting a triage decision — i.e. it sits
  /// in the open queue and maintenance may act on it.
  bool get isOpen => status == 'new' || status == 'triaged';
}