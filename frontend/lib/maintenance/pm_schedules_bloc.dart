/// The PM schedule list's state (issue #74): which Site is being looked at,
/// and what schedules are attached to its Assets.
///
/// Route-scoped, like `DowntimeBloc` and `RequestsBloc`: one Screen's reading
/// of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose, the same reason `WorkOrdersBloc` does: the
/// schedules are Maintenance's (`MaintenanceApi`), the Sites to choose between
/// are People's (`PeopleApi`), and no Maintenance endpoint answers the latter
/// — ADR-0006 keeps a Module asking the owning Module rather than growing its
/// own copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'pm_schedule.dart';

sealed class PmSchedulesEvent {
  const PmSchedulesEvent();
}

/// Load the Sites, then the schedules at the first of them. Also the retry a
/// failed load offers, so a retry re-does whichever half failed.
class PmSchedulesStarted extends PmSchedulesEvent {
  const PmSchedulesStarted();
}

/// Look at a different Site's schedules.
class PmSchedulesSiteSelected extends PmSchedulesEvent {
  const PmSchedulesSiteSelected(this.siteId);
  final String siteId;
}

/// The create form has decided: attach [jobPlanId] to [assetId] with an
/// interval in days. The dialog decides, the Bloc only ever sees a decision
/// already made.
class PmScheduleCreateConfirmed extends PmSchedulesEvent {
  const PmScheduleCreateConfirmed({
    required this.assetId,
    required this.jobPlanId,
    required this.intervalDays,
    required this.anchor,
    this.leadTimeDays,
    this.priority,
    this.nextDueOn,
  });

  final String assetId;
  final String jobPlanId;
  final int intervalDays;
  final String anchor;
  final int? leadTimeDays;
  final int? priority;
  final String? nextDueOn;
}

/// Deactivate or reactivate one PM schedule — one event for both, the same
/// single write (`setPmScheduleActive`) either way.
class PmScheduleActiveToggled extends PmSchedulesEvent {
  const PmScheduleActiveToggled({required this.pmScheduleId, required this.isActive});
  final String pmScheduleId;
  final bool isActive;
}

sealed class PmSchedulesState {
  const PmSchedulesState();
}

/// The first load, before even the Site list is known.
class PmSchedulesLoading extends PmSchedulesState {
  const PmSchedulesLoading();
}

class PmSchedulesLoaded extends PmSchedulesState {
  const PmSchedulesLoaded({
    required this.sites,
    required this.siteId,
    this.schedules = const [],
    this.isLoadingSchedules = false,
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<PmSchedule> schedules;

  /// A Site switch re-reads the list while the rest of the Screen stays put —
  /// the placeholders belong to the list, not the whole Screen.
  final bool isLoadingSchedules;

  /// A create or an active toggle is in flight — one flag, not two, the same
  /// reasoning `RequestsLoaded.isTriaging` gives its own queue.
  final bool isMutating;

  /// Why the last create did not land. Reported by the open create dialog,
  /// which stays open so the caller can fix the field.
  final String? mutationFailure;

  /// What the last act had to say for itself — a create's success, or a
  /// deactivate/reactivate that failed and has no dialog of its own to report
  /// it. Never the failure of a load: that is [PmSchedulesUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  PmSchedulesLoaded copyWith({
    List<PmSchedule>? schedules,
    String? siteId,
    bool? isLoadingSchedules,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      PmSchedulesLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        schedules: schedules ?? this.schedules,
        isLoadingSchedules: isLoadingSchedules ?? this.isLoadingSchedules,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `RequestsLoaded.copyWith` gives `triageFailure`.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class PmSchedulesUnavailable extends PmSchedulesState {
  const PmSchedulesUnavailable({required this.message});
  final String message;
}

class PmSchedulesBloc extends Bloc<PmSchedulesEvent, PmSchedulesState> {
  PmSchedulesBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const PmSchedulesLoading()) {
    on<PmSchedulesStarted>(_onStarted);
    on<PmSchedulesSiteSelected>(_onSiteSelected);
    on<PmScheduleCreateConfirmed>(_onCreateConfirmed);
    on<PmScheduleActiveToggled>(_onActiveToggled);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing to show.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, so a retry re-opens on it rather than jumping back to the first.
  String? _lastSiteId;

  Future<void> _onStarted(PmSchedulesStarted event, Emitter<PmSchedulesState> emit) async {
    emit(const PmSchedulesLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const PmSchedulesUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(PmSchedulesUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const PmSchedulesUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(PmSchedulesLoaded(sites: sites, siteId: opensOn, isLoadingSchedules: true));
    await _readList(opensOn, emit);
  }

  Future<void> _onSiteSelected(PmSchedulesSiteSelected event, Emitter<PmSchedulesState> emit) async {
    final current = state;
    if (current is! PmSchedulesLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, schedules: const [], isLoadingSchedules: true));
    await _readList(event.siteId, emit);
  }

  // Deactivated schedules included, so the list can reach one to reactivate it
  // — the same reasoning `JobPlansBloc._readList` gives its own catalogue.
  Future<void> _readList(String siteId, Emitter<PmSchedulesState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const PmSchedulesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final schedules = await _maintenance.fetchPmSchedules(
        token,
        siteId: siteId,
        includeInactive: true,
      );
      final settled = state;
      // A late response for a Site the caller has since left is discarded —
      // the same staleness guard `RequestsBloc._readQueue` follows.
      if (settled is! PmSchedulesLoaded || settled.siteId != siteId) return;
      emit(
        settled.copyWith(
          schedules: schedules,
          isLoadingSchedules: false,
          isMutating: false,
          notice: notice,
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! PmSchedulesLoaded || settled.siteId != siteId) return;
      emit(PmSchedulesUnavailable(message: error.message));
    }
  }

  Future<void> _onCreateConfirmed(PmScheduleCreateConfirmed event, Emitter<PmSchedulesState> emit) async {
    final current = state;
    if (current is! PmSchedulesLoaded || current.isMutating) return;
    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final schedule = await _maintenance.createPmSchedule(
        token,
        assetId: event.assetId,
        jobPlanId: event.jobPlanId,
        intervalDays: event.intervalDays,
        anchor: event.anchor,
        leadTimeDays: event.leadTimeDays,
        priority: event.priority,
        nextDueOn: event.nextDueOn,
      );
      // Re-read rather than splice: the created schedule's own response does
      // not say which Site it landed in, and the server's list order is by due
      // date, so a second read is the honest way to place it.
      await _readList(siteId, emit, notice: '${schedule.code} has been scheduled.');
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! PmSchedulesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onActiveToggled(PmScheduleActiveToggled event, Emitter<PmSchedulesState> emit) async {
    final current = state;
    if (current is! PmSchedulesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final schedule = await _maintenance.setPmScheduleActive(
        token,
        event.pmScheduleId,
        isActive: event.isActive,
      );
      final settled = state;
      if (settled is! PmSchedulesLoaded) return;
      emit(
        settled.copyWith(
          isMutating: false,
          schedules: [
            for (final existing in settled.schedules)
              if (existing.id == schedule.id) schedule else existing,
          ],
          notice: schedule.isActive
              ? '${schedule.code} has been reactivated.'
              : '${schedule.code} has been deactivated.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! PmSchedulesLoaded) return;
      emit(settled.copyWith(isMutating: false, notice: error.message));
    }
  }
}
