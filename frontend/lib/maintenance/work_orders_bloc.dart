/// The Work order list's state: which Site — and optionally which Org Unit
/// within it — is being looked at, and what open Work orders sit there.
///
/// Route-scoped, like `AssetsBloc` and unlike `AccountBloc`: one Screen's
/// reading of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose, the same reason `AssetsBloc` does: the list
/// itself is Maintenance's (`MaintenanceApi`), the Sites to choose between are
/// People's, and there is no Maintenance endpoint that answers that — ADR-0006
/// keeps a Module asking the owning Module rather than growing its own copy.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'work_order.dart';

sealed class WorkOrdersEvent {
  const WorkOrdersEvent();
}

/// Load the Sites, then the open Work orders at the first of them. Also the
/// retry a failed load offers, so a retry re-does whichever half failed.
class WorkOrdersStarted extends WorkOrdersEvent {
  const WorkOrdersStarted();
}

/// Look at a different Site's list.
class WorkOrdersSiteSelected extends WorkOrdersEvent {
  const WorkOrdersSiteSelected(this.siteId);
  final String siteId;
}

/// Narrow the list to one Org Unit and everything beneath it.
class WorkOrdersOrgUnitFilterSelected extends WorkOrdersEvent {
  const WorkOrdersOrgUnitFilterSelected({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

/// Back to the whole Site.
class WorkOrdersOrgUnitFilterCleared extends WorkOrdersEvent {
  const WorkOrdersOrgUnitFilterCleared();
}

/// The dialog has decided: this is a whole Work order, with the Asset already
/// chosen. Same contract as `AssetAddConfirmed` — the dialog decides, the Bloc
/// only ever sees a decision already made.
///
/// [siteId] is the Site the chosen Asset was fetched from — carried because,
/// unlike `createAsset`'s response, the created Work order's own response
/// does not say which Site it landed in, so this is the only way the Bloc can
/// decide whether the new row belongs on this screen without a second read.
class WorkOrderRaiseConfirmed extends WorkOrdersEvent {
  const WorkOrderRaiseConfirmed({
    required this.siteId,
    required this.assetId,
    required this.summary,
    required this.workType,
    required this.priority,
    this.description,
  });

  final String siteId;
  final String assetId;
  final String summary;
  final String workType;
  final int priority;
  final String? description;
}

/// The dialog has decided: this Work order goes to this Employee. Reassigning
/// is the same event with a different [employeeId] — the server treats it as
/// one idempotent replacement (AC5), and so does this.
class WorkOrderAssignConfirmed extends WorkOrdersEvent {
  const WorkOrderAssignConfirmed({required this.workOrderId, required this.employeeId});
  final String workOrderId;
  final String employeeId;
}

/// Starts a Work order — moves it to `in_progress` and stamps when work
/// began (issue #63). No dialog: starting asks for nothing, the same as
/// `AssetActiveToggled`'s reinstate half.
class WorkOrderStartConfirmed extends WorkOrdersEvent {
  const WorkOrderStartConfirmed(this.workOrderId);
  final String workOrderId;
}

/// The complete dialog has decided: this Work order is done, and [note] says
/// what was found.
class WorkOrderCompleteConfirmed extends WorkOrdersEvent {
  const WorkOrderCompleteConfirmed({required this.workOrderId, required this.note});
  final String workOrderId;
  final String note;
}

/// The cancel dialog has decided: this Work order, raised in error, is
/// cancelled. [reason] is optional.
class WorkOrderCancelConfirmed extends WorkOrdersEvent {
  const WorkOrderCancelConfirmed({required this.workOrderId, this.reason});
  final String workOrderId;
  final String? reason;
}

/// Toggle whether the list includes completed and cancelled Work orders
/// alongside the open ones (issue #63) — re-read with `includeHistory`
/// rather than filtering client-side, the same shape
/// `AssetsShowRetiredChanged` follows for retired Assets.
class WorkOrdersShowHistoryChanged extends WorkOrdersEvent {
  const WorkOrdersShowHistoryChanged(this.showHistory);
  final bool showHistory;
}

sealed class WorkOrdersState {
  const WorkOrdersState();
}

/// The first load, before even the Site list is known.
class WorkOrdersLoading extends WorkOrdersState {
  const WorkOrdersLoading();
}

class WorkOrdersLoaded extends WorkOrdersState {
  const WorkOrdersLoaded({
    required this.sites,
    required this.siteId,
    this.workOrders = const [],
    this.isLoadingWorkOrders = false,
    this.orgUnitFilterId,
    this.orgUnitFilterName,
    this.isRaising = false,
    this.raiseFailure,
    this.isAssigning = false,
    this.assignFailure,
    this.isTransitioning = false,
    this.transitionFailure,
    this.showHistory = false,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<WorkOrder> workOrders;

  /// A Site switch or a filter change re-reads the list while the rest of the
  /// Screen stays put — the placeholders belong to the list, not the whole
  /// Screen.
  final bool isLoadingWorkOrders;

  /// The Org Unit the list is narrowed to, and everything beneath it — null
  /// for the whole Site.
  final String? orgUnitFilterId;
  final String? orgUnitFilterName;

  /// A raise is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isRaising;

  /// Why the last raise did not land. Reported by the open dialog, which
  /// stays open so the caller can fix the field rather than retype the whole
  /// form.
  final String? raiseFailure;

  /// An assign is in flight. Kept on the state, not only in the dialog, so
  /// the Screen can refuse to open a second one while this one is settling.
  final bool isAssigning;

  /// Why the last assign did not land. Reported by the open dialog, which
  /// stays open so the caller can pick somebody else — the same reasoning
  /// [raiseFailure] follows.
  final String? assignFailure;

  /// A start, complete or cancel is in flight (issue #63) — one flag for all
  /// three, mirroring [isAssigning]: the Screen only needs "an action is in
  /// flight" to disable every row's actions while it settles, not which of
  /// the three it was.
  final bool isTransitioning;

  /// Why the last transition did not land. Read by whichever dialog is open
  /// (complete, cancel) so it can stay open and let the caller retry — the
  /// same reasoning [assignFailure] follows. Starting has no dialog to read
  /// it, so a start failure surfaces as [notice] instead.
  final String? transitionFailure;

  /// Whether the list was last (re-)read with `includeHistory` (issue #63) —
  /// mirrors [AssetsLoaded.showRetired].
  final bool showHistory;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [WorkOrdersUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  WorkOrdersLoaded copyWith({
    List<WorkOrder>? workOrders,
    String? siteId,
    bool? isLoadingWorkOrders,
    String? orgUnitFilterId,
    String? orgUnitFilterName,
    bool clearOrgUnitFilter = false,
    bool? isRaising,
    String? raiseFailure,
    bool? isAssigning,
    String? assignFailure,
    bool? isTransitioning,
    String? transitionFailure,
    bool? showHistory,
    String? notice,
  }) =>
      WorkOrdersLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        workOrders: workOrders ?? this.workOrders,
        isLoadingWorkOrders: isLoadingWorkOrders ?? this.isLoadingWorkOrders,
        orgUnitFilterId: clearOrgUnitFilter ? null : (orgUnitFilterId ?? this.orgUnitFilterId),
        orgUnitFilterName:
            clearOrgUnitFilter ? null : (orgUnitFilterName ?? this.orgUnitFilterName),
        isRaising: isRaising ?? this.isRaising,
        // Cleared on every emit that does not set it, exactly as raiseFailure
        // and notice already are — deliberate, not a bug: a fresh emit with
        // nothing to say has nothing left over to say either, so a failure
        // banner from a previous assign never lingers on a later, unrelated
        // state change.
        raiseFailure: raiseFailure,
        isAssigning: isAssigning ?? this.isAssigning,
        assignFailure: assignFailure,
        isTransitioning: isTransitioning ?? this.isTransitioning,
        transitionFailure: transitionFailure,
        showHistory: showHistory ?? this.showHistory,
        notice: notice,
      );
}

class WorkOrdersUnavailable extends WorkOrdersState {
  const WorkOrdersUnavailable({required this.message, this.isScopeRefused = false});
  final String message;

  /// True when the list read was refused for scope rather than failing
  /// outright (issue #103's fifth case, #99 user story 15) — read off
  /// [MaintenanceApiException.statusCode] being `403` in [_readList]'s own
  /// catch block, never by matching [message]'s wording, so this classifies
  /// the same way regardless of what sentence the server chose.
  ///
  /// Today's own list read cannot actually produce one: Maintenance's reads
  /// are Site-wide regardless of Grants (`modules/people/index.js`'s own
  /// header, extending ADR-0009), so `work-order-routes.js`'s `GET
  /// /sites/:siteId/work-orders` never calls `canAct` at all. This field is
  /// not dead code even so — it is the same classification the Org-Unit-
  /// scoped reads #72–#80 add will need, proven here through this Screen's
  /// own pumped test (`work_orders_test.dart`) rather than invented the day
  /// the first real 403 shows up on a list read.
  final bool isScopeRefused;
}

class WorkOrdersBloc extends Bloc<WorkOrdersEvent, WorkOrdersState> {
  WorkOrdersBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const WorkOrdersLoading()) {
    on<WorkOrdersStarted>(_onStarted);
    on<WorkOrdersSiteSelected>(_onSiteSelected);
    on<WorkOrdersOrgUnitFilterSelected>(_onOrgUnitFilterSelected);
    on<WorkOrdersOrgUnitFilterCleared>(_onOrgUnitFilterCleared);
    on<WorkOrderRaiseConfirmed>(_onRaiseConfirmed);
    on<WorkOrderAssignConfirmed>(_onAssignConfirmed);
    on<WorkOrderStartConfirmed>(_onStartConfirmed);
    on<WorkOrderCompleteConfirmed>(_onCompleteConfirmed);
    on<WorkOrderCancelConfirmed>(_onCancelConfirmed);
    on<WorkOrdersShowHistoryChanged>(_onShowHistoryChanged);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is no work to show.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, below. `WorkOrdersStarted` is also what "Try again" on
  /// `WorkOrdersUnavailable` dispatches, and that retry must re-open on the
  /// Site the caller was looking at, not silently jump back to the first one
  /// (the same bug `AssetsBloc._lastSiteId` was fixed for in #56).
  String? _lastSiteId;

  /// The last "Show completed and cancelled" setting the caller chose, kept
  /// for the same reason as [_lastSiteId]: a retry re-reads with the choice
  /// still standing rather than silently resetting to open-only — mirrors
  /// `AssetsBloc._lastShowRetired`.
  bool _lastShowHistory = false;

  Future<void> _onStarted(WorkOrdersStarted event, Emitter<WorkOrdersState> emit) async {
    emit(const WorkOrdersLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const WorkOrdersUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(WorkOrdersUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const WorkOrdersUnavailable(message: noSitesMessage));
      return;
    }
    // A remembered Site the caller can no longer see must not strand them on
    // an empty pane — the same guard `AssetsBloc._onStarted` uses.
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    // A fresh start always opens on the whole Site: an Org Unit filter is
    // scoped to whichever Site it was chosen in, and carrying it across a
    // restart that may land on a different Site would silently narrow to an
    // id that Site knows nothing about.
    emit(
      WorkOrdersLoaded(
        sites: sites,
        siteId: opensOn,
        isLoadingWorkOrders: true,
        showHistory: _lastShowHistory,
      ),
    );
    await _readList(opensOn, emit);
  }

  Future<void> _onSiteSelected(WorkOrdersSiteSelected event, Emitter<WorkOrdersState> emit) async {
    final current = state;
    if (current is! WorkOrdersLoaded) return;
    _lastSiteId = event.siteId;
    // Same reasoning as the fresh-start case above: an Org Unit filter
    // belongs to the Site it was chosen in, so switching Site drops it.
    emit(
      current.copyWith(
        siteId: event.siteId,
        workOrders: const [],
        isLoadingWorkOrders: true,
        clearOrgUnitFilter: true,
      ),
    );
    await _readList(event.siteId, emit);
  }

  Future<void> _onOrgUnitFilterSelected(
    WorkOrdersOrgUnitFilterSelected event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded) return;
    final siteId = current.siteId;
    if (siteId == null) return;
    emit(
      current.copyWith(
        orgUnitFilterId: event.orgUnitId,
        orgUnitFilterName: event.orgUnitName,
        workOrders: const [],
        isLoadingWorkOrders: true,
      ),
    );
    await _readList(siteId, emit);
  }

  Future<void> _onOrgUnitFilterCleared(
    WorkOrdersOrgUnitFilterCleared event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded) return;
    final siteId = current.siteId;
    if (siteId == null) return;
    emit(
      current.copyWith(clearOrgUnitFilter: true, workOrders: const [], isLoadingWorkOrders: true),
    );
    await _readList(siteId, emit);
  }

  Future<void> _readList(String siteId, Emitter<WorkOrdersState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! WorkOrdersLoaded) return;
    // Bloc processes events concurrently by default, so a narrower request
    // (Org Unit filter set) and a broader one (filter cleared) can be in
    // flight together and land out of order. Carrying the filter this
    // request was actually made with — not just the Site — is the same
    // staleness guard below, extended: a late response is discarded when
    // either no longer matches what is currently on screen. `showHistory` is
    // carried the same way (issue #63): a history read and an open read can
    // be in flight together too, for exactly the reason above.
    final requestedOrgUnitId = current.orgUnitFilterId;
    final requestedShowHistory = current.showHistory;
    if (token == null) {
      emit(const WorkOrdersUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final workOrders = await _maintenance.fetchWorkOrders(
        token,
        siteId: siteId,
        orgUnitId: requestedOrgUnitId,
        includeHistory: requestedShowHistory,
      );
      final settled = state;
      if (settled is! WorkOrdersLoaded ||
          settled.siteId != siteId ||
          settled.orgUnitFilterId != requestedOrgUnitId ||
          settled.showHistory != requestedShowHistory) {
        return;
      }
      emit(settled.copyWith(workOrders: workOrders, isLoadingWorkOrders: false, notice: notice));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded ||
          settled.siteId != siteId ||
          settled.orgUnitFilterId != requestedOrgUnitId ||
          settled.showHistory != requestedShowHistory) {
        return;
      }
      emit(WorkOrdersUnavailable(message: error.message, isScopeRefused: error.statusCode == 403));
    }
  }

  Future<void> _onRaiseConfirmed(WorkOrderRaiseConfirmed event, Emitter<WorkOrdersState> emit) async {
    final current = state;
    if (current is! WorkOrdersLoaded || current.isRaising) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(raiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaising: true));
    try {
      final workOrder = await _maintenance.createWorkOrder(
        token,
        assetId: event.assetId,
        summary: event.summary,
        workType: event.workType,
        priority: event.priority,
        description: event.description,
      );
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      // The response does not say which Site the new Work order landed in,
      // unlike `createAsset`'s own response — so whether it belongs on this
      // screen is decided from the Site the Asset was chosen from, carried on
      // the event, and only when nothing has narrowed the view to one Org
      // Unit: a filter cannot be checked against a flat id with no ancestor
      // data on the client, so a filtered view is left to its next read
      // rather than guessed at.
      final belongsOnScreen = event.siteId == settled.siteId && settled.orgUnitFilterId == null;
      emit(
        settled.copyWith(
          isRaising: false,
          // Sorted by (priority, workOrderNo) to match the server's own
          // `ORDER BY wo.priority, wo.work_order_no` (work-orders.js) — the
          // same reasoning `AssetsBloc._onAddConfirmed` follows for its own
          // `(orgUnitName, code)` order: the client's order must agree with
          // the server's, or a freshly-raised priority-1 job would land at
          // the bottom instead of the top, and flip to the top on the next
          // read anyway.
          workOrders: belongsOnScreen
              ? ([...settled.workOrders, workOrder]..sort(_byPriorityThenNumber))
              : settled.workOrders,
          // A filtered-out row is not shown, so the notice must not claim it
          // is — the caller would look for it and not find it.
          notice: belongsOnScreen
              ? '${workOrder.workOrderNo} has been raised.'
              : '${workOrder.workOrderNo} has been raised, but is filtered out of the current view.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(settled.copyWith(isRaising: false, raiseFailure: error.message));
    }
  }

  Future<void> _onAssignConfirmed(
    WorkOrderAssignConfirmed event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded || current.isAssigning) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(assignFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isAssigning: true));
    try {
      final workOrder = await _maintenance.assignWorkOrder(
        token,
        event.workOrderId,
        employeeId: event.employeeId,
      );
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      // Optimistic in-place replacement, no refetch — the response already
      // carries assigneeName, so the row needs no second request. Not
      // re-sorted: assigning does not change priority or workOrderNo, so the
      // server's own order still holds. A row that moved out from under the
      // current Site/filter (no match) is left untouched rather than
      // appended — it may not belong in this view.
      final matches = settled.workOrders.any((existing) => existing.id == event.workOrderId);
      final workOrders = matches
          ? [
              for (final existing in settled.workOrders)
                if (existing.id == event.workOrderId) workOrder else existing,
            ]
          : settled.workOrders;
      emit(
        settled.copyWith(
          isAssigning: false,
          workOrders: workOrders,
          notice: '${workOrder.workOrderNo} is now with ${workOrder.assigneeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(settled.copyWith(isAssigning: false, assignFailure: error.message));
    }
  }

  Future<void> _onStartConfirmed(
    WorkOrderStartConfirmed event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded || current.isTransitioning) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTransitioning: true));
    try {
      final workOrder = await _maintenance.startWorkOrder(token, event.workOrderId);
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(
        settled.copyWith(
          isTransitioning: false,
          workOrders: _applyTransition(settled, workOrder),
          notice: '${workOrder.workOrderNo} is under way.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      // Starting has no dialog of its own to read a failure off, unlike
      // complete/cancel — the row itself is the caller, so the refusal
      // surfaces as the ordinary notice instead of `transitionFailure`.
      emit(settled.copyWith(isTransitioning: false, notice: error.message));
    }
  }

  Future<void> _onCompleteConfirmed(
    WorkOrderCompleteConfirmed event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded || current.isTransitioning) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(transitionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTransitioning: true));
    try {
      final workOrder = await _maintenance.completeWorkOrder(
        token,
        event.workOrderId,
        note: event.note,
      );
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(
        settled.copyWith(
          isTransitioning: false,
          workOrders: _applyTransition(settled, workOrder),
          // Completing takes the row out of the open list unless history is
          // being shown — the notice must say so, or the caller would look
          // for the row and not find it (the same reasoning the raise
          // notice follows for a filtered-out row).
          notice: settled.showHistory
              ? '${workOrder.workOrderNo} is complete.'
              : '${workOrder.workOrderNo} is complete, and has left the open list.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(settled.copyWith(isTransitioning: false, transitionFailure: error.message));
    }
  }

  Future<void> _onCancelConfirmed(
    WorkOrderCancelConfirmed event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded || current.isTransitioning) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(transitionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isTransitioning: true));
    try {
      final workOrder = await _maintenance.cancelWorkOrder(
        token,
        event.workOrderId,
        reason: event.reason,
      );
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(
        settled.copyWith(
          isTransitioning: false,
          workOrders: _applyTransition(settled, workOrder),
          notice: settled.showHistory
              ? '${workOrder.workOrderNo} has been cancelled.'
              : '${workOrder.workOrderNo} has been cancelled, and has left the open list.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrdersLoaded) return;
      emit(settled.copyWith(isTransitioning: false, transitionFailure: error.message));
    }
  }

  Future<void> _onShowHistoryChanged(
    WorkOrdersShowHistoryChanged event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrdersLoaded) return;
    final siteId = current.siteId;
    if (siteId == null) return;
    _lastShowHistory = event.showHistory;
    emit(
      current.copyWith(showHistory: event.showHistory, workOrders: const [], isLoadingWorkOrders: true),
    );
    await _readList(siteId, emit);
  }

  /// The row patched in place with its new state, rather than refetched —
  /// same reasoning [_onAssignConfirmed] follows. Unlike assigning, though,
  /// completing and cancelling can take the row *out* of the open list:
  /// mirrors `AssetsBloc._applyMutation`. A row that is not in the current
  /// list — filtered out by Site/Org Unit already — is left alone by both
  /// branches, which is the staleness guard for a mutation that lands after
  /// the view has moved on.
  List<WorkOrder> _applyTransition(WorkOrdersLoaded state, WorkOrder updated) {
    const terminal = {'completed', 'cancelled'};
    if (!state.showHistory && terminal.contains(updated.status)) {
      return [for (final w in state.workOrders) if (w.id != updated.id) w];
    }
    return [for (final w in state.workOrders) if (w.id == updated.id) updated else w];
  }

  /// The server's own order: priority ascending (1 most urgent, sorting
  /// first), Work order number ascending as the tiebreak.
  static int _byPriorityThenNumber(WorkOrder a, WorkOrder b) {
    final byPriority = a.priority.compareTo(b.priority);
    return byPriority != 0 ? byPriority : a.workOrderNo.compareTo(b.workOrderNo);
  }
}
