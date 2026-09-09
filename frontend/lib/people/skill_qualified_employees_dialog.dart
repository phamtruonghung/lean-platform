/// From a skill, who holds it — filtered by a minimum proficiency level
/// (issue #89, AC5). `GET /api/people/skills/:id/qualified-employees`
/// requires `orgUnitId` (skill-routes.js's own header: it 400s without one),
/// so this dialog makes choosing an Org Unit part of the question rather than
/// firing a request that would refuse it — the same `OrgUnitPickerBloc`
/// single-select tree `EmployeeAssignmentDialog` already drives for choosing
/// a destination Org Unit (issue #88), reused here for choosing a *scope*
/// instead. `OrgUnitPicker` the widget is not reused, for the same reason
/// `EmployeeAssignmentDialog`'s own header gives: it is a Grant editor built
/// for the Approval flow, and this dialog wants a single-select choice with
/// none of that — `_ScopePicker` below is a third Module-local view over the
/// one shared Bloc, the same amount of duplication `EmployeeAssignmentDialog`
/// and `DirectoryOrgUnitFilterDialog` already accept for the same reason.
///
/// A dialog, not a Screen of its own (see this Module's own escalation on the
/// point): the result is a question asked *about* one catalogue row, scoped
/// to an Org Unit chosen fresh each time, not something a caller would
/// bookmark or link to — CONTEXT.md's own Screen entry. Dispatches into
/// `SkillsBloc`, the catalogue Screen's own Bloc, the same "the dialog
/// dispatches into the Screen's own Bloc" shape `EmployeeAssignmentDialog`
/// uses against `EmployeeDetailBloc`.
///
/// `listQualifiedEmployees` (skills.js) already excludes a lapsed
/// qualification server-side (`QUALIFICATION_IS_CURRENT_SQL`) — a holder
/// whose qualification has lapsed simply is not answered here at all, so
/// unlike the Employee Screen's own held-skill chips there is no "lapsed" row
/// to distinguish on this dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'org_unit.dart';
import 'org_unit_picker_bloc.dart';
import 'skill.dart';
import 'skills_bloc.dart';

class SkillQualifiedEmployeesDialog extends StatefulWidget {
  const SkillQualifiedEmployeesDialog({super.key, required this.skill});

  final Skill skill;

  static const ValueKey<String> siteKey = ValueKey<String>('skill-qualified-site');
  static const ValueKey<String> minimumLevelKey = ValueKey<String>('skill-qualified-minimum-level');
  static const ValueKey<String> searchKey = ValueKey<String>('skill-qualified-search');
  static const ValueKey<String> closeKey = ValueKey<String>('skill-qualified-close');
  static const ValueKey<String> failureKey = ValueKey<String>('skill-qualified-failure');
  static const ValueKey<String> emptyKey = ValueKey<String>('skill-qualified-empty');
  static const ValueKey<String> hintKey = ValueKey<String>('skill-qualified-hint');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('skill-qualified-expand-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('skill-qualified-org-unit-$id');
  static ValueKey<String> rowKey(String employeeId) => ValueKey<String>('skill-qualified-row-$employeeId');

  /// Opens the dialog over the skill catalogue — the same explicit Bloc
  /// hand-off every dialog needing a second Bloc uses (`SkillsBloc` plus a
  /// fresh `OrgUnitPickerBloc`), the same pairing `EmployeeAssignmentDialog`
  /// already sets up.
  static Future<void> open(BuildContext context, Skill skill) {
    final skillsBloc = context.read<SkillsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<SkillsBloc>.value(
        value: skillsBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (context) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: SkillQualifiedEmployeesDialog(skill: skill),
        ),
      ),
    ).whenComplete(() => skillsBloc.add(const SkillsQualifiedEmployeesCleared()));
  }

  @override
  State<SkillQualifiedEmployeesDialog> createState() => _SkillQualifiedEmployeesDialogState();
}

class _SkillQualifiedEmployeesDialogState extends State<SkillQualifiedEmployeesDialog> {
  String? _orgUnitId;

  /// Null means "Any" — the server's own default of 1 (skills.js's own
  /// `validateMinimumLevel`), never sent as a bare 0 (skill-routes.js's own
  /// `parseMinimumLevel` only accepts 1–4).
  int? _minimumLevel;

