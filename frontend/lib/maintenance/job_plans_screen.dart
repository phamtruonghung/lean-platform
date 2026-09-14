/// The Job plan catalogue (issue #74): every reusable description of a
/// recurring job, each with its ordered steps, laid over an administrator's
/// own write surface for it (`POST`/`PATCH /api/maintenance/job-plans`).
///
/// CONTEXT.md's distinction is load-bearing in the copy: a Job plan is the
/// instructions, the Work order that carries it out is one particular occasion
/// of following them. The read is open to any approved Account
/// (job-plan-routes.js's own header); the write affordances inside — adding a
/// plan, deactivating or reactivating one — are offered only to an
/// administrator ([isAdmin]), since the server refuses them for every other
/// role. A non-administrator sees the catalogue and no way to change it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'job_plan.dart';
import 'job_plan_form_dialog.dart';
import 'job_plans_bloc.dart';

class JobPlansScreen extends StatelessWidget {
  const JobPlansScreen({super.key, required this.isAdmin});

  /// Whether this caller may add, deactivate or reactivate a plan — read off
  /// `/me`'s own role, the same shape `SkillsScreen.isAdmin` follows.
  final bool isAdmin;

  static const double maxWidth = 960;

  static const ValueKey<String> addKey = ValueKey<String>('job-plans-add');
  static const ValueKey<String> noticeKey = ValueKey<String>('job-plans-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('job-plans-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('job-plans-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('job-plans-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('job-plan-row-$id');
  static ValueKey<String> toggleKey(String id) => ValueKey<String>('job-plan-toggle-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('job-plan-inactive-$id');
  static ValueKey<String> taskKey(String planId, String taskId) =>
      ValueKey<String>('job-plan-task-$planId-$taskId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JobPlansBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, isAdmin: isAdmin),
          if (state is JobPlansLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              JobPlansLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              JobPlansUnavailable(message: final message) => PlatformFailureState(
                  key: JobPlansScreen.failedKey,
                  title: 'The Job plans could not be read',
                  message: message,
                  retryKey: JobPlansScreen.retryKey,
                  onRetry: () => context.read<JobPlansBloc>().add(const JobPlansStarted()),
                ),
              JobPlansLoaded(plans: final plans) when plans.isEmpty => const _JobPlansEmpty(),
              JobPlansLoaded(plans: final plans) => _JobPlansList(plans: plans, isAdmin: isAdmin),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.isAdmin});

  final JobPlansState state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is JobPlansLoaded ? state as JobPlansLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: JobPlansScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Job plans', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'How each recurring job is done — the steps it takes and what each one '
                      'requires. A Work order follows a plan; it does not change one.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (isAdmin && loaded != null)
                FilledButton.icon(
                  key: JobPlansScreen.addKey,
                  onPressed: loaded.isMutating ? null : () => JobPlanFormDialog.open(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a Job plan'),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: JobPlansScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: JobPlansScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobPlansList extends StatelessWidget {
  const _JobPlansList({required this.plans, required this.isAdmin});

  final List<JobPlan> plans;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: JobPlansScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: plans.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _JobPlanCard(plan: plans[index], isAdmin: isAdmin),
        ),
      ),
    );
  }
}

class _JobPlanCard extends StatelessWidget {
  const _JobPlanCard({required this.plan, required this.isAdmin});

  final JobPlan plan;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final state = context.watch<JobPlansBloc>().state;
    final busy = state is JobPlansLoaded && state.isMutating;

    return Card(
      key: JobPlansScreen.rowKey(plan.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text('${plan.code} · ${plan.workTypeLabel}', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                if (!plan.isActive)
                  Chip(
                    key: JobPlansScreen.inactiveChipKey(plan.id),
                    label: const Text('Inactive'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
              ],
            ),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(plan.description!, style: theme.textTheme.bodyMedium),
            ],
            if (plan.requiresShutdown || plan.estimatedHours != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  if (plan.requiresShutdown) 'Requires a shutdown',
                  if (plan.estimatedHours != null) 'About ${plan.estimatedHours} h',
                ].join(' · '),
                style: muted,
              ),
            ],
            const SizedBox(height: Spacing.md),
            if (plan.tasks.isEmpty)
              Text('No steps recorded.', style: muted)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final task in plan.tasks)
                    _JobPlanTaskRow(plan: plan, task: task),
                ],
              ),
            if (isAdmin) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: JobPlansScreen.toggleKey(plan.id),
                onPressed: busy
                    ? null
                    : () => context.read<JobPlansBloc>().add(
                          JobPlanActiveToggled(jobPlanId: plan.id, isActive: !plan.isActive),
                        ),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(plan.isActive ? 'Deactivate' : 'Reactivate'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One step: its number and instruction, and the required Skill's name when
/// one is set — the fact the ticket's own criterion asks to be visible.
class _JobPlanTaskRow extends StatelessWidget {
  const _JobPlanTaskRow({required this.plan, required this.task});

  final JobPlan plan;
  final JobPlanTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      key: JobPlansScreen.taskKey(plan.id, task.id),
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text('${task.stepNo}.', style: muted),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.instruction, style: theme.textTheme.bodyMedium),
                if (task.hasSkill)
                  Text('Requires ${task.skillName}', style: muted)
                else
                  Text('No skill required', style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobPlansEmpty extends StatelessWidget {
  const _JobPlansEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: JobPlansScreen.emptyKey,
      title: 'No Job plans yet',
      message: 'No reusable job plan has been defined. Add one and its steps will show here.',
    );
  }
}
