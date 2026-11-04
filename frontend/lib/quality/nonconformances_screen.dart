/// The Non-conformance register (issue #205, CONTEXT.md's
/// **Non-conformance**): what has been found not to conform at this Site, how
/// much of it there is, and where it was found.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Work order list, the Asset register, the action log and the
/// tier board already follow (#55, ADR-0009, ADR-0032). Recording is offered
/// to everyone too: the server is the real gate on where one may be recorded
/// (a write Grant reaching that Org Unit), and hiding the button would gate an
/// address that answers a clean refusal with a sentence the caller can act on.
///
/// Every filter is a read filter over the already-visible register and sends a
/// request rather than hiding rows client-side, so a narrowed read is what the
/// server's own indexes and its ltree walk are for. The Org Unit filter
/// includes everything *beneath* the chosen area, which is the ticket's own
/// criterion and what "everything under Line 3" means in this Platform.
///
/// Nothing here is typed that has a known set (ADR-0023): the status, the
/// Defect code, the Product and the severity are chosen from what the server
/// offers, and the two ends of the date range are dates, not free text.
///
/// **A table of six columns above [narrowBreakpoint] of content width, a card
/// below it (issue #390).** The severity and the state are two chips in one
/// State column rather than two columns: they are read together ("critical,
/// contained" is one fact about a record, not two), and a six-column register
/// is what a 1280px window's 988px of box can hold. The number this Screen
/// states is 900 for that reason, measured from a `LayoutBuilder` and scaled by
/// the reader's text scale — at twice the text the same box is under 1800 and
/// the cards come back instead of six squeezed columns (design-language §10).
///
/// The three unbounded cells — what was found, the quantity, and where it was
/// filed — clip at a 1280px window and disclose it through `DisclosingText`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_org_unit_filter_dialog.dart';
import 'nonconformances_bloc.dart';
import 'slide_show_toggle.dart';

class NonconformancesScreen extends StatelessWidget {
  const NonconformancesScreen({super.key});

  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the register is
  /// a table of six columns; below it, one card per record. Read from the box
  /// the list is handed, never the window, and scaled by the reader's text size.
  static const double narrowBreakpoint = 900;

  static const ValueKey<String> recordKey = ValueKey<String>('nonconformances-record');
  static const ValueKey<String> siteKey = ValueKey<String>('nonconformances-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('nonconformances-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('nonconformances-filter-status');
  static const ValueKey<String> defectCodeFilterKey =
      ValueKey<String>('nonconformances-filter-defect-code');
  static const ValueKey<String> productFilterKey = ValueKey<String>('nonconformances-filter-product');
  static const ValueKey<String> severityFilterKey =
      ValueKey<String>('nonconformances-filter-severity');
  static const ValueKey<String> fromDateKey = ValueKey<String>('nonconformances-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('nonconformances-filter-to');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('nonconformances-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('nonconformances-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('nonconformances-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('nonconformances-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('nonconformances-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('nonconformances-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformances-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('nonconformances-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('nonconformances-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('nonconformance-row-$id');
  static ValueKey<String> rowStatusKey(String id) =>
      ValueKey<String>('nonconformance-status-$id');
  static ValueKey<String> rowSeverityKey(String id) =>
      ValueKey<String>('nonconformance-severity-$id');
  static ValueKey<String> rowQuantityKey(String id) =>
      ValueKey<String>('nonconformance-quantity-$id');
  static ValueKey<String> rowFiledKey(String id) => ValueKey<String>('nonconformance-filed-$id');

  /// The way into one record, right-most on its row (new in #390).
  static ValueKey<String> rowOpenKey(String id) => ValueKey<String>('nonconformance-open-$id');

  /// The row's slide-show toggle (issue #419).
  static ValueKey<String> slideShowKey(String id) =>
      ValueKey<String>('nonconformance-slide-show-$id');

  /// The banner a refused slide-show toggle renders in.
  static const ValueKey<String> slideShowFailureKey =
      ValueKey<String>('nonconformance-slide-show-failure');

  /// A row's height: the 44 of the controls it holds, plus [Spacing.xs] either
  /// side of the row's own padding.
  static const double rowHeight = AppTouchTarget.min + 2 * Spacing.xs;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NonconformancesBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            if (state is NonconformancesLoaded && state.slideShowFailure != null)
              _SlideShowFailure(
                message: state.slideShowFailure!,
                maxWidth: maxWidth,
                onDismiss: () => context
                    .read<NonconformancesBloc>()
                    .add(const NonconformancesRefreshed()),
              ),
            Expanded(
              child: switch (state) {
                NonconformancesLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                NonconformancesUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The Non-conformance register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<NonconformancesBloc>().add(const NonconformancesStarted()),
                  ),
                NonconformancesLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                NonconformancesLoaded(
                  nonconformances: final rows,
                  filters: final filters
                )
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                NonconformancesLoaded(nonconformances: final rows) => _Register(rows: rows),
              },
            ),
            if (state is NonconformancesLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183).
///
/// The `ShellRoute` creates `NonconformancesBloc` once and keeps it alive while
/// a caller reads a Non-conformance and comes back, so a Screen that only read
/// on `NonconformancesStarted` painted the list as it was when they left —
/// records written elsewhere, quantities grown, none of it visible. The Bloc
/// ignores the ask while its first load is still in flight.
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
    // After this frame, never during it: dispatching an event from `initState`
    // is a side effect while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NonconformancesBloc>().add(const NonconformancesRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final NonconformancesState state;

  @override
  Widget build(BuildContext context) {
    final loaded = state is NonconformancesLoaded ? state as NonconformancesLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: NonconformancesScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Non-conformances',
            description:
                'What was found not to conform at this Site, where it was found, and how '
                'much of it there is.',
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: NonconformancesScreen.recordKey,
                  onPressed: loaded.isRecording || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.nonConformances}/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Record a Non-conformance'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                ),
            ],
            below: loaded == null ? null : _Filters(loaded: loaded),
          ),
        ),
      ),
    );
  }
}

