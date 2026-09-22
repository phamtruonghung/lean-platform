/// The Attendance Destination's own landing Screen (issue #249): choose an
/// Org Unit and a production day, then open the sheet for one of that day's
/// shift instances. There is no shift calendar Screen to link a sheet from
/// yet (#250, the "attendance to confirm" worklist, is what will do that job
/// properly) — this picker exists so the sheet Screen
/// (`/people/attendance/:shiftInstanceId`) has a real address to be reached
/// from, per issue #249's own "at its own address under the People
/// Destination group" criterion.
///
/// Org Unit browsing reuses `OrgUnitPickerBloc`, the same Bloc
/// `DirectoryOrgUnitFilterDialog` already drives for a single-select choice
/// over the same tree — that file's own header explains why the full
/// `OrgUnitPicker` widget (a Grant editor) is not reused instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import 'attendance.dart';
import 'attendance_picker_bloc.dart';
import 'org_unit_picker_bloc.dart';

class AttendancePickerScreen extends StatelessWidget {
  const AttendancePickerScreen({super.key});

  static const double maxWidth = 640;

  static const ValueKey<String> dateFieldKey = ValueKey<String>('attendance-picker-date');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('attendance-picker-org-unit-chosen');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-picker-empty');
  static const ValueKey<String> failureKey = ValueKey<String>('attendance-picker-failure');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('attendance-picker-org-unit-$id');
  static ValueKey<String> shiftRowKey(String id) => ValueKey<String>('attendance-picker-shift-$id');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendancePickerBloc>(
          create: (_) => AttendancePickerBloc(peopleApi: peopleApi, authGateway: authGateway),
        ),
        BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
        ),
      ],
      child: const _PickerBody(),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AttendancePickerBloc>().state;

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: AttendancePickerScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Text('Attendance', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'Choose an Org Unit and a production day to open that '
                "shift's attendance sheet.",
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              if (state.orgUnitName == null)
                const _OrgUnitBrowser()
              else
                Text(
                  state.orgUnitName!,
                  key: AttendancePickerScreen.orgUnitChosenKey,
                  style: theme.textTheme.titleMedium,
                ),
              const SizedBox(height: Spacing.md),
              AppDateField(
                key: AttendancePickerScreen.dateFieldKey,
                name: 'attendance-picker-date',
                label: 'Production day',
                value: state.date,
                onChanged: (value) {
                  if (value != null) {
                    context.read<AttendancePickerBloc>().add(AttendancePickerDateChosen(value));
                  }
                },
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                Text(
                  state.failure!,
                  key: AttendancePickerScreen.failureKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                )
              else if (state.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (state.orgUnitId != null && state.date != null && state.shiftInstances.isEmpty)
                Text(
                  'No shifts are scheduled here on that day.',
                  key: AttendancePickerScreen.emptyKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                for (final shiftInstance in state.shiftInstances) _ShiftRow(shiftInstance: shiftInstance),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shiftInstance});

  final ShiftInstanceSummary shiftInstance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: AttendancePickerScreen.shiftRowKey(shiftInstance.id),
      title: Text(shiftInstance.shiftDefinitionName),
      subtitle: Text(shiftInstance.hasSheet
          ? (shiftInstance.confirmedAt != null ? 'Confirmed' : 'Started, not yet confirmed')
          : 'Not opened yet'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('/people/attendance/${shiftInstance.id}'),
      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    );
  }
}

class _OrgUnitBrowser extends StatelessWidget {
  const _OrgUnitBrowser();

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
      body = Text(state.sitesFailure ?? 'The Sites are unavailable.');
    } else if (state.rootsFailure != null) {
      body = Text(state.rootsFailure!);
    } else if (state.sites.isEmpty) {
      body = const Text('There are no Sites to browse yet.');
    } else if (state.rows.isEmpty) {
      body = const Text('Nothing to browse in this Site.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in state.rows) _OrgUnitRow(row: row, bloc: bloc)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.sites.length > 1)
          DropdownButtonFormField<String>(
            initialValue: state.siteId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Site'),
            items: [
              for (final site in state.sites) DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
            ],
            onChanged: (siteId) {
              if (siteId != null) bloc.add(OrgUnitPickerSiteSelected(siteId));
            },
          ),
        const SizedBox(height: Spacing.sm),
        DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
      ],
    );
  }
}

class _OrgUnitRow extends StatelessWidget {
  const _OrgUnitRow({required this.row, required this.bloc});

  final OrgUnitRow row;
  final OrgUnitPickerBloc bloc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: row.depth * Spacing.lg),
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
            child: InkWell(
              key: AttendancePickerScreen.orgUnitRowKey(row.node.id),
              onTap: () => context.read<AttendancePickerBloc>().add(
                    AttendancePickerOrgUnitChosen(orgUnitId: row.node.id, orgUnitName: row.node.name),
                  ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Text(row.node.name),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
