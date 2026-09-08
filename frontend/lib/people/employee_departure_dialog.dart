/// Recording that an Employee has departed (issue #87): a flag and the date
/// it took effect, never a deletion — CONTEXT.md's own Departed entry, and
/// the reason this dialog reads "has left", never "delete" or "remove".
///
/// The date is optional, mirroring `setEmployeeDeparted`'s own default
/// (directory.js): left blank, the server records today.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'employee.dart';
import 'employee_detail_bloc.dart';

class EmployeeDepartureDialog extends StatefulWidget {
  const EmployeeDepartureDialog({super.key, required this.employee});

  final EmployeeDetail employee;

  static const ValueKey<String> terminatedOnKey = ValueKey<String>('employee-departure-terminated-on');
  static const ValueKey<String> submitKey = ValueKey<String>('employee-departure-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('employee-departure-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-departure-failure');

  /// Opens the dialog over the detail Screen — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context, EmployeeDetail employee) {
    final bloc = context.read<EmployeeDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<EmployeeDetailBloc>.value(
        value: bloc,
        child: EmployeeDepartureDialog(employee: employee),
      ),
    );
  }

  @override
  State<EmployeeDepartureDialog> createState() => _EmployeeDepartureDialogState();
}

class _EmployeeDepartureDialogState extends State<EmployeeDepartureDialog> {
  final TextEditingController _terminatedOn = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _terminatedOn.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final terminatedOn = _terminatedOn.text.trim();
    context.read<EmployeeDetailBloc>().add(
          EmployeeDetailDepartureConfirmed(terminatedOn: terminatedOn.isEmpty ? null : terminatedOn),
        );
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
        title: Text('Record that ${widget.employee.displayName} has left'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'The record stays — nothing is deleted, and this can be undone by '
                  'reinstating the record at any time.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeDepartureDialog.terminatedOnKey,
                  controller: _terminatedOn,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Effective date (optional)',
                    helperText: 'YYYY-MM-DD. Left blank, today is recorded.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: EmployeeDepartureDialog.failureKey,
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
            key: EmployeeDepartureDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: EmployeeDepartureDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Recording…' : 'Record departure'),
          ),
        ],
      ),
    );
  }
}
