/// The marking queue (issue #588, ADR-0068, slice 4): the `submitted` Attempts
/// inside the caller's write reach, oldest first.
///
/// **What a row is for.** A paper waits here after the candidate submits it and
/// before anyone has awarded a point. The server decides which Attempts are in
/// reach — this Bloc asks `GET /assessment-marking` with the caller's own token
/// and renders what comes back, so a Team Leader sees the papers of their own
/// Org Units and nothing else. The count of "Khác" answers is on the row because
/// that is the work: an Other answer scored 0 by the machine is waiting for a
/// person to award or refuse the point (spec section 10).
///
/// Route-scoped: one Screen's own reading of the server, re-read on arrival and
/// on Refresh.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

sealed class AssessmentMarkingQueueEvent {
  const AssessmentMarkingQueueEvent();
}

/// Load the queue. Also the retry a failed load offers.
class AssessmentMarkingQueueStarted extends AssessmentMarkingQueueEvent {
  const AssessmentMarkingQueueStarted();
}

/// Re-read the server without leaving the Screen.
class AssessmentMarkingQueueRefreshed extends AssessmentMarkingQueueEvent {
  const AssessmentMarkingQueueRefreshed();
}

sealed class AssessmentMarkingQueueState {
  const AssessmentMarkingQueueState();
}

class AssessmentMarkingQueueLoading extends AssessmentMarkingQueueState {
  const AssessmentMarkingQueueLoading();
}

class AssessmentMarkingQueueUnavailable extends AssessmentMarkingQueueState {
  const AssessmentMarkingQueueUnavailable({required this.message});

  final String message;
}

class AssessmentMarkingQueueLoaded extends AssessmentMarkingQueueState {
  const AssessmentMarkingQueueLoaded({
    required this.queue,
    this.isRefreshing = false,
  });

  final AssessmentMarkingQueue queue;
  final bool isRefreshing;

  List<AssessmentMarkingEntry> get entries => queue.entries;
}

class AssessmentMarkingQueueBloc
    extends Bloc<AssessmentMarkingQueueEvent, AssessmentMarkingQueueState> {
  AssessmentMarkingQueueBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentMarkingQueueLoading()) {
    on<AssessmentMarkingQueueStarted>(_onStarted);
    on<AssessmentMarkingQueueRefreshed>(_onRefreshed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  Future<void> _onStarted(
    AssessmentMarkingQueueStarted event,
    Emitter<AssessmentMarkingQueueState> emit,
  ) async {
    emit(const AssessmentMarkingQueueLoading());
    await _read(emit);
  }

  Future<void> _onRefreshed(
    AssessmentMarkingQueueRefreshed event,
    Emitter<AssessmentMarkingQueueState> emit,
  ) async {
    final current = state;
    if (current is AssessmentMarkingQueueLoaded) {
      emit(AssessmentMarkingQueueLoaded(queue: current.queue, isRefreshing: true));
    }
    await _read(emit);
  }

  Future<void> _read(Emitter<AssessmentMarkingQueueState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentMarkingQueueUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final queue = await _api.fetchAssessmentMarkingQueue(token);
      emit(AssessmentMarkingQueueLoaded(queue: queue));
    } on PeopleApiException catch (error) {
      emit(AssessmentMarkingQueueUnavailable(message: error.message));
    }
  }
}
