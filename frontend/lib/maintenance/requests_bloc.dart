/// The requester's own view of Requests (issue #72): what this Account raised,
/// what became of each, and a way to raise another. This is the surface an
/// operator earns the Module with — before triage, the only write an operator
/// could make on the Work order screen would have been refused, and a Screen
/// full of refusals is exactly the empty invitation this Bloc's Destination
/// exists to avoid.
///
/// Route-scoped like `AssetsBloc`, not app-scoped like `AccountBloc`: one
/// Screen's reading of the server, re-read on arrival rather than restored
/// stale, so a just-raised Request (or a just-triaged one) is visible without
/// a restart.
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

/// Load the Sites, then the Requests this Account raised. Also the retry a
/// failed load offers, so a retry re-does whichever half failed.
class RequestsStarted extends RequestsEvent {
  const RequestsStarted();
}

/// Look at a different Site's Assets when raising.
class RequestsSiteSelected extends RequestsEvent {
  const RequestsSiteSelected(this.siteId);
  final String siteId;
}

/// The raise dialog has decided: this is a whole Request, with the Asset and
/// urgency already chosen. Same contract as `WorkOrderRaiseConfirmed` — the
/// dialog decides, the Bloc only ever sees a decision already made.
class RequestRaiseConfirmed extends RequestsEvent {
  const RequestRaiseConfirmed({
    required this.siteId,
    required this.assetId,
    required this.summary,
    required this.urgency,
    required this.productionStopped,
    this.description,
  });

  final String siteId;
  final String assetId;
  final String summary;
  final String urgency;
  final bool productionStopped;
  final String? description;
}

sealed class RequestsState {
  const RequestsState();
}

class RequestsLoading extends RequestsState {
  const RequestsLoading();
}

class RequestsLoaded extends RequestsState {
  const RequestsLoaded({
    required this.sites,
    required this.siteId,
    this.requests = const [],
    this.isLoadingRequests = false,
    this.isRaising = false,
    this.raiseFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<MaintenanceRequest> requests;

  /// A re-read of the list (after raising) while the rest of the Screen stays
  /// put.
  final bool isLoadingRequests;

  /// A raise is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isRaising;

  /// Why the last raise did not land. Reported by the open dialog, which
  /// stays open so the caller can fix the field rather than retype the whole
  /// form.
  final String? raiseFailure;

  /// What the last act had to say for itself.
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
    bool? isRaising,
    String? raiseFailure,
    String? notice,
  }) =>
      RequestsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        requests: requests ?? this.requests,
        isLoadingRequests: isLoadingRequests ?? this.isLoadingRequests,
        isRaising: isRaising ?? this.isRaising,
        raiseFailure: raiseFailure,
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
    on<RequestRaiseConfirmed>(_onRaiseConfirmed);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing to ask about.';

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
    emit(RequestsLoaded(sites: sites, siteId: sites.first.id, isLoadingRequests: true));
    await _readRequests(emit);
  }

  Future<void> _onSiteSelected(RequestsSiteSelected event, Emitter<RequestsState> emit) async {
    final current = state;
    if (current is! RequestsLoaded) return;
    emit(current.copyWith(siteId: event.siteId));
  }

  Future<void> _readRequests(Emitter<RequestsState> emit) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! RequestsLoaded) return;
    if (token == null) {
      emit(const RequestsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _maintenance.fetchMyRequests(token);
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(settled.copyWith(requests: requests, isLoadingRequests: false));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(RequestsUnavailable(message: error.message));
    }
  }

  Future<void> _onRaiseConfirmed(RequestRaiseConfirmed event, Emitter<RequestsState> emit) async {
    final current = state;
    if (current is! RequestsLoaded || current.isRaising) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(raiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaising: true));
    try {
      final request = await _maintenance.createRequest(
        token,
        assetId: event.assetId,
        summary: event.summary,
        urgency: event.urgency,
        productionStopped: event.productionStopped,
        description: event.description,
      );
      final settled = state;
      if (settled is! RequestsLoaded) return;
      // Prepend: the requester most recently raised something, so it leads,
      // matching the server's own `ORDER BY reported_at DESC`.
      emit(
        settled.copyWith(
          isRaising: false,
          requests: [request, ...settled.requests],
          notice: '${request.requestNo} has been raised.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! RequestsLoaded) return;
      emit(settled.copyWith(isRaising: false, raiseFailure: error.message));
    }
  }
}