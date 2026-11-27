/// One Assessment's detail (issue #588, ADR-0068, slice 6): the facts, the four
/// sitting counts and every Attempt, with the six things a person may do about
/// them — assign more people, close it, cancel an Attempt, allow a retake, end a
/// running sitting. Marking is not here: it is a link to its own Screen.
///
/// **The server decides what may be done; this Bloc never does.** The read
/// carries `viewerMayChange` / `viewerMayMark` for the Assessment and
/// `viewerMayChange` for each Attempt, and the Screen disables an action with a
/// named reason from them. A write the server still refuses (a 409 because
/// someone closed it first) is shown as the server's own sentence and the page
/// is read again, so what is on screen is always what the server holds.
///
/// **Every write is followed by a read.** A write's own answer is not trusted to
/// describe the Assessment: the Attempts, the counts and every "latest" and
/// "counting" flag move together, so the Bloc asks again rather than patching.
///
/// Route-scoped: one Assessment's reading of the server, keyed on its id.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';
import 'assessment_create_bloc.dart' show AssessmentCreateGroupChanged;

sealed class AssessmentDetailEvent {
  const AssessmentDetailEvent();
}

/// The read, and the retry a failed read offers.
class AssessmentDetailStarted extends AssessmentDetailEvent {
  const AssessmentDetailStarted();
}

/// The assign group in the dialog as it now stands; asks the server how many
/// Employees it reaches.
class AssessmentDetailGroupChanged extends AssessmentDetailEvent {
  const AssessmentDetailGroupChanged(this.group);

  final AssessmentCreateGroupChanged group;
}

/// Adds the people the group reaches to this Assessment.
class AssessmentDetailAssigned extends AssessmentDetailEvent {
  const AssessmentDetailAssigned(this.group);

  final AssessmentCreateGroupChanged group;
}

/// Closes the Assessment: no new starts, no more people, no retakes.
class AssessmentDetailClosed extends AssessmentDetailEvent {
  const AssessmentDetailClosed();
}

/// Cancels one Attempt that has not been started, with the reason kept on it.
class AssessmentDetailAttemptCancelled extends AssessmentDetailEvent {
  const AssessmentDetailAttemptCancelled(this.attemptId, this.reason);

  final String attemptId;
  final String reason;
}

/// Allows one more sitting after a finished Attempt, with the reason kept.
class AssessmentDetailRetakeAllowed extends AssessmentDetailEvent {
  const AssessmentDetailRetakeAllowed(this.attemptId, this.reason);

  final String attemptId;
  final String reason;
}

/// Ends a running Attempt's sitting at its device.
class AssessmentDetailSittingEnded extends AssessmentDetailEvent {
  const AssessmentDetailSittingEnded(this.attemptId);

  final String attemptId;
}

sealed class AssessmentDetailState {
  const AssessmentDetailState();
}

class AssessmentDetailLoading extends AssessmentDetailState {
  const AssessmentDetailLoading();
}

class AssessmentDetailUnavailable extends AssessmentDetailState {
  const AssessmentDetailUnavailable({required this.message});

  final String message;
}

class AssessmentDetailLoaded extends AssessmentDetailState {
  const AssessmentDetailLoaded({
    required this.assessment,
    this.isWriting = false,
    this.failure,
    this.preview,
    this.previewing = false,
    this.previewFailure,
  });

  final Assessment assessment;

  /// A write is in flight; every action is disabled meanwhile.
  final bool isWriting;

  /// The server's refusal of the last write, in its own words, shown on the
  /// Screen and cleared by the next write.
  final String? failure;

  /// How many Employees the assign dialog's group reaches, as the server said.
  final AssignPreview? preview;
  final bool previewing;
  final String? previewFailure;

  AssessmentDetailLoaded copyWith({
    Assessment? assessment,
    bool? isWriting,
    String? failure,
    bool clearFailure = false,
    AssignPreview? preview,
    bool clearPreview = false,
    bool? previewing,
    String? previewFailure,
    bool clearPreviewFailure = false,
  }) {
    return AssessmentDetailLoaded(
      assessment: assessment ?? this.assessment,
      isWriting: isWriting ?? this.isWriting,
      failure: clearFailure ? null : (failure ?? this.failure),
      preview: clearPreview ? null : (preview ?? this.preview),
      previewing: previewing ?? this.previewing,
      previewFailure: clearPreviewFailure ? null : (previewFailure ?? this.previewFailure),
    );
  }
}

