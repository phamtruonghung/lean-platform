/// The Accounts Screen: every Account on the plant, what each one holds, and
/// the two corrections still available on an approved one — changing its
/// role and Grant set, and deactivating or reactivating it (issue #36).
///
/// Every Account the server returns is listed here, pending ones included
/// (issue #112, Decision B) — the same read `GET /accounts` has always sent.
/// A pending row still belongs to the Approval queue for the decision itself
/// (admit or reject); this Screen only ever sends such a row on to the queue
/// (`Review in Approvals`, Decision E), never decides it here. Listing every
/// Account is what makes this the answer to "who can sign in and what may
/// they reach" — see the `CONTEXT.md` entry this issue adds, which is what
/// this Screen is named for and how it differs from the Directory.
///
/// The table shape is #104's, copied rather than re-decided: see
/// `work_orders_screen.dart:500`'s own header for the reasoning, and
/// `_AccountsList`'s header below for how it applies here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/destinations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'account_correction_dialog.dart';
import 'account_employee_dialog.dart';
import 'accounts_bloc.dart';
import 'managed_account.dart';
import 'pending_account.dart' show waitingFor;
import 'role_choice.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.selfAccountId});

  /// The caller's own Account id — threaded down to [_AccountsList] so no
  /// row ever offers an action on the caller's own Account (issue #53).
  final String selfAccountId;

  static const double maxWidth = 960;

  /// The breakpoint below which the list renders as one card per Account
  /// rather than a table (issue #112, Decision A) — the same 700px
  /// `WorkOrdersScreen` and `platform/shell.dart` already agree "narrow"
  /// starts at.
  static const double narrowBreakpoint = 700;

  static const ValueKey<String> noticeKey = ValueKey<String>('accounts-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('accounts-retry');

  /// Shared between the wide table row and the narrow card (issue #112,
  /// Decision A), so a test written against one Account's row does not need
  /// to know which layout rendered it — exactly
  /// [WorkOrdersScreen.rowKey]'s own contract.
  static ValueKey<String> rowKey(String id) => ValueKey<String>('account-row-$id');

  static ValueKey<String> correctKey(String id) => ValueKey<String>('accounts-correct-$id');
  static ValueKey<String> activeKey(String id) => ValueKey<String>('accounts-active-$id');
  static ValueKey<String> grantsKey(String id) => ValueKey<String>('accounts-grants-$id');
  static ValueKey<String> selfKey(String id) => ValueKey<String>('accounts-self-$id');

  /// The Employee cell (issue #116): what this Account is linked to, or that
  /// it is linked to none — shown on every row, self included, since naming a
  /// link is not an action.
  static ValueKey<String> employeeKey(String id) => ValueKey<String>('accounts-employee-$id');

  /// The control that opens [AccountEmployeeDialog] — absent on the caller's
  /// own row and on a pending row, the same two branches
  /// [correctKey]/[activeKey] are already absent from.
  static ValueKey<String> linkEmployeeKey(String id) => ValueKey<String>('accounts-link-employee-$id');

  /// The pending row's own action (issue #112, Decision E): neither
  /// correction nor deactivation, since the server refuses both for a
  /// pending Account — a link to the one place Approval is actually decided.
  static ValueKey<String> reviewInApprovalsKey(String id) =>
      ValueKey<String>('accounts-review-$id');

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
              AccountsLoaded() when state.accounts.isEmpty => const _AccountsEmpty(),
              AccountsLoaded() => _AccountsList(
                  accounts: state.accounts,
                  busyId: state.busyId,
                  correctingId: state.correctingId,
                  employeeLinkingId: state.employeeLinkingId,
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
              // Every Account, not only the ones already dealt with (issue
              // #112, Decision B) — the wording that used to live here
              // ("Everyone already dealt with…") is exactly the confusion
              // that issue reports.
              Text(
                'Every Account on this plant: what it holds, and whether it can sign in.',
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

/// The Account list, laid out one of two ways depending on the window (issue
/// #112, Decision A) — never a third, horizontally-scrolling shape, copying
/// `work_orders_screen.dart`'s own `_WorkOrdersList` (issue #104) rather than
/// re-deciding the shape:
///
/// - At or above [AccountsScreen.narrowBreakpoint] (700px): a table — a
///   header row of column labels (Name, Email, Role, Standing, Since,
///   Grants, Actions — issue #112, Decision C), then one `Row` of cells per
///   Account, built from `Expanded`/`Flexible` cells with
///   `TextOverflow.ellipsis`, sized so it never needs to scroll sideways.
///   Deliberately not Flutter's `DataTable`: its default is a
///   horizontally-scrolling `SingleChildScrollView`, which is exactly the
///   shape this ticket bans at every width, not only below the breakpoint.
/// - Below it: one card per Account, unchanged from what this Screen
///   rendered before this issue, Grants rendering included (Decision D).
///
/// Both shapes key their outer widget with [AccountsScreen.rowKey], so a test
/// written against one Account's row does not need to know which layout is
/// rendering it. Accounts already arrive from [AccountsBloc] ordered pending
/// first, then by email (Decision B); this list renders them in that order
/// rather than re-sorting.
class _AccountsList extends StatelessWidget {
  const _AccountsList({
    required this.accounts,
    required this.busyId,
    required this.correctingId,
    required this.employeeLinkingId,
    required this.selfAccountId,
  });

  final List<ManagedAccount> accounts;
  final String? busyId;
  final String? correctingId;
  final String? employeeLinkingId;
  final String selfAccountId;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < AccountsScreen.narrowBreakpoint;
    bool isBusy(String id) => id == busyId || id == correctingId || id == employeeLinkingId;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AccountsScreen.maxWidth),
        child: narrow
            ? ListView.separated(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                itemCount: accounts.length,
                separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) => _AccountCard(
                  account: accounts[index],
                  busy: isBusy(accounts[index].id),
                  isSelf: accounts[index].id == selfAccountId,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                children: [
                  const _AccountTableHeader(),
                  for (final account in accounts)
                    _AccountTableRow(
                      account: account,
                      busy: isBusy(account.id),
                      isSelf: account.id == selfAccountId,
                    ),
                ],
              ),
      ),
    );
  }
}

