/// The attendance-to-confirm worklist (issue #250): the past shift instances
/// whose sheet is missing or unconfirmed, oldest first, restricted to the
/// Org Units this caller's own edit Grants reach (or every Site's list, for
/// an administrator) — "the sheets it could confirm" (issue #250's own
/// wording). Under #247 decision 9, a single unconfirmed shift makes the
/// injury rates `no_data`, so this Screen is where that gap actually gets
/// closed.
///
/// **Address, deliberately nested under `/attendance` rather than a new
/// sidebar Destination.** Issue #250 asks for "its own address under the
/// People Destination group" — `/attendance/to-confirm` (`Routes.attendance`,
/// `router.dart`) is exactly that: its own bookmarkable address, filed under
/// the same Attendance Destination the picker (`/attendance`) already
/// occupies, per
/// CONTEXT.md's own Screen/Destination distinction ("a Screen has its own
/// address... a Destination is an entry in the Shell's sidebar"). Reached
/// from a button on `AttendancePickerScreen` rather than a second sidebar
/// entry, so this ticket adds no new Destination and therefore reopens
/// none of the Shell's own full-app goldens (`frontend/test/GOLDENS.md`
/// goldens only the Shell and the Work orders Screen; neither reads the
/// Destination list itself, but a new Destination would still shift
/// `shell_test.dart`'s own sidebar assertions and is exactly the kind of
/// change GOLDENS.md asks to not make quietly).
///
/// Org Unit browsing reuses `OrgUnitPickerBloc`, the same Bloc
/// `AttendancePickerScreen`'s own `_OrgUnitBrowser` already drives for a
/// single-select choice over the same tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import 'attendance.dart';
import 'attendance_to_confirm_bloc.dart';
import 'org_unit_picker_bloc.dart';

class AttendanceToConfirmScreen extends StatelessWidget {
  const AttendanceToConfirmScreen({super.key});

  static const double maxWidth = 720;

  static const ValueKey<String> failureKey = ValueKey<String>('attendance-to-confirm-failure');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-to-confirm-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('attendance-to-confirm-loading');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('attendance-to-confirm-org-unit-chosen');
  static const ValueKey<String> orgUnitClearKey = ValueKey<String>('attendance-to-confirm-org-unit-clear');
  static const ValueKey<String> orgUnitBrowseToggleKey = ValueKey<String>('attendance-to-confirm-org-unit-toggle');
  static const ValueKey<String> fromFieldKey = ValueKey<String>('attendance-to-confirm-from');
  static const ValueKey<String> toFieldKey = ValueKey<String>('attendance-to-confirm-to');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('attendance-to-confirm-org-unit-$id');
  static ValueKey<String> entryKey(String shiftInstanceId) =>
      ValueKey<String>('attendance-to-confirm-entry-$shiftInstanceId');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendanceToConfirmBloc>(
          create: (_) => AttendanceToConfirmBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const AttendanceToConfirmStarted()),
        ),
        BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
        ),
      ],
      child: const _WorklistBody(),
    );
  }
}

class _WorklistBody extends StatefulWidget {
  const _WorklistBody();

  @override
  State<_WorklistBody> createState() => _WorklistBodyState();
}

class _WorklistBodyState extends State<_WorklistBody> {
  bool _browsingOrgUnit = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AttendanceToConfirmBloc>().state;
    final bloc = context.read<AttendanceToConfirmBloc>();

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: AttendanceToConfirmScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Text('Attendance to confirm', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                "Past shifts whose sheet is missing or hasn't been confirmed yet, "
                'oldest first, across the Org Units you can confirm one at.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              _OrgUnitFilter(
                state: state,
                bloc: bloc,
                browsing: _browsingOrgUnit,
                onToggleBrowse: () => setState(() => _browsingOrgUnit = !_browsingOrgUnit),
                onCleared: () => setState(() => _browsingOrgUnit = false),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppDateField(
                      key: AttendanceToConfirmScreen.fromFieldKey,
                      name: 'attendance-to-confirm-from',
                      label: 'From',
                      value: state.from,
                      optional: true,
                      onChanged: (value) => bloc.add(AttendanceToConfirmFromChosen(value)),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: AppDateField(
                      key: AttendanceToConfirmScreen.toFieldKey,
                      name: 'attendance-to-confirm-to',
                      label: 'To',
                      value: state.to,
                      optional: true,
                      onChanged: (value) => bloc.add(AttendanceToConfirmToChosen(value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                Text(
                  state.failure!,
                  key: AttendanceToConfirmScreen.failureKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                )
              else if (state.isLoading)
                const Center(
                  key: AttendanceToConfirmScreen.loadingKey,
                  child: CircularProgressIndicator(),
                )
              else if (state.entries.isEmpty)
                Text(
                  'Nothing to confirm here.',
                  key: AttendanceToConfirmScreen.emptyKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                for (final entry in state.entries) _EntryRow(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgUnitFilter extends StatelessWidget {
  const _OrgUnitFilter({
    required this.state,
    required this.bloc,
    required this.browsing,
    required this.onToggleBrowse,
    required this.onCleared,
  });

  final AttendanceToConfirmState state;
  final AttendanceToConfirmBloc bloc;
  final bool browsing;
  final VoidCallback onToggleBrowse;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.orgUnitId != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Org Unit: ${state.orgUnitName}',
              key: AttendanceToConfirmScreen.orgUnitChosenKey,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: AttendanceToConfirmScreen.orgUnitClearKey,
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: () {
              bloc.add(const AttendanceToConfirmOrgUnitCleared());
              onCleared();
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: AttendanceToConfirmScreen.orgUnitBrowseToggleKey,
          onPressed: onToggleBrowse,
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(browsing ? 'Hide Org Units' : 'Filter by Org Unit'),
        ),
        if (browsing) ...[
          const SizedBox(height: Spacing.sm),
          _OrgUnitBrowser(bloc: bloc),
        ],
      ],
    );
  }
}

class _OrgUnitBrowser extends StatelessWidget {
  const _OrgUnitBrowser({required this.bloc});

  final AttendanceToConfirmBloc bloc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final pickerBloc = context.read<OrgUnitPickerBloc>();

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
              if (siteId != null) pickerBloc.add(OrgUnitPickerSiteSelected(siteId));
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
  final AttendanceToConfirmBloc bloc;

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
                    onPressed: () => context.read<OrgUnitPickerBloc>().add(
                          row.isExpanded
                              ? OrgUnitPickerCollapsed(row.node.id)
                              : OrgUnitPickerExpanded(row.node.id),
                        ),
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: InkWell(
              key: AttendanceToConfirmScreen.orgUnitRowKey(row.node.id),
              onTap: () => bloc.add(
                AttendanceToConfirmOrgUnitChosen(orgUnitId: row.node.id, orgUnitName: row.node.name),
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AttendanceToConfirmEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: AttendanceToConfirmScreen.entryKey(entry.shiftInstanceId),
      title: Text('${entry.shiftDefinitionName} · ${entry.productionDate}'),
      subtitle: Text('${entry.orgUnitName} (${entry.siteName}) — ${attendanceSheetStateLabel(entry.sheetState)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('${Routes.attendance}/${entry.shiftInstanceId}'),
      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    );
  }
}
