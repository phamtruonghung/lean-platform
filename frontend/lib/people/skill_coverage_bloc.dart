/// A Site's skill coverage (issue #89, AC6): which Site is being looked at,
/// and where it is thin. Administrator only —
/// `GET /api/people/sites/:siteId/skill-coverage` is deliberately narrower
/// than every other Site-shaped read this Module makes (skill-routes.js's own
/// header: "how the plant is being run", not "who works here").
///
/// Route-scoped, like `AssetsBloc`, and the same reason it switches Sites:
/// one Screen's own reading of the server, re-read on arrival rather than
/// restored stale, with a Site chooser that re-reads on switch.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'org_unit.dart';
import 'skill.dart';

sealed class SkillCoverageEvent {
  const SkillCoverageEvent();
}

/// Load the Sites, then the coverage report at the first of them. Also the
/// retry a failed load offers, so a retry re-does whichever half failed.
class SkillCoverageStarted extends SkillCoverageEvent {
  const SkillCoverageStarted();
}

/// Look at a different Site's coverage.
class SkillCoverageSiteSelected extends SkillCoverageEvent {
  const SkillCoverageSiteSelected(this.siteId);
  final String siteId;
}

sealed class SkillCoverageState {
  const SkillCoverageState();
}

/// The first load, before even the Site list is known.
class SkillCoverageLoading extends SkillCoverageState {
  const SkillCoverageLoading();
}

class SkillCoverageLoaded extends SkillCoverageState {
  const SkillCoverageLoaded({
    required this.sites,
    required this.siteId,
    this.entries = const [],
    this.isLoadingCoverage = false,
  });

  final List<Site> sites;
  final String? siteId;
  final List<SkillCoverageEntry> entries;

  /// A Site switch re-reads the report while the Site chooser stays on
  /// screen — the same shape `AssetsLoaded.isLoadingAssets` uses.
  final bool isLoadingCoverage;

  SkillCoverageLoaded copyWith({
    List<SkillCoverageEntry>? entries,
    String? siteId,
    bool? isLoadingCoverage,
  }) =>
      SkillCoverageLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        entries: entries ?? this.entries,
        isLoadingCoverage: isLoadingCoverage ?? this.isLoadingCoverage,
      );
}

class SkillCoverageUnavailable extends SkillCoverageState {
  const SkillCoverageUnavailable({required this.message});
  final String message;
}

class SkillCoverageBloc extends Bloc<SkillCoverageEvent, SkillCoverageState> {
  SkillCoverageBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const SkillCoverageLoading()) {
    on<SkillCoverageStarted>(_onStarted);
    on<SkillCoverageSiteSelected>(_onSiteSelected);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage =
      'There are no Sites you can see, so there is no coverage to show.';

  /// The last Site the caller actually settled on — the same reason
  /// `AssetsBloc._lastSiteId` is kept: a retry must re-open on it.
  String? _lastSiteId;

  Future<void> _onStarted(SkillCoverageStarted event, Emitter<SkillCoverageState> emit) async {
    emit(const SkillCoverageLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SkillCoverageUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _api.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(SkillCoverageUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const SkillCoverageUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(SkillCoverageLoaded(sites: sites, siteId: opensOn, isLoadingCoverage: true));
    await _readCoverage(opensOn, emit);
  }

  Future<void> _onSiteSelected(SkillCoverageSiteSelected event, Emitter<SkillCoverageState> emit) async {
    final current = state;
    if (current is! SkillCoverageLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, entries: const [], isLoadingCoverage: true));
    await _readCoverage(event.siteId, emit);
  }

  Future<void> _readCoverage(String siteId, Emitter<SkillCoverageState> emit) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! SkillCoverageLoaded) return;
    if (token == null) {
      emit(const SkillCoverageUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final entries = await _api.fetchSiteSkillCoverage(token, siteId);
      if (state is! SkillCoverageLoaded || (state as SkillCoverageLoaded).siteId != siteId) return;
      emit((state as SkillCoverageLoaded).copyWith(entries: entries, isLoadingCoverage: false));
    } on PeopleApiException catch (error) {
      if (state is! SkillCoverageLoaded || (state as SkillCoverageLoaded).siteId != siteId) return;
      emit(SkillCoverageUnavailable(message: error.message));
    }
  }
}