/// The Site chooser and the six ways to narrow the register. Each is a read
/// filter over an already-visible list, so each sends a request rather than
/// hiding rows the client happens to hold.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final NonconformancesLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = loaded.filters;

    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: AppLayout.atTextScale(context, 200),
            child: DropdownButtonFormField<String>(
              key: NonconformancesScreen.siteKey,
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
                context.read<NonconformancesBloc>().add(NonconformancesSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: NonconformancesScreen.orgUnitFilterKey,
          onPressed: () => NonconformanceOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 180),
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in NonconformanceStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(NonconformanceStatus.label(status)),
                ),
            ],
            onChanged: (status) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesStatusFilterChanged(status)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 210),
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.defectCodeFilterKey,
            initialValue: filters.defectCodeId,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Defect code', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Every Defect code')),
              for (final code in loaded.defectCodes)
                DropdownMenuItem<String?>(
                  value: code.id,
                  child: Text('${code.name} · ${code.code}'),
                ),
            ],
            onChanged: (id) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDefectCodeFilterChanged(id)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 200),
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.productFilterKey,
            initialValue: filters.productId,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Every Product')),
              for (final product in loaded.products)
                DropdownMenuItem<String?>(
                  value: product.id,
                  child: Text('${product.name} · ${product.code}'),
                ),
            ],
            onChanged: (id) =>
                context.read<NonconformancesBloc>().add(NonconformancesProductFilterChanged(id)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 170),
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.severityFilterKey,
            initialValue: filters.severity,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any severity')),
              for (final severity in DefectSeverity.values)
                DropdownMenuItem<String?>(
                  value: severity,
                  child: Text(DefectSeverity.label(severity)),
                ),
            ],
            onChanged: (severity) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesSeverityFilterChanged(severity)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 165),
          child: AppDateField(
            key: NonconformancesScreen.fromDateKey,
            name: 'nonconformances-from',
            label: 'Detected from',
            value: filters.from,
            optional: true,
            onChanged: (value) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDateRangeChanged(from: value, clearFrom: value == null)),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 165),
          child: AppDateField(
            key: NonconformancesScreen.toDateKey,
            name: 'nonconformances-to',
            label: 'Detected to',
            value: filters.to,
            optional: true,
            onChanged: (value) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDateRangeChanged(to: value, clearTo: value == null)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: NonconformancesScreen.clearFiltersKey,
            onPressed: () =>
                context.read<NonconformancesBloc>().add(const NonconformancesFiltersCleared()),
            style: TextButton.styleFrom(
              minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
            ),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped. Said out loud rather than left to be inferred from
/// a list that happens to end: a capped list must not read as a whole Site
/// (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: NonconformancesScreen.maxWidth,
        child: Padding(
          key: NonconformancesScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Non-conformances than this list shows. Narrow it by Org Unit, by '
            'status or by date to see the rest.',
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103): a Site with nothing on its
/// register is a good-news empty, and a filter that matched nothing is a
/// filter to clear. The wrong one would send a caller looking for a record
/// that exists.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: NonconformancesScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has Non-conformances, but none of them is in the area, state, '
            'Defect code, Product, severity or dates you picked.',
        actionLabel: 'Clear the filters',
        actionKey: NonconformancesScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<NonconformancesBloc>().add(const NonconformancesFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: NonconformancesScreen.emptyKey,
      title: 'Nothing has been found not to conform',
      message: 'No Non-conformance has been recorded at this Site.',
      icon: Icons.fact_check_outlined,
    );
  }
}

