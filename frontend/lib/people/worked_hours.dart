/// The per-Employee worked-hours summary's own model (issue #263): one
/// Employee's confirmed scheduled/worked/overtime minutes across a date
/// window, day by day plus totals, read from `GET
/// /api/people/employees/:employeeId/work-hours`.
///
/// The backend only ever sums *confirmed* attendance sheets (attendance.js's
/// own header on `summariseEmployeeWorkedHours`): an unconfirmed sheet is a
/// draft a supervisor may still correct, so its minutes are not yet fact. A
/// day inside the window with no confirmed sheet is absent from [days] — it
/// is never counted as zero, because a planted 0 hours would be
/// indistinguishable from "truly stood down", the same reason exposure hours
/// stay unknown rather than silently understating.
library;

/// One production day's confirmed minutes, summed across every shift the
/// Employee worked that day (`summariseEmployeeWorkedHours`'s per-day row).
/// [minutes] are stored as integers, not hours, because 7 hours 30 minutes
/// is a distinct fact from 7 hours — CONTEXT.md's Worked hours entry is
/// explicit that a shift's default is *minutes*.
class WorkedHoursDay {
  const WorkedHoursDay({
    required this.date,
    required this.scheduledMinutes,
    required this.workedMinutes,
    required this.overtimeMinutes,
  });

  final String date;
  final int scheduledMinutes;
  final int workedMinutes;
  final int overtimeMinutes;

  factory WorkedHoursDay.fromJson(Map<String, dynamic> json) => WorkedHoursDay(
        date: json['date'] as String,
        scheduledMinutes: (json['scheduledMinutes'] as num).toInt(),
        workedMinutes: (json['workedMinutes'] as num).toInt(),
        overtimeMinutes: (json['overtimeMinutes'] as num).toInt(),
      );
}

/// The whole worked-hours summary: the ordered [days] plus the [totals]
/// across the window. A person reading the Screen wants the window's bottom
/// line beside the day-by-day — both arrive from one read so they can never
/// disagree the way two fetches could.
class EmployeeWorkedHours {
  const EmployeeWorkedHours({required this.days, required this.totals});

  final List<WorkedHoursDay> days;
  final WorkedHoursTotals totals;

  factory EmployeeWorkedHours.fromJson(Map<String, dynamic> json) =>
      EmployeeWorkedHours(
        days: [
          for (final day in json['days'] as List<dynamic>)
            WorkedHoursDay.fromJson(day as Map<String, dynamic>),
        ],
        totals: WorkedHoursTotals.fromJson(json['totals'] as Map<String, dynamic>),
      );
}

/// The window's sums, computed from the same confirmed rows server-side so
/// the client never re-derives a total that could differ from the days.
class WorkedHoursTotals {
  const WorkedHoursTotals({
    required this.scheduledMinutes,
    required this.workedMinutes,
    required this.overtimeMinutes,
  });

  final int scheduledMinutes;
  final int workedMinutes;
  final int overtimeMinutes;

  factory WorkedHoursTotals.fromJson(Map<String, dynamic> json) => WorkedHoursTotals(
        scheduledMinutes: (json['scheduledMinutes'] as num).toInt(),
        workedMinutes: (json['workedMinutes'] as num).toInt(),
        overtimeMinutes: (json['overtimeMinutes'] as num).toInt(),
      );
}

/// Formats a minute count the way the floor reads a shift — "7h 30m", "0h
/// 0m" — rather than as a bare integer. Hours are whole minutes divided; the
/// remainder is minutes. Negative inputs cannot occur (the baseline's
/// CHECKs refuse them), so the format assumes a non-negative value.
String formatWorkedMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return '${hours}h ${mins}m';
}