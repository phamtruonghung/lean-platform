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
import '../widgets/skeleton_list.dart';
import 'assign_work_order_dialog.dart';
import 'complete_work_order_dialog.dart';
import 'org_unit_chooser.dart';
import 'work_order.dart';
import 'work_order_form_dialog.dart';
import 'work_orders_bloc.dart';

class WorkOrdersScreen extends StatelessWidget {
  const WorkOrdersScreen({super.key, required this.canRaiseWorkOrder, required this.canAssign});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule `AssetsScreen`
  /// applies to its own "Add an Asset" button. False hides the raise
  /// affordance entirely; it does not grey it out, because a disabled button
  /// is still an invitation to fail.
  final bool canRaiseWorkOrder;

  /// Whether the write actions on an open row are offered at all — the same
  /// write-Grant test as [canRaiseWorkOrder]. Assigning is a write (issue
  /// #62) and so are starting, completing and cancelling a Work order (issue
  /// #63): the server refuses any of them outside the caller's Grants, so a
  /// caller without a write Grant is offered no write action on a row, the
  /// same way it is offered no way to raise.
  final bool canAssign;

  static const double maxWidth = 900;
  static const ValueKey<String> raiseKey = ValueKey<String>('work-orders-add');
  static const ValueKey<String> siteKey = ValueKey<String>('work-orders-site');
  static const ValueKey<String> filterKey = ValueKey<String>('work-orders-org-unit-filter');
  static const ValueKey<String> clearFilterKey = ValueKey<String>('work-orders-clear-filter');
  static const ValueKey<String> noticeKey = ValueKey<String>('work-orders-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('work-orders-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('work-orders-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('work-orders-failed');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('work-order-row-$id');
  static ValueKey<String> assignKey(String id) => ValueKey<String>('work-order-assign-$id');
  static ValueKey<String> startKey(String id) => ValueKey<String>('work-order-start-$id');
  static ValueKey<String> completeKey(String id) => ValueKey<String>('work-order-complete-$id');
  static ValueKey<String> cancelKey(String id) => ValueKey<String>('work-order-cancel-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrdersBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseWorkOrder: canRaiseWorkOrder),
          // The last write that landed, or the last transition refused — the
          // former is an informational banner, the latter an error-styled one,
          // so the caller can tell "your work order was completed" from "the
          // server declined that", without hunting.
          if (state is WorkOrdersLoaded && state.transitionFailure != null)
            _Notice(message: state.transitionFailure!, isError: true),
          if (state is WorkOrdersLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              WorkOrdersLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              WorkOrdersUnavailable(message: final message) => _WorkOrdersFailed(message: message),
              WorkOrdersLoaded(isLoadingWorkOrders: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              WorkOrdersLoaded(workOrders: final workOrders, orgUnitFilterName: final filterName)
                  when workOrders.isEmpty =>
                _WorkOrdersEmpty(orgUnitFilterName: filterName),
              WorkOrdersLoaded(workOrders: final workOrders) =>
                _WorkOrdersList(
                  workOrders: workOrders,
                  canAssign: canAssign,
                  transitioningId: state.transitioningId,
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
                        Text(
                          'Every open job raised at this Site, which Asset it is '
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
  const _Notice({required this.message, this.isError = false});

  final String message;

  /// True for a refused write (a transition the server declined): rendered in
  /// the error palette rather than the informational one, so a failure is not
  /// mistaken for a success banner.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final containerColor =
        isError ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer;
    final contentColor =
        isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WorkOrdersScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: WorkOrdersScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.info_outline,
                  size: 20,
                  color: contentColor,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: contentColor),
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

class _WorkOrdersList extends StatelessWidget {
  const _WorkOrdersList({required this.workOrders, required this.canAssign, required this.transitioningId});

  final List<WorkOrder> workOrders;
  final bool canAssign;

  /// The Work order whose transition is in flight — its action buttons are
  /// disabled so a second tap on the same row cannot send a second request.
  final String? transitioningId;

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
            isTransitioning: transitioningId == workOrders[index].id,
          ),
        ),
      ),
    );
  }
}

/// One open Work order: what it is, who has it, and — for a caller with a
/// write Grant — the lifecycle actions this slice offers (issue #63). Those
/// follow the row's status: `approved` (agreed) can be started or cancelled;
/// `in_progress` can be completed or cancelled; a completed or cancelled Work
/// order is not in this open list at all, so no action is offered on a row
/// that is not here. A caller without a write Grant is offered no transition,
/// exactly as it is offered no way to raise or to assign — an action the
/// server would refuse is not offered in the first place.
class _WorkOrderRow extends StatelessWidget {
  const _WorkOrderRow({
    required this.workOrder,
    required this.canAssign,
    required this.isTransitioning,
  });

  final WorkOrder workOrder;
  final bool canAssign;
  final bool isTransitioning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                if (canAssign)
                  IconButton(
                    key: WorkOrdersScreen.assignKey(workOrder.id),
                    tooltip: 'Assign this Work order',
                    icon: const Icon(Icons.person_add_alt_outlined),
                    onPressed: () =>
                        AssignWorkOrderDialog.open(context, workOrderId: workOrder.id),
                  ),
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
            // Lifecycle actions (issue #63), offered only to a caller with a
            // write Grant, and only on a status this slice can act on. Each is
            // a small TextButton rather than an icon, so what it does is said
            // rather than guessed; the server is still the arbiter, so an
            // action the server would refuse is a 400 surfaced as a notice,
            // not a button that lied.
            if (canAssign &&
                (workOrder.canStart || workOrder.canComplete || workOrder.canCancel)) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  if (workOrder.canStart)
                    TextButton.icon(
                      key: WorkOrdersScreen.startKey(workOrder.id),
                      onPressed: isTransitioning
                          ? null
                          : () => context
                              .read<WorkOrdersBloc>()
                              .add(WorkOrderStartPressed(workOrder.id)),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start'),
                    ),
                  if (workOrder.canComplete)
                    TextButton.icon(
                      key: WorkOrdersScreen.completeKey(workOrder.id),
                      onPressed: isTransitioning
                          ? null
                          : () => CompleteWorkOrderDialog.open(context, workOrderId: workOrder.id),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Complete'),
                    ),
                  if (workOrder.canCancel)
                    TextButton.icon(
                      key: WorkOrdersScreen.cancelKey(workOrder.id),
                      onPressed: isTransitioning
                          ? null
                          : () => context
                              .read<WorkOrdersBloc>()
                              .add(WorkOrderCancelPressed(workOrder.id)),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkOrdersEmpty extends StatelessWidget {
  const _WorkOrdersEmpty({required this.orgUnitFilterName});

  /// The Org Unit the list is narrowed to, or null for the whole Site — the
  /// headline must agree with whichever the `_Header` above is already
  /// showing ("Narrowed to Line 1"), not always claim the whole Site.
  final String? orgUnitFilterName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filterName = orgUnitFilterName;
    return Center(
      key: WorkOrdersScreen.emptyKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.build_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text(
                filterName == null ? 'No open work at this Site' : 'No open work at $filterName',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Nothing is currently raised here. Raise a Work order and it will '
                'show up right away.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkOrdersFailed extends StatelessWidget {
  const _WorkOrdersFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: WorkOrdersScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The Work orders could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: WorkOrdersScreen.retryKey,
                onPressed: () => context.read<WorkOrdersBloc>().add(const WorkOrdersStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
