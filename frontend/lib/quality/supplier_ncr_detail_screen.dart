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
///
/// **The page answers "what, whose, how bad, what next" above the fold (issue
/// #390).** A summary card carries the number, the chips, the Supplier and the
/// Product, the description and the nine facts a reader asks for first; the two
/// sections below it are the two decisions, side by side from
/// [AppBreakpoints.detailTwoColumn] of box — which is why [maxWidth] is 1040 and
/// not the old 900: at a 1280px window the Shell leaves a page box of 1020 and a
/// 900-page could never reach a 1000 breakpoint (design-language §10). The
/// Non-conformance that controls the lot sits in that first section, so the CAPA
/// trail is a visible step from the record rather than a hunt.
///
/// No field is hidden by permission here: unlike the Non-conformance detail, an
/// NCR has no restricted field — every one of these is what the record's own read
/// returns (ADR-0037 covers the two that do).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'supplier_ncr.dart';
import 'supplier_ncr_detail_bloc.dart';

class SupplierNcrDetailScreen extends StatelessWidget {
  const SupplierNcrDetailScreen({super.key, required this.supplierNcrId});

  final String supplierNcrId;

  /// 1040, so a box of 1000 is reachable: at a 1280px window the Shell leaves
  /// 1020, and [AppBreakpoints.detailTwoColumn] compares against that box.
  static const double maxWidth = 1040;

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
  static const ValueKey<String> summaryKey = ValueKey<String>('supplier-ncr-detail-summary');

  static ValueKey<String> controlledKey(String issueNo) =>
      ValueKey<String>('supplier-ncr-detail-controlled-$issueNo');

  static final ButtonStyle actionStyle =
      FilledButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));
  static final ButtonStyle secondaryStyle =
      OutlinedButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupplierNcrDetailBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          Expanded(
            child: switch (state) {
              SupplierNcrDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
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
          ),
        ],
      ),
    );
  }
}

