/// One Safety incident (issue #226): what happened, where, when, and where it
/// sits on the severity ladder.
///
/// The record's own number is the title rather than a page heading — the
/// same choice the Non-conformance, Work order and Action detail Screens
/// make, and why this Screen is excluded from `page_alignment_test.dart`'s
/// audit by name rather than audited in it.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so
/// this Screen gates nothing. Nothing here is classified: no injury type, no
/// body part, no severity change and no close — those are issue #224's and
/// #228's own writes, gated on Safety authority, and this slice's detail is
/// read-only.
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
import 'incident_detail_bloc.dart';

class SafetyIncidentDetailScreen extends StatelessWidget {
  const SafetyIncidentDetailScreen({super.key, required this.incidentId});

  final String incidentId;

  static const double maxWidth = 900;

  static const ValueKey<String> backKey = ValueKey<String>('safety-incident-back');
  static const ValueKey<String> statusKey = ValueKey<String>('safety-incident-detail-status');
  static const ValueKey<String> severityKey = ValueKey<String>('safety-incident-detail-severity');
  static const ValueKey<String> recordableKey =
      ValueKey<String>('safety-incident-detail-recordable');
  static const ValueKey<String> filedKey = ValueKey<String>('safety-incident-detail-filed');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-detail-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-incident-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-incident-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('safety-incident-detail-missing');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyIncidentDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        SafetyIncidentDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
        SafetyIncidentDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Safety incident',
            message: 'Nothing is recorded at this address. It may have been removed, or '
                'the address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Safety incidents',
            actionKey: backKey,
            onAction: () => context.go(Routes.safetyIncidents),
          ),
        SafetyIncidentDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'The Safety incident could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<SafetyIncidentDetailBloc>()
                .add(const SafetyIncidentDetailRefreshed()),
          ),
        SafetyIncidentDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SafetyIncidentDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = state.incident;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: SafetyIncidentDetailScreen.backKey,
                onPressed: () => context.go(Routes.safetyIncidents),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Safety incidents'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(row.incidentNo, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: SafetyIncidentDetailScreen.statusKey,
                  label: row.statusLabel,
                  tone: row.statusTone,
                ),
                StatusChip(
                  key: SafetyIncidentDetailScreen.severityKey,
                  label: row.severityLabel,
                  tone: row.severityTone,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              row.isRecordable ? 'Recordable' : 'Not recordable',
              key: SafetyIncidentDetailScreen.recordableKey,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What happened', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    _Fact(label: 'Incident type', value: row.incidentTypeLabel),
                    _Fact(label: 'Org Unit', value: row.orgUnitName),
                    _Fact(
                      label: 'Asset',
                      value:
                          row.assetName == null ? 'None named' : '${row.assetName} · ${row.assetCode}',
                    ),
                    _Fact(
                      label: 'Employee involved',
                      value: row.employeeName ?? 'None named',
                    ),
                    _Fact(
                      label: 'Filed against',
                      key: SafetyIncidentDetailScreen.filedKey,
                      value: row.filedAgainst,
                    ),
                    _Fact(label: 'Occurred at', value: row.occurredAt ?? 'Not recorded'),
                    _Fact(label: 'Reported at', value: row.reportedAt ?? 'Not recorded'),
                    _Fact(label: 'Reported by', value: row.reportedByLabel),
                    _Fact(label: 'Description', value: row.description ?? 'None given'),
                    _Fact(
                      label: 'Immediate action',
                      value: row.immediateAction ?? 'None recorded yet',
                    ),
                    if (row.lostTimeDays > 0)
                      _Fact(label: 'Lost-time days', value: row.lostTimeDays.toString()),
                    if (row.restrictedDays > 0)
                      _Fact(label: 'Restricted days', value: row.restrictedDays.toString()),
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
