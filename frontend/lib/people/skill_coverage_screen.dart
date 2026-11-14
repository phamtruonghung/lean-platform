/// A Site's skill coverage (issue #89, AC6): where the plant is short against
/// the skill requirements it has set for itself. Administrator only —
/// `GET /api/people/sites/:siteId/skill-coverage` is deliberately narrower
/// than every other Site-shaped read in this Module (skill-routes.js's own
/// header), so this Screen carries the same per-Screen access check
/// `AccountsScreen`/`ApprovalQueueScreen` already get at the router, not
/// merely an omission from the sidebar.
///
/// Already filtered to a real shortfall server-side (`SkillCoverageEntry`'s
/// own header) — every row this Screen shows is thin by construction, so
/// there is no "met" row to distinguish from a thin one here.
///
/// **A register, read across, at the grain the server answers at (issue #394).**
/// A coverage report is a matrix: what the Org Unit requires against what it
/// holds. The wire's grain is one row per Org Unit × skill (`getSiteSkillCoverage`
/// in skills.js aggregates the requirement and the holders, and there is no
/// person-by-skill coverage read anywhere in the API), so the columns are the
/// requirement, the qualified headcount, the lapsed headcount and the
/// shortfall — one band above the rows, so the numbers line up down the page
/// and a reader compares them instead of reading nine unlabelled sentences at
/// a 900px window. A person-by-skill matrix would need a read this API does not
/// have; inventing one here would be a business decision, not a layout.
///
/// **The shortfall carries a tone, and the tone carries a legend.** A shortfall
/// is not one severity: an Org Unit with nobody qualified for a skill it says it
/// needs is a different fact from one that is short with some of the
/// requirement met, and both are already in the payload (`qualifiedHeadcount` is
/// zero or it is not). So the `StatusChip` is `danger` for the first and
/// `warning` for the second, and a legend above the register names the tones the
/// rows actually paint — built from those rows, never a fixed five-chip list
/// (`docs/design-language.md` §13).
///
/// **Below [AppBreakpoints.registerTable] of box width it is a card per
/// requirement.** The card states the same two sentences it always stated —
/// "`Line 1 · Welding`" and "Needs 2 at level 1+, 0 qualified, 2 lapsed" — so
/// the narrow shape loses no reading, and the band's columns are the only thing
/// that arrives with the wide one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'skill.dart';
import 'skill_coverage_bloc.dart';
import '../l10n/vocabulary.dart';

class SkillCoverageScreen extends StatelessWidget {
  const SkillCoverageScreen({super.key});

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 760, one of five numbers six catalogue Screens each picked for themselves.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> siteKey = ValueKey<String>('skill-coverage-site');
  static const ValueKey<String> failedKey = ValueKey<String>('skill-coverage-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('skill-coverage-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('skill-coverage-empty');
  static ValueKey<String> rowKey(String orgUnitId, String skillId) =>
      ValueKey<String>('skill-coverage-row-$orgUnitId-$skillId');

  /// The register's own parts, so a test can name what it measures.
  static const ValueKey<String> legendKey = ValueKey<String>('skill-coverage-legend');
  static const ValueKey<String> loadedKey = ValueKey<String>('skill-coverage-loaded');
  static ValueKey<String> cardKey(String orgUnitId, String skillId) =>
      ValueKey<String>('skill-coverage-card-$orgUnitId-$skillId');
  static ValueKey<String> shortfallKey(String orgUnitId, String skillId) =>
      ValueKey<String>('skill-coverage-shortfall-$orgUnitId-$skillId');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'skill-coverage-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's shortfalls renders — a
  /// different fact from [emptyKey] ("every requirement is met"): a Site can
  /// be short somewhere and still have nothing matching what was typed.
  static const ValueKey<String> noMatchKey = ValueKey<String>('skill-coverage-no-match');

  /// The band, stated once: the rows and the labels are built from it, so a
  /// label and its cells start at the same x by construction
  /// (`docs/frontend-layout.md` §4).
  static List<AppTableColumn> columns(AppLocalizations l10n) => <AppTableColumn>[
    AppTableColumn(l10n.skillCoverageOrgUnitAndSkill, flex: 5),
    AppTableColumn(l10n.skillCoverageRequired, flex: 3),
    AppTableColumn(l10n.skillCoverageQualified, flex: 2, align: AppColumnAlign.end),
    AppTableColumn(l10n.skillCoverageLapsed, flex: 2, align: AppColumnAlign.end),
    AppTableColumn(l10n.skillCoverageShortfall, width: 128),
  ];

  /// What a row's shortfall means, in the payload's own terms: nobody qualified
  /// for a requirement the Org Unit set is the worse of the two facts.
  static StatusTone toneOf(SkillCoverageEntry entry) =>
      entry.qualifiedHeadcount == 0 ? StatusTone.danger : StatusTone.warning;

  /// The legend's own words for the tones the register paints — the tone's
  /// meaning, while the cell keeps the record's own words ("Short 2").
  static String legendLabel(AppLocalizations l10n, StatusTone tone) =>
      skillCoverageLegendLabel(l10n, tone);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<SkillCoverageBloc>().state;

    return Scaffold(
      body: switch (state) {
        // The generalised loading placeholder (issue #103) replaces the bare
        // spinner this Screen used before.
        SkillCoverageLoading() => const SkeletonList(maxWidth: SkillCoverageScreen.maxWidth),
        SkillCoverageUnavailable(message: final message) => PlatformFailureState(
            key: SkillCoverageScreen.failedKey,
            title: l10n.skillCoverageSkillCoverageCouldNotBeRead,
            message: message,
            retryKey: SkillCoverageScreen.retryKey,
            onRetry: () => context.read<SkillCoverageBloc>().add(const SkillCoverageStarted()),
          ),
        SkillCoverageLoaded() => _Loaded(state: state),
      },
    );
  }
}

