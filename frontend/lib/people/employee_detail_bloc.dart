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
import 'skill.dart';

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

/// The administrator has chosen to deactivate the Account a just-Departed
/// Employee was still linked to (issue #116, ADR-0022) — offered only when
/// [EmployeeDetailLoaded.departureLinkedAccount] is not null, and never
/// dispatched automatically: a departure must not deactivate the linked
/// Account silently.
class EmployeeDetailLinkedAccountDeactivationConfirmed extends EmployeeDetailEvent {
  const EmployeeDetailLinkedAccountDeactivationConfirmed({required this.accountId});
  final String accountId;
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

/// Records, or re-assesses, this Employee holding a skill (issue #89) — the
/// same "the caller decided, the Bloc only ever sees a decision already
/// made" contract [EmployeeDetailAssignmentConfirmed] carries. `employee_
/// skills` has `UNIQUE (employee_id, skill_id)` (skills.js's own header), so
/// there is no flag here to say "first assessment" or "re-assessment" —
/// `recordEmployeeSkill` (skills.js) upserts either way, and the same event
/// covers both. [proficiencyLevel] is 0–4 on the ILUO scale; [assessedOn]
/// and [expiresOn] are `YYYY-MM-DD`, each optional.
class EmployeeDetailSkillRecorded extends EmployeeDetailEvent {
  const EmployeeDetailSkillRecorded({
    required this.skillId,
    required this.proficiencyLevel,
    this.assessedOn,
    this.expiresOn,
    this.evidenceRef,
    this.note,
  });

