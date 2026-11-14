/// Adding a role, and correcting one (issue #492, ADR-0061).
///
/// One dialog for both, the same shape `JobRoleFormDialog` takes and for the
/// same reason: a role carries a name, a description and an active flag — not
/// enough surface to earn a second file. [role] null means Add; non-null means
/// Correct.
///
/// **The code is typed once and then never changes.** It is the role's identity
/// — the string an administrator writes in a request for access, and what the
/// server's refusals name (`ROLE_STORE_ROOM`) — so Correct shows it read-only
/// rather than offering an edit that the server's own `PATCH` does not accept.
/// A role that needs a different code is a new role and a retired old one.
///
/// Correct sends only the fields that actually changed, which is
/// `updateRole`'s (roles.js) own `hasOwnProperty` contract on the other end —
/// the same discipline `JobRoleFormDialog` and `EmployeeCorrectionDialog`
/// already keep.
///
/// A role is retired, never deleted: the "In active use" switch, offered only
/// while correcting, is the one way this dialog reaches `isActive`. There is no
/// delete anywhere on the Roles Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_scan_field.dart';
import 'app_role.dart';
import 'roles_bloc.dart';
import '../widgets/notice_text.dart';

class RoleFormDialog extends StatefulWidget {
  const RoleFormDialog({super.key, this.role, this.permissions});

  /// Null for Add; the role being corrected otherwise.
  final AppRole? role;

  /// The codes the new role starts with. Only read on Add — the permission
  /// editor is the way to change what an existing role carries, so a form that
  /// also carried a set would be a second door onto the same write.
  final List<String>? permissions;

  static const ValueKey<String> codeKey = ValueKey<String>('role-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('role-form-name');
  static const ValueKey<String> descriptionKey = ValueKey<String>('role-form-description');
  static const ValueKey<String> activeKey = ValueKey<String>('role-form-active');

  static final ValueKey<String> submitKey = AppDialog.actionKey('role-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('role-form-cancel');

  static const ValueKey<String> failureKey = ValueKey<String>('role-form-failure');

  static const String _submitId = 'role-form-submit';
  static const String _cancelId = 'role-form-cancel';

  /// Opens the form over the Roles Screen. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<RolesBloc>`, so that Bloc is handed across explicitly — the
  /// same device every dialog in this Module uses.
  static Future<void> open(BuildContext context, {AppRole? role, List<String>? permissions}) {
    final bloc = context.read<RolesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<RolesBloc>.value(
        value: bloc,
        child: RoleFormDialog(role: role, permissions: permissions),
      ),
    );
  }

  @override
  State<RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<RoleFormDialog> {
  late final TextEditingController _code = TextEditingController(text: widget.role?.code ?? '');
  late final TextEditingController _name = TextEditingController(text: widget.role?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.role?.description ?? '');
  late bool _isActive = widget.role?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.role != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  /// Only the keys whose value actually changed from what this dialog opened
  /// with. Only called while correcting, where `widget.role` is non-null.
  Map<String, Object?> get _changes {
    final original = widget.role!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    final description = _description.text.trim();
    if (description != original.description) changes['description'] = description;
    if (_isActive != original.isActive) changes['isActive'] = _isActive;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;

    if (_isCorrection) {
      final changes = _changes;
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<RolesBloc>().add(RoleCorrected(id: widget.role!.id, changes: changes));
      return;
    }

    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<RolesBloc>().add(RoleCreated(
          code: _code.text.trim(),
          name: _name.text.trim(),
          description: _description.text.trim(),
          permissions: widget.permissions ?? const [],
        ));
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
    final failure = _failure;
    return BlocListener<RolesBloc, RolesState>(
      listener: _onRolesChanged,
      child: AppDialog(
        title: _isCorrection ? l10n.roleFormCorrectRole : l10n.commonAddRole,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: RoleFormDialog._cancelId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: RoleFormDialog._submitId,
            label: _awaiting ? l10n.commonSaving : (_isCorrection ? l10n.commonSave : l10n.commonAddRole),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppScanField(
              key: RoleFormDialog.codeKey,
              controller: _code,
              label: l10n.commonCode,
              helperText: l10n.roleForm330CharactersAZ09,
              // Typed once, then the role's identity: a code is what a request
              // for access names, and the server's PATCH does not accept one.
              enabled: !_isCorrection && !_awaiting,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: RoleFormDialog.nameKey,
              controller: _name,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.commonName, border: OutlineInputBorder()),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: RoleFormDialog.descriptionKey,
              controller: _description,
              enabled: !_awaiting,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.roleFormWhatItIsFor,
                border: OutlineInputBorder(),
              ),
            ),
            if (_isCorrection) ...[
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                key: RoleFormDialog.activeKey,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.roleFormInActiveUse),
                subtitle: Text(l10n.roleFormARetiredRoleKeepsItsHistoryAnd),
                value: _isActive,
                onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
              ),
            ],
            if (failure != null)
              Padding(
                key: RoleFormDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
                  failure,
                  style: AppTypography.dense(context)
                      ?.copyWith(color: AppColors.of(context).statusForeground(StatusTone.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
