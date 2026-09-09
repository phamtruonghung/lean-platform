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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'job_role.dart';
import 'job_roles_bloc.dart';

class JobRoleFormDialog extends StatefulWidget {
  const JobRoleFormDialog({super.key, this.jobRole});

  /// Null for Add; the row being corrected otherwise.
  final JobRole? jobRole;

  static const ValueKey<String> codeKey = ValueKey<String>('job-role-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('job-role-form-name');
  static const ValueKey<String> activeKey = ValueKey<String>('job-role-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('job-role-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('job-role-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('job-role-form-failure');

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
    final theme = Theme.of(context);
    return BlocListener<JobRolesBloc, JobRolesState>(
      listener: _onJobRolesChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct job role' : 'Add job role'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
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
                if (_failure != null)
                  Padding(
                    key: JobRoleFormDialog.failureKey,
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
            key: JobRoleFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: JobRoleFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add job role')),
          ),
        ],
      ),
    );
  }
}
