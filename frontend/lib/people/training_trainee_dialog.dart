/// Adding a Trainee to a Training record, draft or sent (issues #288 and #291, ADR-0043): one
/// Employee picked from the Directory. The picker is an `AppSearchField`
/// (AGENTS.md §7, ADR-0023) — the Directory is a set nobody can scan — and it
/// defaults to the record's own Org Unit's Employees, the common case, with a
/// segmented choice to reach any Employee in the Directory (a person from
/// another line who sat in is the point of some trainings). Changing the
/// choice starts the search over, so a pick is never one the new scope would
/// not have offered.
///
/// The submit button stays shut until an Employee is picked, and a failed
/// read blocks it too (the field reports no pick). A server refusal (403, 404,
/// or the 409s for a duplicate and a departed Employee) is
/// rendered inside the dialog, which stays open. Opened with `showDialog` and
/// an explicit Bloc hand-off, as every dialog in this Module is.
///
/// **Drawn in `AppDialog` (issue #394, ADR-0058)** at [AppDialogSize.picker]
/// (460) — the width the ADR names for "a list or filter to choose one thing
/// from", which is what this is — instead of the 520 it used to hand an
/// `AlertDialog` through a `SizedBox` inside its content. The shell's content
/// area is the only scroller, so the outer `SingleChildScrollView` is gone; the
/// segmented scope control, the picker, its `Key`s, the failure's copy and the
/// enable condition on Add are unchanged. The two action keys are the shell's
/// (`AppDialog.actionKey` of this dialog's own ids), the rename #398
/// established.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import 'employee.dart';
import 'training_detail_bloc.dart';

class TrainingTraineeDialog extends StatefulWidget {
  const TrainingTraineeDialog({super.key, required this.orgUnitId, required this.orgUnitName});

  /// The record's own Org Unit, whose Employees the picker offers first.
  final String orgUnitId;
  final String orgUnitName;

  static const ValueKey<String> scopeKey = ValueKey<String>('training-trainee-scope');

  /// The two actions, named through the dialog shell that now draws them.
  static final ValueKey<String> submitKey = AppDialog.actionKey(_submitId);
  static final ValueKey<String> cancelKey = AppDialog.actionKey(_cancelId);

  static const ValueKey<String> failureKey = ValueKey<String>('training-trainee-failure');

  /// The two choices of the scope control.
  static const ValueKey<String> orgUnitScopeKey = ValueKey<String>('training-trainee-scope-org-unit');
  static const ValueKey<String> directoryScopeKey = ValueKey<String>('training-trainee-scope-directory');

  static const String _submitId = 'training-trainee-submit';
  static const String _cancelId = 'training-trainee-cancel';

  /// The picker's own name, which its `Key`s are derived from.
  static const String employeeFieldName = 'training-trainee-employee';
  static ValueKey<String> employeeFieldKey() => AppSearchField.fieldKey(employeeFieldName);
  static ValueKey<String> employeeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(employeeFieldName, id);

  /// Opens the dialog over the record's Screen — handing across its own
  /// [TrainingDetailBloc], since `showDialog`'s route sits outside the
  /// route-scoped provider.
  static Future<void> open(BuildContext context, {required String orgUnitId, required String orgUnitName}) {
    final bloc = context.read<TrainingDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TrainingDetailBloc>.value(
        value: bloc,
        child: TrainingTraineeDialog(orgUnitId: orgUnitId, orgUnitName: orgUnitName),
      ),
    );
  }

  @override
  State<TrainingTraineeDialog> createState() => _TrainingTraineeDialogState();
}

class _TrainingTraineeDialogState extends State<TrainingTraineeDialog> {
  Employee? _employee;
  bool _wholeDirectory = false;
  bool _awaiting = false;
  String? _failure;

  void _submit() {
    final employee = _employee;
    if (employee == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<TrainingDetailBloc>().add(TrainingTraineeAdded(employee.id));
  }

  void _onRecordChanged(BuildContext context, TrainingDetailState state) {
    if (!_awaiting || state is! TrainingDetailLoaded || state.isWriting) return;
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
    final failure = _failure;
    return BlocListener<TrainingDetailBloc, TrainingDetailState>(
      listener: _onRecordChanged,
      child: AppDialog(
        title: 'Add Trainee',
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: TrainingTraineeDialog._cancelId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: TrainingTraineeDialog._submitId,
            label: _awaiting ? 'Adding…' : 'Add Trainee',
            onPressed: _employee != null && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              key: TrainingTraineeDialog.scopeKey,
              showSelectedIcon: false,
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(widget.orgUnitName, overflow: TextOverflow.ellipsis),
                  tooltip: 'Employees of ${widget.orgUnitName}',
                ),
                const ButtonSegment<bool>(value: true, label: Text('Whole Directory')),
              ],
              selected: {_wholeDirectory},
              onSelectionChanged: _awaiting
                  ? null
                  : (selection) => setState(() {
                        _wholeDirectory = selection.first;
                        _employee = null;
                        _failure = null;
                      }),
            ),
            const SizedBox(height: Spacing.md),
            // Keyed on the scope so a change starts a fresh search.
            KeyedSubtree(
              key: ValueKey<bool>(_wholeDirectory),
              child: AppSearchField<Employee>(
                name: TrainingTraineeDialog.employeeFieldName,
                label: 'Employee',
                helperText: _wholeDirectory
                    ? 'Anyone in the Directory, found by name or number.'
                    : 'An Employee of ${widget.orgUnitName}, found by name or number.',
                value: _employee,
                enabled: !_awaiting,
                onChanged: (employee) => setState(() => _employee = employee),
                onSelected: (employee) => setState(() {
                  _employee = employee;
                  _failure = null;
                }),
                fetchSuggestions: (term) async {
                  final token = context.read<AuthGateway>().currentAccessToken;
                  if (token == null) return const [];
                  return context.read<PeopleApi>().fetchEmployees(
                        token,
                        search: term,
                        orgUnitId: _wholeDirectory ? null : widget.orgUnitId,
                        limit: 10,
                      );
                },
                suggestionBuilder: (context, employee) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                  child: Text('${employee.displayName} · ${employee.employeeNo}'),
                ),
                idOf: (employee) => employee.id,
                displayStringFor: (employee) => employee.displayName,
                codeOf: (employee) => employee.employeeNo,
              ),
            ),
            if (failure != null)
              Padding(
                key: TrainingTraineeDialog.failureKey,
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
