/// An Employee with no Account sitting an Assessment at the shared floor device
/// (issue #588, ADR-0068, slice 5): identify with an Employee number and PIN,
/// read the open Attempts this device reaches, start one, answer it one Question
/// at a time and submit.
///
/// Driven by [FloorDeviceGateway] and holding no `AccountBloc` anywhere: a device
/// is not a person, and most of a plant cannot sign in. The identification
/// exchange is the floor surface's (`MaintenanceApi.identifyTechnician`); the
/// paper's calls are People's own (`PeopleApi`).
///
/// **Two credentials, and the Bloc keeps each where it belongs.** The short-lived
/// identification (120 seconds) lists and starts, and is a private field that
/// dies with the dialog. `start` mints a sitting token that carries every later
/// request, because a paper runs longer than the identification lives; it is kept
/// in the tab's session storage ([AssessmentSittingStore]), keyed by Attempt, and
/// never on a state. A 401 on any sitting route means the sitting is over — it
/// expired, a Team Leader ended it, or a fresh identification replaced it — and
/// returns the dialog to number and PIN; identifying again and starting returns
/// the same paper at the same deadline under a new token.
///
/// **The paper is the server's, once** — see `assessment_sitting_bloc.dart`,
/// whose autosave rules this mirrors: an Option tap is one `PATCH`, the Other
/// answer one `PATCH` after the typist stops, and an emptied Other field sends a
/// blank Answer with no `otherText` at all rather than `''`. The countdown is the
/// dialog's stopwatch over `deadlineAt - serverNow`; this Bloc never reads the
/// device's clock.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../maintenance/maintenance.dart';
import '../people_api.dart';
import '../platform/assessment_sitting_store.dart';
import '../platform/floor_device_gateway.dart';
import 'assessment.dart';

sealed class FloorAssessmentEvent {
  const FloorAssessmentEvent();
}

/// The Employee has typed who they are. The PIN is used for this one exchange
/// and never stored.
class FloorAssessmentIdentified extends FloorAssessmentEvent {
  const FloorAssessmentIdentified({required this.employeeNo, required this.pin});

  final String employeeNo;
  final String pin;
}

/// Start or resume one of the listed Attempts: `POST .../start`, idempotent.
class FloorAssessmentStarted extends FloorAssessmentEvent {
  const FloorAssessmentStarted(this.attemptId);

  final String attemptId;
}

/// An Option was picked, or the Answer was cleared.
class FloorAssessmentOptionChosen extends FloorAssessmentEvent {
  const FloorAssessmentOptionChosen({required this.position, required this.option});

  final int position;

  /// `A`, `B`, `C`, or null for a blank Answer.
  final String? option;
}

/// The Other answer's text changed. The dialog debounces it.
class FloorAssessmentOtherChanged extends FloorAssessmentEvent {
  const FloorAssessmentOtherChanged({required this.position, required this.text});

  final int position;
  final String text;
}

/// The navigator moved between Questions.
class FloorAssessmentMoved extends FloorAssessmentEvent {
  const FloorAssessmentMoved(this.index);

  final int index;
}

/// The countdown reached zero: the server owns the finalise, so ask it for the
/// paper again rather than deciding here that the sitting is over.
class FloorAssessmentExpired extends FloorAssessmentEvent {
  const FloorAssessmentExpired();
}

class FloorAssessmentSubmitted extends FloorAssessmentEvent {
  const FloorAssessmentSubmitted();
}

/// Ask whether the submitted paper has been marked yet.
class FloorAssessmentResultRequested extends FloorAssessmentEvent {
  const FloorAssessmentResultRequested();
}

sealed class FloorAssessmentState {
  const FloorAssessmentState();
}

/// Number and PIN.
class FloorAssessmentIdentifying extends FloorAssessmentState {
  const FloorAssessmentIdentifying({this.isBusy = false, this.failure});

  final bool isBusy;

  /// Why the last step did not land: a Bloc notice code or a server sentence.
  final String? failure;
}

/// The identified Employee's open Attempts at this device.
class FloorAssessmentListed extends FloorAssessmentState {
  const FloorAssessmentListed({
    required this.employeeName,
    required this.attempts,
    this.isBusy = false,
    this.failure,
  });

  final String employeeName;
  final List<AssessmentAttempt> attempts;
  final bool isBusy;
  final String? failure;
}

/// One paper, running or closed.
class FloorAssessmentSitting extends FloorAssessmentState {
  const FloorAssessmentSitting({
    required this.employeeName,
    required this.paper,
    this.index = 0,
    this.saving = false,
    this.savedTick = 0,
    this.saveFailure,
    this.submitting = false,
    this.submitFailure,
    this.submitted = false,
    this.result,
    this.resultFailure,
  });

  final String employeeName;
  final AssessmentPaper paper;
  final int index;
  final bool saving;

  /// Bumped by every save that landed, so a save that did not land never shows a
  /// tick.
  final int savedTick;
  final String? saveFailure;
  final bool submitting;
  final String? submitFailure;

  /// The Attempt is closed: submitted here, or finalised by the server's clock.
  final bool submitted;

