/// One KPI's Targets at one Site (ADR-0055): what is in force today and the
/// whole history.
///
/// Two reads with one purpose each. `GET /api/kpi/targets` carries no date, so
/// the Bloc also reads `GET /api/kpi/catalogue?site_id=` and takes its
/// `review_date` as the Site's today — the server's, never Dart's clock — which
/// bounds the Change Target dialog's date picker.
///
/// Route-scoped, and keyed on the address (the KPI and, when the catalogue sent
/// one, the Site) at the router. The Site chooser has the shape of
/// `SkillCoverageBloc`'s: open on the Site named in the address or else the
/// first, re-read on switch.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart' show Site;
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'kpi_api.dart';
import 'kpi_catalogue.dart';

sealed class KpiTargetsEvent {
  const KpiTargetsEvent();
}

class KpiTargetsStarted extends KpiTargetsEvent {
  const KpiTargetsStarted({required this.kpiId, this.siteId});
  final int kpiId;

  /// The Site the catalogue was showing when the row was tapped, if any.
  final String? siteId;
}

class KpiTargetsSiteSelected extends KpiTargetsEvent {
  const KpiTargetsSiteSelected(this.siteId);
  final String siteId;
}

class TargetAdded extends KpiTargetsEvent {
  const TargetAdded({required this.grain, required this.validFrom, required this.target, this.note});

  final String grain;
  final String validFrom;

  /// Null is "no target from that date on".
  final double? target;
  final String? note;
}

sealed class KpiTargetsState {
  const KpiTargetsState();
}

class KpiTargetsLoading extends KpiTargetsState {
  const KpiTargetsLoading();
}

class KpiTargetsUnavailable extends KpiTargetsState {
  const KpiTargetsUnavailable({required this.message});
  final String message;
}

class KpiTargetsLoaded extends KpiTargetsState {
  const KpiTargetsLoaded({
    required this.sites,
    required this.siteId,
    required this.siteToday,
    required this.targets,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<Site> sites;
  final String siteId;

  /// The Site's today, from the catalogue read's `review_date`.
  final String siteToday;
  final KpiTargets targets;
  final bool isMutating;
  final String? mutationFailure;

  KpiTargetsLoaded copyWith({KpiTargets? targets, bool? isMutating, String? mutationFailure}) => KpiTargetsLoaded(
        sites: sites,
        siteId: siteId,
        siteToday: siteToday,
        targets: targets ?? this.targets,
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
      );
}

class KpiTargetsBloc extends Bloc<KpiTargetsEvent, KpiTargetsState> {
  KpiTargetsBloc({required PeopleApi peopleApi, required KpiApi kpiApi, required AuthGateway authGateway})
      : _people = peopleApi,
        _api = kpiApi,
        _auth = authGateway,
        super(const KpiTargetsLoading()) {
    on<KpiTargetsStarted>(_onStarted);
    on<KpiTargetsSiteSelected>(_onSiteSelected);
    on<TargetAdded>(_onTargetAdded);
  }

  final PeopleApi _people;
  final KpiApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there are no Targets to show.';

  int? _kpiId;
  String? _lastSiteId;

  Future<void> _onStarted(KpiTargetsStarted event, Emitter<KpiTargetsState> emit) async {
    _kpiId = event.kpiId;
    emit(const KpiTargetsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const KpiTargetsUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(KpiTargetsUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const KpiTargetsUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = event.siteId ?? _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    await _read(token, sites, opensOn, emit);
  }

  Future<void> _onSiteSelected(KpiTargetsSiteSelected event, Emitter<KpiTargetsState> emit) async {
    final current = state;
    final token = _auth.currentAccessToken;
    if (current is! KpiTargetsLoaded) return;
    if (token == null) {
      emit(const KpiTargetsUnavailable(message: signedOutMessage));
      return;
    }
    _lastSiteId = event.siteId;
    await _read(token, current.sites, event.siteId, emit);
  }

  Future<void> _read(String token, List<Site> sites, String siteId, Emitter<KpiTargetsState> emit) async {
    final kpiId = _kpiId!;
    try {
      final targets = await _api.fetchTargets(token, siteId: siteId, kpiId: kpiId);
      // The Site's today: the catalogue read's `review_date` (see the header).
      final catalogue = await _api.fetchCatalogue(token, siteId: siteId);
      emit(KpiTargetsLoaded(sites: sites, siteId: siteId, siteToday: catalogue.reviewDate, targets: targets));
    } on KpiApiException catch (error) {
      emit(KpiTargetsUnavailable(message: error.message));
    }
  }

  Future<void> _onTargetAdded(TargetAdded event, Emitter<KpiTargetsState> emit) async {
    final current = state;
    final kpiId = _kpiId;
    if (current is! KpiTargetsLoaded || current.isMutating || kpiId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true));
    try {
      await _api.addTarget(
        token,
        siteId: current.siteId,
        kpiId: kpiId,
        grain: event.grain,
        validFrom: event.validFrom,
        target: event.target,
        note: event.note,
      );
      final targets = await _api.fetchTargets(token, siteId: current.siteId, kpiId: kpiId);
      emit(current.copyWith(targets: targets, isMutating: false));
    } on KpiApiException catch (error) {
      emit(current.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