/// The wide table's own fixed width for its trailing actions column — wide
/// enough for "Deactivate"/"Reactivate" plus "Change" plus the Employee-link
/// icon button (issue #116) side by side, or the self-row explanation, or the
/// pending row's "Review in Approvals" link. Shared between
/// [_AccountTableHeader]'s spacer and every [_AccountTableRow]'s own actions
/// cell, matching `work_orders_screen.dart`'s own `_actionsColumnWidth` in
/// spirit — wider than that Screen's own 232px since three controls together
/// run longer than that Screen's own primary-plus-overflow pair.
///
/// The Employee link's own control deliberately lives here rather than in the
/// Employee cell itself (a flex-sized column): that cell is narrow enough at
/// ordinary widths that a button folded into it overflowed, where this fixed
/// column has room to spare.
const double _actionsColumnWidth = 388;

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget label(String text, int flex) => Expanded(flex: flex, child: Text(text, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        children: [
          label('Name', 2),
          label('Email', 3),
          label('Role', 2),
          label('Standing', 2),
          label('Since', 2),
          label('Grants', 2),
          label('Employee', 2),
          SizedBox(width: _actionsColumnWidth, child: Text('Actions', style: style)),
        ],
      ),
    );
  }
}

class _AccountTableRow extends StatelessWidget {
  const _AccountTableRow({required this.account, required this.busy, required this.isSelf});

