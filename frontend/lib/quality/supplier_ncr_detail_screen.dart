/// One supplier NCR (issue #215): what came in wrong and from whom, which lot it
/// was, what was decided about the material, and the Non-conformance that
/// controls it.
///
/// The Screen is built around the two questions a reader opens an NCR with. **Is
/// the material under control?** — either the Non-conformance that controls it is
/// named, with a door to it, or the two ways to make one are offered: record a
/// Non-conformance from this NCR (`detection_point = incoming`, the NCR's own
/// Product and Defect code, or the ones named in that write's own body when the
/// NCR carries none) or link one that already exists. **Has the Supplier been
/// answered?** — the disposition and what was recovered are shown, or the door to
/// recording them is, and beside them the one transition this slice has: closing
/// the NCR.
///
/// Nothing here is gated on a role: the server is the real gate on every write
/// (an edit Grant reaching the NCR's Org Unit), and hiding a control would gate
/// an address that answers a clean refusal with a sentence the reader can act on.
/// The refusal is rendered beside the action that made it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'supplier_ncr.dart';
import 'supplier_ncr_detail_bloc.dart';

class SupplierNcrDetailScreen extends StatelessWidget {
  const SupplierNcrDetailScreen({super.key, required this.supplierNcrId});

  final String supplierNcrId;

  static const double maxWidth = 900;

