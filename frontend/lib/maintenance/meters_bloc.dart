/// The meters list's state (issue #79): which Site is being looked at, and the
/// meters attached to its Assets.
///
/// Route-scoped, like `PmSchedulesBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale. It holds two APIs on
/// purpose, the same reason `PmSchedulesBloc` does — the meters are
/// Maintenance's, the Sites to choose between are People's, and no Maintenance
/// endpoint answers the latter (ADR-0006).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'meter.dart';

sealed class MetersEvent {
  const MetersEvent();
}

/// Load the Sites, then the meters at the first of them. Also the retry a
/// failed load offers.
class MetersStarted extends MetersEvent {
  const MetersStarted();
}

/// Look at a different Site's meters.
class MetersSiteSelected extends MetersEvent {
  const MetersSiteSelected(this.siteId);
  final String siteId;
}

/// The create form has decided: define [code] on [assetId].
class MeterCreateConfirmed extends MetersEvent {
  const MeterCreateConfirmed({
    required this.assetId,
    required this.code,
    required this.name,
    required this.uomCode,
    required this.meterType,
  });

  final String assetId;
  final String code;
  final String name;
  final String uomCode;
  final String meterType;
}

/// The reading form has decided: record [reading] against [meterId], either
/// as an ordinary reading or as an explicit rollover/replacement (ADR-0029).
class MeterReadingConfirmed extends MetersEvent {
  const MeterReadingConfirmed({
    required this.meterId,
    required this.reading,
    required this.isRollover,
    this.note,
  });

  final String meterId;
  final num reading;
  final bool isRollover;
  final String? note;
}

sealed class MetersState {
  const MetersState();
}

class MetersLoading extends MetersState {
  const MetersLoading();
}

class MetersLoaded extends MetersState {
  const MetersLoaded({
    required this.sites,
    required this.siteId,
    this.meters = const [],
    this.isLoadingMeters = false,
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<AssetMeter> meters;
  final bool isLoadingMeters;
  final bool isMutating;
  final String? mutationFailure;
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  MetersLoaded copyWith({
    List<AssetMeter>? meters,
    String? siteId,
    bool? isLoadingMeters,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      MetersLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        meters: meters ?? this.meters,
        isLoadingMeters: isLoadingMeters ?? this.isLoadingMeters,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // PmSchedulesLoaded gives mutationFailure.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class MetersUnavailable extends MetersState {
  const MetersUnavailable({required this.message});
  final String message;
}

class MetersBloc extends Bloc<MetersEvent, MetersState> {
  MetersBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const MetersLoading()) {
    on<MetersStarted>(_onStarted);
    on<MetersSiteSelected>(_onSiteSelected);
    on<MeterCreateConfirmed>(_onCreateConfirmed);
    on<MeterReadingConfirmed>(_onReadingConfirmed);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing to show.';

  String? _lastSiteId;

  Future<void> _onStarted(MetersStarted event, Emitter<MetersState> emit) async {
    emit(const MetersLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const MetersUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(MetersUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const MetersUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(MetersLoaded(sites: sites, siteId: opensOn, isLoadingMeters: true));
    await _readList(opensOn, emit);
  }

  Future<void> _onSiteSelected(MetersSiteSelected event, Emitter<MetersState> emit) async {
    final current = state;
    if (current is! MetersLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, meters: const [], isLoadingMeters: true));
    await _readList(event.siteId, emit);
  }

  Future<void> _readList(String siteId, Emitter<MetersState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const MetersUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final meters = await _maintenance.fetchMeters(token, siteId: siteId, includeInactive: true);
      final settled = state;
      if (settled is! MetersLoaded || settled.siteId != siteId) return;
      emit(
        settled.copyWith(
          meters: meters,
          isLoadingMeters: false,
          isMutating: false,
          notice: notice,
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! MetersLoaded || settled.siteId != siteId) return;
      emit(MetersUnavailable(message: error.message));
    }
  }

  Future<void> _onCreateConfirmed(MeterCreateConfirmed event, Emitter<MetersState> emit) async {
    final current = state;
    if (current is! MetersLoaded || current.isMutating) return;
    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final meter = await _maintenance.createMeter(
        token,
        assetId: event.assetId,
        code: event.code,
        name: event.name,
        uomCode: event.uomCode,
        meterType: event.meterType,
      );
      // Re-read rather than splice: the server's list order is by Asset then
      // code, so a second read is the honest way to place it.
      await _readList(siteId, emit, notice: '${meter.code} has been defined.');
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! MetersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onReadingConfirmed(MeterReadingConfirmed event, Emitter<MetersState> emit) async {
    final current = state;
    if (current is! MetersLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final meter = event.isRollover
          ? await _maintenance.rolloverMeter(token, event.meterId, reading: event.reading, note: event.note)
          : await _maintenance.recordMeterReading(
              token,
              event.meterId,
              reading: event.reading,
              note: event.note,
            );
      final settled = state;
      if (settled is! MetersLoaded) return;
      emit(
        settled.copyWith(
          isMutating: false,
          meters: [
            for (final existing in settled.meters)
              if (existing.id == meter.id) meter else existing,
          ],
          notice: event.isRollover
              ? '${meter.code} has been rolled over; accumulated use continues from ${meter.accumulatedLabel}.'
              : '${meter.code} now reads ${meter.latestReadingLabel}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! MetersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
