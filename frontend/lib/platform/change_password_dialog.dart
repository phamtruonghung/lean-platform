/// The signed-in person changes their own password (issue #270), opened from
/// the Shell's account menu. Current password and a new one, both obscured; a
/// refusal — a wrong current password included — is shown inside the dialog in
/// the server's own words and the person stays signed in.
///
/// A plain `showDialog`, like every other confirm-style dialog: ADR-0021's
/// addresses are for transitions of a record, and nobody links to a
/// half-typed password.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../theme.dart';
import '../widgets/app_form_submit.dart';
import 'auth_gateway.dart';
import 'change_password_bloc.dart';
import '../widgets/notice_text.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  static const ValueKey<String> currentFieldKey = ValueKey<String>('change-password-current');
  static const ValueKey<String> newFieldKey = ValueKey<String>('change-password-new');
  static const ValueKey<String> failureKey = ValueKey<String>('change-password-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('change-password-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('change-password-cancel');

  /// Opens the dialog; on success closes it and confirms on the Shell's own
  /// messenger. The Bloc is dialog-scoped and built fresh on every open.
  ///
  /// The catalogue is read **before** the first `await`: `showDialog` returns a
  /// future, and the `BuildContext` that resolved it belongs to the Screen
  /// behind the dialog. The `AppLocalizations` object itself is a plain value
  /// and stays usable after the dialog closes.
  static Future<void> open(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    final messenger = ScaffoldMessenger.of(context);
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<ChangePasswordBloc>(
        create: (_) => ChangePasswordBloc(peopleApi: peopleApi, authGateway: authGateway),
        child: const ChangePasswordDialog(),
      ),
    );
    if (changed ?? false) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountPasswordChanged)));
    }
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();

  /// A local pre-check's message; a server refusal comes through the Bloc.
  String? _localFailure;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  void _submit(ChangePasswordState state) {
    if (state is ChangePasswordInProgress) return;
    final l10n = AppLocalizations.of(context);
    if (_current.text.isEmpty) {
      setState(() => _localFailure = l10n.accountPasswordCurrentRequired);
      return;
    }
    if (_new.text.length < PeopleApi.minimumPasswordLength) {
      setState(() =>
          _localFailure = l10n.accountPasswordTooShort(PeopleApi.minimumPasswordLength));
      return;
    }
    setState(() => _localFailure = null);
    context.read<ChangePasswordBloc>().add(
          ChangePasswordSubmitted(currentPassword: _current.text, newPassword: _new.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocConsumer<ChangePasswordBloc, ChangePasswordState>(
      listener: (context, state) {
        if (state is ChangePasswordSucceeded) Navigator.of(context).pop(true);
      },
      builder: (context, state) {
        final awaiting = state is ChangePasswordInProgress;
        final failure = _localFailure ?? (state is ChangePasswordFailed ? state.message : null);
        return AlertDialog(
          title: Text(l10n.shellChangePassword),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              // `Enter` in either field submits (issue #401): both are
              // single-line, the form has one primary act, and a keyboard reader
              // should not have to reach for the button. Null while the request
              // is in flight, the same null both buttons carry.
              child: AppFormSubmit(
                onSubmit: awaiting ? null : () => _submit(state),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: ChangePasswordDialog.currentFieldKey,
                      controller: _current,
                      enabled: !awaiting,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(labelText: l10n.accountPasswordCurrent),
                    ),
                    const SizedBox(height: Spacing.md),
                    TextField(
                      key: ChangePasswordDialog.newFieldKey,
                      controller: _new,
                      enabled: !awaiting,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.accountPasswordNew,
                        helperText: l10n.accountPasswordMinimum(PeopleApi.minimumPasswordLength),
                      ),
                      onSubmitted: (_) => _submit(state),
                    ),
                    if (failure != null)
                      Padding(
                        key: ChangePasswordDialog.failureKey,
                        padding: const EdgeInsets.only(top: Spacing.md),
                        child: NoticeText(
                          failure,
                          style:
                              theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              key: ChangePasswordDialog.cancelKey,
              onPressed: awaiting ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: ChangePasswordDialog.submitKey,
              onPressed: awaiting ? null : () => _submit(state),
              child: Text(awaiting ? l10n.commonSaving : l10n.shellChangePassword),
            ),
          ],
        );
      },
    );
  }
}
