/// The Employee directory (issue #86, CONTEXT.md's Directory entry): who
/// works here, searched, filtered by Org Unit and by job role, Departed
/// Employees excluded by default.
///
/// Offered to every approved Account (AC1) — unlike Assets or Work orders,
/// there is no role gate on this Screen or its destination: ADR-0009 is
/// exactly the decision that a plant directory is not a secret.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/skeleton_list.dart';
import 'directory_bloc.dart';
import 'directory_org_unit_filter_dialog.dart';
import 'employee.dart';
import 'employee_form_dialog.dart';

class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key, required this.isAdmin});

  /// Whether this caller may add an Employee (issue #87) — read off `/me`'s
  /// own role, the same shape `AssetsScreen.canPlaceAnAsset` follows, except
  /// this is a role gate rather than a Grant one: the four write routes are
  /// `requireAdmin`, not Org-Unit-scoped (ADR-0009). False hides the "Add
  /// Employee" affordance entirely, the same reasoning `canPlaceAnAsset`
  /// gives for hiding rather than disabling.
  final bool isAdmin;

  static const double maxWidth = 900;

  /// The `name` the Directory's own `AppSearchField` is seeded with (issue
  /// #128) — kept in one place so [searchFieldKey] and [searchSuggestionKey]
  /// can never drift from what `_Header.build` actually renders, the same
  /// device `SiteFormDialog._timezoneFieldName` uses (issue #127).
  static const String _searchFieldName = 'directory-search';

  /// How many suggestions a fetch asks for (issue #123's own `limit`) —
  /// matches `AppSearchField`'s own cap on rendered rows (issue #125), so
  /// nothing beyond what could ever be shown is pulled over the wire.
  static const int _suggestionLimit = 10;

  static const ValueKey<String> addKey = ValueKey<String>('directory-add');

  /// Kept as the accessor's existing name (issue #128) even though the
  /// control behind it changed from a `TextField` to `AppSearchField` — this
  /// now resolves to that field's own key rather than a bespoke one, the same
  /// change `SiteFormDialog.timezoneKey` made for issue #127.
  static ValueKey<String> get searchFieldKey => AppSearchField.fieldKey(_searchFieldName);

  /// One search suggestion row's own `Key`, keyed by the Employee's own id.
  static ValueKey<String> searchSuggestionKey(String employeeId) =>
      AppSearchField.suggestionKey(_searchFieldName, employeeId);

  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('directory-org-unit-filter');
  static const ValueKey<String> jobRoleFilterKey = ValueKey<String>('directory-job-role-filter');
  static const ValueKey<String> includeDepartedKey = ValueKey<String>('directory-include-departed');
  static const ValueKey<String> myRecordKey = ValueKey<String>('directory-my-record');
  static const ValueKey<String> emptyKey = ValueKey<String>('directory-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('directory-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('directory-retry');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('directory-row-$id');
  static ValueKey<String> departedChipKey(String id) => ValueKey<String>('directory-departed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DirectoryBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, isAdmin: isAdmin),
          Expanded(
            child: switch (state) {
              DirectoryLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
              DirectoryUnavailable(message: final message) => _DirectoryFailed(message: message),
              DirectoryLoaded(isLoadingList: true) => const SkeletonList(rows: 5, maxWidth: maxWidth),
              DirectoryLoaded(employees: final employees) when employees.isEmpty => const _DirectoryEmpty(),
              DirectoryLoaded(employees: final employees) => _DirectoryList(employees: employees),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.state, required this.isAdmin});

  final DirectoryState state;
  final bool isAdmin;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  /// A dumb fetch, per `AppSearchField`'s own contract (issue #125): the
  /// widget itself owns the 300ms debounce and the 2-character minimum, so
  /// this issues one request per term it is actually asked for and nothing
  /// more. Throwing (rather than returning an empty list) on a signed-out
  /// session is what lets `AppSearchField` show `PlatformFailureState`
  /// instead of a suggestion list quietly going empty for a reason it never
  /// reports.
  Future<List<Employee>> _fetchSuggestions(String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      throw PeopleApiException(DirectoryBloc.signedOutMessage);
    }
    return context.read<PeopleApi>().fetchEmployees(
          token,
          search: term,
          limit: DirectoryScreen._suggestionLimit,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = widget.state is DirectoryLoaded ? widget.state as DirectoryLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DirectoryScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and subtitle on their own full-width row, not squeezed
              // beside the action buttons: with two of them now offered to an
              // administrator (issue #87's own "Add Employee", alongside "My
              // record"), an `Expanded` column sharing a `Row` with both would
              // be forced so narrow that "Directory" itself wraps character by
              // character, ballooning this header's own height and starving
              // whatever the body below has left — exactly the failure mode
              // the buttons now live in their own `Wrap` beneath this to avoid.
              Text('Directory', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'Who works here — searched, filtered, and Departed Employees kept '
                'out of sight until asked for.',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  if (widget.isAdmin)
                    FilledButton.icon(
                      key: DirectoryScreen.addKey,
                      onPressed: loaded != null && loaded.isAdding
                          ? null
                          : () => EmployeeFormDialog.open(context),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add Employee'),
                    ),
                  OutlinedButton.icon(
                    key: DirectoryScreen.myRecordKey,
                    onPressed: () => context.go('${Routes.directory}/me'),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('My record'),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              // As-you-type suggestions (issue #128, ADR-0023 point 5) sit
              // alongside the list filter below, not in place of it: picking
              // a suggestion navigates straight to that Employee
              // (`onSelected`), while pressing Enter without picking one
              // still narrows the list underneath exactly as it always has
              // (`onSubmitted` → `DirectorySearchChanged`) — "show me
              // everyone called Nguyen" is a real thing to want, and is not
              // the same as jumping to one person (this ticket's own "Why").
              AppSearchField<Employee>(
                name: DirectoryScreen._searchFieldName,
                label: 'Search by name',
                // No confirmed selection to seed or track here — unlike
                // `SiteFormDialog`'s timezone field, a pick here navigates
                // away rather than settling into this field, so there is
                // never a chosen Employee this field itself needs to display.
                value: null,
                onChanged: (_) {},
                onSelected: (employee) => context.go('${Routes.directory}/${employee.id}'),
                fetchSuggestions: _fetchSuggestions,
                suggestionBuilder: (context, employee) {
                  final theme = Theme.of(context);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(employee.displayName),
                        Text(
                          _employeeSubtitle(employee),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
                idOf: (employee) => employee.id,
                displayStringFor: (employee) => employee.displayName,
                onSubmitted: (value) =>
                    context.read<DirectoryBloc>().add(DirectorySearchChanged(value)),
              ),
              if (loaded != null) ...[
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: DirectoryScreen.orgUnitFilterKey,
                      onPressed: () => DirectoryOrgUnitFilterDialog.open(context),
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: Text(loaded.orgUnitName ?? 'All Org Units'),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        key: DirectoryScreen.jobRoleFilterKey,
                        initialValue: loaded.jobRoleId,
                        isDense: true,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Job role', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('All job roles')),
                          for (final jobRole in loaded.jobRoles)
                            DropdownMenuItem<String>(value: jobRole.id, child: Text(jobRole.name)),
                        ],
                        onChanged: (jobRoleId) => context
                            .read<DirectoryBloc>()
                            .add(DirectoryJobRoleFilterChanged(jobRoleId)),
                      ),
                    ),
                    FilterChip(
                      key: DirectoryScreen.includeDepartedKey,
                      label: const Text('Include Departed'),
                      selected: loaded.includeDeparted,
                      onSelected: (value) =>
                          context.read<DirectoryBloc>().add(DirectoryIncludeDepartedChanged(value)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The job role and Org Unit line shown beneath an Employee's name — shared
/// by `_EmployeeRow` (the listing) and `_HeaderState`'s own search
/// suggestion row (issue #128), so the two can never phrase the same fact
/// differently. A missing job role reads as "No job role", never a blank the
/// reader has to interpret (issue #91's own criterion); the Org Unit is
/// appended only when there is one to name at all — directory.js's own
/// fallback rule means it is usually there even with no current Assignment,
/// but not always (neither a current Assignment nor a `defaultOrgUnitId`).
String _employeeSubtitle(Employee employee) => employee.orgUnitName == null
    ? (employee.jobRoleName ?? 'No job role')
    : '${employee.jobRoleName ?? 'No job role'} · ${employee.orgUnitName}';

class _DirectoryList extends StatelessWidget {
  const _DirectoryList({required this.employees});

  final List<Employee> employees;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DirectoryScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: employees.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _EmployeeRow(employee: employees[index]),
        ),
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: DirectoryScreen.rowKey(employee.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.go('${Routes.directory}/${employee.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.person_outline, size: 20),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            employee.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!employee.isActive) ...[
                          const SizedBox(width: Spacing.sm),
                          Chip(
                            key: DirectoryScreen.departedChipKey(employee.id),
                            label: const Text('Departed'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: theme.colorScheme.errorContainer,
                            labelStyle: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${employee.employeeNo} · ${employee.employmentType}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      _employeeSubtitle(employee),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryEmpty extends StatelessWidget {
  const _DirectoryEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: DirectoryScreen.emptyKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('Nobody matches this search', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Try a different name, or clear a filter.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryFailed extends StatelessWidget {
  const _DirectoryFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: DirectoryScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The Directory could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: DirectoryScreen.retryKey,
                onPressed: () => context.read<DirectoryBloc>().add(const DirectoryStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
