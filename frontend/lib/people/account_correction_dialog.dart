/// Correcting an admitted Account: the role it holds and the Org Units it may
/// work in, replaced as one act (issue #36).
///
/// A sibling of `AdmissionDialog`, not a parameterisation of it. The two share
/// the thing the issue actually asks them to share — `OrgUnitPicker` and its
/// Bloc — and nothing else: `AdmissionDialog` takes a `PendingAccount` and
/// dispatches `ApprovalQueueAdmissionConfirmed` at `ApprovalQueueBloc`, both of
/// which belong to a queue this Screen has no part in. What is genuinely one
/// implementation is the picker; a second dialog composing it is not a second
/// picker.
///
/// It opens holding the Account's current role and current Grant set, because
/// the server replaces the whole Grant set on every Approval: an administrator
/// who came to add one Org Unit must not silently lose the four already there.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/destinations.dart';
import '../theme.dart';
import 'accounts_bloc.dart';
import 'managed_account.dart';
import 'org_unit_picker.dart';
import 'org_unit_picker_bloc.dart';
import 'role_choice.dart';

class AccountCorrectionDialog extends StatefulWidget {
  const AccountCorrectionDialog({super.key, required this.account});

  final ManagedAccount account;

  static const ValueKey<String> adminWarningKey = ValueKey<String>('correction-admin-warning');
  static const ValueKey<String> reactivationNoticeKey =
      ValueKey<String>('correction-reactivation');
  static const ValueKey<String> failureKey = ValueKey<String>('correction-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('correction-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('correction-cancel');
  static ValueKey<String> roleKey(String role) => ValueKey<String>('correction-role-$role');

  /// Opens the correction over the list.
  ///
  /// `showDialog` builds its route under the Navigator, which is not a
  /// descendant of the route-scoped `BlocProvider` the list lives in — so the
  /// Bloc is handed across explicitly rather than looked up from inside.
  static Future<void> open(BuildContext context, ManagedAccount account) {
    final bloc = context.read<AccountsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => MultiBlocProvider(
        providers: [
          BlocProvider<AccountsBloc>.value(value: bloc),
          // Dialog-scoped and built fresh on every open, exactly as the
          // admission dialog builds it — seeded with what this Account already
          // holds, which is the whole of the difference between the two.
          BlocProvider<OrgUnitPickerBloc>(
            create: (_) => OrgUnitPickerBloc(
              peopleApi: peopleApi,
              authGateway: authGateway,
              initialGranted: [for (final grant in account.grants) grant.toGranted()],
            )..add(const OrgUnitPickerStarted()),
          ),
        ],
        child: AccountCorrectionDialog(account: account),
      ),
    );
  }

  @override
  State<AccountCorrectionDialog> createState() => _AccountCorrectionDialogState();
}

class _AccountCorrectionDialogState extends State<AccountCorrectionDialog> {
  /// Starts on what the Account holds now — unlike an admission, where no role
  /// has been chosen yet and none may be assumed.
  late String _role = widget.account.role;

  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final grants = _role == Roles.admin
        ? const <Map<String, Object?>>[]
        : context.read<OrgUnitPickerBloc>().state.grantsPayload;
    context.read<AccountsBloc>().add(
          AccountsCorrectionConfirmed(
            accountId: widget.account.id,
            role: _role,
            grants: grants,
            expectedApprovalStatus: widget.account.approvalStatus,
          ),
        );
  }

  void _onAccountsChanged(BuildContext context, AccountsState state) {
    if (!_awaiting || state is! AccountsLoaded) return;
    if (state.correctingId == widget.account.id) return; // Still in flight.

    final failure = state.correctionFailure;
    if (failure == null) {
      // Landed, or superseded by a re-read the list itself now reports.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _awaiting = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wasDeactivated = widget.account.isApproved && !widget.account.isActive;
    final wasRejected = widget.account.approvalStatus == ApprovalStatuses.rejected;

    return BlocConsumer<AccountsBloc, AccountsState>(
      listener: _onAccountsChanged,
      builder: (context, state) {
        return AlertDialog(
          title: const Text('Change role and Grants'),
          content: SizedBox(
            width: math.max(280, math.min(MediaQuery.sizeOf(context).width - 160, 880)),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.account.email} holds the role and the Org Unit Grants '
                    'chosen here. Whatever is set below replaces what it has now.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.md),
                  RadioGroup<String>(
                    groupValue: _role,
                    onChanged: (role) {
                      if (_awaiting || role == null) return;
                      setState(() => _role = role);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final choice in admissionRoles)
                          RadioListTile<String>(
                            key: AccountCorrectionDialog.roleKey(choice.role),
                            value: choice.role,
                            title: Text(choice.label),
                            subtitle: Text(choice.description),
                            enabled: !_awaiting,
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (_role == Roles.admin)
                    _Callout(
                      key: AccountCorrectionDialog.adminWarningKey,
                      icon: Icons.warning_amber_outlined,
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                      message: 'An administrator can act everywhere. This Account will '
                          'be able to see and change every Site and every Org Unit, and '
                          'to admit other Accounts. Every Org Unit Grant it holds now is '
                          'removed, and none are needed.',
                    )
                  else ...[
                    const SizedBox(height: Spacing.md),
                    OrgUnitPicker(enabled: !_awaiting),
                  ],
                  // The server's own behaviour, said out loud rather than left
                  // to be discovered: approveAccount sets is_active TRUE in the
                  // same transaction as the role and the Grants
                  // (`backend/src/modules/people/service.js`), so saving this
                  // lets a deactivated or rejected Account back in.
                  if (wasDeactivated || wasRejected)
                    _Callout(
                      key: AccountCorrectionDialog.reactivationNoticeKey,
                      icon: Icons.info_outline,
                      background: theme.colorScheme.secondaryContainer,
                      foreground: theme.colorScheme.onSecondaryContainer,
                      message: wasRejected
                          ? 'This Account was turned away. Saving this admits it to the '
                              'Platform and lets it sign in.'
                          : 'This Account is deactivated. Saving this reactivates it and '
                              'lets it sign in again.',
                    ),
                  if (_failure != null)
                    _Callout(
                      key: AccountCorrectionDialog.failureKey,
                      icon: Icons.error_outline,
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                      message: _failure!,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: AccountCorrectionDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: AccountCorrectionDialog.submitKey,
              onPressed: _awaiting ? null : _submit,
              child: Text(_awaiting ? 'Saving…' : 'Save'),
            ),
          ],
        );
      },
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    super.key,
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
