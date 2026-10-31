/// Leave requests (issue #265): an Employee asks to be away for a run of
/// days, and a person with authority approves or rejects it. Two views over
/// one list — "Mine", the caller's own requests with a "Request leave" action,
/// and "To decide", the pending requests the caller may decide.
///
/// Its Destination is offered to every active Account: anyone may ask for
/// leave. "To decide" is offered only when [canDecide] — the router reads that
/// once from `OrgUnitScope.canWriteSomewhere` (an administrator reaches
/// everywhere, so the same test covers them). That is a coarse offer, not the
/// decision: whether a given row may be approved or cancelled is the
/// server's own answer on the row (`canDecide`/`canCancel`), and the buttons
/// follow it exactly.
///
/// Asking, approving, rejecting and cancelling are dialogs reached by
/// address (ADR-0021): `/leave-requests/new` and
/// `/leave-requests/:id/approve|reject|cancel`, over the list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'leave_request.dart';
import 'leave_requests_bloc.dart';

class LeaveRequestsScreen extends StatelessWidget {
  const LeaveRequestsScreen({super.key, required this.canDecide});

  /// Whether to offer the "To decide" view — an administrator or a holder of
  /// an edit Grant somewhere.
  final bool canDecide;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> requestKey = ValueKey<String>('leave-requests-request');
  static const ValueKey<String> emptyRequestKey = ValueKey<String>('leave-requests-empty-request');
  static const ValueKey<String> viewMineKey = ValueKey<String>('leave-requests-view-mine');
  static const ValueKey<String> viewToDecideKey = ValueKey<String>('leave-requests-view-to-decide');
  static const ValueKey<String> failedKey = ValueKey<String>('leave-requests-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('leave-requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('leave-requests-empty');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('leave-requests-row-$id');
  static ValueKey<String> approveKey(String id) => ValueKey<String>('leave-requests-approve-$id');
  static ValueKey<String> rejectKey(String id) => ValueKey<String>('leave-requests-reject-$id');
  static ValueKey<String> cancelKey(String id) => ValueKey<String>('leave-requests-cancel-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LeaveRequestsBloc>().state;
    return Scaffold(
      body: switch (state) {
        LeaveRequestsLoading() => const SkeletonList(maxWidth: LeaveRequestsScreen.maxWidth),
        LeaveRequestsUnavailable(message: final message) => PlatformFailureState(
            key: LeaveRequestsScreen.failedKey,
            title: 'Leave requests could not be read',
            message: message,
            retryKey: LeaveRequestsScreen.retryKey,
            onRetry: () => context.read<LeaveRequestsBloc>().add(const LeaveRequestsStarted()),
          ),
        LeaveRequestsLoaded() => _Loaded(state: state, canDecide: canDecide),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.canDecide});

  final LeaveRequestsLoaded state;
  final bool canDecide;

  void _request(BuildContext context) => context.go('${Routes.leaveRequests}/new');

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LeaveRequestsBloc>();
    final isMine = state.view == LeaveRequestView.mine;
    return Center(
      child: AppPageFrame(
        maxWidth: LeaveRequestsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: 'Leave requests',
              description: 'Ask to be away from work, and follow what became of it.',
              actions: [
                FilledButton.icon(
                  key: LeaveRequestsScreen.requestKey,
                  onPressed: state.isMutating ? null : () => _request(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Request leave'),
                ),
              ],
              below: canDecide
                  ? Wrap(
                      spacing: Spacing.sm,
                      children: [
                        ChoiceChip(
                          key: LeaveRequestsScreen.viewMineKey,
                          label: const Text('Mine'),
                          selected: isMine,
                          onSelected: (_) =>
                              bloc.add(const LeaveRequestsViewSelected(LeaveRequestView.mine)),
                        ),
                        ChoiceChip(
                          key: LeaveRequestsScreen.viewToDecideKey,
                          label: const Text('To decide'),
                          selected: !isMine,
                          onSelected: (_) => bloc
                              .add(const LeaveRequestsViewSelected(LeaveRequestView.toDecide)),
                        ),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: Spacing.lg),
            if (state.requests.isEmpty)
              PlatformEmptyState.noneExist(
                key: LeaveRequestsScreen.emptyKey,
                title: isMine ? 'No leave requests yet' : 'Nothing to decide',
                message: isMine
                    ? 'Request leave to ask for time away.'
                    : 'No pending leave requests are waiting for you.',
                icon: Icons.beach_access_outlined,
                actionLabel: isMine ? 'Request leave' : null,
                actionKey: LeaveRequestsScreen.emptyRequestKey,
                onAction: isMine ? () => _request(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final request in state.requests)
                    _LeaveRequestRow(request: request, isMutating: state.isMutating),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LeaveRequestRow extends StatelessWidget {
  const _LeaveRequestRow({required this.request, required this.isMutating});

  final LeaveRequest request;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final decisionNote = request.decisionNote;
    final note = request.note;
    final address = '${Routes.leaveRequests}/${request.id}';
    return Padding(
      key: LeaveRequestsScreen.rowKey(request.id),
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
                        '${request.employee.displayName} · ${request.leaveTypeName}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    StatusChip(
                      label: request.statusLabel,
                      tone: leaveRequestStatusTone(request.status),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text('${request.periodLabel} · ${request.daysLabel}', style: muted),
                if (note != null && note.isNotEmpty) Text('Note: $note', style: muted),
                if (decisionNote != null && decisionNote.isNotEmpty)
                  Text('Decision note: $decisionNote', style: muted),
              ],
            ),
          ),
          if (request.canDecide) ...[
            OutlinedButton(
              key: LeaveRequestsScreen.approveKey(request.id),
              onPressed: isMutating ? null : () => context.go('$address/approve'),
              child: const Text('Approve'),
            ),
            const SizedBox(width: Spacing.sm),
            OutlinedButton(
              key: LeaveRequestsScreen.rejectKey(request.id),
              onPressed: isMutating ? null : () => context.go('$address/reject'),
              child: const Text('Reject'),
            ),
          ],
          if (request.canCancel) ...[
            const SizedBox(width: Spacing.sm),
            OutlinedButton(
              key: LeaveRequestsScreen.cancelKey(request.id),
              onPressed: isMutating ? null : () => context.go('$address/cancel'),
              child: const Text('Cancel request'),
            ),
          ],
        ],
      ),
    );
  }
}
