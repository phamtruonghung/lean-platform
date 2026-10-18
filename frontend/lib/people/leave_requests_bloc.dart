/// The leave request list's state machine (issue #265): the caller's own
/// requests ("Mine") or the pending ones they may decide ("To decide"), the
/// leave types the request form chooses from, and the four writes — asking,
/// approving, rejecting and cancelling.
///
/// Route-scoped and shared by the Screen and its dialogs (ADR-0021): one
/// `ShellRoute` creates it once, so `/leave-requests/new` and the decision
/// dialogs read the same list the Screen shows and a successful write
/// refreshes it in place.
///
/// The leave types are read with `?requestable=true` and are the only
/// source of the form's leave type choice (ADR-0023). A failed read is kept
/// as [LeaveRequestsLoaded.leaveTypesFailure] so the form can show
/// `FailureState` and block submission; the list itself still works.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'attendance.dart';
import 'leave_request.dart';

sealed class LeaveRequestsEvent {
  const LeaveRequestsEvent();
}

/// The initial read, in [view]. Also what a failed read's retry dispatches.
class LeaveRequestsStarted extends LeaveRequestsEvent {
  const LeaveRequestsStarted({this.view = LeaveRequestView.mine});

  final LeaveRequestView view;
}

/// Re-read the list in the view on screen, painting the stale rows meanwhile.
class LeaveRequestsRefreshed extends LeaveRequestsEvent {
  const LeaveRequestsRefreshed();
}

class LeaveRequestsViewSelected extends LeaveRequestsEvent {
  const LeaveRequestsViewSelected(this.view);

  final LeaveRequestView view;
}

/// Re-read the leave types (the form's retry after a failed read).
class LeaveTypesRequested extends LeaveRequestsEvent {
  const LeaveTypesRequested();
}

/// The request form has decided.
class LeaveRequestSubmitted extends LeaveRequestsEvent {
  const LeaveRequestSubmitted({
    required this.absenceReasonId,
    required this.startsOn,
    required this.endsOn,
    this.note,
  });

  final String absenceReasonId;
  final String startsOn;
  final String endsOn;
  final String? note;
}

/// A decision dialog has decided: approve or reject [id], with an optional note.
class LeaveRequestDecided extends LeaveRequestsEvent {
  const LeaveRequestDecided({required this.id, required this.approve, this.note});

  final String id;
  final bool approve;
  final String? note;
}

class LeaveRequestCancelled extends LeaveRequestsEvent {
  const LeaveRequestCancelled(this.id);

  final String id;
}

sealed class LeaveRequestsState {
  const LeaveRequestsState();
}

class LeaveRequestsLoading extends LeaveRequestsState {
  const LeaveRequestsLoading();
}

class LeaveRequestsUnavailable extends LeaveRequestsState {
  const LeaveRequestsUnavailable({required this.message});

  final String message;
}

class LeaveRequestsLoaded extends LeaveRequestsState {
  const LeaveRequestsLoaded({
    required this.view,
    required this.requests,
    this.leaveTypes = const [],
    this.leaveTypesFailure,
    this.isMutating = false,
    this.mutationFailure,
  });

  final LeaveRequestView view;
  final List<LeaveRequest> requests;

  /// The requestable absence reasons, empty when [leaveTypesFailure] is set.
  final List<AbsenceReason> leaveTypes;
  final String? leaveTypesFailure;

  /// A write is in flight.
  final bool isMutating;

  /// Why the last write did not land — the server's own message. Always
  /// overwritten, never carried forward.
  final String? mutationFailure;

  LeaveRequest? requestById(String id) {
    for (final request in requests) {
      if (request.id == id) return request;
    }
    return null;
  }