  /// The marked result, once there is one; null while the paper awaits marking.
  final AssessmentResult? result;
  final String? resultFailure;

  AssessmentPaperQuestion? get current =>
      index >= 0 && index < paper.questions.length ? paper.questions[index] : null;

  int get answeredCount => paper.questions.where((question) => question.isAnswered).length;

  /// The positions with no Answer at all, for the submit confirmation to name.
  List<int> get blankPositions =>
      [for (final question in paper.questions) if (!question.isAnswered) question.position];

  FloorAssessmentSitting copyWith({
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
    AssessmentResult? result,
    String? resultFailure,
    bool clearResultFailure = false,
  }) {
    return FloorAssessmentSitting(
      employeeName: employeeName,
      paper: paper ?? this.paper,
      index: index ?? this.index,
      saving: saving ?? this.saving,
      savedTick: savedTick ?? this.savedTick,
      saveFailure: clearSaveFailure ? null : (saveFailure ?? this.saveFailure),
      submitting: submitting ?? this.submitting,
      submitFailure: clearSubmitFailure ? null : (submitFailure ?? this.submitFailure),
      submitted: submitted ?? this.submitted,
      result: result ?? this.result,
      resultFailure: clearResultFailure ? null : (resultFailure ?? this.resultFailure),
    );
  }
}

class FloorAssessmentBloc extends Bloc<FloorAssessmentEvent, FloorAssessmentState> {
  FloorAssessmentBloc({
    required PeopleApi peopleApi,
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
    AssessmentSittingStore? sittingStore,
  })  : _people = peopleApi,
        _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        _store = sittingStore ?? createAssessmentSittingStore(),
        super(
          floorDeviceGateway.deviceCredential == null
              ? const FloorAssessmentIdentifying(failure: notRegisteredMessage)
              : const FloorAssessmentIdentifying(),
        ) {
    on<FloorAssessmentIdentified>(_onIdentified);
    on<FloorAssessmentStarted>(_onStarted);
    on<FloorAssessmentOptionChosen>(_onOptionChosen);
    on<FloorAssessmentOtherChanged>(_onOtherChanged);
    on<FloorAssessmentMoved>(_onMoved);
    on<FloorAssessmentExpired>(_onExpired);
    on<FloorAssessmentSubmitted>(_onSubmitted);
    on<FloorAssessmentResultRequested>(_onResultRequested);
  }

  final PeopleApi _people;
  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;
  final AssessmentSittingStore _store;

  /// Held for this Bloc's (the dialog's) lifetime only; never on a state.
  String? _identification;
  String? _attemptId;

  static const String notRegisteredMessage = BlocNotice.deviceNotRegistered;
  static const String expiredMessage = BlocNotice.identificationExpired;
  static const String sittingEndedMessage = BlocNotice.assessmentSittingEnded;

  /// The sitting is over as far as this dialog can tell: forget the token and the
  /// identification and go back to number and PIN.
  void _backToIdentify(Emitter<FloorAssessmentState> emit, {String message = sittingEndedMessage}) {
    final id = _attemptId;
    if (id != null) _store.clear(id);
    _identification = null;
    emit(FloorAssessmentIdentifying(failure: message));
  }

