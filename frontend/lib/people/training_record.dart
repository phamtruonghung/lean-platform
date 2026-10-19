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
    this.answer,
    this.answeredAt,
    this.answeredVia,
    this.evaluation,
  });

  /// The Trainee row's own id — what a removal names, not the Employee's.
  final String id;
  final String employeeId;
  final String employeeNo;
  final String employeeName;

  /// `confirmed` or `declined`; null while the Trainee has not answered
  /// (issue #289). Pending is never inferred from anything else.
  final String? answer;

  /// When the answer was given (an ISO timestamp), null while pending.
  final String? answeredAt;

  /// The door the answer came through — `account` (their own Account) or
  /// `device` (identified at the shared floor device); null while pending.
  final String? answeredVia;

  /// How the trainer recorded this Trainee was evaluated - `paper` or
  /// `job_training` (issue #290), a value with a known set; null until the
  /// trainer says so.
  final String? evaluation;

  bool get hasAnswered => answer != null;

  factory TrainingTrainee.fromJson(Map<String, dynamic> json) => TrainingTrainee(
        id: json['id'].toString(),
        employeeId: json['employeeId'].toString(),
        employeeNo: json['employeeNo'] as String,
        employeeName: json['employeeName'] as String,
        answer: json['answer'] as String?,
        answeredAt: json['answeredAt'] as String?,
        answeredVia: json['answeredVia'] as String?,
        evaluation: json['evaluation'] as String?,
      );
}

/// One row of `GET /api/people/training/to-confirm` (issue #289): a sent
/// record the caller is a Trainee on and has not answered. [traineeId] is the
/// Trainee row's own id — what an answer names.
class TrainingToConfirm {
  const TrainingToConfirm({
    required this.traineeId,
    required this.id,
    required this.number,
    required this.title,
    required this.trainedOn,
    required this.durationHours,
    required this.orgUnitName,
    this.trainerName,
    this.objective,
  });

  final String traineeId;
  final String id;
  final String number;
  final String title;
  final String trainedOn;
  final double durationHours;
  final String orgUnitName;
  final String? trainerName;
  final String? objective;

  factory TrainingToConfirm.fromJson(Map<String, dynamic> json) => TrainingToConfirm(
        traineeId: json['traineeId'].toString(),
        id: json['id'].toString(),
        number: json['number'] as String,
        title: json['title'] as String,
        trainedOn: json['trainedOn'] as String,
        durationHours: (json['durationHours'] as num).toDouble(),
        orgUnitName: json['orgUnitName'] as String,
        trainerName: json['trainerName'] as String?,
        objective: json['objective'] as String?,
      );
}

/// The register's answer: the records and whether the server capped the list
/// (ADR-0026) — said on screen rather than inferred from a list that happens
/// to end.
class TrainingRegister {
  const TrainingRegister({required this.records, required this.truncated});

  final List<TrainingRecord> records;
  final bool truncated;
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
    this.answeredCount = 0,
    this.confirmedCount = 0,
    this.declinedCount = 0,
    this.fullyConfirmed = false,
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

  /// The record's reading of its Trainees' answers, computed by the server
  /// from the rows and never stored (issue #289): nobody asked
  /// ([answeredCount] 0), a decline among the answers ([declinedCount] > 0),
  /// or [fullyConfirmed] — every Trainee confirmed.
  final int answeredCount;
  final int confirmedCount;
  final int declinedCount;
  final bool fullyConfirmed;

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
        answeredCount: (json['answeredCount'] as num?)?.toInt() ?? 0,
        confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
        declinedCount: (json['declinedCount'] as num?)?.toInt() ?? 0,
        fullyConfirmed: json['fullyConfirmed'] as bool? ?? false,
      );
}

/// The two methods a Trainee can have been evaluated by, in the order the
/// picker offers them (issue #290).
const List<String> trainingEvaluations = ['paper', 'job_training'];

String trainingEvaluationLabel(String evaluation) => switch (evaluation) {
      'paper' => 'Paper',
      'job_training' => 'Job-training',
      _ => evaluation,
    };

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
