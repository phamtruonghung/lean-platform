/// A Site's skill coverage (issue #89, AC6): where the plant is short against
/// the skill requirements it has set for itself. Administrator only —
/// `GET /api/people/sites/:siteId/skill-coverage` is deliberately narrower
/// than every other Site-shaped read in this Module (skill-routes.js's own
/// header), so this Screen carries the same per-Screen access check
/// `AccountsScreen`/`ApprovalQueueScreen` already get at the router, not
/// merely an omission from the sidebar.
///
/// Already filtered to a real shortfall server-side (`SkillCoverageEntry`'s
/// own header) — every row this Screen shows is thin by construction, so
/// there is no "met" row to distinguish from a thin one here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'skill.dart';
import 'skill_coverage_bloc.dart';

class SkillCoverageScreen extends StatelessWidget {
  const SkillCoverageScreen({super.key});

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 760, one of five numbers six catalogue Screens each picked for themselves.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> siteKey = ValueKey<String>('skill-coverage-site');
  static const ValueKey<String> failedKey = ValueKey<String>('skill-coverage-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('skill-coverage-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('skill-coverage-empty');
  static ValueKey<String> rowKey(String orgUnitId, String skillId) =>
      ValueKey<String>('skill-coverage-row-$orgUnitId-$skillId');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'skill-coverage-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's shortfalls renders — a
  /// different fact from [emptyKey] ("every requirement is met"): a Site can
  /// be short somewhere and still have nothing matching what was typed.
  static const ValueKey<String> noMatchKey = ValueKey<String>('skill-coverage-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SkillCoverageBloc>().state;

    return Scaffold(
      body: switch (state) {
        // The generalised loading placeholder (issue #103) replaces the bare
        // spinner this Screen used before.
        SkillCoverageLoading() => const SkeletonList(maxWidth: SkillCoverageScreen.maxWidth),
        SkillCoverageUnavailable(message: final message) => PlatformFailureState(
            key: SkillCoverageScreen.failedKey,
            title: 'Skill coverage could not be read',
            message: message,
            retryKey: SkillCoverageScreen.retryKey,
            onRetry: () => context.read<SkillCoverageBloc>().add(const SkillCoverageStarted()),
          ),
        SkillCoverageLoaded() => _Loaded(state: state),
      },
    );
  }
}

/// The report's loaded view. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state});

  final SkillCoverageLoaded state;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the shortfalls to, `''` when nothing is.
  String _term = '';

  /// Whether [entry] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the names that identify a shortfall —
  /// the Org Unit that is short and the skill it is short of (their codes
  /// included, since that is how a plan is read in a spreadsheet). No ranking
  /// and no fuzzy matching, the same rule the assign dialog's own filter uses
  /// (issue #187).
  static bool _matches(SkillCoverageEntry entry, String term) =>
      entry.orgUnitName.toLowerCase().contains(term) ||
      entry.orgUnitCode.toLowerCase().contains(term) ||
      entry.skillName.toLowerCase().contains(term) ||
      entry.skillCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<SkillCoverageEntry> get _matchingEntries {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.entries;
    return widget.state.entries
        .where((entry) => _matches(entry, term))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingEntries;
    return Center(
      child: AppPageFrame(
        maxWidth: SkillCoverageScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Text('Skill coverage', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              'Where this Site falls short of its own skill requirements.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (state.sites.length > 1) ...[
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: SkillCoverageScreen.siteKey,
                  initialValue: state.siteId,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                  items: [
                    for (final site in state.sites)
                      DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (siteId) {
                    if (siteId == null) return;
                    context.read<SkillCoverageBloc>().add(SkillCoverageSiteSelected(siteId));
                  },
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            if (state.isLoadingCoverage)
              const SkeletonList(rows: 3, maxWidth: SkillCoverageScreen.maxWidth)
            else if (state.entries.isEmpty)
              // Good news, not a gap to fill — this read is already
              // filtered to a real shortfall server-side (`SkillCoverageEntry`'s
              // own header), so an empty result means every requirement is
              // met, not that nobody has entered anything yet. No action to
              // carry either way: there is nothing here for a caller to
              // create, and no filter to clear (issue #103).
              PlatformEmptyState.noneExist(
                key: SkillCoverageScreen.emptyKey,
                title: 'Every requirement is met',
                message: 'This Site has no shortfall against the skill requirements it has set '
                    'for itself.',
                icon: Icons.task_alt_outlined,
              )
            else ...[
              // A filter box over a Site with no shortfall would be a control
              // that can do nothing, so it appears with the rows — and stays
              // while a term excludes them all, because the reader still has
              // to be able to clear it.
              AppFilterField(
                name: SkillCoverageScreen.filterFieldName,
                label: 'Filter skill coverage',
                helperText: 'By Org Unit or skill.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: state.entries.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: SkillCoverageScreen.noMatchKey,
                  title: 'No shortfalls match',
                  message: 'This Site is short somewhere, but nothing matches '
                      '"${_term.trim()}". Try a different Org Unit or skill, or clear the '
                      'filter.',
                )
              else
                // One row per requirement, ruled apart from its neighbours
                // (issue #189).
                AppListCard(
                  rows: [for (final entry in matches) _CoverageRow(entry: entry)],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.entry});

  final SkillCoverageEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: SkillCoverageScreen.rowKey(entry.orgUnitId, entry.skillId),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.orgUnitName} · ${entry.skillName}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Needs ${entry.minimumQualifiedHeadcount} at level ${entry.minimumLevel}+, '
                  '${entry.qualifiedHeadcount} qualified, ${entry.expiredHeadcount} lapsed',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Chip(
            label: Text('Short ${entry.shortfall}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: theme.colorScheme.errorContainer,
            labelStyle: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

