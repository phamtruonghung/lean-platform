/// The open Work order list: what is currently raised against the Site's
/// Assets, who has it, and a way to raise a new one (issue #57).
///
/// Readable by anyone whose role earns the Module, whatever their Grants —
/// the same reasoning `AssetsScreen`'s own header documents. Raising is
/// offered only to a caller who holds a write Grant somewhere: an action the
/// server would refuse is not offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'org_unit_chooser.dart';
import 'work_order.dart';
import 'work_order_assign_dialog.dart';
import 'work_order_cancel_dialog.dart';
import 'work_order_complete_dialog.dart';
import 'work_order_form_dialog.dart';
import 'work_orders_bloc.dart';

class WorkOrdersScreen extends StatelessWidget {
  const WorkOrdersScreen({
    super.key,
    required this.canRaiseWorkOrder,
    required this.canAssignWorkOrder,
    required this.canWorkWorkOrder,
  });

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule `AssetsScreen`
  /// applies to its own "Add an Asset" button. False hides the raise
  /// affordance entirely; it does not grey it out, because a disabled button
  /// is still an invitation to fail.
  final bool canRaiseWorkOrder;

  /// Same coarse signal as [canRaiseWorkOrder], and the same reason (issue
  /// #62): `/me` reports which Org Units are granted but not their ancestry,
  /// so the client cannot tell whether a Grant *reaches* this particular Work
  /// order's Org Unit. The server is the real gate (403); this only avoids
  /// offering an action to a caller who holds no write Grant anywhere at all.
  /// False hides the assign affordance entirely, for the same reason —
  /// absent, not disabled.
  final bool canAssignWorkOrder;

  /// Same coarse signal as [canAssignWorkOrder], and the same reason (issue
  /// #63): a separate flag rather than reusing [canAssignWorkOrder] — each
  /// affordance carries its own justification in this codebase, even though
  /// both read off the same `orgUnitScope.canWriteSomewhere` today. False
  /// hides Start, Complete and Cancel entirely — absent, not disabled.
  final bool canWorkWorkOrder;

