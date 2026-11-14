/// Handing one person a role: every role on offer, the ones already held, and
/// the Assign button (issue #492, ADR-0061).
///
/// **Where this lives and why.** The card's own words were "the administrator
/// puts the user into that role group and presses assign" — a person and a
/// group. The Accounts Screen is where an administrator already looks at a
/// person, so the control is on that row and this dialog answers the question
/// it raises. The groups themselves are edited on the Roles Screen; this is the
/// one write that never changes what a role carries.
///
/// **A plain `StatefulWidget`, not a Bloc** — `EmployeeLinkPicker`'s own
/// precedent, and the same reason: a dialog is not a Screen. It reads
/// `GET /accounts/:id/roles` once on open, holds only the ticked set, and
/// reports its own failure inline; there is no state machine worth a Bloc.
///
/// **The automatic roles are drawn, ticked and disabled.** The default group
/// and the role this Account's own `app_users.role` earns are held by every
/// Account that falls into them whether or not anything was assigned, so a
/// checkbox that could be unticked would promise a revocation the server cannot
/// perform — the server refuses such an id with a sentence naming the role, and
/// this dialog never offers the chance to see it.
///
/// Assign replaces the Account's explicit assignment with what is ticked and
/// carries a confirmation line back to the Accounts Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'app_role.dart';
import '../widgets/notice_text.dart';

class AccountRolesDialog extends StatefulWidget {
  const AccountRolesDialog({
    super.key,
    required this.accountId,
    required this.accountName,
    required this.peopleApi,
    required this.authGateway,
  });

  final String accountId;
  final String accountName;
  final PeopleApi peopleApi;
  final AuthGateway authGateway;

  static ValueKey<String> checkboxKey(String roleId) => ValueKey<String>('account-role-$roleId');
  static ValueKey<String> automaticKey(String roleId) =>
      ValueKey<String>('account-role-automatic-$roleId');
  static const ValueKey<String> countKey = ValueKey<String>('account-roles-count');
  static const ValueKey<String> failureKey = ValueKey<String>('account-roles-failure');
  static const ValueKey<String> loadingKey = ValueKey<String>('account-roles-loading');

  static final ValueKey<String> submitKey = AppDialog.actionKey('account-roles-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('account-roles-cancel');

  static const String _submitId = 'account-roles-submit';
  static const String _cancelId = 'account-roles-cancel';

  /// Opens the dialog over the Accounts Screen.
  ///
  /// Unlike the role dialogs this one does not hand a Bloc across: it needs the
  /// API and the session's token, both of which are app-wide providers, so it
  /// reads them from the dialog's own context.
  static Future<String?> open(
    BuildContext context, {
    required String accountId,
    required String accountName,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AccountRolesDialog(
        accountId: accountId,
        accountName: accountName,
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      ),
    );
  }

  @override
  State<AccountRolesDialog> createState() => _AccountRolesDialogState();
}

class _AccountRolesDialogState extends State<AccountRolesDialog> {
  AccountRoles? _held;
  Set<String> _selected = {};
  String? _failure;
  bool _awaiting = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final token = widget.authGateway.currentAccessToken;
    if (token == null) {
      setState(() => _failure = AppLocalizations.of(context).commonSessionEnded);
      return;
    }
    try {
      final held = await widget.peopleApi.fetchAccountRoles(token, widget.accountId);
      if (!mounted) return;
      setState(() {
        _held = held;
        _selected = held.assignedIds.toSet();
      });
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() => _failure = error.message);
    }
  }

  bool get _changed {
    final held = _held;
    if (held == null) return false;
    final original = held.assignedIds.toSet();
    return _selected.length != original.length || !_selected.containsAll(original);
  }

  Future<void> _submit() async {
    if (_awaiting || !_changed) return;

    final token = widget.authGateway.currentAccessToken;
    if (token == null) {
      setState(() => _failure = AppLocalizations.of(context).commonSessionEnded);
      return;
    }

    setState(() {
      _awaiting = true;
      _failure = null;
    });

    try {
      final held = await widget.peopleApi.assignAccountRoles(
        token,
        widget.accountId,
        _selected.toList()..sort(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        held.assignable.isEmpty
            ? 'Roles assigned.'
            : 'Roles assigned: ${_summary(held)}',
      );
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _awaiting = false;
        _failure = error.message;
      });
    }
  }

  /// What the Account now holds explicitly, said in role names rather than
  /// codes where there is a name to use — the same courtesy every other
  /// confirmation on this Platform pays.
  String _summary(AccountRoles held) {
    final names = [
      for (final role in held.roles)
        if (role.isAssigned) role.name,
    ];
    return names.isEmpty ? 'none' : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final held = _held;
    final failure = _failure;

    return AppDialog(
      title: l10n.accountRolesRolesFor(widget.accountName),
      size: AppDialogSize.form,
      actions: [
        AppDialogAction(
          id: AccountRolesDialog._cancelId,
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: AccountRolesDialog._submitId,
          label: _awaiting ? l10n.commonAssigning : l10n.commonAssign,
          onPressed: !_awaiting && held != null && _changed ? _submit : null,
        ),
      ],
      child: held == null
          ? Padding(
              key: AccountRolesDialog.loadingKey,
              padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
              child: failure == null
                  ? const Center(child: CircularProgressIndicator())
                  : NoticeText(
                      failure,
                      key: AccountRolesDialog.failureKey,
                      style: AppTypography.dense(context)
                          ?.copyWith(color: palette.statusForeground(StatusTone.danger)),
                    ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.accountRolesRoleAssigned(_selected.length),
                  key: AccountRolesDialog.countKey,
                  style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: Spacing.sm),
                for (final role in held.roles)
                  if (role.isAutomatic)
                    CheckboxListTile(
                      key: AccountRolesDialog.automaticKey(role.id),
                      value: true,
                      onChanged: null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(role.name),
                      subtitle: Text(
                        role.isDefault
                            ? l10n.accountRolesEveryAccountHoldsThis(role.code)
                            : l10n.accountRolesEveryAccountWhoseOwnRoleIs(
                                role.code, role.legacyRole ?? ''),
                      ),
                    )
                  else
                    CheckboxListTile(
                      key: AccountRolesDialog.checkboxKey(role.id),
                      value: _selected.contains(role.id),
                      onChanged: _awaiting
                          ? null
                          : (ticked) => setState(() {
                                if (ticked == true) {
                                  _selected.add(role.id);
                                } else {
                                  _selected.remove(role.id);
                                }
                              }),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(role.name),
                      subtitle: Text(
                        l10n.accountRolesPermission(role.code, role.permissionCodes.length),
                      ),
                    ),
                if (failure != null)
                  Padding(
                    key: AccountRolesDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: NoticeText(
                      failure,
                      style: AppTypography.dense(context)
                          ?.copyWith(color: palette.statusForeground(StatusTone.danger)),
                    ),
                  ),
              ],
            ),
    );
  }
}
