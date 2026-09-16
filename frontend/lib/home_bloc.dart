/// Home's own state (issue #101): role-scoped counts of work the signed-in
/// Account can act on now — never a trend, a target or a Pillar; those
/// belong to #76's tier board, not this Screen.
///
/// Two independent sections, each read only when the Account's role earns
/// the Destination behind it, and each tracked with its own
/// loading/loaded/failed state rather than one whole-Screen flag: #99's
/// Implementation Decisions ask for per-card failure where it is not
/// disproportionate, so a broken Work order read must not hide the
/// Approvals count, and the reverse. A role that earns neither section — an
/// operator, who holds no Work orders Destination and no Approvals — never
/// reads either endpoint at all: [HomeStarted] settles straight into
/// [HomeReady] with both sections left null, which is what asks the Screen
/// for its own "nothing is waiting on you" empty state rather than a stalled
/// loading placeholder.
///
/// No new endpoint: [_loadWorkSummary] reads exactly what `WorkOrdersBloc`
/// already reads (`PeopleApi.fetchSites`, then `MaintenanceApi.fetchWorkOrders`
/// per Site), and [_loadApprovals] reads exactly what `ApprovalQueueBloc`
/// already reads (`PeopleApi.fetchPendingAccounts`).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'actions/actions_api.dart';
import 'maintenance/maintenance_api.dart';
import 'people/employee.dart';
import 'people/org_unit_scope.dart';
import 'people_api.dart';
import 'platform/auth_gateway.dart';
import 'platform/destinations.dart';

sealed class HomeEvent {
  const HomeEvent();
}

/// The Screen's first build: settles which sections this role earns, then
/// reads every one of them.
class HomeStarted extends HomeEvent {
  const HomeStarted();
}

/// The Work order section's own retry — re-reads Sites and, per Site, the
/// open Work orders, the same reads [HomeStarted] makes for this section.
/// Leaves the Approvals section, if any, untouched.
class HomeWorkSummaryRetried extends HomeEvent {
  const HomeWorkSummaryRetried();
}

/// The Approvals section's own retry. Leaves the Work order section, if any,
/// untouched — the same reasoning [HomeWorkSummaryRetried] follows for its
/// own sibling.
class HomeApprovalsRetried extends HomeEvent {
  const HomeApprovalsRetried();
}

/// The "assigned to you" section's own retry. Leaves the other sections, if
/// any, untouched — the same reasoning its siblings follow.
class HomeMyActionsRetried extends HomeEvent {
  const HomeMyActionsRetried();
}

/// One section's own reading of the server — loading, loaded, or failed.
/// Kept apart from [HomeReady] itself so one section's failure carries no
/// opinion about the other's.
sealed class HomeSectionState<T> {
  const HomeSectionState();
}

class HomeSectionLoading<T> extends HomeSectionState<T> {
  const HomeSectionLoading();
}

class HomeSectionLoaded<T> extends HomeSectionState<T> {
  const HomeSectionLoaded(this.data);
  final T data;
}

class HomeSectionFailed<T> extends HomeSectionState<T> {
  const HomeSectionFailed({required this.message, this.isScopeRefused = false});
  final String message;

  /// Read off a `403`, the same classification `WorkOrdersUnavailable`
  /// already makes (issue #103's fifth case). Neither read this Bloc makes
  /// can actually produce one today — Maintenance's list read is Site-wide
  /// regardless of Grants (ADR-0009) and the Approval queue is gated by role,
  /// not by Grant — so this exists for the same reason that field does:
  /// proven now, through this Screen's own test, rather than invented the
  /// day a scoped read is added.
  final bool isScopeRefused;
}

/// Open Work orders across every Site this Account can see, and how many of
/// them nobody has yet.
class HomeWorkSummary {
  const HomeWorkSummary({
    required this.openCount,
    required this.unassignedCount,
    required this.unassignedScopedToGrants,
  });

  final int openCount;

