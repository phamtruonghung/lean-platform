/// Correcting an already-admitted Account's Employee link (issue #116,
/// ADR-0022): `PUT /accounts/:id/employee`, the dedicated correction route —
/// not Approval, and never touching role or Grants. Opened from the Accounts
/// Screen's own Employee cell, for a suggestion missed at Approval time, an
/// Employee record that arrived after the Account did, or a mistake.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'accounts_bloc.dart';
import 'employee_link_picker.dart';
import 'employee_ref.dart';
import 'managed_account.dart';

class AccountEmployeeDialog extends StatefulWidget {
  const AccountEmployeeDialog({super.key, required this.account});

  final ManagedAccount account;

  static const ValueKey<String> failureKey = ValueKey<String>('account-employee-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('account-employee-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('account-employee-cancel');

  /// Opens the correction over the list — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context, ManagedAccount account) {
    final bloc = context.read<AccountsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AccountsBloc>.value(
        value: bloc,
        child: AccountEmployeeDialog(account: account),
      ),
    );
  }

  @override
  State<AccountEmployeeDialog> createState() => _AccountEmployeeDialogState();
}

class _AccountEmployeeDialogState extends State<AccountEmployeeDialog> {
  /// Starts on whatever this Account already holds — null is a real starting
  /// point too, for a row with no Employee linked yet.
  late EmployeeRef? _selected = widget.account.linkedEmployee;

  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<AccountsBloc>().add(
          AccountsEmployeeLinkConfirmed(accountId: widget.account.id, employeeId: _selected?.id),
        );
  }

  void _onAccountsChanged(BuildContext context, AccountsState state) {
    if (!_awaiting || state is! AccountsLoaded) return;
    if (state.employeeLinkingId == widget.account.id) return; // Still in flight.

    final failure = state.employeeLinkFailure;
    if (failure == null) {
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
    return BlocConsumer<AccountsBloc, AccountsState>(
      listener: _onAccountsChanged,
      builder: (context, state) {
        return AlertDialog(
          title: const Text('Change Employee link'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.account.email} will be linked to the Employee chosen here, '
                    'or to none.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.md),
                  EmployeeLinkPicker(
                    initial: _selected,
                    enabled: !_awaiting,
                    onChanged: (employee) => setState(() => _selected = employee),
                  ),
                  if (_failure != null)
                    Padding(
                      key: AccountEmployeeDialog.failureKey,
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Text(
                        _failure!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: AccountEmployeeDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: AccountEmployeeDialog.submitKey,
              onPressed: _awaiting ? null : _submit,
              child: Text(_awaiting ? 'Saving…' : 'Save'),
            ),
          ],
        );
      },
    );
  }
}
