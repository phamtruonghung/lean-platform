/// The Safety observation register (issue #230, CONTEXT.md's **Safety
/// observation**): what was seen before anything went wrong at this Site,
/// where it happened, and how bad it could have been.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Safety incident register follows (#55, ADR-0009, ADR-0032).
/// Recording is offered to everyone too: the server is the real gate on where
/// one may be recorded (a write Grant reaching that Org Unit, or the
/// administrator role).
///
/// **Worst-first by severity potential** (the binding design comment on
/// #223) — the entire reason the field exists, so it is the register's
/// default order, never date. Severity potential paints as `fatal` ->
/// danger, `high` -> warning, `medium` -> info, `low` -> neutral, and
/// **stop-work is its own labelled badge, not a tone** — it is a fact about
/// what somebody did, not a state the observation is in. Because that badge is
/// the one thing a reader must not miss, it is a column of its own in the
/// table rather than a word inside another cell, and it keeps its own `Key` in
/// both shapes.
///
/// **A register of six columns above [AppBreakpoints.registerTable] of box, a
/// card per record below it** (issue #391, `docs/design-language.md` §10). The
/// breakpoint is measured on the box the list was handed — the page less the
/// Shell's rail and this frame — never on the window, and is multiplied by the
/// reader's text scale, so a table that read at 100% falls back to cards at
/// 200% rather than clipping (WCAG 1.4.4; #379, #381).
///
/// **The Site, the Org Unit and the seven narrowing controls are one toolbar
/// row** (`AppToolbar`): filters lead, the count of what they narrowed to
/// follows, and the row wraps into a column when the box cannot hold it.
///
/// **The empty register is bad news, unlike the incident register's.** A
/// leading indicator with nothing on it means nobody is walking, so the copy
/// says so rather than reading as good news the way an empty incident
/// register does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'safety_observation.dart';
import 'safety_observation_org_unit_filter_dialog.dart';
import 'safety_observations_bloc.dart';

class SafetyObservationsScreen extends StatelessWidget {
  const SafetyObservationsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('safety-observations-record');
  static const ValueKey<String> siteKey = ValueKey<String>('safety-observations-site');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('safety-observations-filter-org-unit');
  static const ValueKey<String> typeFilterKey =
      ValueKey<String>('safety-observations-filter-type');
  static const ValueKey<String> categoryFilterKey =
      ValueKey<String>('safety-observations-filter-category');
  static const ValueKey<String> severityPotentialFilterKey =
      ValueKey<String>('safety-observations-filter-severity-potential');
  static const ValueKey<String> stopWorkFilterKey =
      ValueKey<String>('safety-observations-filter-stop-work');
  static const ValueKey<String> hasActionFilterKey =
      ValueKey<String>('safety-observations-filter-has-action');
  static const ValueKey<String> fromDateKey = ValueKey<String>('safety-observations-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('safety-observations-filter-to');
  static const ValueKey<String> clearFiltersKey =
      ValueKey<String>('safety-observations-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('safety-observations-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('safety-observations-empty');
  static const ValueKey<String> emptyMatchedKey =
      ValueKey<String>('safety-observations-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('safety-observations-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-observations-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-observations-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('safety-observations-no-site');
  static const ValueKey<String> formLoadingKey =
      ValueKey<String>('safety-observations-form-loading');

  /// The register's two shapes and its count, named so a test can tell which
  /// one it is looking at without counting widgets.
  static const ValueKey<String> tableKey = ValueKey<String>('safety-observations-table');
  static const ValueKey<String> cardsKey = ValueKey<String>('safety-observations-cards');
  static const ValueKey<String> countKey = ValueKey<String>('safety-observations-count');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('safety-observation-row-$id');
  static ValueKey<String> rowPotentialKey(String id) =>
      ValueKey<String>('safety-observation-potential-$id');
  static ValueKey<String> rowStopWorkKey(String id) =>
      ValueKey<String>('safety-observation-stop-work-$id');
  static ValueKey<String> rowFiledKey(String id) =>
      ValueKey<String>('safety-observation-filed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyObservationsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SafetyObservationsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SafetyObservationsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The Safety observation register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<SafetyObservationsBloc>().add(const SafetyObservationsStarted()),
                  ),
                SafetyObservationsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                SafetyObservationsLoaded(observations: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SafetyObservationsLoaded(observations: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SafetyObservationsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered — the same
/// reasoning `SafetyIncidentsScreen`'s own `_RefreshOnMount` carries.
class _RefreshOnMount extends StatefulWidget {
  const _RefreshOnMount({required this.child});

  final Widget child;

  @override
  State<_RefreshOnMount> createState() => _RefreshOnMountState();
}

class _RefreshOnMountState extends State<_RefreshOnMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SafetyObservationsBloc>().add(const SafetyObservationsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SafetyObservationsState state;

  @override
  Widget build(BuildContext context) {
    final loaded = state is SafetyObservationsLoaded ? state as SafetyObservationsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: Padding(
          // One inset, so the title, the first filter and the first row share
          // one left edge (`docs/frontend-layout.md` §1).
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Safety observations',
            description:
                'What was seen before anything went wrong, ranked worst-first by the '
                'worst credible outcome.',
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: SafetyObservationsScreen.recordKey,
                  onPressed: loaded.isRecording || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.safetyObservations}/record'),
                  icon: const Icon(Icons.add),
                  label: const Text('Record an observation'),
                ),
            ],
            below: loaded == null ? null : _Filters(loaded: loaded),
          ),
        ),
      ),
    );
  }
}

