/// One Non-conformance (issue #205): what was found, where, how much of it
/// there is, and every step that number has taken since it was written down.
///
/// The record's own number is the title rather than a page heading — a reader
/// has arrived at one Non-conformance, and `NC-HCM-2026-00001` is what it is
/// called everywhere it is quoted. That is the same choice the Work order and
/// Action detail Screens make, and why this Screen is excluded from
/// `page_alignment_test.dart`'s audit by name rather than audited in it.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so
/// this Screen gates nothing. What it *offers* is gated by the server: raising
/// the severity, recording containment and increasing the quantity are all
/// writes at the Org Unit the record sits at, and a caller without a Grant
/// reaching it gets a sentence back rather than a hidden button.
///
/// The three affordances are addressed dialogs (ADR-0021): a refresh lands on
/// the record with the control open, and the change a caller was making is not
/// lost to a stray back-navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'defect_code.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceDetailScreen extends StatelessWidget {
  const NonconformanceDetailScreen({super.key, required this.nonconformanceId});

  final String nonconformanceId;

  static const double maxWidth = 900;

  static const ValueKey<String> backKey = ValueKey<String>('nonconformance-back');
  static const ValueKey<String> statusKey = ValueKey<String>('nonconformance-detail-status');
  static const ValueKey<String> severityKey = ValueKey<String>('nonconformance-detail-severity');
  static const ValueKey<String> filedKey = ValueKey<String>('nonconformance-detail-filed');
  static const ValueKey<String> quantityKey = ValueKey<String>('nonconformance-detail-quantity');
  static const ValueKey<String> quantityHistoryKey =
      ValueKey<String>('nonconformance-detail-quantity-history');
  static const ValueKey<String> noHistoryKey =
      ValueKey<String>('nonconformance-detail-no-history');
  static const ValueKey<String> increaseQuantityKey =
      ValueKey<String>('nonconformance-detail-increase');
  static const ValueKey<String> updateKey = ValueKey<String>('nonconformance-detail-update');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-detail-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('nonconformance-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformance-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('nonconformance-detail-missing');

  static ValueKey<String> changeKey(String id) => ValueKey<String>('nonconformance-change-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NonconformanceDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        NonconformanceDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
        NonconformanceDetailMissing() => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Non-conformance',
            message: 'Nothing is recorded at this address. It may have been removed, or the '
                'address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Non-conformances',
            actionKey: backKey,
            onAction: () => context.go(Routes.nonConformances),
          ),
        NonconformanceDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'The Non-conformance could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () =>
                context.read<NonconformanceDetailBloc>().add(const NonconformanceDetailRefreshed()),
          ),
        NonconformanceDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final NonconformanceDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = state.nonconformance;

    return Center(
      child: AppPageFrame(
        maxWidth: NonconformanceDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: NonconformanceDetailScreen.backKey,
                onPressed: () => context.go(Routes.nonConformances),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Non-conformances'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            // A `Wrap`: the number and its chips must not overflow at a narrow
            // width, and the record's own number is what a reader looks for.
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(row.issueNo, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: NonconformanceDetailScreen.statusKey,
                  label: row.statusLabel,
                  tone: row.statusTone,
                ),
                StatusChip(
                  key: NonconformanceDetailScreen.severityKey,
                  label: '${row.severityLabel} severity',
                  tone: _severityTone(row.severity),
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
                    Text('What was found', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    _Fact(label: 'Product', value: '${row.productName} · ${row.productCode}'),
                    _Fact(
                      label: 'Defect code',
                      value: '${row.defectCodeName} · ${row.defectCodeCode} · starts at '
                          '${DefectSeverity.label(row.defectCodeDefaultSeverity)}',
                    ),
                    _Fact(label: 'Detection point', value: row.detectionPointLabel),
                    _Fact(label: 'Org Unit', value: row.orgUnitName),
                    _Fact(
                      label: 'Asset',
                      value: row.assetName == null
                          ? 'None named'
                          : '${row.assetName} · ${row.assetCode}',
                    ),
                    _Fact(label: 'Lot reference', value: row.lotRef ?? 'Not given'),
                    _Fact(
                      label: 'Filed against',
                      key: NonconformanceDetailScreen.filedKey,
                      value: row.filedAgainst,
                    ),
                    _Fact(label: 'Detected at', value: row.detectedAt ?? 'Not recorded'),
                    _Fact(
                      label: 'Quantity affected',
                      key: NonconformanceDetailScreen.quantityKey,
                      value: '${_number(row.quantityAffected)} ${row.uomCode}',
                    ),
                    _Fact(label: 'Detail', value: row.description ?? 'None given'),
                    _Fact(
                      label: 'Immediate containment',
                      value: row.immediateContainment ?? 'None recorded yet',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quantity history', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Sorting finds more than the first count. Every change is kept, and the '
                      'affected quantity never shrinks.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (row.quantityChanges.isEmpty)
                      Text(
                        'The affected quantity has not been changed since it was recorded.',
                        key: NonconformanceDetailScreen.noHistoryKey,
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        key: NonconformanceDetailScreen.quantityHistoryKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final change in row.quantityChanges)
                            Padding(
                              key: NonconformanceDetailScreen.changeKey(change.id),
                              padding: const EdgeInsets.only(bottom: Spacing.xs),
                              child: Text(
                                '${_number(change.previousQuantity)} → '
                                '${_number(change.newQuantity)} ${row.uomCode} · '
                                '${change.changedBy}'
                                '${change.changedAt == null ? '' : ' · ${change.changedAt}'}'
                                '${change.note == null ? '' : ' · ${change.note}'}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: NonconformanceDetailScreen.increaseQuantityKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/quantity'),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Increase the quantity'),
                ),
                OutlinedButton.icon(
                  key: NonconformanceDetailScreen.updateKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/update'),
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('Raise severity or contain it'),
                ),
              ],
            ),
            if (state.mutationFailure != null)
              Padding(
                key: NonconformanceDetailScreen.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  state.mutationFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One label-and-value pair. A `Column` of two `Text`s, so a long value wraps
/// rather than being clipped, and the label is the quiet one.
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
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A severity's meaning in the shared status vocabulary (issue #168).
StatusTone _severityTone(String severity) => switch (severity) {
      'critical' => StatusTone.danger,
      'major' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
