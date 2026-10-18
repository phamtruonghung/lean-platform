/// Raising a Training record (issue #287, ADR-0043): the Org Unit it was given
/// at, a title, the day, how many hours it lasted, optionally who trained and
/// the objective. It starts as a draft; correcting and sending are later
/// slices (#288 adds the Trainees).
///
/// Every value with a known set is chosen, never typed (AGENTS.md §7,
/// ADR-0023): the Org Unit is browsed from the tree, the day comes from
/// `AppDateField`, and the trainer is an `AppSearchField` over the Directory —
/// a set nobody can scan. The submit button stays shut until the Org Unit, a
/// title, a day and a positive number of hours are all present. A server
/// refusal (403 outside the caller's Org Units, 404, 400) is rendered beside
/// the button with what was entered still in place.
///
/// Opened with `showDialog` and an explicit Bloc hand-off, as every dialog in
/// this Module is (`AttendanceRecordDialog.open`'s own pattern).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'employee.dart';
import 'org_unit.dart';
import 'org_unit_picker_bloc.dart';
import 'training_bloc.dart';

class TrainingRaiseDialog extends StatefulWidget {
  const TrainingRaiseDialog({super.key});

  static const ValueKey<String> siteKey = ValueKey<String>('training-raise-site');
  static const ValueKey<String> titleKey = ValueKey<String>('training-raise-title');
  static const ValueKey<String> trainedOnKey = ValueKey<String>('training-raise-trained-on');
  static const ValueKey<String> durationKey = ValueKey<String>('training-raise-duration');
  static const ValueKey<String> objectiveKey = ValueKey<String>('training-raise-objective');
  static const ValueKey<String> submitKey = ValueKey<String>('training-raise-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('training-raise-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('training-raise-failure');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('training-raise-expand-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('training-raise-org-unit-$id');

  /// The trainer picker's own name, which its `Key`s are derived from.
  static const String trainerFieldName = 'training-raise-trainer';
  static ValueKey<String> trainerFieldKey() => AppSearchField.fieldKey(trainerFieldName);
  static ValueKey<String> trainerSuggestionKey(String id) =>
      AppSearchField.suggestionKey(trainerFieldName, id);

  /// Opens the dialog over the register — handing across the register's own
  /// [TrainingBloc] (`showDialog`'s route sits outside the route-scoped
  /// provider) and giving the dialog an `OrgUnitPickerBloc` of its own.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<TrainingBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TrainingBloc>.value(
        value: bloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (context) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: const TrainingRaiseDialog(),
        ),
      ),
    );
  }

  @override
  State<TrainingRaiseDialog> createState() => _TrainingRaiseDialogState();
}