  void _search() {
    final orgUnitId = _orgUnitId;
    if (orgUnitId == null) return;
    context.read<SkillsBloc>().add(
          SkillsQualifiedEmployeesRequested(
            skillId: widget.skill.id,
            orgUnitId: orgUnitId,
            minimumLevel: _minimumLevel,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skillsState = context.watch<SkillsBloc>().state;
    final query = skillsState is SkillsLoaded ? skillsState.query : null;

    return AlertDialog(
      title: Text('Who holds ${widget.skill.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scoped to', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.xs),
              _ScopePicker(
                selectedId: _orgUnitId,
                onSelected: (node) => setState(() => _orgUnitId = node.id),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<int?>(
                key: SkillQualifiedEmployeesDialog.minimumLevelKey,
                initialValue: _minimumLevel,
                decoration: const InputDecoration(
                  labelText: 'Minimum proficiency',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<int?>(value: null, child: Text('Any')),
                  DropdownMenuItem<int?>(value: 1, child: Text('1')),
                  DropdownMenuItem<int?>(value: 2, child: Text('2')),
                  DropdownMenuItem<int?>(value: 3, child: Text('3')),
                  DropdownMenuItem<int?>(value: 4, child: Text('4')),
                ],
                onChanged: (value) => setState(() => _minimumLevel = value),
              ),
              const SizedBox(height: Spacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: SkillQualifiedEmployeesDialog.searchKey,
                  onPressed: _orgUnitId == null ? null : _search,
                  child: const Text('Search'),
                ),
              ),
              const SizedBox(height: Spacing.md),
              _Results(query: query),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: SkillQualifiedEmployeesDialog.closeKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query});

  final QualifiedEmployeesQuery? query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (query == null) {
      return Text(
        'Choose an Org Unit, then search.',
        key: SkillQualifiedEmployeesDialog.hintKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    switch (query!.status) {
      case QualifiedEmployeesStatus.loading:
        return const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case QualifiedEmployeesStatus.failed:
        return Text(
          query!.failure ?? '',
          key: SkillQualifiedEmployeesDialog.failureKey,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        );
      case QualifiedEmployeesStatus.ready:
        if (query!.employees.isEmpty) {
          return Text(
            'Nobody currently qualifies at this Org Unit.',
            key: SkillQualifiedEmployeesDialog.emptyKey,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final employee in query!.employees)
              Padding(
                key: SkillQualifiedEmployeesDialog.rowKey(employee.id),
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text('${employee.displayName} · ${employee.employeeNo}')),
                    Text('Level ${employee.proficiencyLevel}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

/// The tree pane itself — a Site switch (when there is more than one to
/// choose from) over a bounded-height, single-select view of
/// `OrgUnitPickerBloc`'s own rows. See this file's own header for why this is
/// a third view rather than a shared widget with `EmployeeAssignmentDialog`'s
/// own `_DestinationPicker`.
class _ScopePicker extends StatelessWidget {
  const _ScopePicker({required this.selectedId, required this.onSelected});

  final String? selectedId;
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
        onRetry: () => bloc.add(const OrgUnitPickerStarted()),
      );
    } else if (state.rootsFailure != null) {
      body = _PickerMessage(
        message: state.rootsFailure!,
        onRetry: () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)),
      );
    } else if (state.rows.isEmpty) {
      body = const _PickerMessage(message: 'Nothing to browse in this Site.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _ScopeRow(
          row: state.rows[index],
          isSelected: state.rows[index].node.id == selectedId,
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
            key: SkillQualifiedEmployeesDialog.siteKey,
            initialValue: state.siteId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
            items: [
              for (final site in state.sites)
                DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
            ],
            onChanged: (siteId) {
              if (siteId == null) return;
              bloc.add(OrgUnitPickerSiteSelected(siteId));
            },
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

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.row, required this.isSelected, required this.onSelected});

  final OrgUnitRow row;
  final bool isSelected;
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
                    key: SkillQualifiedEmployeesDialog.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                    onPressed: () => bloc.add(
                      row.isExpanded
                          ? OrgUnitPickerCollapsed(row.node.id)
                          : OrgUnitPickerExpanded(row.node.id),
                    ),
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: TextButton(
              key: SkillQualifiedEmployeesDialog.orgUnitKey(row.node.id),
              onPressed: () => onSelected(row.node),
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
