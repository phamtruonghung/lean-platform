/// One customer complaint (issue #214): what the customer said, which Product
/// it is about, who is answering it, and the Non-conformance that controls the
/// product they complained about.
///
/// The Screen is built around the two questions a reader opens a complaint
/// with. **Is the product under control?** — either the Non-conformance that
/// controls it is named, with a door to it, or the two ways to make one are
/// offered: record a Non-conformance from this complaint (`detection_point =
/// customer`, the complaint's own Product and Defect code) or link one that
/// already exists. **Has the customer been answered?** — the response the
/// complaint was closed with is shown, or the door to closing it is.
///
/// Nothing here is gated on a role: the server is the real gate on every write
/// (an edit Grant reaching the complaint's Org Unit), and hiding a control
/// would gate an address that answers a clean refusal with a sentence the
/// reader can act on. The refusal is rendered beside the action that made it.
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
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';

class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final String complaintId;

  static const double maxWidth = 900;

  static const ValueKey<String> loadedKey = ValueKey<String>('complaint-detail-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('complaint-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('complaint-detail-retry');
  static const ValueKey<String> backKey = ValueKey<String>('complaint-detail-back');
  static const ValueKey<String> statusKey = ValueKey<String>('complaint-detail-status');
  static const ValueKey<String> overdueKey = ValueKey<String>('complaint-detail-overdue');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-detail-failure');
  static const ValueKey<String> respondKey = ValueKey<String>('complaint-detail-respond');
  static const ValueKey<String> recordKey = ValueKey<String>('complaint-detail-record');
  static const ValueKey<String> linkKey = ValueKey<String>('complaint-detail-link');
  static const ValueKey<String> responseNoteKey = ValueKey<String>('complaint-detail-response');
  static const ValueKey<String> noControlKey = ValueKey<String>('complaint-detail-no-control');
  static ValueKey<String> controlledKey(String issueNo) =>
      ValueKey<String>('complaint-detail-controlled-$issueNo');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ComplaintDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        ComplaintDetailLoading() => const SkeletonList(maxWidth: maxWidth),
        ComplaintDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That complaint could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<ComplaintDetailBloc>()
                .add(ComplaintDetailStarted(complaintId)),
          ),
        ComplaintDetailLoaded(complaint: final complaint) => _Loaded(
            complaint: complaint,
            failure: state.mutationFailure,
          ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.complaint, this.failure});

  final CustomerComplaint complaint;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = complaint.nonconformance;

    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintDetailScreen.maxWidth,
        child: ListView(
          key: ComplaintDetailScreen.loadedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            // `go`, never `maybePop` — every navigation in this Platform
            // replaces the location rather than pushing a page, so a Back
            // button is an address. The label names the Destination.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ComplaintDetailScreen.backKey,
                onPressed: () => context.go(Routes.complaints),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Customer complaints'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(complaint.complaintNo, style: theme.textTheme.labelMedium),
                StatusChip(
                  key: ComplaintDetailScreen.statusKey,
                  label: complaint.statusLabel,
                  tone: complaint.statusTone,
                ),
                if (complaint.isOverdue)
                  StatusChip(
                    key: ComplaintDetailScreen.overdueKey,
                    label: 'Past due',
                    tone: StatusTone.danger,
                  ),
                if (complaint.isWarranty)
                  const StatusChip(label: 'Warranty claim', tone: StatusTone.info),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${complaint.customerName} · ${complaint.productName}',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.xs),
            Text(complaint.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Spacing.lg),
            _DetailCard(complaint: complaint),
            const SizedBox(height: Spacing.lg),
            Text('The product this is about', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            if (record == null) ...[
              Text(
                'Nothing controls the product this customer complained about yet. Record a '
                'Non-conformance from this complaint, or link one that already exists for the '
                'same Product.',
                key: ComplaintDetailScreen.noControlKey,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    key: ComplaintDetailScreen.recordKey,
                    onPressed: complaint.isFinished
                        ? null
                        : () => context.go('${Routes.complaints}/${complaint.id}/nonconformance'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Record a Non-conformance'),
                  ),
                  OutlinedButton.icon(
                    key: ComplaintDetailScreen.linkKey,
                    onPressed: complaint.isFinished
                        ? null
                        : () => context.go('${Routes.complaints}/${complaint.id}/link'),
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
                    key: ComplaintDetailScreen.controlledKey(record.issueNo),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const StatusChip(label: 'Open record', tone: StatusTone.info),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                record.detectionPoint == 'customer'
                    ? 'Found by the customer, so this complaint is where it started.'
                    : 'Recorded at ${record.detectionPoint ?? 'another detection point'}, and '
                        'linked to this complaint.',
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
            Text('The response', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            if (complaint.responseNote != null) ...[
              Text(
                complaint.responseNote!,
                key: ComplaintDetailScreen.responseNoteKey,
                style: theme.textTheme.bodyMedium,
              ),
              if (complaint.closedAt != null) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  'Closed ${complaint.closedAt}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ] else ...[
              Text(
                'Nothing has been said back to this customer yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.sm),
              FilledButton.icon(
                key: ComplaintDetailScreen.respondKey,
                onPressed: complaint.isFinished
                    ? null
                    : () => context.go('${Routes.complaints}/${complaint.id}/respond'),
                icon: const Icon(Icons.reply_outlined),
                label: const Text('Close with the response'),
              ),
            ],
            if (failure != null)
              Padding(
                key: ComplaintDetailScreen.failureKey,
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

/// The complaint's own fields, as a reader asks for them — the Customer and
/// Product again with their codes, the quantity in the Product's unit, where it
/// is filed, when it arrived and the day the customer was promised an answer.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final customer = complaint;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Customer', '${customer.customerName} · ${customer.customerCode}'),
            _row('Product', '${customer.productName} · ${customer.productCode}'),
            _row(
              'Defect code',
              customer.defectCodeName == null
                  ? 'Not known yet'
                  : '${customer.defectCodeName} · ${customer.defectCodeCode}',
            ),
            _row('Quantity', customer.quantityLabel),
            _row('Filed at', customer.orgUnitName),
            _row('Received', customer.receivedAt),
            _row('Response', customer.dueLabel),
            _row('Type', customer.typeLabel),
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
