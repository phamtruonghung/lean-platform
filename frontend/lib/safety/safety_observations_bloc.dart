/// The Safety observation register's own state (issue #230): a Site's
/// observations, worst-first, the filters that narrow them, and the
/// recording of a new one.
///
/// Route-scoped and shared by the whole surface, the same shape
/// `SafetyIncidentsBloc` keeps: one `ShellRoute` creates it once and the
/// register and the record form's own address both read it, so the Site and
/// the filters a caller picked survive opening the record form and coming
/// back.
///
/// Every filter sends a request rather than hiding rows client-side — the
/// server's own worst-first ordering and its ltree walk are what this Bloc
/// relies on. There is no catalogue to load alongside the register:
/// observation type, category and severity potential are fixed sets this
/// Module names itself ([ObservationType], [ObservationCategory],
/// [SeverityPotential]), not reference data the server maintains.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'safety_api.dart';
import 'safety_observation.dart';

sealed class SafetyObservationsEvent {
  const SafetyObservationsEvent();
}

class SafetyObservationsStarted extends SafetyObservationsEvent {
  const SafetyObservationsStarted();
}

/// Re-read the list whenever the register is entered — the same reasoning
/// `SafetyIncidentsRefreshed` carries.
class SafetyObservationsRefreshed extends SafetyObservationsEvent {
  const SafetyObservationsRefreshed();
}

class SafetyObservationsSiteSelected extends SafetyObservationsEvent {
  const SafetyObservationsSiteSelected(this.siteId);

  final String siteId;
}

/// Narrow to one Org Unit and everything beneath it. The name rides along so
/// the button can say which area is on screen without a second read.
class SafetyObservationsOrgUnitFilterSet extends SafetyObservationsEvent {
  const SafetyObservationsOrgUnitFilterSet({required this.orgUnitId, required this.name});

  final String orgUnitId;
  final String name;
}

class SafetyObservationsTypeFilterChanged extends SafetyObservationsEvent {
  const SafetyObservationsTypeFilterChanged(this.observationType);

  final String? observationType;
}

class SafetyObservationsCategoryFilterChanged extends SafetyObservationsEvent {
  const SafetyObservationsCategoryFilterChanged(this.category);

  final String? category;
}

class SafetyObservationsSeverityPotentialFilterChanged extends SafetyObservationsEvent {
  const SafetyObservationsSeverityPotentialFilterChanged(this.severityPotential);

  final String? severityPotential;
}

class SafetyObservationsStopWorkFilterChanged extends SafetyObservationsEvent {
  const SafetyObservationsStopWorkFilterChanged(this.isStopWork);

  final bool? isStopWork;
}

/// The production days the register covers, either end optional.
class SafetyObservationsDateRangeChanged extends SafetyObservationsEvent {
  const SafetyObservationsDateRangeChanged({
    this.from,
    this.to,
    this.clearFrom = false,
    this.clearTo = false,
  });

  final String? from;
  final String? to;
  final bool clearFrom;
  final bool clearTo;
}

class SafetyObservationsFiltersCleared extends SafetyObservationsEvent {
  const SafetyObservationsFiltersCleared();
}

/// The record form has decided: a whole new Safety observation. Same
/// contract as `SafetyIncidentRecordConfirmed` — the dialog decides, the Bloc
/// only ever sees a decision already made, and the refusal comes back as
/// `recordFailure` so the dialog stays open with its values.
class SafetyObservationRecordConfirmed extends SafetyObservationsEvent {
  const SafetyObservationRecordConfirmed({
    required this.orgUnitId,
    required this.observationType,
    required this.category,
    required this.severityPotential,
    required this.description,
    this.isStopWork = false,
    this.actionTaken,
    this.observedAt,
  });

  final String orgUnitId;
  final String observationType;
  final String category;
  final String severityPotential;
  final String description;
  final bool isStopWork;
  final String? actionTaken;
  final String? observedAt;
}

sealed class SafetyObservationsState {
  const SafetyObservationsState();
}

