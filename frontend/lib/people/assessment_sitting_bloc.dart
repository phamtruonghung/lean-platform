/// The sitting's own state (issue #588, ADR-0068, slice 3): the paper, which
/// Question is on screen, the autosave and the submit.
///
/// **The paper comes from the server, once.** `POST .../start` is idempotent, so
/// a refresh gets the same paper and the same deadline; nothing here re-draws,
/// re-orders or re-derives a Question.
///
/// **The clock is the server's.** [AssessmentPaper.remainingAtFetch] is the
/// difference between two server instants; the Screen counts it down with a
/// monotonic stopwatch and never reads the device's wall clock. When it reaches
/// zero the Screen asks for the paper again, and the server — which has already
/// finalised the Attempt by its own clock — answers `submitted`.
///
/// **Every change is saved as it is made.** An Option tap is one `PATCH`; the
/// Other answer is one `PATCH` after the typist stops. A save that lands bumps
/// [AssessmentSittingLoaded.savedTick], which is what the Screen's quiet tick
/// watches; a save the server refuses is the server's sentence, and the Attempt
/// is re-read because a 409 past the deadline means the paper has closed.
///
/// **Submitting is the candidate's own act, once.** The confirmation names how
/// many Questions are still unanswered (the Screen builds that sentence); the
/// Bloc only sends the submit and holds what came back.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

sealed class AssessmentSittingEvent {
  const AssessmentSittingEvent();
}

/// Start or resume: `POST .../start`, which is idempotent.
class AssessmentSittingStarted extends AssessmentSittingEvent {
  const AssessmentSittingStarted(this.attemptId);

  final String attemptId;
}

/// An Option was picked, or the Answer was cleared.
class AssessmentSittingOptionChosen extends AssessmentSittingEvent {
  const AssessmentSittingOptionChosen({required this.position, required this.option});

  final int position;

  /// `A`, `B`, `C`, or null for a blank Answer.
  final String? option;
}

/// The Other answer's text changed. The Screen debounces it; this Bloc saves
/// what it is given.
class AssessmentSittingOtherChanged extends AssessmentSittingEvent {
  const AssessmentSittingOtherChanged({required this.position, required this.text});

  final int position;
  final String text;
}

/// The navigator moved between Questions.
class AssessmentSittingMoved extends AssessmentSittingEvent {
  const AssessmentSittingMoved(this.index);

  final int index;
}

/// The countdown reached zero: the server owns the finalise, so ask it for the
/// paper again rather than deciding here that the sitting is over.
class AssessmentSittingExpired extends AssessmentSittingEvent {
  const AssessmentSittingExpired();
}

class AssessmentSittingSubmitted extends AssessmentSittingEvent {
  const AssessmentSittingSubmitted();
}

sealed class AssessmentSittingState {
  const AssessmentSittingState();
}

class AssessmentSittingLoading extends AssessmentSittingState {
  const AssessmentSittingLoading();
}

class AssessmentSittingUnavailable extends AssessmentSittingState {
  const AssessmentSittingUnavailable({required this.message});

  final String message;
}

class AssessmentSittingLoaded extends AssessmentSittingState {
  const AssessmentSittingLoaded({
    required this.paper,
    this.index = 0,
    this.saving = false,
    this.savedTick = 0,
    this.saveFailure,
    this.submitting = false,
    this.submitFailure,
    this.submitted = false,
  });

  final AssessmentPaper paper;
  final int index;
  final bool saving;

  /// Bumped by every save that landed. The Screen shows its tick when this
  /// changes, so a save that did not land never shows one.
  final int savedTick;
  final String? saveFailure;
  final bool submitting;
  final String? submitFailure;

  /// The Attempt is `submitted` — either by this Screen's submit or by the
  /// server's own finalise after the deadline.
  final bool submitted;

  AssessmentPaperQuestion? get current =>
      index >= 0 && index < paper.questions.length ? paper.questions[index] : null;

  int get answeredCount => paper.questions.where((question) => question.isAnswered).length;
  int get unansweredCount => paper.questions.length - answeredCount;

  AssessmentSittingLoaded copyWith({
    AssessmentPaper? paper,
    int? index,
    bool? saving,
    int? savedTick,
    String? saveFailure,
    bool clearSaveFailure = false,
    bool? submitting,
    String? submitFailure,
    bool clearSubmitFailure = false,
    bool? submitted,
  }) {
    return AssessmentSittingLoaded(
      paper: paper ?? this.paper,
      index: index ?? this.index,
      saving: saving ?? this.saving,
      savedTick: savedTick ?? this.savedTick,
      saveFailure: clearSaveFailure ? null : (saveFailure ?? this.saveFailure),
      submitting: submitting ?? this.submitting,
      submitFailure: clearSubmitFailure ? null : (submitFailure ?? this.submitFailure),
      submitted: submitted ?? this.submitted,
    );
  }
}

