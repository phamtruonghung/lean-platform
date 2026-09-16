/// The triage queue: the Requests still waiting for a decision at a Site, each
/// offering Accept, Decline and Mark duplicate (issue #72).
///
/// Readable by anyone whose role earns the Module, whatever their Grants — the
/// same reasoning `WorkOrdersScreen`'s own header documents. The three row
/// actions are offered only to a caller who holds a write Grant somewhere: an
/// action the server would refuse is not offered in the first place (the
/// coarse `orgUnitScope.canWriteSomewhere` signal, as `WorkOrdersScreen`
/// already uses).
///
/// Accepting raises a Work order for the Request; after any of the three
/// actions the Request has been triaged and leaves this queue. The link back
/// to the Work order an accepted Request produced is ADR-0014's, and the
/// requester follows it on `MyRequestsScreen`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'request.dart';
import 'request_accept_dialog.dart';
import 'request_decline_dialog.dart';
import 'request_duplicate_dialog.dart';
import 'requests_bloc.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.canTriage});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule `WorkOrdersScreen`
  /// applies to its own row actions. False hides Accept, Decline and Mark
  /// duplicate entirely; it does not grey them out, because a disabled button
  /// is still an invitation to fail.
  final bool canTriage;

  static const double maxWidth = 960;

  static const ValueKey<String> siteKey = ValueKey<String>('requests-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('requests-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('requests-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('requests-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('request-row-$id');
  static ValueKey<String> acceptKey(String id) => ValueKey<String>('request-accept-$id');
  static ValueKey<String> declineKey(String id) => ValueKey<String>('request-decline-$id');
  static ValueKey<String> duplicateKey(String id) => ValueKey<String>('request-duplicate-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'requests-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's waiting Requests renders — a
  /// different fact from [emptyKey]: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('requests-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RequestsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          if (state is RequestsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              RequestsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              RequestsUnavailable(message: final message) => PlatformFailureState(
                  key: RequestsScreen.failedKey,
                  title: 'The requests could not be read',
                  message: message,
                  retryKey: RequestsScreen.retryKey,
                  onRetry: () => context.read<RequestsBloc>().add(const RequestsStarted()),
                ),
              RequestsLoaded(isLoadingRequests: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              RequestsLoaded(requests: final requests) when requests.isEmpty =>
                const _RequestsEmpty(),
              RequestsLoaded(requests: final requests) =>
                _RequestsList(requests: requests, canTriage: canTriage),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RequestsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is RequestsLoaded ? state as RequestsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: RequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Triage queue', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'The Requests waiting for a decision at this Site. Accepting one raises '
                'a Work order for it.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: RequestsScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<RequestsBloc>().add(RequestsSiteSelected(siteId));
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
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: RequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: RequestsScreen.noticeKey,
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

/// The triage queue. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _RequestsList extends StatefulWidget {
  const _RequestsList({required this.requests, required this.canTriage});

  final List<Request> requests;
  final bool canTriage;

  @override
  State<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends State<_RequestsList> {
  /// What the filter box is narrowing the waiting Requests to, `''` when
  /// nothing is.
  String _term = '';

  /// Whether [request] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a Request — its
  /// own number, the sentences that describe it, and the Asset it was raised
  /// against. No ranking and no fuzzy matching, the same rule the assign
  /// dialog's own filter uses (issue #187).
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
        maxWidth: RequestsScreen.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppFilterField(
                name: RequestsScreen.filterFieldName,
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
                      key: RequestsScreen.noMatchKey,
                      title: 'No requests match',
                      message: 'Requests are waiting at this Site, but none matches '
                          '"${_term.trim()}". Try a different description or Asset.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) =>
                          _RequestCard(request: matches[index], canTriage: widget.canTriage),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.canTriage});

  final Request request;
  final bool canTriage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<RequestsBloc>().state;
    final busy = state is RequestsLoaded && state.isTriaging;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      key: RequestsScreen.rowKey(request.id),
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
                        '${request.assetName} (${request.assetCode}) · ${request.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(request.urgencyLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (request.reporterName != null)
                  Text('Raised by ${request.reporterName}', style: muted),
                if (request.productionStopped)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: Spacing.xxs),
                      Text(
                        'Production is stopped',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
              ],
            ),
            if (canTriage) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton(
                    key: RequestsScreen.acceptKey(request.id),
                    onPressed: busy ? null : () => _openAccept(context),
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: const Text('Accept'),
                  ),
                  OutlinedButton(
                    key: RequestsScreen.declineKey(request.id),
                    onPressed: busy ? null : () => _openDecline(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: const Text('Decline'),
                  ),
                  OutlinedButton(
                    key: RequestsScreen.duplicateKey(request.id),
                    onPressed: busy ? null : () => _openDuplicate(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: const Text('Mark duplicate'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAccept(BuildContext context) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `RequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it.
    final bloc = context.read<RequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestAcceptDialog(request: request),
      ),
    );
  }

  Future<void> _openDecline(BuildContext context) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `RequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it.
    final bloc = context.read<RequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestDeclineDialog(request: request),
      ),
    );
  }

  Future<void> _openDuplicate(BuildContext context) {
    final bloc = context.read<RequestsBloc>();
    final state = bloc.state;
    final candidates = state is RequestsLoaded
        ? [for (final other in state.requests) if (other.id != request.id) other]
        : const <Request>[];
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestDuplicateDialog(request: request, candidates: candidates),
      ),
    );
  }
}

class _RequestsEmpty extends StatelessWidget {
  const _RequestsEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: RequestsScreen.emptyKey,
      title: 'Nothing is waiting',
      message: 'No Requests are waiting for a decision at this Site.',
    );
  }
}