class SafetyObservationsLoading extends SafetyObservationsState {
  const SafetyObservationsLoading();
}

class SafetyObservationsUnavailable extends SafetyObservationsState {
  const SafetyObservationsUnavailable({required this.message});

  final String message;
}

class SafetyObservationsLoaded extends SafetyObservationsState {
  const SafetyObservationsLoaded({
    required this.sites,
    required this.siteId,
    required this.filters,
    required this.observations,
    required this.truncated,
    this.isRecording = false,
    this.recordFailure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none — in which
  /// case there is no register to read and the Screen says so.
  final String? siteId;

  final SafetyObservationFilters filters;
  final List<SafetyObservation> observations;
  final bool truncated;

  /// A recording is in flight.
  final bool isRecording;

  /// Why the last recording did not land. Reported by the form, which stays
  /// open so the caller can fix the one field that was wrong.
  final String? recordFailure;

  Site? get site {
    for (final site in sites) {
      if (site.id == siteId) return site;
    }
    return null;
  }

  SafetyObservationsLoaded copyWith({
    String? siteId,
    SafetyObservationFilters? filters,
    List<SafetyObservation>? observations,
    bool? truncated,
    bool? isRecording,
    String? recordFailure,
  }) =>
      SafetyObservationsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        filters: filters ?? this.filters,
        observations: observations ?? this.observations,
        truncated: truncated ?? this.truncated,
        isRecording: isRecording ?? this.isRecording,
        // Always overwritten, never carried forward — the same rule
        // `SafetyIncidentsLoaded.copyWith` gives its own failure.
        recordFailure: recordFailure,
      );
}

class SafetyObservationsBloc extends Bloc<SafetyObservationsEvent, SafetyObservationsState> {
  SafetyObservationsBloc({
    required SafetyApi safetyApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = safetyApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const SafetyObservationsLoading()) {
    on<SafetyObservationsStarted>(_onStarted);
    on<SafetyObservationsRefreshed>(_onRefreshed);
    on<SafetyObservationsSiteSelected>(_onSiteSelected);
    on<SafetyObservationsOrgUnitFilterSet>(_onOrgUnitFilterSet);
    on<SafetyObservationsTypeFilterChanged>(_onTypeFilterChanged);
    on<SafetyObservationsCategoryFilterChanged>(_onCategoryFilterChanged);
    on<SafetyObservationsSeverityPotentialFilterChanged>(_onSeverityPotentialFilterChanged);
    on<SafetyObservationsStopWorkFilterChanged>(_onStopWorkFilterChanged);
    on<SafetyObservationsDateRangeChanged>(_onDateRangeChanged);
    on<SafetyObservationsFiltersCleared>(_onFiltersCleared);
    on<SafetyObservationRecordConfirmed>(_onRecordConfirmed);
  }

  final SafetyApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(
    SafetyObservationsStarted event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    emit(const SafetyObservationsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyObservationsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      if (sites.isEmpty) {
        emit(
          const SafetyObservationsLoaded(
            sites: [],
            siteId: null,
            filters: SafetyObservationFilters(),
            observations: [],
            truncated: false,
          ),
        );
        return;
      }
      await _readSite(sites, sites.first.id, const SafetyObservationFilters(), emit);
    } on SafetyApiException catch (error) {
      emit(SafetyObservationsUnavailable(message: error.message));
    } on PeopleApiException catch (error) {
      emit(SafetyObservationsUnavailable(message: error.message));
    }
  }

  Future<void> _onRefreshed(
    SafetyObservationsRefreshed event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _onSiteSelected(
    SafetyObservationsSiteSelected event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    // A Site change clears the filters: an Org Unit belongs to the Site it
    // was chosen in.
    await _readSite(settled.sites, event.siteId, const SafetyObservationFilters(), emit);
  }

  Future<void> _onOrgUnitFilterSet(
    SafetyObservationsOrgUnitFilterSet event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.name),
      emit,
    );
  }