  final ManagedAccount account;
  final bool busy;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget cell(String text, int flex, {TextStyle? style}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: Text(text, overflow: TextOverflow.ellipsis, style: style),
          ),
        );

    return Container(
      key: AccountsScreen.rowKey(account.id),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          cell(account.displayName, 2, style: theme.textTheme.bodyMedium),
          cell(account.email, 3, style: muted),
          cell(roleLabel(account.role), 2, style: muted),
          cell(account.standing, 2, style: muted),
          cell(waitingFor(account.createdAt), 2, style: muted),
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerLeft, child: _GrantsCell(account: account)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _EmployeeCell(account: account),
            ),
          ),
          SizedBox(
            width: _actionsColumnWidth,
            child: _RowActions(account: account, busy: busy, isSelf: isSelf),
          ),
        ],
      ),
    );
  }
}

/// The narrow (<700px) card — unchanged from what this Screen rendered
/// before issue #112, apart from carrying the same [AccountsScreen.rowKey]
/// the wide table row now carries too.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.busy, required this.isSelf});

  final ManagedAccount account;
  final bool busy;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: AccountsScreen.rowKey(account.id),
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
                // Only the self-row branch is wrapped in `Flexible` — unlike
                // the wide table row, which hands `_RowActions` a tight width
                // via `SizedBox`, this `Row` has no width constraint of its
                // own, and the self-row explanation is the one branch long
                // enough to overflow it. Wrapping every branch instead would
                // be wrong, not merely unnecessary: `Flexible` next to this
                // `Row`'s own `Expanded` would split the remaining space
                // between the two rather than letting the account-info
                // column keep whatever the actions do not need, which is
                // exactly what made the two-button case overflow when this
                // was tried.
                if (isSelf)
                  Flexible(child: _RowActions(account: account, busy: busy, isSelf: isSelf))
                else
                  _RowActions(account: account, busy: busy, isSelf: isSelf),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _Grants(account: account),
            const SizedBox(height: Spacing.sm),
            _EmployeeCell(account: account),
          ],
        ),
      ),
    );
  }
}

/// The Employee cell (issue #116, ADR-0022), shared between the wide table
/// row and the narrow card exactly as [_GrantsCell]/[_Grants] are — names
/// what this Account is linked to, or that it is linked to none, neither
/// rendered as a problem. Plain text, on every row including the caller's
/// own: showing a link is not an action, so it carries none of
/// [_RowActions]'s self-row/pending-row exclusions. The control that opens
/// [AccountEmployeeDialog] lives in [_RowActions] instead — folding it into
/// this flex-sized cell overflowed the wide table's narrow Employee column at
/// ordinary widths, the fixed-width actions column does not have that
/// problem.
class _EmployeeCell extends StatelessWidget {
  const _EmployeeCell({required this.account});