class _TrainingRaiseDialogState extends State<TrainingRaiseDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _objective = TextEditingController();

  String? _orgUnitId;
  String? _trainedOn;
  Employee? _trainer;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _objective.dispose();
    super.dispose();
  }

  double? get _hours {
    final hours = double.tryParse(_duration.text.trim());
    return hours != null && hours.isFinite && hours > 0 ? hours : null;
  }

  bool get _complete =>
      _orgUnitId != null && _title.text.trim().isNotEmpty && _trainedOn != null && _hours != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final objective = _objective.text.trim();
    context.read<TrainingBloc>().add(
          TrainingRaised(
            orgUnitId: _orgUnitId!,
            title: _title.text.trim(),
            trainedOn: _trainedOn!,
            durationHours: _hours!,
            trainerEmployeeId: _trainer?.id,
            objective: objective.isEmpty ? null : objective,
          ),
        );
  }

  void _onRegisterChanged(BuildContext context, TrainingState state) {
    if (!_awaiting || state.isRaising) return;
    if (state.raiseFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.raiseFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<TrainingBloc, TrainingState>(
      listener: _onRegisterChanged,
      child: AlertDialog(
        title: const Text('Raise training record'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: TrainingRaiseDialog.titleKey,
                  controller: _title,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    helperText: 'What the training was.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppDateField(
                  key: TrainingRaiseDialog.trainedOnKey,
                  name: 'training-raise-trained-on',
                  label: 'Trained on',
                  helperText: 'The day it was given.',
                  value: _trainedOn,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _trainedOn = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: TrainingRaiseDialog.durationKey,
                  controller: _duration,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Duration (hours)',
                    helperText: 'How long it lasted, e.g. 1.5.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppSearchField<Employee>(
                  name: TrainingRaiseDialog.trainerFieldName,
                  label: 'Trainer (optional)',
                  helperText: 'Who gave it, found in the Directory.',
                  value: _trainer,
                  enabled: !_awaiting,
                  onChanged: (employee) => setState(() => _trainer = employee),
                  onSelected: (employee) => setState(() => _trainer = employee),
                  fetchSuggestions: (term) async {
                    final token = context.read<AuthGateway>().currentAccessToken;
                    if (token == null) return const [];
                    return context.read<PeopleApi>().fetchEmployees(token, search: term, limit: 10);
                  },
                  suggestionBuilder: (context, employee) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                    child: Text(employee.displayName),
                  ),
                  idOf: (employee) => employee.id,
                  displayStringFor: (employee) => employee.displayName,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: TrainingRaiseDialog.objectiveKey,
                  controller: _objective,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Objective (optional)',
                    helperText: 'What the training set out to teach.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text('Where it was given', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                _OrgUnitPicker(
                  selectedId: _orgUnitId,
                  enabled: !_awaiting,
                  onSelected: (node) => setState(() => _orgUnitId = node.id),
                ),
                if (_failure != null)
                  Padding(
                    key: TrainingRaiseDialog.failureKey,
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
            key: TrainingRaiseDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: TrainingRaiseDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Raising…' : 'Raise training record'),
          ),
        ],
      ),
    );
  }
}

/// A single-select view over `OrgUnitPickerBloc`'s rows — the same shape
/// `EmployeeAssignmentDialog`'s destination picker takes (its header explains
/// why each caller draws its own view over the one shared Bloc).
class _OrgUnitPicker extends StatelessWidget {
  const _OrgUnitPicker({required this.selectedId, required this.enabled, required this.onSelected});

  final String? selectedId;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = _PickerMessage(
        message: state.sitesFailure!,
        onRetry: enabled ? () => bloc.add(const OrgUnitPickerStarted()) : null,
      );
    } else if (state.rootsFailure != null) {
      body = _PickerMessage(
        message: state.rootsFailure!,
        onRetry: enabled ? () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)) : null,
      );
    } else if (state.rows.isEmpty) {
      body = const _PickerMessage(message: 'Nothing to browse in this Site.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _OrgUnitPickerRow(
          row: state.rows[index],
          isSelected: state.rows[index].node.id == selectedId,
          enabled: enabled,
          onSelected: onSelected,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.sites.length > 1) ...[
          DropdownButtonFormField<String>(
            key: TrainingRaiseDialog.siteKey,
            initialValue: state.siteId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
            items: [
              for (final site in state.sites)
                DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
            ],
            onChanged: enabled
                ? (siteId) {
                    if (siteId == null) return;
                    bloc.add(OrgUnitPickerSiteSelected(siteId));
                  }
                : null,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.edge),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
        ),
      ],
    );
  }
}

class _OrgUnitPickerRow extends StatelessWidget {
  const _OrgUnitPickerRow({
    required this.row,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
  });

  final OrgUnitRow row;
  final bool isSelected;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm + row.depth * Spacing.lg, 0, Spacing.sm, 0),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: row.isLoadingChildren
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.sm),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: TrainingRaiseDialog.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                    onPressed: enabled
                        ? () => bloc.add(
                              row.isExpanded
                                  ? OrgUnitPickerCollapsed(row.node.id)
                                  : OrgUnitPickerExpanded(row.node.id),
                            )
                        : null,
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: TextButton(
              key: TrainingRaiseDialog.orgUnitKey(row.node.id),
              onPressed: enabled ? () => onSelected(row.node) : null,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(child: Text(row.node.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({this.message = '', this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Spacing.xs),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
