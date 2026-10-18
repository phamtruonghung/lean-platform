/// The Training record's own model (issue #287, ADR-0043, CONTEXT.md's
/// Training section) — one occasion of training delivered: what it was, the
/// day it was given, how long it lasted, who gave it. Mirrors
/// `toTrainingRecord` (backend/src/modules/people/training.js) key for key.
library;

import '../status_tone.dart';

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
