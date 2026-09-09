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
import 'skill.dart';
import 'skill_coverage_bloc.dart';

class SkillCoverageScreen extends StatelessWidget {
  const SkillCoverageScreen({super.key});

  static const double maxWidth = 760;

  static const ValueKey<String> siteKey = ValueKey<String>('skill-coverage-site');
  static const ValueKey<String> failedKey = ValueKey<String>('skill-coverage-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('skill-coverage-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('skill-coverage-empty');
  static ValueKey<String> rowKey(String orgUnitId, String skillId) =>
      ValueKey<String>('skill-coverage-row-$orgUnitId-$skillId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SkillCoverageBloc>().state;

    return Scaffold(
      body: switch (state) {
        SkillCoverageLoading() => const Center(child: CircularProgressIndicator()),
        SkillCoverageUnavailable(message: final message) => _Failed(message: message),
        SkillCoverageLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SkillCoverageLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SkillCoverageScreen.maxWidth),
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
              const Center(child: CircularProgressIndicator())
            else if (state.entries.isEmpty)
              Text(
                'Every skill requirement at this Site is met.',
                key: SkillCoverageScreen.emptyKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [for (final entry in state.entries) _CoverageRow(entry: entry)],
                ),
              ),
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
            labelStyle: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
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
      key: SkillCoverageScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('Skill coverage could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: SkillCoverageScreen.retryKey,
                onPressed: () => context.read<SkillCoverageBloc>().add(const SkillCoverageStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