/// A chip's own width at the reader's text scale: its label, the compact chip's
/// padding either side, and the slot's gutter.
double _chipWidth(BuildContext context, String label, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style ?? Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.xxl + Spacing.sm;
}

double _widestChip(BuildContext context, Iterable<String> labels) {
  var widest = 0.0;
  for (final label in labels) {
    final width = _chipWidth(context, label, null);
    if (width > widest) widest = width;
  }
  return widest;
}

/// The number column: `NC-HCM-2026-00001` is a fixed-width code, so the column
/// is measured to it rather than taking a share of the flex.
double _numberColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'NC-HCM-2026-00001', style: AppTypography.dense(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.sm + 8;
}

/// The State column carries the severity chip and the state chip side by side,
/// so it is the two widest labels of either family plus the [Spacing.xs] between
/// them. Both are bounded sets, so this is measured once rather than guessed.
double _stateColumnWidth(BuildContext context) {
  final severity = _widestChip(context, [
    for (final value in DefectSeverity.values) DefectSeverity.label(value),
  ]);
  final status = _widestChip(context, [
    for (final value in NonconformanceStatus.values) NonconformanceStatus.label(value),
  ]);
  return severity + Spacing.xs + status;
}

double _openColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'Open', style: Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // The Open button, then the slide-show toggle beside it (issue #419): a
  // 44-px control and the [Spacing.xs] that separates the two. Without the
  // extra room the cell's Row overflows, which is what a table does when a
  // control is added to a column measured for one button.
  return painter.width + 2 * Spacing.xl + Spacing.sm + AppTouchTarget.min + Spacing.xs;
}

/// The register's one column spec, spent by the band and by every row.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn('Non-conformance', width: _numberColumnWidth(context)),
      const AppTableColumn('What was found', flex: 4),
      AppTableColumn('State', width: _stateColumnWidth(context)),
      const AppTableColumn('Quantity', flex: 2, align: AppColumnAlign.end),
      const AppTableColumn('Filed', flex: 3),
      AppTableColumn('Actions', width: _openColumnWidth(context), align: AppColumnAlign.end),
    ];

Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

