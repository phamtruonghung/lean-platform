/// Raising a Concern: what was found, what kind of Action it is, where it was
/// found, who owns it and by when (issue #176).
///
/// Addressed rather than popped — `/actions/new` (ADR-0021) — so a refresh
/// lands on the register with the form open, and a widget test drives it
/// through the router the way `work_orders_test.dart` drives its own dialogs.
///
/// Two pickers are built here and neither outlives the dialog:
/// `OrgUnitPickerBloc` for where it was found, and `AppSearchField` over
/// People's Employee directory for the optional owner. Both are the shared
/// shapes ADR-0023 settles: a value with a known set is chosen from what the
/// server offers, never typed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'action.dart';
import 'actions_api.dart';
import 'actions_bloc.dart';

class ActionFormDialog extends StatefulWidget {
  const ActionFormDialog({super.key, required this.siteId});

  /// The Site the register is showing. The Org Unit chooser opens on it, and
  /// the raise itself is sent to it.
  final String siteId;

  static const ValueKey<String> titleKey = ValueKey<String>('action-form-title');
  static const ValueKey<String> descriptionKey = ValueKey<String>('action-form-description');
  static const ValueKey<String> typeKey = ValueKey<String>('action-form-type');
  static const ValueKey<String> pillarKey = ValueKey<String>('action-form-pillar');
  static const ValueKey<String> ownerKey = ValueKey<String>('action-form-owner');
  static const ValueKey<String> dueDateKey = ValueKey<String>('action-form-due-date');
  static const ValueKey<String> priorityKey = ValueKey<String>('action-form-priority');
  static const ValueKey<String> submitKey = ValueKey<String>('action-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('action-form-failure');
  static const ValueKey<String> chosenKey = ValueKey<String>('action-form-chosen');

  @override
  State<ActionFormDialog> createState() => _ActionFormDialogState();
}

class _ActionFormDialogState extends State<ActionFormDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// The kind of Action, defaulted to the concern itself: a row with no type
  /// is the thing found wrong, which is what a person raising one has.
  ActionType _type = ActionType.concern;

  /// Null until chosen — `action_items.priority`'s own DEFAULT is 3, and the
  /// form shows that as the selected value rather than as an absence.
  int _priority = 3;

  String? _pillarCode;
  List<Pillar> _pillars = const [];
  bool _pillarsFailed = false;

