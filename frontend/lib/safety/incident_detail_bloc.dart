/// One Safety incident's own state (issue #226): the record, read by its id.
///
/// Route-scoped and keyed on the id in the address, the same shape
/// `NonconformanceDetailBloc` and `ActionDetailBloc` keep: go_router reuses a
/// page when the route *pattern* matches, so a second incident's address
/// would otherwise paint the first one's record (issue #183's own bug), and
/// the router keys the provider on the id for it.
///
/// Issue #228 adds five writes: setting or changing the investigation due
/// date, moving the status ladder, correcting the severity, recording the
/// days the injury cost, and closing. Four of them (every one but the due
/// date) keep this record's event history, so the whole record — the write's
/// own answer — is what every mutation re-emits, the same discipline
/// `NonconformanceDetailBloc`'s own `_mutate` keeps.
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

/// The investigation due date was set or changed. `null` clears it.
class SafetyIncidentDueDateSet extends SafetyIncidentDetailEvent {
  const SafetyIncidentDueDateSet({this.investigationDueAt});

  final String? investigationDueAt;
}

/// The status moved one step along the ladder.
class SafetyIncidentStatusMoved extends SafetyIncidentDetailEvent {
  const SafetyIncidentStatusMoved({required this.status});

  final String status;
}

/// The severity level was corrected, with the note it was corrected on
/// (issue #228, #223 decision 5).
class SafetyIncidentSeverityChanged extends SafetyIncidentDetailEvent {
  const SafetyIncidentSeverityChanged({required this.severityLevel, required this.note});

  final String severityLevel;
  final String note;
}

/// The lost-time and restricted days were recorded.
class SafetyIncidentDaysRecorded extends SafetyIncidentDetailEvent {
  const SafetyIncidentDaysRecorded({required this.lostTimeDays, required this.restrictedDays});

  final int lostTimeDays;
  final int restrictedDays;
}

/// The incident was closed, with the note it was closed on.
class SafetyIncidentClosed extends SafetyIncidentDetailEvent {
  const SafetyIncidentClosed({required this.note});

  final String note;
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
  const SafetyIncidentDetailLoaded({
    required this.incident,
    this.isMutating = false,
    this.mutationFailure,
  });

  final SafetyIncident incident;
  final bool isMutating;

  /// Why the last change did not land. Reported by whichever dialog made it,
  /// which stays open so the caller can correct the one value — mirrors
  /// `NonconformanceDetailLoaded.mutationFailure`.
  final String? mutationFailure;

  SafetyIncidentDetailLoaded copyWith({
    SafetyIncident? incident,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      SafetyIncidentDetailLoaded(
        incident: incident ?? this.incident,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
      );
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
    on<SafetyIncidentDueDateSet>(_onDueDateSet);
    on<SafetyIncidentStatusMoved>(_onStatusMoved);
    on<SafetyIncidentSeverityChanged>(_onSeverityChanged);
    on<SafetyIncidentDaysRecorded>(_onDaysRecorded);
    on<SafetyIncidentClosed>(_onClosed);
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

  /// The investigation due date, set or changed (issue #228). The Screen only
  /// offers this while the incident is not yet closed; this guard is the same
  /// rule said again where it cannot be bypassed.
  Future<void> _onDueDateSet(
    SafetyIncidentDueDateSet event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded) return;
    if (current.incident.isClosed) return;
    await _mutate(
      emit,
      (token) => _api.setInvestigationDueDate(
        token,
        current.incident.id,
        investigationDueAt: event.investigationDueAt,
      ),
    );
  }

  /// The status moved one step along the ladder (issue #228). Only the
  /// ladder's own next step is ever sent: the Screen offers no other, and this
  /// guard is the same rule said again where it cannot be bypassed.
  Future<void> _onStatusMoved(
    SafetyIncidentStatusMoved event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded) return;
    if (current.incident.nextStatus != event.status) return;
    await _mutate(
      emit,
      (token) => _api.moveSafetyIncidentStatus(token, current.incident.id, status: event.status),
    );
  }

  /// The severity level was corrected, with a note (issue #228, #223 decision
  /// 5). Accepted even on a closed incident: a correction restates the period
  /// it occurred in.
  Future<void> _onSeverityChanged(
    SafetyIncidentSeverityChanged event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded) return;
    if (event.severityLevel == current.incident.severityLevel) return;
    if (event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.changeSafetyIncidentSeverity(
        token,
        current.incident.id,
        severityLevel: event.severityLevel,
        note: event.note,
      ),
    );
  }

  /// The lost-time and restricted days were recorded (issue #228). Not
  /// offered once the incident is closed.
  Future<void> _onDaysRecorded(
    SafetyIncidentDaysRecorded event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded) return;
    if (current.incident.isClosed) return;
    if (event.lostTimeDays < 0 || event.restrictedDays < 0) return;
    await _mutate(
      emit,
      (token) => _api.recordSafetyIncidentDays(
        token,
        current.incident.id,
        lostTimeDays: event.lostTimeDays,
        restrictedDays: event.restrictedDays,
      ),
    );
  }

  /// The incident was closed, with a note (issue #228, #223 decision 4).
  Future<void> _onClosed(
    SafetyIncidentClosed event,
    Emitter<SafetyIncidentDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded) return;
    if (current.incident.isClosed) return;
    if (event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.closeSafetyIncident(token, current.incident.id, note: event.note),
    );
  }

  Future<void> _mutate(
    Emitter<SafetyIncidentDetailState> emit,
    Future<SafetyIncident> Function(String token) change,
  ) async {
    final current = state;
    if (current is! SafetyIncidentDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final updated = await change(token);
      final settled = state;
      if (settled is! SafetyIncidentDetailLoaded) return;
      // The whole record comes back from every write, event history
      // included, so the Screen never has to patch its own copy.
      emit(settled.copyWith(incident: updated, isMutating: false));
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! SafetyIncidentDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