class AssessmentDetailBloc extends Bloc<AssessmentDetailEvent, AssessmentDetailState> {
  AssessmentDetailBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.assessmentId,
    this.mayChange = false,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentDetailLoading()) {
    on<AssessmentDetailStarted>(_onStarted);
    on<AssessmentDetailGroupChanged>(_onGroupChanged);
    on<AssessmentDetailAssigned>(_onAssigned);
    on<AssessmentDetailClosed>(_onClosed);
    on<AssessmentDetailAttemptCancelled>(_onCancelled);
    on<AssessmentDetailRetakeAllowed>(_onRetake);
    on<AssessmentDetailSittingEnded>(_onSittingEnded);
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  final String assessmentId;

  /// Whether the caller holds `PPL_ASSESSMENT_CHANGE` at all; the router
  /// decides it. The per-Assessment and per-Attempt reach is the server's.
  final bool mayChange;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  /// Bumped by every group change, so a slow preview cannot overwrite the number
  /// for a group the person has already changed.
  int _previewGeneration = 0;

  Future<void> _onStarted(
    AssessmentDetailStarted event,
    Emitter<AssessmentDetailState> emit,
  ) async {
    emit(const AssessmentDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      emit(AssessmentDetailLoaded(assessment: await _api.fetchAssessment(token, assessmentId)));
    } on PeopleApiException catch (error) {
      emit(AssessmentDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onGroupChanged(
    AssessmentDetailGroupChanged event,
    Emitter<AssessmentDetailState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentDetailLoaded) return;
    final group = event.group;
    final empty = group.isEmpty;
    final generation = ++_previewGeneration;
    emit(current.copyWith(
      clearPreview: true,
      clearPreviewFailure: true,
      previewing: !empty,
    ));
    if (empty) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(previewing: false, previewFailure: signedOutMessage));
      return;
    }
    try {
      final preview = await _api.previewAssessmentAssignment(
        token,
        orgUnitIds: [for (final unit in group.orgUnits) unit.id],
        crewIds: [for (final crew in group.crews) crew.id],
        employeeIds: [for (final employee in group.employees) employee.id],
      );
      if (generation != _previewGeneration) return;
      final now = state;
      if (now is! AssessmentDetailLoaded) return;
      emit(now.copyWith(preview: preview, previewing: false));
    } on PeopleApiException catch (error) {
      if (generation != _previewGeneration) return;
      final now = state;
      if (now is! AssessmentDetailLoaded) return;
      emit(now.copyWith(previewing: false, previewFailure: error.message));
    }
  }

  Future<void> _onAssigned(
    AssessmentDetailAssigned event,
    Emitter<AssessmentDetailState> emit,
  ) {
    return _write(emit, (token) async {
      await _api.assignAssessment(
        token,
        assessmentId,
        orgUnitIds: [for (final unit in event.group.orgUnits) unit.id],
        crewIds: [for (final crew in event.group.crews) crew.id],
        employeeIds: [for (final employee in event.group.employees) employee.id],
      );
    });
  }

  Future<void> _onClosed(
    AssessmentDetailClosed event,
    Emitter<AssessmentDetailState> emit,
  ) {
    return _write(emit, (token) async {
      await _api.closeAssessment(token, assessmentId);
    });
  }

  Future<void> _onCancelled(
    AssessmentDetailAttemptCancelled event,
    Emitter<AssessmentDetailState> emit,
  ) {
    return _write(emit, (token) => _api.cancelAssessmentAttempt(token, event.attemptId, event.reason));
  }

  Future<void> _onRetake(
    AssessmentDetailRetakeAllowed event,
    Emitter<AssessmentDetailState> emit,
  ) {
    return _write(emit, (token) => _api.retakeAssessmentAttempt(token, event.attemptId, event.reason));
  }

  Future<void> _onSittingEnded(
    AssessmentDetailSittingEnded event,
    Emitter<AssessmentDetailState> emit,
  ) {
    return _write(emit, (token) => _api.endAssessmentSitting(token, event.attemptId));
  }

  /// One write, then one read. A refusal is carried on the loaded state as the
  /// server's sentence, and the read still happens so the page is never stale.
  Future<void> _write(
    Emitter<AssessmentDetailState> emit,
    Future<void> Function(String token) send,
  ) async {
    final current = state;
    if (current is! AssessmentDetailLoaded || current.isWriting) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(failure: signedOutMessage));
      return;
    }
    emit(current.copyWith(isWriting: true, clearFailure: true));
    String? failure;
    try {
      await send(token);
    } on PeopleApiException catch (error) {
      failure = error.message;
    }
    try {
      final fresh = await _api.fetchAssessment(token, assessmentId);
      emit(AssessmentDetailLoaded(assessment: fresh, failure: failure));
    } on PeopleApiException catch (error) {
      emit(current.copyWith(isWriting: false, failure: failure ?? error.message));
    }
  }
}
