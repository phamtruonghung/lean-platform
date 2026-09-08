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

/// The Add Employee form has decided: this is a whole new Employee (issue
/// #87). Same contract as `AssetAddConfirmed` — the dialog decides, the Bloc
/// only ever sees a decision already made.
class DirectoryAddConfirmed extends DirectoryEvent {
  const DirectoryAddConfirmed({
    required this.employeeNo,
    required this.firstName,
    required this.lastName,
    this.employmentType,
    this.workEmail,
  });

  final String employeeNo;
  final String firstName;
  final String lastName;
  final String? employmentType;
  final String? workEmail;
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
    this.isAdding = false,
    this.addFailure,
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

  /// An add is in flight (issue #87). Kept on the state, not only in the
  /// dialog, so the Screen can refuse a second one — the same shape
  /// `AssetsLoaded.isAdding` uses.
  final bool isAdding;

  /// Why the last add did not land. Reported by the open dialog, which stays
  /// open so the caller can fix the field rather than retype the whole
  /// Employee.
  final String? addFailure;

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
    bool? isAdding,
    String? addFailure,
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
        isAdding: isAdding ?? this.isAdding,
        // Always overwritten, never carried forward — the same rule
        // `AssetsLoaded.copyWith` gives `addFailure`: a failure is reported
        // once, for the frame right after it happens, and any other state
        // change (a re-list, a filter) clears it rather than leaving it to
        // linger silently.
        addFailure: addFailure,
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
    on<DirectoryAddConfirmed>(_onAddConfirmed);
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
      // isAdding is always explicitly false here, not left to `copyWith`'s
      // `?? this.isAdding` default — harmless for an ordinary filter/search
      // re-read (already false), and what lets `_onAddConfirmed` fold "the
      // add landed" and "the list now shows it" into the one state
      // transition the open dialog's own listener reacts to, rather than
      // two, which would call `Navigator.pop` twice.
      emit(settled.copyWith(employees: employees, isLoadingList: false, isAdding: false));
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

  /// Adds an Employee (issue #87), administrator only — the Screen never
  /// offers this event to anyone else, and `POST /employees` would refuse it
  /// with a 403 anyway.
  ///
  /// On success this deliberately does NOT splice the response into
  /// [DirectoryLoaded.employees]: `createEmployee`'s own response
  /// (`PeopleApi.createEmployee`'s own header explains why) carries no
  /// `orgUnit` and no `jobRole`, so the new row would render with neither
  /// until something else reloaded it. A full [_readList] is what
  /// `listEmployees`'s own joins are for.
  Future<void> _onAddConfirmed(DirectoryAddConfirmed event, Emitter<DirectoryState> emit) async {
    final current = state;
    if (current is! DirectoryLoaded || current.isAdding) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(addFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isAdding: true, addFailure: null));
    try {
      await _api.createEmployee(
        token,
        employeeNo: event.employeeNo,
        firstName: event.firstName,
        lastName: event.lastName,
        employmentType: event.employmentType,
        workEmail: event.workEmail,
      );
      // One state transition, not two: `_readList`'s own success emit is what
      // clears `isAdding`, bundled with the refreshed list — see its own
      // comment for why a separate "isAdding: false" emit here would fire the
      // open dialog's listener twice and pop it twice.
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! DirectoryLoaded) return;
      emit(settled.copyWith(isAdding: false, addFailure: error.message));
    }
  }
}
