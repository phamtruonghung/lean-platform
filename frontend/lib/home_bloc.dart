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

import 'maintenance/maintenance_api.dart';
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
  /// a Grant on — every Org Unit, for an administrator (`everywhere`). A
  /// coarse signal, the same one `Routes.workOrders`'s own
  /// `canAssignWorkOrder` already reads off `orgUnitScope` (router.dart):
  /// `/me` reports which Org Units are granted but not their ancestry, so a
  /// Work order sitting *beneath* a granted Org Unit is not counted here even
  /// though a write there would actually be allowed. No new endpoint changes
  /// that; this only tells the same coarse story a card can.
  final int unassignedCount;

  /// Whether [unassignedCount] is genuinely undercounted for this reason —
  /// true for every Account except an administrator's own `everywhere` scope
  /// (a follow-up on #101, raised before this shipped). The count itself is
  /// never changed for this: fixing the undercount needs the Org Unit
  /// ancestry no endpoint here answers. What changes is the card's own
  /// claim — `_HomeCard`'s context line reads differently depending on this
  /// flag, so a scoped Account is never told it is seeing everything
  /// unassigned when it is only seeing what it holds a Grant on directly.
  final bool unassignedScopedToGrants;
}

sealed class HomeState {
  const HomeState();
}

/// Before [HomeStarted] has settled which sections this role earns.
class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeReady extends HomeState {
  const HomeReady({required this.role, this.workSummary, this.approvals});

  final String role;

  /// Null when this role does not earn the Work orders Destination at all
  /// (`ModuleRoles.maintenance`) — never read in that case.
  final HomeSectionState<HomeWorkSummary>? workSummary;

  /// Null when this role is not `admin` — never read in that case.
  final HomeSectionState<int>? approvals;

  /// Neither section applies to this role: the Screen's own no-cards case
  /// (#99 user story 6), which gets its own deliberate empty state rather
  /// than a blank Screen.
  bool get earnsNoCards => workSummary == null && approvals == null;

  HomeReady copyWith({
    HomeSectionState<HomeWorkSummary>? workSummary,
    HomeSectionState<int>? approvals,
  }) =>
      HomeReady(
        role: role,
        workSummary: workSummary ?? this.workSummary,
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
    required AuthGateway authGateway,
    required String accountRole,
    required OrgUnitScope accountOrgUnitScope,
  })  : _people = peopleApi,
        _maintenance = maintenanceApi,
        _auth = authGateway,
        _role = accountRole,
        _orgUnitScope = accountOrgUnitScope,
        super(const HomeLoading()) {
    on<HomeStarted>(_onStarted);
    on<HomeWorkSummaryRetried>(_onWorkSummaryRetried);
    on<HomeApprovalsRetried>(_onApprovalsRetried);
  }

  final PeopleApi _people;
  final MaintenanceApi _maintenance;
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

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    emit(
      HomeReady(
        role: _role,
        workSummary: _earnsWorkSummary ? const HomeSectionLoading() : null,
        approvals: _earnsApprovals ? const HomeSectionLoading() : null,
      ),
    );
    // Both sections, when earned, are read concurrently — `Future.wait`
    // rather than two `unawaited` calls, since an event handler's `emit`
    // stops accepting calls the moment the handler itself returns (bloc's own
    // contract): a fire-and-forget read racing past that point would throw.
    await Future.wait([
      if (_earnsWorkSummary) _loadWorkSummary(emit),
      if (_earnsApprovals) _loadApprovals(emit),
    ]);
  }

  Future<void> _onWorkSummaryRetried(HomeWorkSummaryRetried event, Emitter<HomeState> emit) async {
    final current = state;
    if (current is! HomeReady || current.workSummary == null) return;
    emit(current.copyWith(workSummary: const HomeSectionLoading()));
    await _loadWorkSummary(emit);
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

  bool _reachesOrgUnit(String orgUnitId) =>
      _orgUnitScope.everywhere || _orgUnitScope.grants.any((grant) => grant.orgUnitId == orgUnitId);

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
