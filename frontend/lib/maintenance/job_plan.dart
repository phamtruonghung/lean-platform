/// One Job plan as `GET /api/maintenance/job-plans` and
/// `GET /api/maintenance/job-plans/:id` send it (issue #74).
///
/// CONTEXT.md's own distinction is the whole point of this model: a Job plan
/// is the reusable description of how a recurring job is done — the steps it
/// takes and what each one requires — kept once and used every time that job
/// comes around again. It is deliberately distinct from the Work order that
/// carries it out: the plan is the instructions, the work order is one
/// particular occasion of following them, and a plan revised next year cannot
/// rewrite what a technician was told to do last year (the tasks are copied
/// onto the work order at raise time).
library;

import 'package:flutter/foundation.dart';

import 'work_order.dart' show WorkType;

/// The four kinds of work a Job plan may describe, mirroring the CHECK
/// constraint on `job_plans.work_type` and `job-plans.js`'s own
/// `JOB_PLAN_WORK_TYPES`. Deliberately narrower than [WorkType]: a generated
/// job plan describes planned work, so `corrective` and `improvement` are not
/// offered here.
const List<WorkType> jobPlanWorkTypes = [
  WorkType.preventive,
  WorkType.predictive,
  WorkType.inspection,
  WorkType.calibration,
];

/// One step inside a Job plan — an instruction, the Skill it requires (if
/// any), and how long it is expected to take. Mirrors `toJobPlanTask`
/// (job-plans.js) key for key: `skillName` is resolved by the server's own
/// join onto People's `skills` table, so the client never looks a Skill up
/// separately.
@immutable
class JobPlanTask {
  const JobPlanTask({
    required this.id,
    required this.stepNo,
    required this.instruction,
    required this.skillId,
    required this.skillName,
    required this.estimatedHours,
  });

  final String id;

  /// The step's own order within the plan — the server orders by it.
  final int stepNo;
  final String instruction;

  /// The required Skill's id, or null when the step requires none.
  final String? skillId;
  final String? skillName;
  final num? estimatedHours;

  /// Whether this step names a required Skill worth showing.
  bool get hasSkill => skillName != null && skillName!.isNotEmpty;
}

/// The draft of one step a caller is adding to a Job plan, on its way to
/// `POST /api/maintenance/job-plans` (issue #74). Distinct from
/// [JobPlanTask]: an unsaved step has no server-issued id and no resolved
/// [JobPlanTask.skillName], only the Skill id that was chosen. The create
/// call sends these directly.
@immutable
class JobPlanTaskDraft {
  const JobPlanTaskDraft({
    required this.stepNo,
    required this.instruction,
    this.skillId,
    this.estimatedHours,
  });

  final int stepNo;
  final String instruction;

  /// The required Skill's id, or null when the step requires none.
  final String? skillId;
  final num? estimatedHours;
}

@immutable
class JobPlan {
  const JobPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.workType,
    required this.estimatedHours,
    required this.requiresShutdown,
    required this.safetyNote,
    required this.isActive,
    required this.tasks,
  });

  final String id;
  final String code;
  final String name;
  final String? description;

  /// The wire string, not the enum: a work type this build does not know
  /// about still renders rather than throwing — the same reasoning
  /// `WorkOrder.workType` keeps it as a wire string for.
  final String workType;

  final num? estimatedHours;
  final bool requiresShutdown;
  final String? safetyNote;

  /// False once deactivated. Deactivation is not deletion (job-plans.js's own
  /// header): a plan stays readable and a Work order already copied from it
  /// keeps its tasks.
  final bool isActive;

  /// The ordered steps. Populated on both the list and the single-plan read,
  /// so the catalogue can show a plan's steps without a second request.
  final List<JobPlanTask> tasks;

  /// The human label for [workType] — falls back to the wire string itself
  /// for a work type this build does not know about.
  String get workTypeLabel {
    for (final type in WorkType.values) {
      if (type.wire == workType) return type.label;
    }
    return workType;
  }
}
