/// An administrator sets another Account's password (issue #270): `POST
/// /accounts/:id/password`. Opened from the Accounts Screen's row actions,
/// never on the caller's own row (ADR-0013 — the server refuses it too).
///
/// A plain `showDialog` like every other Account dialog in this Module:
/// ADR-0021's addresses are for transitions of a record somebody might link a
/// colleague to, and nobody links to a half-typed password.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart' show PeopleApi;
import '../theme.dart';
import 'accounts_bloc.dart';
import 'managed_account.dart';

class AccountPasswordDialog extends StatefulWidget {
  const AccountPasswordDialog({super.key, required this.account});

  final ManagedAccount account;

  static const ValueKey<String> passwordFieldKey = ValueKey<String>('account-password-field');
  static const ValueKey<String> failureKey = ValueKey<String>('account-password-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('account-password-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('account-password-cancel');

  /// Opens the dialog over the list — the same explicit Bloc hand-off every
  /// dialog in this Module uses.
  static Future<void> open(BuildContext context, ManagedAccount account) {
    final bloc = context.read<AccountsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AccountsBloc>.value(
        value: bloc,
        child: AccountPasswordDialog(account: account),
      ),
    );
  }

  @override
  State<AccountPasswordDialog> createState() => _AccountPasswordDialogState();
}

class _AccountPasswordDialogState extends State<AccountPasswordDialog> {
  final TextEditingController _password = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    final password = _password.text;
    // A nicer message than a round trip for the obvious case; the server's own
    // refusal stays authoritative for everything else.
    if (password.length < PeopleApi.minimumPasswordLength) {
      setState(() => _failure =
          'Use at least ${PeopleApi.minimumPasswordLength} characters.');
      return;
    }
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<AccountsBloc>().add(
          AccountsPasswordResetConfirmed(accountId: widget.account.id, password: password),
        );
  }

  void _onAccountsChanged(BuildContext context, AccountsState state) {
    if (!_awaiting || state is! AccountsLoaded) return;
    if (state.passwordResettingId == widget.account.id) return; // Still in flight.

    final failure = state.passwordResetFailure;
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
          title: const Text('Reset password'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose a new password for ${widget.account.email}. '
                    'Tell them what it is yourself; it is not shown again.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: AccountPasswordDialog.passwordFieldKey,
                    controller: _password,
                    enabled: !_awaiting,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      helperText: 'At least ${PeopleApi.minimumPasswordLength} characters.',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_failure != null)
                    Padding(
                      key: AccountPasswordDialog.failureKey,
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
              key: AccountPasswordDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: AccountPasswordDialog.submitKey,
              onPressed: _awaiting ? null : _submit,
              child: Text(_awaiting ? 'Saving…' : 'Reset password'),
            ),
          ],
        );
      },
    );
  }
}