/// The count, and whether it has grown since it was first written down — a
/// reader deciding what to do about it needs the number that is true now.
String _quantityLabel(Nonconformance row) =>
    '${_number(row.quantityAffected)} ${row.uomCode} affected'
    '${row.quantityChanged ? ' · raised ${row.quantityChanges.length} time'
        '${row.quantityChanges.length == 1 ? '' : 's'}' : ''}';

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<Nonconformance> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth <
            AppBreakpoints.effective(context, NonconformancesScreen.narrowBreakpoint);
        final columns = _columns(context);
        return Center(
          child: AppPageFrame(
            maxWidth: NonconformancesScreen.maxWidth,
            child: narrow
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) => _NonconformanceCard(nonconformance: rows[index]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    children: [
                      AppTableHeader(columns: columns),
                      for (final row in rows)
                        _NonconformanceTableRow(columns: columns, nonconformance: row),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _NonconformanceTableRow extends StatelessWidget {
  const _NonconformanceTableRow({required this.columns, required this.nonconformance});

  final List<AppTableColumn> columns;
  final Nonconformance nonconformance;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = nonconformance;

    return KeyedSubtree(
      key: NonconformancesScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.nonConformances}/${row.id}'),
        cells: [
          DisclosingText(row.issueNo, style: dense?.copyWith(color: palette.textMuted)),
          DisclosingText(
            '${row.productName} · ${row.defectCodeName} · ${row.detectionPointLabel}',
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          _shrinkWrapTargets(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusChip(
                  key: NonconformancesScreen.rowSeverityKey(row.id),
                  label: row.severityLabel,
                  tone: _severityTone(row.severity),
                ),
                const SizedBox(width: Spacing.xs),
                StatusChip(
                  key: NonconformancesScreen.rowStatusKey(row.id),
                  label: row.statusLabel,
                  tone: row.statusTone,
                ),
              ],
            ),
          ),
          DisclosingText(
            _quantityLabel(row),
            key: NonconformancesScreen.rowQuantityKey(row.id),
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
          ),
          DisclosingText(
            '${row.orgUnitName} · filed against ${row.filedAgainst}',
            key: NonconformancesScreen.rowFiledKey(row.id),
            style: dense?.copyWith(color: palette.textMuted),
          ),
          _shrinkWrapTargets(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SlideShowToggle(
                  key: NonconformancesScreen.slideShowKey(row.id),
                  inSlideShow: row.inSlideShow,
                  busy: _slideShowPending(context, row.id),
                  onChanged: (chosen) => context.read<NonconformancesBloc>().add(
                        NonconformanceSlideShowToggled(id: row.id, chosen: chosen),
                      ),
                ),
                const SizedBox(width: Spacing.xs),
                OutlinedButton(
                  key: NonconformancesScreen.rowOpenKey(row.id),
                  onPressed: () => context.go('${Routes.nonConformances}/${row.id}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NonconformanceCard extends StatelessWidget {
  const _NonconformanceCard({required this.nonconformance});

  final Nonconformance nonconformance;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final row = nonconformance;

    return Card(
      key: NonconformancesScreen.rowKey(row.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.go('${Routes.nonConformances}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.issueNo,
                    style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${row.productName} · ${row.defectCodeName} · ${row.detectionPointLabel}',
                style: AppTypography.dense(context)
                    ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    key: NonconformancesScreen.rowSeverityKey(row.id),
                    label: row.severityLabel,
                    tone: _severityTone(row.severity),
                  ),
                  StatusChip(
                    key: NonconformancesScreen.rowStatusKey(row.id),
                    label: row.statusLabel,
                    tone: row.statusTone,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                _quantityLabel(row),
                key: NonconformancesScreen.rowQuantityKey(row.id),
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                '${row.orgUnitName} · filed against ${row.filedAgainst}',
                key: NonconformancesScreen.rowFiledKey(row.id),
                style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                // Open first, at the card's own left padding: that is what
                // tells a card apart from a table row (issue #390's geometry
                // test measures exactly that edge), and the slide-show toggle
                // follows it rather than pushing it right.
                children: [
                  OutlinedButton(
                    key: NonconformancesScreen.rowOpenKey(row.id),
                    onPressed: () => context.go('${Routes.nonConformances}/${row.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: const Text('Open'),
                  ),
                  const SizedBox(width: Spacing.xs),
                  SlideShowToggle(
                    key: NonconformancesScreen.slideShowKey(row.id),
                    inSlideShow: row.inSlideShow,
                    busy: _slideShowPending(context, row.id),
                    onChanged: (chosen) => context.read<NonconformancesBloc>().add(
                          NonconformanceSlideShowToggled(id: row.id, chosen: chosen),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A severity's meaning in the shared status vocabulary (issue #168): a
/// critical find wants attention, a major one wants a decision, a minor one is
/// the quietest of the three.
StatusTone _severityTone(String severity) => switch (severity) {
      'critical' => StatusTone.danger,
      'major' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

/// A quantity without a trailing `.0` — 12, not 12.0, since that is how a
/// person writes a count of pieces.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

/// Whether this row's slide-show request is in flight (issue #419). A row that
/// is waiting shows it rather than looking stuck; `select` keeps the rebuild to
/// the one row that changed.
bool _slideShowPending(BuildContext context, String id) =>
    context.select<NonconformancesBloc, bool>((bloc) {
      final state = bloc.state;
      return state is NonconformancesLoaded && state.slideShowPending.contains(id);
    });

/// A refused slide-show toggle, above the register (design-language §12): the
/// act failed and the row that caused it may have scrolled away, so the
/// sentence goes where the page's own banner goes rather than beside one row.
class _SlideShowFailure extends StatelessWidget {
  const _SlideShowFailure({
    required this.message,
    required this.maxWidth,
    required this.onDismiss,
  });

  final String message;
  final double maxWidth;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: AppBanner(
            key: NonconformancesScreen.slideShowFailureKey,
            tone: StatusTone.danger,
            message: message,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }
}
