/// One Safety incident's own state (issue #226): the record, read by its id.
///
/// Route-scoped and keyed on the id in the address, the same shape
/// `NonconformanceDetailBloc` and `ActionDetailBloc` keep: go_router reuses a
/// page when the route *pattern* matches, so a second incident's address
/// would otherwise paint the first one's record (issue #183's own bug), and
/// the router keys the provider on the id for it.
///
/// A read-only Bloc in this slice: classifying an injury, changing the
/// severity, recording days and closing are all issue #228's and #224's own
/// writes, gated on Safety authority, and arrive as this Bloc's own later
/// events when those tickets land.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'safety_api.dart';
import 'safety_incident.dart';

sealed class SafetyIncidentDetailEvent {
  const SafetyIncidentDetailEvent();
}

class SafetyIncidentDetailStarted extends SafetyIncidentDetailEvent {
  const SafetyIncidentDetailStarted(this.id);

  final String id;
}

class SafetyIncidentDetailRefreshed extends SafetyIncidentDetailEvent {
  const SafetyIncidentDetailRefreshed();
}

sealed class SafetyIncidentDetailState {
  const SafetyIncidentDetailState();
}

class SafetyIncidentDetailLoading extends SafetyIncidentDetailState {
  const SafetyIncidentDetailLoading();
}

class SafetyIncidentDetailUnavailable extends SafetyIncidentDetailState {
  const SafetyIncidentDetailUnavailable({required this.message, this.statusCode});

  final String message;

  /// The API's own status code, when this came from a response rather than a
  /// transport failure — `404` is "no such incident", told apart from an
  /// ordinary failure the same way `NonconformanceDetailMissing` is its own
  /// state rather than a flavour of `NonconformanceDetailUnavailable`.
  final int? statusCode;

  bool get isMissing => statusCode == 404;
}

class SafetyIncidentDetailLoaded extends SafetyIncidentDetailState {
  const SafetyIncidentDetailLoaded({required this.incident});

  final SafetyIncident incident;
}

class SafetyIncidentDetailBloc
    extends Bloc<SafetyIncidentDetailEvent, SafetyIncidentDetailState> {
  SafetyIncidentDetailBloc({
    required SafetyApi safetyApi,
    required AuthGateway authGateway,
  })  : _api = safetyApi,
        _auth = authGateway,
        super(const SafetyIncidentDetailLoading()) {
    on<SafetyIncidentDetailStarted>(_onStarted);
    on<SafetyIncidentDetailRefreshed>(_onRefreshed);
  }

  final SafetyApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  String? _id;

  Future<void> _onStarted(
    SafetyIncidentDetailStarted event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    _id = event.id;
    emit(const SafetyIncidentDetailLoading());
    await _read(emit);
  }

  Future<void> _onRefreshed(
    SafetyIncidentDetailRefreshed event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    if (_id == null) return;
    await _read(emit);
  }

  Future<void> _read(Emitter<SafetyIncidentDetailState> emit) async {
    final id = _id;
    if (id == null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyIncidentDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final incident = await _api.fetchSafetyIncident(token, id);
      emit(SafetyIncidentDetailLoaded(incident: incident));
    } on SafetyApiException catch (error) {
      emit(SafetyIncidentDetailUnavailable(message: error.message, statusCode: error.statusCode));
    }
  }
}
