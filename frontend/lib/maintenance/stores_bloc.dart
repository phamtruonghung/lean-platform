/// The stores at a Site (issue #80): the shelves that hold parts, each
/// belonging to one Site and sitting at an Org Unit. Read-only here — a store
/// is created through the API, and this Screen is where a storekeeper finds
/// the shelf whose stock they want.
///
/// Route-scoped, like `AssetsBloc`: one Screen's reading of the server. It
/// holds People's `PeopleApi` as well as Maintenance's, for the same reason
/// `AssetsBloc` does — the list of Sites to choose between is People's, and
/// ADR-0006 says a Module asks the owning Module rather than growing its own
/// copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'store.dart';

sealed class StoresEvent {
  const StoresEvent();
}

/// Load the Sites, then the stores at the first of them. Also the retry a
/// failed load offers.
class StoresStarted extends StoresEvent {
  const StoresStarted();
}

/// Look at a different Site's stores.
class StoresSiteSelected extends StoresEvent {
  const StoresSiteSelected(this.siteId);
  final String siteId;
}

sealed class StoresState {
  const StoresState();
}

class StoresLoading extends StoresState {
  const StoresLoading();
}

class StoresLoaded extends StoresState {
  const StoresLoaded({
    required this.sites,
    required this.siteId,
    this.stores = const [],
    this.isLoadingStores = false,
  });

  final List<Site> sites;
  final String? siteId;
  final List<Store> stores;
  final bool isLoadingStores;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  StoresLoaded copyWith({
    String? siteId,
    List<Store>? stores,
    bool? isLoadingStores,
  }) =>
      StoresLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        stores: stores ?? this.stores,
        isLoadingStores: isLoadingStores ?? this.isLoadingStores,
      );
}

class StoresUnavailable extends StoresState {
  const StoresUnavailable({required this.message});
  final String message;
}

class StoresBloc extends Bloc<StoresEvent, StoresState> {
  StoresBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const StoresLoading()) {
    on<StoresStarted>(_onStarted);
    on<StoresSiteSelected>(_onSiteSelected);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage =
      'There are no Sites you can see, so there are no stores to show.';

  String? _lastSiteId;

  Future<void> _onStarted(StoresStarted event, Emitter<StoresState> emit) async {
    emit(const StoresLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const StoresUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(StoresUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const StoresUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(StoresLoaded(sites: sites, siteId: opensOn, isLoadingStores: true));
    await _readStores(opensOn, emit);
  }

  Future<void> _onSiteSelected(StoresSiteSelected event, Emitter<StoresState> emit) async {
    final current = state;
    if (current is! StoresLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, stores: const [], isLoadingStores: true));
    await _readStores(event.siteId, emit);
  }

  Future<void> _readStores(String siteId, Emitter<StoresState> emit) async {
    final token = _auth.currentAccessToken;
    if (state is! StoresLoaded) return;
    if (token == null) {
      emit(const StoresUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final stores = await _maintenance.fetchStores(token, siteId: siteId);
      if (state is! StoresLoaded || (state as StoresLoaded).siteId != siteId) return;
      emit((state as StoresLoaded).copyWith(stores: stores, isLoadingStores: false));
    } on MaintenanceApiException catch (error) {
      if (state is! StoresLoaded || (state as StoresLoaded).siteId != siteId) return;
      emit(StoresUnavailable(message: error.message));
    }
  }
}
