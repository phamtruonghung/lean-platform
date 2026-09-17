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
/// The four decisions the Grant's Quality authority gates — the Concession,
/// the lowered severity, the reopen and the cancel (issue #206, ADR-0035) —
/// are the exception: they are offered only to a caller who holds that
/// authority at the record's Org Unit, so nobody is shown a control whose only
/// answer would be a 403.
///
/// The five affordances are addressed dialogs (ADR-0021): a refresh lands on
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
import 'nonconformance.dart';
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
  static const ValueKey<String> dispositionKey =
      ValueKey<String>('nonconformance-detail-disposition');
  static const ValueKey<String> concessionKey =
      ValueKey<String>('nonconformance-detail-concession');
  static const ValueKey<String> lowerSeverityKey =
      ValueKey<String>('nonconformance-detail-lower-severity');
  static const ValueKey<String> reopenKey = ValueKey<String>('nonconformance-detail-reopen');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-detail-cancel');
  static const ValueKey<String> dispositionsKey =
      ValueKey<String>('nonconformance-detail-dispositions');
  static const ValueKey<String> noDispositionsKey =
      ValueKey<String>('nonconformance-detail-no-dispositions');
  static const ValueKey<String> correctionsKey =
      ValueKey<String>('nonconformance-detail-corrections');
  static const ValueKey<String> noCorrectionsKey =
      ValueKey<String>('nonconformance-detail-no-corrections');
  static const ValueKey<String> closedKey = ValueKey<String>('nonconformance-detail-closed');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-detail-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('nonconformance-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformance-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('nonconformance-detail-missing');

  static ValueKey<String> changeKey(String id) => ValueKey<String>('nonconformance-change-$id');

  static ValueKey<String> dispositionRowKey(String id) =>
      ValueKey<String>('nonconformance-disposition-$id');

  static ValueKey<String> correctionRowKey(String id) =>
      ValueKey<String>('nonconformance-correction-$id');

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
    // Read here, in a build, rather than passed in from the route: a value
    // computed when the route first built would freeze the Account state as it
    // was before `/me` answered, and a holder of Quality authority would never
    // be offered the four decisions that authority gates (ADR-0035).
    final holdsQuality = holdsQualityAuthority(context, row.orgUnitId);

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
            // What has been decided about the product, and the corrections a
            // holder of Quality authority has made to the record (issue #206).
            _DispositionsCard(row: row),
            const SizedBox(height: Spacing.lg),
            _CorrectionsCard(row: row),
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
                // A Disposition is offered wherever the record still has
                // undecided quantity — the server is the gate on the Grant
                // reaching the Org Unit, exactly as it is for recording.
                if (row.acceptsDisposition)
                  FilledButton.icon(
                    key: NonconformanceDetailScreen.dispositionKey,
                    onPressed: state.isMutating
                        ? null
                        : () => context.go('${Routes.nonConformances}/${row.id}/disposition'),
                    icon: const Icon(Icons.rule_outlined),
                    label: const Text('Record a Disposition'),
                  ),
                // The four decisions only a holder of Quality authority may
                // take (ADR-0035). None of them is offered to anyone else, so
                // no request is ever sent that the server would refuse for a
                // reason the caller could not see.
                if (holdsQuality) ...[
                  if (row.acceptsConcession)
                    FilledButton.icon(
                      key: NonconformanceDetailScreen.concessionKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.nonConformances}/${row.id}/concession'),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Grant a Concession'),
                    ),
                  if (row.canBeLowered)
                    OutlinedButton.icon(
                      key: NonconformanceDetailScreen.lowerSeverityKey,
                      onPressed: state.isMutating
                          ? null
                          : () =>
                              context.go('${Routes.nonConformances}/${row.id}/lower-severity'),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('Lower the severity'),
                    ),
                  if (row.canBeReopened)
                    OutlinedButton.icon(
                      key: NonconformanceDetailScreen.reopenKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.nonConformances}/${row.id}/reopen'),
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Reopen it'),
                    ),
                  if (row.canBeCancelled)
                    OutlinedButton.icon(
                      key: NonconformanceDetailScreen.cancelKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.nonConformances}/${row.id}/cancel'),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel it in error'),
                    ),
                ],
                if (row.closedAt != null)
                  StatusChip(
                    key: NonconformanceDetailScreen.closedKey,
                    label: 'Finished ${row.closedAt}',
                    tone: StatusTone.neutral,
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

/// What has been decided about the product (issue #206): every Disposition in
/// the order it was decided, with the quantity it covers, who decided it and
/// when — and, for a Concession, the reference it was granted under.
///
/// The card is drawn even when nothing has been dispositioned, because "none of
/// this has been decided yet" is the state a reader of an open record needs,
/// said rather than left blank.
class _DispositionsCard extends StatelessWidget {
  const _DispositionsCard({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dispositions', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Product is dealt with in parts. A Non-conformance closes by itself once all of '
              'its quantity has a Disposition.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              '${_number(row.quantityDispositioned)} of ${_number(row.quantityAffected)} '
              '${row.uomCode} dispositioned',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.sm),
            if (row.dispositions.isEmpty)
              Text(
                'Nothing has been decided about this product yet.',
                key: NonconformanceDetailScreen.noDispositionsKey,
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                key: NonconformanceDetailScreen.dispositionsKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final disposition in row.dispositions)
                    Padding(
                      key: NonconformanceDetailScreen.dispositionRowKey(disposition.id),
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${disposition.label} · ${_number(disposition.quantity)} '
                            '${disposition.uomCode}'
                            '${disposition.reworkMinutes > 0 ? ' · ${_number(disposition.reworkMinutes)} minutes of rework' : ''}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            '${disposition.decidedBy}'
                            '${disposition.decidedAt == null ? '' : ' · ${disposition.decidedAt}'}'
                            '${disposition.reference == null ? '' : ' · ${disposition.reference}'}'
                            '${disposition.note == null ? '' : ' · ${disposition.note}'}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The corrections a holder of Quality authority has made to the record
/// (issue #206): a lowered severity, a reopen, a cancel — each with what
/// changed, why, and who decided it, which is what "readable back with who and
/// when" asks a client to show.
class _CorrectionsCard extends StatelessWidget {
  const _CorrectionsCard({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Corrections', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'What a holder of Quality authority has changed about this record, and why.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            if (row.corrections.isEmpty)
              Text(
                'This record has not been corrected.',
                key: NonconformanceDetailScreen.noCorrectionsKey,
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                key: NonconformanceDetailScreen.correctionsKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final correction in row.corrections)
                    Padding(
                      key: NonconformanceDetailScreen.correctionRowKey(correction.id),
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(correction.summary, style: theme.textTheme.bodyMedium),
                          Text(
                            '${correction.correctedBy}'
                            '${correction.correctedAt == null ? '' : ' · ${correction.correctedAt}'}'
                            '${correction.note == null ? '' : ' · ${correction.note}'}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
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
