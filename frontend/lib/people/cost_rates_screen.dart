/// The cost rate catalogue (issue #252, ADR-0005's shared catalogue): the money
/// the Platform costs things at — an hour of labour, an hour a machine is down,
/// the premium on an overtime hour — laid over an administrator's own write
/// surface for it (`POST`/`PATCH /api/people/cost-rates` and the revision
/// route, cost-rate-routes.js).
///
/// `JobRolesScreen`'s shape, and for the same reasons, with one thing neither
/// it nor any other catalogue Screen has: every row carries its **period**, and
/// a closed period is shown rather than hidden. That is the point of the
/// catalogue — a cost reported for September has to stay what it was in
/// September, so the rate that produced it must stay readable.
///
/// Its **Destination** is an administrator's (see `destinations.dart`), because
/// a plant's labour rates are commercially sensitive in a way a job role list is
/// not. The Screen itself is not gated, because the read behind it is not:
/// `GET /api/people/cost-rates` carries no admin and no Org Unit scope of its
/// own, so a non-administrator who follows a link here sees the catalogue with
/// no write affordances on it — exactly what they would see on `/job-roles`.
///
/// **This page does not tell anyone what a given Org Unit's rate is.** The rate
/// that actually applies somewhere falls back from the Asset to the nearest
/// ancestor Org Unit to the Site, in the database
/// (`resolve_cost_rate`), and `GET /api/people/cost-rates/resolution` is what
/// answers that question. Re-spelling the fallback here, over a list of rows,
/// is exactly the second implementation the ticket rules out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'cost_rate.dart';
import 'cost_rate_form_dialog.dart';
import 'cost_rates_bloc.dart';

class CostRatesScreen extends StatelessWidget {
  const CostRatesScreen({super.key, required this.isAdmin});

  /// Whether this caller may set or correct a rate — read off `/me`'s own role,
  /// the same shape `JobRolesScreen.isAdmin` follows.
  final bool isAdmin;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('cost-rates-add');
  static const ValueKey<String> failedKey = ValueKey<String>('cost-rates-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('cost-rates-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('cost-rates-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('cost-rates-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('cost-rates-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('cost-rates-correct-$id');
  static ValueKey<String> reviseKey(String id) => ValueKey<String>('cost-rates-revise-$id');
  static ValueKey<String> closedChipKey(String id) => ValueKey<String>('cost-rates-closed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CostRatesBloc>().state;

    return Scaffold(
      body: switch (state) {
        CostRatesLoading() => const SkeletonList(maxWidth: CostRatesScreen.maxWidth),
        CostRatesUnavailable(message: final message) => PlatformFailureState(
            key: CostRatesScreen.failedKey,
            title: 'The cost rate catalogue could not be read',
            message: message,
            retryKey: CostRatesScreen.retryKey,
            onRetry: () => context.read<CostRatesBloc>().add(const CostRatesStarted()),
          ),
        CostRatesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final CostRatesLoaded state;
  final bool isAdmin;

  void _add(BuildContext context) => CostRateFormDialog.open(
        context,
        mode: CostRateFormMode.add,
        scopes: state.scopes,
        scopesFailure: state.scopesFailure,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: CostRatesScreen.maxWidth,
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
                      Text('Cost rates', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What an hour costs — one catalogue shared by every Site, and what the '
                        'Cost numbers on the tier board are worked out from. A rate is never '
                        'overwritten: it is closed, and a new one opened, so a cost reported '
                        'for an earlier month stays what it was.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: CostRatesScreen.addKey,
                    onPressed: state.isMutating ? null : () => _add(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add cost rate'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.costRates.isEmpty)
              PlatformEmptyState.noneExist(
                key: CostRatesScreen.emptyKey,
                title: 'No cost rates yet',
                message: 'Until a rate is set, every Cost number resolves to nothing.',
                icon: Icons.payments_outlined,
                actionLabel: isAdmin ? 'Add cost rate' : null,
                actionKey: CostRatesScreen.emptyAddKey,
                onAction: isAdmin ? () => _add(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final costRate in state.costRates)
                    _CostRateRow(
                      costRate: costRate,
                      isAdmin: isAdmin,
                      isMutating: state.isMutating,
                      scopes: state.scopes,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CostRateRow extends StatelessWidget {
  const _CostRateRow({
    required this.costRate,
    required this.isAdmin,
    required this.isMutating,
    required this.scopes,
  });

  final CostRate costRate;
  final bool isAdmin;
  final bool isMutating;
  final List<CostRateScope> scopes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: CostRatesScreen.rowKey(costRate.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${costRateTypeLabel(costRate.rateType)} · ${costRate.amountLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (!costRate.isCurrent) ...[
                      const SizedBox(width: Spacing.sm),
                      StatusChip(
                        key: CostRatesScreen.closedChipKey(costRate.id),
                        label: 'Closed',
                        tone: StatusTone.neutral,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '${costRate.scopeLabel} · ${costRate.periodLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            OutlinedButton(
              key: CostRatesScreen.correctKey(costRate.id),
              onPressed: isMutating
                  ? null
                  : () => CostRateFormDialog.open(
                        context,
                        mode: CostRateFormMode.correct,
                        scopes: scopes,
                        costRate: costRate,
                      ),
              child: const Text('Correct'),
            ),
            const SizedBox(width: Spacing.sm),
            OutlinedButton(
              key: CostRatesScreen.reviseKey(costRate.id),
              onPressed: isMutating
                  ? null
                  : () => CostRateFormDialog.open(
                        context,
                        mode: CostRateFormMode.revise,
                        scopes: scopes,
                        costRate: costRate,
                      ),
              child: const Text('Revise'),
            ),
          ],
        ],
      ),
    );
  }
}
