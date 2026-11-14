/// The Safety incident register (issue #226, CONTEXT.md's **Safety
/// incident**): what went wrong at this Site, where it happened, and where it
/// sits on the severity ladder.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants —
/// the same rule the Non-conformance register, the Work order list, the
/// Asset register and the action log already follow (#55, ADR-0009,
/// ADR-0032). Recording is offered to everyone too: the server is the real
/// gate on where one may be recorded (a write Grant reaching that Org Unit,
/// or the administrator role).
///
/// **A register of six columns above [AppBreakpoints.registerTable] of box, a
/// card per record below it** (issue #391, `docs/design-language.md` §10). The
/// table is what makes the register scannable at the density the reference
/// board sets: severity and state are `StatusChip`s in measured columns so a
/// column of rungs compares by eye, and the four text columns disclose what
/// they clip. Below the breakpoint the same record renders as a card, because
/// six columns in a phone-width box is a row nobody can read. The breakpoint is
/// read from the box a `LayoutBuilder` hands the list, never from the window,
/// and is multiplied by the reader's text scale — at twice the text the table
/// needs twice the box, so it falls back to cards on a screen that held it at
/// 100% (WCAG 1.4.4; the defect behind #379 and #381).
///
/// **Severity leads and status ends.** The two chips are the column a reader
/// scans for, so the rung is the first column and the state the last, and each
/// is sized from its own longest label at the reader's text scale rather than
/// left to flex — a chip column that moves with the window would put the same
/// rung at a different x on every page.
///
/// **The Site, the Org Unit and the six narrowing controls are one toolbar
/// row** (`AppToolbar`), not a hand-rolled `Wrap`: the filters lead, the count
/// of what they narrowed to follows, and the row wraps into a column when the
/// box cannot hold it instead of squeezing the controls.
///
/// **The empty register is good news, and must not be celebrated.** A plant
/// with no recorded incidents may simply not be reporting, which is the exact
/// failure ADR-0036 trades against — so the copy is flat, never "All clear".
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
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
import 'safety_incident.dart';
import 'safety_incidents_bloc.dart';
import 'safety_org_unit_filter_dialog.dart';
import '../l10n/vocabulary.dart';

class SafetyIncidentsScreen extends StatelessWidget {
  const SafetyIncidentsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('safety-incidents-record');
  static const ValueKey<String> siteKey = ValueKey<String>('safety-incidents-site');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('safety-incidents-filter-org-unit');
  static const ValueKey<String> statusFilterKey =
      ValueKey<String>('safety-incidents-filter-status');
  static const ValueKey<String> typeFilterKey = ValueKey<String>('safety-incidents-filter-type');
  static const ValueKey<String> severityFilterKey =
      ValueKey<String>('safety-incidents-filter-severity');
  static const ValueKey<String> recordableFilterKey =
      ValueKey<String>('safety-incidents-filter-recordable');
  static const ValueKey<String> fromDateKey = ValueKey<String>('safety-incidents-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('safety-incidents-filter-to');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('safety-incidents-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('safety-incidents-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('safety-incidents-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('safety-incidents-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('safety-incidents-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-incidents-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-incidents-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('safety-incidents-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('safety-incidents-form-loading');

  /// The register's two shapes, named so a test can tell which one it is
  /// looking at without counting `AppTableRow`s or `Card`s.
  static const ValueKey<String> tableKey = ValueKey<String>('safety-incidents-table');
  static const ValueKey<String> cardsKey = ValueKey<String>('safety-incidents-cards');
  static const ValueKey<String> countKey = ValueKey<String>('safety-incidents-count');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('safety-incident-row-$id');
  static ValueKey<String> rowStatusKey(String id) =>
      ValueKey<String>('safety-incident-status-$id');
  static ValueKey<String> rowSeverityKey(String id) =>
      ValueKey<String>('safety-incident-severity-$id');
  static ValueKey<String> rowFiledKey(String id) => ValueKey<String>('safety-incident-filed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyIncidentsBloc>().state;
    final l10n = AppLocalizations.of(context);

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SafetyIncidentsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SafetyIncidentsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: l10n.safetyIncidentsUnavailableTitle,
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsStarted()),
                  ),
                SafetyIncidentsLoaded(siteId: null) => PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: l10n.commonNoSiteTitle,
                    message: l10n.commonNoSiteMessage,
                    icon: Icons.factory_outlined,
                  ),
                SafetyIncidentsLoaded(incidents: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SafetyIncidentsLoaded(incidents: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SafetyIncidentsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered — the same
/// reasoning `NonconformancesScreen`'s own `_RefreshOnMount` carries (issue
/// #183).
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
      context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SafetyIncidentsState state;

  @override
  Widget build(BuildContext context) {
    final loaded = state is SafetyIncidentsLoaded ? state as SafetyIncidentsLoaded : null;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
        child: Padding(
          // One inset, so the title, the first filter and the first row share
          // one left edge (`docs/frontend-layout.md` §1).
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.titleSafetyIncidents,
            description: l10n.safetyIncidentsDescription,
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: SafetyIncidentsScreen.recordKey,
                  onPressed: loaded.isRecording || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.safetyIncidents}/record'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.safetyIncidentRecord),
                ),
            ],
            below: loaded == null ? null : _Filters(loaded: loaded),
          ),
        ),
      ),
    );
  }
}

