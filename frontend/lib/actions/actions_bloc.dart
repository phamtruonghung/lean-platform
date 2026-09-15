/// The Actions register's state: which Site is being looked at, which filters
/// are on, what the log holds, and an Action being raised.
///
/// Route-scoped, like `AssetsBloc` and `WorkOrdersBloc`: one Screen's reading
/// of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose. The log is Actions'; the list of Sites to
/// choose between is People's, and there is no Actions endpoint that answers
/// it — ADR-0006's rule is that a Module asks the owning Module rather than
/// growing its own copy of Sites.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'action.dart';
import 'actions_api.dart';

sealed class ActionsEvent {
  const ActionsEvent();
}

/// Load the Sites, then the Site's log. Also the retry a failed load offers,
/// so a retry re-does whichever half failed — and re-opens on the Site and the
/// filters the caller had settled on, never silently back to the first one.
class ActionsStarted extends ActionsEvent {
  const ActionsStarted();
}

/// Re-read the log for the Site already on screen.
///
/// Sent by the register when it is entered *again* — the Module's own
/// `ShellRoute` creates this Bloc once and keeps it alive while the caller
/// reads an Action and comes back, so without this the list they return to is
/// the list they left: rows raised, measures closed and counts moved elsewhere
/// are all missing (issue #183). The first load is `ActionsStarted`; this is
/// every visit after it.
class ActionsRefreshed extends ActionsEvent {
  const ActionsRefreshed();
}

/// Look at a different Site's log.
class ActionsSiteSelected extends ActionsEvent {
  const ActionsSiteSelected(this.siteId);
  final String siteId;
}

