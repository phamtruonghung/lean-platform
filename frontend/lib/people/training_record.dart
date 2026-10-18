/// The Training record's own model (issue #287, ADR-0043, CONTEXT.md's
/// Training section) — one occasion of training delivered: what it was, the
/// day it was given, how long it lasted, who gave it. Mirrors
/// `toTrainingRecord` (backend/src/modules/people/training.js) key for key.
library;

import '../status_tone.dart';

/// One Trainee on a Training record (issue #288): an Employee who was trained
/// on it. Mirrors the rows `listTrainees` (training.js) sends.
class TrainingTrainee {
  const TrainingTrainee({
    required this.id,
    required this.employeeId,
    required this.employeeNo,
    required this.employeeName,
  });

  /// The Trainee row's own id — what a removal names, not the Employee's.
  final String id;
  final String employeeId;
  final String employeeNo;
  final String employeeName;

  factory TrainingTrainee.fromJson(Map<String, dynamic> json) => TrainingTrainee(
        id: json['id'].toString(),
        employeeId: json['employeeId'].toString(),
        employeeNo: json['employeeNo'] as String,
        employeeName: json['employeeName'] as String,
      );
}

class TrainingRecord {
  const TrainingRecord({
    required this.id,
    required this.siteId,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.number,
    required this.title,
    required this.trainedOn,
    required this.durationHours,
    required this.status,
    this.trainerEmployeeId,
    this.trainerName,
    this.objective,
    this.trainees = const [],
    this.traineeCount = 0,
  });

  final String id;
  final String siteId;
  final String orgUnitId;
  final String orgUnitName;

  /// The record's own Site-scoped number (e.g. `TR-HCM-2026-00001`).
  final String number;
  final String title;

  /// `YYYY-MM-DD`, the day the training was given.
  final String trainedOn;
  final double durationHours;

  /// `draft` or `sent` — a value with a known set (ADR-0043).
  final String status;
  final String? trainerEmployeeId;
  final String? trainerName;
  final String? objective;

  /// The Trainees in the order they were added. Only the record's own read
  /// carries them; a register row has none and reads as an empty list.
  final List<TrainingTrainee> trainees;
  final int traineeCount;

  bool get isDraft => status == 'draft';

  String get statusLabel => trainingStatusLabel(status);

  factory TrainingRecord.fromJson(Map<String, dynamic> json) => TrainingRecord(
        id: json['id'].toString(),
        siteId: json['siteId'].toString(),
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String,
        number: json['number'] as String,
        title: json['title'] as String,
        trainedOn: json['trainedOn'] as String,
        durationHours: (json['durationHours'] as num).toDouble(),
        status: json['status'] as String,
        trainerEmployeeId: json['trainerEmployeeId']?.toString(),
        trainerName: json['trainerName'] as String?,
        objective: json['objective'] as String?,
        trainees: [
          for (final trainee in (json['trainees'] as List<dynamic>? ?? const []))
            TrainingTrainee.fromJson(trainee as Map<String, dynamic>),
        ],
        traineeCount: (json['traineeCount'] as num?)?.toInt() ?? 0,
      );
}

String trainingStatusLabel(String status) => switch (status) {
      'draft' => 'Draft',
      'sent' => 'Sent',
      _ => status,
    };

StatusTone trainingStatusTone(String status) => switch (status) {
      'sent' => StatusTone.success,
      _ => StatusTone.neutral,
    };

/// `2 h`, `1.5 h` — whole hours without a decimal point.
String formatTrainingHours(double hours) {
  final text = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();
  return '$text h';
}
