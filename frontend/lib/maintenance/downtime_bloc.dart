/// The Downtime Screen's state: which Site is being looked at, what stops are
/// open there, and a Breakdown being reported (issue #73).
///
/// Route-scoped, like `RequestsBloc` and `WorkOrdersBloc`: one Screen's reading
/// of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs for the same reason every other Maintenance Bloc does: the
/// stops are Maintenance's (`MaintenanceApi`), the Sites to choose between are
/// People's (`PeopleApi`), and ADR-0006 keeps a Module asking the owning Module
/// rather than growing its own copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'downtime_event.dart';
import 'maintenance_api.dart';

sealed class DowntimeEventBase {
  const DowntimeEventBase();
}

/// Load the Sites, then the open stops at the first of them. Also the retry a
/// failed load offers, so a retry re-does whichever half failed.
class DowntimeStarted extends DowntimeEventBase {
  const DowntimeStarted();
}

/// Look at a different Site's stops.
class DowntimeSiteSelected extends DowntimeEventBase {
  const DowntimeSiteSelected(this.siteId);
  final String siteId;
}

/// The close dialog has decided: close this stop, at [endedAt] when the caller
/// chose one. The server owns the resulting duration and status.
class DowntimeCloseConfirmed extends DowntimeEventBase {
  const DowntimeCloseConfirmed({required this.downtimeEventId, this.endedAt});
  final String downtimeEventId;
  final DateTime? endedAt;
}

/// The classify dialog has decided: this stop is against [downtimeReasonId],
/// with [description] when the caller gave one. The server refuses a
/// `requiresComment` reason with no description (400) — the dialog blocks that
/// before dispatching.
class DowntimeClassifyConfirmed extends DowntimeEventBase {
  const DowntimeClassifyConfirmed({
    required this.downtimeEventId,
    required this.downtimeReasonId,
    this.description,
  });
  final String downtimeEventId;
  final String downtimeReasonId;
  final String? description;
}

/// The report dialog has decided: this is a whole Breakdown, with the Asset
/// already chosen.
///
/// [siteId] is the Site the chosen Asset was fetched from, carried so the Bloc
/// can decide whether the new row belongs on this Screen without a second read
/// — the same reasoning `RequestRaiseConfirmed.siteId` follows.
class BreakdownReportConfirmed extends DowntimeEventBase {
  const BreakdownReportConfirmed({
    required this.siteId,
    required this.assetId,
    this.startedAt,
    this.description,
  });
  final String siteId;
  final String assetId;
  final DateTime? startedAt;
  final String? description;
}

sealed class DowntimeState {
  const DowntimeState();
}

/// The first load, before even the Site list is known.
class DowntimeLoading extends DowntimeState {
  const DowntimeLoading();
}

