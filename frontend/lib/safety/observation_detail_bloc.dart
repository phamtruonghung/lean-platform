/// One Safety observation's own state (issue #230): the record, read by its
/// id.
///
/// Route-scoped and keyed on the id in the address, the same shape
/// `SafetyIncidentDetailBloc` keeps: go_router reuses a page when the route
/// *pattern* matches, so a second observation's address would otherwise
/// paint the first one's record (issue #183's own bug), and the router keys
/// the provider on the id for it.
///
/// Unlike `SafetyIncidentDetailBloc` there is nothing to write from this
/// Screen: an observation has no status, no event history and no
/// injury-style restriction to read around (#223 decision 9) — it is a fact,
/// read once and shown. Raising an Action from one is #231, out of scope
/// here.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'safety_api.dart';
import 'safety_observation.dart';

sealed class SafetyObservationDetailEvent {
  const SafetyObservationDetailEvent();
}

class SafetyObservationDetailStarted extends SafetyObservationDetailEvent {
  const SafetyObservationDetailStarted(this.id);

  final String id;
}

class SafetyObservationDetailRefreshed extends SafetyObservationDetailEvent {
  const SafetyObservationDetailRefreshed();
}

sealed class SafetyObservationDetailState {
  const SafetyObservationDetailState();
}

class SafetyObservationDetailLoading extends SafetyObservationDetailState {
  const SafetyObservationDetailLoading();
}

class SafetyObservationDetailUnavailable extends SafetyObservationDetailState {
  const SafetyObservationDetailUnavailable({required this.message, this.isMissing = false});

  final String message;

  /// A 404 rather than a transport or server failure — the Screen offers
  /// "back to the register" instead of "try again".
  final bool isMissing;
}

class SafetyObservationDetailLoaded extends SafetyObservationDetailState {
  const SafetyObservationDetailLoaded({required this.observation});

  final SafetyObservation observation;
}

class SafetyObservationDetailBloc
    extends Bloc<SafetyObservationDetailEvent, SafetyObservationDetailState> {
  SafetyObservationDetailBloc({
    required SafetyApi safetyApi,
    required AuthGateway authGateway,
  })  : _api = safetyApi,
        _auth = authGateway,
        super(const SafetyObservationDetailLoading()) {
    on<SafetyObservationDetailStarted>(_onStarted);
    on<SafetyObservationDetailRefreshed>(_onRefreshed);
  }

  final SafetyApi _api;
  final AuthGateway _auth;
  String? _id;

  Future<void> _onStarted(
    SafetyObservationDetailStarted event,
    Emitter<SafetyObservationDetailState> emit,
  ) async {
    _id = event.id;
    await _read(emit);
  }

  Future<void> _onRefreshed(
    SafetyObservationDetailRefreshed event,
    Emitter<SafetyObservationDetailState> emit,
  ) async {
    await _read(emit);
  }

  Future<void> _read(Emitter<SafetyObservationDetailState> emit) async {
    final id = _id;
    if (id == null) return;
    emit(const SafetyObservationDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(
        const SafetyObservationDetailUnavailable(
          message: 'This session has ended. Sign in again to continue.',
        ),
      );
      return;
    }
    try {
      final observation = await _api.fetchSafetyObservation(token, id);
      emit(SafetyObservationDetailLoaded(observation: observation));
    } on SafetyApiException catch (error) {
      emit(
        SafetyObservationDetailUnavailable(
          message: error.message,
          isMissing: error.statusCode == 404,
        ),
      );
    }
  }
}
