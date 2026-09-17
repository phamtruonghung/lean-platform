/// The CAPA list (issue #211, CONTEXT.md's **CAPA**): every investigation on
/// the Platform, worst first — the ones whose effectiveness check has fallen
/// due and not been recorded, then the ones due soonest, then the most recently
/// opened.
///
/// Read platform-wide by any approved Account, whatever their Grants: a CAPA is
/// identified by its own number (`CA-HCM-2026-00001`), it belongs to no one
/// Module (CONTEXT.md is explicit — "it belongs to no one Module and is owned by
/// none"), and its own detail read has no Site in the address either. Which Org
/// Unit a CAPA sits at decides where somebody may *act* on it, never who may
/// know about it (ADR-0009, ADR-0032).
///
/// Every filter is a read filter over the already-visible list and sends a
/// request rather than hiding rows client-side, so a narrowed read is what the
/// server's ltree walk and its own indexes are for. The Org Unit filter includes
/// everything *beneath* the chosen area, which is what "everything under Line 3"
/// means in this Platform.
///
/// **No control here opens a CAPA, and that is deliberate.** ADR-0034 is
/// explicit that a CAPA is opened by a quality engineer's judgement on a
/// Concern and never beside one, so the one address that opens one is the
/// Concern's own (`.../actions/:id/capa`, #209's open dialog). A "New CAPA"
/// button here would offer an act with no Concern to stand on.
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
import 'capa.dart';
import 'capa_org_unit_filter_dialog.dart';
import 'capas_bloc.dart';

class CapasScreen extends StatelessWidget {
  const CapasScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> listKey = ValueKey<String>('capas-list');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('capas-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('capas-filter-status');
  static const ValueKey<String> overdueFilterKey = ValueKey<String>('capas-filter-overdue');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('capas-clear-filters');

  /// The empty state's own way to clear the filters, kept apart from
  /// [clearFiltersKey] because both are on screen at once: the filter row stays
  /// above the list while the list is replaced by the empty story, and two
  /// widgets sharing one key would make `find.byKey` ambiguous. The
  /// Non-conformance register's own empty state keeps its two apart for exactly
  /// this reason.
  static const ValueKey<String> emptyClearFiltersKey = ValueKey<String>('capas-empty-clear');
  static const ValueKey<String> truncatedKey = ValueKey<String>('capas-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('capas-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('capas-empty-matched');
  static const ValueKey<String> failedKey = ValueKey<String>('capas-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('capas-retry');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('capa-row-$id');
  static ValueKey<String> rowOverdueKey(String id) => ValueKey<String>('capa-row-$id-overdue');
  static ValueKey<String> rowDueKey(String id) => ValueKey<String>('capa-row-$id-due');
  static ValueKey<String> rowVerifiedKey(String id) => ValueKey<String>('capa-row-$id-verified');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapasBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                CapasLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                CapasUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The CAPA list could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<CapasBloc>().add(const CapasStarted()),
                  ),
                CapasLoaded(capas: final capas, isLoadingCapas: true) when capas.isEmpty =>
                  const SkeletonList(rows: 3, maxWidth: maxWidth),
                CapasLoaded(capas: final capas) when capas.isEmpty =>
                  _Empty(isFiltered: state.isFiltered),
                CapasLoaded(capas: final capas) => _Register(capas: capas),
              },
            ),
            if (state is CapasLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the list to re-read whenever the Screen is entered (issue #183's own
/// lesson): the `ShellRoute` creates `CapasBloc` once and keeps it alive while a
/// caller reads one investigation and comes back, so a Screen that only read on
/// `CapasStarted` painted the list as it was when they left — a check recorded
/// elsewhere, an investigation closed, a due date passed, none of it visible.
/// The Bloc ignores the ask while its first read is in flight.
class _RefreshOnMount extends StatefulWidget {
  const _RefreshOnMount({required this.child});

  final Widget child;

  @override
  State<_RefreshOnMount> createState() => _RefreshOnMountState();
}

class _RefreshOnMountState extends State<_RefreshOnMount> {
  @override
  void initState() {
    super.initState();
    // After this frame, never during it: dispatching an event from `initState`
    // is a side effect while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CapasBloc>().add(const CapasRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final CapasState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is CapasLoaded ? state as CapasLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: CapasScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CAPAs', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'The investigations opened on a Concern, and the effectiveness check each one is '
                'waiting on.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                _Filters(loaded: loaded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The three ways to narrow the list, each a read filter over an
/// already-visible list and so each a request rather than a client-side hide.
///
/// The overdue switch is the question this Screen exists for and is offered as
/// its own control rather than folded into the status chooser: "what is late"
/// cuts across the investigations' own states, and a plant reads it every
/// morning.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final CapasLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: CapasScreen.orgUnitFilterKey,
          onPressed: () => CapaOrgUnitFilterDialog.open(context),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(loaded.orgUnitFilterName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: CapasScreen.statusFilterKey,
            initialValue: loaded.statusFilter,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in capaStatuses.keys)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(capaStatusLabel(status)),
                ),
            ],
            onChanged: (status) =>
                context.read<CapasBloc>().add(CapasStatusFilterChanged(status)),
          ),
        ),
        // A value with a known set is chosen, never typed (ADR-0023), and this
        // one has two values, so it is a switch rather than a chooser.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              key: CapasScreen.overdueFilterKey,
              value: loaded.overdueFilter,
              onChanged: (overdue) =>
                  context.read<CapasBloc>().add(CapasOverdueToggled(overdue)),
            ),
            const SizedBox(width: Spacing.sm),
            Text('Overdue checks', style: theme.textTheme.bodyMedium),
          ],
        ),
        if (loaded.isFiltered)
          TextButton.icon(
            key: CapasScreen.clearFiltersKey,
            onPressed: () => context.read<CapasBloc>().add(const CapasFiltersCleared()),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: CapasScreen.truncatedKey,
      padding: const EdgeInsets.all(Spacing.lg),
      child: Center(
        child: Text(
          'There are more investigations than this list shows. Narrow it by Org Unit or status.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The two empty stories (issue #103): nothing has ever been investigated —
/// which resolves by opening a CAPA on a Concern, an act this Screen does not
/// offer — or a filter that matched none of them, which resolves by clearing
/// it.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: CapasScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'No investigation matches the Org Unit, status or overdue check you asked for.',
        actionLabel: 'Clear the filters',
        actionKey: CapasScreen.emptyClearFiltersKey,
        onAction: () => context.read<CapasBloc>().add(const CapasFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: CapasScreen.emptyKey,
      title: 'No investigations yet',
      message: 'A CAPA is opened from a Concern, when somebody decides that the problem needs a '
          'root cause and a fix that holds.',
      icon: Icons.fact_check_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.capas});

  final List<Capa> capas;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: CapasScreen.maxWidth,
        child: ListView(
          key: CapasScreen.listKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
          children: [
            for (final capa in capas) _CapaRow(capa: capa),
          ],
        ),
      ),
    );
  }
}

