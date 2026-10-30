/// The KPI catalogue at one Site (ADR-0055): every KPI, its Targets in force
/// and today's review state.
///
/// The Site chooser has the shape of `SkillCoverageBloc`'s: open on the first
/// Site, re-read on switch. "Today" is the server's — the read carries no
/// `date`, so `review_date` is the Site's own today and nothing here computes a
/// date.
///
/// Adding a KPI posts and then reads the catalogue again: `kpi_id` is the
/// server's, so a local row is never spliced in.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart' show Site;
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'kpi_api.dart';
import 'kpi_catalogue.dart';

sealed class KpiCatalogueEvent {
  const KpiCatalogueEvent();
}

/// Load the Sites, then the catalogue at the first of them. Also the retry a
/// failed load offers.
class KpiCatalogueStarted extends KpiCatalogueEvent {
  const KpiCatalogueStarted();
}

class KpiCatalogueSiteSelected extends KpiCatalogueEvent {
  const KpiCatalogueSiteSelected(this.siteId);
  final String siteId;
}

class KpiAdded extends KpiCatalogueEvent {
  const KpiAdded(this.details);
  final NewKpi details;
}

sealed class KpiCatalogueState {
  const KpiCatalogueState();
}

class KpiCatalogueLoading extends KpiCatalogueState {
  const KpiCatalogueLoading();
}

class KpiCatalogueUnavailable extends KpiCatalogueState {
  const KpiCatalogueUnavailable({required this.message});
  final String message;
}

class KpiCatalogueLoaded extends KpiCatalogueState {
  const KpiCatalogueLoaded({
    required this.sites,
    required this.siteId,
    this.catalogue,
    this.isLoadingCatalogue = false,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<Site> sites;
  final String siteId;

  /// Null while a Site switch is still reading.
  final KpiCatalogue? catalogue;
  final bool isLoadingCatalogue;
  final bool isMutating;

  /// Why the last Add KPI did not land, reported by the dialog that made it,
  /// which stays open.
  final String? mutationFailure;

  KpiCatalogueLoaded copyWith({
    String? siteId,
    KpiCatalogue? catalogue,
    bool clearCatalogue = false,
    bool? isLoadingCatalogue,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      KpiCatalogueLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        catalogue: clearCatalogue ? null : (catalogue ?? this.catalogue),
        isLoadingCatalogue: isLoadingCatalogue ?? this.isLoadingCatalogue,
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
      );
}

class KpiCatalogueBloc extends Bloc<KpiCatalogueEvent, KpiCatalogueState> {
  KpiCatalogueBloc({required PeopleApi peopleApi, required KpiApi kpiApi, required AuthGateway authGateway})
      : _people = peopleApi,
        _api = kpiApi,
        _auth = authGateway,
        super(const KpiCatalogueLoading()) {
    on<KpiCatalogueStarted>(_onStarted);
    on<KpiCatalogueSiteSelected>(_onSiteSelected);
    on<KpiAdded>(_onKpiAdded);
  }

  final PeopleApi _people;
  final KpiApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is no KPI catalogue to show.';

  String? _lastSiteId;

  Future<void> _onStarted(KpiCatalogueStarted event, Emitter<KpiCatalogueState> emit) async {
    emit(const KpiCatalogueLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const KpiCatalogueUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(KpiCatalogueUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const KpiCatalogueUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(KpiCatalogueLoaded(sites: sites, siteId: opensOn, isLoadingCatalogue: true));
    await _readCatalogue(opensOn, emit);
  }

  Future<void> _onSiteSelected(KpiCatalogueSiteSelected event, Emitter<KpiCatalogueState> emit) async {
    final current = state;
    if (current is! KpiCatalogueLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, clearCatalogue: true, isLoadingCatalogue: true));
    await _readCatalogue(event.siteId, emit);
  }

  Future<void> _readCatalogue(String siteId, Emitter<KpiCatalogueState> emit) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! KpiCatalogueLoaded) return;
    if (token == null) {
      emit(const KpiCatalogueUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final catalogue = await _api.fetchCatalogue(token, siteId: siteId);
      final now = state;
      if (now is! KpiCatalogueLoaded || now.siteId != siteId) return;
      emit(now.copyWith(catalogue: catalogue, isLoadingCatalogue: false));
    } on KpiApiException catch (error) {
      final now = state;
      if (now is! KpiCatalogueLoaded || now.siteId != siteId) return;
      emit(KpiCatalogueUnavailable(message: error.message));
    }
  }

  Future<void> _onKpiAdded(KpiAdded event, Emitter<KpiCatalogueState> emit) async {
    final current = state;
    if (current is! KpiCatalogueLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true));
    try {
      final details = event.details;
      await _api.addKpi(
        token,
        siteId: current.siteId,
        kpi: details.kpi,
        title: details.title,
        unit: details.unit,
        direction: details.direction,
        decimals: details.decimals,
        valueMeasure: details.valueMeasure,
      );
      // Read again rather than splice a local row: `kpi_id` is the server's.
      final catalogue = await _api.fetchCatalogue(token, siteId: current.siteId);
      emit(current.copyWith(catalogue: catalogue, isMutating: false));
    } on KpiApiException catch (error) {
      emit(current.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