  LeaveRequestsLoaded copyWith({
    LeaveRequestView? view,
    List<LeaveRequest>? requests,
    List<AbsenceReason>? leaveTypes,
    String? leaveTypesFailure,
    bool clearLeaveTypesFailure = false,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      LeaveRequestsLoaded(
        view: view ?? this.view,
        requests: requests ?? this.requests,
        leaveTypes: leaveTypes ?? this.leaveTypes,
        leaveTypesFailure: clearLeaveTypesFailure ? null : (leaveTypesFailure ?? this.leaveTypesFailure),
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
      );
}

class LeaveRequestsBloc extends Bloc<LeaveRequestsEvent, LeaveRequestsState> {
  LeaveRequestsBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const LeaveRequestsLoading()) {
    on<LeaveRequestsStarted>(_onStarted);
    on<LeaveRequestsRefreshed>(_onRefreshed);
    on<LeaveRequestsViewSelected>(_onViewSelected);
    on<LeaveTypesRequested>(_onLeaveTypesRequested);
    on<LeaveRequestSubmitted>(_onSubmitted);
    on<LeaveRequestDecided>(_onDecided);
    on<LeaveRequestCancelled>(_onCancelled);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(LeaveRequestsStarted event, Emitter<LeaveRequestsState> emit) async {
    emit(const LeaveRequestsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const LeaveRequestsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _api.fetchLeaveRequests(token, view: event.view);
      final types = await _readLeaveTypes(token);
      emit(
        LeaveRequestsLoaded(
          view: event.view,
          requests: requests,
          leaveTypes: types.$1,
          leaveTypesFailure: types.$2,
        ),
      );
    } on PeopleApiException catch (error) {
      emit(LeaveRequestsUnavailable(message: error.message));
    }
  }

  Future<(List<AbsenceReason>, String?)> _readLeaveTypes(String token) async {
    try {
      return (await _api.fetchAbsenceReasons(token, requestable: true), null);
    } on PeopleApiException catch (error) {
      return (const <AbsenceReason>[], error.message);
    }
  }

  Future<void> _onRefreshed(LeaveRequestsRefreshed event, Emitter<LeaveRequestsState> emit) async {
    final settled = state;
    if (settled is! LeaveRequestsLoaded) return;
    await _reload(settled, settled.view, emit);
  }

  Future<void> _onViewSelected(
    LeaveRequestsViewSelected event,
    Emitter<LeaveRequestsState> emit,
  ) async {
    final settled = state;
    if (settled is! LeaveRequestsLoaded) return;
    await _reload(settled, event.view, emit);
  }

  Future<void> _reload(
    LeaveRequestsLoaded settled,
    LeaveRequestView view,
    Emitter<LeaveRequestsState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const LeaveRequestsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _api.fetchLeaveRequests(token, view: view);
      emit(settled.copyWith(view: view, requests: requests, isMutating: false));
    } on PeopleApiException catch (error) {
      emit(LeaveRequestsUnavailable(message: error.message));
    }
  }

  Future<void> _onLeaveTypesRequested(
    LeaveTypesRequested event,
    Emitter<LeaveRequestsState> emit,
  ) async {
    final settled = state;
    if (settled is! LeaveRequestsLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(settled.copyWith(leaveTypesFailure: signedOutMessage));
      return;
    }
    final types = await _readLeaveTypes(token);
    emit(
      settled.copyWith(
        leaveTypes: types.$1,
        leaveTypesFailure: types.$2,
        clearLeaveTypesFailure: types.$2 == null,
      ),
    );
  }

  Future<void> _onSubmitted(LeaveRequestSubmitted event, Emitter<LeaveRequestsState> emit) =>
      _write(
        emit,
        (token) => _api.submitLeaveRequest(
          token,
          absenceReasonId: event.absenceReasonId,
          startsOn: event.startsOn,
          endsOn: event.endsOn,
          note: event.note,
        ),
      );

  Future<void> _onDecided(LeaveRequestDecided event, Emitter<LeaveRequestsState> emit) => _write(
        emit,
        (token) => event.approve
            ? _api.approveLeaveRequest(token, event.id, note: event.note)
            : _api.rejectLeaveRequest(token, event.id, note: event.note),
      );

  Future<void> _onCancelled(LeaveRequestCancelled event, Emitter<LeaveRequestsState> emit) =>
      _write(emit, (token) => _api.cancelLeaveRequest(token, event.id));

  // One write, then a re-read of the view on screen. A refusal is reported as
  // `mutationFailure` with the list untouched, so the dialog stays open with
  // what the caller typed.
  Future<void> _write(
    Emitter<LeaveRequestsState> emit,
    Future<LeaveRequest> Function(String token) send,
  ) async {
    final settled = state;
    if (settled is! LeaveRequestsLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(settled.copyWith(mutationFailure: signedOutMessage));
      return;
    }
    emit(settled.copyWith(isMutating: true));
    try {
      await send(token);
    } on PeopleApiException catch (error) {
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
      return;
    }
    try {
      final requests = await _api.fetchLeaveRequests(token, view: settled.view);
      emit(settled.copyWith(requests: requests, isMutating: false));
    } on PeopleApiException catch (error) {
      emit(LeaveRequestsUnavailable(message: error.message));
    }
  }
}
