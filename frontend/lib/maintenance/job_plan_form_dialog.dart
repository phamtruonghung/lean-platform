/// Creating a Job plan (issue #74): the plan's own fields and a dynamic list
/// of the steps that make it up, each with an optional required Skill.
///
/// CONTEXT.md's own line is the point of this form: a Job plan is the
/// reusable description of how a recurring job is done — the instructions kept
/// once and followed every time the job comes round again. It is
/// administrator-only server-side (job-plan-routes.js's own `requireAdmin`),
/// and the Screen only opens it for an administrator.
///
/// The Skill picker reads the same People catalogue the skills feature already
/// reads (`PeopleApi.fetchSkills`) — no second source is invented for it. A
/// step that requires no Skill simply omits `skillId` on the wire.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/skill.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'job_plan.dart';
import 'job_plans_bloc.dart';
import 'work_order.dart' show WorkType;

class JobPlanFormDialog extends StatefulWidget {
  const JobPlanFormDialog({super.key});

  static const ValueKey<String> codeKey = ValueKey<String>('job-plan-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('job-plan-form-name');
  static const ValueKey<String> descriptionKey = ValueKey<String>('job-plan-form-description');
  static const ValueKey<String> workTypeKey = ValueKey<String>('job-plan-form-work-type');
  static const ValueKey<String> estimatedHoursKey = ValueKey<String>('job-plan-form-estimated-hours');
  static const ValueKey<String> requiresShutdownKey =
      ValueKey<String>('job-plan-form-requires-shutdown');
  static const ValueKey<String> safetyNoteKey = ValueKey<String>('job-plan-form-safety-note');
  static const ValueKey<String> addTaskKey = ValueKey<String>('job-plan-form-add-task');
  static const ValueKey<String> submitKey = ValueKey<String>('job-plan-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('job-plan-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('job-plan-form-failure');
  static const ValueKey<String> skillsFailedKey = ValueKey<String>('job-plan-form-skills-failed');

  static ValueKey<String> taskStepKey(int index) => ValueKey<String>('job-plan-task-step-$index');
  static ValueKey<String> taskInstructionKey(int index) =>
      ValueKey<String>('job-plan-task-instruction-$index');
  static ValueKey<String> taskSkillKey(int index) => ValueKey<String>('job-plan-task-skill-$index');
  static ValueKey<String> taskEstimatedHoursKey(int index) =>
      ValueKey<String>('job-plan-task-hours-$index');
  static ValueKey<String> removeTaskKey(int index) => ValueKey<String>('job-plan-task-remove-$index');

  /// Opens the form over the catalogue — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider<JobPlansBloc>`.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<JobPlansBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<JobPlansBloc>.value(
        value: bloc,
        child: const JobPlanFormDialog(),
      ),
    );
  }

  @override
  State<JobPlanFormDialog> createState() => _JobPlanFormDialogState();
}

enum _SkillsStatus { loading, ready, failed }

/// One editable step's own controllers and chosen Skill — held together so
/// adding and removing a row is one list operation rather than four parallel
/// lists that could drift apart.
class _TaskDraft {
  _TaskDraft({required this.stepNo, required this.instruction, required this.estimatedHours});

  final TextEditingController stepNo;
  final TextEditingController instruction;
  final TextEditingController estimatedHours;
  String? skillId;

  void dispose() {
    stepNo.dispose();
    instruction.dispose();
    estimatedHours.dispose();
  }
}

