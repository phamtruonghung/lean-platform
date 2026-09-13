/// Choosing which Employee an Account is linked to — the suggested one,
/// confirmed; a different one, found by searching the Directory; or none at
/// all (issue #116, ADR-0022). Shared by `AdmissionDialog` (where a
/// suggestion may already be waiting) and `AccountEmployeeDialog` (where an
/// existing link is being corrected) — the two differ only in what this
/// starts holding, never in how a choice is made.
///
/// A plain `StatefulWidget`, not a Bloc: unlike `OrgUnitPicker`, this reads
/// one flat list from one query (`GET /employees?search=`) and holds nothing
/// that needs to survive this dialog closing — the same proportion
/// `AdmissionDialog`'s own `_role`/`_failure` fields already keep for
/// dialog-local, ephemeral choices.
///
/// The Directory search is `AppSearchField` (issue #129, ADR-0023): typing
/// suggests matching Employees as the user goes, rather than making them
/// commit to a term and press a Search button to find out whether anyone
/// matches. Each suggestion names the Employee's job role and Org Unit
/// alongside their name, so two people sharing a name can be told apart —
/// the whole point of confirming an Account's Employee (ADR-0022); issue #91
/// made both unconditional on `listEmployees`'s own row, so no second fetch
/// is needed to show them. The fetch it issues always carries a `limit`
/// (issue #123) matching `AppSearchField`'s own 10-suggestion cap — asking
/// the server for more than this widget will ever render would only
/// transfer rows nobody sees.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import 'employee.dart';
import 'employee_ref.dart';

class EmployeeLinkPicker extends StatefulWidget {
  const EmployeeLinkPicker({
    super.key,
    this.suggestion,
    required this.initial,
    required this.onChanged,
    this.enabled = true,
  });

  /// The suggestion the Approval queue carried, if any (ADR-0022) — shown
  /// distinctly from an ordinary search result, so an administrator can tell
  /// "the Platform matched this by email" from "I searched and picked this".
  final EmployeeRef? suggestion;

  /// What is selected when this picker first builds — [suggestion] where the
  /// caller wants it pre-confirmed, an existing link where one is being
  /// corrected, or null for "no Employee".
  final EmployeeRef? initial;

  final ValueChanged<EmployeeRef?> onChanged;
  final bool enabled;

  /// The `name` this picker's own `AppSearchField` is seeded with — kept in
  /// one place so [searchFieldKey] and [resultKey] can never drift from what
  /// `build` actually renders (the same shape `SiteFormDialog` already uses
  /// for its own `AppSearchField`, issue #127).
  static const String _searchFieldName = 'employee-link';

  /// Kept as the accessor's existing name (issue #129) even though the
  /// control behind it changed from a bespoke `TextField` to `AppSearchField`
  /// — this now resolves to that field's own key rather than a bespoke one.
  static ValueKey<String> get searchFieldKey => AppSearchField.fieldKey(_searchFieldName);

  static const ValueKey<String> clearKey = ValueKey<String>('employee-link-clear');

  /// One suggestion row's own `Key`, keyed by the Employee's own id —
  /// `AppSearchField`'s `idOf` for this field is `Employee.id`.
  static ValueKey<String> resultKey(String employeeId) =>
      AppSearchField.suggestionKey(_searchFieldName, employeeId);

  @override
  State<EmployeeLinkPicker> createState() => _EmployeeLinkPickerState();
}

class _EmployeeLinkPickerState extends State<EmployeeLinkPicker> {
  late EmployeeRef? _selected = widget.initial;

  /// At most this many suggestions are ever asked for — `AppSearchField`
  /// itself never renders more than 10 of whatever a fetch returns (its own
  /// doc comment), so asking the server for more would only transfer rows
  /// nobody will ever see.
  static const int _suggestionLimit = 10;

  Future<List<Employee>> _fetchSuggestions(String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      throw PeopleApiException('Not signed in.');
    }
    return context.read<PeopleApi>().fetchEmployees(
          token,
          search: term,
          limit: _suggestionLimit,
        );
  }

  void _select(EmployeeRef? employee) {
    setState(() => _selected = employee);
    widget.onChanged(employee);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Employee', style: theme.textTheme.labelLarge),
        const SizedBox(height: Spacing.xs),
        if (_selected != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.suggestion != null && widget.suggestion!.id == _selected!.id
                      ? 'Suggested match: ${_selected!.label}'
                      : 'Linked to: ${_selected!.label}',
                ),
              ),
              TextButton(
                key: EmployeeLinkPicker.clearKey,
                onPressed: widget.enabled ? () => _select(null) : null,
                child: const Text('Remove'),
              ),
            ],
          )
        else
          Text('No Employee will be linked.', style: muted),
        const SizedBox(height: Spacing.sm),
        AppSearchField<Employee>(
          name: EmployeeLinkPicker._searchFieldName,
          label: 'Search the Directory',
          enabled: widget.enabled,
          // Never fed a confirmed Employee back in: the choice already made
          // is shown above, in the "Linked to"/"Suggested match" line, not
          // echoed into the search box itself — the same reason the old
          // `TextField` cleared on a pick rather than displaying it.
          value: null,
          // This picker never surfaces a failed-fetch "value" of its own —
          // `_selected` already tracks the real choice via `onSelected`
          // below, and a failed fetch here has nothing to unset.
          onChanged: (_) {},
          onSelected: (employee) => _select(
            EmployeeRef(
              id: employee.id,
              employeeNo: employee.employeeNo,
              displayName: employee.displayName,
            ),
          ),
          fetchSuggestions: _fetchSuggestions,
          suggestionBuilder: (context, employee) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${employee.employeeNo} · ${employee.displayName}'),
                Text(
                  '${employee.jobRoleName ?? 'No job role'}'
                  '${employee.orgUnitName == null ? '' : ' · ${employee.orgUnitName}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          idOf: (employee) => employee.id,
          displayStringFor: (employee) => '${employee.employeeNo} · ${employee.displayName}',
        ),
      ],
    );
  }
}