  static const double maxWidth = 900;
  static const ValueKey<String> raiseKey = ValueKey<String>('work-orders-add');
  static const ValueKey<String> siteKey = ValueKey<String>('work-orders-site');
  static const ValueKey<String> filterKey = ValueKey<String>('work-orders-org-unit-filter');
  static const ValueKey<String> clearFilterKey = ValueKey<String>('work-orders-clear-filter');
  static const ValueKey<String> noticeKey = ValueKey<String>('work-orders-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('work-orders-retry');

  /// The "nothing has ever been raised" empty state (issue #103's
  /// `EmptyStateVariant.noneExist`) — unfiltered, genuinely nothing at this
  /// Site. Kept as `work-orders-empty`, its pre-#103 name, so the existing
  /// test asserting this key stays meaningful rather than silently starting
  /// to assert on the wrong variant.
  static const ValueKey<String> emptyKey = ValueKey<String>('work-orders-empty');

  /// The "your filter matched nothing" empty state
  /// (`EmptyStateVariant.noneMatched`) — an Org Unit filter is narrowing the
  /// list and nothing in that narrower scope is currently open.
  static const ValueKey<String> emptyFilteredKey = ValueKey<String>('work-orders-empty-filtered');

  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('work-orders-empty-raise');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('work-orders-empty-clear-filters');
  static const ValueKey<String> failedKey = ValueKey<String>('work-orders-failed');
  static const ValueKey<String> scopeRefusedKey = ValueKey<String>('work-orders-scope-refused');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('work-order-row-$id');

  /// One key, two labels — unlike `AssetsScreen.retireKey`/`reinstateKey`,
  /// which are two keys because they are two different acts. Assigning and
  /// reassigning are one act (AC5), so the key is stable and only the label
  /// changes.
  static ValueKey<String> assignKey(String id) => ValueKey<String>('work-order-assign-$id');

  /// Three separate keys, not one — unlike [assignKey]: starting, completing
  /// and cancelling are three different acts, so this follows
  /// `AssetsScreen.retireKey`/`reinstateKey` instead (issue #63).
  static ValueKey<String> startKey(String id) => ValueKey<String>('work-order-start-$id');
  static ValueKey<String> completeKey(String id) => ValueKey<String>('work-order-complete-$id');
  static ValueKey<String> cancelKey(String id) => ValueKey<String>('work-order-cancel-$id');
  static const ValueKey<String> showHistoryKey = ValueKey<String>('work-orders-show-history');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrdersBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseWorkOrder: canRaiseWorkOrder),
          if (state is WorkOrdersLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              WorkOrdersLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              // The scope refusal (#103's fifth case) is checked before the
              // ordinary failure below, and matched on its own field pattern
              // rather than folded into it, so a scope-refused read can
              // never fall through to `PlatformFailureState`'s generic
              // wording — see `WorkOrdersUnavailable.isScopeRefused`'s own
              // doc comment for why this read cannot actually produce one
              // today and why the branch is kept anyway.
              WorkOrdersUnavailable(isScopeRefused: true) =>
                const PlatformScopeRefusedState(key: WorkOrdersScreen.scopeRefusedKey),
              WorkOrdersUnavailable(message: final message) => PlatformFailureState(
                  key: WorkOrdersScreen.failedKey,
                  title: 'The Work orders could not be read',
                  message: message,
                  retryKey: WorkOrdersScreen.retryKey,
                  onRetry: () => context.read<WorkOrdersBloc>().add(const WorkOrdersStarted()),
                ),
              WorkOrdersLoaded(isLoadingWorkOrders: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              WorkOrdersLoaded(
                workOrders: final workOrders,
                orgUnitFilterId: final filterId,
                orgUnitFilterName: final filterName,
                showHistory: final showHistory
              )
                  when workOrders.isEmpty =>
                _WorkOrdersEmpty(
                  orgUnitFilterId: filterId,
                  orgUnitFilterName: filterName,
                  showHistory: showHistory,
                  canRaiseWorkOrder: canRaiseWorkOrder,
                ),
              WorkOrdersLoaded(workOrders: final workOrders) => _WorkOrdersList(
                  workOrders: workOrders,
                  canAssign: canAssignWorkOrder,
                  canWork: canWorkWorkOrder,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canRaiseWorkOrder});

  final WorkOrdersState state;
  final bool canRaiseWorkOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is WorkOrdersLoaded ? state as WorkOrdersLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WorkOrdersScreen.maxWidth),
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
                        Text('Work orders', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        // "Every open job" stopped being true once the history
                        // toggle can bring completed and cancelled rows back
                        // (issue #63) — neutral wording that holds either way.
                        Text(
                          'The work raised at this Site, which Asset it is '
                          'against, and who has it.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canRaiseWorkOrder && loaded != null)
                    FilledButton.icon(
                      key: WorkOrdersScreen.raiseKey,
                      onPressed: loaded.isRaising
                          ? null
                          : () => WorkOrderFormDialog.open(context, siteId: loaded.siteId!),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise a Work order'),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: WorkOrdersScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<WorkOrdersBloc>().add(WorkOrdersSiteSelected(siteId));
                    },
                  ),
                ),
              ],
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                if (loaded.orgUnitFilterId == null)
                  OutlinedButton.icon(
                    key: WorkOrdersScreen.filterKey,
                    onPressed: () => _openOrgUnitFilter(context, loaded.siteId!),
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Narrow to an Org Unit'),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Narrowed to ${loaded.orgUnitFilterName}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        key: WorkOrdersScreen.clearFilterKey,
                        tooltip: 'Show the whole Site again',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            context.read<WorkOrdersBloc>().add(const WorkOrdersOrgUnitFilterCleared()),
                      ),
                    ],
                  ),
                const SizedBox(height: Spacing.md),
                FilterChip(
                  key: WorkOrdersScreen.showHistoryKey,
                  label: const Text('Show completed and cancelled'),
                  selected: loaded.showHistory,
                  // Same guard `AssetsScreen.showRetiredKey` uses for its own
                  // chip: toggling while a raise, assign or transition is in
                  // flight would interleave the re-read with that write's own
                  // mutation and could wipe a pending success notice before
                  // the caller ever sees it.
                  onSelected: loaded.isRaising || loaded.isAssigning || loaded.isTransitioning
                      ? null
                      : (value) =>
                          context.read<WorkOrdersBloc>().add(WorkOrdersShowHistoryChanged(value)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a chooser over the same tree `OrgUnitChooser` already browses for
/// placing an Asset (#56) — the real tree engine (`OrgUnitPickerBloc`), not
/// the Grant-editing `OrgUnitPicker` widget, which carries a mandatory level
/// on every row that has no meaning here.
Future<void> _openOrgUnitFilter(BuildContext context, String siteId) async {
  final bloc = context.read<WorkOrdersBloc>();
  final peopleApi = context.read<PeopleApi>();
  final authGateway = context.read<AuthGateway>();
  final chosen = await showDialog<OrgUnitNode>(
    context: context,
    builder: (dialogContext) => BlocProvider<OrgUnitPickerBloc>(
      create: (_) => OrgUnitPickerBloc(
        peopleApi: peopleApi,
        authGateway: authGateway,
        initialSiteId: siteId,
      )..add(const OrgUnitPickerStarted()),
      child: const _OrgUnitFilterDialog(),
    ),
  );
  if (chosen != null) {
    bloc.add(WorkOrdersOrgUnitFilterSelected(orgUnitId: chosen.id, orgUnitName: chosen.name));
  }
}

class _OrgUnitFilterDialog extends StatelessWidget {
  const _OrgUnitFilterDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Narrow to an Org Unit'),
      content: SizedBox(
        width: 480,
        child: OrgUnitChooser(
          selectedId: null,
          onSelected: (node) => Navigator.of(context).pop(node),
          // The filter is scoped to the Site the list is already showing —
          // browsing a different Site's tree from inside it would let the
          // header end up naming an Org Unit outside that Site.
          showSitePicker: false,
          title: 'Narrow the list',
          description: 'Choose the Org Unit to narrow the list to. Everything beneath it is '
              'included too.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
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
        constraints: const BoxConstraints(maxWidth: WorkOrdersScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: WorkOrdersScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The transitions offered from [status] (issue #63) — `approved` offers
/// Start, `in_progress` offers Complete; both offer Cancel. Every other
/// status, reachable only through history, offers none of the three: a
/// completed or cancelled Work order is terminal, and the four the schema
/// allows but this slice does not offer (`draft`, `scheduled`, `on_hold`,
/// `closed`) are unreachable through this list anyway.
bool _offersStart(String status) => status == 'approved';
bool _offersComplete(String status) => status == 'in_progress';
bool _offersCancel(String status) => status == 'approved' || status == 'in_progress';

class _WorkOrdersList extends StatelessWidget {
  const _WorkOrdersList({required this.workOrders, required this.canAssign, required this.canWork});

  final List<WorkOrder> workOrders;
  final bool canAssign;
  final bool canWork;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WorkOrdersScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: workOrders.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _WorkOrderRow(
            workOrder: workOrders[index],
            canAssign: canAssign,
            canWork: canWork,
          ),
        ),
      ),
    );
  }
}

class _WorkOrderRow extends StatelessWidget {
  const _WorkOrderRow({required this.workOrder, required this.canAssign, required this.canWork});

  final WorkOrder workOrder;
  final bool canAssign;
  final bool canWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<WorkOrdersBloc>().state;
    final isAssigning = state is WorkOrdersLoaded && state.isAssigning;
    final isTransitioning = state is WorkOrdersLoaded && state.isTransitioning;
    // Every row's actions are disabled by any action in flight, not only this
    // row's own — the same reasoning `AssetsScreen`'s `disabled` flag
    // documents: a second row's confirm-then-dispatch must not reach the Bloc
    // while a different write is still settling.
    final busy = isAssigning || isTransitioning;
    return Card(
      key: WorkOrdersScreen.rowKey(workOrder.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
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
                      Text(
                        workOrder.summary,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${workOrder.assetName} (${workOrder.assetCode}) · ${workOrder.workTypeLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(workOrder.statusLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                // Never a blank when nobody has it yet — "Unassigned" says so
                // plainly, the contract issue #57 sets for a null assignee.
                Text(workOrder.assigneeName ?? 'Unassigned', style: theme.textTheme.bodyMedium),
                const SizedBox(width: Spacing.lg),
                Icon(Icons.account_tree_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Text(
                  workOrder.orgUnitName,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (canAssign || (canWork && _offersCancel(workOrder.status))) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  if (canAssign) ...[
                    OutlinedButton(
                      key: WorkOrdersScreen.assignKey(workOrder.id),
                      onPressed: busy
                          ? null
                          : () => WorkOrderAssignDialog.open(context, workOrder: workOrder),
                      child: Text(workOrder.assignedTo == null ? 'Assign' : 'Reassign'),
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                  // Start/Complete/Cancel: absent, not disabled, for a caller
                  // with no write Grant anywhere at all — the server would
                  // refuse it, so the interface does not invite it (the same
                  // rule `canAssign` already follows). Which of the three
                  // shows depends on the row's own status (§3's state
                  // machine); `busy` disables all of them, on every row,
                  // while any action — assign or transition — is in flight.
                  if (canWork && _offersStart(workOrder.status))
                    OutlinedButton(
                      key: WorkOrdersScreen.startKey(workOrder.id),
                      onPressed: busy
                          ? null
                          : () => context
                              .read<WorkOrdersBloc>()
                              .add(WorkOrderStartConfirmed(workOrder.id)),
                      child: const Text('Start'),
                    ),
                  if (canWork && _offersComplete(workOrder.status)) ...[
                    if (canAssign || _offersStart(workOrder.status)) const SizedBox(width: Spacing.sm),
                    OutlinedButton(
                      key: WorkOrdersScreen.completeKey(workOrder.id),
                      onPressed: busy
                          ? null
                          : () => WorkOrderCompleteDialog.open(context, workOrder: workOrder),
                      child: const Text('Complete'),
                    ),
                  ],
                  if (canWork && _offersCancel(workOrder.status)) ...[
                    const SizedBox(width: Spacing.sm),
                    OutlinedButton(
                      key: WorkOrdersScreen.cancelKey(workOrder.id),
                      onPressed: busy
                          ? null
                          : () => WorkOrderCancelDialog.open(context, workOrder: workOrder),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The two empty stories issue #103 asks this Screen to tell apart — see
/// `PlatformEmptyState`'s own header for the general reasoning, and this
/// class for the worked example the ticket names.
class _WorkOrdersEmpty extends StatelessWidget {
  const _WorkOrdersEmpty({
    required this.orgUnitFilterId,
    required this.orgUnitFilterName,
    required this.showHistory,
    required this.canRaiseWorkOrder,
  });

  /// The Org Unit the list is narrowed to, or null for the whole Site. Its
  /// presence, not [showHistory], is what decides which of the two empty
  /// stories this is: a filter can matched-nothing, but broadening the read
  /// with "Show completed and cancelled" on an unfiltered, genuinely-empty
  /// Site is still "nothing exists", not "nothing matched" — there is no
  /// filter for a caller to clear in that case.
  final String? orgUnitFilterId;
  final String? orgUnitFilterName;

  /// Whether the list is currently showing completed and cancelled Work
  /// orders too (issue #63) — "No open work" is wrong once the caller has
  /// asked to see everything and there is still nothing at all.
  final bool showHistory;

  /// Same coarse signal `_Header`'s own raise button reads — whether this
  /// caller holds a write Grant anywhere at all. Read again here rather than
  /// shared through the header: the empty state carries its own action per
  /// #103's own requirement ("it carries the action that resolves it"), on
  /// top of — not instead of — the persistent one in the header.
  final bool canRaiseWorkOrder;

  @override
  Widget build(BuildContext context) {
    if (orgUnitFilterId != null) {
      return PlatformEmptyState.noneMatched(
        key: WorkOrdersScreen.emptyFilteredKey,
        title: 'No work orders match',
        message: 'There is work at this Site, but none of it is raised at '
            '${orgUnitFilterName ?? 'this Org Unit'} or beneath it'
            '${showHistory ? '' : ' and still open'}.',
        actionLabel: 'Clear filters',
        actionKey: WorkOrdersScreen.emptyClearFiltersKey,
        onAction: () => context.read<WorkOrdersBloc>().add(const WorkOrdersOrgUnitFilterCleared()),
      );
    }

    final state = context.watch<WorkOrdersBloc>().state;
    final loaded = state is WorkOrdersLoaded ? state : null;
    return PlatformEmptyState.noneExist(
      key: WorkOrdersScreen.emptyKey,
      title: showHistory ? 'No work at this Site' : 'No open work at this Site',
      message: 'Nothing has been raised against the Org Units you can act in. Raise a '
          'Work order and it will show up right away.',
      actionLabel: canRaiseWorkOrder && loaded?.siteId != null ? 'Raise a Work order' : null,
      actionKey: WorkOrdersScreen.emptyRaiseKey,
      onAction: canRaiseWorkOrder && loaded?.siteId != null
          ? () => WorkOrderFormDialog.open(context, siteId: loaded!.siteId!)
          : null,
    );
  }
}
