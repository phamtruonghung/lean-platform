/// Raising a measure against the Concern it answers (issue #178).
///
/// Addressed rather than popped —
/// `${Routes.actions}/:id/measures/:measureType/new` (ADR-0021) — so a refresh
/// lands on the Concern with the form open.
///
/// The kind is fixed by the address and shown, never chosen inside the form:
/// the three words mean three different pieces of work, and a picker in the
/// middle of a form invites the wrong one. What a caller can choose here is
/// everything a *measure* has — where its work happens, who does it and by when
/// — and nothing about what it is.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

class ActionMeasureDialog extends StatefulWidget {
  const ActionMeasureDialog({super.key, required this.concern, required this.measureType});

  /// The Concern this measure answers.
  final Action concern;

  /// `containment`, `countermeasure` or `preventive` — fixed by the address.
  final String measureType;

  static const ValueKey<String> titleKey = ValueKey<String>('action-measure-title');
  static const ValueKey<String> descriptionKey = ValueKey<String>('action-measure-description');
  static const ValueKey<String> ownerKey = ValueKey<String>('action-measure-owner');
  static const ValueKey<String> dueDateKey = ValueKey<String>('action-measure-due-date');
  static const ValueKey<String> priorityKey = ValueKey<String>('action-measure-priority');
  static const ValueKey<String> submitKey = ValueKey<String>('action-measure-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-measure-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('action-measure-failure');

  /// The address's own guards: the detail read has not answered yet, and the
  /// kind in the address is not one of the three (issue #178).
  static const ValueKey<String> loadingKey = ValueKey<String>('action-measure-loading');
  static const ValueKey<String> unknownKindKey = ValueKey<String>('action-measure-unknown-kind');

  @override
  State<ActionMeasureDialog> createState() => _ActionMeasureDialogState();
}

class _ActionMeasureDialogState extends State<ActionMeasureDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  int _priority = 3;
  Employee? _owner;
  OrgUnitNode? _orgUnit;
  String? _dueDate;
  bool _awaiting = false;
  String? _failure;

  String get _label => actionTypeLabel(widget.measureType);
  bool get _complete => _title.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ActionDetailBloc>().add(
          ActionMeasureRaised(
            concernId: widget.concern.id,
            actionType: widget.measureType,
            title: _title.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            orgUnitId: _orgUnit?.id,
            ownerEmployeeId: _owner?.id,
            dueDate: _dueDate,
            priority: _priority,
          ),
        );
  }

  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (!_awaiting || state is! ActionDetailLoaded || state.isAddingMeasure) return;
    if (state.measureFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.measureFailure;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Add a ${_label.toLowerCase()}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Answering ${widget.concern.actionNo}: ${widget.concern.title}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  switch (widget.measureType) {
                    'containment' => 'What stops its effect now. This is work done before the cause '
                        'is known — which is the point of it.',
                    'countermeasure' => 'What removes the cause. Recorded once the cause is known, '
                        'and what the Concern cannot close without.',
                    _ => 'What stops the same failure appearing somewhere else.',
                  },
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ActionMeasureDialog.titleKey,
                  controller: _title,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'What will be done',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ActionMeasureDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Detail (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppSearchField<Employee>(
                  key: ActionMeasureDialog.ownerKey,
                  name: 'action-measure-owner',
                  label: 'Owner (optional)',
                  helperText: 'Who will do it.',
                  value: _owner,
                  enabled: !_awaiting,
                  onChanged: (employee) => setState(() => _owner = employee),
                  fetchSuggestions: (term) async {
                    final token = context.read<AuthGateway>().currentAccessToken;
                    if (token == null) return const [];
                    return context.read<PeopleApi>().fetchEmployees(token, search: term);
                  },
                  suggestionBuilder: (context, employee) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                    child: Text(employee.displayName),
                  ),
                  idOf: (employee) => employee.id,
                  displayStringFor: (employee) => employee.displayName,
                  onSelected: (employee) => setState(() => _owner = employee),
                ),
                const SizedBox(height: Spacing.md),
                AppDateField(
                  key: ActionMeasureDialog.dueDateKey,
                  name: 'action-measure-due',
                  label: 'Due (optional)',
                  value: _dueDate,
                  optional: true,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _dueDate = value),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<int>(
                  key: ActionMeasureDialog.priorityKey,
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in actionPriorityLabels.entries)
                      DropdownMenuItem<int>(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged:
                      _awaiting ? null : (value) => setState(() => _priority = value ?? _priority),
                ),
                const SizedBox(height: Spacing.lg),
                OrgUnitChooser(
                  selectedId: _orgUnit?.id,
                  enabled: !_awaiting,
                  showSitePicker: false,
                  title: 'Where this work happens',
                  description: 'Leave it alone to record the measure at ${widget.concern.orgUnitName}, '
                      'where the concern sits. A fix that belongs somewhere else — a store, a '
                      'supplier — can name that instead.',
                  onSelected: (node) => setState(() => _orgUnit = node),
                ),
                if (_failure != null)
                  Padding(
                    key: ActionMeasureDialog.failureKey,
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
            key: ActionMeasureDialog.cancelKey,
            onPressed: _awaiting ? null : () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ActionMeasureDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text('Add the ${_label.toLowerCase()}'),
          ),
        ],
      ),
    );
  }
}
