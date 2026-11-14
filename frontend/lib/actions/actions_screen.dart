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

import '../l10n/app_localizations.dart';
import '../l10n/notices.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_row.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'action_escalated_to_filter_dialog.dart';
import 'action_org_unit_filter_dialog.dart';
import 'actions_bloc.dart';
import '../l10n/vocabulary.dart';
import '../widgets/notice_text.dart';

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

  /// Which shape the log was drawn in — the register above
  /// `AppBreakpoints.registerTable` of box, the card per record below it. Both
  /// carry the same keys and the same sentences; only the arrangement differs.
  static const ValueKey<String> tableKey = ValueKey<String>('actions-table');
  static const ValueKey<String> cardsKey = ValueKey<String>('actions-cards');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('action-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('action-status-$id');
  static ValueKey<String> ownerKey(String id) => ValueKey<String>('action-owner-$id');
  static ValueKey<String> dueKey(String id) => ValueKey<String>('action-due-$id');
  static ValueKey<String> escalatedKey(String id) => ValueKey<String>('action-escalated-$id');
  static ValueKey<String> measuresKey(String id) => ValueKey<String>('action-measures-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ActionsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            if (state is ActionsLoaded && state.notice != null) _Notice(message: noticeText(l10n, state.notice!)),
            if (state is ActionsLoaded && state.truncated) const _Truncated(),
            Expanded(
              child: switch (state) {
                ActionsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                ActionsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: l10n.actionsTheActionLogCouldNotBeRead,
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<ActionsBloc>().add(const ActionsStarted()),
                  ),
                ActionsLoaded(isLoadingActions: true) =>
                  const SkeletonList(rows: 4, maxWidth: maxWidth),
                ActionsLoaded(actions: final actions, isFiltered: final isFiltered)
                    when actions.isEmpty =>
                  _ActionsEmpty(isFiltered: isFiltered),
                ActionsLoaded(actions: final actions) => _ActionsList(actions: actions),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183).
///
/// This Module's `ShellRoute` creates `ActionsBloc` once and keeps it alive
/// while the caller reads an Action and comes back, so a Screen that only read
/// on `ActionsStarted` painted the list as it was when they left — rows raised
/// elsewhere, measures closed, counts moved, none of it visible. The Bloc
/// ignores the ask while its first load is still in flight, which is what a
/// Screen mounting mid-load looks like.
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
      context.read<ActionsBloc>().add(const ActionsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ActionsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = state is ActionsLoaded ? state as ActionsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: ActionsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.groupActions,
            description:
                l10n.actionsWhatThePlantOwesAtThisSite,
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: ActionsScreen.raiseKey,
                  onPressed: loaded.isRaising || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.actions}/new'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.commonRaiseAConcern),
                ),
            ],
            below: loaded == null ? null : _Filters(loaded: loaded),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFilterRow(
          children: [
            if (loaded.sites.length > 1)
              SizedBox(
                width: AppLayout.atTextScale(context, 220),
                child: DropdownButtonFormField<String>(
                  key: ActionsScreen.siteKey,
                  initialValue: loaded.siteId,
                  isDense: true,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.commonSite, border: OutlineInputBorder()),
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
              label: Text(loaded.orgUnitFilterName ?? l10n.commonAllOrgUnits),
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
                    ? l10n.actionsEscalatedToAnyone
                    : l10n.actionsEscalatedTo((loaded.escalatedToOrgUnitFilterName ?? '')),
              ),
            ),
            SizedBox(
              width: AppLayout.atTextScale(context, 190),
              child: DropdownButtonFormField<String?>(
                key: ActionsScreen.statusFilterKey,
                initialValue: loaded.statusFilter,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.commonStatus, border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l10n.nonconformancesAnyStatus)),
                  for (final (status, label) in actionStatusChoices(l10n))
                    DropdownMenuItem<String?>(value: status, child: Text(label)),
                ],
                onChanged: (status) =>
                    context.read<ActionsBloc>().add(ActionsStatusFilterChanged(status)),
              ),
            ),
            SizedBox(
              width: AppLayout.atTextScale(context, 210),
              child: DropdownButtonFormField<String?>(
                key: ActionsScreen.typeFilterKey,
                initialValue: loaded.typeFilter,
                isDense: true,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l10n.commonKindOfAction, border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l10n.actionsEveryKind)),
                  for (final (type, label) in actionTypeChoices(l10n))
                    DropdownMenuItem<String?>(value: type, child: Text(label)),
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
                Text(l10n.actionsShowClosed, style: theme.textTheme.bodyMedium),
              ],
            ),
            if (loaded.isFiltered || loaded.includeHistory)
              TextButton(
                key: ActionsScreen.clearFiltersKey,
                onPressed: () => context.read<ActionsBloc>().add(const ActionsFiltersCleared()),
                child: Text(l10n.workOrdersClearFilters),
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
      child: AppPageFrame(
        maxWidth: ActionsScreen.maxWidth,
        child: Padding(
          key: ActionsScreen.noticeKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: NoticeText(message, style: theme.textTheme.bodyMedium),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ActionsScreen.maxWidth,
        child: Padding(
          key: ActionsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            l10n.actionsThereAreMoreActionsThanThisList,
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
    final l10n = AppLocalizations.of(context);
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: ActionsEmptyKeys.matched,
        title: l10n.nonconformancesNoMatchTitle,
        message: l10n.actionsTheLogHasActionsButNoneOf,
        actionLabel: l10n.nonconformancesClearTheFilters,
        actionKey: ActionsScreen.emptyClearFiltersKey,
        onAction: () => context.read<ActionsBloc>().add(const ActionsFiltersCleared()),
      );
    }
    return PlatformEmptyState.noneExist(
      key: ActionsEmptyKeys.none,
      title: l10n.actionsNothingOnTheLog,
      message: l10n.actionsNoActionHasBeenRaisedAtThis,
      icon: Icons.assignment_outlined,
    );
  }
}

