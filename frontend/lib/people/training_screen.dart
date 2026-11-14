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
///
/// **A register, not a catalogue (issue #394).** A reader comes here to compare
/// records — which of them was trained, by whom, and how many of its Trainees
/// have answered — so above [AppBreakpoints.registerTable] of box width the
/// records sit under one `AppTableHeader` band with the numbers aligned, and
/// below it each record is a card carrying the two sentences this Screen has
/// always shown. The card states today's wording verbatim; the band adds the
/// column labels the wide shape needs, which is the only reading the narrow one
/// does without.
///
/// **Which columns, and why these.** The wire sends one row per record
/// (`toTrainingRecord` in training.js): its number, its title, the day it was
/// given, its Org Unit, whose Trainees are on it and how many of them have
/// answered. Those are the columns, in that order, with the record's state as
/// the tone column and the printed form as the row's own action — a field is
/// not invented to fill a column and none is dropped for a narrower row
/// (`docs/design-language.md` §6). A per-Trainee answered *date* is on the
/// record's own page and on the printed form, where it belongs beside the
/// person it belongs to; the register answers "how many", which is what it can
/// compare down a column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/status_chip.dart';
import 'org_unit_picker_bloc.dart';
import 'training_bloc.dart';
import 'training_raise_dialog.dart';
import 'training_record.dart';
import '../l10n/vocabulary.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key, required this.canRaise});

  /// Whether to offer "Raise training record" — a holder of an edit Grant
  /// somewhere, or an administrator.
  final bool canRaise;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> raiseKey = ValueKey<String>('training-raise');
  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('training-empty-raise');
  static const ValueKey<String> truncatedKey = ValueKey<String>('training-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('training-empty');
  static const ValueKey<String> failureKey = ValueKey<String>('training-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('training-retry');
  static const ValueKey<String> loadingKey = ValueKey<String>('training-loading');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('training-org-unit-chosen');
  static const ValueKey<String> orgUnitClearKey = ValueKey<String>('training-org-unit-clear');
  static const ValueKey<String> orgUnitBrowseToggleKey = ValueKey<String>('training-org-unit-toggle');
  static const ValueKey<String> fromFieldKey = ValueKey<String>('training-from');
  static const ValueKey<String> toFieldKey = ValueKey<String>('training-to');
  static const ValueKey<String> registerKey = ValueKey<String>('training-register');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('training-org-unit-$id');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('training-row-$id');

  /// The record's own state chip. The name is historical — #287 rendered it only
  /// for a draft — and since #394 the register's State column carries it for
  /// every row, a sent record included, so the column is never blank. No caller
  /// or test is renamed by that.
  static ValueKey<String> draftKey(String id) => ValueKey<String>('training-draft-$id');

  /// A row's link to the record's printed form (issue #292).
  static ValueKey<String> formKey(String id) => ValueKey<String>('training-form-$id');

  /// The band, stated once: the labels and the cells are built from it, so a
  /// label and its cells start at the same x by construction
  /// (`docs/frontend-layout.md` §4).
  static List<AppTableColumn> columns(AppLocalizations l10n) => <AppTableColumn>[
    AppTableColumn(l10n.trainingRecord, flex: 3),
    AppTableColumn(l10n.navTraining, flex: 5),
    AppTableColumn(l10n.trainingTrainees, flex: 5),
    AppTableColumn(l10n.commonTrainedOn, flex: 2),
    AppTableColumn(l10n.trainingAnswers, flex: 2, align: AppColumnAlign.end),
    AppTableColumn(l10n.commonState, width: 104),
    // The row's own action column: an unlabelled slot at the far end, so the
    // printed form sits at the card's right edge rather than inside another
    // cell (`docs/frontend-layout.md` §6).
    AppTableColumn('', width: 56),
  ];

  /// How many Trainees have answered, of how many are on the record.
  static String answersOf(TrainingRecord record) =>
      '${record.answeredCount} of ${record.traineeCount}';

  /// Who is on the record, as one cell: the names, in the order they were added.
  static String traineesOf(TrainingRecord record) =>
      record.trainees.isEmpty ? '—' : record.trainees.map((t) => t.employeeName).join(', ');

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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<TrainingBloc>().state;
    final bloc = context.read<TrainingBloc>();

    final Widget content;
    if (state.failure != null) {
      content = PlatformFailureState(
        key: TrainingScreen.failureKey,
        title: l10n.trainingTrainingRecordsCouldNotBeRead,
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
          ? PlatformEmptyState.noneMatched(
              key: TrainingScreen.emptyKey,
              title: l10n.trainingNoTrainingRecordsMatch,
              message: l10n.trainingNothingWasTrainedUnderThatOrgUnit,
            )
          : PlatformEmptyState.noneExist(
              key: TrainingScreen.emptyKey,
              title: l10n.trainingNoTrainingRecordsYet,
              message: widget.canRaise
                  ? l10n.trainingRaiseATrainingRecordToStartThe
                  : l10n.trainingNothingHasBeenRecordedAsTrainedYet,
              icon: Icons.school_outlined,
              actionLabel: widget.canRaise ? l10n.commonRaiseTrainingRecord : null,
              actionKey: TrainingScreen.emptyRaiseKey,
              onAction: widget.canRaise ? () => TrainingRaiseDialog.open(context) : null,
            );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          // The box the register is handed, at the reader's text size (§10):
          // one card per record below it, the band above it.
          final wide = constraints.maxWidth >=
              AppBreakpoints.effective(context, AppBreakpoints.registerTable);
          if (!wide) {
            return AppListCard(
              key: TrainingScreen.registerKey,
              rows: [for (final record in state.records) _TrainingRow(record: record)],
            );
          }
          return Card(
            key: TrainingScreen.registerKey,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTableHeader(columns: TrainingScreen.columns(l10n)),
                for (final record in state.records) _TrainingTableRow(record: record),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: TrainingScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(
                title: l10n.titleTrainingRecords,
                description: l10n.trainingWhatThePlantHasTrainedPeopleOn,
                actions: [
                  if (widget.canRaise)
                    FilledButton.icon(
                      key: TrainingScreen.raiseKey,
                      onPressed: () => TrainingRaiseDialog.open(context),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.commonRaiseTrainingRecord),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
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
                      label: l10n.commonFrom,
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
                      label: l10n.commonTo,
                      value: state.to,
                      optional: true,
                      onChanged: (value) => bloc.add(TrainingToChosen(value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              // A capped register must not read as the whole of it (ADR-0026).
              if (state.truncated && state.failure == null && !state.isLoading)
                Padding(
                  key: TrainingScreen.truncatedKey,
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    l10n.trainingThereAreMoreTrainingRecordsThanThis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

/// One record under the register's band: the same fields the card carries, one
/// per column. The row is 44 (`AppTouchTarget.min`) because the whole of it
/// opens the record, and the printed form is a sibling target inside it.
class _TrainingTableRow extends StatelessWidget {
  const _TrainingTableRow({required this.record});

  final TrainingRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    return AppTableRow(
      key: TrainingScreen.rowKey(record.id),
      columns: TrainingScreen.columns(l10n),
      onTap: () => context.go('${Routes.training}/${record.id}'),
      cells: [
        DisclosingText(record.number, style: dense?.copyWith(color: palette.textMuted)),
        DisclosingText(record.title, style: dense?.copyWith(color: palette.textPrimary)),
        DisclosingText(
          TrainingScreen.traineesOf(record),
          style: dense?.copyWith(color: palette.textMuted),
        ),
        Text(record.trainedOn, style: dense),
        Text(
          TrainingScreen.answersOf(record),
          style: AppTableRow.numberStyle(context),
        ),
        // The record's own state. A draft carries the chip (issue #287's own
        // marking, kept as it was); a sent record states its state as words,
        // so the column is never blank and the draft marking stays distinct.
        if (record.isDraft)
          StatusChip(
            key: TrainingScreen.draftKey(record.id),
            label: record.statusLabel(l10n),
            tone: trainingStatusTone(record.status),
          )
        else
          Text(record.statusLabel(l10n), style: dense?.copyWith(color: palette.textMuted)),
        // The printed form, one tap from the register — a sibling of the row's
        // own tap target so the two never fight over one gesture.
        IconButton(
          key: TrainingScreen.formKey(record.id),
          tooltip: l10n.trainingTheFormFor(record.number),
          icon: const Icon(Icons.description_outlined),
          onPressed: () => context.go(Routes.trainingForm(record.id)),
        ),
      ],
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (state.orgUnitId != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l10n.commonOrgUnit2(state.orgUnitName ?? ''),
              key: TrainingScreen.orgUnitChosenKey,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: TrainingScreen.orgUnitClearKey,
            tooltip: l10n.commonClear,
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
            label: Text(browsing ? l10n.commonHideOrgUnits : l10n.commonFilterByOrgUnit),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final pickerBloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = Text(state.sitesFailure ?? l10n.commonTheSitesAreUnavailable);
    } else if (state.rootsFailure != null) {
      body = Text(state.rootsFailure!);
    } else if (state.sites.isEmpty) {
      body = Text(l10n.commonThereAreNoSitesToBrowseYet);
    } else if (state.rows.isEmpty) {
      body = Text(l10n.commonNothingToBrowseInThisSite);
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
            decoration: InputDecoration(labelText: l10n.commonSite),
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
    final l10n = AppLocalizations.of(context);
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
                    tooltip: row.isExpanded ? l10n.commonCollapse : l10n.commonExpand,
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

/// One record below the register's breakpoint: the two sentences this Screen
/// has always shown, its state, and the printed form.
class _TrainingRow extends StatelessWidget {
  const _TrainingRow({required this.record});

  final TrainingRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final muted = AppTypography.floor(context)?.copyWith(color: palette.textMuted);
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
                        child: DisclosingText(
                          '${record.number} · ${record.title}',
                          style: AppTypography.dense(context)?.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      if (record.isDraft)
                        StatusChip(
                          key: TrainingScreen.draftKey(record.id),
                          label: record.statusLabel(l10n),
                          tone: trainingStatusTone(record.status),
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xxs),
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
          tooltip: l10n.trainingTheFormFor(record.number),
          icon: const Icon(Icons.description_outlined),
          onPressed: () => context.go(Routes.trainingForm(record.id)),
        ),
      ],
    );
  }
}
