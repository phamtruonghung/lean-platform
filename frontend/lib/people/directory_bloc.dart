/// The Directory list's own state (issue #86): who is read, and by which
/// search and filters.
///
/// Route-scoped, like `AssetsBloc` and `ApprovalQueueBloc`, and unlike
/// `AccountBloc`: one Screen's reading of the server, re-read on arrival
/// rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'employee.dart';
import 'job_role.dart';

sealed class DirectoryEvent {
  const DirectoryEvent();
}

/// Load the job role catalogue once, then the list itself. Also the retry a
/// failed load offers.
class DirectoryStarted extends DirectoryEvent {
  const DirectoryStarted();
}

/// Narrow (or clear, with `''`) by name.
class DirectorySearchChanged extends DirectoryEvent {
  const DirectorySearchChanged(this.search);
  final String search;
}

/// Narrow (or clear, with both null) to one Org Unit. [orgUnitName] is
/// carried alongside the id purely so the Screen has something to show for
/// the filter chosen — there is no "look this id up" endpoint the Directory
/// itself could call (ADR-0009: the whole point is that it needs none).
class DirectoryOrgUnitFilterChanged extends DirectoryEvent {
  const DirectoryOrgUnitFilterChanged({this.orgUnitId, this.orgUnitName});
  final String? orgUnitId;
  final String? orgUnitName;
}

/// Narrow (or clear, with null) to one job role.
class DirectoryJobRoleFilterChanged extends DirectoryEvent {
  const DirectoryJobRoleFilterChanged(this.jobRoleId);
  final String? jobRoleId;
}

/// Whether Departed Employees are included (AC criterion 4).
class DirectoryIncludeDepartedChanged extends DirectoryEvent {
  const DirectoryIncludeDepartedChanged(this.includeDeparted);
  final bool includeDeparted;
}

sealed class DirectoryState {
  const DirectoryState();
}

class DirectoryLoading extends DirectoryState {
  const DirectoryLoading();
}

/// The Directory as it last read, and every filter currently applied. An
/// empty [employees] is not a state of its own — the same reasoning
/// `ApprovalQueueLoaded` gives for its own empty list.
class DirectoryLoaded extends DirectoryState {
  const DirectoryLoaded({
    required this.employees,
    this.jobRoles = const [],
    this.search = '',
    this.orgUnitId,
    this.orgUnitName,
    this.jobRoleId,
    this.jobRoleName,
    this.includeDeparted = false,
    this.isLoadingList = false,
  });

  final List<Employee> employees;

  /// The job role catalogue, read once at [DirectoryStarted] for the job
  /// role filter's own options. A failure to read it does not fail the whole
  /// Screen — see `DirectoryBloc._onStarted` — so this can legitimately stay
  /// empty while [employees] itself reads fine.
  final List<JobRole> jobRoles;

  final String search;
  final String? orgUnitId;
  final String? orgUnitName;
  final String? jobRoleId;
  final String? jobRoleName;
  final bool includeDeparted;

  /// A filter change re-reads the list while everything else on the Header
  /// stays interactive — the same shape `AssetsLoaded.isLoadingAssets` gives
  /// a Site switch.
  final bool isLoadingList;

  DirectoryLoaded copyWith({
    List<Employee>? employees,
    List<JobRole>? jobRoles,
    String? search,
    String? orgUnitId,
    String? orgUnitName,
    bool clearOrgUnitFilter = false,
    String? jobRoleId,
    String? jobRoleName,
    bool clearJobRoleFilter = false,
    bool? includeDeparted,
    bool? isLoadingList,
  }) =>
      DirectoryLoaded(
        employees: employees ?? this.employees,
        jobRoles: jobRoles ?? this.jobRoles,
        search: search ?? this.search,
        orgUnitId: clearOrgUnitFilter ? null : (orgUnitId ?? this.orgUnitId),
        orgUnitName: clearOrgUnitFilter ? null : (orgUnitName ?? this.orgUnitName),
        jobRoleId: clearJobRoleFilter ? null : (jobRoleId ?? this.jobRoleId),
        jobRoleName: clearJobRoleFilter ? null : (jobRoleName ?? this.jobRoleName),
        includeDeparted: includeDeparted ?? this.includeDeparted,
        isLoadingList: isLoadingList ?? this.isLoadingList,
      );
}