/// The two empty states' keys, named so a test can tell which story rendered.
abstract final class ActionsEmptyKeys {
  static const ValueKey<String> none = ActionsScreen.emptyKey;
  static const ValueKey<String> matched = ValueKey<String>('actions-empty-matched');
}

/// The register's one column spec (issue #396's design pass): `AppTableHeader`
/// and every `AppTableRow` are built from this list, so a label and its cells
/// start at the same x by construction.
///
/// Four of these are the columns the ticket names — owner, due, state and
/// source — because those are the four questions a reader of an action log asks
/// in order: who owes it, when is it due, is it still live, and where did it
/// come from. The fifth is the record's own title, which is what the row is
/// *about* and therefore takes the slack.
///
/// The State column states a measured `width` rather than a `flex`: a chip is
/// bounded content, and a column that took a share of the window would move the
/// same word's x on two Screens.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn(AppLocalizations.of(context).titleAction, flex: 6),
      AppTableColumn(AppLocalizations.of(context).commonOwner, flex: 2),
      AppTableColumn(AppLocalizations.of(context).pmSchedulesDue, flex: 3),
      AppTableColumn(AppLocalizations.of(context).actionsSource, flex: 2),
      AppTableColumn(AppLocalizations.of(context).commonState, width: _statusColumnWidth(context)),
    ];

