/// One Request as `GET /api/maintenance/sites/:siteId/requests`,
/// `.../requests/mine` and the triage actions send it (issue #72).
///
/// CONTEXT.md's own distinction is the whole point of this model: a Request is
/// what anyone on the floor asks maintenance for, before there is a Work
/// order. An accepted Request carries the Work order it became through
/// [workOrder] — the link ADR-0014 records — so a requester can follow what
/// they raised through to the job.
library;

import 'package:flutter/foundation.dart';

/// The urgency the reporter chose, mirroring the CHECK constraint on
/// `maintenance_requests.urgency` and the backend's own `URGENCIES`. This is
/// the reporter's judgement and is deliberately **not** the Work order's own
/// `priority`: accepting a Request lets maintenance set that separately
/// (issue #72's own Implementation Decisions).
enum RequestUrgency {
  low('low', 'Low'),
  normal('normal', 'Normal'),
  high('high', 'High'),
  immediate('immediate', 'Immediate');

  const RequestUrgency(this.wire, this.label);

  final String wire;
  final String label;
}

/// The states a Request can be in, mirroring the CHECK constraint on
/// `maintenance_requests.status`. A label for each known value, with the wire
/// string itself as the fallback for one this build does not know about — the
/// same fallback `WorkOrder.statusLabel` follows.
const Map<String, String> _statusLabels = {
  'new': 'New',
  'triaged': 'Triaged',
  'accepted': 'Accepted',
  'rejected': 'Rejected',
  'duplicate': 'Duplicate',
};

/// The Work order an accepted Request produced, as the nested `workOrder` map
/// on the wire. Only ever non-null for an accepted Request (ADR-0014): the
/// reference points backward once, at acceptance.
@immutable
class RequestWorkOrder {
  const RequestWorkOrder({required this.id, required this.workOrderNo, required this.status});

  final String id;

  /// Issued by the Site's own sequence — the client never sends one.
  final String workOrderNo;
  final String status;

  String get statusLabel => _statusLabels[status] ?? status;
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
    required this.description,
    required this.urgency,
    required this.productionStopped,
    required this.reportedBy,
    required this.reporterName,
    required this.reportedAt,
    required this.status,
    required this.triagedAt,
    required this.rejectionReason,
    required this.duplicateOfId,
    required this.workOrder,
  });

  final String id;

  /// Issued by the Site's own document sequence — the client never sends one.
  final String requestNo;

  /// The Asset this Request is against, flattened onto the row exactly as
  /// `toRequest` (requests.js) sends it — no nested `asset` map on the wire.
  final String assetId;
  final String assetCode;
  final String assetName;

  /// The Org Unit derived by trigger from the Asset at raise time, never sent
  /// by the client.
  final String orgUnitId;
  final String orgUnitName;

  final String summary;
  final String? description;

  /// The wire string, not the enum: an urgency this build does not know about
  /// still renders rather than throwing.
  final String urgency;

  /// Whether production is stopped right now, the reporter's own answer.
  final bool productionStopped;

  /// The Account's linked Employee id, or null when it names none.
  final String? reportedBy;

  /// The reporting Employee's name, or null when nobody resolved.
  final String? reporterName;

  final String? reportedAt;

  /// The wire status, shown through [statusLabel].
  final String status;
  final String? triagedAt;

  /// Why a rejected Request was declined, if it was.
  final String? rejectionReason;

  /// The surviving Request an accepted-duplicate points at, if this one is a
  /// duplicate.
  final String? duplicateOfId;

  /// The Work order this Request became, or null when it is not accepted.
  final RequestWorkOrder? workOrder;

  String get urgencyLabel => _labelFor(urgency, [
        for (final urgency in RequestUrgency.values) (urgency.wire, urgency.label),
      ]);

  String get statusLabel => _statusLabels[status] ?? status;

  static String _labelFor(String wire, List<(String, String)> known) {
    for (final (value, label) in known) {
      if (value == wire) return label;
    }
    return wire;
  }
}