  Future<void> _onIdentified(FloorAssessmentIdentified event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    if (current is! FloorAssessmentIdentifying || current.isBusy) return;
    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(const FloorAssessmentIdentifying(failure: notRegisteredMessage));
      return;
    }
    // A fresh identification replaces any sitting this dialog held: the paper is
    // resumed through `start`, which mints the token again.
    emit(const FloorAssessmentIdentifying(isBusy: true));
    try {
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      final attempts = await _people.fetchFloorAssessments(credential, identification.token);
      _identification = identification.token;
      emit(FloorAssessmentListed(employeeName: identification.employeeName, attempts: attempts));
    } on MaintenanceApiException catch (error) {
      emit(FloorAssessmentIdentifying(failure: error.message));
    } on PeopleApiException catch (error) {
      emit(FloorAssessmentIdentifying(failure: error.message));
    }
  }

  Future<void> _onStarted(FloorAssessmentStarted event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    final credential = _device.deviceCredential;
    final identification = _identification;
    if (current is! FloorAssessmentListed || current.isBusy || credential == null || identification == null) {
      return;
    }
    emit(FloorAssessmentListed(employeeName: current.employeeName, attempts: current.attempts, isBusy: true));
    try {
      final started = await _people.startFloorAssessment(credential, identification, event.attemptId);
      _attemptId = event.attemptId;
      _store.write(event.attemptId, started.sittingToken);
      emit(FloorAssessmentSitting(
        employeeName: current.employeeName,
        paper: started.paper,
        submitted: !started.paper.isRunning,
      ));
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401) {
        _identification = null;
        emit(const FloorAssessmentIdentifying(failure: expiredMessage));
        return;
      }
      emit(FloorAssessmentListed(
        employeeName: current.employeeName,
        attempts: current.attempts,
        failure: error.message,
      ));
    }
  }

  Future<void> _onOptionChosen(FloorAssessmentOptionChosen event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    if (current is! FloorAssessmentSitting || !current.paper.isRunning || current.submitted) return;
    // The tap is shown at once; the server's answer replaces it when it lands.
    emit(current.copyWith(
      paper: _answered(current.paper, event.position, chosenOption: event.option, otherText: null),
      saving: true,
      clearSaveFailure: true,
    ));
    await _save(
      emit,
      (credential, token, id) => _people.saveFloorAssessmentAnswer(
        credential,
        token,
        id,
        event.position,
        chosenOption: event.option,
      ),
    );
  }

  Future<void> _onOtherChanged(FloorAssessmentOtherChanged event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    if (current is! FloorAssessmentSitting || !current.paper.isRunning || current.submitted) return;
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
    await _save(
      emit,
      (credential, token, id) => _people.saveFloorAssessmentAnswer(
        credential,
        token,
        id,
        event.position,
        // An emptied field is a blank Answer, and the API's blank body omits
        // `otherText` altogether: `''` is the explicit-clear spelling the server
        // tolerates, but the client never relies on it.
        otherText: text.isEmpty ? null : text,
      ),
    );
  }

  Future<void> _save(
    Emitter<FloorAssessmentState> emit,
    Future<AssessmentPaper> Function(String credential, String token, String attemptId) send,
  ) async {
    final credential = _device.deviceCredential;
    final id = _attemptId;
    final token = id == null ? null : _store.read(id);
    if (credential == null || id == null || token == null) {
      _backToIdentify(emit);
      return;
    }
    try {
      final paper = await send(credential, token, id);
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      emit(now.copyWith(
        paper: paper,
        saving: false,
        savedTick: now.savedTick + 1,
        clearSaveFailure: true,
        submitted: !paper.isRunning,
      ));
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401) {
        _backToIdentify(emit);
        return;
      }
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      emit(now.copyWith(saving: false, saveFailure: error.message));
      // A refusal past the deadline is the server's finalise: read the paper so
      // the dialog shows the closed Attempt rather than an editable one.
      if (error.statusCode == 409) add(const FloorAssessmentExpired());
    }
  }

  void _onMoved(FloorAssessmentMoved event, Emitter<FloorAssessmentState> emit) {
    final current = state;
    if (current is! FloorAssessmentSitting) return;
    final index = event.index.clamp(0, current.paper.questions.length - 1);
    emit(current.copyWith(index: index));
  }

  Future<void> _onExpired(FloorAssessmentExpired event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    final credential = _device.deviceCredential;
    final id = _attemptId;
    if (current is! FloorAssessmentSitting || credential == null || id == null) return;
    final token = _store.read(id);
    if (token == null) {
      _backToIdentify(emit);
      return;
    }
    try {
      final paper = await _people.fetchFloorAssessmentPaper(credential, token, id);
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      emit(now.copyWith(
        paper: paper,
        saving: false,
        submitted: !paper.isRunning,
        saveFailure: paper.isRunning ? now.saveFailure : null,
      ));
      if (!paper.isRunning) add(const FloorAssessmentResultRequested());
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401) {
        _backToIdentify(emit);
        return;
      }
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      emit(now.copyWith(saving: false, saveFailure: error.message));
    }
  }

  Future<void> _onSubmitted(FloorAssessmentSubmitted event, Emitter<FloorAssessmentState> emit) async {
    final current = state;
    final credential = _device.deviceCredential;
    final id = _attemptId;
    if (current is! FloorAssessmentSitting || current.submitting || credential == null || id == null) return;
    final token = _store.read(id);
    if (token == null) {
      _backToIdentify(emit);
      return;
    }
    emit(current.copyWith(submitting: true, clearSubmitFailure: true));
    try {
      final paper = await _people.submitFloorAssessment(credential, token, id);
      emit(current.copyWith(
        paper: paper,
        submitting: false,
        submitted: true,
        savedTick: current.savedTick + 1,
      ));
      add(const FloorAssessmentResultRequested());
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401) {
        _backToIdentify(emit);
        return;
      }
      emit(current.copyWith(submitting: false, submitFailure: error.message));
      if (error.statusCode == 409) add(const FloorAssessmentExpired());
    }
  }

  Future<void> _onResultRequested(
    FloorAssessmentResultRequested event,
    Emitter<FloorAssessmentState> emit,
  ) async {
    final current = state;
    final credential = _device.deviceCredential;
    final id = _attemptId;
    if (current is! FloorAssessmentSitting || !current.submitted || credential == null || id == null) return;
    final token = _store.read(id);
    // After the paper is closed a missing or lapsed token is not a failure to
    // report: the result is simply not readable from here, and "awaiting
    // marking" stands until the Employee identifies again.
    if (token == null) return;
    try {
      final result = await _people.fetchFloorAssessmentResult(credential, token, id);
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      emit(now.copyWith(result: result, clearResultFailure: true));
    } on PeopleApiException catch (error) {
      final now = state;
      if (now is! FloorAssessmentSitting) return;
      if (error.statusCode == 409 || error.statusCode == 401) {
        emit(now.copyWith(clearResultFailure: true));
        return;
      }
      emit(now.copyWith(resultFailure: error.message));
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
