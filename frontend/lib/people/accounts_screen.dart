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
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'account_correction_dialog.dart';
import 'account_employee_dialog.dart';
import 'account_password_dialog.dart';
import 'account_roles_dialog.dart';
import 'accounts_bloc.dart';
import 'managed_account.dart';
import 'pending_account.dart' show waitingFor;
import 'role_choice.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.selfAccountId});

  /// The caller's own Account id — threaded down to [_AccountsList] so no
  /// row ever offers an action on the caller's own Account (issue #53).
  final String selfAccountId;

  /// A register's width (#392, `design-language.md` §6): eight columns and the
  /// fixed actions slot under them are read across, and 960 was what the
  /// hand-rolled table used.
  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the register is a
  /// table; below it, one card per Account.
  ///
  /// Measured against this Screen's own *content* width (`_AccountsList`'s own
  /// `LayoutBuilder`, issue #120), never the browser window: this Screen only
  /// ever sees what the Shell hands it after its own sidebar is subtracted, so a
  /// window figure says nothing about the box this table is drawn in.
  ///
  /// **900, and read through [AppBreakpoints.effective]** — both halves changed
  /// in #392. The old number was 850, chosen when the actions column was a fixed
  /// 420-width box; it is now measured from the widest label it actually draws
  /// (~300), so more of the box goes to the seven flexible columns, and at a 1280
  /// window this page is handed 988 — every header label (`Standing`,
  /// `Employee`, `Grants`) is single-line there. At 900 the leftover for the
  /// names would be 283px across seven columns, which is clipped to nothing; that
  /// is why the number moved up rather than down. And the comparison now
  /// multiplies the breakpoint by the reader's text size: the same 988px box at
  /// twice the text needs 1800, so the cards come back instead of squeezing eight
  /// columns past legibility (§10; the bug class of #379 and #381, which this
  /// line was one of).
  static const double narrowBreakpoint = 900;

  static const ValueKey<String> noticeKey = ValueKey<String>('accounts-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('accounts-retry');
  static const ValueKey<String> failedKey = ValueKey<String>('accounts-failed');
  static const ValueKey<String> emptyKey = ValueKey<String>('accounts-empty');

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

  /// The control that opens [AccountPasswordDialog] (issue #270) — absent on
  /// the caller's own row (ADR-0013) and on a pending row, like
  /// [linkEmployeeKey].
  static ValueKey<String> resetPasswordKey(String id) =>
      ValueKey<String>('accounts-reset-password-$id');

  /// The control that opens [AccountRolesDialog] (issue #492, ADR-0061) — the
  /// "put this person in that group and press Assign" act. Absent on the
  /// caller's own row and on a pending row, for the same two reasons the three
  /// controls above it are.
  static ValueKey<String> rolesKey(String id) => ValueKey<String>('accounts-roles-$id');

  /// The pending row's own action (issue #112, Decision E): neither
  /// correction nor deactivation, since the server refuses both for a
  /// pending Account — a link to the one place Approval is actually decided.
  static ValueKey<String> reviewInApprovalsKey(String id) =>
      ValueKey<String>('accounts-review-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'accounts-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the plant's Accounts renders — a different
  /// fact from the Screen's own empty state: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('accounts-no-match');

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
              AccountsUnavailable(message: final message) => PlatformFailureState(
                  key: AccountsScreen.failedKey,
                  title: 'The Accounts could not be loaded',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<AccountsBloc>().add(const AccountsRequested()),
                ),
              // Nothing has ever been recorded here — the *none exist* variant,
              // distinct from the filter's own *none matched* below (§7 of
              // `docs/design-language.md`).
              AccountsLoaded() when state.accounts.isEmpty => const PlatformEmptyState.noneExist(
                  key: AccountsScreen.emptyKey,
                  title: 'No Accounts yet',
                  // Literally true now that every Account is listed here (issue
                  // #112): nothing at all, not merely nothing admitted yet.
                  message: 'Accounts appear here as soon as somebody signs in for the first time.',
                  icon: Icons.badge_outlined,
                ),
              AccountsLoaded() => _AccountsList(
                  accounts: state.accounts,
                  busyId: state.busyId,
                  correctingId: state.correctingId,
                  employeeLinkingId: state.employeeLinkingId,
                  passwordResettingId: state.passwordResettingId,
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
    return Center(
      child: AppPageFrame(
        maxWidth: AccountsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          // Every Account, not only the ones already dealt with (issue
          // #112, Decision B) — the wording that used to live here
          // ("Everyone already dealt with…") is exactly the confusion
          // that issue reports.
          child: const AppPageHeader(
            title: 'Accounts',
            description: 'Every Account on this plant: what it holds, and whether it can sign in.',
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
        maxWidth: AccountsScreen.maxWidth,
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

/// The Account list, laid out one of two ways depending on this Screen's own
/// *content* width, read off a `LayoutBuilder` rather than
/// `MediaQuery.sizeOf(context).width` (issue #112, Decision A; measured
/// correctly since issue #120 — see [AccountsScreen.narrowBreakpoint]'s own
/// doc comment for why the window was never the right thing to ask) — never
/// a third, horizontally-scrolling shape, copying `work_orders_screen.dart`'s
/// own `_WorkOrdersList` (issue #104) rather than re-deciding the shape:
///
/// - At or above [AccountsScreen.narrowBreakpoint] (850px of content): a table — a
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
///
/// **Stateful since issue #191, for the filter box's own term.** The box sits
/// above either shape, at the page's own padding, and the rows are narrowed
/// immediately before they are built — so a term can only ever hide rows this
/// Screen already read. The term is this widget's own `setState` and never a
/// Bloc event: a filter is a view of the rows the Bloc holds, not a state of
/// the domain (ADR-0012 asks for a Bloc where a Screen drives a state machine,
/// not for one per text field).
class _AccountsList extends StatefulWidget {
  const _AccountsList({
    required this.accounts,
    required this.busyId,
    required this.correctingId,
    required this.employeeLinkingId,
    required this.passwordResettingId,
    required this.selfAccountId,
  });

  final List<ManagedAccount> accounts;
  final String? busyId;
  final String? correctingId;
  final String? employeeLinkingId;
  final String? passwordResettingId;
  final String selfAccountId;

  @override
  State<_AccountsList> createState() => _AccountsListState();
}

class _AccountsListState extends State<_AccountsList> {
  /// What the filter box is narrowing the register to, `''` when nothing is.
  String _term = '';

  /// Whether [account] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the three fields that identify an
  /// Account — the name it signed up with, the email it signs in as, and the
  /// role it holds (both the wire's own name for it and the label the table
  /// shows, so "supervisor" and "Supervisor" both find it). No ranking and
  /// no fuzzy matching, the same rule the assign dialog's own filter uses
  /// (issue #187).
  static bool _matches(ManagedAccount account, String term) =>
      account.displayName.toLowerCase().contains(term) ||
      account.email.toLowerCase().contains(term) ||
      account.role.toLowerCase().contains(term) ||
      roleLabel(account.role).toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<ManagedAccount> get _matchingAccounts {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.accounts;
    return widget.accounts.where((account) => _matches(account, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the rows are built, so a term can
    // only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingAccounts;
    bool isBusy(String id) =>
        id == widget.busyId ||
        id == widget.correctingId ||
        id == widget.employeeLinkingId ||
        id == widget.passwordResettingId;
    // `constraints.maxWidth` — the box this Screen actually got from its own
    // parent — not `MediaQuery.sizeOf(context).width`, the whole browser
    // window (issue #120). This Screen always renders inside the Shell's
    // content area, never the full window: at exactly 700px of *window*,
    // `PlatformShell`'s own rail breakpoint (`shell.dart`, frozen by #99's
    // own Implementation Decisions, not touched here) has just switched to
    // its 260px expanded sidebar, leaving only 440px of actual content — so
    // measuring the window told this Screen it had 700px when it truly had
    // 440, and it chose the table on that false premise. A `LayoutBuilder`
    // reads the real number instead, so [AccountsScreen.narrowBreakpoint]
    // keeps meaning what its own doc comment says: content width, not window
    // width.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The breakpoint times the reader's own text size (§10), read from the
        // box this list was handed — never the window.
        final narrow = constraints.maxWidth <
            AppBreakpoints.effective(context, AccountsScreen.narrowBreakpoint);
        final columns = _columns(context);
        return Center(
          child: AppPageFrame(
            maxWidth: AccountsScreen.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: AppFilterField(
                    name: AccountsScreen.filterFieldName,
                    label: 'Filter Accounts',
                    helperText: 'By name, email or role.',
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
                          key: AccountsScreen.noMatchKey,
                          title: 'No Accounts match',
                          message: 'This plant has Accounts, but none matches '
                              '"${_term.trim()}". Try a different name, email or role, or '
                              'clear the filter.',
                        )
                      : narrow
                          ? ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  Spacing.lg, 0, Spacing.lg, Spacing.xl),
                              itemCount: matches.length,
                              separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                              itemBuilder: (context, index) => _AccountCard(
                                account: matches[index],
                                busy: isBusy(matches[index].id),
                                isSelf: matches[index].id == widget.selfAccountId,
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(
                                  Spacing.lg, 0, Spacing.lg, Spacing.xl),
                              children: [
                                // One column spec builds both the band and every
                                // row's cells, so a label and its cells start at
                                // the same x by construction (§6).
                                AppTableHeader(columns: columns),
                                for (final account in matches)
                                  _AccountTableRow(
                                    columns: columns,
                                    account: account,
                                    busy: isBusy(account.id),
                                    isSelf: account.id == widget.selfAccountId,
                                  ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The trailing actions column, measured from the widest controls a row can
/// actually draw: `Reactivate` (the longer of Deactivate/Reactivate) plus
/// `Change` plus the two icon buttons, each at its 44px floor, plus the gutters
/// between them. Measured rather than fixed (it was a hand-set 420 before #392),
/// so the seven flexible columns get every pixel the actions do not need — and
/// at twice the reader's text the column grows with the labels instead of
/// clipping them.
double _actionsColumnWidth(BuildContext context) {
  final label = Theme.of(context).textTheme.labelLarge;
  final reactivate = _measure(context, 'Reactivate', label) + 2 * Spacing.xl;
  final change = _measure(context, 'Change', label) + 2 * Spacing.xl;
  // The two icon buttons are 48 apiece (an `IconButton`'s own default target),
  // so the column is never asked to hold less than they are.
  return reactivate +
      change +
      48 +
      48 +
      3 * Spacing.xs +
      2 * Spacing.sm;
}

/// The register's one column spec: [AppTableHeader] and every
/// [_AccountTableRow]'s cells are built from it, so a band label and its cells
/// start at the same x.
///
/// The Employee link's own control deliberately lives in the actions column
/// rather than in the Employee cell itself (a flex-sized column): that cell is
/// narrow enough at ordinary widths that a button folded into it overflowed,
/// where the measured actions column has room to spare.
List<AppTableColumn> _columns(BuildContext context) => [
      const AppTableColumn('Name', flex: 2),
      const AppTableColumn('Email', flex: 3),
      const AppTableColumn('Role', flex: 2),
      const AppTableColumn('Standing', flex: 2),
      const AppTableColumn('Since', flex: 2),
      const AppTableColumn('Grants', flex: 2),
      const AppTableColumn('Employee', flex: 2),
      AppTableColumn('Actions', width: _actionsColumnWidth(context), align: AppColumnAlign.end),
    ];

double _measure(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// The tone a standing carries: an Account that may act reads as finished, one
/// still waiting on an administrator reads as a decision owed, one turned away
/// reads as wrong, and a deactivated one as deliberately out of the way
/// (`status_tone.dart`'s five meanings). Written against the three fields rather
/// than against [ManagedAccount.standing]'s wording, so a copy change cannot
/// silently re-tone the column.
StatusTone _standingTone(ManagedAccount account) {
  if (account.isPending) return StatusTone.warning;
  if (account.approvalStatus == ApprovalStatuses.rejected) return StatusTone.danger;
  if (account.isApproved && account.isActive) return StatusTone.success;
  return StatusTone.neutral;
}

/// The avatar block, the same one the Directory draws: initials from the name
/// the Account signed up with, fitted rather than scaled so twice the reader's
/// text shrinks them inside the circle.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final words = displayName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '·'
        : words.length == 1
            ? words.first.characters.first.toUpperCase()
            : '${words.first.characters.first.toUpperCase()}'
                '${words.last.characters.first.toUpperCase()}';
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: Text(
            initials,
            style: AppTypography.floor(context)?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTableRow extends StatelessWidget {
  const _AccountTableRow({
    required this.columns,
    required this.account,
    required this.busy,
    required this.isSelf,
  });

  final List<AppTableColumn> columns;
  final ManagedAccount account;
  final bool busy;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);

    return KeyedSubtree(
      key: AccountsScreen.rowKey(account.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          Row(
            children: [
              _AccountAvatar(displayName: account.displayName),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: DisclosingText(
                  account.displayName,
                  style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          DisclosingText(account.email, style: dense?.copyWith(color: palette.textMuted)),
          // A role is one of five known words, so it is a chip rather than a
          // sentence: the reader compares roles down the column, and a chip's
          // fixed shape is what makes that comparison possible (#392).
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(label: roleLabel(account.role), tone: StatusTone.neutral),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(label: account.standing, tone: _standingTone(account)),
          ),
          DisclosingText(
            waitingFor(account.createdAt),
            style: dense?.copyWith(color: palette.textMuted),
          ),
          Align(alignment: Alignment.centerLeft, child: _GrantsCell(account: account)),
          Align(alignment: Alignment.centerLeft, child: _EmployeeCell(account: account)),
          // The framework's padded tap target is lifted here: each control states
          // its own floor, and the padded target would add height to a row that
          // already carries the 44.
          Theme(
            data: Theme.of(context)
                .copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: _RowActions(account: account, busy: busy, isSelf: isSelf),
          ),
        ],
      ),
    );
  }
}

/// The narrow (<850px of content) card — unchanged from what this Screen
/// rendered before issue #112, apart from carrying the same
/// [AccountsScreen.rowKey] the wide table row now carries too, and apart
/// from where [_RowActions] sits (issue #120 — see its own header below).
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.busy, required this.isSelf});

  final ManagedAccount account;
  final bool busy;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Card(
      key: AccountsScreen.rowKey(account.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _AccountAvatar(displayName: account.displayName),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.dense(context)?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        account.email,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // The role and the standing are the two things a reader compares
            // down this list, so both are chips here too — the same two widgets
            // the table row draws, at the same two tones (#392).
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xs,
              children: [
                StatusChip(label: roleLabel(account.role), tone: StatusTone.neutral),
                StatusChip(label: account.standing, tone: _standingTone(account)),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _Grants(account: account),
            const SizedBox(height: Spacing.sm),
            _EmployeeCell(account: account),
            const SizedBox(height: Spacing.sm),
            _RowActions(account: account, busy: busy, isSelf: isSelf),
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
    return DisclosingText(
      label,
      key: AccountsScreen.employeeKey(account.id),
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
/// hands it unbounded space. [_AccountTableRow] constrains it with a
/// fixed-width `SizedBox`; [_AccountCard] gives it a full-width line of its
/// own at the bottom of the card, below the info row, Grants and Employee
/// cell (issue #120) — the same shape `work_orders_screen.dart`'s own
/// `_WorkOrderCard` already uses for its `_RowActions`, and copied here for
/// the same reason: a `CircleAvatar` plus an info column plus this widget
/// side by side in one `Row`, as this card used to lay them out, does not
/// leave enough width for the two-button case (Deactivate/Reactivate plus
/// Change plus the Employee-link icon) once this Screen actually measures
/// its own content width instead of the browser window — at the 700px window
/// where the Shell's own sidebar breakpoint used to collide with this
/// Screen's old one, the content box is 440px, and three controls beside an
/// avatar and an info column do not fit at that width no matter how they are
/// wrapped. Giving `_RowActions` its own line, rather than trying to squeeze
/// it beside the info column with a `Flexible` (tried once already, and
/// rejected because `Flexible` next to this `Row`'s own `Expanded` splits the
/// remaining space between the two instead of letting the info column keep
/// whatever the actions do not need), removes the competition for width
/// entirely: neither branch needs a `Flexible`, and neither can overflow the
/// other.
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
      return DisclosingText(
        'Your own Account. Another administrator has to change it.',
        key: AccountsScreen.selfKey(account.id),
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

    // A `Wrap`, not a `Row` (issue #270): four controls fit on one line in the
    // table's fixed [_actionsColumnWidth], but the card at the 700px window
    // hands this widget only 376px, so there they flow onto a second line
    // rather than overflow — and are never dropped, since an administrator
    // needs them most on the phone-sized layout.
    return Wrap(
      spacing: Spacing.xs,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Only an approved Account can be deactivated or reactivated: the
        // server refuses either for a rejected one, whose way back in is a
        // correction (`setAccountActive`, service.js).
        if (account.isApproved)
          OutlinedButton(
            key: AccountsScreen.activeKey(account.id),
            onPressed: busy ? null : () => _toggleActive(context, account),
            child: Text(account.isActive ? 'Deactivate' : 'Reactivate'),
          ),
        FilledButton(
          key: AccountsScreen.correctKey(account.id),
          onPressed: busy ? null : () => AccountCorrectionDialog.open(context, account),
          child: const Text('Change'),
        ),
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
        // Reset the Account's password (issue #270) — after the two early
        // returns above, so absent on the caller's own row and a pending one.
        IconButton(
          key: AccountsScreen.resetPasswordKey(account.id),
          icon: const Icon(Icons.lock_reset, size: 20),
          tooltip: 'Reset password',
          visualDensity: VisualDensity.compact,
          onPressed: busy ? null : () => AccountPasswordDialog.open(context, account),
        ),
        // The groups this person is in (issue #492, ADR-0061): one control that
        // opens the Assign dialog. A `Roles` label would not fit the fixed
        // [_actionsColumnWidth] beside four other controls, so this is the same
        // icon-button shape the password reset takes.
        IconButton(
          key: AccountsScreen.rolesKey(account.id),
          icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
          tooltip: 'Roles',
          visualDensity: VisualDensity.compact,
          onPressed: busy
              ? null
              : () async {
                  final notice = await AccountRolesDialog.open(
                    context,
                    accountId: account.id,
                    accountName: account.displayName,
                  );
                  if (notice == null || !context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(notice)));
                },
        ),
      ],
    );
  }
}

/// One Grant, as a person reads it: where it sits, at what level, and whether
/// it carries Quality authority (issue #204, ADR-0035) or Safety authority
/// (issue #225, ADR-0035 applied a second time) — a phrase shared by
/// [_GrantsCell]'s tooltip and [_Grants]' chips so the two layouts cannot say
/// different things about the same Grant.
String _grantLabel(AccountGrant grant) =>
    '${grant.siteName} › ${grant.name} · ${grant.level.label}'
    '${grant.qualityAuthority ? ' · Quality authority' : ''}'
    '${grant.safetyAuthority ? ' · Safety authority' : ''}';

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
        for (final grant in account.grants) _grantLabel(grant),
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
            // A Grant holding Quality or Safety authority is named as such in
            // the chip itself (issue #204, issue #225, ADR-0035), not only in
            // the wide table's tooltip: an administrator auditing "who may
            // accept bad product" or "who may close an incident" on a narrow
            // window must be able to read it without hovering.
            label: Text(_grantLabel(grant)),
            labelStyle: theme.textTheme.labelMedium,
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
    builder: (dialogContext) => AppConfirmDialog(
      title: 'Deactivate this Account?',
      description:
          '${account.email} will not be able to sign in. Nothing is deleted — '
          'the role and the Org Unit Grants stay exactly as they are, and an '
          'administrator can reactivate the Account at any time.',
      confirmLabel: 'Deactivate',
      dismissLabel: 'Cancel',
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onDismiss: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (confirmed ?? false) {
    bloc.add(AccountsActiveToggled(accountId: account.id, isActive: false));
  }
}