class _JobPlanFormDialogState extends State<JobPlanFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _estimatedHours = TextEditingController();
  final TextEditingController _safetyNote = TextEditingController();

  WorkType _workType = jobPlanWorkTypes.first;
  bool _requiresShutdown = false;

  final List<_TaskDraft> _tasks = [];
  _SkillsStatus _skillsStatus = _SkillsStatus.loading;
  List<Skill> _skills = const [];
  String? _skillsFailure;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _tasks.add(_newTask());
    _loadSkills();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _estimatedHours.dispose();
    _safetyNote.dispose();
    for (final task in _tasks) {
      task.dispose();
    }
    super.dispose();
  }

  _TaskDraft _newTask() => _TaskDraft(
        stepNo: TextEditingController(text: '${_tasks.length + 1}'),
        instruction: TextEditingController(),
        estimatedHours: TextEditingController(),
      );

  Future<void> _loadSkills() async {
    setState(() {
      _skillsStatus = _SkillsStatus.loading;
      _skillsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _skillsStatus = _SkillsStatus.failed;
        _skillsFailure = JobPlansBloc.signedOutMessage;
      });
      return;
    }
    try {
      final skills = await context.read<PeopleApi>().fetchSkills(token);
      if (!mounted) return;
      setState(() {
        _skills = skills;
        _skillsStatus = _SkillsStatus.ready;
      });
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _skillsStatus = _SkillsStatus.failed;
        _skillsFailure = error.message;
      });
    }
  }

  num? _parseOptionalNumber(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : num.tryParse(trimmed);
  }

  /// Whether every field the server requires is present and every entered
  /// number parses. A step's estimated hours and required Skill are both
  /// optional; a step with no instruction is not a step.
  bool get _complete {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) return false;
    if (_estimatedHours.text.trim().isNotEmpty && _parseOptionalNumber(_estimatedHours.text) == null) {
      return false;
    }
    for (final task in _tasks) {
      if (task.instruction.text.trim().isEmpty) return false;
      final stepNo = int.tryParse(task.stepNo.text.trim());
      if (stepNo == null || stepNo < 1) return false;
      final hours = task.estimatedHours.text.trim();
      if (hours.isNotEmpty && _parseOptionalNumber(hours) == null) return false;
    }
    return true;
  }

  void _addTask() => setState(() => _tasks.add(_newTask()));

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index).dispose();
    });
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    final safetyNote = _safetyNote.text.trim();
    context.read<JobPlansBloc>().add(
          JobPlanCreateConfirmed(
            code: _code.text.trim(),
            name: _name.text.trim(),
            workType: _workType.wire,
            description: description.isEmpty ? null : description,
            estimatedHours: _parseOptionalNumber(_estimatedHours.text),
            requiresShutdown: _requiresShutdown,
            safetyNote: safetyNote.isEmpty ? null : safetyNote,
            tasks: [
              for (final task in _tasks)
                JobPlanTaskDraft(
                  stepNo: int.parse(task.stepNo.text.trim()),
                  instruction: task.instruction.text.trim(),
                  skillId: task.skillId,
                  estimatedHours: _parseOptionalNumber(task.estimatedHours.text),
                ),
            ],
          ),
        );
  }

  void _onJobPlansChanged(BuildContext context, JobPlansState state) {
    if (!_awaiting || state is! JobPlansLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<JobPlansBloc, JobPlansState>(
      listener: _onJobPlansChanged,
      child: AlertDialog(
        title: const Text('Add a Job plan'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: JobPlanFormDialog.codeKey,
                  controller: _code,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: JobPlanFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<WorkType>(
                  key: JobPlanFormDialog.workTypeKey,
                  initialValue: _workType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kind of work',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final choice in jobPlanWorkTypes)
                      DropdownMenuItem<WorkType>(value: choice, child: Text(choice.label)),
                  ],
                  onChanged:
                      _awaiting ? null : (value) => setState(() => _workType = value!),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: JobPlanFormDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: JobPlanFormDialog.estimatedHoursKey,
                  controller: _estimatedHours,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Estimated hours (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                SwitchListTile(
                  key: JobPlanFormDialog.requiresShutdownKey,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires a shutdown'),
                  value: _requiresShutdown,
                  onChanged:
                      _awaiting ? null : (value) => setState(() => _requiresShutdown = value),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: JobPlanFormDialog.safetyNoteKey,
                  controller: _safetyNote,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Safety note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Steps', style: theme.textTheme.titleSmall),
                    ),
                    TextButton.icon(
                      key: JobPlanFormDialog.addTaskKey,
                      onPressed: _awaiting ? null : _addTask,
                      icon: const Icon(Icons.add),
                      label: const Text('Add a step'),
                    ),
                  ],
                ),
                if (_skillsStatus == _SkillsStatus.failed)
                  Padding(
                    key: JobPlanFormDialog.skillsFailedKey,
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _skillsFailure ?? 'The skill catalogue could not be read.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                        TextButton(
                          onPressed: _awaiting ? null : _loadSkills,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                for (var index = 0; index < _tasks.length; index++)
                  _TaskFields(
                    key: ObjectKey(_tasks[index]),
                    index: index,
                    task: _tasks[index],
                    skills: _skills,
                    skillsReady: _skillsStatus == _SkillsStatus.ready,
                    enabled: !_awaiting,
                    canRemove: _tasks.length > 1,
                    onChanged: () => setState(() {}),
                    onSkillChanged: (skillId) => setState(() => _tasks[index].skillId = skillId),
                    onRemove: () => _removeTask(index),
                  ),
                if (_failure != null)
                  Padding(
                    key: JobPlanFormDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: JobPlanFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: JobPlanFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Add plan'),
          ),
        ],
      ),
    );
  }
}

/// One step's own fields — step number, instruction, optional required Skill
/// and optional estimated hours — plus its remove affordance once there is
/// more than one step.
class _TaskFields extends StatelessWidget {
  const _TaskFields({
    super.key,
    required this.index,
    required this.task,
    required this.skills,
    required this.skillsReady,
    required this.enabled,
    required this.canRemove,
    required this.onChanged,
    required this.onSkillChanged,
    required this.onRemove,
  });

  final int index;
  final _TaskDraft task;
  final List<Skill> skills;
  final bool skillsReady;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onChanged;
  final ValueChanged<String?> onSkillChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  key: JobPlanFormDialog.taskStepKey(index),
                  controller: task.stepNo,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Step', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: TextField(
                  key: JobPlanFormDialog.taskInstructionKey(index),
                  controller: task.instruction,
                  enabled: enabled,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Instruction',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (canRemove)
                IconButton(
                  key: JobPlanFormDialog.removeTaskKey(index),
                  tooltip: 'Remove this step',
                  icon: const Icon(Icons.close),
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: JobPlanFormDialog.taskSkillKey(index),
                  initialValue: task.skillId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Required skill (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final skill in skills)
                      DropdownMenuItem<String>(value: skill.id, child: Text(skill.name)),
                  ],
                  // Disabled until the catalogue answers — the control is a
                  // known set, so it never falls back to free text (ADR-0023).
                  onChanged: enabled && skillsReady ? onSkillChanged : null,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              SizedBox(
                width: 160,
                child: TextField(
                  key: JobPlanFormDialog.taskEstimatedHoursKey(index),
                  controller: task.estimatedHours,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Hours (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