class DirectoryUnavailable extends DirectoryState {
  const DirectoryUnavailable({required this.message});
  final String message;
}

class DirectoryBloc extends Bloc<DirectoryEvent, DirectoryState> {
  DirectoryBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const DirectoryLoading()) {
    on<DirectoryStarted>(_onStarted);
    on<DirectorySearchChanged>(_onSearchChanged);
    on<DirectoryOrgUnitFilterChanged>(_onOrgUnitFilterChanged);
    on<DirectoryJobRoleFilterChanged>(_onJobRoleFilterChanged);
    on<DirectoryIncludeDepartedChanged>(_onIncludeDepartedChanged);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(DirectoryStarted event, Emitter<DirectoryState> emit) async {
    emit(const DirectoryLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const DirectoryUnavailable(message: signedOutMessage));
      return;
    }

    // The job role filter's own options. Deliberately not fatal to the whole
    // Screen: the filter is what is missing, not the Directory itself.
    List<JobRole> jobRoles = const [];
    try {
      jobRoles = await _api.fetchJobRoles(token);
    } on PeopleApiException {
      jobRoles = const [];
    }

    emit(DirectoryLoaded(employees: const [], jobRoles: jobRoles, isLoadingList: true));
    await _readList(emit);
  }

  Future<void> _readList(Emitter<DirectoryState> emit) async {
    final current = state;
    if (current is! DirectoryLoaded) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const DirectoryUnavailable(message: signedOutMessage));
      return;
    }

    try {
      final employees = await _api.fetchEmployees(
        token,
        search: current.search,
        orgUnitId: current.orgUnitId,
        jobRoleId: current.jobRoleId,
        includeDeparted: current.includeDeparted,
      );
      final settled = state;
      if (settled is! DirectoryLoaded) return;
      emit(settled.copyWith(employees: employees, isLoadingList: false));
    } on PeopleApiException catch (error) {
      emit(DirectoryUnavailable(message: error.message));
    }
  }

  Future<void> _onSearchChanged(DirectorySearchChanged event, Emitter<DirectoryState> emit) async {
    final current = state;
    if (current is! DirectoryLoaded) return;
    emit(current.copyWith(search: event.search, isLoadingList: true));
    await _readList(emit);
  }

  Future<void> _onOrgUnitFilterChanged(
    DirectoryOrgUnitFilterChanged event,
    Emitter<DirectoryState> emit,
  ) async {
    final current = state;
    if (current is! DirectoryLoaded) return;
    emit(
      current.copyWith(
        orgUnitId: event.orgUnitId,
        orgUnitName: event.orgUnitName,
        clearOrgUnitFilter: event.orgUnitId == null,
        isLoadingList: true,
      ),
    );
    await _readList(emit);
  }

  Future<void> _onJobRoleFilterChanged(
    DirectoryJobRoleFilterChanged event,
    Emitter<DirectoryState> emit,
  ) async {
    final current = state;
    if (current is! DirectoryLoaded) return;
    String? jobRoleName;
    for (final jobRole in current.jobRoles) {
      if (jobRole.id == event.jobRoleId) {
        jobRoleName = jobRole.name;
        break;
      }
    }
    emit(
      current.copyWith(
        jobRoleId: event.jobRoleId,
        jobRoleName: jobRoleName,
        clearJobRoleFilter: event.jobRoleId == null,
        isLoadingList: true,
      ),
    );
    await _readList(emit);
  }

  Future<void> _onIncludeDepartedChanged(
    DirectoryIncludeDepartedChanged event,
    Emitter<DirectoryState> emit,
  ) async {
    final current = state;
    if (current is! DirectoryLoaded) return;
    emit(current.copyWith(includeDeparted: event.includeDeparted, isLoadingList: true));
    await _readList(emit);
  }
}
