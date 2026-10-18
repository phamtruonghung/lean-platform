/// A leave request (issue #265): one Employee asking to be away from work for
/// a run of calendar days, for a leave type chosen from the requestable
/// absence reasons, and the decision a person with authority then makes on
/// it. Read from `GET /api/people/leave-requests`.
///
/// The server decides who may approve, reject or cancel a given request and
/// says so on the row ([LeaveRequest.canDecide], [LeaveRequest.canCancel]);
/// the client never re-derives that from roles or Grants, so a Screen that
/// offers a button offers exactly what the route would accept.
library;

import '../status_tone.dart';

/// The wire values of a leave request's status, in the order a person scans
/// them.
const List<String> leaveRequestStatuses = ['pending', 'approved', 'rejected', 'cancelled'];

String leaveRequestStatusLabel(String status) => switch (status) {
      'pending' => 'Pending',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'cancelled' => 'Cancelled',
      _ => status,
    };

StatusTone leaveRequestStatusTone(String status) => switch (status) {
      'pending' => StatusTone.warning,
      'approved' => StatusTone.success,
      'rejected' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

/// The two views of the leave request list: the caller's own requests, and
/// the pending requests the caller may decide. [wire] is the `view` query
/// value.
enum LeaveRequestView {
  mine('mine'),
  toDecide('to-decide');

  const LeaveRequestView(this.wire);

  final String wire;
}

/// A person named on a leave request (the Employee, who asked, who decided).
class LeaveRequestPerson {
  const LeaveRequestPerson({required this.id, required this.displayName, this.employeeNo});

  final String id;
  final String displayName;
  final String? employeeNo;

  factory LeaveRequestPerson.fromJson(Map<String, dynamic> json) => LeaveRequestPerson(
        id: json['id'].toString(),
        displayName: json['displayName'] as String,
        employeeNo: json['employeeNo'] as String?,
      );

  static LeaveRequestPerson? maybe(Object? json) =>
      json is Map<String, dynamic> ? LeaveRequestPerson.fromJson(json) : null;
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.employee,
    required this.leaveTypeId,
    required this.leaveTypeName,
    this.orgUnitName,
    required this.startsOn,
    required this.endsOn,
    required this.days,
    this.note,
    required this.status,
    this.requestedBy,
    this.requestedAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.cancelledBy,
    this.cancelledAt,
    required this.canDecide,
    required this.canCancel,
  });

  final String id;
  final LeaveRequestPerson employee;

  /// The absence reason chosen as the leave type.
  final String leaveTypeId;
  final String leaveTypeName;
  final String? orgUnitName;
  final String startsOn;
  final String endsOn;

  /// Inclusive calendar days, counted by the server.
  final int days;
  final String? note;
  final String status;
  final LeaveRequestPerson? requestedBy;
  final String? requestedAt;
  final LeaveRequestPerson? decidedBy;
  final String? decidedAt;
  final String? decisionNote;
  final LeaveRequestPerson? cancelledBy;
  final String? cancelledAt;
  final bool canDecide;
  final bool canCancel;

  String get statusLabel => leaveRequestStatusLabel(status);

  /// "2026-05-04" for a one-day request, "2026-05-04 to 2026-05-06" otherwise.
  String get periodLabel => startsOn == endsOn ? startsOn : '$startsOn to $endsOn';

  String get daysLabel => days == 1 ? '1 day' : '$days days';

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final reason = json['absenceReason'] as Map<String, dynamic>;
    final orgUnit = json['orgUnit'];
    return LeaveRequest(
      id: json['id'].toString(),
      employee: LeaveRequestPerson.fromJson(json['employee'] as Map<String, dynamic>),
      leaveTypeId: reason['id'].toString(),
      leaveTypeName: reason['name'] as String,
      orgUnitName: orgUnit is Map<String, dynamic> ? orgUnit['name'] as String? : null,
      startsOn: json['startsOn'] as String,
      endsOn: json['endsOn'] as String,
      days: (json['days'] as num).toInt(),
      note: json['note'] as String?,
      status: json['status'] as String,
      requestedBy: LeaveRequestPerson.maybe(json['requestedBy']),
      requestedAt: json['requestedAt'] as String?,
      decidedBy: LeaveRequestPerson.maybe(json['decidedBy']),
      decidedAt: json['decidedAt'] as String?,
      decisionNote: json['decisionNote'] as String?,
      cancelledBy: LeaveRequestPerson.maybe(json['cancelledBy']),
      cancelledAt: json['cancelledAt'] as String?,
      canDecide: json['canDecide'] == true,
      canCancel: json['canCancel'] == true,
    );
  }
}
