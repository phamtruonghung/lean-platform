/// The action log: what the Site owes, who owns it, and when it is due
/// (issue #176).
///
/// The list `v_open_actions`' own comment in the baseline describes — "every
/// open action on a unit and everything beneath it, whatever raised it" — read
/// Site-wide by anyone admitted to the Platform, whatever their Grants
/// (ADR-0032). Raising is offered to everyone too: a concern is a report, and
/// the server is the real gate on where one may be raised.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'action_escalated_to_filter_dialog.dart';
import 'action_org_unit_filter_dialog.dart';
import 'actions_bloc.dart';

class ActionsScreen extends StatelessWidget {
  const ActionsScreen({super.key});

  static const double maxWidth = 1100;
  static const ValueKey<String> raiseKey = ValueKey<String>('actions-raise');
  static const ValueKey<String> siteKey = ValueKey<String>('actions-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('actions-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('actions-filter-status');
  static const ValueKey<String> escalatedToFilterKey =
      ValueKey<String>('actions-filter-escalated');
  static const ValueKey<String> typeFilterKey = ValueKey<String>('actions-filter-type');
  static const ValueKey<String> historyKey = ValueKey<String>('actions-show-closed');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('actions-clear-filters');
  static const ValueKey<String> noticeKey = ValueKey<String>('actions-notice');
  static const ValueKey<String> truncatedKey = ValueKey<String>('actions-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('actions-empty');
  static const ValueKey<String> emptyClearFiltersKey = ValueKey<String>('actions-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('actions-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('actions-retry');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('actions-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('action-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('action-status-$id');
  static ValueKey<String> ownerKey(String id) => ValueKey<String>('action-owner-$id');
  static ValueKey<String> dueKey(String id) => ValueKey<String>('action-due-$id');
  static ValueKey<String> escalatedKey(String id) => ValueKey<String>('action-escalated-$id');
  static ValueKey<String> measuresKey(String id) => ValueKey<String>('action-measures-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          if (state is ActionsLoaded && state.notice != null) _Notice(message: state.notice!),
          if (state is ActionsLoaded && state.truncated) const _Truncated(),
          Expanded(
            child: switch (state) {
              ActionsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              ActionsUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: 'The action log could not be read',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<ActionsBloc>().add(const ActionsStarted()),
                ),
              ActionsLoaded(isLoadingActions: true) => const SkeletonList(rows: 4, maxWidth: maxWidth),
              ActionsLoaded(actions: final actions, isFiltered: final isFiltered)
                  when actions.isEmpty =>
                _ActionsEmpty(isFiltered: isFiltered),
              ActionsLoaded(actions: final actions) => _ActionsList(actions: actions),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ActionsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is ActionsLoaded ? state as ActionsLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ActionsScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Actions', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'What the plant owes at this Site: what was found, who owns it, and '
                          'when it is due. Overdue first.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: ActionsScreen.raiseKey,
                      onPressed: loaded.isRaising || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.actions}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise a concern'),
                    ),
                ],
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

/// The Site chooser and the four ways to narrow the log. Every one of them is a
/// read filter over an already-visible register, so each sends a request rather
/// than hiding rows client-side — a closed Action is not even sent unless asked
/// for, and a narrowed read is what the server's own indexes are built for.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final ActionsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (loaded.sites.length > 1)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ActionsScreen.siteKey,
                  initialValue: loaded.siteId,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                  items: [
                    for (final site in loaded.sites)
                      DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (siteId) {
                    if (siteId == null) return;
                    context.read<ActionsBloc>().add(ActionsSiteSelected(siteId));
                  },
                ),
              ),
            OutlinedButton.icon(
              key: ActionsScreen.orgUnitFilterKey,
              onPressed: () => ActionOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(loaded.orgUnitFilterName ?? 'All Org Units'),
            ),
            // What was handed up to whom (issue #180) — the plant manager's
            // queue in one click, and a different question from where the work
            // sits.
            OutlinedButton.icon(
              key: ActionsScreen.escalatedToFilterKey,
              onPressed: () =>
                  ActionEscalatedToFilterDialog.open(context, siteId: loaded.siteId),
              icon: const Icon(Icons.arrow_upward),
              label: Text(
                loaded.escalatedToOrgUnitFilterName == null
                    ? 'Escalated to anyone'
                    : 'Escalated to ${loaded.escalatedToOrgUnitFilterName}',
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                key: ActionsScreen.statusFilterKey,
                initialValue: loaded.statusFilter,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
                  for (final entry in actionStatuses.entries)
                    DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value.$1)),
                ],
                onChanged: (status) =>
                    context.read<ActionsBloc>().add(ActionsStatusFilterChanged(status)),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String?>(
                key: ActionsScreen.typeFilterKey,
                initialValue: loaded.typeFilter,
                isDense: true,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Kind of Action', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Every kind')),
                  for (final type in ActionType.values)
                    DropdownMenuItem<String?>(value: type.wire, child: Text(type.label)),
                ],
                onChanged: (type) => context.read<ActionsBloc>().add(ActionsTypeFilterChanged(type)),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: ActionsScreen.historyKey,
                  value: loaded.includeHistory,
                  onChanged: (value) =>
                      context.read<ActionsBloc>().add(ActionsHistoryToggled(value)),
                ),
                const SizedBox(width: Spacing.xs),
                Text('Show closed', style: theme.textTheme.bodyMedium),
              ],
            ),
            if (loaded.isFiltered || loaded.includeHistory)
              TextButton(
                key: ActionsScreen.clearFiltersKey,
                onPressed: () => context.read<ActionsBloc>().add(const ActionsFiltersCleared()),
                child: const Text('Clear filters'),
              ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ActionsScreen.maxWidth),
        child: Padding(
          key: ActionsScreen.noticeKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(message, style: theme.textTheme.bodyMedium),
        ),
      ),
    );
  }
}

