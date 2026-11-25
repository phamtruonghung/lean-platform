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
/// **A candidate's paper never carries the key.** The wire shape of one drawn
/// Question on `/assessment-attempts/:id` is a stem, three Options and the
/// candidate's own Answer — the correct Option and the explanation are not in
/// that payload at all, and there is nowhere in [AssessmentPaperQuestion] to
/// hold them by accident. The key travels on two doors only, each modelled
/// separately: the Marking paper ([AssessmentMarkingPaper]) and the result of a
/// marked Attempt ([AssessmentResult]).
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
    this.siteCode,
    this.viewerMayChange = false,
    this.viewerMayMark = false,
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

  /// The Site's code, on the detail read.
  final String? siteCode;

  /// What the server says the caller may do with this Assessment (slice 6):
  /// change it (`CHANGE` with write reach on the process) and mark its Attempts
  /// (`MARK` with reach on the process). Both are false on a read that does not
  /// carry them, so a Screen never offers an action the server did not vouch
  /// for.
  final bool viewerMayChange;
  final bool viewerMayMark;

  bool get isAssigned => status == assessmentAssigned;

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
      siteCode: json['siteCode'] as String?,
      viewerMayChange: json['viewerMayChange'] == true,
      viewerMayMark: json['viewerMayMark'] == true,
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
    this.markedByName,
    this.markingNote,
    this.score,
    this.finalScore,
    this.passed,
    this.scoreHidden = true,
    this.assessmentNumber,
    this.assessmentTitle,
    this.processName,
    this.questionCount,
    this.passMark,
    this.dueOn,
    this.isCounting = false,
    this.isLatest = false,
    this.retakeReason,
    this.viewerMayChange = false,
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

  /// Who marked the Attempt, on a marked one (slice 4).
  final String? markedByName;

  /// The Marker's note, kept with the record (slice 4).
  final String? markingNote;

  /// The machine's number and the Marker's, and the verdict derived from
  /// `finalScore >= passMark` — all `null` when the caller may not read a score
  /// or the Attempt is not marked yet, with [scoreHidden] saying which.
  final int? score;
  final int? finalScore;
  final bool? passed;
  final bool scoreHidden;

  /// Present on the candidate's own list (`/assessment-attempts/mine`): the
  /// Assessment the Attempt belongs to, flattened so one list row needs no
  /// second request.
  final String? assessmentNumber;
  final String? assessmentTitle;
  final String? processName;
  final int? questionCount;
  final int? passMark;
  final String? dueOn;

  /// On the detail read (slice 6): whether this is the person's latest marked
  /// Attempt — the score that counts — and whether no later sitting exists for
  /// them. Both are the server's answer, never worked out here.
  final bool isCounting;
  final bool isLatest;

  /// Why a retake was allowed, on an Attempt that is one.
  final String? retakeReason;

  /// Whether the caller may change this Attempt (`CHANGE` with write reach on
  /// the Attempt's own Org Unit).
  final bool viewerMayChange;

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
      markedByName: json['markedByName'] as String?,
      markingNote: json['markingNote'] as String?,
      score: json['score'] == null ? null : _int(json['score']),
      finalScore: json['finalScore'] == null ? null : _int(json['finalScore']),
      passed: json['passed'] is bool ? json['passed'] as bool : null,
      scoreHidden: json['scoreHidden'] != false,
      assessmentNumber: json['assessmentNumber'] as String?,
      assessmentTitle: json['assessmentTitle'] as String?,
      processName: json['processName'] as String?,
      questionCount: json['questionCount'] == null ? null : _int(json['questionCount']),
      passMark: json['passMark'] == null ? null : _int(json['passMark']),
      dueOn: json['dueOn'] as String?,
      isCounting: json['isCounting'] == true,
      isLatest: json['isLatest'] == true,
      retakeReason: json['retakeReason'] as String?,
      viewerMayChange: json['viewerMayChange'] == true,
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

/// What `POST /api/maintenance/floor/assessments/:attemptId/start` answers: the
/// paper exactly as the Account door's start does, plus the sitting token the
/// floor device presents on every later request (spec section 4.6). The token is
/// shown once, here, and is held by the tab's session storage, never by a state.
@immutable
class FloorAssessmentStart {
  const FloorAssessmentStart({required this.paper, required this.sittingToken});