/// The Site chooser, the Org Unit filter, the six narrowing controls and the
/// count, in one [AppToolbar]. Each filter is a read filter over an
/// already-visible list, so each sends a request rather than hiding rows the
/// client happens to hold.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final SafetyIncidentsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final filters = loaded.filters;

    return AppToolbar(
      filters: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: AppLayout.atTextScale(context, 200),
            child: DropdownButtonFormField<String>(
              key: SafetyIncidentsScreen.siteKey,
              initialValue: loaded.siteId,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonSite,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final site in loaded.sites)
                  DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
              ],
              onChanged: (siteId) {
                if (siteId == null) return;
                context.read<SafetyIncidentsBloc>().add(SafetyIncidentsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SafetyIncidentsScreen.orgUnitFilterKey,
          onPressed: () => SafetyOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? l10n.commonAllOrgUnits),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 170),
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.commonStatus,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(l10n.nonconformancesAnyStatus)),
              for (final status in SafetyIncidentStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(safetyIncidentStatusLabel(l10n, status)),
                ),
            ],
            onChanged: (status) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsStatusFilterChanged(status)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 190),
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.typeFilterKey,
            initialValue: filters.incidentType,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.safetyIncidentType,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(l10n.safetyAnyType)),
              for (final type in IncidentType.values)
                DropdownMenuItem<String?>(value: type, child: Text(safetyIncidentTypeLabel(l10n, type))),
            ],
            onChanged: (type) =>
                context.read<SafetyIncidentsBloc>().add(SafetyIncidentsTypeFilterChanged(type)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 190),
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.severityFilterKey,
            initialValue: filters.severityLevel,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.commonSeverity,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.nonconformancesAnySeverity),
              ),
              // Ladder order, never alphabetical (the binding design comment
              // on #223) — the same order the record form's own dropdown
              // renders.
              for (final level in SeverityLevel.values)
                DropdownMenuItem<String?>(
                  value: level,
                  child: Text(safetySeverityLabel(l10n, level)),
                ),
            ],
            onChanged: (level) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsSeverityFilterChanged(level)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 170),
          child: DropdownButtonFormField<bool?>(
            key: SafetyIncidentsScreen.recordableFilterKey,
            initialValue: filters.isRecordable,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.safetyRecordable,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<bool?>(value: null, child: Text(l10n.commonAny)),
              DropdownMenuItem<bool?>(value: true, child: Text(l10n.safetyRecordable)),
              DropdownMenuItem<bool?>(value: false, child: Text(l10n.safetyNotRecordable)),
            ],
            onChanged: (value) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsRecordableFilterChanged(value)),
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
              width: AppLayout.atTextScale(context, 165),
              child: AppDateField(
                key: SafetyIncidentsScreen.fromDateKey,
                name: 'safety-incidents-from',
                label: l10n.safetyOccurredFrom,
                value: filters.from,
                optional: true,
                onChanged: (value) => context
                    .read<SafetyIncidentsBloc>()
                    .add(SafetyIncidentsDateRangeChanged(from: value, clearFrom: value == null)),
              ),
            ),
            SizedBox(
              width: AppLayout.atTextScale(context, 165),
              child: AppDateField(
                key: SafetyIncidentsScreen.toDateKey,
                name: 'safety-incidents-to',
                label: l10n.safetyOccurredTo,
                value: filters.to,
                optional: true,
                onChanged: (value) => context
                    .read<SafetyIncidentsBloc>()
                    .add(SafetyIncidentsDateRangeChanged(to: value, clearTo: value == null)),
              ),
            ),
          ],
        ),
        if (filters.isSet)
          TextButton(
            key: SafetyIncidentsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsFiltersCleared()),
            child: Text(l10n.workOrdersClearFilters, style: theme.textTheme.bodyMedium),
          ),
      ],
      count: Text(
        loaded.incidents.length == 1
            ? l10n.incidents1SafetyIncident
            : l10n.incidentsSafetyIncidents(loaded.incidents.length),
        key: SafetyIncidentsScreen.countKey,
        style: AppTypography.dense(context)?.copyWith(
          color: AppColors.of(context).textMuted,
        ),
      ),
    );
  }
}