  Future<void> _onTypeFilterChanged(
    SafetyObservationsTypeFilterChanged event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    final moved = event.observationType == null
        ? settled.filters.copyWith(clearObservationType: true)
        : settled.filters.copyWith(observationType: event.observationType);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onCategoryFilterChanged(
    SafetyObservationsCategoryFilterChanged event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    final moved = event.category == null
        ? settled.filters.copyWith(clearCategory: true)
        : settled.filters.copyWith(category: event.category);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onSeverityPotentialFilterChanged(
    SafetyObservationsSeverityPotentialFilterChanged event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    final moved = event.severityPotential == null
        ? settled.filters.copyWith(clearSeverityPotential: true)
        : settled.filters.copyWith(severityPotential: event.severityPotential);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onStopWorkFilterChanged(
    SafetyObservationsStopWorkFilterChanged event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    final moved = event.isStopWork == null
        ? settled.filters.copyWith(clearIsStopWork: true)
        : settled.filters.copyWith(isStopWork: event.isStopWork);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onDateRangeChanged(
    SafetyObservationsDateRangeChanged event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    var moved = settled.filters;
    if (event.clearFrom) {
      moved = moved.copyWith(clearFrom: true);
    } else if (event.from != null) {
      moved = moved.copyWith(from: event.from);
    }
    if (event.clearTo) {
      moved = moved.copyWith(clearTo: true);
    } else if (event.to != null) {
      moved = moved.copyWith(to: event.to);
    }
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onFiltersCleared(
    SafetyObservationsFiltersCleared event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyObservationsLoaded) return;
    await _applyFilters(settled, const SafetyObservationFilters(), emit);
  }

  Future<void> _readSite(
    List<Site> sites,
    String? siteId,
    SafetyObservationFilters filters,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = SafetyObservationsLoaded(
      sites: sites,
      siteId: siteId,
      filters: filters,
      observations: const [],
      truncated: false,
    );
    emit(settled);
    await _readList(settled, siteId, emit);
  }

  /// Puts a filter set in force, then reads with it — the same two-step
  /// `SafetyIncidentsBloc._applyFilters` follows and for the same reason.
  Future<void> _applyFilters(
    SafetyObservationsLoaded current,
    SafetyObservationFilters filters,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final settled = current.copyWith(filters: filters);
    emit(settled);
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _readList(
    SafetyObservationsLoaded current,
    String? siteId,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyObservationsUnavailable(message: signedOutMessage));
      return;
    }
    if (siteId == null) {
      emit(current.copyWith(observations: const [], truncated: false));
      return;
    }
    try {
      final page = await _api.fetchSafetyObservations(token, siteId, filters: current.filters);
      emit(
        current.copyWith(
          siteId: siteId,
          observations: page.observations,
          truncated: page.truncated,
        ),
      );
    } on SafetyApiException catch (error) {
      emit(SafetyObservationsUnavailable(message: error.message));
    }
  }

  Future<void> _onRecordConfirmed(
    SafetyObservationRecordConfirmed event,
    Emitter<SafetyObservationsState> emit,
  ) async {
    final current = state;
    if (current is! SafetyObservationsLoaded || current.isRecording) return;
    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(recordFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, recordFailure: null));
    try {
      await _api.recordSafetyObservation(
        token,
        siteId,
        orgUnitId: event.orgUnitId,
        observationType: event.observationType,
        category: event.category,
        severityPotential: event.severityPotential,
        description: event.description,
        isStopWork: event.isStopWork,
        actionTaken: event.actionTaken,
        observedAt: event.observedAt,
      );
      final settled = state;
      if (settled is! SafetyObservationsLoaded) return;
      emit(settled.copyWith(isRecording: false));
      final loaded = state;
      if (loaded is! SafetyObservationsLoaded) return;
      await _readList(loaded, siteId, emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! SafetyObservationsLoaded) return;
      emit(settled.copyWith(isRecording: false, recordFailure: error.message));
    }
  }
}
