/// The job role catalogue's own state (issue #88): the shared reference data
/// (ADR-0005, CONTEXT.md's Job role entry) that feeds the Directory's own job
/// role filter and every Assignment's job role choice — and, on this
/// Screen, an administrator's own write surface over it
/// (`POST`/`PATCH /api/people/job-roles`, job-role-routes.js).
///
/// Route-scoped, like `DirectoryBloc`: one Screen's own reading of the
/// server, re-read on arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'job_role.dart';

sealed class JobRolesEvent {
  const JobRolesEvent();
}

/// Load the whole catalogue, active and deactivated rows alike. Also the
/// retry a failed load offers.
class JobRolesStarted extends JobRolesEvent {
  const JobRolesStarted();
}

/// The add form has decided: a whole new job role (issue #88). Same contract
/// as `DirectoryAddConfirmed` — the dialog decides, the Bloc only ever sees a
/// decision already made.
class JobRolesAddConfirmed extends JobRolesEvent {
  const JobRolesAddConfirmed({required this.code, required this.name});

  final String code;
  final String name;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed — same contract `EmployeeDetailCorrectionConfirmed`
/// carries for the Employee record, `updateJobRole`'s (job-roles.js) own
/// `hasOwnProperty` idiom on the other end. `isActive` rides in [changes]
/// too: retiring or reactivating a job role is a correction, not a
/// dedicated verb the way an Employee's departure is (job-roles.js's own
/// header — there is no delete, and no second action here for it).
class JobRolesCorrectionConfirmed extends JobRolesEvent {
  const JobRolesCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class JobRolesState {
  const JobRolesState();
}

class JobRolesLoading extends JobRolesState {
  const JobRolesLoading();
}

/// The catalogue as it last read. An empty [jobRoles] is not a state of its
/// own — the same reasoning `DirectoryLoaded` gives its own empty list.
class JobRolesLoaded extends JobRolesState {
  const JobRolesLoaded({required this.jobRoles, this.isMutating = false, this.mutationFailure});

  final List<JobRole> jobRoles;

  /// An add or a correction is in flight — one flag, not two, the same
  /// reasoning `EmployeeDetailLoaded.isMutating` gives its own record: this
  /// Screen has one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever
  /// dialog is open, which stays open so the caller can fix the field rather
  /// than retype the whole job role.
  final String? mutationFailure;

  JobRolesLoaded copyWith({List<JobRole>? jobRoles, bool? isMutating, String? mutationFailure}) =>
      JobRolesLoaded(
        jobRoles: jobRoles ?? this.jobRoles,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `DirectoryLoaded.copyWith` gives `addFailure`.
        mutationFailure: mutationFailure,
      );
}

class JobRolesUnavailable extends JobRolesState {
  const JobRolesUnavailable({required this.message});

  final String message;
}

class JobRolesBloc extends Bloc<JobRolesEvent, JobRolesState> {
  JobRolesBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const JobRolesLoading()) {
    on<JobRolesStarted>(_onStarted);
    on<JobRolesAddConfirmed>(_onAddConfirmed);
    on<JobRolesCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(JobRolesStarted event, Emitter<JobRolesState> emit) async {
    emit(const JobRolesLoading());
    await _readList(emit);
  }

  // Deactivated rows included (`includeInactive: true`): unlike the
  // Directory's own filter and the assignment dialog's own dropdown, this
  // Screen's whole purpose is reaching a retired row to reactivate it.
  Future<void> _readList(Emitter<JobRolesState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const JobRolesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final jobRoles = await _api.fetchJobRoles(token, includeInactive: true);
      final settled = state;
      emit(
        settled is JobRolesLoaded
            ? settled.copyWith(jobRoles: jobRoles, isMutating: false)
            : JobRolesLoaded(jobRoles: jobRoles),
      );
    } on PeopleApiException catch (error) {
      emit(JobRolesUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(JobRolesAddConfirmed event, Emitter<JobRolesState> emit) async {
    final current = state;
    if (current is! JobRolesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createJobRole(token, code: event.code, name: event.name);
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! JobRolesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    JobRolesCorrectionConfirmed event,
    Emitter<JobRolesState> emit,
  ) async {
    final current = state;
    if (current is! JobRolesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateJobRole(token, event.id, event.changes);
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! JobRolesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
