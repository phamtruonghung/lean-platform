/// The attendance sheet's own models (issue #249, CONTEXT.md's Attendance
/// section) — one sheet per shift instance, a row per Employee recorded on
/// it, and the absence reason catalogue a row's exception is chosen from.
library;

/// `attendance_status`'s six values, mirrored exactly from the baseline's
/// own CHECK (`backend/migrations/1756000000000_baseline.js`) and from
/// `attendance.js`'s `ATTENDANCE_STATUSES` — a value with a known set is
/// chosen from a list, never typed (AGENTS.md §7, ADR-0023).
const List<String> attendanceStatuses = [
  'present',
  'late',
  'absent_planned',
  'absent_unplanned',
  'training',
  'not_scheduled',
];

/// A human label for each of [attendanceStatuses], in the same order.
String attendanceStatusLabel(String status) => switch (status) {
      'present' => 'Present',
      'late' => 'Late',
      'absent_planned' => 'Absent (planned)',
      'absent_unplanned' => 'Absent (unplanned)',
      'training' => 'Training',
      'not_scheduled' => 'Not scheduled',
      _ => status,
    };

/// `absent_planned`/`absent_unplanned` — the two statuses `attendance.js`
/// requires an [AbsenceReason] for, mirrored here so the Screen can decide
/// when to show the reason dropdown without guessing at the server's own
/// rule.
bool attendanceStatusNeedsReason(String status) =>
    status == 'absent_planned' || status == 'absent_unplanned';

/// One `attendance_sheets` row (`toAttendanceSheet`, attendance.js).
/// [confirmedAt]/[confirmedByAccountId] are both null, or both set — ADR-0040's
/// own "confirmation is its own record, never inferred" rule, enforced by the
/// baseline's `attendance_sheets_confirmed_together` CHECK, mirrored here as
/// a matched pair of nullable fields rather than a separate `isConfirmed`
/// flag that could disagree with them.
class AttendanceSheet {
  const AttendanceSheet({
    required this.id,
    required this.shiftInstanceId,
    this.confirmedAt,
    this.confirmedByAccountId,
  });

  final String id;
  final String shiftInstanceId;
  final String? confirmedAt;
  final String? confirmedByAccountId;

  bool get isConfirmed => confirmedAt != null;

  factory AttendanceSheet.fromJson(Map<String, dynamic> json) => AttendanceSheet(
        id: json['id'].toString(),
        shiftInstanceId: json['shiftInstanceId'].toString(),
        confirmedAt: json['confirmedAt'] as String?,
        confirmedByAccountId: json['confirmedByAccountId']?.toString(),
      );
}

/// The absence reason an [AttendanceRecord] carries, when it names one.
class AttendanceAbsenceReason {
  const AttendanceAbsenceReason({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;
}

/// One `attendance_records` row (`toAttendanceRecord`, attendance.js) — one
/// Employee's own line on the sheet, pre-filled or added as a stand-in.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeNo,
    required this.displayName,
    required this.attendanceStatus,
    this.absenceReason,
    required this.scheduledMinutes,
    required this.workedMinutes,
    required this.overtimeMinutes,
    this.note,
  });

  final String id;
  final String employeeId;
  final String employeeNo;
  final String displayName;
  final String attendanceStatus;
  final AttendanceAbsenceReason? absenceReason;
  final int scheduledMinutes;
  final int workedMinutes;
  final int overtimeMinutes;
  final String? note;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final reason = json['absenceReason'] as Map<String, dynamic>?;
    return AttendanceRecord(
      id: json['id'].toString(),
      employeeId: json['employeeId'].toString(),
      employeeNo: json['employeeNo'] as String,
      displayName: json['displayName'] as String,
      attendanceStatus: json['attendanceStatus'] as String,
      absenceReason: reason == null
          ? null
          : AttendanceAbsenceReason(
              id: reason['id'].toString(),
              code: reason['code'] as String,
              name: reason['name'] as String,
            ),
      scheduledMinutes: (json['scheduledMinutes'] as num).toInt(),
      workedMinutes: (json['workedMinutes'] as num).toInt(),
      overtimeMinutes: (json['overtimeMinutes'] as num).toInt(),
      note: json['note'] as String?,
    );
  }
}