  /// Open and unassigned, counted only within an Org Unit this Account holds
  /// a Grant reaching — every Org Unit, for an administrator (`everywhere`).
  /// Since issue #110 (ADR-0027) `/me` reports each Grant's whole reach, the
  /// granted unit plus every descendant, so a Work order sitting *beneath* a
  /// granted Org Unit is counted here too: this is now the honest "awaiting
  /// assignment across the Org Units I may act in", not a count that silently
  /// drops everything below a Grant.
  final int unassignedCount;

  /// Whether [unassignedCount] is scoped to this Account's Grants rather than
  /// every Site — false only for an administrator's own `everywhere` scope.
  /// The count itself is complete within that scope (issue #110), so this no
  /// longer flags an undercount; it is what lets the card say *which* scope
  /// the number is complete across, rather than telling a scoped Account it is
  /// seeing everything when it is seeing its own reach.
  final bool unassignedScopedToGrants;
}

/// What is assigned to the caller: open Actions whose owner is their own
/// Employee record.
///
/// Two facts rather than one, because "you have nothing assigned" and "nothing
/// can be assigned to you" are different answers and only the second is
/// actionable: an Action's owner is an Employee (`action_items.owner_employee_id`
/// references `employees`), and an Account with no linked Employee can never be
/// one. The server 404s `GET /employees/me` with that exact distinction, so it
/// is carried here rather than being flattened into a count of zero.
class HomeMyActions {
  const HomeMyActions({required this.openCount, required this.hasEmployeeLink});

  /// Open Actions owned by the caller's Employee, across every Site the caller
  /// can see.
  final int openCount;

  /// Whether this Account is linked to an Employee at all.
  final bool hasEmployeeLink;
}

sealed class HomeState {
  const HomeState();
}

/// Before [HomeStarted] has settled which sections this role earns.
class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeReady extends HomeState {
  const HomeReady({required this.role, this.workSummary, this.myActions, this.approvals});

  final String role;

  /// Null when this role does not earn the Work orders Destination at all
  /// (`ModuleRoles.maintenance`) — never read in that case.
  final HomeSectionState<HomeWorkSummary>? workSummary;

  /// What is assigned to the caller. Never null: every approved Account earns
  /// the Actions Destination (ADR-0032 — the Module's register is a Site-wide
  /// read and raising needs only a read Grant), so this section is read for
  /// every role that can reach Home at all.
  final HomeSectionState<HomeMyActions>? myActions;

  /// Null when this role is not `admin` — never read in that case.
  final HomeSectionState<int>? approvals;

  /// Whether no section applies to this role — #99 user story 6's case, and
  /// false for every role now: [myActions] is read for everyone, so there is
  /// always at least one card. Kept because it is the honest statement of the
  /// rule the Screen no longer needs to branch on.
  bool get earnsNoCards => workSummary == null && myActions == null && approvals == null;

  HomeReady copyWith({
    HomeSectionState<HomeWorkSummary>? workSummary,
    HomeSectionState<HomeMyActions>? myActions,
    HomeSectionState<int>? approvals,
  }) =>
      HomeReady(
        role: role,
        workSummary: workSummary ?? this.workSummary,
        myActions: myActions ?? this.myActions,
        approvals: approvals ?? this.approvals,
      );
}