  final ManagedAccount account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = account.linkedEmployee == null ? 'No Employee linked' : account.linkedEmployee!.label;
    return Text(
      label,
      key: AccountsScreen.employeeKey(account.id),
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// One row's own actions (issue #112, Decision E), shared between the wide
/// table row and the narrow card so both layouts offer exactly the same
/// actions through exactly the same keys — the same reasoning
/// `work_orders_screen.dart`'s own `_RowActions` documents.
///
/// - The caller's own row (issue #53): neither action, an explanation
///   instead. Checked first, since the server refuses every action on it
///   unconditionally regardless of standing.
/// - A pending Account: neither correction nor deactivation — the server
///   refuses both — but a "Review in Approvals" link to the one place
///   Approval is actually decided, never a disabled button and never an
///   inline approve/reject here.
/// - Otherwise: "Deactivate"/"Reactivate", offered only for an approved
///   Account (the server refuses it for a rejected one, whose way back in is
///   a correction), plus "Change", offered for both an approved and a
///   rejected Account.
///
/// Sizing is the caller's job, not this widget's: the self-row branch is a
/// `Text` with no width of its own, long enough to overflow a `Row` that
/// hands it unbounded space. [_AccountTableRow] constrains every branch
/// alike (a fixed-width `SizedBox`); [_AccountCard] has no such width to
/// give, so it wraps only the self-row branch in a `Flexible` — see that
/// call site's own comment for why wrapping every branch there is wrong, not
/// merely unneeded.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.account, required this.busy, required this.isSelf});

  final ManagedAccount account;
  final bool busy;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Neither action is offered on the caller's own row: the server refuses
    // all three self-actions unconditionally (issue #53), so no button here
    // would ever succeed.
    if (isSelf) {
      return Text(
        'Your own Account. Another administrator has to change it.',
        key: AccountsScreen.selfKey(account.id),
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    if (account.isPending) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: AccountsScreen.reviewInApprovalsKey(account.id),
          onPressed: () => context.go(Routes.approvals),
          child: const Text('Review in Approvals'),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only an approved Account can be deactivated or reactivated: the
        // server refuses either for a rejected one, whose way back in is a
        // correction (`setAccountActive`, service.js).
        if (account.isApproved) ...[
          OutlinedButton(
            key: AccountsScreen.activeKey(account.id),
            onPressed: busy ? null : () => _toggleActive(context, account),
            child: Text(account.isActive ? 'Deactivate' : 'Reactivate'),
          ),
          const SizedBox(width: Spacing.sm),
        ],
        FilledButton(
          key: AccountsScreen.correctKey(account.id),
          onPressed: busy ? null : () => AccountCorrectionDialog.open(context, account),
          child: const Text('Change'),
        ),
        const SizedBox(width: Spacing.xs),
        // The Employee link's own control (issue #116, ADR-0022) — an icon
        // button, not a labelled one, so it fits this fixed-width column
        // alongside the two above; [_actionsColumnWidth] was widened to make
        // room for it. Absent on the caller's own row and on a pending row
        // for free, by sitting after the two early returns above rather than
        // needing an exclusion of its own.
        IconButton(
          key: AccountsScreen.linkEmployeeKey(account.id),
          icon: const Icon(Icons.badge_outlined, size: 20),
          tooltip: account.linkedEmployee == null ? 'Link an Employee' : 'Change Employee link',
          visualDensity: VisualDensity.compact,
          onPressed: busy ? null : () => AccountEmployeeDialog.open(context, account),
        ),
      ],
    );
  }
}

/// The Grants cell in the wide table (issue #112, Decision D): a count, not
/// a wall of chips — "Everywhere" for an admin, "None" for an Account with
/// no Grants (the case an administrator most needs to spot: approved, can
/// sign in, cannot act anywhere), and a count otherwise, with the full chip
/// list available on hover as a tooltip.
class _GrantsCell extends StatelessWidget {
  const _GrantsCell({required this.account});

  final ManagedAccount account;

  @override
  Widget build(BuildContext context) {
    if (account.role == Roles.admin) {
      return Text('Everywhere', key: AccountsScreen.grantsKey(account.id));
    }
    if (account.grants.isEmpty) {
      return Text('None', key: AccountsScreen.grantsKey(account.id));
    }
    final count = account.grants.length;
    return Tooltip(
      key: AccountsScreen.grantsKey(account.id),
      message: [
        for (final grant in account.grants) '${grant.siteName} › ${grant.name} · ${grant.level.label}',
      ].join('\n'),
      child: Text('$count Org Unit${count == 1 ? '' : 's'}', overflow: TextOverflow.ellipsis),
    );
  }
}

/// The narrow card's own Grants rendering — unchanged since before issue
/// #112 (Decision D): prose for the admin and empty cases, chips otherwise.
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
        key: AccountsScreen.grantsKey(account.id),
        style: muted,
      );
    }
    if (account.grants.isEmpty) {
      return Text(
        'No Org Unit Grants. Can sign in, but cannot act in any Org Unit.',
        key: AccountsScreen.grantsKey(account.id),
        style: muted,
      );
    }
    return Wrap(
      key: AccountsScreen.grantsKey(account.id),
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
              // Literally true now that every Account is listed here (issue
              // #112): nothing at all, not merely nothing admitted yet.
              Text('No Accounts yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Accounts appear here as soon as somebody signs in for the first time.',
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