/// The report's loaded view. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state});

  final SkillCoverageLoaded state;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the shortfalls to, `''` when nothing is.
  String _term = '';

  /// Whether [entry] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the names that identify a shortfall —
  /// the Org Unit that is short and the skill it is short of (their codes
  /// included, since that is how a plan is read in a spreadsheet). No ranking
  /// and no fuzzy matching, the same rule the assign dialog's own filter uses
  /// (issue #187).
  static bool _matches(SkillCoverageEntry entry, String term) =>
      entry.orgUnitName.toLowerCase().contains(term) ||
      entry.orgUnitCode.toLowerCase().contains(term) ||
      entry.skillName.toLowerCase().contains(term) ||
      entry.skillCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<SkillCoverageEntry> get _matchingEntries {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.entries;
    return widget.state.entries
        .where((entry) => _matches(entry, term))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingEntries;
    return Center(
      child: AppPageFrame(
        maxWidth: SkillCoverageScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navSkillCoverage,
              description: l10n.skillCoverageWhereThisSiteFallsShortOfIts,
              below: state.sites.length > 1
                  ? SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: SkillCoverageScreen.siteKey,
                        initialValue: state.siteId,
                        isDense: true,
                        decoration:
                            InputDecoration(labelText: l10n.commonSite, border: OutlineInputBorder()),
                        items: [
                          for (final site in state.sites)
                            DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                        ],
                        onChanged: (siteId) {
                          if (siteId == null) return;
                          context.read<SkillCoverageBloc>().add(SkillCoverageSiteSelected(siteId));
                        },
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            if (state.isLoadingCoverage)
              // `SkeletonList` scrolls its own rows, so inside this page's
              // `ListView` it is given a bounded height rather than an unbounded
              // one. It was handed an unbounded one until #394 and threw
              // "Vertical viewport was given unbounded height" on every Site
              // switch, before the real rows arrived in the same place.
              const SizedBox(
                height: _skeletonHeight,
                child: SkeletonList(rows: 3, maxWidth: SkillCoverageScreen.maxWidth),
              )
            else if (state.entries.isEmpty)
              // Good news, not a gap to fill — this read is already
              // filtered to a real shortfall server-side (`SkillCoverageEntry`'s
              // own header), so an empty result means every requirement is
              // met, not that nobody has entered anything yet. No action to
              // carry either way: there is nothing here for a caller to
              // create, and no filter to clear (issue #103).
              PlatformEmptyState.noneExist(
                key: SkillCoverageScreen.emptyKey,
                title: l10n.skillCoverageEveryRequirementIsMet,
                message: l10n.skillCoverageThisSiteHasNoShortfallAgainstThe,
                icon: Icons.task_alt_outlined,
              )
            else ..._body(context, matches),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, List<SkillCoverageEntry> matches) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    return [
      // A filter box over a Site with no shortfall would be a control
      // that can do nothing, so it appears with the rows — and stays
      // while a term excludes them all, because the reader still has
      // to be able to clear it.
      AppFilterField(
        name: SkillCoverageScreen.filterFieldName,
        label: l10n.skillCoverageFilterSkillCoverage,
        helperText: l10n.skillCoverageByOrgUnitOrSkill,
        term: _term,
        onChanged: (term) => setState(() => _term = term),
        shown: matches.length,
        total: state.entries.length,
      ),
      const SizedBox(height: Spacing.md),
      if (matches.isEmpty)
        PlatformEmptyState.noneMatched(
          key: SkillCoverageScreen.noMatchKey,
          title: l10n.skillCoverageNoShortfallsMatch,
          message: l10n.skillCoverageThisSiteIsShortSomewhereButNothing(_term.trim()),
        )
      else ...[
        _Legend(entries: matches),
        const SizedBox(height: Spacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // The box this register is handed, at the reader's text size (§10):
            // cards below it, the band above it.
            final wide = constraints.maxWidth >=
                AppBreakpoints.effective(context, AppBreakpoints.registerTable);
            if (!wide) {
              return AppListCard(
                key: SkillCoverageScreen.loadedKey,
                rows: [for (final entry in matches) _CoverageCard(entry: entry)],
              );
            }
            return Card(
              key: SkillCoverageScreen.loadedKey,
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTableHeader(columns: SkillCoverageScreen.columns(l10n)),
                  for (final entry in matches) _CoverageRow(entry: entry),
                ],
              ),
            );
          },
        ),
      ],
    ];
  }
}

