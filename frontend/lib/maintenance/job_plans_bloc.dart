/// The Job plan catalogue's state (issue #74): the shared, administrator-
/// managed description of each recurring job, with each plan's ordered steps.
///
/// Route-scoped, like `SkillsBloc`: one Screen's own reading of the server,
/// re-read on arrival rather than restored stale. Reads are open to any
/// approved Account (`GET /api/maintenance/job-plans`, job-plan-routes.js's
/// own header); the two writes it drives — create and deactivate/reactivate —
/// are administrator-only server-side, and the Screen only offers them to an
/// administrator.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'job_plan.dart';
import 'maintenance_api.dart';

sealed class JobPlansEvent {
  const JobPlansEvent();
}

/// Load the whole catalogue, deactivated plans included so an administrator
/// can reach one worth reactivating. Also the retry a failed load offers.
class JobPlansStarted extends JobPlansEvent {
  const JobPlansStarted();
}

/// The create form has decided: a whole new Job plan, with its ordered tasks
/// (issue #74). The dialog decides, the Bloc only ever sees a decision already
/// made.
class JobPlanCreateConfirmed extends JobPlansEvent {
  const JobPlanCreateConfirmed({
    required this.code,
    required this.name,
    required this.workType,
    required this.tasks,
    this.description,
    this.estimatedHours,
    this.requiresShutdown,
    this.safetyNote,
  });

  final String code;
  final String name;
  final String workType;
  final String? description;
  final num? estimatedHours;
  final bool? requiresShutdown;
  final String? safetyNote;
  final List<JobPlanTaskDraft> tasks;
}

/// Deactivate or reactivate one Job plan — one event for both, the same
/// single write (`setJobPlanActive`) either way.
class JobPlanActiveToggled extends JobPlansEvent {
  const JobPlanActiveToggled({required this.jobPlanId, required this.isActive});
  final String jobPlanId;
  final bool isActive;
}

sealed class JobPlansState {
  const JobPlansState();
}

class JobPlansLoading extends JobPlansState {
  const JobPlansLoading();
}

/// The catalogue as it last read. An empty [plans] is not a state of its own —
/// the same reasoning `SkillsLoaded` gives its own empty list.
class JobPlansLoaded extends JobPlansState {
  const JobPlansLoaded({
    required this.plans,
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
  });

  final List<JobPlan> plans;

  /// A create or an active toggle is in flight — one flag, not two, the same
  /// reasoning `SkillsLoaded.isMutating` gives its own catalogue.
  final bool isMutating;

  /// Why the last create did not land. Reported by the open create dialog,
  /// which stays open so the caller can fix the field rather than retype the
  /// whole plan.
  final String? mutationFailure;

  /// What the last act had to say for itself — a create's success, or a
  /// deactivate/reactivate that failed and has no dialog of its own to report
  /// it. Never the failure of a load: that is [JobPlansUnavailable].
  final String? notice;

  JobPlansLoaded copyWith({
    List<JobPlan>? plans,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      JobPlansLoaded(
        plans: plans ?? this.plans,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `SkillsLoaded.copyWith` gives `mutationFailure`.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class JobPlansUnavailable extends JobPlansState {
  const JobPlansUnavailable({required this.message});
  final String message;
}

class JobPlansBloc extends Bloc<JobPlansEvent, JobPlansState> {
  JobPlansBloc({required MaintenanceApi maintenanceApi, required AuthGateway authGateway})
      : _maintenance = maintenanceApi,
        _auth = authGateway,
        super(const JobPlansLoading()) {
    on<JobPlansStarted>(_onStarted);
    on<JobPlanCreateConfirmed>(_onCreateConfirmed);
    on<JobPlanActiveToggled>(_onActiveToggled);
  }

  final MaintenanceApi _maintenance;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(JobPlansStarted event, Emitter<JobPlansState> emit) async {
    emit(const JobPlansLoading());
    await _readList(emit);
  }

  // Deactivated plans included: unlike every other reader of this catalogue,
  // this Screen's whole purpose is reaching a deactivated one to reactivate
  // it — the same reasoning `SkillsBloc._readList` already gives.
  Future<void> _readList(Emitter<JobPlansState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const JobPlansUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final plans = await _maintenance.fetchJobPlans(token);
      final settled = state;
      emit(
        settled is JobPlansLoaded
            ? settled.copyWith(plans: plans, isMutating: false, notice: notice)
            : JobPlansLoaded(plans: plans, notice: notice),
      );
    } on MaintenanceApiException catch (error) {
      emit(JobPlansUnavailable(message: error.message));
    }
  }

  Future<void> _onCreateConfirmed(JobPlanCreateConfirmed event, Emitter<JobPlansState> emit) async {
    final current = state;
    if (current is! JobPlansLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final plan = await _maintenance.createJobPlan(
        token,
        code: event.code,
        name: event.name,
        description: event.description,
        workType: event.workType,
        estimatedHours: event.estimatedHours,
        requiresShutdown: event.requiresShutdown,
        safetyNote: event.safetyNote,
        tasks: event.tasks,
      );
      await _readList(emit, notice: '${plan.name} has been added.');
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! JobPlansLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onActiveToggled(JobPlanActiveToggled event, Emitter<JobPlansState> emit) async {
    final current = state;
    if (current is! JobPlansLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final plan = await _maintenance.setJobPlanActive(
        token,
        event.jobPlanId,
        isActive: event.isActive,
      );
      final settled = state;
      if (settled is! JobPlansLoaded) return;
      // Patched in place rather than re-read: the response already carries the
      // whole plan, so a second read would be one request too many — the same
      // reasoning `WorkOrdersBloc._onAssignConfirmed` follows.
      emit(
        settled.copyWith(
          isMutating: false,
          plans: [
            for (final existing in settled.plans)
              if (existing.id == plan.id) plan else existing,
          ],
          notice: plan.isActive
              ? '${plan.name} has been reactivated.'
              : '${plan.name} has been deactivated.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! JobPlansLoaded) return;
      // Toggling has no dialog to read a failure off, so the refusal surfaces
      // as the ordinary notice instead.
      emit(settled.copyWith(isMutating: false, notice: error.message));
    }
  }
}
