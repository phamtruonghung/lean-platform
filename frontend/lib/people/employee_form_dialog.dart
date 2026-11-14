/// Adding an Employee (issue #87): the plant record itself — who they are,
/// what kind of employment it is, the employee number the rest of the plant
/// already knows them by.
///
/// A sibling of `AssetFormDialog`, not a parameterisation of it: same shape
/// (a Bloc-backed dialog, disabled while required fields are empty, a failure
/// shown inline rather than swallowed), but nothing here is shared — an
/// Employee's own fields are nothing like an Asset's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'directory_bloc.dart';
import 'employment_type.dart';
import '../l10n/vocabulary.dart';

class EmployeeFormDialog extends StatefulWidget {
  const EmployeeFormDialog({super.key});

  static const ValueKey<String> employeeNoKey = ValueKey<String>('employee-form-employee-no');
  static const ValueKey<String> firstNameKey = ValueKey<String>('employee-form-first-name');
  static const ValueKey<String> lastNameKey = ValueKey<String>('employee-form-last-name');
  static const ValueKey<String> employmentTypeKey = ValueKey<String>('employee-form-employment-type');
  static const ValueKey<String> workEmailKey = ValueKey<String>('employee-form-work-email');
  static final ValueKey<String> submitKey = AppDialog.actionKey('employee-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('employee-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-form-failure');

  /// Opens the form over the Directory. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider` the Directory lives in — so the Bloc is handed across
  /// explicitly, the same device `AssetFormDialog.open` uses.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<DirectoryBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<DirectoryBloc>.value(
        value: bloc,
        child: const EmployeeFormDialog(),
      ),
    );
  }

  @override
  State<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<EmployeeFormDialog> {
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _workEmail = TextEditingController();

  /// Defaults to the baseline's own default ('permanent'), matching
  /// `createEmployee`'s own fallback (directory.js) — never left null, since
  /// a dropdown pre-selected on the server's own default is one fewer
  /// decision to make than an empty one.
  String _employmentType = employmentTypes.first;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _employeeNo.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _workEmail.dispose();
    super.dispose();
  }

  bool get _complete =>
      _employeeNo.text.trim().isNotEmpty &&
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<DirectoryBloc>().add(
          DirectoryAddConfirmed(
            employeeNo: _employeeNo.text.trim(),
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            employmentType: _employmentType,
            workEmail: _workEmail.text.trim().isEmpty ? null : _workEmail.text.trim(),
          ),
        );
  }

  void _onDirectoryChanged(BuildContext context, DirectoryState state) {
    if (!_awaiting || state is! DirectoryLoaded || state.isAdding) return;
    if (state.addFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.addFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocListener<DirectoryBloc, DirectoryState>(
      listener: _onDirectoryChanged,
      child: AppDialog(
        title: l10n.commonAddEmployee,
        size: AppDialogSize.form,
        // `child` last, as `sort_child_properties_last` requires (and #398's
        // own note records for every migrated dialog).
        actions: [
          AppDialogAction(
            id: 'employee-form-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'employee-form-submit',
            label: _awaiting ? l10n.commonAdding : l10n.commonAddEmployee,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: SizedBox(
          width: double.infinity,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: EmployeeFormDialog.employeeNoKey,
                  controller: _employeeNo,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      InputDecoration(labelText: l10n.commonEmployeeNumber, border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: EmployeeFormDialog.firstNameKey,
                        controller: _firstName,
                        enabled: !_awaiting,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            InputDecoration(labelText: l10n.commonFirstName, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: TextField(
                        key: EmployeeFormDialog.lastNameKey,
                        controller: _lastName,
                        enabled: !_awaiting,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            InputDecoration(labelText: l10n.commonLastName, border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: EmployeeFormDialog.employmentTypeKey,
                  initialValue: _employmentType,
                  decoration:
                      InputDecoration(labelText: l10n.commonEmploymentType, border: OutlineInputBorder()),
                  items: [
                    for (final type in employmentTypes)
                      DropdownMenuItem<String>(value: type, child: Text(employmentTypeLabel(l10n, type))),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) => setState(() => _employmentType = value ?? _employmentType),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeFormDialog.workEmailKey,
                  controller: _workEmail,
                  enabled: !_awaiting,
                  decoration: InputDecoration(
                    labelText: l10n.commonWorkEmailOptional,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: EmployeeFormDialog.failureKey,
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
    );
  }
}
