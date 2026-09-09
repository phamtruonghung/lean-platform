/// One Employee's record, as the detail Screen needs it (issue #86, AC5) —
/// reached either from a Directory row (`GET /api/people/employees/:id`) or
/// from "My record" (`GET /api/people/employees/me`), the same shape both
/// ways: [EmployeeDetailRequested.employeeId] null means "me".
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'employee.dart';
import 'job_role.dart';

sealed class EmployeeDetailEvent {
  const EmployeeDetailEvent();
}

/// Load one Employee's record — the Screen's first build, and the retry a
/// failed load offers.
class EmployeeDetailRequested extends EmployeeDetailEvent {
  const EmployeeDetailRequested({this.employeeId});

  /// Null means "the caller's own record" (`GET /employees/me`).
  final String? employeeId;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed (issue #87) — same contract `PeopleApi.updateEmployee`
/// documents, carried one step further back to the dialog that builds the
/// diff in the first place.
class EmployeeDetailCorrectionConfirmed extends EmployeeDetailEvent {
  const EmployeeDetailCorrectionConfirmed(this.changes);
  final Map<String, Object?> changes;
}

/// Records that this Employee has departed (issue #87) — a flag and a date,
/// never a deletion. [terminatedOn] is `YYYY-MM-DD`; null defers to the
/// server's own default of today.
class EmployeeDetailDepartureConfirmed extends EmployeeDetailEvent {
  const EmployeeDetailDepartureConfirmed({this.terminatedOn});
  final String? terminatedOn;
}

/// Undoes a departure (issue #87) — no fields, since reinstating asks for
/// nothing.
class EmployeeDetailReinstatementConfirmed extends EmployeeDetailEvent {
  const EmployeeDetailReinstatementConfirmed();
}

/// Assigns this Employee to an Org Unit (issue #88) — the first Assignment,
/// or a transfer when one is already open; `createAssignment` (directory.js)
/// decides which from whether an open Assignment already exists, so this
/// event carries no flag of its own for it. [jobRoleId] is optional,
/// [effectiveFrom] (`YYYY-MM-DD`) is not — see `EmployeeAssignmentDialog`'s
/// own header for why this dialog treats it as required even though the
/// server would default a missing one to today.
class EmployeeDetailAssignmentConfirmed extends EmployeeDetailEvent {
  const EmployeeDetailAssignmentConfirmed({
    required this.orgUnitId,
    this.jobRoleId,
    required this.effectiveFrom,
  });

  final String orgUnitId;
  final String? jobRoleId;
  final String effectiveFrom;
}

sealed class EmployeeDetailState {
  const EmployeeDetailState();
}

class EmployeeDetailLoading extends EmployeeDetailState {
  const EmployeeDetailLoading();
}

class EmployeeDetailLoaded extends EmployeeDetailState {
  const EmployeeDetailLoaded({
    required this.employee,
    this.jobRoles = const [],
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
  });

  final EmployeeDetail employee;

  /// The job role catalogue, read once alongside the Employee record for the
  /// assignment dialog's own job role choice (issue #88) — the same
  /// "read once, tolerate its own failure" shape `DirectoryLoaded.jobRoles`
  /// already uses, and for the same reason: a failure to read it should not
  /// fail the whole Screen, only leave the dropdown short.
  final List<JobRole> jobRoles;

  /// A correction, a departure or a reinstatement is in flight (issue #87).
  /// One flag, not three — the same reasoning `AssetsLoaded.mutatingAssetId`
  /// gives an Asset row: this record has one mutation at a time.
  final bool isMutating;

  /// Why the last correction or departure did not land. Reported by whichever
  /// dialog is open, which stays open so the caller can fix the field rather
  /// than retype the whole record.
  final String? mutationFailure;

  /// What a reinstatement (or its failure) had to say for itself — shown as a
  /// Screen-level banner, not inside a dialog, since reinstating opens none
  /// (the same "not asked about — it takes nothing away" rule
  /// `AccountsScreen`'s own reactivation and `AssetsScreen`'s own Asset
  /// reinstatement already follow).
  final String? notice;

  EmployeeDetailLoaded copyWith({
    EmployeeDetail? employee,
    List<JobRole>? jobRoles,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      EmployeeDetailLoaded(
        employee: employee ?? this.employee,
        jobRoles: jobRoles ?? this.jobRoles,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward, the same rule
        // `DirectoryLoaded.copyWith` gives `addFailure`.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class EmployeeDetailUnavailable extends EmployeeDetailState {
  const EmployeeDetailUnavailable({required this.message});
  final String message;
}

/// Route-scoped, like `DirectoryBloc`: one Screen's own reading of the
/// server, re-read on arrival rather than restored stale.
class EmployeeDetailBloc extends Bloc<EmployeeDetailEvent, EmployeeDetailState> {
  EmployeeDetailBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const EmployeeDetailLoading()) {
    on<EmployeeDetailRequested>(_onRequested);
    on<EmployeeDetailCorrectionConfirmed>(_onCorrectionConfirmed);
    on<EmployeeDetailDepartureConfirmed>(_onDepartureConfirmed);
    on<EmployeeDetailReinstatementConfirmed>(_onReinstatementConfirmed);
    on<EmployeeDetailAssignmentConfirmed>(_onAssignmentConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  /// The `employeeId` this Screen was last asked to show — null for "my own
  /// record". Remembered so a write's own re-read (`_reload`) asks the same
  /// question `_onRequested` originally did, rather than a correction on
  /// someone else's record silently falling back to `/me`.
  String? _lastRequestedEmployeeId;

  Future<void> _onRequested(
    EmployeeDetailRequested event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    emit(const EmployeeDetailLoading());
    _lastRequestedEmployeeId = event.employeeId;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const EmployeeDetailUnavailable(message: signedOutMessage));
      return;
    }
    // The job role catalogue, for the assignment dialog's own job role
    // choice (issue #88) — the same "read once, tolerate its own failure"
    // shape `DirectoryBloc._onStarted` already uses for its filter: a failure
    // here leaves the dropdown short, not the whole Screen unavailable.
    List<JobRole> jobRoles = const [];
    try {
      jobRoles = await _api.fetchJobRoles(token);
    } on PeopleApiException {
      jobRoles = const [];
    }
    try {
      final employee = event.employeeId == null
          ? await _api.fetchMyEmployeeRecord(token)
          : await _api.fetchEmployeeDetail(token, event.employeeId!);
      emit(EmployeeDetailLoaded(employee: employee, jobRoles: jobRoles));
    } on PeopleApiException catch (error) {
      emit(EmployeeDetailUnavailable(message: error.message));
    }
  }

  /// Re-reads the record in place after a successful write, rather than
  /// splicing the write's own response in: `updateEmployee`,
  /// `setEmployeeDeparted` and `reinstateEmployee` all RETURNING the bare
  /// `toEmployee` shape (directory.js) — no `jobRole`, no `assignments`, no
  /// `skills` — so building an `EmployeeDetail` straight from any of their
  /// responses would lose everything this Screen shows beneath the header.
  /// [notice] is carried into the freshly emitted state for a mutation (like
  /// reinstatement) that reports on a Screen-level banner rather than inside
  /// a dialog.
  Future<void> _reload(Emitter<EmployeeDetailState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const EmployeeDetailUnavailable(message: signedOutMessage));
      return;
    }
    // Carried forward rather than re-fetched: the job role catalogue did not
    // change just because the Employee record did, and `EmployeeDetailLoaded`
    // below is built fresh (not `copyWith`), so this is what keeps the
    // assignment dialog's own dropdown populated across the reload its own
    // success triggers.
    final settledBefore = state;
    final jobRoles = settledBefore is EmployeeDetailLoaded ? settledBefore.jobRoles : const <JobRole>[];
    try {
      final employee = _lastRequestedEmployeeId == null
          ? await _api.fetchMyEmployeeRecord(token)
          : await _api.fetchEmployeeDetail(token, _lastRequestedEmployeeId!);
      emit(EmployeeDetailLoaded(employee: employee, jobRoles: jobRoles, notice: notice));
    } on PeopleApiException catch (error) {
      emit(EmployeeDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    EmployeeDetailCorrectionConfirmed event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final current = state;
    if (current is! EmployeeDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateEmployee(token, current.employee.id, event.changes);
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onDepartureConfirmed(
    EmployeeDetailDepartureConfirmed event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final current = state;
    if (current is! EmployeeDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.setEmployeeDeparted(token, current.employee.id, terminatedOn: event.terminatedOn);
      await _reload(emit, notice: '${current.employee.displayName} has left.');
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onReinstatementConfirmed(
    EmployeeDetailReinstatementConfirmed event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final current = state;
    if (current is! EmployeeDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    // Not asked about — it takes nothing away, the same rule
    // `AccountsScreen`'s own reactivation and `AssetsScreen`'s own Asset
    // reinstatement already follow — so this dispatches straight through,
    // with no confirming dialog on the way.
    emit(current.copyWith(isMutating: true, notice: null));
    try {
      await _api.reinstateEmployee(token, current.employee.id);
      await _reload(emit, notice: '${current.employee.displayName} is back.');
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, notice: error.message));
    }
  }

  /// Assigns this Employee to an Org Unit (issue #88) — not administrator
  /// only, unlike the three handlers above: `EmployeeAssignmentDialog` is
  /// offered to any caller `OrgUnitScope.canWriteSomewhere` allows
  /// (ADR-0010), and the server is the real gate either way (403
  /// `OUTSIDE_GRANTED_ORG_UNITS` if the destination named turns out to sit
  /// outside every Grant this caller holds). Failure is reported inline on
  /// the open dialog, the same shape [_onCorrectionConfirmed] already uses —
  /// a scope refusal, an overlap/backdate 409, and a malformed date 400 all
  /// surface here as the API's own message rather than three different
  /// tellings of "that failed".
  Future<void> _onAssignmentConfirmed(
    EmployeeDetailAssignmentConfirmed event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final current = state;
    if (current is! EmployeeDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createAssignment(
        token,
        current.employee.id,
        orgUnitId: event.orgUnitId,
        jobRoleId: event.jobRoleId,
        effectiveFrom: event.effectiveFrom,
      );
      // Re-read rather than trust the response: `createAssignment`'s own
      // response is one Assignment, not the recomputed history with
      // `isCurrent` resolved (`PeopleApi.createAssignment`'s own header).
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