/// One `absence_reasons` row (`GET /api/people/absence-reasons`) — the
/// shared catalogue a `absent_planned`/`absent_unplanned` row's reason is
/// chosen from, never typed.
class AbsenceReason {
  const AbsenceReason({
    required this.id,
    required this.code,
    required this.name,
    required this.isPlanned,
    required this.countsAsAbsenteeism,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final bool isPlanned;
  final bool countsAsAbsenteeism;
  final bool isActive;

  factory AbsenceReason.fromJson(Map<String, dynamic> json) => AbsenceReason(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        isPlanned: json['isPlanned'] == true,
        countsAsAbsenteeism: json['countsAsAbsenteeism'] == true,
        isActive: json['isActive'] == true,
      );
}

/// One row of `GET /api/people/org-units/:id/shift-instances?date=...` — the
/// Attendance picker's own listing (issue #249), so a supervisor can find
/// the sheet they mean to open.
class ShiftInstanceSummary {
  const ShiftInstanceSummary({
    required this.id,
    required this.shiftDefinitionCode,
    required this.shiftDefinitionName,
    required this.productionDate,
    required this.startsAt,
    required this.hasSheet,
    this.confirmedAt,
  });

  final String id;
  final String shiftDefinitionCode;
  final String shiftDefinitionName;
  final String productionDate;
  final String startsAt;
  final bool hasSheet;
  final String? confirmedAt;

  factory ShiftInstanceSummary.fromJson(Map<String, dynamic> json) => ShiftInstanceSummary(
        id: json['id'].toString(),
        shiftDefinitionCode: json['shiftDefinitionCode'] as String,
        shiftDefinitionName: json['shiftDefinitionName'] as String,
        productionDate: json['productionDate'] as String,
        startsAt: json['startsAt'] as String,
        hasSheet: json['hasSheet'] == true,
        confirmedAt: json['confirmedAt'] as String?,
      );
}

/// One row of `GET /api/people/attendance-to-confirm` (issue #250) — a past
/// shift instance whose sheet is missing or unconfirmed, restricted to the
/// Org Units the caller's own edit Grants reach (`attendance.js`'s own
/// `listAttendanceToConfirm`). [sheetState] is exactly `attendance.js`'s own
/// `'missing'`/`'unconfirmed'` — a value with a known set, read here rather
/// than re-derived from [hasSheet]/[confirmedAt] the way [ShiftInstanceSummary]
/// carries them, because the worklist's whole reason to exist is that
/// distinction.
class AttendanceToConfirmEntry {
  const AttendanceToConfirmEntry({
    required this.shiftInstanceId,
    required this.siteId,
    required this.siteName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.shiftDefinitionCode,
    required this.shiftDefinitionName,
    required this.productionDate,
    required this.startsAt,
    required this.endsAt,
    required this.sheetState,
  });

  final String shiftInstanceId;
  final String siteId;
  final String siteName;
  final String orgUnitId;
  final String orgUnitName;
  final String shiftDefinitionCode;
  final String shiftDefinitionName;
  final String productionDate;
  final String startsAt;
  final String endsAt;
  final String sheetState;

  bool get isMissing => sheetState == 'missing';

  factory AttendanceToConfirmEntry.fromJson(Map<String, dynamic> json) => AttendanceToConfirmEntry(
        shiftInstanceId: json['shiftInstanceId'].toString(),
        siteId: json['siteId'].toString(),
        siteName: json['siteName'] as String,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String,
        shiftDefinitionCode: json['shiftDefinitionCode'] as String,
        shiftDefinitionName: json['shiftDefinitionName'] as String,
        productionDate: json['productionDate'] as String,
        startsAt: json['startsAt'] as String,
        endsAt: json['endsAt'] as String,
        sheetState: json['sheetState'] as String,
      );
}

/// A human label for [AttendanceToConfirmEntry.sheetState], the same two
/// readings `_ShiftRow` in `attendance_picker_screen.dart` already gives
/// `hasSheet`/`confirmedAt` — kept in step so a shift reads the same way
/// whichever Screen a supervisor found it from.
String attendanceSheetStateLabel(String sheetState) => switch (sheetState) {
      'missing' => 'Not opened yet',
      'unconfirmed' => 'Started, not yet confirmed',
      _ => sheetState,
    };
