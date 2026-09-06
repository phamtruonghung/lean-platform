/// The triage queue (issue #72): every open Request across a Site, and the
/// decisions maintenance makes on each — accept (which raises a Work order),
/// decline (which requires a reason), or mark a duplicate. This is the
/// commitment half of the Module: the surface a maintenance worker uses to
/// answer the floor, and the only one an operator is deliberately not offered.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'maintenance_request.dart';

sealed class TriageEvent {
  const TriageEvent();
}

class TriageStarted extends TriageEvent {
  const TriageStarted();
}

class TriageSiteSelected extends TriageEvent {
  const TriageSiteSelected(this.siteId);
  final String siteId;
}

/// A triage decision is confirmed: accept, decline (with a reason), or mark a
/// duplicate (of another Request). All are decisions already made by a dialog;
/// the Bloc only ever sees the decision and lets the server (the arbiter of
/// status and scope) refuse an illegal one.
sealed class TriageDecision extends TriageEvent {
  const TriageDecision(this.requestId);
  final String requestId;
}

class RequestAcceptConfirmed extends TriageDecision {
  const RequestAcceptConfirmed(super.requestId, {required this.workType, required this.priority});
  final String workType;
  final int priority;
}

class RequestDeclineConfirmed extends TriageDecision {
  const RequestDeclineConfirmed(super.requestId, {required this.reason});
  final String reason;
}

class RequestDuplicateConfirmed extends TriageDecision {
  const RequestDuplicateConfirmed(super.requestId, {required this.duplicateOfId});
  final String duplicateOfId;
}

sealed class TriageState {
  const TriageState();
}

class TriageLoading extends TriageState {
  const TriageLoading();
}

class TriageLoaded extends TriageState {
  const TriageLoaded({
    required this.sites,
    required this.siteId,
    this.requests = const [],
    this.isLoadingRequests = false,
    this.actingOnId,
    this.actionFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<MaintenanceRequest> requests;

  final bool isLoadingRequests;

  /// The Request whose triage decision is in flight, or null when none is —
  /// kept so the Screen can refuse a second decision on the same Request while
  /// the first is still being sent.
  final String? actingOnId;

  /// Why the last triage decision did not land.
  final String? actionFailure;

  final String? notice;

  TriageLoaded copyWith({
    List<MaintenanceRequest>? requests,
    String? siteId,
    bool? isLoadingRequests,
    String? actingOnId,
    String? actionFailure,
    String? notice,
  }) =>
      TriageLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        requests: requests ?? this.requests,
        isLoadingRequests: isLoadingRequests ?? this.isLoadingRequests,
        actingOnId: actingOnId,
        actionFailure: actionFailure,
        notice: notice,
      );
}

class TriageUnavailable extends TriageState {
  const TriageUnavailable({required this.message});
  final String message;
}

class TriageBloc extends Bloc<TriageEvent, TriageState> {
  TriageBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const TriageLoading()) {
    on<TriageStarted>(_onStarted);
    on<TriageSiteSelected>(_onSiteSelected);
    on<RequestAcceptConfirmed>(_onAccept);
    on<RequestDeclineConfirmed>(_onDecline);
    on<RequestDuplicateConfirmed>(_onDuplicate);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is no queue to work.';

  Future<void> _onStarted(TriageStarted event, Emitter<TriageState> emit) async {
    emit(const TriageLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const TriageUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(TriageUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const TriageUnavailable(message: noSitesMessage));
      return;
    }
    emit(TriageLoaded(sites: sites, siteId: sites.first.id, isLoadingRequests: true));
    await _readQueue(emit);
  }

  Future<void> _onSiteSelected(TriageSiteSelected event, Emitter<TriageState> emit) async {
    final current = state;
    if (current is! TriageLoaded) return;
    emit(current.copyWith(siteId: event.siteId, requests: const [], isLoadingRequests: true));
    await _readQueue(emit);
  }

  Future<void> _readQueue(Emitter<TriageState> emit) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! TriageLoaded || current.siteId == null) return;
    if (token == null) {
      emit(const TriageUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _maintenance.fetchTriageQueue(token, siteId: current.siteId!);
      final settled = state;
      if (settled is! TriageLoaded) return;
      emit(settled.copyWith(requests: requests, isLoadingRequests: false));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! TriageLoaded) return;
      emit(TriageUnavailable(message: error.message));
    }
  }

  void _onAccept(RequestAcceptConfirmed event, Emitter<TriageState> emit) =>
      _runAction(event.requestId, emit, (token, id) => _maintenance.acceptRequest(
            token,
            id,
            workType: event.workType,
            priority: event.priority,
          ).then((r) => r.request));

  void _onDecline(RequestDeclineConfirmed event, Emitter<TriageState> emit) =>
      _runAction(event.requestId, emit,
          (token, id) => _maintenance.declineRequest(token, id, reason: event.reason));

  void _onDuplicate(RequestDuplicateConfirmed event, Emitter<TriageState> emit) => _runAction(
      event.requestId,
      emit,
      (token, id) =>
          _maintenance.markRequestDuplicate(token, id, duplicateOfId: event.duplicateOfId));

  /// The one shape all three triage decisions share: refuse a second decision
  /// while one is in flight, send one request, and drop the decided Request
  /// from the queue (an accepted/rejected/duplicate Request is no longer
  /// open).
  Future<void> _runAction(
    String requestId,
    Emitter<TriageState> emit,
    Future<MaintenanceRequest> Function(String token, String requestId) request,
  ) async {
    final current = state;
    if (current is! TriageLoaded || current.actingOnId != null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(actingOnId: requestId, actionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(actingOnId: requestId));
    try {
      final updated = await request(token, requestId);
      final settled = state;
      if (settled is! TriageLoaded) return;
      emit(
        settled.copyWith(
          actingOnId: null,
          requests: [for (final r in settled.requests) if (r.id != updated.id) r],
          notice: _noticeFor(updated),
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! TriageLoaded) return;
      emit(settled.copyWith(actingOnId: null, actionFailure: error.message));
    }
  }

  static String _noticeFor(MaintenanceRequest updated) => switch (updated.status) {
        'accepted' => '${updated.requestNo} accepted — ${updated.workOrder?.workOrderNo ?? 'a Work order'} raised.',
        'rejected' => '${updated.requestNo} declined.',
        'duplicate' => '${updated.requestNo} marked a duplicate of ${updated.duplicateOfNo ?? 'another Request'}.',
        _ => '${updated.requestNo} ${updated.status}.',
      };
}