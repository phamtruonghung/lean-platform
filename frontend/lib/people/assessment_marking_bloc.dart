/// Marking one paper (issue #588, ADR-0068, slice 4): the key, the candidate's
/// Answers, the point on each, and the award.
///
/// **Both scores are on the Screen.** `score` is what the machine made of the
/// paper at submit and never moves; `finalScore` is what the award makes of it.
/// Before the award the second is empty — a paper that has not been marked has
/// no final score, and the Screen must not compute one from the drafts, because
/// the server derives it and the two must never disagree (spec section 3.13).
///
/// **The drafts are the Marker's edits, not the truth.** Every 0/1 control writes
/// a local draft; `Save` sends only the positions the Marker actually changed,
/// plus the note. Everything else keeps the machine's point, so a fully correct
/// paper needs no interference at all.
///
/// A second `mark` is a 409 on the server: an award is a record, and this Bloc
/// surfaces that refusal instead of retrying it.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

sealed class AssessmentMarkingEvent {
  const AssessmentMarkingEvent();
}

/// Load the paper. Also the retry a failed load offers.
class AssessmentMarkingStarted extends AssessmentMarkingEvent {
  const AssessmentMarkingStarted(this.attemptId);

  final String attemptId;
}

/// The Marker set one Answer's point. `points` is 0 or 1.
class AssessmentMarkingPointSet extends AssessmentMarkingEvent {
  const AssessmentMarkingPointSet(this.position, this.points);

  final int position;
  final int points;
}

/// The Marker typed one Answer's note.
class AssessmentMarkingAnswerNoteChanged extends AssessmentMarkingEvent {
  const AssessmentMarkingAnswerNoteChanged(this.position, this.note);

  final int position;
  final String note;
}

/// The Marker typed the Attempt's own note.
class AssessmentMarkingNoteChanged extends AssessmentMarkingEvent {
  const AssessmentMarkingNoteChanged(this.note);

  final String note;
}

/// Award the paper and mark the Attempt.
class AssessmentMarkingSubmitted extends AssessmentMarkingEvent {
  const AssessmentMarkingSubmitted();
}

sealed class AssessmentMarkingState {
  const AssessmentMarkingState();
}

class AssessmentMarkingLoading extends AssessmentMarkingState {
  const AssessmentMarkingLoading();
}

class AssessmentMarkingUnavailable extends AssessmentMarkingState {
  const AssessmentMarkingUnavailable({required this.message});

  final String message;
}

class AssessmentMarkingLoaded extends AssessmentMarkingState {
  const AssessmentMarkingLoaded({
    required this.paper,
    this.drafts = const {},
    this.answerNotes = const {},
    this.note = '',
    this.isSaving = false,
    this.notice,
    this.marked = false,
  });

  final AssessmentMarkingPaper paper;

  /// The points the Marker set, by position. A position absent from this map
  /// keeps the machine's point.
  final Map<int, int> drafts;
  final Map<int, String> answerNotes;
  final String note;
  final bool isSaving;

  /// A sentence the Screen shows once: a refusal, or why the save failed.
  final String? notice;

  /// The award landed; the Screen moves to the result.
  final bool marked;

  /// The point on one Answer as it stands: the draft if the Marker set one,
  /// otherwise the machine's.
  int pointsFor(AssessmentMarkedQuestion question) =>
      drafts[question.position] ?? question.points;

  /// What the award would make of the paper — for the running total the Screen
  /// shows beside the machine's score. It is a preview, never the record.
  int get draftTotal =>
      paper.questions.fold(0, (sum, question) => sum + pointsFor(question));

  /// Only the positions the Marker changed are sent.
  Map<int, int> get changedPoints {
    return {
      for (final entry in drafts.entries)
        if (paper.questions.any(
          (question) => question.position == entry.key && question.points != entry.value,
        ))
          entry.key: entry.value,
    };
  }

  AssessmentMarkingLoaded copyWith({
    AssessmentMarkingPaper? paper,
    Map<int, int>? drafts,
    Map<int, String>? answerNotes,
    String? note,
    bool? isSaving,
    String? notice,
    bool clearNotice = false,
    bool? marked,
  }) {
    return AssessmentMarkingLoaded(
      paper: paper ?? this.paper,
      drafts: drafts ?? this.drafts,
      answerNotes: answerNotes ?? this.answerNotes,
      note: note ?? this.note,
      isSaving: isSaving ?? this.isSaving,
      notice: clearNotice ? null : (notice ?? this.notice),
      marked: marked ?? this.marked,
    );
  }
}

class AssessmentMarkingBloc extends Bloc<AssessmentMarkingEvent, AssessmentMarkingState> {
  AssessmentMarkingBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.attemptId,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentMarkingLoading()) {
    on<AssessmentMarkingStarted>(_onStarted);
    on<AssessmentMarkingPointSet>(_onPointSet);
    on<AssessmentMarkingAnswerNoteChanged>(_onAnswerNoteChanged);
    on<AssessmentMarkingNoteChanged>(_onNoteChanged);
    on<AssessmentMarkingSubmitted>(_onSubmitted);
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  final String attemptId;

  static const String signedOutMessage = BlocNotice.sessionEnded;
  static const String alreadyMarkedMessage =
      'This Assessment was already marked, and an award is a record: it cannot be given twice.';

  Future<void> _onStarted(
    AssessmentMarkingStarted event,
    Emitter<AssessmentMarkingState> emit,
  ) async {
    emit(const AssessmentMarkingLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentMarkingUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final paper = await _api.fetchAssessmentMarkingPaper(token, event.attemptId);
      emit(AssessmentMarkingLoaded(paper: paper));
    } on PeopleApiException catch (error) {
      emit(AssessmentMarkingUnavailable(message: error.message));
    }
  }

  void _onPointSet(AssessmentMarkingPointSet event, Emitter<AssessmentMarkingState> emit) {
    final current = state;
    if (current is! AssessmentMarkingLoaded || current.marked) return;
    final drafts = Map<int, int>.from(current.drafts)..[event.position] = event.points;
    emit(current.copyWith(drafts: drafts, clearNotice: true));
  }

  void _onAnswerNoteChanged(
    AssessmentMarkingAnswerNoteChanged event,
    Emitter<AssessmentMarkingState> emit,
  ) {
    final current = state;
    if (current is! AssessmentMarkingLoaded || current.marked) return;
    final notes = Map<int, String>.from(current.answerNotes)..[event.position] = event.note;
    emit(current.copyWith(answerNotes: notes));
  }

  void _onNoteChanged(AssessmentMarkingNoteChanged event, Emitter<AssessmentMarkingState> emit) {
    final current = state;
    if (current is! AssessmentMarkingLoaded || current.marked) return;
    emit(current.copyWith(note: event.note));
  }

  Future<void> _onSubmitted(
    AssessmentMarkingSubmitted event,
    Emitter<AssessmentMarkingState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentMarkingLoaded || current.isSaving || current.marked) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentMarkingUnavailable(message: signedOutMessage));
      return;
    }

    emit(current.copyWith(isSaving: true, clearNotice: true));
    try {
      final paper = await _api.markAssessmentAttempt(
        token,
        attemptId,
        points: current.changedPoints,
        note: current.note.trim().isEmpty ? null : current.note.trim(),
        notes: {
          for (final entry in current.answerNotes.entries)
            if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        },
      );
      emit(current.copyWith(paper: paper, isSaving: false, marked: true));
    } on PeopleApiException catch (error) {
      emit(current.copyWith(
        isSaving: false,
        notice: error.statusCode == 409 ? alreadyMarkedMessage : error.message,
      ));
    }
  }
}
