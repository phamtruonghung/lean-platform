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
  });
  final TrainingRecord record;

  /// A Trainee write is in flight.
  final bool isWriting;

  /// The server's refusal of the last add (shown in the add dialog) or of the
  /// last remove (shown on the Screen), cleared by the next write.
  final String? addFailure;
  final String? removeFailure;
}

class TrainingDetailBloc extends Bloc<TrainingDetailEvent, TrainingDetailState> {
  TrainingDetailBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const TrainingDetailLoading()) {
    on<TrainingDetailRequested>(_onRequested);
    on<TrainingTraineeAdded>(_onAdded);
    on<TrainingTraineeRemoved>(_onRemoved);
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
      _write(emit, isAdd: true, call: (token, record) => _api.addTrainee(token, record.id, event.employeeId));

  Future<void> _onRemoved(TrainingTraineeRemoved event, Emitter<TrainingDetailState> emit) =>
      _write(emit, isAdd: false, call: (token, record) => _api.removeTrainee(token, record.id, event.traineeId));

  Future<void> _write(
    Emitter<TrainingDetailState> emit, {
    required bool isAdd,
    required Future<TrainingRecord> Function(String token, TrainingRecord record) call,
  }) async {
    final current = state;
    if (current is! TrainingDetailLoaded || current.isWriting) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      const message = 'This session has ended. Sign in again to continue.';
      emit(TrainingDetailLoaded(
        record: current.record,
        addFailure: isAdd ? message : null,
        removeFailure: isAdd ? null : message,
      ));
      return;
    }
    emit(TrainingDetailLoaded(record: current.record, isWriting: true));
    try {
      emit(TrainingDetailLoaded(record: await call(token, current.record)));
    } on PeopleApiException catch (error) {
      emit(TrainingDetailLoaded(
        record: current.record,
        addFailure: isAdd ? error.message : null,
        removeFailure: isAdd ? null : error.message,
      ));
    }
  }
}
