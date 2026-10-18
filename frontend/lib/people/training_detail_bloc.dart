/// One Training record's state machine (issue #287): reads
/// `GET /api/people/training/:id`. Created per record — the router keys its
/// `BlocProvider` on the id in the address so moving from one record to
/// another re-reads rather than showing the record before. Adding and
/// removing a Trainee (issue #288) re-emit the record from the server's own
/// answer, so the list on screen is always the one the server holds; a refusal
/// leaves the record as it was and is carried on the loaded state, apart for
/// the add dialog and the Screen's own remove controls.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'training_record.dart';

sealed class TrainingDetailEvent {
  const TrainingDetailEvent();
}

/// The read, also what a failed read's retry dispatches.
class TrainingDetailRequested extends TrainingDetailEvent {
  const TrainingDetailRequested(this.id);
  final String id;
}

/// Adds one Employee as a Trainee of the record on screen.
class TrainingTraineeAdded extends TrainingDetailEvent {
  const TrainingTraineeAdded(this.employeeId);
  final String employeeId;
}

/// Takes one Trainee (the row's id, not the Employee's) off the record.
class TrainingTraineeRemoved extends TrainingDetailEvent {
  const TrainingTraineeRemoved(this.traineeId);
  final String traineeId;
}

/// Sends the draft on screen, asking every Trainee on it at once (issue #289).
class TrainingRecordSent extends TrainingDetailEvent {
  const TrainingRecordSent();
}

/// The signed-in Trainee's own answer, `confirmed` or `declined`, on the row
/// with this id (the Trainee row's, not the Employee's).
class TrainingTraineeAnswered extends TrainingDetailEvent {
  const TrainingTraineeAnswered(this.traineeId, this.answer);
  final String traineeId;
  final String answer;
}

/// The trainer's evaluation of one Trainee (the row's id): `paper`,
/// `job_training`, or null to return the Trainee to unevaluated (issue #290).
class TrainingTraineeEvaluated extends TrainingDetailEvent {
  const TrainingTraineeEvaluated(this.traineeId, this.evaluation);
  final String traineeId;
  final String? evaluation;
}

sealed class TrainingDetailState {
  const TrainingDetailState();
}

class TrainingDetailLoading extends TrainingDetailState {
  const TrainingDetailLoading();
}

class TrainingDetailUnavailable extends TrainingDetailState {
  const TrainingDetailUnavailable({required this.message, this.isMissing = false});
  final String message;

  /// The record is not there (404) — also what a draft the caller could not
  /// send answers, so the address does not reveal that it exists.
  final bool isMissing;
}

class TrainingDetailLoaded extends TrainingDetailState {
  const TrainingDetailLoaded({
    required this.record,
    this.isWriting = false,
    this.addFailure,
    this.removeFailure,
    this.sendFailure,
    this.answerFailure,
    this.evaluationFailure,
  });
  final TrainingRecord record;

  /// A Trainee write is in flight.
  final bool isWriting;

  /// The server's refusal of the last add (shown in the add dialog) or of the
  /// last remove (shown on the Screen), cleared by the next write.
  final String? addFailure;
  final String? removeFailure;

  /// The server's refusal of the last send (a record that still lacks a fact,
  /// in the server's own words) and of the last answer, shown beside the
  /// control that caused them.
  final String? sendFailure;
  final String? answerFailure;

  /// The server's refusal of the last evaluation, shown beside the list.
  final String? evaluationFailure;
}

class TrainingDetailBloc extends Bloc<TrainingDetailEvent, TrainingDetailState> {
  TrainingDetailBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const TrainingDetailLoading()) {
    on<TrainingDetailRequested>(_onRequested);
    on<TrainingTraineeAdded>(_onAdded);
    on<TrainingTraineeRemoved>(_onRemoved);
    on<TrainingRecordSent>(_onSent);
    on<TrainingTraineeAnswered>(_onAnswered);
    on<TrainingTraineeEvaluated>(_onEvaluated);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  Future<void> _onRequested(TrainingDetailRequested event, Emitter<TrainingDetailState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const TrainingDetailUnavailable(message: 'This session has ended. Sign in again to continue.'));
      return;
    }
    emit(const TrainingDetailLoading());
    try {
      emit(TrainingDetailLoaded(record: await _api.fetchTrainingRecord(token, event.id)));
    } on PeopleApiException catch (error) {
      emit(TrainingDetailUnavailable(message: error.message, isMissing: error.statusCode == 404));
    }
  }

  Future<void> _onAdded(TrainingTraineeAdded event, Emitter<TrainingDetailState> emit) =>
      _write(emit, _Write.add, (token, record) => _api.addTrainee(token, record.id, event.employeeId));

  Future<void> _onRemoved(TrainingTraineeRemoved event, Emitter<TrainingDetailState> emit) =>
      _write(emit, _Write.remove, (token, record) => _api.removeTrainee(token, record.id, event.traineeId));

  Future<void> _onSent(TrainingRecordSent event, Emitter<TrainingDetailState> emit) =>
      _write(emit, _Write.send, (token, record) => _api.sendTrainingRecord(token, record.id));

  Future<void> _onAnswered(TrainingTraineeAnswered event, Emitter<TrainingDetailState> emit) =>
      _write(emit, _Write.answer, (token, _) => _api.answerTrainee(token, event.traineeId, event.answer));

  Future<void> _onEvaluated(TrainingTraineeEvaluated event, Emitter<TrainingDetailState> emit) => _write(
      emit,
      _Write.evaluation,
      (token, record) => _api.setTraineeEvaluation(token, record.id, event.traineeId, event.evaluation));

  TrainingDetailLoaded _failed(TrainingRecord record, _Write kind, String message) => TrainingDetailLoaded(
        record: record,
        addFailure: kind == _Write.add ? message : null,
        removeFailure: kind == _Write.remove ? message : null,
        sendFailure: kind == _Write.send ? message : null,
        answerFailure: kind == _Write.answer ? message : null,
        evaluationFailure: kind == _Write.evaluation ? message : null,
      );

  Future<void> _write(
    Emitter<TrainingDetailState> emit,
    _Write kind,
    Future<TrainingRecord> Function(String token, TrainingRecord record) call,
  ) async {
    final current = state;
    if (current is! TrainingDetailLoaded || current.isWriting) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(_failed(current.record, kind, 'This session has ended. Sign in again to continue.'));
      return;
    }
    emit(TrainingDetailLoaded(record: current.record, isWriting: true));
    try {
      emit(TrainingDetailLoaded(record: await call(token, current.record)));
    } on PeopleApiException catch (error) {
      emit(_failed(current.record, kind, error.message));
    }
  }
}

enum _Write { add, remove, send, answer, evaluation }
