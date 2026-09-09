/// The job role catalogue (issue #88, ADR-0005's shared catalogue,
/// CONTEXT.md's Job role entry): every job role the plant recognises, laid
/// over an administrator's own write surface for it (`POST`/
/// `PATCH /api/people/job-roles`, job-role-routes.js).
///
/// Offered to every approved Account, the same openness `DirectoryScreen`
/// already has: `GET /api/people/job-roles` carries no admin or scope check
/// of its own (job-role-routes.js's own header), so hiding this Screen behind
/// a role would gate a destination the route itself never refuses. Only the
/// write affordances inside it ([isAdmin]) are gated — the same shape
/// `EmployeeDetailScreen` already uses for its own administrator-only writes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'job_role.dart';
import 'job_role_form_dialog.dart';
import 'job_roles_bloc.dart';

class JobRolesScreen extends StatelessWidget {
  const JobRolesScreen({super.key, required this.isAdmin});

  /// Whether this caller may add or correct a job role — read off `/me`'s
  /// own role, the same shape `DirectoryScreen.isAdmin` follows.
  final bool isAdmin;

  static const double maxWidth = 700;

  static const ValueKey<String> addKey = ValueKey<String>('job-roles-add');
  static const ValueKey<String> failedKey = ValueKey<String>('job-roles-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('job-roles-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('job-roles-empty');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('job-roles-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('job-roles-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('job-roles-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JobRolesBloc>().state;

    return Scaffold(
      body: switch (state) {
        JobRolesLoading() => const Center(child: CircularProgressIndicator()),
        JobRolesUnavailable(message: final message) => _Failed(message: message),
        JobRolesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final JobRolesLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: JobRolesScreen.maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Job roles', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What an Employee does — defined once, shared by every Site.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: JobRolesScreen.addKey,
                    onPressed: state.isMutating ? null : () => JobRoleFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add job role'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.jobRoles.isEmpty)
              Text(
                'No job role has been defined yet.',
                key: JobRolesScreen.emptyKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final jobRole in state.jobRoles)
                      _JobRoleRow(jobRole: jobRole, isAdmin: isAdmin, isMutating: state.isMutating),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JobRoleRow extends StatelessWidget {
  const _JobRoleRow({required this.jobRole, required this.isAdmin, required this.isMutating});

  final JobRole jobRole;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: JobRolesScreen.rowKey(jobRole.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '${jobRole.name} · ${jobRole.code}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (!jobRole.isActive) ...[
                  const SizedBox(width: Spacing.sm),
                  Chip(
                    key: JobRolesScreen.inactiveChipKey(jobRole.id),
                    label: const Text('Inactive'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle:
                        theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin)
            OutlinedButton(
              key: JobRolesScreen.correctKey(jobRole.id),
              onPressed: isMutating ? null : () => JobRoleFormDialog.open(context, jobRole: jobRole),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: JobRolesScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The job role catalogue could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: JobRolesScreen.retryKey,
                onPressed: () => context.read<JobRolesBloc>().add(const JobRolesStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
