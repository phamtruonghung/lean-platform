/// Booking an Employee's time against a Work order (issue #75): a window and
/// a kind of activity.
///
/// The window is the only input that decides the hours — this dialog sends no
/// `hours`, because the server's column is generated from the window and a
/// client figure would only be able to disagree with it. Overtime is its own
/// checkbox rather than a second booking kind, so it is recorded
/// distinguishably from ordinary hours without splitting the window.
///
/// All five activities are offered rather than defaulting every booking to
/// `work`: the schema's own comment is why (`waiting` and `travel` are worth
/// separating from wrench time).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class LabourBookingDialog extends StatefulWidget {
  const LabourBookingDialog({super.key, required this.workOrderId});

  final String workOrderId;

  static const ValueKey<String> employeeKey = ValueKey<String>('labour-booking-employee');
  static const ValueKey<String> employeesFailedKey = ValueKey<String>('labour-booking-employees-failed');
  static const ValueKey<String> activityKey = ValueKey<String>('labour-booking-activity');
  static const ValueKey<String> overtimeKey = ValueKey<String>('labour-booking-overtime');
  static const ValueKey<String> noteKey = ValueKey<String>('labour-booking-note');
  static const ValueKey<String> submitKey = ValueKey<String>('labour-booking-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('labour-booking-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('labour-booking-failure');

  @override
  State<LabourBookingDialog> createState() => _LabourBookingDialogState();
}

enum _EmployeesStatus { loading, ready, failed }

class _LabourBookingDialogState extends State<LabourBookingDialog> {
  final TextEditingController _note = TextEditingController();

  _EmployeesStatus _employeesStatus = _EmployeesStatus.loading;
  List<Employee> _employees = const [];
  String? _employeesFailure;

  /// Null until chosen — never defaulted, so "an Employee was chosen" is only
  /// true once somebody chose one.
  String? _employeeId;

  /// Null until chosen — every activity is offered, none silently defaulted.
  String? _activity;

  /// A window the caller can adjust. Defaulted rather than blank because the
  /// hours follow from it and a booking with no window has none; this is the
  /// last hour, which is the common case for a technician finishing a job.
  late DateTime _startedAt = DateTime.now().subtract(const Duration(hours: 1));
  late DateTime _endedAt = DateTime.now();

  bool _isOvertime = false;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _employeesStatus = _EmployeesStatus.loading;
      _employeesFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _employeesStatus = _EmployeesStatus.failed;
        _employeesFailure = WorkOrderDetailBloc.signedOutMessage;
      });
      return;
    }
    try {
      final employees = await context.read<PeopleApi>().fetchEmployees(token);
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _employeesStatus = _EmployeesStatus.ready;
      });
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _employeesStatus = _EmployeesStatus.failed;
        _employeesFailure = error.message;
      });
    }
  }

  bool get _complete =>
      _employeeId != null &&
      _activity != null &&
      !_endedAt.isBefore(_startedAt);

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    context.read<WorkOrderDetailBloc>().add(
          WorkOrderLabourBookingConfirmed(
            employeeId: _employeeId!,
            startedAt: _startedAt,
            endedAt: _endedAt,
            activity: _activity!,
            isOvertime: _isOvertime,
            note: note.isEmpty ? null : note,
          ),
        );
  }

  void _onChanged(BuildContext context, WorkOrderDetailState state) {
    if (!_awaiting || state is! WorkOrderDetailLoaded || state.isBooking) return;
    if (state.bookingFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.bookingFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<WorkOrderDetailBloc, WorkOrderDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Book labour'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _EmployeeField(
                  status: _employeesStatus,
                  employees: _employees,
                  failure: _employeesFailure,
                  selectedId: _employeeId,
                  enabled: !_awaiting,
                  onRetry: _loadEmployees,
                  onChanged: (id) => setState(() => _employeeId = id),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: LabourBookingDialog.activityKey,
                  initialValue: _activity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Activity',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final activity in LabourActivity.values)
                      DropdownMenuItem<String>(value: activity.wire, child: Text(activity.label)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _activity = value),
                ),
                const SizedBox(height: Spacing.md),
                AppDateTimeField(
                  name: 'labour-started-at',
                  label: 'Started at',
                  value: _startedAt,
                  enabled: !_awaiting,
                  onChanged: (value) {
                    if (value != null) setState(() => _startedAt = value);
                  },
                ),
                const SizedBox(height: Spacing.md),
                AppDateTimeField(
                  name: 'labour-ended-at',
                  label: 'Ended at',
                  value: _endedAt,
                  enabled: !_awaiting,
                  onChanged: (value) {
                    if (value != null) setState(() => _endedAt = value);
                  },
                ),
                const SizedBox(height: Spacing.sm),
                CheckboxListTile(
                  key: LabourBookingDialog.overtimeKey,
                  value: _isOvertime,
                  onChanged: _awaiting ? null : (value) => setState(() => _isOvertime = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Overtime'),
                ),
                TextField(
                  key: LabourBookingDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: LabourBookingDialog.failureKey,
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
            key: LabourBookingDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: LabourBookingDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Book labour'),
          ),
        ],
      ),
    );
  }
}

class _EmployeeField extends StatelessWidget {
  const _EmployeeField({
    required this.status,
    required this.employees,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _EmployeesStatus status;
  final List<Employee> employees;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _EmployeesStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _EmployeesStatus.failed:
        return Column(
          key: LabourBookingDialog.employeesFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Employees could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _EmployeesStatus.ready:
        return DropdownButtonFormField<String>(
          key: LabourBookingDialog.employeeKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder()),
          items: [
            for (final employee in employees)
              DropdownMenuItem<String>(
                value: employee.id,
                child: Text(employee.displayName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        );
    }
  }
}
