/// One Safety observation (issue #230): what was seen, where, when, and how
/// bad it could have been.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so
/// this Screen gates nothing about reading it. There is no injury-style
/// restriction here the way `SafetyIncidentDetailScreen` has: an observation
/// names nobody's health information, so every field on the record renders
/// for every reader.
///
/// **An observation has no status, no event history and no closure** (#223
/// decision 9). This Screen offers nothing to change it — it is a fact — and
/// raising an Action from one is #231, out of scope here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'observation_detail_bloc.dart';

class SafetyObservationDetailScreen extends StatelessWidget {
  const SafetyObservationDetailScreen({super.key, required this.observationId});

  final String observationId;

  static const double maxWidth = 900;

  static const ValueKey<String> backKey = ValueKey<String>('safety-observation-back');
  static const ValueKey<String> potentialKey =
      ValueKey<String>('safety-observation-detail-potential');
  static const ValueKey<String> stopWorkKey =
      ValueKey<String>('safety-observation-detail-stop-work');
  static const ValueKey<String> filedKey = ValueKey<String>('safety-observation-detail-filed');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-observation-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-observation-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('safety-observation-detail-missing');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyObservationDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        SafetyObservationDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
        SafetyObservationDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Safety observation',
            message: 'Nothing is recorded at this address. It may have been removed, or '
                'the address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Safety observations',
            actionKey: backKey,
            onAction: () => context.go(Routes.safetyObservations),
          ),
        SafetyObservationDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'The Safety observation could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<SafetyObservationDetailBloc>()
                .add(const SafetyObservationDetailRefreshed()),
          ),
        SafetyObservationDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SafetyObservationDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = state.observation;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: SafetyObservationDetailScreen.backKey,
                onPressed: () => context.go(Routes.safetyObservations),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Safety observations'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(row.observationTypeLabel, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: SafetyObservationDetailScreen.potentialKey,
                  label: row.severityPotentialLabel,
                  tone: row.severityPotentialTone,
                ),
                if (row.isStopWork)
                  Chip(
                    key: SafetyObservationDetailScreen.stopWorkKey,
                    label: const Text('Stop-work'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What was seen', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    _Fact(label: 'Category', value: row.categoryLabel),
                    _Fact(label: 'Org Unit', value: row.orgUnitName),
                    _Fact(
                      label: 'Filed against',
                      key: SafetyObservationDetailScreen.filedKey,
                      value: row.filedAgainst,
                    ),
                    _Fact(label: 'Observed at', value: row.observedAt ?? 'Not recorded'),
                    _Fact(label: 'Description', value: row.description ?? 'None given'),
                    _Fact(
                      label: 'Action taken',
                      value: row.actionTaken ?? 'None recorded yet',
                    ),
                    _Fact(label: 'Recorded by', value: row.recordedByLabel),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