/// Lives and dies with Home, unlike `AccountBloc`: this is one Screen's own
/// reading of the server, and it should be re-read on arrival rather than
/// restored stale — the same reasoning `WorkOrdersBloc`/`ApprovalQueueBloc`
/// already carry for their own Screens.
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required PeopleApi peopleApi,
    required MaintenanceApi maintenanceApi,
    required ActionsApi actionsApi,
    required AuthGateway authGateway,
    required String accountRole,
    required OrgUnitScope accountOrgUnitScope,
  })  : _people = peopleApi,
        _maintenance = maintenanceApi,
        _actions = actionsApi,
        _auth = authGateway,
        _role = accountRole,
        _orgUnitScope = accountOrgUnitScope,
        super(const HomeLoading()) {
    on<HomeStarted>(_onStarted);
    on<HomeWorkSummaryRetried>(_onWorkSummaryRetried);
    on<HomeMyActionsRetried>(_onMyActionsRetried);
    on<HomeApprovalsRetried>(_onApprovalsRetried);
  }

  final PeopleApi _people;
  final MaintenanceApi _maintenance;
  final ActionsApi _actions;
  final AuthGateway _auth;
  final String _role;
  final OrgUnitScope _orgUnitScope;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  /// The roles that earn a Work orders Destination at all — the same set
  /// `Routes.workOrders`'s own route guard checks (router.dart), so this
  /// Bloc can never offer a card the Shell would refuse.
  bool get _earnsWorkSummary => ModuleRoles.maintenance.contains(_role);

  /// The Approval queue is administrator-only (router.dart's own
  /// `Routes.approvals` guard) — mirrored here for the same reason.
  bool get _earnsApprovals => _role == Roles.admin;

  /// Every role earns what is assigned to it. The Actions Destination carries
  /// no `roles` set (ADR-0032): the register is a Site-wide read for every
  /// admitted Account, and an Account may own work whoever it is — an
  /// operator on the floor most of all. So this is not a check, it is the
  /// reason the section is unlike its two siblings.
  bool get _earnsMyActions => true;

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    emit(
      HomeReady(
        role: _role,
        workSummary: _earnsWorkSummary ? const HomeSectionLoading() : null,
        myActions: _earnsMyActions ? const HomeSectionLoading() : null,
        approvals: _earnsApprovals ? const HomeSectionLoading() : null,
      ),
    );
    // Both sections, when earned, are read concurrently — `Future.wait`
    // rather than two `unawaited` calls, since an event handler's `emit`
    // stops accepting calls the moment the handler itself returns (bloc's own
    // contract): a fire-and-forget read racing past that point would throw.
    await Future.wait([
      if (_earnsWorkSummary) _loadWorkSummary(emit),
      if (_earnsMyActions) _loadMyActions(emit),
      if (_earnsApprovals) _loadApprovals(emit),
    ]);
  }

  Future<void> _onWorkSummaryRetried(HomeWorkSummaryRetried event, Emitter<HomeState> emit) async {
    final current = state;
    if (current is! HomeReady || current.workSummary == null) return;
    emit(current.copyWith(workSummary: const HomeSectionLoading()));
    await _loadWorkSummary(emit);
  }

  Future<void> _onMyActionsRetried(HomeMyActionsRetried event, Emitter<HomeState> emit) async {
    final current = state;
    if (current is! HomeReady || current.myActions == null) return;
    emit(current.copyWith(myActions: const HomeSectionLoading()));
    await _loadMyActions(emit);
  }

  /// What is assigned to the caller, read exactly the way the Actions register
  /// reads it (`PeopleApi.fetchSites`, then `ActionsApi.fetchActions` per Site
  /// with `ownerEmployeeId`) — no new endpoint, the same rule
  /// [_loadWorkSummary] follows for Work orders.
  ///
  /// The one read here that the register does not make is `/employees/me`,
  /// which is what turns "the caller" into an Employee id. Its 404 means this
  /// Account carries no `employeeId` at all (directory-routes.js writes that
  /// refusal itself), and that is an answer rather than a failure: it settles
  /// as `hasEmployeeLink: false` and the card says so. Every other failure is
  /// this section's own.
  Future<void> _loadMyActions(Emitter<HomeState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      _emitMyActions(emit, const HomeSectionFailed(message: signedOutMessage));
      return;
    }
    try {
      final EmployeeDetail me;
      try {
        me = await _people.fetchMyEmployeeRecord(token);
      } on PeopleApiException catch (error) {
        if (error.statusCode == 404) {
          _emitMyActions(
            emit,
            const HomeSectionLoaded(
              HomeMyActions(openCount: 0, hasEmployeeLink: false),
            ),
          );
          return;
        }
        rethrow;
      }

      final sites = await _people.fetchSites(token);
      var openCount = 0;
      for (final site in sites) {
        final register = await _actions.fetchActions(
          token,
          siteId: site.id,
          ownerEmployeeId: me.id,
        );
        openCount += register.actions.length;
      }
      _emitMyActions(
        emit,
        HomeSectionLoaded(HomeMyActions(openCount: openCount, hasEmployeeLink: true)),
      );
    } on PeopleApiException catch (error) {
      _emitMyActions(emit, HomeSectionFailed(message: error.message));
    } on ActionsApiException catch (error) {
      _emitMyActions(emit, HomeSectionFailed(message: error.message));
    }
  }

  void _emitMyActions(Emitter<HomeState> emit, HomeSectionState<HomeMyActions> section) {
    final current = state;
    if (current is! HomeReady) return;
    emit(current.copyWith(myActions: section));
  }

  Future<void> _onApprovalsRetried(HomeApprovalsRetried event, Emitter<HomeState> emit) async {
    final current = state;
    if (current is! HomeReady || current.approvals == null) return;
    emit(current.copyWith(approvals: const HomeSectionLoading()));
    await _loadApprovals(emit);
  }

  Future<void> _loadWorkSummary(Emitter<HomeState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      _emitWorkSummary(emit, const HomeSectionFailed(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      var openCount = 0;
      var unassignedCount = 0;
      for (final site in sites) {
        final workOrders = await _maintenance.fetchWorkOrders(token, siteId: site.id);
        openCount += workOrders.length;
        unassignedCount += workOrders
            .where((workOrder) => workOrder.assignedTo == null && _reachesOrgUnit(workOrder.orgUnitId))
            .length;
      }
      _emitWorkSummary(
        emit,
        HomeSectionLoaded(
          HomeWorkSummary(
            openCount: openCount,
            unassignedCount: unassignedCount,
            unassignedScopedToGrants: !_orgUnitScope.everywhere,
          ),
        ),
      );
    } on PeopleApiException catch (error) {
      _emitWorkSummary(
        emit,
        HomeSectionFailed(message: error.message, isScopeRefused: error.statusCode == 403),
      );
    } on MaintenanceApiException catch (error) {
      _emitWorkSummary(
        emit,
        HomeSectionFailed(message: error.message, isScopeRefused: error.statusCode == 403),
      );
    }
  }

  bool _reachesOrgUnit(String orgUnitId) => _orgUnitScope.reachesOrgUnit(orgUnitId);

  Future<void> _loadApprovals(Emitter<HomeState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      _emitApprovals(emit, const HomeSectionFailed(message: signedOutMessage));
      return;
    }
    try {
      final pending = await _people.fetchPendingAccounts(token);
      _emitApprovals(emit, HomeSectionLoaded(pending.length));
    } on PeopleApiException catch (error) {
      _emitApprovals(
        emit,
        HomeSectionFailed(message: error.message, isScopeRefused: error.statusCode == 403),
      );
    }
  }

  /// Guards every emit the same way `WorkOrdersBloc._readList` guards its
  /// own: a section's read can outlive the state it was reading for (this
  /// Bloc is torn down when the Screen is, but a late response between two
  /// microtasks is still worth discarding defensively rather than crashing
  /// on a state that is no longer [HomeReady]).
  void _emitWorkSummary(Emitter<HomeState> emit, HomeSectionState<HomeWorkSummary> section) {
    final current = state;
    if (current is! HomeReady) return;
    emit(current.copyWith(workSummary: section));
  }

  void _emitApprovals(Emitter<HomeState> emit, HomeSectionState<int> section) {
    final current = state;
    if (current is! HomeReady) return;
    emit(current.copyWith(approvals: section));
  }
}