/// The register was capped — said out loud rather than left to be inferred,
/// the same rule `NonconformancesScreen`'s own `_Truncated` follows
/// (ADR-0026).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
        child: Padding(
          key: SafetyIncidentsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            l10n.safetyIncidentsTruncated,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103, and the binding design comment
/// on #223): a Site with no incidents recorded is good news that must not be
/// celebrated, and a filter that matched nothing is a filter to clear.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: SafetyIncidentsScreen.emptyMatchedKey,
        title: l10n.nonconformancesNoMatchTitle,
        message: l10n.safetyIncidentsNoMatchMessage,
        actionLabel: l10n.nonconformancesClearTheFilters,
        actionKey: SafetyIncidentsScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsFiltersCleared()),
      );
    }
    // Flat, deliberately — never "All clear". A plant with no incidents may
    // simply not be reporting, which is the exact failure ADR-0036 trades
    // against.
    return PlatformEmptyState.noneExist(
      key: SafetyIncidentsScreen.emptyKey,
      title: l10n.safetyIncidentsNoneTitle,
      message: l10n.safetyIncidentsNoneMessage,
      icon: Icons.health_and_safety_outlined,
    );
  }
}

/// The register's one column spec: [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a header label and its cells start at the same x.
///
/// The two chip columns state a measured `width` rather than a `flex`: a rung
/// or a state is bounded content, and a column that took a share of the window
/// would move the same value's x on two Screens. The three text columns flex,
/// and disclose what they clip.
///
/// `Incident #` is measured for the same reason, one step further: the number
/// is a fixed-shape code, so a share of the flex let the identifier be the one
/// value that clipped — `SI-HCM-2026-000…` at every window under 1440, which is
/// a reader unable to tell `00001` from `00002`. It is the same measurement
/// `quality/complaints_screen.dart` makes for a complaint number.
List<AppTableColumn> _columns(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return [
    AppTableColumn(l10n.commonSeverity, width: _severityColumnWidth(context)),
    AppTableColumn(l10n.safetyIncidentNumberColumn, width: _incidentNumberColumnWidth(context)),
    AppTableColumn(l10n.commonType, flex: 3),
    AppTableColumn(l10n.commonOrgUnit, flex: 2),
    AppTableColumn(l10n.commonFiledAgainstColumn, flex: 3),
    AppTableColumn(l10n.commonStatus, width: _statusColumnWidth(context)),
  ];
}

