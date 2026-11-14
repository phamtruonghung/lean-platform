/// One KPI's Targets (ADR-0055) at `/kpi/:kpiId/targets`: what is in force
/// today per grain, and the whole history, newest first. Reached from a
/// catalogue row — it needs a `kpiId`, so it is not a Destination of its own;
/// the Shell lights the catalogue's entry while it is open.
///
/// **Change Target is offered only with write authority** (`canWrite`, from
/// `/me`'s `orgUnitScope.canWriteSomewhere`). A KPI Target is never edited: the
/// dialog appends a new entry from a date, and this history shows every entry
/// ever made, newest first as the server orders it.
///
/// **The page reads as a ledger (issue #395).** `kpi.kpi_target` is append-only
/// by construction, and the Screen used to say so in a doc comment while showing
/// six unlabelled columns of plain text over a header that looked like another
/// row. It now reads the way the record behaves: a card of what is in force
/// today, per grain, each row one sentence on the 32px rhythm; then a register
/// whose band is the shared `AppTableHeader`, whose rows are `AppTableRow`'s
/// (32px at the minimum, taller only if a cell wraps), whose Target column ends
/// on a shared right edge in tabular figures, and whose caption states the rule
/// in words — an entry is never edited, a later one supersedes it. There is
/// exactly one write affordance on the Screen (Change Target) and no edit or
/// delete anywhere, which is what an append-only record should offer.
///
/// **Seven columns of ledger need a box, or they become cards.** Below
/// [tableWidth] (at the reader's text scale — `AppBreakpoints.effective`) six
/// columns cannot hold a date, a word and a name without ellipsising a label, so
/// each entry becomes a card that labels its own six fields. That is the same
/// turn every maintenance register makes at its own number (design-language §10),
/// and it is why the entry is never clipped at 700px or at twice the text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'change_target_dialog.dart';
import 'kpi_catalogue.dart';
import 'kpi_targets_bloc.dart';

class KpiTargetsScreen extends StatelessWidget {
  const KpiTargetsScreen({super.key, required this.kpiId, required this.canWrite});

  final int kpiId;
  final bool canWrite;

  static const double maxWidth = AppLayout.pageWidth;

  /// The width of content at which the history's six columns stay a register.
  /// A date (10 characters), a grain, a Target with its comparator, a note and
  /// two stamps need about this much before a column has to ellipsise its own
  /// label; below it each entry becomes a card instead.
  static const double tableWidth = 860;