  static const ValueKey<String> loadedKey = ValueKey<String>('supplier-ncr-detail-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('supplier-ncr-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('supplier-ncr-detail-retry');
  static const ValueKey<String> backKey = ValueKey<String>('supplier-ncr-detail-back');
  static const ValueKey<String> statusKey = ValueKey<String>('supplier-ncr-detail-status');
  static const ValueKey<String> overdueKey = ValueKey<String>('supplier-ncr-detail-overdue');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-detail-failure');
  static const ValueKey<String> dispositionKey = ValueKey<String>('supplier-ncr-detail-disposition');
  static const ValueKey<String> dispositionButtonKey =
      ValueKey<String>('supplier-ncr-detail-disposition-button');
  static const ValueKey<String> closeKey = ValueKey<String>('supplier-ncr-detail-close');
  static const ValueKey<String> recordKey = ValueKey<String>('supplier-ncr-detail-record');
  static const ValueKey<String> linkKey = ValueKey<String>('supplier-ncr-detail-link');
  static const ValueKey<String> costRecoveredKey =
      ValueKey<String>('supplier-ncr-detail-cost-recovered');
  static const ValueKey<String> noControlKey = ValueKey<String>('supplier-ncr-detail-no-control');
  static ValueKey<String> controlledKey(String issueNo) =>
      ValueKey<String>('supplier-ncr-detail-controlled-$issueNo');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupplierNcrDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        SupplierNcrDetailLoading() => const SkeletonList(maxWidth: maxWidth),
        SupplierNcrDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That supplier NCR could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<SupplierNcrDetailBloc>()
                .add(SupplierNcrDetailStarted(supplierNcrId)),
          ),
        SupplierNcrDetailLoaded(supplierNcr: final supplierNcr) => _Loaded(
            supplierNcr: supplierNcr,
            failure: state.mutationFailure,
          ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.supplierNcr, this.failure});

  final SupplierNcr supplierNcr;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = supplierNcr.nonconformance;
    final product = supplierNcr.productName;

    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrDetailScreen.maxWidth,
        child: ListView(
          key: SupplierNcrDetailScreen.loadedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            // `go`, never `maybePop` — every navigation in this Platform
            // replaces the location rather than pushing a page, so a Back
            // button is an address. The label names the Destination.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: SupplierNcrDetailScreen.backKey,
                onPressed: () => context.go(Routes.supplierNcrs),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Supplier NCRs'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(supplierNcr.ncrNo, style: theme.textTheme.labelMedium),
                StatusChip(
                  key: SupplierNcrDetailScreen.statusKey,
                  label: supplierNcr.statusLabel,
                  tone: supplierNcr.statusTone,
                ),
                if (supplierNcr.isOverdue)
                  StatusChip(
                    key: SupplierNcrDetailScreen.overdueKey,
                    label: 'Past due',
                    tone: StatusTone.danger,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${supplierNcr.supplierName}${product == null ? '' : ' · $product'}',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              supplierNcr.description ?? 'Nothing was written down about it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.lg),
            _DetailCard(supplierNcr: supplierNcr),
            const SizedBox(height: Spacing.lg),
            Text('The material this is about', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            if (record == null) ...[
              Text(
                'Nothing controls the material this NCR is about yet. Record a Non-conformance '
                'from this NCR, or link one that already exists for the same lot.',
                key: SupplierNcrDetailScreen.noControlKey,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    key: SupplierNcrDetailScreen.recordKey,
                    onPressed: supplierNcr.isFinished
                        ? null
                        : () => context.go(
                              '${Routes.supplierNcrs}/${supplierNcr.id}/nonconformance',
                            ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Record a Non-conformance'),
                  ),
                  OutlinedButton.icon(
                    key: SupplierNcrDetailScreen.linkKey,
                    onPressed: supplierNcr.isFinished
                        ? null
                        : () => context.go('${Routes.supplierNcrs}/${supplierNcr.id}/link'),
                    icon: const Icon(Icons.link_outlined),
                    label: const Text('Link one that exists'),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    record.issueNo,
                    key: SupplierNcrDetailScreen.controlledKey(record.issueNo),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const StatusChip(label: 'Open record', tone: StatusTone.info),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                record.detectionPoint == 'incoming'
                    ? 'Found at goods-in, so this NCR is where it started.'
                    : 'Recorded at ${record.detectionPoint ?? 'another detection point'}, and '
                        'linked to this NCR.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.go('${Routes.nonConformances}/${record.id}'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open the Non-conformance'),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Text('The Supplier\'s disposition', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              supplierNcr.dispositionLabel,
              key: SupplierNcrDetailScreen.dispositionKey,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.xxs),
            Text(
              // What was clawed back, or that nothing was — a different fact
              // from nobody having decided.
              supplierNcr.costRecovered == null
                  ? 'Nothing has been recovered from this Supplier.'
                  : 'Recovered ${supplierNcr.costRecoveredLabel}.',
              key: SupplierNcrDetailScreen.costRecoveredKey,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              children: [
                FilledButton.icon(
                  key: SupplierNcrDetailScreen.dispositionButtonKey,
                  onPressed: supplierNcr.isFinished
                      ? null
                      : () => context.go(
                            '${Routes.supplierNcrs}/${supplierNcr.id}/disposition',
                          ),
                  icon: const Icon(Icons.gavel_outlined),
                  label: Text(
                    supplierNcr.costRecovered == null && supplierNcr.status == SupplierNcrStatus.open
                        ? 'Record the disposition'
                        : 'Correct the disposition',
                  ),
                ),
                OutlinedButton.icon(
                  key: SupplierNcrDetailScreen.closeKey,
                  onPressed: supplierNcr.isFinished
                      ? null
                      : () => context.read<SupplierNcrDetailBloc>().add(
                            SupplierNcrCloseConfirmed(supplierNcr.id),
                          ),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Close the NCR'),
                ),
              ],
            ),
            if (supplierNcr.closedAt != null) ...[
              const SizedBox(height: Spacing.xxs),
              Text(
                'Closed ${supplierNcr.closedAt}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (failure != null)
              Padding(
                key: SupplierNcrDetailScreen.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  failure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The NCR's own fields, as a reader asks for them — the Supplier and the
/// Product again with their codes, the lot and the purchase order it arrived
/// against, the quantity in its own unit, where it was filed, when it was found
/// and the day the Supplier was given.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final record = supplierNcr;
    final product = record.productName;
    final defectCode = record.defectCodeName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Supplier', '${record.supplierName} · ${record.supplierCode}'),
            _row(
              'Product',
              product == null ? 'Not named yet' : '$product · ${record.productCode}',
            ),
            _row(
              'Defect code',
              defectCode == null
                  ? 'Not known yet'
                  : '$defectCode · ${record.defectCodeCode}',
            ),
            _row('Quantity', record.quantityLabel),
            _row('Incoming lot', record.incomingLotRef ?? 'Not written down'),
            _row('Purchase reference', record.purchaseRef ?? 'Not written down'),
            _row('Filed at', record.orgUnitName),
            _row('Detected', record.detectedAt),
            _row('Answer', record.dueLabel),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Text('$label: $value'),
    );
  }
}