/// One investigation as the list reads it: what it is, how it is going, where it
/// sits, and — the fact this Screen exists for — when its effectiveness check
/// falls due or that it is overdue.
///
/// Built as a `Card` around a `Padding` rather than a `ListTile` with a
/// `trailing`, so a row that grows a chip or a longer due sentence drops onto
/// its own line instead of overflowing an 800px window (the rule every row that
/// gained a control in this Platform has paid for).
class _CapaRow extends StatelessWidget {
  const _CapaRow({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verifiedAt = capa.effectivenessVerifiedAt;

    return Card(
      key: CapasScreen.rowKey(capa.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.actions}/capas/${capa.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  Text(capa.capaNo, style: theme.textTheme.titleSmall),
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // The one mark this list exists to make: the check is due
                      // and the day has passed. It is a chip rather than a
                      // colour on the row so it reads at a glance and survives a
                      // colour-blind reader.
                      if (capa.effectivenessCheckOverdue)
                        StatusChip(
                          key: CapasScreen.rowOverdueKey(capa.id),
                          label: 'Overdue check',
                          tone: StatusTone.warning,
                        ),
                      StatusChip(label: capa.statusLabel, tone: capa.statusTone),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(capa.title, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  capa.methodLabel,
                  capa.orgUnitName,
                  '${capa.team.length} on the team',
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (capa.effectivenessCheckDueAt != null)
                Padding(
                  key: CapasScreen.rowDueKey(capa.id),
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    capa.effectivenessCheckOverdue
                        ? 'The effectiveness check was due on ${capa.effectivenessCheckDueAt}.'
                        : 'The effectiveness check is due on ${capa.effectivenessCheckDueAt}.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (verifiedAt != null)
                Padding(
                  key: CapasScreen.rowVerifiedKey(capa.id),
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    '${capaEffectivenessOutcomeLabel(capa.effectivenessOutcome!)}, '
                    'recorded by ${capa.effectivenessVerifiedBy?.name ?? 'somebody'}.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              if (capa.effectivenessCheckDueAt == null && verifiedAt == null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    'The effectiveness check falls due ${capa.effectivenessCheckDelayDays} days '
                    'after the Concern closes.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
