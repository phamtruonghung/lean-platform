/// The Requests this caller raised, every status — what became of each,
/// including the Work order an accepted one turned into (issue #72, ADR-0014).
///
/// This is the operator-facing Destination: anyone admitted may reach it, and
/// raising a Request needs only a read Grant reaching the Asset's Org Unit
/// (the server's own rule). The "Raise a Request" button is offered only to a
/// caller who holds at least one Grant somewhere — an action the server would
/// refuse is not offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'my_requests_bloc.dart';
import 'request.dart';
import 'request_form_dialog.dart';

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key, required this.canRaiseRequest});

  /// Whether this caller holds a Grant anywhere at all. Raising needs only a
  /// read Grant (the server passes `write: false`), so this is
  /// `orgUnitScope.canReadSomewhere` — deliberately not `canWriteSomewhere`,
  /// which would hide the affordance from a read-only Grant that the server
  /// would in fact allow. False hides the button entirely; it does not grey it
  /// out, because a disabled button is still an invitation to fail.
  final bool canRaiseRequest;

  static const double maxWidth = 960;

  static const ValueKey<String> raiseKey = ValueKey<String>('my-requests-add');
  static const ValueKey<String> siteKey = ValueKey<String>('my-requests-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('my-requests-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('my-requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('my-requests-empty');
  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('my-requests-empty-raise');
  static const ValueKey<String> failedKey = ValueKey<String>('my-requests-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('my-request-row-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'my-requests-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the caller's own Requests renders — a
  /// different fact from [emptyKey]: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('my-requests-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MyRequestsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseRequest: canRaiseRequest),
          if (state is MyRequestsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              MyRequestsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              MyRequestsUnavailable(message: final message) => PlatformFailureState(
                  key: MyRequestsScreen.failedKey,
                  title: 'Your requests could not be read',
                  message: message,
                  retryKey: MyRequestsScreen.retryKey,
                  onRetry: () => context.read<MyRequestsBloc>().add(const MyRequestsStarted()),
                ),
              MyRequestsLoaded(isLoadingRequests: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              MyRequestsLoaded(requests: final requests, siteId: final siteId)
                  when requests.isEmpty =>
                _MyRequestsEmpty(canRaiseRequest: canRaiseRequest, siteId: siteId),
              MyRequestsLoaded(requests: final requests) => _MyRequestsList(requests: requests),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canRaiseRequest});

  final MyRequestsState state;
  final bool canRaiseRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is MyRequestsLoaded ? state as MyRequestsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: MyRequestsScreen.maxWidth,
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
                        Text('My requests', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'What you raised, and what became of each.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canRaiseRequest && loaded != null)
                    FilledButton.icon(
                      key: MyRequestsScreen.raiseKey,
                      onPressed: loaded.isRaising || loaded.siteId == null
                          ? null
                          : () => _openRaise(context, loaded.siteId!),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise a Request'),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: MyRequestsScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<MyRequestsBloc>().add(MyRequestsSiteSelected(siteId));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRaise(BuildContext context, String siteId) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `MyRequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it, the same shape `WorkOrdersScreen._openOrgUnitFilter`
    // already uses for its picker's Bloc.
    final bloc = context.read<MyRequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<MyRequestsBloc>.value(
        value: bloc,
        child: RequestFormDialog(siteId: siteId),
      ),
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
        maxWidth: MyRequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: MyRequestsScreen.noticeKey,
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

/// The caller's own Requests. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _MyRequestsList extends StatefulWidget {
  const _MyRequestsList({required this.requests});

  final List<Request> requests;

  @override
  State<_MyRequestsList> createState() => _MyRequestsListState();
}

class _MyRequestsListState extends State<_MyRequestsList> {
  /// What the filter box is narrowing the caller's own Requests to, `''` when
  /// nothing is.
  String _term = '';

  /// Whether [request] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a Request — its
  /// own number, the sentences that describe it, and the Asset it was raised
  /// against — so chasing one is one term rather than a walk through them all
  /// (issue #191, user story 7).
  static bool _matches(Request request, String term) =>
      request.requestNo.toLowerCase().contains(term) ||
      request.summary.toLowerCase().contains(term) ||
      (request.description ?? '').toLowerCase().contains(term) ||
      request.assetName.toLowerCase().contains(term) ||
      request.assetCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Request> get _matchingRequests {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.requests;
    return widget.requests.where((request) => _matches(request, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingRequests;
    return Center(
      child: AppPageFrame(
        maxWidth: MyRequestsScreen.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppFilterField(
                name: MyRequestsScreen.filterFieldName,
                label: 'Filter requests',
                helperText: 'By description, Request number or Asset.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.requests.length,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: matches.isEmpty
                  ? PlatformEmptyState.noneMatched(
                      key: MyRequestsScreen.noMatchKey,
                      title: 'No requests match',
                      message: 'You have Requests at this Site, but none matches '
                          '"${_term.trim()}". Try a different description or Asset.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) => _MyRequestCard(request: matches[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRequestCard extends StatelessWidget {
  const _MyRequestCard({required this.request});

  final Request request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final workOrder = request.workOrder;

    return Card(
      key: MyRequestsScreen.rowKey(request.id),
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
                      Text(request.requestNo, style: muted),
                      const SizedBox(height: Spacing.xxs),
                      Text(request.summary, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${request.assetName} (${request.assetCode}) · ${request.urgencyLabel}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                StatusChip(label: request.statusLabel, tone: request.statusTone),
              ],
            ),
            if (workOrder != null) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(Icons.build_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      'Became Work order ${workOrder.workOrderNo}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (request.status == 'rejected' && request.rejectionReason != null) ...[
              const SizedBox(height: Spacing.sm),
              Text('Declined: ${request.rejectionReason}', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyRequestsEmpty extends StatelessWidget {
  const _MyRequestsEmpty({required this.canRaiseRequest, required this.siteId});

  final bool canRaiseRequest;
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    return PlatformEmptyState.noneExist(
      key: MyRequestsScreen.emptyKey,
      title: 'Nothing raised yet',
      message: 'You have not raised any Requests at this Site. Raise one and it will '
          'show up here with whatever becomes of it.',
      actionLabel: canRaiseRequest && siteId != null ? 'Raise a Request' : null,
      actionKey: MyRequestsScreen.emptyRaiseKey,
      onAction: canRaiseRequest && siteId != null
          ? () {
              final bloc = context.read<MyRequestsBloc>();
              showDialog<void>(
                context: context,
                builder: (_) => BlocProvider<MyRequestsBloc>.value(
                  value: bloc,
                  child: RequestFormDialog(siteId: siteId!),
                ),
              );
            }
          : null,
    );
  }
}
