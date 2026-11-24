/// Assessments and their Attempts (issue #588, ADR-0068, slice 3).
///
/// An **Assessment** is the check's own definition: a process whose bank is
/// drawn, a title, a paper size, how long a sitting runs, the pass mark, how
/// many Attempts one Employee may have, an optional due date and a status.
/// An **Attempt** is one Employee's sitting of it, with the paper drawn at the
/// moment they start.
///
/// **Nothing here decides a fact.** The status, the deadline, whether a paper
/// is still running, and every count come from the server as they are: this
/// client renders them and never re-derives one from the device clock, the same
/// discipline `WorkOrder` keeps for its own server-decided fields.
///
/// **A paper never carries the key.** The wire shape of one drawn Question is
/// a stem, three Options and the candidate's own Answer — the correct Option
/// and the explanation are not in the payload until the Attempt is marked
/// (slice 4), and there is nowhere in this file to hold them by accident.
library;

import 'package:flutter/foundation.dart';

/// The statuses an Assessment moves through: a draft names nobody, an assigned
/// one carries Attempts, a closed one takes no more.
const String assessmentDraft = 'draft';
const String assessmentAssigned = 'assigned';
const String assessmentClosed = 'closed';

/// The statuses one Employee's Attempt moves through.
const String attemptAssigned = 'assigned';
const String attemptInProgress = 'in_progress';
const String attemptSubmitted = 'submitted';
const String attemptMarked = 'marked';
const String attemptExpired = 'expired';
const String attemptCancelled = 'cancelled';

@immutable
class Assessment {
  const Assessment({
    required this.id,
    required this.siteId,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.number,
    required this.title,
    required this.questionCount,
    required this.minutes,
    required this.passMark,
    required this.attemptsAllowed,
    required this.dueOn,
    required this.status,
    required this.assignedCount,
    required this.runningCount,
    required this.awaitingMarkingCount,
    required this.markedCount,
    this.attempts = const [],
  });

  final String id;
  final String siteId;
  final String orgUnitId;

  /// The **process** whose bank a paper is drawn from — never the group's Org
  /// Unit and never where a candidate works.
  final String? orgUnitName;
  final String number;
  final String title;
  final int questionCount;
  final int minutes;
  final int passMark;
  final int attemptsAllowed;

  /// The last day an Attempt may be started, `YYYY-MM-DD`, or null.
  final String? dueOn;
  final String status;

  /// How many Attempts exist, and how many sit in each state. Counts, never
  /// scores, so they are never hidden from anyone.
  final int assignedCount;
  final int runningCount;
  final int awaitingMarkingCount;
  final int markedCount;

  /// Every Attempt, on the detail read; empty on a register row.
  final List<AssessmentAttempt> attempts;

  bool get isDraft => status == assessmentDraft;
  bool get isClosed => status == assessmentClosed;

  int get attemptCount =>
      assignedCount + runningCount + awaitingMarkingCount + markedCount;

  factory Assessment.fromJson(Map<String, dynamic> json) {
    return Assessment(
      id: json['id'].toString(),
      siteId: json['siteId'].toString(),
      orgUnitId: json['orgUnitId'].toString(),
      orgUnitName: json['orgUnitName'] as String?,
      number: json['number'] as String? ?? '',
      title: json['title'] as String? ?? '',
      questionCount: _int(json['questionCount']),
      minutes: _int(json['minutes']),
      passMark: _int(json['passMark']),
      attemptsAllowed: _int(json['attemptsAllowed']),
      dueOn: json['dueOn'] as String?,
      status: json['status'] as String? ?? assessmentDraft,
      assignedCount: _int(json['assignedCount']),
      runningCount: _int(json['runningCount']),
      awaitingMarkingCount: _int(json['awaitingMarkingCount']),
      markedCount: _int(json['markedCount']),
      attempts: [
        for (final attempt in (json['attempts'] as List<dynamic>? ?? const []))
          AssessmentAttempt.fromJson(attempt as Map<String, dynamic>),
      ],
    );
  }
}

@immutable
class AssessmentAttempt {
  const AssessmentAttempt({
    required this.id,
    required this.assessmentId,
    required this.employeeId,
    required this.attemptNo,
    required this.orgUnitId,
    required this.orgUnitResolvedOn,
    required this.status,
    required this.submittedLate,
    required this.otherAnswerCount,
    required this.blankCount,
    this.employeeName,
    this.orgUnitName,
    this.startedAt,
    this.deadlineAt,
    this.submittedAt,
    this.assessmentNumber,
    this.assessmentTitle,
    this.processName,
    this.questionCount,
    this.passMark,
    this.dueOn,
  });

  final String id;
  final String assessmentId;
  final String employeeId;
  final int attemptNo;

  /// Where the person works — a snapshot with the day it was resolved. Not the
  /// process the paper was drawn from.
  final String orgUnitId;
  final String orgUnitResolvedOn;
  final String status;
  final bool submittedLate;

  /// How many drawn Questions carry an Other answer, and how many were left
  /// blank. Both counts, so neither is hidden.
  final int otherAnswerCount;
  final int blankCount;

  final String? employeeName;
  final String? orgUnitName;
  final DateTime? startedAt;
  final DateTime? deadlineAt;
  final DateTime? submittedAt;

  /// Present on the candidate's own list (`/assessment-attempts/mine`): the
  /// Assessment the Attempt belongs to, flattened so one list row needs no
  /// second request.
  final String? assessmentNumber;
  final String? assessmentTitle;
  final String? processName;
  final int? questionCount;
  final int? passMark;
  final String? dueOn;

  bool get isRunning => status == attemptInProgress;
  bool get isFinal =>
      status == attemptSubmitted ||
      status == attemptMarked ||
      status == attemptExpired ||
      status == attemptCancelled;

