/// The Training record register (issue #287, ADR-0043): every Training record
/// the caller may read, newest first, narrowed by an Org Unit (and everything
/// beneath it — the server does that) and a range of days. A row opens that
/// record at `/training/:id`.
///
/// Offered to every approved Account: the register is a read open to all
/// (ADR-0009), and the server alone decides which drafts a caller sees (a
/// draft is shown only to someone who could send it). Only the "Raise
/// training record" control is gated, by [canRaise] — the router reads it off
/// `OrgUnitScope.canWriteSomewhere`, the same coarse "can write somewhere"
/// signal the attendance sheet's `canRecord` reads. The server is the real
/// per-Org-Unit gate (403 `OUTSIDE_GRANTED_ORG_UNITS`), rendered in the dialog.
///
/// Org Unit browsing reuses `OrgUnitPickerBloc`, exactly as
/// `AttendanceToConfirmScreen` does for its own filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/status_chip.dart';
import 'org_unit_picker_bloc.dart';
import 'training_bloc.dart';
import 'training_raise_dialog.dart';
import 'training_record.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key, required this.canRaise});

  /// Whether to offer "Raise training record" — a holder of an edit Grant
  /// somewhere, or an administrator.
  final bool canRaise;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> raiseKey = ValueKey<String>('training-raise');
  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('training-empty-raise');
  static const ValueKey<String> emptyKey = ValueKey<String>('training-empty');
  static const ValueKey<String> failureKey = ValueKey<String>('training-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('training-retry');
  static const ValueKey<String> loadingKey = ValueKey<String>('training-loading');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('training-org-unit-chosen');
  static const ValueKey<String> orgUnitClearKey = ValueKey<String>('training-org-unit-clear');
  static const ValueKey<String> orgUnitBrowseToggleKey = ValueKey<String>('training-org-unit-toggle');
  static const ValueKey<String> fromFieldKey = ValueKey<String>('training-from');
  static const ValueKey<String> toFieldKey = ValueKey<String>('training-to');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('training-org-unit-$id');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('training-row-$id');
  static ValueKey<String> draftKey(String id) => ValueKey<String>('training-draft-$id');

  /// A row's link to the record's printed form (issue #292).
  static ValueKey<String> formKey(String id) => ValueKey<String>('training-form-$id');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<TrainingBloc>(
          create: (_) => TrainingBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const TrainingStarted()),
        ),
        BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
        ),
      ],
      child: _RegisterBody(canRaise: canRaise),
    );
  }
}

class _RegisterBody extends StatefulWidget {
  const _RegisterBody({required this.canRaise});

  final bool canRaise;

  @override
  State<_RegisterBody> createState() => _RegisterBodyState();
}

class _RegisterBodyState extends State<_RegisterBody> {
  bool _browsingOrgUnit = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<TrainingBloc>().state;
    final bloc = context.read<TrainingBloc>();

    final Widget content;
    if (state.failure != null) {
      content = PlatformFailureState(
        key: TrainingScreen.failureKey,
        title: 'Training records could not be read',
        message: state.failure!,
        retryKey: TrainingScreen.retryKey,
        onRetry: () => bloc.add(const TrainingStarted()),
      );
    } else if (state.isLoading) {
      content = const Center(
        key: TrainingScreen.loadingKey,
        child: Padding(padding: EdgeInsets.all(Spacing.lg), child: CircularProgressIndicator()),
      );
    } else if (state.records.isEmpty) {
      content = state.isFiltered
          ? const PlatformEmptyState.noneMatched(
              key: TrainingScreen.emptyKey,
              title: 'No Training records match',
              message: 'Nothing was trained under that Org Unit in those days.',
            )
          : PlatformEmptyState.noneExist(
              key: TrainingScreen.emptyKey,
              title: 'No Training records yet',
              message: widget.canRaise
                  ? 'Raise a Training record to start the register.'
                  : 'Nothing has been recorded as trained yet.',
              icon: Icons.school_outlined,
              actionLabel: widget.canRaise ? 'Raise training record' : null,
              actionKey: TrainingScreen.emptyRaiseKey,
              onAction: widget.canRaise ? () => TrainingRaiseDialog.open(context) : null,
            );
    } else {
      content = AppListCard(
        rows: [for (final record in state.records) _TrainingRow(record: record)],
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: TrainingScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Training records', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'What the plant has trained people on, and when.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canRaise)
                    FilledButton.icon(
                      key: TrainingScreen.raiseKey,
                      onPressed: () => TrainingRaiseDialog.open(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise training record'),
                    ),
                ],
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
                      key: TrainingScreen.fromFieldKey,
                      name: 'training-from',
                      label: 'From',
                      value: state.from,
                      optional: true,
                      onChanged: (value) => bloc.add(TrainingFromChosen(value)),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: AppDateField(
                      key: TrainingScreen.toFieldKey,
                      name: 'training-to',
                      label: 'To',
                      value: state.to,
                      optional: true,
                      onChanged: (value) => bloc.add(TrainingToChosen(value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              content,
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

  final TrainingState state;
  final TrainingBloc bloc;
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
              key: TrainingScreen.orgUnitChosenKey,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: TrainingScreen.orgUnitClearKey,
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: () {
              bloc.add(const TrainingOrgUnitCleared());
              onCleared();
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: TrainingScreen.orgUnitBrowseToggleKey,
            onPressed: onToggleBrowse,
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(browsing ? 'Hide Org Units' : 'Filter by Org Unit'),
          ),
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

  final TrainingBloc bloc;

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
  final TrainingBloc bloc;

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
              key: TrainingScreen.orgUnitRowKey(row.node.id),
              onTap: () => bloc.add(
                TrainingOrgUnitChosen(orgUnitId: row.node.id, orgUnitName: row.node.name),
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

class _TrainingRow extends StatelessWidget {
  const _TrainingRow({required this.record});

  final TrainingRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final trainerName = record.trainerName;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: TrainingScreen.rowKey(record.id),
            onTap: () => context.go('${Routes.training}/${record.id}'),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${record.number} · ${record.title}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (record.isDraft) ...[
                        const SizedBox(width: Spacing.sm),
                        StatusChip(
                          key: TrainingScreen.draftKey(record.id),
                          label: record.statusLabel,
                          tone: trainingStatusTone(record.status),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${record.trainedOn} · ${record.orgUnitName} · ${formatTrainingHours(record.durationHours)}'
                    '${trainerName == null ? '' : ' · Trainer: $trainerName'}',
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        // The printed form, one tap from the register — a sibling of the row's
        // own tap target so the two never fight over one gesture.
        IconButton(
          key: TrainingScreen.formKey(record.id),
          tooltip: 'The form for ${record.number}',
          icon: const Icon(Icons.description_outlined),
          onPressed: () => context.go(Routes.trainingForm(record.id)),
        ),
      ],
    );
  }
}
