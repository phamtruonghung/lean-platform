/// Accounts: everyone an administrator has already dealt with, what each one
/// holds, and the two corrections still available — changing a role and Grant
/// set, and deactivating or reactivating (issue #36).
///
/// The Approval queue next door lists only Accounts nobody has decided about;
/// this Screen lists everyone else, which is what makes an admitted Account
/// reachable again at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/destinations.dart';
import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'account_correction_dialog.dart';
import 'accounts_bloc.dart';
import 'managed_account.dart';
import 'role_choice.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.selfAccountId});

  /// The caller's own Account id — threaded down to [_AccountsList] so no
  /// row ever offers an action on the caller's own Account (issue #53).
  final String selfAccountId;

  static const double maxWidth = 900;
  static const ValueKey<String> noticeKey = ValueKey<String>('accounts-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('accounts-retry');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AccountsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          if (state is AccountsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              AccountsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              AccountsUnavailable(message: final message) => _AccountsFailed(message: message),
              AccountsLoaded() when state.admitted.isEmpty => const _AccountsEmpty(),
              AccountsLoaded() => _AccountsList(
                  accounts: state.admitted,
                  busyId: state.busyId,
                  correctingId: state.correctingId,
                  selfAccountId: selfAccountId,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AccountsScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accounts', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'Everyone already dealt with, what they hold, and whether they can sign in.',
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

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AccountsScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: AccountsScreen.noticeKey,
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

class _AccountsList extends StatelessWidget {
  const _AccountsList({
    required this.accounts,
    required this.busyId,
    required this.correctingId,
    required this.selfAccountId,
  });

  final List<ManagedAccount> accounts;
  final String? busyId;
  final String? correctingId;
  final String selfAccountId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AccountsScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => AccountRow(
            account: accounts[index],
            busy: accounts[index].id == busyId || accounts[index].id == correctingId,
            isSelf: accounts[index].id == selfAccountId,
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class AccountRow extends StatelessWidget {
  const AccountRow({super.key, required this.account, required this.busy, required this.isSelf});

  final ManagedAccount account;
  final bool busy;

  /// Whether this row is the caller's own Account (issue #53) — when true,
  /// neither action button is offered, mirroring the same "don't offer a
  /// button the server will refuse" reasoning the `isApproved` check below
  /// already uses in this file.
  final bool isSelf;

  static ValueKey<String> correctKey(String id) => ValueKey<String>('accounts-correct-$id');
  static ValueKey<String> activeKey(String id) => ValueKey<String>('accounts-active-$id');
  static ValueKey<String> grantsKey(String id) => ValueKey<String>('accounts-grants-$id');
  static ValueKey<String> selfKey(String id) => ValueKey<String>('accounts-self-$id');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        '${roleLabel(account.role)} · ${account.standing}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Neither action is offered on the caller's own row: the
                // server refuses all three self-actions unconditionally
                // (issue #53), so no button here would ever succeed.
                if (isSelf)
                  Flexible(
                    child: Text(
                      'Your own Account. Another administrator has to change it.',
                      key: selfKey(account.id),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else ...[
                  // Only an approved Account can be deactivated or
                  // reactivated: the server refuses either for a rejected
                  // one, whose way back in is a correction
                  // (`setAccountActive`, service.js).
                  if (account.isApproved) ...[
                    OutlinedButton(
                      key: activeKey(account.id),
                      onPressed: busy ? null : () => _toggleActive(context, account),
                      child: Text(account.isActive ? 'Deactivate' : 'Reactivate'),
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                  FilledButton(
                    key: correctKey(account.id),
                    onPressed:
                        busy ? null : () => AccountCorrectionDialog.open(context, account),
                    child: const Text('Change'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _Grants(account: account),
          ],
        ),
      ),
    );
  }
}

class _Grants extends StatelessWidget {
  const _Grants({required this.account});

  final ManagedAccount account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (account.role == Roles.admin) {
      return Text(
        'Acts everywhere, in every Site. No Org Unit Grants, and none needed.',
        key: AccountRow.grantsKey(account.id),
        style: muted,
      );
    }
    if (account.grants.isEmpty) {
      return Text(
        'No Org Unit Grants. Can sign in, but cannot act in any Org Unit.',
        key: AccountRow.grantsKey(account.id),
        style: muted,
      );
    }
    return Wrap(
      key: AccountRow.grantsKey(account.id),
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        for (final grant in account.grants)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('${grant.siteName} › ${grant.name} · ${grant.level.label}'),
            labelStyle: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}

/// Asks first before cutting someone off, and sends nothing unless the answer
/// is yes — the same shape the Approval queue's rejection uses. Reactivating
/// is not asked about: it takes nothing away.
Future<void> _toggleActive(BuildContext context, ManagedAccount account) async {
  final bloc = context.read<AccountsBloc>();
  if (!account.isActive) {
    bloc.add(AccountsActiveToggled(accountId: account.id, isActive: true));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Deactivate this Account?'),
      content: Text(
        '${account.email} will not be able to sign in. Nothing is deleted — '
        'the role and the Org Unit Grants stay exactly as they are, and an '
        'administrator can reactivate the Account at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Deactivate'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    bloc.add(AccountsActiveToggled(accountId: account.id, isActive: false));
  }
}

class _AccountsEmpty extends StatelessWidget {
  const _AccountsEmpty();

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
              Icon(Icons.badge_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('Nobody has been let in yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Accounts appear here once they have been admitted or turned '
                'away in the Approval queue.',
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

class _AccountsFailed extends StatelessWidget {
  const _AccountsFailed({required this.message});

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
              Text('The Accounts could not be loaded', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: Spacing.lg),
              FilledButton.icon(
                key: AccountsScreen.retryKey,
                onPressed: () =>
                    context.read<AccountsBloc>().add(const AccountsRequested()),
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