/// The page's own head: the way back, then the shared `AppPageHeader`. What the
/// NCR *is* — its number, its Supplier, its state — is the summary card's.
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `go`, never `maybePop` — every navigation in this Platform
              // replaces the location rather than pushing a page, so a Back
              // button is an address. The label names the Destination.
              TextButton.icon(
                key: SupplierNcrDetailScreen.backKey,
                onPressed: () => context.go(Routes.supplierNcrs),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Supplier NCRs'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              const AppPageHeader(title: 'Supplier NCR'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.supplierNcr, this.failure});

  final SupplierNcr supplierNcr;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrDetailScreen.maxWidth,
        // The box is the page's, before its inset: 1020 at a 1280px window, over
        // [AppBreakpoints.detailTwoColumn], so the two decisions sit side by
        // side; the sections themselves are handed 988. At 2x the page goes back
        // to one column.
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >=
                AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
            return ListView(
              key: SupplierNcrDetailScreen.loadedKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                _SummaryCard(supplierNcr: supplierNcr),
                const SizedBox(height: Spacing.md),
                _SectionRows(
                  wide: wide,
                  sections: [
                    _ControlSection(supplierNcr: supplierNcr),
                    _DispositionSection(supplierNcr: supplierNcr),
                  ],
                ),
                if (failure != null)
                  Padding(
                    key: SupplierNcrDetailScreen.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      failure!,
                      style: AppTypography.dense(context)
                          ?.copyWith(color: AppColors.of(context).statusDanger),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Two sections side by side when [wide], one above the other when not — the
/// shape `AppSectionGrid` draws, asked of the page's box rather than the list's
/// inner one (see `complaint_detail_screen.dart`'s copy for the arithmetic, and
/// `work_order_detail_screen.dart` for the precedent).
class _SectionRows extends StatelessWidget {
  const _SectionRows({required this.wide, required this.sections});

  final bool wide;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: Spacing.md),
            sections[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var start = 0; start < sections.length; start += 2) ...[
          if (start > 0) const SizedBox(height: Spacing.md),
          if (start + 1 >= sections.length)
            sections[start]
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: sections[start]),
                  const SizedBox(width: Spacing.md),
                  Expanded(child: sections[start + 1]),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The NCR's own fields, first. The Supplier and the Product head it — "who
/// sent it, what it was" — and the nine facts a reader asks next are a `Wrap` of
/// label-over-value pairs rather than eight more sentences, so the card reads
/// down its facts instead of parsing `Label: value` lines.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final record = supplierNcr;
    final product = record.productName;
    final defectCode = record.defectCodeName;

    Widget fact(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTypography.floor(context)?.copyWith(color: palette.textMuted)),
            Text(value, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
          ],
        );

    return Card(
      key: SupplierNcrDetailScreen.summaryKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  record.ncrNo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                ),
                StatusChip(
                  key: SupplierNcrDetailScreen.statusKey,
                  label: record.statusLabel,
                  tone: record.statusTone,
                ),
                if (record.isOverdue)
                  StatusChip(
                    key: SupplierNcrDetailScreen.overdueKey,
                    label: 'Past due',
                    tone: StatusTone.danger,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${record.supplierName}${product == null ? '' : ' · $product'}',
              style: AppTypography.dense(context)
                  ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: Spacing.xxs),
            Text(
              record.description ?? 'Nothing was written down about it.',
              style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.md,
              children: [
                fact('Supplier', '${record.supplierName} · ${record.supplierCode}'),
                fact(
                  'Product',
                  product == null ? 'Not named yet' : '$product · ${record.productCode}',
                ),
                fact(
                  'Defect code',
                  defectCode == null
                      ? 'Not known yet'
                      : '$defectCode · ${record.defectCodeCode}',
                ),
                fact('Quantity', record.quantityLabel),
                fact('Incoming lot', record.incomingLotRef ?? 'Not written down'),
                fact('Purchase reference', record.purchaseRef ?? 'Not written down'),
                fact('Filed at', record.orgUnitName),
                fact('Detected', record.detectedAt),
                fact('Answer', record.dueLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Is the material under control?" — the Non-conformance that controls it, with
/// a door to it, or the two ways to make one.
class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final record = supplierNcr.nonconformance;

    return AppDetailSection(
      title: 'The material this is about',
      children: [
        if (record == null) ...[
          Text(
            'Nothing controls the material this NCR is about yet. Record a Non-conformance '
            'from this NCR, or link one that already exists for the same lot.',
            key: SupplierNcrDetailScreen.noControlKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.sm,
            children: [
              FilledButton.icon(
                key: SupplierNcrDetailScreen.recordKey,
                onPressed: supplierNcr.isFinished
                    ? null
                    : () => context.go('${Routes.supplierNcrs}/${supplierNcr.id}/nonconformance'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Record a Non-conformance'),
                style: SupplierNcrDetailScreen.actionStyle,
              ),
              OutlinedButton.icon(
                key: SupplierNcrDetailScreen.linkKey,
                onPressed: supplierNcr.isFinished
                    ? null
                    : () => context.go('${Routes.supplierNcrs}/${supplierNcr.id}/link'),
                icon: const Icon(Icons.link_outlined),
                label: const Text('Link one that exists'),
                style: SupplierNcrDetailScreen.secondaryStyle,
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
                style: AppTypography.dense(context)
                    ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
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
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: () => context.go('${Routes.nonConformances}/${record.id}'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open the Non-conformance'),
            style: SupplierNcrDetailScreen.secondaryStyle,
          ),
        ],
      ],
    );
  }
}

/// "Has the Supplier been answered?" — the disposition and what was recovered,
/// then the two writes: record or correct the disposition, and close the NCR.
class _DispositionSection extends StatelessWidget {
  const _DispositionSection({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final record = supplierNcr;

    return AppDetailSection(
      title: "The Supplier's disposition",
      children: [
        Text(
          record.dispositionLabel,
          key: SupplierNcrDetailScreen.dispositionKey,
          style: AppTypography.dense(context)
              ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: Spacing.xxs),
        Text(
          // What was clawed back, or that nothing was — a different fact from
          // nobody having decided.
          record.costRecovered == null
              ? 'Nothing has been recovered from this Supplier.'
              : 'Recovered ${record.costRecoveredLabel}.',
          key: SupplierNcrDetailScreen.costRecoveredKey,
          style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
        ),
        if (record.closedAt != null) ...[
          const SizedBox(height: Spacing.xxs),
          Text(
            'Closed ${record.closedAt}',
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          ),
        ],
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          children: [
            FilledButton.icon(
              key: SupplierNcrDetailScreen.dispositionButtonKey,
              onPressed: record.isFinished
                  ? null
                  : () => context.go('${Routes.supplierNcrs}/${record.id}/disposition'),
              icon: const Icon(Icons.gavel_outlined),
              label: Text(
                record.costRecovered == null && record.status == SupplierNcrStatus.open
                    ? 'Record the disposition'
                    : 'Correct the disposition',
              ),
              style: SupplierNcrDetailScreen.actionStyle,
            ),
            OutlinedButton.icon(
              key: SupplierNcrDetailScreen.closeKey,
              onPressed: record.isFinished
                  ? null
                  : () => context.read<SupplierNcrDetailBloc>().add(
                        SupplierNcrCloseConfirmed(record.id),
                      ),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Close the NCR'),
              style: SupplierNcrDetailScreen.secondaryStyle,
            ),
          ],
        ),
      ],
    );
  }
}