/// The Site chooser, the Org Unit filter, the seven narrowing controls and the
/// count, in one [AppToolbar]. Each filter is a read filter over an
/// already-visible list, so each sends a request rather than hiding rows the
/// client happens to hold.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final SafetyObservationsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = loaded.filters;

    return AppToolbar(
      filters: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: SafetyObservationsScreen.siteKey,
              initialValue: loaded.siteId,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
              items: [
                for (final site in loaded.sites)
                  DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
              ],
              onChanged: (siteId) {
                if (siteId == null) return;
                context.read<SafetyObservationsBloc>().add(SafetyObservationsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SafetyObservationsScreen.orgUnitFilterKey,
          onPressed: () =>
              SafetyObservationOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.typeFilterKey,
            initialValue: filters.observationType,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any type')),
              for (final type in ObservationType.values)
                DropdownMenuItem<String?>(value: type, child: Text(ObservationType.label(type))),
            ],
            onChanged: (type) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsTypeFilterChanged(type)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.categoryFilterKey,
            initialValue: filters.category,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any category')),
              for (final category in ObservationCategory.values)
                DropdownMenuItem<String?>(
                  value: category,
                  child: Text(ObservationCategory.label(category)),
                ),
            ],
            onChanged: (category) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsCategoryFilterChanged(category)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.severityPotentialFilterKey,
            initialValue: filters.severityPotential,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Severity potential', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any potential')),
              // Worst-first order is the register's own order; the filter's
              // own dropdown renders `SeverityPotential.values`' ascending
              // order for the same reason the record form does — the picker
              // is a scan of "how bad could this be", not a scan of the list
              // it narrows.
              for (final potential in SeverityPotential.values)
                DropdownMenuItem<String?>(
                  value: potential,
                  child: Text(SeverityPotential.label(potential)),
                ),
            ],
            onChanged: (potential) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsSeverityPotentialFilterChanged(potential)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<bool?>(
            key: SafetyObservationsScreen.stopWorkFilterKey,
            initialValue: filters.isStopWork,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Stop-work', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Any')),
              DropdownMenuItem<bool?>(value: true, child: Text('Stop-work only')),
              DropdownMenuItem<bool?>(value: false, child: Text('Not stop-work')),
            ],
            onChanged: (value) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsStopWorkFilterChanged(value)),
          ),
        ),
        // Whether an Action has been raised from the observation (issue
        // #231) — `false` is a walk's own worklist, so its unanswered items
        // do not disappear into the register.
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<bool?>(
            key: SafetyObservationsScreen.hasActionFilterKey,
            initialValue: filters.hasAction,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Action', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Any')),
              DropdownMenuItem<bool?>(value: false, child: Text('No Action raised')),
              DropdownMenuItem<bool?>(value: true, child: Text('Action raised')),
            ],
            onChanged: (value) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsHasActionFilterChanged(value)),
          ),
        ),
        // The date range is one pair, side by side, and is the group a reader
        // changes together — so it is one entry in the toolbar's own filter
        // list and wraps as a unit.
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            SizedBox(
              width: 165,
              child: AppDateField(
                key: SafetyObservationsScreen.fromDateKey,
                name: 'safety-observations-from',
                label: 'Observed from',
                value: filters.from,
                optional: true,
                onChanged: (value) => context
                    .read<SafetyObservationsBloc>()
                    .add(SafetyObservationsDateRangeChanged(from: value, clearFrom: value == null)),
              ),
            ),
            SizedBox(
              width: 165,
              child: AppDateField(
                key: SafetyObservationsScreen.toDateKey,
                name: 'safety-observations-to',
                label: 'Observed to',
                value: filters.to,
                optional: true,
                onChanged: (value) => context
                    .read<SafetyObservationsBloc>()
                    .add(SafetyObservationsDateRangeChanged(to: value, clearTo: value == null)),
              ),
            ),
          ],
        ),
        if (filters.isSet)
          TextButton(
            key: SafetyObservationsScreen.clearFiltersKey,
            onPressed: () => context
                .read<SafetyObservationsBloc>()
                .add(const SafetyObservationsFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
      count: Text(
        loaded.observations.length == 1
            ? '1 Safety observation'
            : '${loaded.observations.length} Safety observations',
        key: SafetyObservationsScreen.countKey,
        style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textMuted),
      ),
    );
  }
}

