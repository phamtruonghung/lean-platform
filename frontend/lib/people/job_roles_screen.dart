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

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'job_role.dart';
import 'job_role_form_dialog.dart';
import 'job_roles_bloc.dart';

class JobRolesScreen extends StatelessWidget {
  const JobRolesScreen({super.key, required this.isAdmin});

  /// Whether this caller may add or correct a job role — read off `/me`'s
  /// own role, the same shape `DirectoryScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189). This Screen used to declare
  /// 700 while the Directory and Org Units declared 900, which is why a
  /// catalogue page read as a narrower app than the two pages either side of
  /// it; the number now comes from [AppLayout.pageWidth].
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('job-roles-add');
  static const ValueKey<String> failedKey = ValueKey<String>('job-roles-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('job-roles-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('job-roles-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('job-roles-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('job-roles-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('job-roles-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('job-roles-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JobRolesBloc>().state;

    return Scaffold(
      body: switch (state) {
        // A generalised loading placeholder (issue #103) replaces the bare
        // spinner this Screen used before — six rows is the same default
        // `SkeletonList` itself defaults to, and this catalogue is rarely
        // long enough to need more.
        JobRolesLoading() => const SkeletonList(maxWidth: JobRolesScreen.maxWidth),
        JobRolesUnavailable(message: final message) => PlatformFailureState(
            key: JobRolesScreen.failedKey,
            title: 'The job role catalogue could not be read',
            message: message,
            retryKey: JobRolesScreen.retryKey,
            onRetry: () => context.read<JobRolesBloc>().add(const JobRolesStarted()),
          ),
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
      child: AppPageFrame(
        maxWidth: JobRolesScreen.maxWidth,
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
              // No "none matched" variant here (issue #103): this catalogue
              // carries no filter to clear, only a whole-catalogue read, so
              // there is only ever the one empty story to tell.
              PlatformEmptyState.noneExist(
                key: JobRolesScreen.emptyKey,
                title: 'No job roles yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.badge_outlined,
                actionLabel: isAdmin ? 'Add job role' : null,
                actionKey: JobRolesScreen.emptyAddKey,
                onAction: isAdmin ? () => JobRoleFormDialog.open(context) : null,
              )
            else
              // One row per job role, ruled apart from its neighbours — the
              // catalogue's record has an edge to follow across the page now
              // (issue #189), rather than six lines of undifferentiated white.
              AppListCard(
                rows: [
                  for (final jobRole in state.jobRoles)
                    _JobRoleRow(jobRole: jobRole, isAdmin: isAdmin, isMutating: state.isMutating),
                ],
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
                  StatusChip(key: JobRolesScreen.inactiveChipKey(jobRole.id), label: 'Inactive', tone: StatusTone.neutral),
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

