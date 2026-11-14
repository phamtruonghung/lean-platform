/// The Approval queue: who is waiting to be let in, admitting one, and turning
/// one away.
///
/// The role an admission carries is chosen in `admission_dialog.dart`; the Org
/// Unit Grant picker that dialog will grow is issue #42. A row carries an
/// email address and a wait, and nothing else: an Account need not correspond
/// to an Employee, so there is no name to show and inventing one would be a
/// lie.
///
/// **It is a decision surface, so it is a register (#392, `design-language.md`
/// §6).** A queue is worked down: the reader asks who is waiting, how long they
/// have waited, and then acts, and a decision surface that hides its decision
/// behind a row tap is a surface that has to be opened before it can be read.
/// So a row carries the Account, what the request suggests it should be linked
/// to, how long it has waited, and the two actions that end it — at the row's own
/// far end, each at least [AppTouchTarget.min] tall, and disabled rather than
/// hidden while a request is in flight. Above [narrowBreakpoint] of content
/// width the table is drawn and below it one card per Account; the number is
/// read from the box a `LayoutBuilder` hands the list and scaled by the reader's
/// text size (§10).
///
/// **The role and the Site are not on the row: the role a pending Account
/// holds is a signup default, and no Grant exists for it yet.**
/// `GET /api/people/accounts/pending` (`service.js`'s `listPendingAccounts`)
/// sends the Account row's own `role`, along with its id, email address, the
/// instant it was created and the Employee it suggests — and that `role` is
/// the signup default, `operator`, or `admin` only for the bootstrap first
/// Account, not a requested role. `PendingAccount` does not parse it, and
/// printing that default as if it were the request would misrepresent the
/// request, so a row carries who is waiting, the Employee the request
/// suggests (as a chip), how long it has waited and the two decisions that
/// end it. A pending Account holds no Grant, so there is no Site to name; the
/// role and the Org Units are chosen in `AdmissionDialog`, which is where a
/// reader first has them to look at.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../l10n/notices.dart';
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
import 'admission_dialog.dart';
import 'approval_queue_bloc.dart';
import 'pending_account.dart';
import '../widgets/notice_text.dart';

class ApprovalQueueScreen extends StatelessWidget {
  const ApprovalQueueScreen({super.key});

  /// A register's width (#392).
  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the queue is a
  /// table; below it, one card per Account. Four columns of which one holds two
  /// buttons is more than `AppBreakpoints.registerTable` (700) was measured for,
  /// so this Screen states its own 900 and reads it through
  /// [AppBreakpoints.effective].
  static const double narrowBreakpoint = 900;

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

  /// The failed read's retry button, kept at the same value it has always had —
  /// `PlatformFailureState` takes the key rather than drawing one of its own.
  static const ValueKey<String> retryKey = ValueKey<String>('approval-queue-retry');

  static ValueKey<String> rejectKey(String accountId) =>
      ValueKey<String>('approval-queue-reject-$accountId');
  static ValueKey<String> admitKey(String accountId) =>
      ValueKey<String>('approval-queue-admit-$accountId');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ApprovalQueueBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          if (state is ApprovalQueueLoaded && state.notice != null)
            _Notice(message: noticeText(l10n, state.notice!)),
          Expanded(
            child: switch (state) {
              ApprovalQueueLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              ApprovalQueueUnavailable(message: final message) => PlatformFailureState(
                  key: const ValueKey<String>('approval-queue-failed'),
                  title: l10n.approvalQueueTheQueueCouldNotBeLoaded,
                  message: message,
                  retryKey: retryKey,
                  onRetry: () =>
                      context.read<ApprovalQueueBloc>().add(const ApprovalQueueRequested()),
                ),
              // Nothing has ever been asked for, which is the *none exist*
              // variant — distinct from the filter's own *none matched* below
              // (§7).
              ApprovalQueueLoaded(accounts: final accounts) when accounts.isEmpty =>
                PlatformEmptyState.noneExist(
                  key: ValueKey<String>('approval-queue-empty'),
                  title: l10n.approvalQueueNobodyIsWaiting,
                  message: l10n.approvalQueueEveryAccountHasBeenDealtWithNew,
                ),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ApprovalQueueScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.titleApprovalQueue,
            description: l10n.approvalQueueEveryoneWaitingToBeLetInTo,
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
                  child: NoticeText(
                    message,
                    style: AppTypography.dense(context)
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
    final l10n = AppLocalizations.of(context);
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
                label: l10n.commonFilterAccounts,
                helperText: l10n.approvalQueueByEmailAddress,
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
                      title: l10n.commonNoAccountsMatch,
                      message: l10n.approvalQueueAccountsAreWaitingButNoneMatchesTry(_term.trim()),
                    )
                  : _Register(
                      accounts: matches,
                      rejectingId: widget.rejectingId,
                      admittingId: widget.admittingId,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one column spec: the band and every row are built from it, so a label and
/// its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn(AppLocalizations.of(context).approvalQueueAccount, flex: 5),
      AppTableColumn(AppLocalizations.of(context).approvalQueueSuggestedEmployee, flex: 4),
      AppTableColumn(AppLocalizations.of(context).approvalQueueWaiting, flex: 3),
      AppTableColumn(AppLocalizations.of(context).commonActions, width: _actionsColumnWidth(context), align: AppColumnAlign.end),
    ];

/// Reject and Admit side by side at the 44px floor each states, plus gutters.
/// Measured from the wider of the two labels *and* the two in-flight labels, so
/// a row does not reflow the column the moment a request is dispatched.
double _actionsColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final label = Theme.of(context).textTheme.labelLarge;
  final reject = _measure(context, l10n.approvalQueueRejecting, label);
  final rejectIdle = _measure(context, l10n.commonReject, label);
  final admit = _measure(context, l10n.commonAdmitting, label);
  final admitIdle = _measure(context, l10n.commonAdmit, label);
  final rejectWidth = reject > rejectIdle ? reject : rejectIdle;
  final admitWidth = admit > admitIdle ? admit : admitIdle;
  return rejectWidth + admitWidth + 4 * Spacing.md + 2 * Spacing.sm;
}

double _measure(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _Register extends StatelessWidget {
  const _Register({
    required this.accounts,
    required this.rejectingId,
    required this.admittingId,
  });

  final List<PendingAccount> accounts;
  final String? rejectingId;
  final String? admittingId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth <
            AppBreakpoints.effective(context, ApprovalQueueScreen.narrowBreakpoint);
        final columns = _columns(context);

        return ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          children: [
            if (!narrow) AppTableHeader(columns: columns),
            for (var index = 0; index < accounts.length; index++) ...[
              if (narrow && index > 0) const SizedBox(height: Spacing.sm),
              if (narrow)
                _QueueCard(
                  account: accounts[index],
                  rejecting: accounts[index].id == rejectingId,
                  admitting: accounts[index].id == admittingId,
                )
              else
                _QueueTableRow(
                  columns: columns,
                  account: accounts[index],
                  rejecting: accounts[index].id == rejectingId,
                  admitting: accounts[index].id == admittingId,
                ),
            ],
          ],
        );
      },
    );
  }
}