  static const ValueKey<String> siteKey = ValueKey<String>('kpi-targets-site');
  static const ValueKey<String> backKey = ValueKey<String>('kpi-targets-back');
  static const ValueKey<String> changeTargetKey = ValueKey<String>('kpi-targets-change');
  static const ValueKey<String> headerKey = ValueKey<String>('kpi-targets-header');
  static const ValueKey<String> currentKey = ValueKey<String>('kpi-targets-current');
  static const ValueKey<String> historyKey = ValueKey<String>('kpi-targets-history');
  static const ValueKey<String> failedKey = ValueKey<String>('kpi-targets-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('kpi-targets-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('kpi-targets-empty');
  static ValueKey<String> currentRowKey(String grain) => ValueKey<String>('kpi-targets-current-$grain');
  static ValueKey<String> historyRowKey(int targetId) => ValueKey<String>('kpi-targets-history-$targetId');
  static ValueKey<String> historyCardKey(int targetId) => ValueKey<String>('kpi-targets-history-card-$targetId');

  /// The six column labels, once — the band, the cards and their fields all
  /// read the same words.
  static const String validFromLabel = 'Valid from';
  static const String grainLabel = 'Grain';
  static const String targetLabel = 'Target';
  static const String noteLabel = 'Note';
  static const String enteredByLabel = 'Entered by';
  static const String enteredAtLabel = 'Entered at';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<KpiTargetsBloc>().state;
    return Scaffold(
      body: switch (state) {
        KpiTargetsLoading() => const SkeletonList(maxWidth: KpiTargetsScreen.maxWidth),
        KpiTargetsUnavailable(message: final message) => PlatformFailureState(
            key: KpiTargetsScreen.failedKey,
            title: l10n.kpiTargetsTheTargetsCouldNotBeRead,
            message: message,
            retryKey: KpiTargetsScreen.retryKey,
            onRetry: () => context.read<KpiTargetsBloc>().add(KpiTargetsStarted(kpiId: kpiId)),
          ),
        KpiTargetsLoaded() => _Loaded(state: state, canWrite: canWrite),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.canWrite});

  final KpiTargetsLoaded state;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kpi = state.targets.kpi;
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final dense = AppTypography.dense(context);
    final history = state.targets.history;
    return Center(
      child: AppPageFrame(
        maxWidth: KpiTargetsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: KpiTargetsScreen.backKey,
                onPressed: () => context.go(Routes.kpi),
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.navKpiCatalogue),
              ),
            ),
            KeyedSubtree(
              key: KpiTargetsScreen.headerKey,
              child: AppPageHeader(
                title: '${kpi.kpi} · ${kpi.title}',
                description: l10n.kpiTargetsKpiTargets(kpi.direction, kpi.unit).trim(),
                actions: [
                  if (canWrite)
                    FilledButton.icon(
                      key: KpiTargetsScreen.changeTargetKey,
                      onPressed: () => ChangeTargetDialog.open(context, siteToday: state.siteToday),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: Text(l10n.commonChangeTarget),
                    ),
                ],
                below: state.sites.length > 1
                    ? SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<String>(
                          key: KpiTargetsScreen.siteKey,
                          initialValue: state.siteId,
                          isDense: true,
                          decoration: InputDecoration(
                              labelText: l10n.commonSite, border: OutlineInputBorder()),
                          items: [
                            for (final site in state.sites)
                              DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                          ],
                          onChanged: (siteId) {
                            if (siteId == null) return;
                            context.read<KpiTargetsBloc>().add(KpiTargetsSiteSelected(siteId));
                          },
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            _SectionLabel(
              title: l10n.kpiTargetsCurrentlyInForce,
              caption: l10n.kpiTargetsWhatEachGrainIsJudgedAgainstToday,
              captionStyle: muted,
            ),
            const SizedBox(height: Spacing.sm),
            if (state.targets.current.isEmpty)
              Text(l10n.kpiTargetsNoTargetIsInForceToday, key: KpiTargetsScreen.currentKey, style: muted)
            else
              Column(
                key: KpiTargetsScreen.currentKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppListCard(
                    rows: [
                      for (final entry in state.targets.current)
                        Padding(
                          key: KpiTargetsScreen.currentRowKey(entry.grain),
                          padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: Spacing.xs),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.kpiTargetsFrom(entry.grain, formatTarget(kpi, entry.target), entry.validFrom),
                              style: dense,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: Spacing.lg),
            _SectionLabel(
              title: l10n.kpiTargetsHistory,
              caption: l10n.kpiTargetsNewestFirstAnEntryIsNeverEdited,
              captionStyle: muted,
            ),
            const SizedBox(height: Spacing.sm),
            if (history.isEmpty)
              PlatformEmptyState.noneExist(
                key: KpiTargetsScreen.emptyKey,
                title: l10n.kpiTargetsNoTargetHasBeenSet,
                message: l10n.kpiTargetsEveryEntryMadeForThisKpiWill,
                icon: Icons.flag_outlined,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final table = constraints.maxWidth >=
                      AppBreakpoints.effective(context, KpiTargetsScreen.tableWidth);
                  final rows = [
                    for (final entry in history) _HistoryRow(entry: entry, kpi: kpi),
                  ];
                  if (!table) {
                    return Column(
                      key: KpiTargetsScreen.historyKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < rows.length; index++) ...[
                          if (index > 0) const SizedBox(height: Spacing.sm),
                          _HistoryCard(entry: history[index], kpi: kpi),
                        ],
                      ],
                    );
                  }
                  return Column(
                    key: KpiTargetsScreen.historyKey,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppTableHeader(columns: _columns),
                      ...rows,
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A section's own name over its block, with a line of context under it. It is
/// `titleSmall` at w600 — 14px, the Dense body's own size, so no heading here
/// outgrows the text it heads (#367's 1.3x rule) — and sentence case, never
/// uppercased: uppercase is the Shell's Destination-group device.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.caption, this.captionStyle});

  final String title;
  final String caption;
  final TextStyle? captionStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(caption, style: captionStyle),
      ],
    );
  }
}

const int _fromFlex = 2;
const int _grainFlex = 2;
const int _targetFlex = 2;
const int _noteFlex = 3;
const int _byFlex = 2;
// A stamp is `YYYY-MM-DD HH:MM`, the longest fixed value in the ledger: two
// flexes of 868px of content is 130px, which 14px tabular figures just fill, so
// the stamp wrapped to two lines and made every row 48 instead of 32. Three
// flexes hold it on one line (issue #395).
const int _atFlex = 3;

/// The one column spec the band and every table row are built from, so a label
/// and its cells start (or end) on the same edge by construction.
const List<AppTableColumn> _columns = [
  AppTableColumn(KpiTargetsScreen.validFromLabel, flex: _fromFlex),
  AppTableColumn(KpiTargetsScreen.grainLabel, flex: _grainFlex),
  AppTableColumn(KpiTargetsScreen.targetLabel, flex: _targetFlex, align: AppColumnAlign.end),
  AppTableColumn(KpiTargetsScreen.noteLabel, flex: _noteFlex),
  AppTableColumn(KpiTargetsScreen.enteredByLabel, flex: _byFlex),
  AppTableColumn(KpiTargetsScreen.enteredAtLabel, flex: _atFlex, align: AppColumnAlign.end),
];

/// The value of one field of one entry, formatted once so the table row and the
/// card below the breakpoint can never disagree about what an entry says.
class _EntryValues {
  _EntryValues(this.entry, KpiSummary kpi)
      : target = entry.target == null ? 'No target' : formatTarget(kpi, entry.target!),
        note = (entry.note == null || entry.note!.isEmpty) ? '—' : entry.note!,
        by = entry.appUser ?? entry.enteredBy ?? '—',
        at = entry.enteredAt == null ? '—' : formatEnteredAt(entry.enteredAt!);

  final KpiHistoryEntry entry;
  final String target;
  final String note;
  final String by;
  final String at;

  List<String> get values => [entry.validFrom, entry.grain, target, note, by, at];
}

/// One entry of the history, as a register row: six labelled columns.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.kpi});

  final KpiHistoryEntry entry;
  final KpiSummary kpi;

  @override
  Widget build(BuildContext context) {
    final values = _EntryValues(entry, kpi);
    final dense = AppTypography.dense(context);
    final number = AppTableRow.numberStyle(context);
    final muted = dense?.copyWith(color: AppColors.of(context).textMuted);
    return AppTableRow(
      key: KpiTargetsScreen.historyRowKey(entry.targetId),
      columns: _columns,
      cells: [
        Text(values.entry.validFrom, style: muted),
        Text(values.entry.grain, style: dense),
        Text(values.target, style: number),
        Text(values.note, style: dense),
        Text(values.by, style: dense),
        Text(values.at, style: number),
      ],
    );
  }
}

/// One entry of the history, as a card: the same six fields, each labelled,
/// for a box too narrow to hold six columns without ellipsising a label.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.kpi});

  final KpiHistoryEntry entry;
  final KpiSummary kpi;

  @override
  Widget build(BuildContext context) {
    final values = _EntryValues(entry, kpi);
    final dense = AppTypography.dense(context);
    final floor = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final labels = [
      KpiTargetsScreen.validFromLabel,
      KpiTargetsScreen.grainLabel,
      KpiTargetsScreen.targetLabel,
      KpiTargetsScreen.noteLabel,
      KpiTargetsScreen.enteredByLabel,
      KpiTargetsScreen.enteredAtLabel,
    ];
    return Card(
      key: KpiTargetsScreen.historyCardKey(entry.targetId),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < labels.length; index++)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : Spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One label width for all six, so the values line up as a
                    // column of their own inside the card.
                    SizedBox(
                      width: 88,
                      child: Text(labels[index], style: floor),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: Text(values.values[index], style: dense)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