  final AssessmentPaper paper;
  final String sittingToken;

  factory FloorAssessmentStart.fromJson(Map<String, dynamic> json) {
    return FloorAssessmentStart(
      paper: AssessmentPaper.fromJson(json),
      sittingToken: json['sittingToken'] as String? ?? '',
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

/// One row of the marking queue (`GET /assessment-marking`, slice 4): a
/// `submitted` Attempt in the Marker's write reach, with the flags that decide
/// what to look at first — how many "Khác" answers it holds, and whether the
/// server finalised it late.
@immutable
class AssessmentMarkingEntry {
  const AssessmentMarkingEntry({
    required this.id,
    required this.assessmentId,
    required this.employeeId,
    required this.attemptNo,
    required this.orgUnitId,
    required this.submittedLate,
    required this.otherAnswerCount,
    this.assessmentNumber,
    this.assessmentTitle,
    this.employeeName,
    this.orgUnitName,
    this.processName,
    this.questionCount,
    this.passMark,
    this.submittedAt,
  });

  final String id;
  final String assessmentId;
  final String employeeId;
  final int attemptNo;
  final String orgUnitId;
  final bool submittedLate;

  /// How many drawn Questions carry an Other answer — the count the queue is
  /// read for. A count, never a score, so it is never hidden.
  final int otherAnswerCount;

  final String? assessmentNumber;
  final String? assessmentTitle;
  final String? employeeName;
  final String? orgUnitName;
  final String? processName;
  final int? questionCount;
  final int? passMark;
  final DateTime? submittedAt;

  factory AssessmentMarkingEntry.fromJson(Map<String, dynamic> json) {
    return AssessmentMarkingEntry(
      id: json['id'].toString(),
      assessmentId: json['assessmentId'].toString(),
      employeeId: json['employeeId'].toString(),
      attemptNo: _int(json['attemptNo']),
      orgUnitId: json['orgUnitId'].toString(),
      submittedLate: json['submittedLate'] == true,
      otherAnswerCount: _int(json['otherAnswerCount']),
      assessmentNumber: json['assessmentNumber'] as String?,
      assessmentTitle: json['assessmentTitle'] as String?,
      employeeName: json['employeeName'] as String?,
      orgUnitName: json['orgUnitName'] as String?,
      processName: json['processName'] as String?,
      questionCount: json['questionCount'] == null ? null : _int(json['questionCount']),
      passMark: json['passMark'] == null ? null : _int(json['passMark']),
      submittedAt: _time(json['submittedAt']),
    );
  }
}

/// The queue, and the server's own bound on it (ADR-0026).
@immutable
class AssessmentMarkingQueue {
  const AssessmentMarkingQueue({
    required this.entries,
    required this.total,
    required this.truncated,
  });

  final List<AssessmentMarkingEntry> entries;
  final int total;
  final bool truncated;

  factory AssessmentMarkingQueue.fromJson(Map<String, dynamic> json) {
    return AssessmentMarkingQueue(
      entries: [
        for (final entry in (json['attempts'] as List<dynamic>? ?? const []))
          AssessmentMarkingEntry.fromJson(entry as Map<String, dynamic>),
      ],
      total: _int(json['total']),
      truncated: json['truncated'] == true,
    );
  }
}

/// One Question as the Marker and the result read it: the same stem and three
/// Options the candidate saw, plus the key, the explanation and the point. The
/// candidate's paper ([AssessmentPaperQuestion]) deliberately has no field for
/// the key; this one exists only for the two doors that may carry it.
@immutable
class AssessmentMarkedQuestion {
  const AssessmentMarkedQuestion({
    required this.position,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.correctOption,
    required this.points,
    this.explanation,
    this.chosenOption,
    this.otherText,
  });

  final int position;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;

  /// The key: one of `A`, `B`, `C`.
  final String correctOption;
  final String? explanation;
  final String? chosenOption;
  final String? otherText;

  /// The point on this Answer — the machine's, or the Marker's after the award.
  final int points;

  bool get isOther => otherText != null;
  bool get isBlank => chosenOption == null && otherText == null;

  String? optionText(String? letter) => switch (letter) {
        'A' => optionA,
        'B' => optionB,
        'C' => optionC,
        _ => null,
      };

  AssessmentMarkedQuestion withPoints(int next) => AssessmentMarkedQuestion(
        position: position,
        questionText: questionText,
        optionA: optionA,
        optionB: optionB,
        optionC: optionC,
        correctOption: correctOption,
        points: next,
        explanation: explanation,
        chosenOption: chosenOption,
        otherText: otherText,
      );

  factory AssessmentMarkedQuestion.fromJson(Map<String, dynamic> json) {
    return AssessmentMarkedQuestion(
      position: _int(json['position']),
      questionText: json['questionText'] as String? ?? '',
      optionA: json['optionA'] as String? ?? '',
      optionB: json['optionB'] as String? ?? '',
      optionC: json['optionC'] as String? ?? '',
      correctOption: json['correctOption'] as String? ?? '',
      points: _int(json['points']),
      explanation: json['explanation'] as String?,
      chosenOption: json['chosenOption'] as String?,
      otherText: json['otherText'] as String?,
    );
  }
}

/// One Attempt's marking paper (`GET /assessment-attempts/:id/marking`): the
/// Attempt, and every Question with its key, its Answer and its point.
@immutable
class AssessmentMarkingPaper {
  const AssessmentMarkingPaper({required this.attempt, required this.questions});

  final AssessmentAttempt attempt;
  final List<AssessmentMarkedQuestion> questions;

  int get totalPoints => questions.fold(0, (sum, question) => sum + question.points);
  int get otherCount => questions.where((question) => question.isOther).length;

  AssessmentMarkingPaper withPoints(Map<int, int> points) => AssessmentMarkingPaper(
        attempt: attempt,
        questions: [
          for (final question in questions)
            points.containsKey(question.position)
                ? question.withPoints(points[question.position]!)
                : question,
        ],
      );

  factory AssessmentMarkingPaper.fromJson(Map<String, dynamic> json) {
    return AssessmentMarkingPaper(
      attempt: AssessmentAttempt.fromJson(json['attempt'] as Map<String, dynamic>),
      questions: [
        for (final question in (json['questions'] as List<dynamic>? ?? const []))
          AssessmentMarkedQuestion.fromJson(question as Map<String, dynamic>),
      ],
    );
  }
}

/// The verdict a marked Attempt carries: both numbers and the pass mark, with
/// pass/fail **derived by the server** at read and never stored (spec section
/// 3.13) — this class only carries the three numbers and the answer.
@immutable
class AssessmentVerdict {
  const AssessmentVerdict({
    required this.passMark,
    required this.questionCount,
    required this.passed,
    this.score,
    this.finalScore,
  });

  final int? score;
  final int? finalScore;
  final int passMark;
  final int questionCount;
  final bool passed;

  factory AssessmentVerdict.fromJson(Map<String, dynamic> json) {
    return AssessmentVerdict(
      score: json['score'] == null ? null : _int(json['score']),
      finalScore: json['finalScore'] == null ? null : _int(json['finalScore']),
      passMark: _int(json['passMark']),
      questionCount: _int(json['questionCount']),
      passed: json['passed'] == true,
    );
  }
}

/// One marked Attempt's result (`GET /assessment-attempts/:id/result`): the
/// Attempt, the verdict, and every Question with the candidate's Answer, the
/// key, the point and the explanation.
@immutable
class AssessmentResult {
  const AssessmentResult({
    required this.attempt,
    required this.verdict,
    required this.questions,
  });

  final AssessmentAttempt attempt;
  final AssessmentVerdict verdict;
  final List<AssessmentMarkedQuestion> questions;

  factory AssessmentResult.fromJson(Map<String, dynamic> json) {
    return AssessmentResult(
      attempt: AssessmentAttempt.fromJson(json['attempt'] as Map<String, dynamic>),
      verdict: AssessmentVerdict.fromJson(json['verdict'] as Map<String, dynamic>),
      questions: [
        for (final question in (json['questions'] as List<dynamic>? ?? const []))
          AssessmentMarkedQuestion.fromJson(question as Map<String, dynamic>),
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
