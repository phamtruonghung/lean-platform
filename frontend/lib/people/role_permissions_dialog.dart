/// What a role carries: the whole permission catalogue, grouped by Module, with
/// the ones this role holds ticked (issue #492, ADR-0061).
///
/// **The set is replaced, not patched.** Save sends every ticked code — the
/// complete answer to "what should this group carry" — because that is what the
/// administrator just did. `PUT /roles/:id/permissions` replaces the set in one
/// transaction on the other end, so two administrators with this dialog open
/// cannot each add half a set and lose the other's work silently: the later
/// Save wins whole, which is a rule a reader can predict.
///
/// **Grouped by Module, in the catalogue's own order.** The catalogue is
/// ordered the way the sidebar's groups render, so an administrator editing
/// "Maintenance" reads the same sequence of Screens they walk down the Shell.
/// One `CheckboxListTile` per permission: its label is the Screen's name, its
/// code and the sentence explaining it sit underneath — the sentence is what
/// stops `MTN_WORK_ORDERS_DISPLAY` and `MTN_WORK_ORDERS_CHANGE` being ticked
/// for each other.
///
/// The catalogue comes from the Roles Screen's own `RolesBloc` rather than a
/// fetch of its own: it was read when the Screen loaded, and a second read here
/// would be a second answer to the same question.
library;

import '../l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'app_role.dart';
import 'roles_bloc.dart';

class RolePermissionsDialog extends StatefulWidget {
  const RolePermissionsDialog({super.key, required this.role});

  /// The role being edited. Its `permissionCodes` is what the boxes start on.
  final AppRole role;

  static ValueKey<String> checkboxKey(String code) => ValueKey<String>('role-permission-$code');
  static ValueKey<String> moduleKey(String module) => ValueKey<String>('role-permission-module-$module');
  static const ValueKey<String> countKey = ValueKey<String>('role-permissions-count');
  static const ValueKey<String> failureKey = ValueKey<String>('role-permissions-failure');

  static final ValueKey<String> submitKey = AppDialog.actionKey('role-permissions-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('role-permissions-cancel');

  static const String _submitId = 'role-permissions-submit';
  static const String _cancelId = 'role-permissions-cancel';

  static Future<void> open(BuildContext context, {required AppRole role}) {
    final bloc = context.read<RolesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<RolesBloc>.value(
        value: bloc,
        child: RolePermissionsDialog(role: role),
      ),
    );
  }

  @override
  State<RolePermissionsDialog> createState() => _RolePermissionsDialogState();
}

class _RolePermissionsDialogState extends State<RolePermissionsDialog> {
  late final Set<String> _selected = {...widget.role.permissionCodes};

  bool _awaiting = false;
  String? _failure;

  /// Whether the set is unchanged from what the dialog opened with — Save is
  /// disabled until something is ticked or unticked, so an accidental open
  /// cannot rewrite a role with what it already carried.
  bool get _changed =>
      _selected.length != widget.role.permissionCodes.length ||
      !_selected.containsAll(widget.role.permissionCodes);

  void _toggle(String code, bool? ticked) {
    if (_awaiting) return;
    setState(() {
      if (ticked == true) {
        _selected.add(code);
      } else {
        _selected.remove(code);
      }
    });
  }

  void _submit() {
    if (_awaiting || !_changed) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    // Sorted before sending: the request's body is then stable for a reader
    // comparing two saves, and the order the boxes happened to be ticked in is
    // not information.
    final codes = _selected.toList()..sort();
    context.read<RolesBloc>().add(RolePermissionsSaved(id: widget.role.id, permissions: codes));
  }

  void _onRolesChanged(BuildContext context, RolesState state) {
    if (!_awaiting || state is! RolesLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<RolesBloc>().state;
    final palette = AppColors.of(context);
    final failure = _failure;

    // The catalogue is carried by the Screen's loaded state; opening this
    // dialog is only possible from that state, so an absent one is a bug and
    // reads as an empty list rather than a crash.
    final grouped = state is RolesLoaded ? state.permissionsByModule : const <String, List<Permission>>{};
    final total = state is RolesLoaded ? state.permissions.length : 0;
    final height = math.min(MediaQuery.sizeOf(context).height * 0.6, 460.0);

    return BlocListener<RolesBloc, RolesState>(
      listener: _onRolesChanged,
      child: AppDialog(
        title: l10n.rolePermissionsWhatCarries(widget.role.code),
        size: AppDialogSize.wide,
        actions: [
          AppDialogAction(
            id: RolePermissionsDialog._cancelId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: RolePermissionsDialog._submitId,
            label: _awaiting ? l10n.commonSaving : l10n.commonSave,
            onPressed: !_awaiting && _changed ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.rolePermissionsOfPermissions(_selected.length, total),
              key: RolePermissionsDialog.countKey,
              style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: height,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in grouped.entries) ...[
                    Padding(
                      key: RolePermissionsDialog.moduleKey(entry.key),
                      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.xs),
                      child: Text(
                        entry.key,
                        style: AppTypography.dense(context)?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final permission in entry.value)
                      CheckboxListTile(
                        key: RolePermissionsDialog.checkboxKey(permission.code),
                        value: _selected.contains(permission.code),
                        onChanged: _awaiting ? null : (ticked) => _toggle(permission.code, ticked),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: Text(permission.label),
                        subtitle: Text('${permission.code} — ${permission.description}'),
                      ),
                  ],
                ],
              ),
            ),
            if (failure != null)
              Padding(
                key: RolePermissionsDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  failure,
                  style: AppTypography.dense(context)
                      ?.copyWith(color: palette.statusForeground(StatusTone.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