/// The register was capped — said out loud rather than left to be inferred
/// (ADR-0026), the same rule `SafetyIncidentsScreen`'s own `_Truncated`
/// follows.
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: Padding(
          key: SafetyObservationsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Safety observations than this list shows. Narrow it by Org Unit, '
            'by type or by date to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart — the opposite of the incident register's
/// own pair (the binding design comment on #223): an observation register
/// with no rows is bad news, because the leading indicator being empty means
/// nobody is walking.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: SafetyObservationsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has Safety observations, but none of them is in the area, type, '
            'category, potential, stop-work or dates you picked.',
        actionLabel: 'Clear the filters',
        actionKey: SafetyObservationsScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<SafetyObservationsBloc>().add(const SafetyObservationsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: SafetyObservationsScreen.emptyKey,
      title: 'No observations recorded. The leading indicator is empty.',
      message: 'No Safety observation has been recorded at this Site for the area and dates '
          'shown.',
      icon: Icons.visibility_outlined,
    );
  }
}

/// The register's one column spec: [AppTableHeader] and every [AppTableRow] are
/// built from it, so a label and its cells start at the same x. The two chip
/// columns state a measured width; the three text columns flex and disclose
/// what they clip.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn('Potential', width: _chipColumnWidth(context, _potentialLabels)),
      const AppTableColumn('Type', flex: 2),
      const AppTableColumn('Category', flex: 3),
      const AppTableColumn('Org Unit', flex: 2),
      const AppTableColumn('Filed against', flex: 3),
      AppTableColumn('Stop-work', width: _chipColumnWidth(context, const ['Stop-work'])),
    ];

List<String> get _potentialLabels =>
    [for (final potential in SeverityPotential.values) SeverityPotential.label(potential)];

/// A chip column's width: the widest label in a compact `Chip`'s own label
/// style at the reader's text scale, plus the chip's padding and the slot's
/// gutter.
double _chipColumnWidth(BuildContext context, List<String> labels) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final label in labels) {
    painter.text = TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + Spacing.xxl + Spacing.sm;
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SafetyObservation> rows;

  @override
  Widget build(BuildContext context) {
    final columns = _columns(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: LayoutBuilder(
          builder: (context, box) {
            final table =
                box.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.registerTable);
            if (!table) {
              return ListView.builder(
                key: SafetyObservationsScreen.cardsKey,
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                itemCount: rows.length,
                itemBuilder: (context, index) => _SafetyObservationCard(observation: rows[index]),
              );
            }
            return ListView(
              key: SafetyObservationsScreen.tableKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTableHeader(columns: columns),
                      for (final row in rows)
                        _SafetyObservationTableRow(columns: columns, observation: row),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One Safety observation as a row of the table. The whole row opens the
/// record, so it is [AppTouchTarget.min] tall and carries a focus ring.
class _SafetyObservationTableRow extends StatelessWidget {
  const _SafetyObservationTableRow({required this.columns, required this.observation});

  final List<AppTableColumn> columns;
  final SafetyObservation observation;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);

    Widget shrinkWrapTargets(Widget child) => Theme(
          data: Theme.of(context)
              .copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: child,
        );

    return KeyedSubtree(
      key: SafetyObservationsScreen.rowKey(observation.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.safetyObservations}/${observation.id}'),
        cells: [
          shrinkWrapTargets(
            StatusChip(
              key: SafetyObservationsScreen.rowPotentialKey(observation.id),
              label: observation.severityPotentialLabel,
              tone: observation.severityPotentialTone,
            ),
          ),
          DisclosingText(observation.observationTypeLabel, style: dense),
          DisclosingText(
            observation.categoryLabel,
            style: dense?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          DisclosingText(observation.orgUnitName, style: muted),
          Text(
            observation.filedAgainst,
            key: SafetyObservationsScreen.rowFiledKey(observation.id),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          // Stop-work is a labelled badge, never a tone (the binding design
          // comment on #223) — it is a fact about what somebody did, not a
          // state the observation is in.
          if (observation.isStopWork)
            shrinkWrapTargets(
              Chip(
                key: SafetyObservationsScreen.rowStopWorkKey(observation.id),
                label: const Text('Stop-work'),
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// One Safety observation as a card, below the table's breakpoint.
class _SafetyObservationCard extends StatelessWidget {
  const _SafetyObservationCard({required this.observation});

  final SafetyObservation observation;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = observation;

    return Card(
      key: SafetyObservationsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('${Routes.safetyObservations}/${row.id}'),
        hoverColor: palette.rowHoverFill,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(
                          key: SafetyObservationsScreen.rowPotentialKey(row.id),
                          label: row.severityPotentialLabel,
                          tone: row.severityPotentialTone,
                        ),
                        // Stop-work is a labelled badge, never a tone (the
                        // binding design comment on #223).
                        if (row.isStopWork)
                          Chip(
                            key: SafetyObservationsScreen.rowStopWorkKey(row.id),
                            label: const Text('Stop-work'),
                            visualDensity: VisualDensity.compact,
                          ),
                        Text(
                          row.observationTypeLabel,
                          style: dense?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      row.categoryLabel,
                      style: dense?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      '${row.orgUnitName} · filed against ${row.filedAgainst}',
                      key: SafetyObservationsScreen.rowFiledKey(row.id),
                      style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