/// The widest status label in a chip's own style at the reader's text scale,
/// plus the chip's padding and the slot's gutter — measured rather than guessed
/// so a renamed state cannot clip (the same measurement
/// `safety/incidents_screen.dart` makes for its own state column).
double _statusColumnWidth(BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  final l10n = AppLocalizations.of(context);
  for (final (_, label) in actionStatusChoices(l10n)) {
    painter.text = TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + Spacing.xxl + Spacing.sm;
}

/// The record an Action was raised from, in the words the detail Screen already
/// prints for the same three sources (issue #396).
///
/// Deliberately derived from the links the payload carries rather than from
/// `sourceType`: the words belong to the records, and a wire value this build
/// does not model (a Downtime event, a Work order) must not become a column of
/// snake_case. `Raised here` is what `standalone` reads as on screen — an Action
/// somebody raised on the log itself.
String sourceLabel(AppLocalizations l10n, Action action) {
  if (action.safetyIncident != null) return l10n.titleSafetyIncident;
  if (action.safetyObservation != null) return l10n.titleSafetyObservation;
  if (action.nonconformances.isNotEmpty) return l10n.titleNonConformance;
  return l10n.actionsSourceRaisedHere;
}

class _ActionsList extends StatelessWidget {
  const _ActionsList({required this.actions});

  final List<Action> actions;

  @override
  Widget build(BuildContext context) {
    final columns = _columns(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ActionsScreen.maxWidth,
        child: LayoutBuilder(
          builder: (context, box) {
            // The box this list was handed — the page less the Shell's rail and
            // this frame — never the window (the lesson of #105), and scaled by
            // the reader's text size (WCAG 1.4.4): five columns at twice the
            // text need twice the box before they read.
            final table =
                box.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.registerTable);
            if (!table) {
              return ListView.builder(
                key: ActionsScreen.cardsKey,
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                itemCount: actions.length,
                itemBuilder: (context, index) => _ActionRow(action: actions[index]),
              );
            }
            return ListView(
              key: ActionsScreen.tableKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  // The band's own fill would otherwise square off the card's
                  // rounded corners.
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTableHeader(columns: columns),
                      for (final action in actions)
                        _ActionTableRow(columns: columns, action: action),
                    ],
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

/// One Action as a row of the register.
///
/// **The row is two lines, and both are the point.** The first is the record's
/// title — the only unbounded text, so it is the cell that discloses its
/// clipping — and the second is the metadata a reader uses to place it: its
/// number, the kind of Action it is, its priority when it has one worth
/// flagging, how much answers it, and what it was handed up to. Squeezing those
/// five facts into a fifth one-line column was the alternative, and it produced
/// a register with nine columns, each too narrow to read.
///
/// The four columns beside it are one line each, so the row is as tall as the
/// tallest cell and no taller: owner, due (the overdue reading is a sentence,
/// never arithmetic on a date), source, and the state chip.
class _ActionTableRow extends StatelessWidget {
  const _ActionTableRow({required this.columns, required this.action});

  final List<AppTableColumn> columns;
  final Action action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    final floor = AppTypography.floor(context)?.copyWith(color: palette.textMuted);

    // The framework's own padded tap target is lifted on the chips: it would add
    // height to a row whose height is already the target.
    Widget shrinkWrapTargets(Widget child) => Theme(
          data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: child,
        );

    final meta = <Widget>[
      Text(action.actionNo, style: floor),
      // The kind of Action, chip and key exactly as the card below draws it:
      // `rowStatusKey` names this chip on both shapes of the log, so a test that
      // finds it by that key finds one thing whatever the window is.
      shrinkWrapTargets(
        StatusChip(
          key: ActionsScreen.rowStatusKey(action.id),
          label: action.typeLabel(l10n),
          tone: StatusTone.info,
        ),
      ),
      if (action.priority <= 2)
        Text(
          action.priorityLabel(l10n),
          style: floor?.copyWith(color: palette.statusWarning),
        ),
      if (action.measureCount > 0)
        Text(
          l10n.actionsOfThemCountermeasures(action.measureCount, action.countermeasureCount),
          key: ActionsScreen.measuresKey(action.id),
          style: floor,
        ),
      if (action.escalatedToOrgUnitName != null)
        Text(
          l10n.actionsEscalatedTo2((action.escalatedToOrgUnitName ?? '')),
          key: ActionsScreen.escalatedKey(action.id),
          style: floor,
        ),
    ];

    return KeyedSubtree(
      key: ActionsScreen.rowKey(action.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.actions}/${action.id}'),
        cells: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DisclosingText(
                action.title,
                style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Spacing.xxs),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: meta,
              ),
            ],
          ),
          DisclosingText(
            action.ownerName ?? 'Nobody yet',
            key: ActionsScreen.ownerKey(action.id),
            style: muted,
          ),
          Text(
            action.isOverdue
                ? l10n.commonOverdueByDays((action.daysOverdue ?? 0))
                : action.dueDate == null
                    ? l10n.actionsNoDueDate
                    : l10n.actionsDue((action.dueDate ?? '')),
            key: ActionsScreen.dueKey(action.id),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dense?.copyWith(
              color: action.isOverdue ? palette.statusDanger : palette.textMuted,
            ),
          ),
          Text(
            sourceLabel(l10n, action),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          shrinkWrapTargets(
            StatusChip(
              label: action.statusLabel(l10n),
              tone: action.statusTone,
            ),
          ),
        ],
      ),
    );
  }
}


class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                          label: action.typeLabel(l10n),
                          tone: StatusTone.info,
                        ),
                        StatusChip(label: action.statusLabel(l10n), tone: action.statusTone),
                        if (action.priority <= 2)
                          StatusChip(label: action.priorityLabel(l10n), tone: StatusTone.warning),
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
                          l10n.actionsOfThemCountermeasures(action.measureCount, action.countermeasureCount),
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
                    action.ownerName ?? l10n.commonNobodyYet,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    key: ActionsScreen.dueKey(action.id),
                    action.isOverdue
                        ? l10n.commonOverdueByDays((action.daysOverdue ?? 0))
                        : action.dueDate == null
                            ? l10n.actionsNoDueDate
                            : l10n.actionsDue((action.dueDate ?? '')),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: action.isOverdue
                          ? AppColors.of(context).statusDanger
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action.escalatedToOrgUnitName != null) ...[
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      key: ActionsScreen.escalatedKey(action.id),
                      l10n.actionsEscalatedTo2((action.escalatedToOrgUnitName ?? '')),
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