/// The framework's padded tap target is lifted on the row's buttons: each one
/// states its own [AppTouchTarget.min] and the padded target would add height to
/// a row that already carries the 44.
Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

/// The avatar block, the same one the Directory draws: the first letter of the
/// address a waiting Account is known by, fitted rather than scaled so twice the
/// reader's text shrinks it inside the circle.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = email.trim();
    final initial = trimmed.isEmpty ? '·' : trimmed.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: Text(
            initial,
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

/// What the request suggests it should be linked to, as a chip: the link is the
/// one thing about a waiting Account that has a shape other than "free text".
/// No suggestion is `—` and never an empty cell (§13's nothing-versus-zero).
Widget _suggestedCell(PendingAccount account) {
  final suggestion = account.suggestedEmployee;
  if (suggestion == null) return const Text('—');
  return StatusChip(label: suggestion.label, tone: StatusTone.info);
}

class _QueueTableRow extends StatelessWidget {
  const _QueueTableRow({
    required this.columns,
    required this.account,
    required this.rejecting,
    required this.admitting,
  });

  final List<AppTableColumn> columns;
  final PendingAccount account;
  final bool rejecting;
  final bool admitting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);

    return KeyedSubtree(
      key: ValueKey<String>('approval-queue-row-${account.id}'),
      child: AppTableRow(
        columns: columns,
        cells: [
          Row(
            children: [
              _AccountAvatar(email: account.email),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: DisclosingText(
                  account.email,
                  style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          _suggestedCell(account),
          DisclosingText(
            waitingFor(account.waitingSince),
            style: dense?.copyWith(color: palette.textMuted),
          ),
          _shrinkWrapTargets(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  key: ApprovalQueueScreen.rejectKey(account.id),
                  onPressed: rejecting || admitting
                      ? null
                      : () => _confirmRejection(context, account),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(rejecting ? l10n.approvalQueueRejecting : l10n.commonReject),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  key: ApprovalQueueScreen.admitKey(account.id),
                  onPressed: rejecting || admitting
                      ? null
                      : () => AdmissionDialog.open(context, account),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(admitting ? l10n.commonAdmitting : l10n.commonAdmit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One waiting Account as a card, for a box that cannot hold four columns — the
/// same facts and the same two actions, stacked.
class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.account,
    required this.rejecting,
    required this.admitting,
  });

  final PendingAccount account;
  final bool rejecting;
  final bool admitting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);

    return Card(
      key: ValueKey<String>('approval-queue-row-${account.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _AccountAvatar(email: account.email),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    account.email,
                    style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  waitingFor(account.waitingSince),
                  style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                ),
                _suggestedCell(account),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: ApprovalQueueScreen.rejectKey(account.id),
                  onPressed: rejecting || admitting
                      ? null
                      : () => _confirmRejection(context, account),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(rejecting ? l10n.approvalQueueRejecting : l10n.commonReject),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  key: ApprovalQueueScreen.admitKey(account.id),
                  onPressed: rejecting || admitting
                      ? null
                      : () => AdmissionDialog.open(context, account),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(admitting ? l10n.commonAdmitting : l10n.commonAdmit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks first, and sends nothing at all unless the answer is yes. The Bloc never
/// sees an unconfirmed rejection — the event is only added below.
///
/// The shell is `AppConfirmDialog` (#398's pattern): one destructive action, a
/// way out at the inline start, `Esc` cancels and initial focus is on the way
/// out, so Enter on opening cannot turn somebody away.
Future<void> _confirmRejection(BuildContext context, PendingAccount account) async {
  final l10n = AppLocalizations.of(context);
  final bloc = context.read<ApprovalQueueBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppConfirmDialog(
      title: l10n.approvalQueueRejectThisAccount,
      description:
          l10n.approvalQueueWillNotBeLetInToThe(account.email),
      confirmLabel: l10n.commonReject,
      dismissLabel: 'Cancel',
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onDismiss: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (confirmed ?? false) {
    bloc.add(ApprovalQueueRejectionConfirmed(account.id));
  }
}
