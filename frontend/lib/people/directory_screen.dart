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

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'directory_bloc.dart';
import 'directory_org_unit_filter_dialog.dart';
import 'employee.dart';

class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key});

  static const double maxWidth = 900;

  static const ValueKey<String> searchFieldKey = ValueKey<String>('directory-search');
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
          _Header(state: state),
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
  const _Header({required this.state});

  final DirectoryState state;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state is DirectoryLoaded ? (widget.state as DirectoryLoaded).search : '',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Directory', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Who works here — searched, filtered, and Departed Employees kept '
                          'out of sight until asked for.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
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
              TextField(
                key: DirectoryScreen.searchFieldKey,
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search by name',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
                ),
                onSubmitted: (value) =>
                    context.read<DirectoryBloc>().add(DirectorySearchChanged(value.trim())),
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
                            labelStyle: theme.textTheme.labelSmall
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
