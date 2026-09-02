/// The Approval queue: who is waiting to be let in, and turning one away.
///
/// Approving — choosing a role and granting Org Units — is issue #41 and is
/// deliberately not here. A row carries an email address and a wait, and
/// nothing else: an Account need not correspond to an Employee, so there is
/// no name to show and inventing one would be a lie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'approval_queue_bloc.dart';
import 'pending_account.dart';

class ApprovalQueueScreen extends StatelessWidget {
  const ApprovalQueueScreen({super.key});

  static const double maxWidth = 900;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ApprovalQueueBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          if (state is ApprovalQueueLoaded && state.notice != null)
            _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              ApprovalQueueLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              ApprovalQueueUnavailable(message: final message) => _QueueFailed(message: message),
              ApprovalQueueLoaded(accounts: final accounts) when accounts.isEmpty =>
                const _QueueEmpty(),
              ApprovalQueueLoaded(accounts: final accounts, rejectingId: final rejectingId) =>
                _QueueList(accounts: accounts, rejectingId: rejectingId),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ApprovalQueueScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approval queue', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'Everyone waiting to be let in to the Platform.',
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

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  static const ValueKey<String> noticeKey = ValueKey<String>('approval-queue-notice');

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ApprovalQueueScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: noticeKey,
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

class _QueueList extends StatelessWidget {
  const _QueueList({required this.accounts, required this.rejectingId});

  final List<PendingAccount> accounts;
  final String? rejectingId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ApprovalQueueScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _QueueRow(
            account: accounts[index],
            rejecting: accounts[index].id == rejectingId,
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.account, required this.rejecting});

  final PendingAccount account;
  final bool rejecting;

  static ValueKey<String> rejectKey(String accountId) =>
      ValueKey<String>('approval-queue-reject-$accountId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.person_outline, size: 20),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.email,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    waitingFor(account.waitingSince),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            OutlinedButton(
              key: rejectKey(account.id),
              onPressed: rejecting ? null : () => _confirmRejection(context, account),
              child: Text(rejecting ? 'Rejecting…' : 'Reject'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks first, and sends nothing at all unless the answer is yes. The Bloc
/// never sees an unconfirmed rejection — the event is only added below.
Future<void> _confirmRejection(BuildContext context, PendingAccount account) async {
  final bloc = context.read<ApprovalQueueBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reject this Account?'),
      content: Text(
        '${account.email} will not be let in to the Platform, and will be '
        'told their request was turned down. An administrator can still admit '
        'them later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Reject'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    bloc.add(ApprovalQueueRejectionConfirmed(account.id));
  }
}

class _QueueEmpty extends StatelessWidget {
  const _QueueEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('Nobody is waiting', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Every Account has been dealt with. New requests appear here.',
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

class _QueueFailed extends StatelessWidget {
  const _QueueFailed({required this.message});

  static const ValueKey<String> retryKey = ValueKey<String>('approval-queue-retry');

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: Spacing.md),
              Text('The queue could not be loaded', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: Spacing.lg),
              FilledButton.icon(
                key: retryKey,
                onPressed: () => context
                    .read<ApprovalQueueBloc>()
                    .add(const ApprovalQueueRequested()),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
