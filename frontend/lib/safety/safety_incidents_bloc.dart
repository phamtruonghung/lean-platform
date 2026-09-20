/// The Safety incident register's own state (issue #226): a Site's
/// incidents, the filters that narrow them, and the recording of a new one.
///
/// Route-scoped and shared by the whole Safety incident surface, the same
/// shape `NonconformancesBloc` keeps: one `ShellRoute` creates it once and
/// the register, the record form's own address and the detail Screen all
/// read it, so the Site and the filters a caller picked survive opening a
/// record and coming back.
///
/// Every filter sends a request rather than hiding rows client-side — that is
/// what the server's own indexes and its ltree walk are for. Unlike
/// `NonconformancesBloc`, there is no catalogue to load alongside the
/// register: incident type and severity level are fixed sets this Module
/// names itself ([IncidentType], [SeverityLevel]), not reference data the
/// server maintains.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'safety_api.dart';
import 'safety_incident.dart';

sealed class SafetyIncidentsEvent {
  const SafetyIncidentsEvent();
}

/// Load the register: the Sites and the Site's Safety incidents. Also the
/// retry a failed load offers.
class SafetyIncidentsStarted extends SafetyIncidentsEvent {
  const SafetyIncidentsStarted();
}

/// Re-read the list whenever the register is entered (the same reasoning
/// `NonconformancesRefreshed` carries, issue #183): the `ShellRoute` keeps
/// this Bloc alive while a caller reads an incident and comes back.
class SafetyIncidentsRefreshed extends SafetyIncidentsEvent {
  const SafetyIncidentsRefreshed();
}

class SafetyIncidentsSiteSelected extends SafetyIncidentsEvent {
  const SafetyIncidentsSiteSelected(this.siteId);

  final String siteId;
}

/// Narrow to one Org Unit and everything beneath it. The name rides along so
/// the button can say which area is on screen without a second read.
class SafetyIncidentsOrgUnitFilterSet extends SafetyIncidentsEvent {
  const SafetyIncidentsOrgUnitFilterSet({required this.orgUnitId, required this.name});

  final String orgUnitId;
  final String name;
}

class SafetyIncidentsStatusFilterChanged extends SafetyIncidentsEvent {
  const SafetyIncidentsStatusFilterChanged(this.status);

  final String? status;
}

class SafetyIncidentsTypeFilterChanged extends SafetyIncidentsEvent {
  const SafetyIncidentsTypeFilterChanged(this.incidentType);

  final String? incidentType;
}

class SafetyIncidentsSeverityFilterChanged extends SafetyIncidentsEvent {
  const SafetyIncidentsSeverityFilterChanged(this.severityLevel);

  final String? severityLevel;
}

class SafetyIncidentsRecordableFilterChanged extends SafetyIncidentsEvent {
  const SafetyIncidentsRecordableFilterChanged(this.isRecordable);

  final bool? isRecordable;
}

