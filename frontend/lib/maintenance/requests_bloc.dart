/// The triage queue's state: which Site is being looked at, and what Requests
/// are still waiting for a decision there.
///
/// Route-scoped, like `WorkOrdersBloc` and unlike `AccountBloc`: one Screen's
/// reading of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose, the same reason `WorkOrdersBloc` does: the
/// queue itself is Maintenance's (`MaintenanceApi`), the Sites to choose
/// between are People's (`PeopleApi`), and there is no Maintenance endpoint
/// that answers that — ADR-0006 keeps a Module asking the owning Module
/// rather than growing its own copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'maintenance_request.dart';

sealed class RequestsEvent {
  const RequestsEvent();
}

/// Load the Sites, then the triage queue at the first of them. Also the retry
/// a failed load offers, so a retry re-does whichever half failed.
class RequestsStarted extends RequestsEvent {
  const RequestsStarted();
}

/// Look at a different Site's queue.
class RequestsSiteSelected extends RequestsEvent {
  const RequestsSiteSelected(this.siteId);
  final String siteId;
}

/// The queue has decided: accept this Request, raising a Work order for it.
class RequestAcceptConfirmed extends RequestsEvent {
  const RequestAcceptConfirmed(this.requestId);
  final String requestId;
}

/// The decline dialog has decided: this Request is declined, and [reason] says
/// why. Required — the database refuses a rejection without one.
class RequestDeclineConfirmed extends RequestsEvent {
  const RequestDeclineConfirmed({required this.requestId, required this.reason});
  final String requestId;
  final String reason;
}

/// The duplicate dialog has decided: this Request is a duplicate of
/// [duplicateOfId], the Request that survives.
class RequestDuplicateConfirmed extends RequestsEvent {
  const RequestDuplicateConfirmed({required this.requestId, required this.duplicateOfId});
  final String requestId;
  final String duplicateOfId;
}

sealed class RequestsState {
  const RequestsState();
}

/// The first load, before even the Site list is known.
class RequestsLoading extends RequestsState {
  const RequestsLoading();
}

