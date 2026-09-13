/// The requester's own Request list: which Site is being looked at, what this
/// caller raised there, and a Request being raised.
///
/// Route-scoped, like `RequestsBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose, the same reason every other Maintenance Bloc
/// does: the list is Maintenance's (`MaintenanceApi`), the Sites to choose
/// between are People's (`PeopleApi`), and ADR-0006 keeps a Module asking the
/// owning Module rather than growing its own copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'maintenance_request.dart';

sealed class MyRequestsEvent {
  const MyRequestsEvent();
}

/// Load the Sites, then the caller's own Requests at the first of them. Also
/// the retry a failed load offers.
class MyRequestsStarted extends MyRequestsEvent {
  const MyRequestsStarted();
}

/// Look at a different Site's list.
class MyRequestsSiteSelected extends MyRequestsEvent {
  const MyRequestsSiteSelected(this.siteId);
  final String siteId;
}

/// The raise dialog has decided: this is a whole Request, with the Asset
/// already chosen. Same contract every other dialog in this Module follows —
/// the dialog decides, the Bloc only ever sees a decision already made.
///
/// [siteId] is the Site the chosen Asset was fetched from, carried so the Bloc
/// can decide whether the new row belongs on this screen without a second
/// read — the same reasoning `WorkOrderRaiseConfirmed.siteId` follows.
class RequestRaiseConfirmed extends MyRequestsEvent {
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

sealed class MyRequestsState {
  const MyRequestsState();
}

/// The first load, before even the Site list is known.
class MyRequestsLoading extends MyRequestsState {
  const MyRequestsLoading();
}

class MyRequestsLoaded extends MyRequestsState {
  const MyRequestsLoaded({
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

  /// A Site switch re-reads the list while the rest of the Screen stays put.
  final bool isLoadingRequests;

  /// A raise is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isRaising;

  /// Why the last raise did not land. Reported by the open dialog, which stays
  /// open so the caller can fix the field rather than retype the whole form.
  final String? raiseFailure;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [MyRequestsUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  MyRequestsLoaded copyWith({
    List<MaintenanceRequest>? requests,
    String? siteId,
    bool? isLoadingRequests,
    bool? isRaising,
    String? raiseFailure,
    String? notice,
  }) =>
      MyRequestsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        requests: requests ?? this.requests,
        isLoadingRequests: isLoadingRequests ?? this.isLoadingRequests,
        isRaising: isRaising ?? this.isRaising,
        raiseFailure: raiseFailure,
        notice: notice,
      );
}

class MyRequestsUnavailable extends MyRequestsState {
  const MyRequestsUnavailable({required this.message});
  final String message;
}

class MyRequestsBloc extends Bloc<MyRequestsEvent, MyRequestsState> {
  MyRequestsBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const MyRequestsLoading()) {
    on<MyRequestsStarted>(_onStarted);
    on<MyRequestsSiteSelected>(_onSiteSelected);
    on<RequestRaiseConfirmed>(_onRaiseConfirmed);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing to show.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, so a retry re-opens on it rather than jumping back to the first.
  String? _lastSiteId;

  Future<void> _onStarted(MyRequestsStarted event, Emitter<MyRequestsState> emit) async {
    emit(const MyRequestsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const MyRequestsUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(MyRequestsUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const MyRequestsUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(MyRequestsLoaded(sites: sites, siteId: opensOn, isLoadingRequests: true));
    await _readList(opensOn, emit);
  }

  Future<void> _onSiteSelected(MyRequestsSiteSelected event, Emitter<MyRequestsState> emit) async {
    final current = state;
    if (current is! MyRequestsLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, requests: const [], isLoadingRequests: true));
    await _readList(event.siteId, emit);
  }

  Future<void> _readList(String siteId, Emitter<MyRequestsState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const MyRequestsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final requests = await _maintenance.fetchMyRequests(token, siteId: siteId);
      final settled = state;
      if (settled is! MyRequestsLoaded || settled.siteId != siteId) return;
      emit(settled.copyWith(requests: requests, isLoadingRequests: false, notice: notice));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! MyRequestsLoaded || settled.siteId != siteId) return;
      emit(MyRequestsUnavailable(message: error.message));
    }
  }

  Future<void> _onRaiseConfirmed(RequestRaiseConfirmed event, Emitter<MyRequestsState> emit) async {
    final current = state;
    if (current is! MyRequestsLoaded || current.isRaising) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(raiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaising: true));
    try {
      final request = await _maintenance.raiseRequest(
        token,
        assetId: event.assetId,
        summary: event.summary,
        description: event.description,
        urgency: event.urgency,
        productionStopped: event.productionStopped,
      );
      final settled = state;
      if (settled is! MyRequestsLoaded) return;
      emit(
        settled.copyWith(
          isRaising: false,
          // The response does not say which Site the new Request landed in, so
          // whether it belongs on screen is decided from the Site the Asset
          // was chosen from, carried on the event — the same reasoning
          // `WorkOrdersBloc._onRaiseConfirmed` follows.
          requests: event.siteId == settled.siteId
              ? [request, ...settled.requests]
              : settled.requests,
          notice: '${request.requestNo} has been raised.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! MyRequestsLoaded) return;
      emit(settled.copyWith(isRaising: false, raiseFailure: error.message));
    }
  }
}
