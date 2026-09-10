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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
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

  static const ValueKey<String> searchFieldKey = ValueKey<String>('employee-link-search');
  static const ValueKey<String> searchButtonKey = ValueKey<String>('employee-link-search-button');
  static const ValueKey<String> clearKey = ValueKey<String>('employee-link-clear');
  static const ValueKey<String> searchFailureKey = ValueKey<String>('employee-link-search-failure');
  static const ValueKey<String> noResultsKey = ValueKey<String>('employee-link-no-results');
  static ValueKey<String> resultKey(String employeeId) =>
      ValueKey<String>('employee-link-result-$employeeId');

  @override
  State<EmployeeLinkPicker> createState() => _EmployeeLinkPickerState();
}

class _EmployeeLinkPickerState extends State<EmployeeLinkPicker> {
  late EmployeeRef? _selected = widget.initial;
  final TextEditingController _searchController = TextEditingController();
  List<EmployeeRef> _results = const [];
  bool _searched = false;
  bool _searching = false;
  String? _searchFailure;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final search = _searchController.text.trim();
    if (search.isEmpty || !widget.enabled) return;
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) return;
    setState(() {
      _searching = true;
      _searchFailure = null;
    });
    try {
      final employees = await context.read<PeopleApi>().fetchEmployees(token, search: search);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _results = [
          for (final employee in employees)
            EmployeeRef(id: employee.id, employeeNo: employee.employeeNo, displayName: employee.displayName),
        ];
      });
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchFailure = error.message;
      });
    }
  }

  void _select(EmployeeRef? employee) {
    setState(() {
      _selected = employee;
      _results = const [];
      _searched = false;
      _searchController.clear();
    });
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
        Row(
          children: [
            Expanded(
              child: TextField(
                key: EmployeeLinkPicker.searchFieldKey,
                controller: _searchController,
                enabled: widget.enabled,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search the Directory',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              key: EmployeeLinkPicker.searchButtonKey,
              onPressed: widget.enabled && !_searching ? _search : null,
              child: const Text('Search'),
            ),
          ],
        ),
        if (_searchFailure != null)
          Padding(
            key: EmployeeLinkPicker.searchFailureKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(_searchFailure!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        if (_searched && _results.isEmpty)
          Padding(
            key: EmployeeLinkPicker.noResultsKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text('Nobody matches this search', style: muted),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final result in _results)
                  ListTile(
                    key: EmployeeLinkPicker.resultKey(result.id),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(result.label),
                    onTap: widget.enabled ? () => _select(result) : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