  final String skillId;
  final int proficiencyLevel;
  final String? assessedOn;
  final String? expiresOn;
  final String? evidenceRef;
  final String? note;
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
    this.skills = const [],
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
    this.departureLinkedAccount,
  });

  final EmployeeDetail employee;

  /// The job role catalogue, read once alongside the Employee record for the
  /// assignment dialog's own job role choice (issue #88) — the same
  /// "read once, tolerate its own failure" shape `DirectoryLoaded.jobRoles`
  /// already uses, and for the same reason: a failure to read it should not
  /// fail the whole Screen, only leave the dropdown short.
  final List<JobRole> jobRoles;

  /// The skill catalogue (issue #89), read once alongside the Employee
  /// record for the "record a skill" form's own skill choice — the same
  /// "read once, tolerate its own failure" shape [jobRoles] already carries,
  /// for the same reason.
  final List<Skill> skills;

  /// A correction, a departure, a reinstatement or a skill assessment is in
  /// flight (issue #87, extended by issue #89).
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

  /// The Account a departure just recorded through this Bloc found still
  /// linked to this Employee, if any (issue #116, ADR-0022) — set only by the
  /// departure that just landed, and cleared on every subsequent emit the
  /// same way [mutationFailure]/[notice] already are: it is a one-shot "this
  /// just happened" signal, not standing state. Null means either nothing was
  /// linked, or the warning has already been dealt with (deactivated, or
  /// dismissed by the dialog closing).
  final LinkedAccountSummary? departureLinkedAccount;

  EmployeeDetailLoaded copyWith({
    EmployeeDetail? employee,
    List<JobRole>? jobRoles,
    List<Skill>? skills,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
    LinkedAccountSummary? departureLinkedAccount,
  }) =>
      EmployeeDetailLoaded(
        employee: employee ?? this.employee,
        jobRoles: jobRoles ?? this.jobRoles,
        skills: skills ?? this.skills,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward, the same rule
        // `DirectoryLoaded.copyWith` gives `addFailure`.
        mutationFailure: mutationFailure,
        notice: notice,
        departureLinkedAccount: departureLinkedAccount,
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
    on<EmployeeDetailLinkedAccountDeactivationConfirmed>(_onLinkedAccountDeactivationConfirmed);
    on<EmployeeDetailAssignmentConfirmed>(_onAssignmentConfirmed);
    on<EmployeeDetailSkillRecorded>(_onSkillRecorded);
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
    // The skill catalogue (issue #89), for the "record a skill" form's own
    // skill choice — the same "read once, tolerate its own failure" shape as
    // [jobRoles] just above.
    List<Skill> skills = const [];
    try {
      skills = await _api.fetchSkills(token);
    } on PeopleApiException {
      skills = const [];
    }
    try {
      final employee = event.employeeId == null
          ? await _api.fetchMyEmployeeRecord(token)
          : await _api.fetchEmployeeDetail(token, event.employeeId!);
      emit(EmployeeDetailLoaded(employee: employee, jobRoles: jobRoles, skills: skills));
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
  Future<void> _reload(
    Emitter<EmployeeDetailState> emit, {
    String? notice,
    LinkedAccountSummary? departureLinkedAccount,
  }) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const EmployeeDetailUnavailable(message: signedOutMessage));
      return;
    }
    // Carried forward rather than re-fetched: neither catalogue changed just
    // because the Employee record did, and `EmployeeDetailLoaded` below is
    // built fresh (not `copyWith`), so this is what keeps the assignment
    // dialog's job role dropdown and the skill form's skill dropdown
    // populated across the reload their own success triggers.
    final settledBefore = state;
    final jobRoles = settledBefore is EmployeeDetailLoaded ? settledBefore.jobRoles : const <JobRole>[];
    final skills = settledBefore is EmployeeDetailLoaded ? settledBefore.skills : const <Skill>[];
    try {
      final employee = _lastRequestedEmployeeId == null
          ? await _api.fetchMyEmployeeRecord(token)
          : await _api.fetchEmployeeDetail(token, _lastRequestedEmployeeId!);
      emit(
        EmployeeDetailLoaded(
          employee: employee,
          jobRoles: jobRoles,
          skills: skills,
          notice: notice,
          departureLinkedAccount: departureLinkedAccount,
        ),
      );
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
      final linkedAccount = await _api.setEmployeeDeparted(
        token,
        current.employee.id,
        terminatedOn: event.terminatedOn,
      );
      await _reload(
        emit,
        notice: '${current.employee.displayName} has left.',
        departureLinkedAccount: linkedAccount,
      );
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  /// Deactivates the Account [EmployeeDetailLoaded.departureLinkedAccount]
  /// named, after the administrator explicitly chooses to (issue #116,
  /// ADR-0022) — the departure already landed before this ever runs, so a
  /// failure here leaves the departure exactly as it was, not undone.
  Future<void> _onLinkedAccountDeactivationConfirmed(
    EmployeeDetailLinkedAccountDeactivationConfirmed event,
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
      await _api.setAccountActive(token, accountId: event.accountId, isActive: false);
      // The warning has now been dealt with — cleared, not carried forward,
      // so the dialog's own listener reads this as "settled" and closes.
      emit(current.copyWith(isMutating: false, departureLinkedAccount: null));
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

  /// Records, or re-assesses, this Employee holding a skill (issue #89) —
  /// administrator only, unlike [_onAssignmentConfirmed] just above:
  /// `PUT /employees/:id/skills/:skillId` sits behind `requireAdmin`, not
  /// Org-Unit write scope (skill-routes.js's own header, ADR-0010's
  /// Consequences section naming this exact case as the one where ADR-0009's
  /// original "an Employee record is not owned by an Org Unit" reasoning
  /// holds unchanged). Re-reads the record afterwards rather than trusting
  /// the response, the same reason [_onAssignmentConfirmed] does: the PUT's
  /// own response is the bare `employee_skills` row, not the recomputed
  /// `EmployeeDetail` with `isLapsed` resolved.
  Future<void> _onSkillRecorded(
    EmployeeDetailSkillRecorded event,
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
      await _api.recordEmployeeSkill(
        token,
        current.employee.id,
        event.skillId,
        proficiencyLevel: event.proficiencyLevel,
        assessedOn: event.assessedOn,
        expiresOn: event.expiresOn,
        evidenceRef: event.evidenceRef,
        note: event.note,
      );
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! EmployeeDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
