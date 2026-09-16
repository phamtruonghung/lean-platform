/// The Approval queue: who is waiting to be let in, admitting one, and turning
/// one away.
///
/// The role an admission carries is chosen in `admission_dialog.dart`; the Org
/// Unit Grant picker that dialog will grow is issue #42. A row carries an
/// email address and a wait, and nothing else: an Account need not correspond
/// to an Employee, so there is no name to show and inventing one would be a
/// lie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/skeleton_list.dart';
import 'admission_dialog.dart';
import 'approval_queue_bloc.dart';
import 'pending_account.dart';

class ApprovalQueueScreen extends StatelessWidget {
  const ApprovalQueueScreen({super.key});

  static const double maxWidth = 900;

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'approvals-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the waiting Accounts renders — a different
  /// fact from the queue's own empty state: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('approvals-no-match');

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
              ApprovalQueueLoaded(
                accounts: final accounts,
                rejectingId: final rejectingId,
                admittingId: final admittingId,
              ) =>
                _QueueList(
                  accounts: accounts,
                  rejectingId: rejectingId,
                  admittingId: admittingId,
                ),
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
      child: AppPageFrame(
        maxWidth: ApprovalQueueScreen.maxWidth,
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
      child: AppPageFrame(
        maxWidth: ApprovalQueueScreen.maxWidth,
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

/// The queue itself. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _QueueList extends StatefulWidget {
  const _QueueList({
    required this.accounts,
    required this.rejectingId,
    required this.admittingId,
  });

  final List<PendingAccount> accounts;
  final String? rejectingId;
  final String? admittingId;

  @override
  State<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<_QueueList> {
  /// What the filter box is narrowing the queue to, `''` when nothing is.
  String _term = '';

  /// Whether [account] matches [term], already lower-cased and trimmed. An
  /// email address is the only thing a waiting Account carries — an Account
  /// need not correspond to an Employee, so there is no name to match on
  /// (`pending_account.dart`'s own note). No ranking and no fuzzy matching,
  /// the same rule the assign dialog's own filter uses (issue #187).
  static bool _matches(PendingAccount account, String term) =>
      account.email.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<PendingAccount> get _matchingAccounts {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.accounts;
    return widget.accounts.where((account) => _matches(account, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingAccounts;
    return Center(
      child: AppPageFrame(
        maxWidth: ApprovalQueueScreen.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppFilterField(
                name: ApprovalQueueScreen.filterFieldName,
                label: 'Filter Accounts',
                helperText: 'By email address.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.accounts.length,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: matches.isEmpty
                  ? PlatformEmptyState.noneMatched(
                      key: ApprovalQueueScreen.noMatchKey,
                      title: 'No Accounts match',
                      message: 'Accounts are waiting, but none matches "${_term.trim()}". '
                          'Try a different email address, or clear the filter.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) => _QueueRow(
                        account: matches[index],
                        rejecting: matches[index].id == widget.rejectingId,
                        admitting: matches[index].id == widget.admittingId,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.account, required this.rejecting, required this.admitting});

  final PendingAccount account;
  final bool rejecting;
  final bool admitting;

  static ValueKey<String> rejectKey(String accountId) =>
      ValueKey<String>('approval-queue-reject-$accountId');

  static ValueKey<String> admitKey(String accountId) =>
      ValueKey<String>('approval-queue-admit-$accountId');

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
              onPressed: rejecting || admitting ? null : () => _confirmRejection(context, account),
              child: Text(rejecting ? 'Rejecting…' : 'Reject'),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              key: admitKey(account.id),
              onPressed:
                  rejecting || admitting ? null : () => AdmissionDialog.open(context, account),
              child: Text(admitting ? 'Admitting…' : 'Admit'),
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