/// The production days the register covers, either end optional.
class SafetyIncidentsDateRangeChanged extends SafetyIncidentsEvent {
  const SafetyIncidentsDateRangeChanged({
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

class SafetyIncidentsFiltersCleared extends SafetyIncidentsEvent {
  const SafetyIncidentsFiltersCleared();
}

/// The record form has decided: a whole new Safety incident. Same contract as
/// `NonconformanceRecordConfirmed` — the dialog decides, the Bloc only ever
/// sees a decision already made, and the refusal comes back as
/// `recordFailure` so the dialog stays open with its values.
class SafetyIncidentRecordConfirmed extends SafetyIncidentsEvent {
  const SafetyIncidentRecordConfirmed({
    required this.orgUnitId,
    required this.occurredAt,
    required this.incidentType,
    required this.severityLevel,
    required this.description,
    this.assetId,
    this.employeeId,
    this.reportedAt,
    this.immediateAction,
    this.lostTimeDays,
    this.restrictedDays,
  });

  final String orgUnitId;
  final String occurredAt;
  final String incidentType;
  final String severityLevel;
  final String description;
  final String? assetId;
  final String? employeeId;
  final String? reportedAt;
  final String? immediateAction;
  final int? lostTimeDays;
  final int? restrictedDays;
}

sealed class SafetyIncidentsState {
  const SafetyIncidentsState();
}

class SafetyIncidentsLoading extends SafetyIncidentsState {
  const SafetyIncidentsLoading();
}

class SafetyIncidentsUnavailable extends SafetyIncidentsState {
  const SafetyIncidentsUnavailable({required this.message});

  final String message;
}

class SafetyIncidentsLoaded extends SafetyIncidentsState {
  const SafetyIncidentsLoaded({
    required this.sites,
    required this.siteId,
    required this.filters,
    required this.incidents,
    required this.truncated,
    this.isRecording = false,
    this.recordFailure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none — in which
  /// case there is no register to read and the Screen says so.
  final String? siteId;

  final SafetyIncidentFilters filters;
  final List<SafetyIncident> incidents;
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

  SafetyIncidentsLoaded copyWith({
    String? siteId,
    SafetyIncidentFilters? filters,
    List<SafetyIncident>? incidents,
    bool? truncated,
    bool? isRecording,
    String? recordFailure,
  }) =>
      SafetyIncidentsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        filters: filters ?? this.filters,
        incidents: incidents ?? this.incidents,
        truncated: truncated ?? this.truncated,
        isRecording: isRecording ?? this.isRecording,
        // Always overwritten, never carried forward — the same rule
        // `NonconformancesLoaded.copyWith` gives its own failure.
        recordFailure: recordFailure,
      );
}

class SafetyIncidentsBloc extends Bloc<SafetyIncidentsEvent, SafetyIncidentsState> {
  SafetyIncidentsBloc({
    required SafetyApi safetyApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = safetyApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const SafetyIncidentsLoading()) {
    on<SafetyIncidentsStarted>(_onStarted);
    on<SafetyIncidentsRefreshed>(_onRefreshed);
    on<SafetyIncidentsSiteSelected>(_onSiteSelected);
    on<SafetyIncidentsOrgUnitFilterSet>(_onOrgUnitFilterSet);
    on<SafetyIncidentsStatusFilterChanged>(_onStatusFilterChanged);
    on<SafetyIncidentsTypeFilterChanged>(_onTypeFilterChanged);
    on<SafetyIncidentsSeverityFilterChanged>(_onSeverityFilterChanged);
    on<SafetyIncidentsRecordableFilterChanged>(_onRecordableFilterChanged);
    on<SafetyIncidentsDateRangeChanged>(_onDateRangeChanged);
    on<SafetyIncidentsFiltersCleared>(_onFiltersCleared);
    on<SafetyIncidentRecordConfirmed>(_onRecordConfirmed);
  }

  final SafetyApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(
    SafetyIncidentsStarted event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    emit(const SafetyIncidentsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyIncidentsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      if (sites.isEmpty) {
        emit(
          const SafetyIncidentsLoaded(
            sites: [],
            siteId: null,
            filters: SafetyIncidentFilters(),
            incidents: [],
            truncated: false,
          ),
        );
        return;
      }
      await _readSite(sites, sites.first.id, const SafetyIncidentFilters(), emit);
    } on SafetyApiException catch (error) {
      emit(SafetyIncidentsUnavailable(message: error.message));
    } on PeopleApiException catch (error) {
      emit(SafetyIncidentsUnavailable(message: error.message));
    }
  }

  // A re-read that keeps the Site and the filters, and paints the stale list
  // until the new one lands — the same rule `NonconformancesRefreshed`'s own
  // handler follows.
  Future<void> _onRefreshed(
    SafetyIncidentsRefreshed event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _onSiteSelected(
    SafetyIncidentsSiteSelected event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    // A Site change clears the filters: an Org Unit belongs to the Site it
    // was chosen in.
    await _readSite(settled.sites, event.siteId, const SafetyIncidentFilters(), emit);
  }

  Future<void> _onOrgUnitFilterSet(
    SafetyIncidentsOrgUnitFilterSet event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.name),
      emit,
    );
  }

  Future<void> _onStatusFilterChanged(
    SafetyIncidentsStatusFilterChanged event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    final moved = event.status == null
        ? settled.filters.copyWith(clearStatus: true)
        : settled.filters.copyWith(status: event.status);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onTypeFilterChanged(
    SafetyIncidentsTypeFilterChanged event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    final moved = event.incidentType == null
        ? settled.filters.copyWith(clearIncidentType: true)
        : settled.filters.copyWith(incidentType: event.incidentType);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onSeverityFilterChanged(
    SafetyIncidentsSeverityFilterChanged event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    final moved = event.severityLevel == null
        ? settled.filters.copyWith(clearSeverityLevel: true)
        : settled.filters.copyWith(severityLevel: event.severityLevel);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onRecordableFilterChanged(
    SafetyIncidentsRecordableFilterChanged event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    final moved = event.isRecordable == null
        ? settled.filters.copyWith(clearIsRecordable: true)
        : settled.filters.copyWith(isRecordable: event.isRecordable);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onDateRangeChanged(
    SafetyIncidentsDateRangeChanged event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
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
    SafetyIncidentsFiltersCleared event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = state;
    if (settled is! SafetyIncidentsLoaded) return;
    await _applyFilters(settled, const SafetyIncidentFilters(), emit);
  }

  Future<void> _readSite(
    List<Site> sites,
    String? siteId,
    SafetyIncidentFilters filters,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = SafetyIncidentsLoaded(
      sites: sites,
      siteId: siteId,
      filters: filters,
      incidents: const [],
      truncated: false,
    );
    emit(settled);
    await _readList(settled, siteId, emit);
  }

  /// Puts a filter set in force, then reads with it — the same two-step
  /// `NonconformancesBloc._applyFilters` follows and for the same reason.
  Future<void> _applyFilters(
    SafetyIncidentsLoaded current,
    SafetyIncidentFilters filters,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final settled = current.copyWith(filters: filters);
    emit(settled);
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _readList(
    SafetyIncidentsLoaded current,
    String? siteId,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyIncidentsUnavailable(message: signedOutMessage));
      return;
    }
    if (siteId == null) {
      emit(current.copyWith(incidents: const [], truncated: false));
      return;
    }
    try {
      final page = await _api.fetchSafetyIncidents(token, siteId, filters: current.filters);
      emit(
        current.copyWith(
          siteId: siteId,
          incidents: page.incidents,
          truncated: page.truncated,
        ),
      );
    } on SafetyApiException catch (error) {
      emit(SafetyIncidentsUnavailable(message: error.message));
    }
  }

  Future<void> _onRecordConfirmed(
    SafetyIncidentRecordConfirmed event,
    Emitter<SafetyIncidentsState> emit,
  ) async {
    final current = state;
    if (current is! SafetyIncidentsLoaded || current.isRecording) return;
    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(recordFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, recordFailure: null));
    try {
      await _api.recordSafetyIncident(
        token,
        siteId,
        orgUnitId: event.orgUnitId,
        occurredAt: event.occurredAt,
        incidentType: event.incidentType,
        severityLevel: event.severityLevel,
        description: event.description,
        assetId: event.assetId,
        employeeId: event.employeeId,
        reportedAt: event.reportedAt,
        immediateAction: event.immediateAction,
        lostTimeDays: event.lostTimeDays,
        restrictedDays: event.restrictedDays,
      );
      final settled = state;
      if (settled is! SafetyIncidentsLoaded) return;
      emit(settled.copyWith(isRecording: false));
      final loaded = state;
      if (loaded is! SafetyIncidentsLoaded) return;
      await _readList(loaded, siteId, emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! SafetyIncidentsLoaded) return;
      emit(settled.copyWith(isRecording: false, recordFailure: error.message));
    }
  }
}
