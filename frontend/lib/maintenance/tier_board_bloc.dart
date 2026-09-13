/// The tier board's state: which Site is being looked at, which Org Unit the
/// rollup is narrowed to, which period it covers, and the board itself
/// (issue #76).
///
/// Route-scoped, like `WorkOrdersBloc` and `DowntimeBloc`: one Screen's reading
/// of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs for the same reason every other Maintenance Bloc does: the
/// board is Maintenance's (`MaintenanceApi`), the Sites to choose between are
/// People's (`PeopleApi`), and ADR-0006 keeps a Module asking the owning Module
/// rather than growing its own copy.
///
/// Every control change is its own event, so each one dispatches exactly one
/// board read. Nothing here responds to a rebuild: the Screen dispatches from
/// user callbacks only, and each handler issues one request.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'tier_board.dart';

sealed class TierBoardEvent {
  const TierBoardEvent();
}

/// Load the Sites, then the board at the first of them. Also the retry a failed
/// load offers, so a retry re-does whichever half failed.
class TierBoardStarted extends TierBoardEvent {
  const TierBoardStarted();
}

/// Look at a different Site's board. An Org Unit filter belongs to the Site it
/// was chosen in, so switching Site drops it.
class TierBoardSiteSelected extends TierBoardEvent {
  const TierBoardSiteSelected(this.siteId);
  final String siteId;
}

/// Narrow the rollup to one Org Unit and everything beneath it.
class TierBoardOrgUnitFilterSelected extends TierBoardEvent {
  const TierBoardOrgUnitFilterSelected({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

/// Back to the whole Site.
class TierBoardOrgUnitFilterCleared extends TierBoardEvent {
  const TierBoardOrgUnitFilterCleared();
}

/// Cover a different period type — `shift`, `day`, `week` or `month`.
class TierBoardPeriodTypeSelected extends TierBoardEvent {
  const TierBoardPeriodTypeSelected(this.periodType);

  /// The wire string, one of [BoardPeriodType]'s own `wire` values.
  final String periodType;
}

/// Cover the period containing a different production day, or null to let the
/// Site's own shift calendar decide.
class TierBoardDateChanged extends TierBoardEvent {
  const TierBoardDateChanged(this.date);
  final String? date;
}

sealed class TierBoardState {
  const TierBoardState();
}

/// The first load, before even the Site list is known.
class TierBoardLoading extends TierBoardState {
  const TierBoardLoading();
}

class TierBoardLoaded extends TierBoardState {
  const TierBoardLoaded({
    required this.sites,
    required this.siteId,
    this.board,
    this.isLoadingBoard = false,
    this.orgUnitFilterId,
    this.orgUnitFilterName,
    this.periodType = BoardDefault.periodType,
    this.date,
  });

  final List<Site> sites;
  final String? siteId;

  /// The most recently read board, or null while the first read is in flight.
  final TierBoard? board;

  /// A Site, Org Unit, period or date change re-reads the board while the
  /// controls stay put — the placeholder belongs to the board, not the header.
  final bool isLoadingBoard;

  /// The Org Unit the rollup is narrowed to, and everything beneath it — null
  /// for the whole Site.
  final String? orgUnitFilterId;
  final String? orgUnitFilterName;

  /// The wire period type currently chosen, one of [BoardPeriodType]'s own
  /// `wire` values.
  final String periodType;

  /// `YYYY-MM-DD`, the production day the period is resolved around, or null
  /// to let the Site's own calendar decide.
  final String? date;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  TierBoardLoaded copyWith({
    TierBoard? board,
    String? siteId,
    bool? isLoadingBoard,
    String? orgUnitFilterId,
    String? orgUnitFilterName,
    bool clearOrgUnitFilter = false,
    String? periodType,
    String? date,
    bool clearDate = false,
  }) =>
      TierBoardLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        board: board ?? this.board,
        isLoadingBoard: isLoadingBoard ?? this.isLoadingBoard,
        orgUnitFilterId: clearOrgUnitFilter ? null : (orgUnitFilterId ?? this.orgUnitFilterId),
        orgUnitFilterName:
            clearOrgUnitFilter ? null : (orgUnitFilterName ?? this.orgUnitFilterName),
        periodType: periodType ?? this.periodType,
        date: clearDate ? null : (date ?? this.date),
      );
}

class TierBoardUnavailable extends TierBoardState {
  const TierBoardUnavailable({required this.message});
  final String message;
}

/// The one place the default period type is named, so the Bloc and any future
/// caller cannot disagree about what a board opens on.
abstract final class BoardDefault {
  static const String periodType = 'day';
}

class TierBoardBloc extends Bloc<TierBoardEvent, TierBoardState> {
  TierBoardBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const TierBoardLoading()) {
    on<TierBoardStarted>(_onStarted);
    on<TierBoardSiteSelected>(_onSiteSelected);
    on<TierBoardOrgUnitFilterSelected>(_onOrgUnitFilterSelected);
    on<TierBoardOrgUnitFilterCleared>(_onOrgUnitFilterCleared);
    on<TierBoardPeriodTypeSelected>(_onPeriodTypeSelected);
    on<TierBoardDateChanged>(_onDateChanged);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is no board to show.';

  /// The last Site the caller settled on, so a retry reopens on it rather than
  /// jumping back to the first — the same guard `WorkOrdersBloc._lastSiteId`
  /// keeps.
  String? _lastSiteId;

  Future<void> _onStarted(TierBoardStarted event, Emitter<TierBoardState> emit) async {
    emit(const TierBoardLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const TierBoardUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(TierBoardUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const TierBoardUnavailable(message: noSitesMessage));
      return;
    }
    // A remembered Site the caller can no longer see must not strand them.
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(TierBoardLoaded(sites: sites, siteId: opensOn, isLoadingBoard: true));
    await _readBoard(emit);
  }

  Future<void> _onSiteSelected(TierBoardSiteSelected event, Emitter<TierBoardState> emit) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    _lastSiteId = event.siteId;
    // An Org Unit filter is scoped to the Site it was chosen in, so switching
    // Site drops it — the same reasoning `WorkOrdersBloc._onSiteSelected` uses.
    emit(
      current.copyWith(
        siteId: event.siteId,
        clearOrgUnitFilter: true,
        isLoadingBoard: true,
      ),
    );
    await _readBoard(emit);
  }

  Future<void> _onOrgUnitFilterSelected(
    TierBoardOrgUnitFilterSelected event,
    Emitter<TierBoardState> emit,
  ) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    emit(
      current.copyWith(
        orgUnitFilterId: event.orgUnitId,
        orgUnitFilterName: event.orgUnitName,
        isLoadingBoard: true,
      ),
    );
    await _readBoard(emit);
  }