class RequestsLoaded extends RequestsState {
  const RequestsLoaded({
    required this.sites,
    required this.siteId,
    this.requests = const [],
    this.isLoadingRequests = false,
    this.isTriaging = false,
    this.triageFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<MaintenanceRequest> requests;

  /// A Site switch re-reads the queue while the rest of the Screen stays put —
  /// the placeholders belong to the list, not the whole Screen.
  final bool isLoadingRequests;

  /// An accept, decline or duplicate is in flight — one flag for all three,
  /// mirroring `WorkOrdersLoaded.isTransitioning`: the Screen only needs "a
  /// triage action is in flight" to disable every row's actions while it
  /// settles, not which of the three it was.
  final bool isTriaging;

  /// Why the last triage action did not land. Read by whichever dialog is open
  /// (decline, duplicate) so it can stay open and let the caller fix the field
  /// — the same reasoning `WorkOrdersLoaded.transitionFailure` follows.
  /// Accepting has no dialog to read it, so an accept failure surfaces as
  /// [notice] instead.
  final String? triageFailure;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [RequestsUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  RequestsLoaded copyWith({
    List<MaintenanceRequest>? requests,
    String? siteId,
    bool? isLoadingRequests,
    bool? isTriaging,
    String? triageFailure,
    String? notice,
  }) =>
      RequestsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        requests: requests ?? this.requests,
        isLoadingRequests: isLoadingRequests ?? this.isLoadingRequests,
        isTriaging: isTriaging ?? this.isTriaging,
        // Cleared on every emit that does not set it, exactly as raiseFailure
        // is in `WorkOrdersBloc` — a failure banner from a previous action
        // never lingers on a later, unrelated state change.
        triageFailure: triageFailure,
        notice: notice,
      );
}

class RequestsUnavailable extends RequestsState {
  const RequestsUnavailable({required this.message});
  final String message;
}

class RequestsBloc extends Bloc<RequestsEvent, RequestsState> {
  RequestsBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const RequestsLoading()) {
    on<RequestsStarted>(_onStarted);
    on<RequestsSiteSelected>(_onSiteSelected);
    on<RequestAcceptConfirmed>(_onAcceptConfirmed);
    on<RequestDeclineConfirmed>(_onDeclineConfirmed);
    on<RequestDuplicateConfirmed>(_onDuplicateConfirmed);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing waiting.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, so a retry re-opens on it rather than jumping back to the first.
  String? _lastSiteId;

  Future<void> _onStarted(RequestsStarted event, Emitter<RequestsState> emit) async {
    emit(const RequestsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const RequestsUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(RequestsUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const RequestsUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(RequestsLoaded(sites: sites, siteId: opensOn, isLoadingRequests: true));
    await _readQueue(opensOn, emit);
  }

  Future<void> _onSiteSelected(RequestsSiteSelected event, Emitter<RequestsState> emit) async {
    final current = state;
    if (current is! RequestsLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, requests: const [], isLoadingRequests: true));
    await _readQueue(event.siteId, emit);
  }

  Future<void> _readQueue(String siteId, Emitter<RequestsState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const RequestsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _maintenance.fetchTriageRequests(token, siteId: siteId);
      final settled = state;
      // A late response for a Site the caller has since left is discarded —
      // the same staleness guard `WorkOrdersBloc._readList` follows.
      if (settled is! RequestsLoaded || settled.siteId != siteId) return;
      emit(settled.copyWith(requests: requests, isLoadingRequests: false, notice: notice));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded || settled.siteId != siteId) return;
      emit(RequestsUnavailable(message: error.message));
    }
  }

  Future<void> _onAcceptConfirmed(
    RequestAcceptConfirmed event,
    Emitter<RequestsState> emit,
  ) async {
    final current = state;
    if (current is! RequestsLoaded || current.isTriaging) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTriaging: true));
    try {
      final request = await _maintenance.acceptRequest(token, event.requestId);
      final settled = state;
      if (settled is! RequestsLoaded) return;
      // The row leaves the queue either way — it has been triaged, and the
      // queue holds only what still awaits a decision.
      emit(
        settled.copyWith(
          isTriaging: false,
          requests: _withoutRequest(settled, request.id),
          notice: request.workOrder == null
              ? '${request.requestNo} has been accepted.'
              : '${request.requestNo} has been accepted, and raised ${request.workOrder!.workOrderNo}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded) return;
      // Accepting has no dialog of its own to read a failure off, unlike
      // decline/duplicate — the row itself is the caller, so the refusal
      // surfaces as the ordinary notice instead of `triageFailure`.
      emit(settled.copyWith(isTriaging: false, notice: error.message));
    }
  }

  Future<void> _onDeclineConfirmed(
    RequestDeclineConfirmed event,
    Emitter<RequestsState> emit,
  ) async {
    final current = state;
    if (current is! RequestsLoaded || current.isTriaging) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(triageFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTriaging: true));
    try {
      final request = await _maintenance.declineRequest(
        token,
        event.requestId,
        reason: event.reason,
      );
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(
        settled.copyWith(
          isTriaging: false,
          requests: _withoutRequest(settled, request.id),
          notice: '${request.requestNo} has been declined.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(settled.copyWith(isTriaging: false, triageFailure: error.message));
    }
  }

  Future<void> _onDuplicateConfirmed(
    RequestDuplicateConfirmed event,
    Emitter<RequestsState> emit,
  ) async {
    final current = state;
    if (current is! RequestsLoaded || current.isTriaging) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(triageFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTriaging: true));
    try {
      final request = await _maintenance.markRequestDuplicate(
        token,
        event.requestId,
        duplicateOfId: event.duplicateOfId,
      );
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(
        settled.copyWith(
          isTriaging: false,
          requests: _withoutRequest(settled, request.id),
          notice: '${request.requestNo} has been marked a duplicate.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(settled.copyWith(isTriaging: false, triageFailure: error.message));
    }
  }

  /// The queue with one triaged Request taken out, rather than re-read — the
  /// row has left the queue whichever of the three actions took it there.
  static List<MaintenanceRequest> _withoutRequest(RequestsLoaded state, String id) => [
        for (final request in state.requests)
          if (request.id != id) request,
      ];
}