  Employee? _owner;
  OrgUnitNode? _orgUnit;
  String? _dueDate;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadPillars();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadPillars() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() => _pillarsFailed = true);
      return;
    }
    try {
      final pillars = await context.read<ActionsApi>().fetchPillars(token);
      if (!mounted) return;
      setState(() {
        _pillars = pillars;
        _pillarsFailed = false;
      });
    } on ActionsApiException {
      if (!mounted) return;
      // The Pillar is optional, so a failed catalogue blocks nothing: the
      // control says it could not be read rather than offering a typed
      // alternative (ADR-0023).
      setState(() => _pillarsFailed = true);
    }
  }

  bool get _complete => _title.text.trim().isNotEmpty && _orgUnit != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ActionsBloc>().add(
          ActionRaiseConfirmed(
            orgUnitId: _orgUnit!.id,
            title: _title.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            actionType: _type.wire,
            pillarCode: _pillarCode,
            ownerEmployeeId: _owner?.id,
            dueDate: _dueDate,
            priority: _priority,
          ),
        );
  }

  void _onActionsChanged(BuildContext context, ActionsState state) {
    if (!_awaiting || state is! ActionsLoaded || state.isRaising) return;
    if (state.raiseFailure != null) {
      // The refusal stays inside the dialog with the values still in it, so a
      // caller fixes the one thing that was wrong rather than retyping the
      // whole concern.
      setState(() {
        _awaiting = false;
        _failure = state.raiseFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  // A chosen Org Unit belongs to the Site it was chosen in, so switching the
  // chooser's Site necessarily discards it.
  void _onOrgUnitSiteChanged(OrgUnitPickerState state) {
    setState(() => _orgUnit = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<ActionsBloc, ActionsState>(
      listener: _onActionsChanged,
      child: BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
        listenWhen: (previous, current) => previous.siteId != current.siteId,
        listener: (context, state) => _onOrgUnitSiteChanged(state),
        child: AlertDialog(
          title: const Text('Raise a concern'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: ActionFormDialog.titleKey,
                    controller: _title,
                    enabled: !_awaiting,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'What was found',
                      helperText: 'One line. The cause goes in the Plan phase, not here.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: ActionFormDialog.descriptionKey,
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ActionType>(
                          key: ActionFormDialog.typeKey,
                          initialValue: _type,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Kind of Action',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final type in ActionType.values)
                              DropdownMenuItem<ActionType>(value: type, child: Text(type.label)),
                          ],
                          onChanged:
                              _awaiting ? null : (value) => setState(() => _type = value ?? _type),
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ActionFormDialog.priorityKey,
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
                          onChanged: _awaiting
                              ? null
                              : (value) => setState(() => _priority = value ?? _priority),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  if (_pillarsFailed)
                    Text(
                      'The Pillar catalogue could not be read, so no Pillar can be chosen.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ActionFormDialog.pillarKey,
                      initialValue: _pillarCode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Pillar (optional)',
                        helperText: 'Which SQDCP number does this threaten?',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('No Pillar')),
                        for (final pillar in _pillars)
                          DropdownMenuItem<String?>(
                            value: pillar.code,
                            child: Text('${pillar.name} (${pillar.code})'),
                          ),
                      ],
                      onChanged: _awaiting
                          ? null
                          : (value) => setState(() => _pillarCode = value),
                    ),
                  const SizedBox(height: Spacing.md),
                  AppSearchField<Employee>(
                    key: ActionFormDialog.ownerKey,
                    name: 'action-owner',
                    label: 'Owner (optional)',
                    helperText: 'Who will do it. An Action nobody owns is visibly nobody\'s.',
                    value: _owner,
                    enabled: !_awaiting,
                    // The field reports the record it now stands for, picked or
                    // cleared — the same contract `SiteFormDialog`'s own
                    // timezone field keeps, so the form's own value and the
                    // field's display cannot disagree.
                    onChanged: (employee) => setState(() => _owner = employee),
                    fetchSuggestions: (term) async {
                      final token = context.read<AuthGateway>().currentAccessToken;
                      if (token == null) return const [];
                      return context.read<PeopleApi>().fetchEmployees(token, search: term);
                    },
                    suggestionBuilder: (context, employee) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(employee.displayName),
                    ),
                    idOf: (employee) => employee.id,
                    displayStringFor: (employee) => employee.displayName,
                    onSelected: (employee) => setState(() => _owner = employee),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateField(
                    key: ActionFormDialog.dueDateKey,
                    name: 'action-due-date',
                    label: 'Due (optional)',
                    value: _dueDate,
                    optional: true,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _dueDate = value),
                  ),
                  const SizedBox(height: Spacing.lg),
                  OrgUnitChooser(
                    selectedId: _orgUnit?.id,
                    enabled: !_awaiting,
                    showSitePicker: false,
                    title: 'Where it was found',
                    description: 'Choose the Org Unit this concern is about. This is what decides '
                        'who may act on it.',
                    onSelected: (node) => setState(() => _orgUnit = node),
                  ),
                  if (_orgUnit != null)
                    Padding(
                      key: ActionFormDialog.chosenKey,
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        'This concern will be recorded at ${_orgUnit!.name}.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (_failure != null)
                    Padding(
                      key: ActionFormDialog.failureKey,
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
              key: ActionFormDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: ActionFormDialog.submitKey,
              onPressed: _complete && !_awaiting ? _submit : null,
              child: const Text('Raise it'),
            ),
          ],
        ),
      ),
    );
  }
}
