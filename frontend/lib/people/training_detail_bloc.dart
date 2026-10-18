/// One Training record's state machine (issue #287): reads
/// `GET /api/people/training/:id`. Created per record — the router keys its
/// `BlocProvider` on the id in the address so moving from one record to
/// another re-reads rather than showing the record before. The Trainee list
/// is #288's; this Bloc reads the record alone.
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
  const TrainingDetailLoaded({required this.record});
  final TrainingRecord record;
}

class TrainingDetailBloc extends Bloc<TrainingDetailEvent, TrainingDetailState> {
  TrainingDetailBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const TrainingDetailLoading()) {
    on<TrainingDetailRequested>(_onRequested);
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
}