class DowntimeLoaded extends DowntimeState {
  const DowntimeLoaded({
    required this.sites,
    required this.siteId,
    this.events = const [],
    this.isLoadingEvents = false,
    this.isActing = false,
    this.actionFailure,
    this.isReporting = false,
    this.reportFailure,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<DowntimeEvent> events;

  /// A Site switch re-reads the list while the rest of the Screen stays put —
  /// the placeholders belong to the list, not the whole Screen.
  final bool isLoadingEvents;

  /// A close or classify is in flight — one flag for both, mirroring
  /// `RequestsLoaded.isTriaging`: the Screen only needs "a row action is in
  /// flight" to disable every row's actions while it settles.
  final bool isActing;

  /// Why the last close or classify did not land. Read by whichever dialog is
  /// open so it can stay open and let the caller fix the field.
  final String? actionFailure;

  /// A Breakdown report is in flight, kept on the state so the Screen can
  /// refuse a second one.
  final bool isReporting;

  /// Why the last report did not land — the server's own message, so a
  /// duplicate's actionable "already recorded as down since …" sentence is
  /// shown verbatim by the dialog, which stays open.
  final String? reportFailure;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [DowntimeUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  DowntimeLoaded copyWith({
    List<DowntimeEvent>? events,
    String? siteId,
    bool? isLoadingEvents,
    bool? isActing,
    String? actionFailure,
    bool? isReporting,
    String? reportFailure,
    String? notice,
  }) =>
      DowntimeLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        events: events ?? this.events,
        isLoadingEvents: isLoadingEvents ?? this.isLoadingEvents,
        isActing: isActing ?? this.isActing,
        // Cleared on every emit that does not set it, exactly as
        // `RequestsLoaded.triageFailure` is — a failure banner from a previous
        // action never lingers on a later, unrelated state change.
        actionFailure: actionFailure,
        isReporting: isReporting ?? this.isReporting,
        reportFailure: reportFailure,
        notice: notice,
      );
}

class DowntimeUnavailable extends DowntimeState {
  const DowntimeUnavailable({required this.message});
  final String message;
}

class DowntimeBloc extends Bloc<DowntimeEventBase, DowntimeState> {
  DowntimeBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const DowntimeLoading()) {
    on<DowntimeStarted>(_onStarted);
    on<DowntimeSiteSelected>(_onSiteSelected);
    on<DowntimeCloseConfirmed>(_onCloseConfirmed);
    on<DowntimeClassifyConfirmed>(_onClassifyConfirmed);
    on<BreakdownReportConfirmed>(_onReportConfirmed);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is nothing to show.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, so a retry re-opens on it rather than jumping back to the first.
  String? _lastSiteId;

  Future<void> _onStarted(DowntimeStarted event, Emitter<DowntimeState> emit) async {
    emit(const DowntimeLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const DowntimeUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(DowntimeUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const DowntimeUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(DowntimeLoaded(sites: sites, siteId: opensOn, isLoadingEvents: true));
    await _readList(opensOn, emit);
  }

  Future<void> _onSiteSelected(DowntimeSiteSelected event, Emitter<DowntimeState> emit) async {
    final current = state;
    if (current is! DowntimeLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, events: const [], isLoadingEvents: true));
    await _readList(event.siteId, emit);
  }

  Future<void> _readList(String siteId, Emitter<DowntimeState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const DowntimeUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final events = await _maintenance.fetchDowntimeEvents(token, siteId: siteId);
      final settled = state;
      // A late response for a Site the caller has since left is discarded —
      // the same staleness guard `RequestsBloc._readQueue` follows.
      if (settled is! DowntimeLoaded || settled.siteId != siteId) return;
      emit(settled.copyWith(events: events, isLoadingEvents: false, notice: notice));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! DowntimeLoaded || settled.siteId != siteId) return;
      emit(DowntimeUnavailable(message: error.message));
    }
  }

  Future<void> _onCloseConfirmed(
    DowntimeCloseConfirmed event,
    Emitter<DowntimeState> emit,
  ) async {
    final current = state;
    if (current is! DowntimeLoaded || current.isActing) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(actionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isActing: true));
    try {
      final updated = await _maintenance.closeDowntimeEvent(
        token,
        event.downtimeEventId,
        endedAt: event.endedAt,
      );
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(
        settled.copyWith(
          isActing: false,
          events: _withEvent(settled, updated),
          notice: 'The stop for ${updated.assetName} has been closed.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(settled.copyWith(isActing: false, actionFailure: error.message));
    }
  }

  Future<void> _onClassifyConfirmed(
    DowntimeClassifyConfirmed event,
    Emitter<DowntimeState> emit,
  ) async {
    final current = state;
    if (current is! DowntimeLoaded || current.isActing) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(actionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isActing: true));
    try {
      final updated = await _maintenance.classifyDowntimeEvent(
        token,
        event.downtimeEventId,
        downtimeReasonId: event.downtimeReasonId,
        description: event.description,
      );
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(
        settled.copyWith(
          isActing: false,
          events: _withEvent(settled, updated),
          notice: updated.downtimeReasonName == null
              ? 'The stop for ${updated.assetName} has been classified.'
              : 'The stop for ${updated.assetName} has been classified as '
                  '${updated.downtimeReasonName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(settled.copyWith(isActing: false, actionFailure: error.message));
    }
  }

  Future<void> _onReportConfirmed(
    BreakdownReportConfirmed event,
    Emitter<DowntimeState> emit,
  ) async {
    final current = state;
    if (current is! DowntimeLoaded || current.isReporting) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(reportFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isReporting: true));
    try {
      final reported = await _maintenance.reportBreakdown(
        token,
        assetId: event.assetId,
        startedAt: event.startedAt,
        description: event.description,
      );
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(
        settled.copyWith(
          isReporting: false,
          // The response does not say which Site the new stop landed in, so
          // whether it belongs on Screen is decided from the Site the Asset
          // was chosen from, carried on the event.
          events: event.siteId == settled.siteId
              ? [reported, ...settled.events]
              : settled.events,
          notice: 'A Breakdown has been reported for ${reported.assetName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! DowntimeLoaded) return;
      emit(settled.copyWith(isReporting: false, reportFailure: error.message));
    }
  }

  /// The list with one stop replaced by the server's own updated copy — the
  /// row a close or classify touched stays visible while it settles, rather
  /// than being spliced away, because a closed-but-unclassified stop still
  /// needs classifying.
  static List<DowntimeEvent> _withEvent(DowntimeLoaded state, DowntimeEvent updated) => [
        for (final event in state.events)
          if (event.id == updated.id) updated else event,
      ];
}
