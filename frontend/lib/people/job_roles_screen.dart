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
import '../widgets/app_filter_field.dart';
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

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'job-roles-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the catalogue's rows renders — a different
  /// fact from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('job-roles-no-match');
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

/// The catalogue's loaded view. Stateful only because the filter box's term
/// is the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final JobRolesLoaded state;
  final bool isAdmin;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the catalogue to, `''` when nothing is.
  String _term = '';

  /// Whether [jobRole] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify a job role —
  /// its name and its code. No ranking and no fuzzy matching, the same rule
  /// the assign dialog's own filter uses (issue #187).
  static bool _matches(JobRole jobRole, String term) =>
      jobRole.name.toLowerCase().contains(term) || jobRole.code.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<JobRole> get _matchingJobRoles {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.jobRoles;
    return widget.state.jobRoles
        .where((jobRole) => _matches(jobRole, term))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingJobRoles;
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
                if (widget.isAdmin)
                  FilledButton.icon(
                    key: JobRolesScreen.addKey,
                    onPressed: widget.state.isMutating
                        ? null
                        : () => JobRoleFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add job role'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (widget.state.jobRoles.isEmpty)
              // No "none matched" variant while there is nothing to narrow
              // (issue #103's own distinction, now carried by the filter box
              // above the rows): this catalogue's own empty story is the only
              // one to tell until it has rows.
              PlatformEmptyState.noneExist(
                key: JobRolesScreen.emptyKey,
                title: 'No job roles yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.badge_outlined,
                actionLabel: widget.isAdmin ? 'Add job role' : null,
                actionKey: JobRolesScreen.emptyAddKey,
                onAction: widget.isAdmin ? () => JobRoleFormDialog.open(context) : null,
              )
            else ...[
              AppFilterField(
                name: JobRolesScreen.filterFieldName,
                label: 'Filter job roles',
                helperText: 'By name or code.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.state.jobRoles.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: JobRolesScreen.noMatchKey,
                  title: 'No job roles match',
                  message: 'Nothing in the catalogue matches "${_term.trim()}". Try a '
                      'different name or code, or clear the filter.',
                )
              else
                // One row per job role, ruled apart from its neighbours — the
                // catalogue's record has an edge to follow across the page now
                // (issue #189), rather than six lines of undifferentiated white.
                AppListCard(
                  rows: [
                    for (final jobRole in matches)
                      _JobRoleRow(
                        jobRole: jobRole,
                        isAdmin: widget.isAdmin,
                        isMutating: widget.state.isMutating,
                      ),
                  ],
                ),
            ],
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

