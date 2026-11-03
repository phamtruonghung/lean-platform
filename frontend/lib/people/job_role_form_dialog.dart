/// Adding a job role, and correcting one (issue #88): the shared catalogue's
/// own write surface (`POST`/`PATCH /api/people/job-roles`,
/// job-role-routes.js, administrator only).
///
/// One dialog for both, unlike `EmployeeFormDialog`/`EmployeeCorrectionDialog`'s
/// own split: a job role carries two fields and an active flag, not enough
/// surface to earn two files. [jobRole] null means Add; non-null means
/// Correct, and Correct sends only the fields that actually changed — the
/// same `hasOwnProperty` contract `EmployeeCorrectionDialog` already keeps
/// for the Employee record, on `updateJobRole`'s (job-roles.js) own end.
///
/// A job role is deactivated, never deleted (job-roles.js's own header) — the
/// "Active" switch, offered only while correcting an existing row, is the one
/// way this dialog ever reaches `isActive`; there is no delete anywhere on
/// this Screen.
///
/// **Drawn in `AppDialog` (issue #394, ADR-0058).** The shell, the width and
/// the sheet behaviour at a narrow box or a large text scale are the shared
/// dialog's, not this file's: it used to be an `AlertDialog` with the width set
/// on a `SizedBox` *inside* its content, which left the title and the action row
/// at the platform's own width. At [AppDialogSize.form] (520) — a three-field
/// form is a short form, not a decision (420). Nothing else moved: the two
/// field keys, the Active switch, the failure line's copy, the enable condition
/// on Add/Save and the `Saving…` label are the same, and the two action keys are
/// `AppDialog.actionKey` of the ids this dialog gives them, which is the one
/// rename (#398's pattern) the PR lists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'job_role.dart';
import 'job_roles_bloc.dart';

class JobRoleFormDialog extends StatefulWidget {
  const JobRoleFormDialog({super.key, this.jobRole});

  /// Null for Add; the row being corrected otherwise.
  final JobRole? jobRole;

  static const ValueKey<String> codeKey = ValueKey<String>('job-role-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('job-role-form-name');
  static const ValueKey<String> activeKey = ValueKey<String>('job-role-form-active');

  /// The two actions, named through the dialog shell that now draws them
  /// (`AppDialog.actionKey`, ADR-0058). The accessors are unchanged; the key
  /// values are the shell's own, which is the rename #398 established.
  static final ValueKey<String> submitKey = AppDialog.actionKey('job-role-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('job-role-form-cancel');

  static const ValueKey<String> failureKey = ValueKey<String>('job-role-form-failure');

  static const String _submitId = 'job-role-form-submit';
  static const String _cancelId = 'job-role-form-cancel';

  /// Opens the form over the job role catalogue. `showDialog` builds its
  /// route under the Navigator, which is not a descendant of the
  /// route-scoped `BlocProvider<JobRolesBloc>` the Screen lives in — so that
  /// Bloc is handed across explicitly, the same device every other dialog in
  /// this Module uses.
  static Future<void> open(BuildContext context, {JobRole? jobRole}) {
    final bloc = context.read<JobRolesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<JobRolesBloc>.value(
        value: bloc,
        child: JobRoleFormDialog(jobRole: jobRole),
      ),
    );
  }

  @override
  State<JobRoleFormDialog> createState() => _JobRoleFormDialogState();
}

class _JobRoleFormDialogState extends State<JobRoleFormDialog> {
  late final TextEditingController _code = TextEditingController(text: widget.jobRole?.code ?? '');
  late final TextEditingController _name = TextEditingController(text: widget.jobRole?.name ?? '');
  late bool _isActive = widget.jobRole?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.jobRole != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — never the whole form, whatever was left untouched. Only called
  /// while correcting an existing row, where `widget.jobRole` is non-null.
  Map<String, Object?> get _changes {
    final original = widget.jobRole!;
    final changes = <String, Object?>{};
    final code = _code.text.trim();
    if (code != original.code) changes['code'] = code;
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
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
      context.read<JobRolesBloc>().add(JobRolesCorrectionConfirmed(id: widget.jobRole!.id, changes: changes));
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<JobRolesBloc>().add(
            JobRolesAddConfirmed(code: _code.text.trim(), name: _name.text.trim()),
          );
    }
  }

  void _onJobRolesChanged(BuildContext context, JobRolesState state) {
    if (!_awaiting || state is! JobRolesLoaded || state.isMutating) return;
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
    final failure = _failure;
    return BlocListener<JobRolesBloc, JobRolesState>(
      listener: _onJobRolesChanged,
      child: AppDialog(
        title: _isCorrection ? 'Correct job role' : 'Add job role',
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: JobRoleFormDialog._cancelId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: JobRoleFormDialog._submitId,
            label: _awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add job role'),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: JobRoleFormDialog.codeKey,
              controller: _code,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: JobRoleFormDialog.nameKey,
              controller: _name,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            if (_isCorrection) ...[
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                key: JobRoleFormDialog.activeKey,
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
              ),
            ],
            if (failure != null)
              Padding(
                key: JobRoleFormDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
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