/// The register was capped. Said out loud rather than left to be inferred from
/// a list that happens to end: a capped list must not read as a whole Site
/// (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ActionsScreen.maxWidth),
        child: Padding(
          key: ActionsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Actions than this list shows. Narrow it by Org Unit, by status or by '
            'kind to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103): a Site with nothing on its log
/// is a good-news empty, and a filter that matched nothing is a filter to
/// clear. The wrong one would send a caller looking for a record that exists.
class _ActionsEmpty extends StatelessWidget {
  const _ActionsEmpty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: ActionsEmptyKeys.matched,
        title: 'Nothing matches these filters',
        message: 'The log has Actions, but none of them is in the Org Unit, status or kind you '
            'picked.',
        actionLabel: 'Clear the filters',
        actionKey: ActionsScreen.emptyClearFiltersKey,
        onAction: () => context.read<ActionsBloc>().add(const ActionsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: ActionsEmptyKeys.none,
      title: 'Nothing on the log',
      message: 'No Action has been raised at this Site yet.',
      icon: Icons.assignment_outlined,
    );
  }
}

/// The two empty states' keys, named so a test can tell which story rendered.
abstract final class ActionsEmptyKeys {
  static const ValueKey<String> none = ActionsScreen.emptyKey;
  static const ValueKey<String> matched = ValueKey<String>('actions-empty-matched');
}

class _ActionsList extends StatelessWidget {
  const _ActionsList({required this.actions});

  final List<Action> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ActionsScreen.maxWidth),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: actions.length,
          itemBuilder: (context, index) => _ActionRow(action: actions[index]),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ActionsScreen.rowKey(action.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.actions}/${action.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(action.actionNo, style: theme.textTheme.labelMedium),
                        StatusChip(
                          key: ActionsScreen.rowStatusKey(action.id),
                          label: action.typeLabel,
                          tone: StatusTone.info,
                        ),
                        StatusChip(label: action.statusLabel, tone: action.statusTone),
                        if (action.priority <= 2)
                          StatusChip(label: action.priorityLabel, tone: StatusTone.warning),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(action.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      [
                        action.orgUnitName,
                        // What answers this, and how much of it is a fix
                        // rather than a holding action (issue #178): a concern
                        // with no countermeasure is the one that cannot close,
                        // so it is visible without opening the row.
                        if (action.measureCount > 0)
                          '${action.measureCount} '
                              '${action.measureCount == 1 ? 'measure' : 'measures'}, '
                              '${action.countermeasureCount} of them countermeasures',
                      ].join(' · '),
                      key: ActionsScreen.measuresKey(action.id),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    key: ActionsScreen.ownerKey(action.id),
                    action.ownerName ?? 'Nobody yet',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    key: ActionsScreen.dueKey(action.id),
                    action.isOverdue
                        ? 'Overdue by ${action.daysOverdue} days'
                        : action.dueDate == null
                            ? 'No due date'
                            : 'Due ${action.dueDate}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: action.isOverdue
                          ? AppColors.statusDanger
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action.escalatedToOrgUnitName != null) ...[
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      key: ActionsScreen.escalatedKey(action.id),
                      'Escalated to ${action.escalatedToOrgUnitName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