class AssessmentSittingBloc extends Bloc<AssessmentSittingEvent, AssessmentSittingState> {
  AssessmentSittingBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentSittingLoading()) {
    on<AssessmentSittingStarted>(_onStarted);
    on<AssessmentSittingOptionChosen>(_onOptionChosen);
    on<AssessmentSittingOtherChanged>(_onOtherChanged);
    on<AssessmentSittingMoved>(_onMoved);
    on<AssessmentSittingExpired>(_onExpired);
    on<AssessmentSittingSubmitted>(_onSubmitted);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  String? _attemptId;

  Future<void> _onStarted(
    AssessmentSittingStarted event,
    Emitter<AssessmentSittingState> emit,
  ) async {
    _attemptId = event.attemptId;
    emit(const AssessmentSittingLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentSittingUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final paper = await _api.startAssessmentAttempt(token, event.attemptId);
      emit(AssessmentSittingLoaded(paper: paper, submitted: !paper.attempt.isRunning));
    } on PeopleApiException catch (error) {
      emit(AssessmentSittingUnavailable(message: error.message));
    }
  }

  Future<void> _onOptionChosen(
    AssessmentSittingOptionChosen event,
    Emitter<AssessmentSittingState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentSittingLoaded || !current.paper.isRunning) return;
    // The tap is shown at once; the server's answer replaces it when it lands.
    emit(current.copyWith(
      paper: _answered(current.paper, event.position, chosenOption: event.option, otherText: null),
      saving: true,
      clearSaveFailure: true,
    ));
    await _save(emit, (token) => _api.saveAssessmentAnswer(
          token,
          current.paper.attempt.id,
          event.position,
          chosenOption: event.option,
        ));
  }

  Future<void> _onOtherChanged(
    AssessmentSittingOtherChanged event,
    Emitter<AssessmentSittingState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentSittingLoaded || !current.paper.isRunning) return;
    final text = event.text.trim();
    emit(current.copyWith(
      paper: _answered(
        current.paper,
        event.position,
        chosenOption: null,
        otherText: text.isEmpty ? null : text,
      ),
      saving: true,
      clearSaveFailure: true,
    ));
    await _save(emit, (token) => _api.saveAssessmentAnswer(
          token,
          current.paper.attempt.id,
          event.position,
          otherText: text.isEmpty ? '' : text,
        ));
  }

  Future<void> _save(
    Emitter<AssessmentSittingState> emit,
    Future<AssessmentPaper> Function(String token) send,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      final now = state;
      if (now is AssessmentSittingLoaded) {
        emit(now.copyWith(saving: false, saveFailure: signedOutMessage));
      }
      return;
    }
    try {
      final paper = await send(token);
      final now = state;
      if (now is! AssessmentSittingLoaded) return;
      emit(now.copyWith(
        paper: paper,
        saving: false,
        savedTick: now.savedTick + 1,
        clearSaveFailure: true,
        submitted: !paper.attempt.isRunning,
      ));
    } on PeopleApiException catch (error) {
      final now = state;
      if (now is! AssessmentSittingLoaded) return;
      emit(now.copyWith(saving: false, saveFailure: error.message));
      // A refusal past the deadline is the server's finalise: read the paper so
      // the Screen shows the closed Attempt rather than an editable one.
      if (error.statusCode == 409) {
        add(const AssessmentSittingExpired());
      }
    }
  }

  void _onMoved(
    AssessmentSittingMoved event,
    Emitter<AssessmentSittingState> emit,
  ) {
    final current = state;
    if (current is! AssessmentSittingLoaded) return;
    final index = event.index.clamp(0, current.paper.questions.length - 1);
    emit(current.copyWith(index: index));
  }

  Future<void> _onExpired(
    AssessmentSittingExpired event,
    Emitter<AssessmentSittingState> emit,
  ) async {
    final current = state;
    final id = _attemptId ?? (current is AssessmentSittingLoaded ? current.paper.attempt.id : null);
    if (id == null) return;
    final token = _auth.currentAccessToken;
    if (token == null) return;
    try {
      final paper = await _api.fetchAssessmentPaper(token, id);
      final now = state;
      if (now is! AssessmentSittingLoaded) return;
      emit(now.copyWith(
        paper: paper,
        saving: false,
        submitted: !paper.attempt.isRunning,
        saveFailure: paper.isRunning ? now.saveFailure : null,
      ));
    } on PeopleApiException catch (error) {
      final now = state;
      if (now is! AssessmentSittingLoaded) return;
      emit(now.copyWith(saving: false, saveFailure: error.message));
    }
  }

  Future<void> _onSubmitted(
    AssessmentSittingSubmitted event,
    Emitter<AssessmentSittingState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentSittingLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(submitFailure: signedOutMessage));
      return;
    }
    emit(current.copyWith(submitting: true, clearSubmitFailure: true));
    try {
      final paper = await _api.submitAssessmentAttempt(token, current.paper.attempt.id);
      emit(current.copyWith(
        paper: paper,
        submitting: false,
        submitted: true,
        savedTick: current.savedTick + 1,
      ));
    } on PeopleApiException catch (error) {
      emit(current.copyWith(submitting: false, submitFailure: error.message));
      if (error.statusCode == 409) add(const AssessmentSittingExpired());
    }
  }

  /// The paper with one Question's Answer replaced, locally, so the tap is not
  /// waiting on a round trip.
  AssessmentPaper _answered(
    AssessmentPaper paper,
    int position, {
    required String? chosenOption,
    required String? otherText,
  }) {
    return AssessmentPaper(
      attempt: paper.attempt,
      serverNow: paper.serverNow,
      questions: [
        for (final question in paper.questions)
          if (question.position == position)
            AssessmentPaperQuestion(
              position: question.position,
              questionText: question.questionText,
              optionA: question.optionA,
              optionB: question.optionB,
              optionC: question.optionC,
              chosenOption: chosenOption,
              otherText: otherText,
            )
          else
            question,
      ],
    );
  }
}
