/// The requester's own view of the Maintenance Module (issue #72): every
/// Request this Account raised, what became of each — and, for an accepted
/// one, the Work order it turned into (ADR-0014) — plus a way to raise more.
///
/// This is the Destination that earns an operator the Module: it is the whole
/// of what a floor worker needs, and it does not offer the triage queue or the
/// Work order Screen, every action of which the server would refuse them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'maintenance_request.dart';
import 'request_form_dialog.dart';
import 'requests_bloc.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.canRaiseRequest});

  /// Whether this caller holds a Grant reaching some Asset's Org Unit —
  /// raising a Request needs any Grant (read or write), unlike triaging which
  /// needs a write one. False hides the raise affordance.
  final bool canRaiseRequest;

  static const double maxWidth = 900;
  static const ValueKey<String> raiseKey = ValueKey<String>('requests-add');
  static const ValueKey<String> siteKey = ValueKey<String>('requests-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('requests-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('requests-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('requests-failed');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('request-row-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RequestsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseRequest: canRaiseRequest),
          if (state is RequestsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              RequestsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              RequestsUnavailable(message: final message) => _RequestsFailed(message: message),
              RequestsLoaded(isLoadingRequests: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              RequestsLoaded(requests: final requests) when requests.isEmpty =>
                const _RequestsEmpty(),
              RequestsLoaded(requests: final requests) => _RequestsList(requests: requests),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canRaiseRequest});

  final RequestsState state;
  final bool canRaiseRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is RequestsLoaded ? state as RequestsLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: RequestsScreen.maxWidth),
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
                          'Everything you have asked maintenance to look at, and what '
                          'became of each — accepted into a Work order, declined, or '
                          'marked a duplicate.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canRaiseRequest && loaded != null)
                    FilledButton.icon(
                      key: RequestsScreen.raiseKey,
                      onPressed: loaded.isRaising
                          ? null
                          : () => RequestFormDialog.open(context, siteId: loaded.siteId!),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise a Request'),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                // The Site is only used to pick an Asset when raising — the
                // list itself is the caller's Requests regardless of Site, since
                // only the Account that raised them can ever see them.
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: RequestsScreen.maxWidth),
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
                  child: Text(message, style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({required this.requests});

  final List<MaintenanceRequest> requests;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: RequestsScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _RequestRow(request: requests[index]),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final MaintenanceRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workOrder = request.workOrder;
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
                      Text(request.summary, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${request.assetName} (${request.assetCode}) · ${request.urgencyLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(request.statusLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Text(
                  _relativeTime(request.reportedAt),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (request.productionStopped) ...[
                  const SizedBox(width: Spacing.lg),
                  Icon(Icons.warning_amber_outlined, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: Spacing.xs),
                  Text('Production stopped', style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error)),
                ],
              ],
            ),
            if (workOrder != null) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(Icons.build_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    'Accepted as ${workOrder.workOrderNo} — ${workOrder.statusLabel ?? workOrder.status}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ] else if (request.status == 'rejected' && request.rejectionReason != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Declined: ${request.rejectionReason}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ] else if (request.status == 'duplicate' && request.duplicateOfNo != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'A duplicate of ${request.duplicateOfNo}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime when) {
  final difference = DateTime.now().difference(when);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

class _RequestsEmpty extends StatelessWidget {
  const _RequestsEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: RequestsScreen.emptyKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('No requests yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Ask maintenance to look at something and it will show up here, '
                'along with what becomes of it.',
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

class _RequestsFailed extends StatelessWidget {
  const _RequestsFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: RequestsScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The requests could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: RequestsScreen.retryKey,
                onPressed: () => context.read<RequestsBloc>().add(const RequestsStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}