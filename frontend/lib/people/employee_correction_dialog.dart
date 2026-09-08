/// Correcting an existing Employee's record (issue #87): the employee
/// number, the name, the employment type, the work email — whichever of
/// those actually changed.
///
/// Unlike `AccountCorrectionDialog`, which always replaces the whole role and
/// Grant set, this dialog sends only the fields the caller actually edited:
/// `updateEmployee` (directory.js) only ever touches the keys present in the
/// body, and a one-field correction re-sending every other field unchanged
/// would still be honest about the *value* but dishonest about the *act* —
/// the ticket's own criterion is "a one-field edit must send one field, not
/// the whole record re-sent".
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'employee.dart';
import 'employee_detail_bloc.dart';
import 'employment_type.dart';

class EmployeeCorrectionDialog extends StatefulWidget {
  const EmployeeCorrectionDialog({super.key, required this.employee});

  final EmployeeDetail employee;

  static const ValueKey<String> employeeNoKey = ValueKey<String>('employee-correction-employee-no');
  static const ValueKey<String> firstNameKey = ValueKey<String>('employee-correction-first-name');
  static const ValueKey<String> lastNameKey = ValueKey<String>('employee-correction-last-name');
  static const ValueKey<String> employmentTypeKey =
      ValueKey<String>('employee-correction-employment-type');
  static const ValueKey<String> workEmailKey = ValueKey<String>('employee-correction-work-email');
  static const ValueKey<String> submitKey = ValueKey<String>('employee-correction-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('employee-correction-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-correction-failure');

  /// Opens the correction over the detail Screen. `showDialog` builds its
  /// route under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider` the Screen lives in — so the Bloc is handed across
  /// explicitly, the same device every other dialog in this Module uses.
  static Future<void> open(BuildContext context, EmployeeDetail employee) {
    final bloc = context.read<EmployeeDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<EmployeeDetailBloc>.value(
        value: bloc,
        child: EmployeeCorrectionDialog(employee: employee),
      ),
    );
  }

  @override
  State<EmployeeCorrectionDialog> createState() => _EmployeeCorrectionDialogState();
}

class _EmployeeCorrectionDialogState extends State<EmployeeCorrectionDialog> {
  late final TextEditingController _employeeNo =
      TextEditingController(text: widget.employee.employeeNo);
  late final TextEditingController _firstName = TextEditingController(text: widget.employee.firstName);
  late final TextEditingController _lastName = TextEditingController(text: widget.employee.lastName);
  late final TextEditingController _workEmail =
      TextEditingController(text: widget.employee.workEmail ?? '');
  late String _employmentType = widget.employee.employmentType;

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

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — never the whole form, whatever was left untouched.
  Map<String, Object?> get _changes {
    final changes = <String, Object?>{};
    final employeeNo = _employeeNo.text.trim();
    if (employeeNo != widget.employee.employeeNo) changes['employeeNo'] = employeeNo;
    final firstName = _firstName.text.trim();
    if (firstName != widget.employee.firstName) changes['firstName'] = firstName;
    final lastName = _lastName.text.trim();
    if (lastName != widget.employee.lastName) changes['lastName'] = lastName;
    if (_employmentType != widget.employee.employmentType) {
      changes['employmentType'] = _employmentType;
    }
    final workEmail = _workEmail.text.trim();
    final currentWorkEmail = widget.employee.workEmail ?? '';
    if (workEmail != currentWorkEmail) changes['workEmail'] = workEmail.isEmpty ? null : workEmail;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<EmployeeDetailBloc>().add(EmployeeDetailCorrectionConfirmed(changes));
  }

  void _onDetailChanged(BuildContext context, EmployeeDetailState state) {
    if (!_awaiting || state is! EmployeeDetailLoaded || state.isMutating) return;
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
    return BlocListener<EmployeeDetailBloc, EmployeeDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Correct ${widget.employee.displayName}\'s record'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: EmployeeCorrectionDialog.employeeNoKey,
                  controller: _employeeNo,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'Employee number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: EmployeeCorrectionDialog.firstNameKey,
                        controller: _firstName,
                        enabled: !_awaiting,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'First name', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: TextField(
                        key: EmployeeCorrectionDialog.lastNameKey,
                        controller: _lastName,
                        enabled: !_awaiting,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'Last name', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: EmployeeCorrectionDialog.employmentTypeKey,
                  initialValue: _employmentType,
                  decoration:
                      const InputDecoration(labelText: 'Employment type', border: OutlineInputBorder()),
                  items: [
                    for (final type in employmentTypes)
                      DropdownMenuItem<String>(value: type, child: Text(employmentTypeLabel(type))),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) => setState(() => _employmentType = value ?? _employmentType),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeCorrectionDialog.workEmailKey,
                  controller: _workEmail,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Work email (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: EmployeeCorrectionDialog.failureKey,
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
            key: EmployeeCorrectionDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: EmployeeCorrectionDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