/// The Incident # column: the documented number format —
/// `SI-HCM-2026-00001` (`safety-incidents.js`'s own header: a Site-scoped,
/// year-stamped, zero-padded sequence) — in the cell's own style at the
/// reader's text scale, plus the slot's gutter. The cell renders it `dense` and
/// semi-bold, so that is what is measured, never a default style.
double _incidentNumberColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final painter = TextPainter(
    text: TextSpan(
      text: l10n.incidentsSiHcm202600001,
      style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.sm + 8;
}

/// The Severity column's width: the widest rung label in a compact `Chip`'s own
/// label style at the reader's text scale, plus the chip's padding and the
/// slot's gutter.
double _chipColumnWidth(BuildContext context, Iterable<String> labels) {
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

double _severityColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _chipColumnWidth(context, [
    for (final level in SeverityLevel.values) safetySeverityLabel(l10n, level),
  ]);
}

double _statusColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _chipColumnWidth(context, [
    for (final status in SafetyIncidentStatus.values) safetyIncidentStatusLabel(l10n, status),
  ]);
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SafetyIncident> rows;

  @override
  Widget build(BuildContext context) {
    final columns = _columns(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
        child: LayoutBuilder(
          builder: (context, box) {
            // The box this list was handed — the page less the Shell's rail and
            // this frame — never the window (the lesson of #105), and scaled by
            // the reader's text size (WCAG 1.4.4): six columns at twice the
            // text need twice the box before they read.
            final table =
                box.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.registerTable);
            if (!table) {
              return ListView.builder(
                key: SafetyIncidentsScreen.cardsKey,
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                itemCount: rows.length,
                itemBuilder: (context, index) => _SafetyIncidentCard(incident: rows[index]),
              );
            }
            return ListView(
              key: SafetyIncidentsScreen.tableKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  // The band's own fill would otherwise square off the card's
                  // rounded corners.
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTableHeader(columns: columns),
                      for (final row in rows) _SafetyIncidentTableRow(columns: columns, incident: row),
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

/// One Safety incident as a row of the table. The whole row opens the record,
/// so it is [AppTouchTarget.min] tall and carries a focus ring — a row a
/// keyboard cannot reach would make the register unreadable without a pointer.
class _SafetyIncidentTableRow extends StatelessWidget {
  const _SafetyIncidentTableRow({required this.columns, required this.incident});

  final List<AppTableColumn> columns;
  final SafetyIncident incident;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);

    // The framework's own padded tap target is lifted on the chips: it would add
    // height to a row whose height is already the target.
    Widget shrinkWrapTargets(Widget child) => Theme(
          data: Theme.of(context)
              .copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: child,
        );

    return KeyedSubtree(
      key: SafetyIncidentsScreen.rowKey(incident.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.safetyIncidents}/${incident.id}'),
        cells: [
          shrinkWrapTargets(
            StatusChip(
              key: SafetyIncidentsScreen.rowSeverityKey(incident.id),
              label: incident.severityLabel(l10n),
              tone: incident.severityTone,
            ),
          ),
          DisclosingText(
            incident.incidentNo,
            style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
          ),
          DisclosingText(incident.incidentTypeLabel(l10n), style: dense),
          DisclosingText(incident.orgUnitName, style: muted),
          // Measured: this is the one cell that still clips in a table over a
          // 1280 window (183.2px needed; 63.9 at 960, 138.9 at 1160), so it is
          // the same disclosing cell its two neighbours are — the value is read
          // in full from the tooltip rather than lost to the ellipsis.
          DisclosingText(
            incident.filedAgainst,
            key: SafetyIncidentsScreen.rowFiledKey(incident.id),
            style: muted,
          ),
          shrinkWrapTargets(
            StatusChip(
              key: SafetyIncidentsScreen.rowStatusKey(incident.id),
              label: incident.statusLabel(l10n),
              tone: incident.statusTone,
            ),
          ),
        ],
      ),
    );
  }
}

/// One Safety incident as a card, below the table's breakpoint: the rung and
/// the number on the first line, what happened on the second, where and when on
/// the third, and the state at the card's own top-right corner.
///
/// Two chips, separated by role rather than stacked (the binding design comment
/// on #223): severity on the left, with the number, Org Unit and date — what
/// happened — and status on the right — what is being done about it.
class _SafetyIncidentCard extends StatelessWidget {
  const _SafetyIncidentCard({required this.incident});

  final SafetyIncident incident;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final dense = AppTypography.dense(context);
    final row = incident;

    return Card(
      key: SafetyIncidentsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('${Routes.safetyIncidents}/${row.id}'),
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
                          key: SafetyIncidentsScreen.rowSeverityKey(row.id),
                          label: row.severityLabel(l10n),
                          tone: row.severityTone,
                        ),
                        Text(
                          row.incidentNo,
                          style: dense?.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      row.incidentTypeLabel(l10n),
                      style: dense?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.commonFiledAgainst(row.orgUnitName, row.filedAgainst),
                      key: SafetyIncidentsScreen.rowFiledKey(row.id),
                      style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              StatusChip(
                key: SafetyIncidentsScreen.rowStatusKey(row.id),
                label: row.statusLabel(l10n),
                tone: row.statusTone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