/// Narrow the register to one Org Unit and everything beneath it (the tier
/// board's own filter shape), or clear back to the whole Site.
class ActionsOrgUnitFilterSelected extends ActionsEvent {
  const ActionsOrgUnitFilterSelected({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

class ActionsOrgUnitFilterCleared extends ActionsEvent {
  const ActionsOrgUnitFilterCleared();
}

/// Narrow the register to what has been handed up to one Org Unit (issue
/// #180) — the plant manager's own queue. A read filter over an already-visible
/// register, so it narrows by responsibility and never by entitlement.
class ActionsEscalatedToFilterSelected extends ActionsEvent {
  const ActionsEscalatedToFilterSelected({
    required this.orgUnitId,
    required this.orgUnitName,
  });
  final String orgUnitId;
  final String orgUnitName;
}

class ActionsEscalatedToFilterCleared extends ActionsEvent {
  const ActionsEscalatedToFilterCleared();
}

class ActionsStatusFilterChanged extends ActionsEvent {
  const ActionsStatusFilterChanged(this.status);
  final String? status;
}

class ActionsTypeFilterChanged extends ActionsEvent {
  const ActionsTypeFilterChanged(this.actionType);
  final String? actionType;
}

/// Include the closed Actions as well as the open ones. Re-reads rather than
/// filtering client-side, since a closed Action is not sent unless asked for.
class ActionsHistoryToggled extends ActionsEvent {
  const ActionsHistoryToggled(this.includeHistory);
  final bool includeHistory;
}

/// Every filter back to "the whole Site's open Actions".
class ActionsFiltersCleared extends ActionsEvent {
  const ActionsFiltersCleared();
}

/// The raise form has decided: this is a whole Action, with the Org Unit
/// already chosen. Same contract the Asset and Work order forms follow — the
/// dialog decides, the Bloc only ever sees a decision already made.
class ActionRaiseConfirmed extends ActionsEvent {
  const ActionRaiseConfirmed({
    required this.orgUnitId,
    required this.title,
    this.description,
    this.actionType,
    this.pillarCode,
    this.ownerEmployeeId,
    this.dueDate,
    this.priority,
  });

  final String orgUnitId;
  final String title;
  final String? description;
  final String? actionType;
  final String? pillarCode;
  final String? ownerEmployeeId;
  final String? dueDate;
  final int? priority;
}

sealed class ActionsState {
  const ActionsState();
}

/// The first load, before even the Site list is known.
class ActionsLoading extends ActionsState {
  const ActionsLoading();
}

class ActionsLoaded extends ActionsState {
  const ActionsLoaded({
    required this.sites,
    required this.siteId,
    this.actions = const [],
    this.truncated = false,
    this.isLoadingActions = false,
    this.isRaising = false,
    this.raiseFailure,
    this.orgUnitFilterId,
    this.orgUnitFilterName,
    this.escalatedToOrgUnitFilterId,
    this.escalatedToOrgUnitFilterName,
    this.statusFilter,
    this.typeFilter,
    this.includeHistory = false,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<Action> actions;

  /// Whether the server had more than it was willing to send. Rendered, never
  /// swallowed: a capped list must not read as a whole Site.
  final bool truncated;

  /// A Site switch or a filter change re-reads the log while the header stays
  /// on screen — the placeholders belong to the list, not to the Screen.
  final bool isLoadingActions;

  /// A raise is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isRaising;

  /// Why the last raise did not land. Reported by the open dialog, which stays
  /// open so the caller can fix it rather than retyping the Action.
  final String? raiseFailure;

  final String? orgUnitFilterId;
  final String? orgUnitFilterName;

  /// What has been handed up to one Org Unit, or null for the whole Site.
  final String? escalatedToOrgUnitFilterId;
  final String? escalatedToOrgUnitFilterName;
  final String? statusFilter;
  final String? typeFilter;
  final bool includeHistory;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [ActionsUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  /// Whether anything is narrowing the list — which decides which of the two
  /// empty stories the Screen tells (issue #103): a Site with no concerns at
  /// all is not the same as a filter that matched none of them.
  bool get isFiltered =>
      orgUnitFilterId != null ||
      escalatedToOrgUnitFilterId != null ||
      statusFilter != null ||
      typeFilter != null;

  ActionsLoaded copyWith({
    List<Action>? actions,
    String? siteId,
    bool? truncated,
    bool? isLoadingActions,
    bool? isRaising,
    String? raiseFailure,
    String? orgUnitFilterId,
    String? orgUnitFilterName,
    bool clearOrgUnitFilter = false,
    String? escalatedToOrgUnitFilterId,
    String? escalatedToOrgUnitFilterName,
    bool clearEscalatedToFilter = false,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? typeFilter,
    bool clearTypeFilter = false,
    bool? includeHistory,
    String? notice,
  }) =>
      ActionsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        actions: actions ?? this.actions,
        truncated: truncated ?? this.truncated,
        isLoadingActions: isLoadingActions ?? this.isLoadingActions,
        isRaising: isRaising ?? this.isRaising,
        raiseFailure: raiseFailure,
        orgUnitFilterId: clearOrgUnitFilter ? null : (orgUnitFilterId ?? this.orgUnitFilterId),
        orgUnitFilterName: clearOrgUnitFilter ? null : (orgUnitFilterName ?? this.orgUnitFilterName),
        escalatedToOrgUnitFilterId: clearEscalatedToFilter
            ? null
            : (escalatedToOrgUnitFilterId ?? this.escalatedToOrgUnitFilterId),
        escalatedToOrgUnitFilterName: clearEscalatedToFilter
            ? null
            : (escalatedToOrgUnitFilterName ?? this.escalatedToOrgUnitFilterName),
        // `clearX` flags rather than `copyWith(statusFilter: null)`, exactly as
        // the Org Unit filter already does: every re-read emits another
        // `copyWith`, and a plain `?? this.x` with a null default would clear a
        // filter the caller set one event earlier. (It did: the register said
        // "nothing has ever been raised" with a status filter applied.)
        statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
        typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
        includeHistory: includeHistory ?? this.includeHistory,
        notice: notice,
      );
}

class ActionsUnavailable extends ActionsState {
  const ActionsUnavailable({required this.message});
  final String message;
}

class ActionsBloc extends Bloc<ActionsEvent, ActionsState> {
  ActionsBloc({
    required ActionsApi actionsApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _actions = actionsApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const ActionsLoading()) {
    on<ActionsStarted>(_onStarted);
    on<ActionsRefreshed>(_onRefreshed);
    on<ActionsSiteSelected>(_onSiteSelected);
    on<ActionsOrgUnitFilterSelected>(_onOrgUnitFilterSelected);
    on<ActionsOrgUnitFilterCleared>(_onOrgUnitFilterCleared);
    on<ActionsEscalatedToFilterSelected>(_onEscalatedToFilterSelected);
    on<ActionsEscalatedToFilterCleared>(_onEscalatedToFilterCleared);
    on<ActionsStatusFilterChanged>(_onStatusFilterChanged);
    on<ActionsTypeFilterChanged>(_onTypeFilterChanged);
    on<ActionsHistoryToggled>(_onHistoryToggled);
    on<ActionsFiltersCleared>(_onFiltersCleared);
    on<ActionRaiseConfirmed>(_onRaiseConfirmed);
  }

  final ActionsApi _actions;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage =
      'There are no Sites you can see, so there is no action log to show.';

  /// What a second raise reports, rather than dropping silently, when one is
  /// already in flight — the same guard `AssetsBloc` keeps for its own writes.
  static const String inFlightMessage = 'Another action is already in progress. Try again in a moment.';

  /// The last Site, the last filter set and the last history setting the caller
  /// actually settled on. `ActionsStarted` is also what "Try again" on
  /// [ActionsUnavailable] dispatches, and that retry must re-open where they
  /// were looking rather than silently resetting to the first Site with no
  /// filters.
  String? _lastSiteId;
  String? _lastOrgUnitFilterId;
  String? _lastOrgUnitFilterName;
  String? _lastEscalatedToFilterId;
  String? _lastEscalatedToFilterName;
  String? _lastStatusFilter;
  String? _lastTypeFilter;
  bool _lastIncludeHistory = false;

  Future<void> _onStarted(ActionsStarted event, Emitter<ActionsState> emit) async {
    emit(const ActionsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ActionsUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(ActionsUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const ActionsUnavailable(message: noSitesMessage));
      return;
    }
    // A remembered Site the caller can no longer see must not strand them on an
    // empty pane — the same `sites.any` guard `AssetsBloc._onStarted` uses.
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(
      ActionsLoaded(
        sites: sites,
        siteId: opensOn,
        isLoadingActions: true,
        orgUnitFilterId: _lastOrgUnitFilterId,
        escalatedToOrgUnitFilterId: _lastEscalatedToFilterId,
        escalatedToOrgUnitFilterName: _lastEscalatedToFilterName,
        orgUnitFilterName: _lastOrgUnitFilterName,
        statusFilter: _lastStatusFilter,
        typeFilter: _lastTypeFilter,
        includeHistory: _lastIncludeHistory,
      ),
    );
    await _readLog(opensOn, emit);
  }

  /// The refresh a returning caller gets: same Site, same filters, same
  /// history switch, a fresh read. A no-op while the first load is still in
  /// flight, so a Screen that mounts mid-load does not ask twice.
  Future<void> _onRefreshed(ActionsRefreshed event, Emitter<ActionsState> emit) async {
    final current = state;
    if (current is! ActionsLoaded || current.isLoadingActions) return;
    emit(current.copyWith(isLoadingActions: true));
    await _readLog(current.siteId, emit);
  }

  Future<void> _onSiteSelected(ActionsSiteSelected event, Emitter<ActionsState> emit) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastSiteId = event.siteId;
    // A filter naming an Org Unit belongs to the Site it was chosen in, so it
    // goes with it — the same rule the Asset form applies to its own chooser.
    _lastOrgUnitFilterId = null;
    _lastOrgUnitFilterName = null;
    // The same rule for what was handed up: an Org Unit filter chosen in one
    // Site means nothing in the next one.
    _lastEscalatedToFilterId = null;
    _lastEscalatedToFilterName = null;
    emit(
      current.copyWith(
        siteId: event.siteId,
        clearOrgUnitFilter: true,
        clearEscalatedToFilter: true,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(event.siteId, emit);
  }

  Future<void> _onOrgUnitFilterSelected(
    ActionsOrgUnitFilterSelected event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastOrgUnitFilterId = event.orgUnitId;
    _lastOrgUnitFilterName = event.orgUnitName;
    emit(
      current.copyWith(
        orgUnitFilterId: event.orgUnitId,
        orgUnitFilterName: event.orgUnitName,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  Future<void> _onOrgUnitFilterCleared(
    ActionsOrgUnitFilterCleared event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastOrgUnitFilterId = null;
    _lastOrgUnitFilterName = null;
    emit(current.copyWith(clearOrgUnitFilter: true, actions: const [], isLoadingActions: true));
    await _readLog(current.siteId, emit);
  }

  Future<void> _onEscalatedToFilterSelected(
    ActionsEscalatedToFilterSelected event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastEscalatedToFilterId = event.orgUnitId;
    _lastEscalatedToFilterName = event.orgUnitName;
    emit(
      current.copyWith(
        escalatedToOrgUnitFilterId: event.orgUnitId,
        escalatedToOrgUnitFilterName: event.orgUnitName,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  Future<void> _onEscalatedToFilterCleared(
    ActionsEscalatedToFilterCleared event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastEscalatedToFilterId = null;
    _lastEscalatedToFilterName = null;
    emit(
      current.copyWith(
        clearEscalatedToFilter: true,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  Future<void> _onStatusFilterChanged(
    ActionsStatusFilterChanged event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastStatusFilter = event.status;
    emit(
      current.copyWith(
        statusFilter: event.status,
        clearStatusFilter: event.status == null,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  Future<void> _onTypeFilterChanged(
    ActionsTypeFilterChanged event,
    Emitter<ActionsState> emit,
  ) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastTypeFilter = event.actionType;
    emit(
      current.copyWith(
        typeFilter: event.actionType,
        clearTypeFilter: event.actionType == null,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  Future<void> _onHistoryToggled(ActionsHistoryToggled event, Emitter<ActionsState> emit) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastIncludeHistory = event.includeHistory;
    emit(current.copyWith(includeHistory: event.includeHistory, actions: const [], isLoadingActions: true));
    await _readLog(current.siteId, emit);
  }

  Future<void> _onFiltersCleared(ActionsFiltersCleared event, Emitter<ActionsState> emit) async {
    final current = state;
    if (current is! ActionsLoaded) return;
    _lastOrgUnitFilterId = null;
    _lastOrgUnitFilterName = null;
    _lastEscalatedToFilterId = null;
    _lastEscalatedToFilterName = null;
    _lastStatusFilter = null;
    _lastTypeFilter = null;
    emit(
      current.copyWith(
        clearOrgUnitFilter: true,
        clearEscalatedToFilter: true,
        clearStatusFilter: true,
        clearTypeFilter: true,
        actions: const [],
        isLoadingActions: true,
      ),
    );
    await _readLog(current.siteId, emit);
  }

  /// Reads the log for the Site on the state, after a filter change, and keeps
  /// the read honest about which filters produced it: a response that arrives
  /// after the caller has moved on (a different Site, a different filter) is
  /// dropped rather than painted over the newer one.
  Future<void> _readLog(String? siteId, Emitter<ActionsState> emit) async {
    if (siteId == null) return;
    final current = state;
    if (current is! ActionsLoaded) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ActionsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final register = await _actions.fetchActions(
        token,
        siteId: siteId,
        orgUnitId: current.orgUnitFilterId,
        escalatedToOrgUnitId: current.escalatedToOrgUnitFilterId,
        status: current.statusFilter,
        actionType: current.typeFilter,
        includeHistory: current.includeHistory,
      );
      if (state is! ActionsLoaded) return;
      final latest = state as ActionsLoaded;
      if (latest.siteId != siteId) return;
      emit(
        latest.copyWith(
          actions: register.actions,
          truncated: register.truncated,
          isLoadingActions: false,
        ),
      );
    } on ActionsApiException catch (error) {
      if (state is! ActionsLoaded) return;
      emit(ActionsUnavailable(message: error.message));
    }
  }

  Future<void> _onRaiseConfirmed(ActionRaiseConfirmed event, Emitter<ActionsState> emit) async {
    final current = state;
    if (current is! ActionsLoaded || current.isRaising) {
      if (current is ActionsLoaded) emit(current.copyWith(notice: inFlightMessage));
      return;
    }

    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(raiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaising: true));
    try {
      final action = await _actions.raiseAction(
        token,
        siteId: siteId,
        orgUnitId: event.orgUnitId,
        title: event.title,
        description: event.description,
        actionType: event.actionType,
        pillarCode: event.pillarCode,
        ownerEmployeeId: event.ownerEmployeeId,
        dueDate: event.dueDate,
        priority: event.priority,
      );
      final settled = state;
      if (settled is! ActionsLoaded) return;
      // The response already says what the row became, so the log is updated in
      // place — the same reasoning the Asset register and the Approval queue
      // follow. An Action raised in a Site that is not on screen simply does
      // not appear, which is honest: the caller is looking elsewhere.
      emit(
        settled.copyWith(
          isRaising: false,
          actions: action.siteId == settled.siteId
              ? _inRegisterOrder([...settled.actions, action])
              : settled.actions,
          notice: '${action.actionNo} is on the log, at ${action.orgUnitName}.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionsLoaded) return;
      emit(settled.copyWith(isRaising: false, raiseFailure: error.message));
    }
  }

  /// The register in the order the server sends it — overdue first, then due
  /// date, then priority, then most recently raised (actions.js). The client's
  /// order has to agree with the server's, or a row just raised lands at the
  /// bottom of the list and jumps the moment the next read arrives.
  List<Action> _inRegisterOrder(List<Action> actions) => [...actions]..sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
        final byDue = (a.dueDate ?? '9999-99-99').compareTo(b.dueDate ?? '9999-99-99');
        if (byDue != 0) return byDue;
        final byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) return byPriority;
        final aRaised = a.raisedAt?.toUtc().toIso8601String() ?? '';
        final bRaised = b.raisedAt?.toUtc().toIso8601String() ?? '';
        return bRaised.compareTo(aRaised);
      });
}