  factory AssessmentAttempt.fromJson(Map<String, dynamic> json) {
    return AssessmentAttempt(
      id: json['id'].toString(),
      assessmentId: json['assessmentId'].toString(),
      employeeId: json['employeeId'].toString(),
      attemptNo: _int(json['attemptNo']),
      orgUnitId: json['orgUnitId'].toString(),
      orgUnitResolvedOn: json['orgUnitResolvedOn'] as String? ?? '',
      status: json['status'] as String? ?? attemptAssigned,
      submittedLate: json['submittedLate'] == true,
      otherAnswerCount: _int(json['otherAnswerCount']),
      blankCount: _int(json['blankCount']),
      employeeName: json['employeeName'] as String?,
      orgUnitName: json['orgUnitName'] as String?,
      startedAt: _time(json['startedAt']),
      deadlineAt: _time(json['deadlineAt']),
      submittedAt: _time(json['submittedAt']),
      assessmentNumber: json['assessmentNumber'] as String?,
      assessmentTitle: json['assessmentTitle'] as String?,
      processName: json['processName'] as String?,
      questionCount: json['questionCount'] == null ? null : _int(json['questionCount']),
      passMark: json['passMark'] == null ? null : _int(json['passMark']),
      dueOn: json['dueOn'] as String?,
    );
  }
}

/// One drawn Question, as the candidate sees it: the stem, its three Options,
/// and their own Answer. There is deliberately no field for the key or the
/// explanation — the payload does not carry them.
@immutable
class AssessmentPaperQuestion {
  const AssessmentPaperQuestion({
    required this.position,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    this.chosenOption,
    this.otherText,
  });

  final int position;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;

  /// The Option picked, `A`/`B`/`C`, or null.
  final String? chosenOption;

  /// The Other answer's text ("Khác"), or null. Never both.
  final String? otherText;

  bool get isAnswered => chosenOption != null || otherText != null;

  /// The Option's own text for a letter, or null when the letter is not one of
  /// the three.
  String? optionText(String? letter) => switch (letter) {
        'A' => optionA,
        'B' => optionB,
        'C' => optionC,
        _ => null,
      };

  factory AssessmentPaperQuestion.fromJson(Map<String, dynamic> json) {
    return AssessmentPaperQuestion(
      position: _int(json['position']),
      questionText: json['questionText'] as String? ?? '',
      optionA: json['optionA'] as String? ?? '',
      optionB: json['optionB'] as String? ?? '',
      optionC: json['optionC'] as String? ?? '',
      chosenOption: json['chosenOption'] as String?,
      otherText: json['otherText'] as String?,
    );
  }
}

/// One Attempt's paper plus the clock the client counts from: `serverNow` and
/// `deadlineAt` are the server's own instants, so a wrong tablet clock changes
/// nothing about how long is left.
@immutable
class AssessmentPaper {
  const AssessmentPaper({
    required this.attempt,
    required this.questions,
    required this.serverNow,
  });

  final AssessmentAttempt attempt;
  final List<AssessmentPaperQuestion> questions;
  final DateTime serverNow;

  bool get isRunning => attempt.isRunning;

  /// How long is left at the moment the payload was produced. Counted down from
  /// the difference of two server instants, then by a monotonic stopwatch — the
  /// device's wall clock is never consulted again.
  Duration get remainingAtFetch {
    final deadline = attempt.deadlineAt;
    if (deadline == null) return Duration.zero;
    final left = deadline.difference(serverNow);
    return left.isNegative ? Duration.zero : left;
  }

  factory AssessmentPaper.fromJson(Map<String, dynamic> json) {
    return AssessmentPaper(
      attempt: AssessmentAttempt.fromJson(json['attempt'] as Map<String, dynamic>),
      questions: [
        for (final question in (json['paper'] as List<dynamic>? ?? const []))
          AssessmentPaperQuestion.fromJson(question as Map<String, dynamic>),
      ],
      serverNow: _time(json['serverNow']) ?? DateTime.now().toUtc(),
    );
  }
}

/// One page of the register (`GET /assessments`): the rows, how many the filter
/// matches, and whether the server's own bound cut the list short.
@immutable
class AssessmentPage {
  const AssessmentPage({
    required this.assessments,
    required this.total,
    required this.truncated,
  });

  final List<Assessment> assessments;
  final int total;
  final bool truncated;

  factory AssessmentPage.fromJson(Map<String, dynamic> json) {
    return AssessmentPage(
      assessments: [
        for (final assessment in (json['assessments'] as List<dynamic>? ?? const []))
          Assessment.fromJson(assessment as Map<String, dynamic>),
      ],
      total: _int(json['total']),
      truncated: json['truncated'] == true,
    );
  }
}

/// How many Employees an assign group reaches, and how many of them have no Org
/// Unit to answer to (`GET /assessments/assign-preview`). The server answers it
/// with the same expansion `/assign` runs, so the number on the create form and
/// the number of Attempts created cannot disagree.
@immutable
class AssignPreview {
  const AssignPreview({
    required this.count,
    required this.unresolvedCount,
    required this.unresolvedNames,
  });

  final int count;
  final int unresolvedCount;
  final List<String> unresolvedNames;

  factory AssignPreview.fromJson(Map<String, dynamic> json) {
    return AssignPreview(
      count: _int(json['count']),
      unresolvedCount: _int(json['unresolvedCount']),
      unresolvedNames: [
        for (final row in (json['unresolved'] as List<dynamic>? ?? const []))
          (row as Map<String, dynamic>)['displayName'] as String? ?? '',
      ],
    );
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _time(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