  Future<void> _onOrgUnitFilterCleared(
    TierBoardOrgUnitFilterCleared event,
    Emitter<TierBoardState> emit,
  ) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    emit(current.copyWith(clearOrgUnitFilter: true, isLoadingBoard: true));
    await _readBoard(emit);
  }

  Future<void> _onPeriodTypeSelected(
    TierBoardPeriodTypeSelected event,
    Emitter<TierBoardState> emit,
  ) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    emit(current.copyWith(periodType: event.periodType, isLoadingBoard: true));
    await _readBoard(emit);
  }

  Future<void> _onDateChanged(TierBoardDateChanged event, Emitter<TierBoardState> emit) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    emit(
      event.date == null
          ? current.copyWith(clearDate: true, isLoadingBoard: true)
          : current.copyWith(date: event.date, isLoadingBoard: true),
    );
    await _readBoard(emit);
  }

  Future<void> _readBoard(Emitter<TierBoardState> emit) async {
    final current = state;
    if (current is! TierBoardLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const TierBoardUnavailable(message: signedOutMessage));
      return;
    }
    final siteId = current.siteId;
    if (siteId == null) return;
    // Bloc processes events concurrently by default, so a narrower and a broader
    // read can be in flight together and land out of order. Carrying what this
    // request was actually made with — Site, Org Unit, period and date — lets a
    // late response for a view the caller has since left be discarded.
    final requestedOrgUnitId = current.orgUnitFilterId;
    final requestedPeriodType = current.periodType;
    final requestedDate = current.date;
    try {
      final board = await _maintenance.fetchBoard(
        token,
        siteId: siteId,
        periodType: requestedPeriodType,
        orgUnitId: requestedOrgUnitId,
        date: requestedDate,
      );
      final settled = state;
      if (settled is! TierBoardLoaded ||
          settled.siteId != siteId ||
          settled.orgUnitFilterId != requestedOrgUnitId ||
          settled.periodType != requestedPeriodType ||
          settled.date != requestedDate) {
        return;
      }
      emit(settled.copyWith(board: board, isLoadingBoard: false));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! TierBoardLoaded ||
          settled.siteId != siteId ||
          settled.orgUnitFilterId != requestedOrgUnitId ||
          settled.periodType != requestedPeriodType ||
          settled.date != requestedDate) {
        return;
      }
      // The board read carries no Grant filter (ADR-0009), so a refusal here
      // is an ordinary failure rather than a scope problem.
      emit(TierBoardUnavailable(message: error.message));
    }
  }
}
