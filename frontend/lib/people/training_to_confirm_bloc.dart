/// The Training-to-confirm queue's state machine (issue #289): reads
/// `GET /api/people/training/to-confirm` — the caller's own outstanding
/// answers, oldest first — and writes a Trainee's answer
/// (`POST /api/people/training/trainees/:traineeId/answer`).
///
/// An answered row leaves the queue: the Bloc drops it on the server's 200
/// rather than re-reading, so the list on screen is the one the server just
/// agreed to. A refusal leaves every row where it was and is carried on the
/// state beside the list.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'training_record.dart';

sealed class TrainingToConfirmEvent {
  const TrainingToConfirmEvent();
}

/// The read, also what a failed read's retry dispatches.
class TrainingToConfirmStarted extends TrainingToConfirmEvent {
  const TrainingToConfirmStarted();
}

/// The caller's own answer, `confirmed` or `declined`, on one Trainee row.
class TrainingToConfirmAnswered extends TrainingToConfirmEvent {
  const TrainingToConfirmAnswered(this.traineeId, this.answer);
  final String traineeId;
  final String answer;
}

class TrainingToConfirmState {
  const TrainingToConfirmState({
    this.entries = const [],
    this.isLoading = true,
    this.isWriting = false,
    this.failure,
    this.answerFailure,
  });

  final List<TrainingToConfirm> entries;
  final bool isLoading;
  final bool isWriting;

  /// The read failed: the queue cannot be shown.
  final String? failure;

  /// The last answer was refused; the rows are as they were.
  final String? answerFailure;
}

class TrainingToConfirmBloc extends Bloc<TrainingToConfirmEvent, TrainingToConfirmState> {
  TrainingToConfirmBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const TrainingToConfirmState()) {
    on<TrainingToConfirmStarted>(_onStarted);
    on<TrainingToConfirmAnswered>(_onAnswered);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(TrainingToConfirmStarted event, Emitter<TrainingToConfirmState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const TrainingToConfirmState(isLoading: false, failure: signedOutMessage));
      return;
    }
    emit(const TrainingToConfirmState());
    try {
      emit(TrainingToConfirmState(entries: await _api.fetchTrainingToConfirm(token), isLoading: false));
    } on PeopleApiException catch (error) {
      emit(TrainingToConfirmState(isLoading: false, failure: error.message));
    }
  }

  Future<void> _onAnswered(TrainingToConfirmAnswered event, Emitter<TrainingToConfirmState> emit) async {
    final current = state;
    if (current.isWriting || current.isLoading || current.failure != null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(TrainingToConfirmState(entries: current.entries, isLoading: false, answerFailure: signedOutMessage));
      return;
    }
    emit(TrainingToConfirmState(entries: current.entries, isLoading: false, isWriting: true));
    try {
      await _api.answerTrainee(token, event.traineeId, event.answer);
      emit(TrainingToConfirmState(
        entries: [for (final entry in current.entries) if (entry.traineeId != event.traineeId) entry],
        isLoading: false,
      ));
    } on PeopleApiException catch (error) {
      emit(TrainingToConfirmState(entries: current.entries, isLoading: false, answerFailure: error.message));
    }
  }
}