/// The height a bounded loading placeholder is given inside the page's list:
/// three of `SkeletonList`'s own rows, so the ghost is the shape of what
/// arrives and the page does not jump when it does.
const double _skeletonHeight = 288;

/// One row of the register: the same five columns as the band, cell for cell.
class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.entry});

  final SkillCoverageEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final number = AppTableRow.numberStyle(context);
    final dense = AppTypography.dense(context);
    final id = SkillCoverageScreen.rowKey(entry.orgUnitId, entry.skillId);
    return AppTableRow(
      key: id,
      columns: SkillCoverageScreen.columns(l10n),
      cells: [
        DisclosingText(
          '${entry.orgUnitName} · ${entry.skillName}',
          style: dense?.copyWith(color: palette.textPrimary),
        ),
        DisclosingText(
          l10n.skillCoverageNeedsAtLevel(
            entry.minimumQualifiedHeadcount,
            entry.minimumLevel,
          ),
          style: dense?.copyWith(color: palette.textMuted),
        ),
        Text('${entry.qualifiedHeadcount}', style: number),
        Text('${entry.expiredHeadcount}', style: number),
        Align(
          alignment: Alignment.centerLeft,
          child: _ShortfallChip(entry: entry),
        ),
      ],
    );
  }
}

/// One requirement below the register's breakpoint: the two sentences this
/// Screen has always shown, and the same chip.
class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.entry});

  final SkillCoverageEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return Padding(
      key: SkillCoverageScreen.cardKey(entry.orgUnitId, entry.skillId),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.orgUnitName} · ${entry.skillName}',
                  style: AppTypography.dense(context)?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  l10n.skillCoverageNeedsAtLevelQualifiedLapsed(
                    entry.minimumQualifiedHeadcount,
                    entry.minimumLevel,
                    entry.qualifiedHeadcount,
                    entry.expiredHeadcount,
                  ),
                  style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          _ShortfallChip(entry: entry),
        ],
      ),
    );
  }
}

/// The shortfall, in the record's own words, painted with the tone its own
/// counts carry.
class _ShortfallChip extends StatelessWidget {
  const _ShortfallChip({required this.entry});

  final SkillCoverageEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StatusChip(
      key: SkillCoverageScreen.shortfallKey(entry.orgUnitId, entry.skillId),
      label: l10n.skillCoverageShort(entry.shortfall),
      tone: SkillCoverageScreen.toneOf(entry),
    );
  }
}

/// What the register's colours mean, built from the tones its rows paint
/// (`docs/design-language.md` §13): a Site whose shortfalls are all "nobody
/// qualified" shows one chip, not a five-chip list naming tones nothing paints.
class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<SkillCoverageEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tones = <StatusTone>{
      for (final entry in entries) SkillCoverageScreen.toneOf(entry),
    }.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Wrap(
      key: SkillCoverageScreen.legendKey,
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tone in tones)
          StatusChip(label: SkillCoverageScreen.legendLabel(AppLocalizations.of(context), tone), tone: tone),
      ],
    );
  }
}
