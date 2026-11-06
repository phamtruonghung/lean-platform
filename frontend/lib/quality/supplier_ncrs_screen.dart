/// The supplier NCR register (issue #215, CONTEXT.md's **Supplier NCR**): what
/// came in wrong at this Site, which Supplier it came from, what was decided
/// about the material, and whether it is under control.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Non-conformance register, the Customer complaint register and
/// the Work order list already follow (#55, ADR-0009). Recording is offered to
/// everyone too: the server is the real gate on where an NCR may be filed (an
/// edit Grant reaching that Org Unit), and hiding the button would gate an
/// address that answers a clean refusal with a sentence the caller can act on.
///
/// The three filters are read filters over the already-visible register and send
/// a request rather than hiding rows client-side — the Supplier and the status
/// are what the ticket names, and the Org Unit one includes everything *beneath*
/// the chosen area, which is the server's ltree walk rather than a filter this
/// client applies.
///
/// A row that is past the day the Supplier was given says so on its own face:
/// the server marks it ([SupplierNcr.isOverdue]) and the row renders that as a
/// chip, because the one thing a reader must not have to work out from two dates
/// is who owes an answer.
///
/// **Seven columns above [narrowBreakpoint] of content width, a card below it
/// (issue #390).** An NCR carries two facts a complaint does not — what was
/// decided about the material, and when an answer is owed — so the register is
/// one column wider than the complaint register's six and states 900 of box for
/// the same reason: at a 1280px window the list is handed 988px, which holds
/// seven columns if the three unbounded ones disclose what they clip. They do:
/// the supplier line, the disposition line, the answer date and the control line
/// are all `DisclosingText`. At twice the reader's text the same box is under
/// 1800 and the cards come back (design-language §10).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_row.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'supplier_ncr.dart';
import 'supplier_ncr_org_unit_filter_dialog.dart';
import 'supplier_ncr_supplier_filter_dialog.dart';
import 'supplier_ncrs_bloc.dart';

class SupplierNcrsScreen extends StatelessWidget {
  const SupplierNcrsScreen({super.key});

  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the register is
  /// a table of seven columns; below it, one card per NCR. Read from the box the
  /// list is handed, never the window, and scaled by the reader's text size.
  static const double narrowBreakpoint = 900;

  static const ValueKey<String> recordKey = ValueKey<String>('supplier-ncrs-record');
  static const ValueKey<String> siteKey = ValueKey<String>('supplier-ncrs-site');
  static const ValueKey<String> supplierFilterKey =
      ValueKey<String>('supplier-ncrs-filter-supplier');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('supplier-ncrs-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('supplier-ncrs-filter-status');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('supplier-ncrs-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('supplier-ncrs-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('supplier-ncrs-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('supplier-ncrs-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('supplier-ncrs-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('supplier-ncrs-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('supplier-ncrs-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('supplier-ncrs-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('supplier-ncrs-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('supplier-ncr-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('supplier-ncr-status-$id');
  static ValueKey<String> rowOverdueKey(String id) => ValueKey<String>('supplier-ncr-overdue-$id');
  static ValueKey<String> rowDueKey(String id) => ValueKey<String>('supplier-ncr-due-$id');
  static ValueKey<String> rowDispositionKey(String id) =>
      ValueKey<String>('supplier-ncr-disposition-$id');
  static ValueKey<String> rowControlledKey(String id) =>
      ValueKey<String>('supplier-ncr-controlled-$id');

  /// The way into one NCR, right-most on its row (new in #390).
  static ValueKey<String> rowOpenKey(String id) => ValueKey<String>('supplier-ncr-open-$id');

  /// A row's height: the 44 of the controls it holds, plus [Spacing.xs] either
  /// side of the row's own padding.
  static const double rowHeight = AppTouchTarget.min + 2 * Spacing.xs;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupplierNcrsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SupplierNcrsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SupplierNcrsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The supplier NCR register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<SupplierNcrsBloc>().add(const SupplierNcrsStarted()),
                  ),
                SupplierNcrsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                SupplierNcrsLoaded(supplierNcrs: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SupplierNcrsLoaded(supplierNcrs: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SupplierNcrsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183): the
/// `ShellRoute` creates `SupplierNcrsBloc` once and keeps it alive while a caller
/// reads an NCR and comes back, so a Screen that only read on
/// `SupplierNcrsStarted` painted the list as it was when they left.
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
      context.read<SupplierNcrsBloc>().add(const SupplierNcrsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SupplierNcrsState state;

  @override
  Widget build(BuildContext context) {
    final loaded = state is SupplierNcrsLoaded ? state as SupplierNcrsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Supplier NCRs',
            description:
                'What arrived wrong from a Supplier at this Site, and whether the '
                'material it came in with is under control.',
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: SupplierNcrsScreen.recordKey,
                  onPressed: loaded.isRecording || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.supplierNcrs}/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Record a supplier NCR'),
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

class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final SupplierNcrsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = loaded.filters;

    return AppFilterRow(
      children: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: AppLayout.atTextScale(context, 200),
            child: DropdownButtonFormField<String>(
              key: SupplierNcrsScreen.siteKey,
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
                context.read<SupplierNcrsBloc>().add(SupplierNcrsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SupplierNcrsScreen.supplierFilterKey,
          onPressed: () => SupplierNcrSupplierFilterDialog.open(context),
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(filters.supplierName ?? 'All Suppliers'),
        ),
        OutlinedButton.icon(
          key: SupplierNcrsScreen.orgUnitFilterKey,
          onPressed: () => SupplierNcrOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 190),
          child: DropdownButtonFormField<String?>(
            key: SupplierNcrsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in SupplierNcrStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(SupplierNcrStatus.label(status)),
                ),
            ],
            onChanged: (status) =>
                context.read<SupplierNcrsBloc>().add(SupplierNcrsStatusFilterChanged(status)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: SupplierNcrsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<SupplierNcrsBloc>().add(const SupplierNcrsFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped. Said out loud rather than left to be inferred from
/// a list that happens to end (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrsScreen.maxWidth,
        child: Padding(
          key: SupplierNcrsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more supplier NCRs than this list shows. Narrow it by Supplier or by '
            'status to see the rest.',
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103): a Site with nothing on its
/// register is a good-news empty, and a filter that matched nothing is a filter
/// to clear.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: SupplierNcrsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has supplier NCRs, but none of them is in the area, the Supplier '
            'or the state you picked.',
        actionLabel: 'Clear the filters',
        actionKey: SupplierNcrsScreen.emptyClearFiltersKey,
        onAction: () => context.read<SupplierNcrsBloc>().add(const SupplierNcrsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: SupplierNcrsScreen.emptyKey,
      title: 'No supplier NCRs',
      message: 'Nothing has come in wrong from a Supplier at this Site.',
      icon: Icons.local_shipping_outlined,
    );
  }
}

/// A chip's own width at the reader's text scale: its label, the compact chip's
/// padding either side, and the slot's gutter.
double _chipWidth(BuildContext context, String label) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.xxl + Spacing.sm;
}

/// The number column: `SN-2026-00001` is a fixed-width code, so the column is
/// measured to it rather than taking a share of the flex.
double _numberColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'SN-2026-00001', style: AppTypography.dense(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.sm + 8;
}

/// The State column carries the state chip and, on a row that is late, the
/// "Past due" chip beside it, so it is the two widest labels plus the
/// [Spacing.xs] between them.
double _stateColumnWidth(BuildContext context) {
  var widestStatus = 0.0;
  for (final status in SupplierNcrStatus.values) {
    final width = _chipWidth(context, SupplierNcrStatus.label(status));
    if (width > widestStatus) widestStatus = width;
  }
  return widestStatus + Spacing.xs + _chipWidth(context, 'Past due');
}

double _openColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'Open', style: Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + 2 * Spacing.xl + Spacing.sm;
}

/// The register's one column spec, spent by the band and by every row.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn('NCR', width: _numberColumnWidth(context)),
      const AppTableColumn('Supplier and product', flex: 4),
      AppTableColumn('State', width: _stateColumnWidth(context)),
      const AppTableColumn('Disposition', flex: 3),
      const AppTableColumn('Answer due', flex: 2),
      const AppTableColumn('Control', flex: 3),
      AppTableColumn('Actions', width: _openColumnWidth(context), align: AppColumnAlign.end),
    ];

Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

/// Who sent the bad lot, and what it was: the Supplier, then the Product and the
/// Defect code the NCR names, each only when the record carries it.
String _subject(SupplierNcr row) {
  final product = row.productName;
  return '${row.supplierName}${product == null ? '' : ' · $product'}'
      '${row.defectCodeName == null ? '' : ' · ${row.defectCodeName}'}';
}

/// The answer for the material, and what was clawed back: the two facts the Cost
/// pillar is built on.
String _dispositionLabel(SupplierNcr row) =>
    '${row.dispositionLabel} · ${row.costRecoveredLabel}';

/// The control that exists, or the absence of one — the two answers this
/// register is read for.
String _control(SupplierNcr row) => row.nonconformance == null
    ? 'No Non-conformance controls this lot yet'
    : 'Controlled by ${row.nonconformance!.issueNo}';

List<Widget> _marks(SupplierNcr row) => [
      StatusChip(
        key: SupplierNcrsScreen.rowStatusKey(row.id),
        label: row.statusLabel,
        tone: row.statusTone,
      ),
      if (row.isOverdue)
        StatusChip(
          key: SupplierNcrsScreen.rowOverdueKey(row.id),
          label: 'Past due',
          tone: StatusTone.danger,
        ),
    ];

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SupplierNcr> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow =
            box.maxWidth < AppBreakpoints.effective(context, SupplierNcrsScreen.narrowBreakpoint);
        final columns = _columns(context);
        return Center(
          child: AppPageFrame(
            maxWidth: SupplierNcrsScreen.maxWidth,
            child: narrow
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) => _SupplierNcrCard(supplierNcr: rows[index]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    children: [
                      AppTableHeader(columns: columns),
                      for (final row in rows)
                        _SupplierNcrTableRow(columns: columns, supplierNcr: row),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _SupplierNcrTableRow extends StatelessWidget {
  const _SupplierNcrTableRow({required this.columns, required this.supplierNcr});

  final List<AppTableColumn> columns;
  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = supplierNcr;

    return KeyedSubtree(
      key: SupplierNcrsScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.supplierNcrs}/${row.id}'),
        cells: [
          DisclosingText(row.ncrNo, style: dense?.copyWith(color: palette.textMuted)),
          DisclosingText(_subject(row), style: dense?.copyWith(color: palette.textPrimary)),
          _shrinkWrapTargets(
            context,
            Row(mainAxisSize: MainAxisSize.min, children: _marks(row)),
          ),
          DisclosingText(
            _dispositionLabel(row),
            key: SupplierNcrsScreen.rowDispositionKey(row.id),
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          DisclosingText(
            row.dueLabel,
            key: SupplierNcrsScreen.rowDueKey(row.id),
            style: dense?.copyWith(color: row.isOverdue ? palette.statusDanger : palette.textMuted),
          ),
          DisclosingText(
            _control(row),
            key: SupplierNcrsScreen.rowControlledKey(row.id),
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          _shrinkWrapTargets(
            context,
            OutlinedButton(
              key: SupplierNcrsScreen.rowOpenKey(row.id),
              onPressed: () => context.go('${Routes.supplierNcrs}/${row.id}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
              ),
              child: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One NCR as a card, for a box that cannot hold seven columns. A `Wrap` of the
/// chips, not a `Row`: the chips grow per ticket and a long supplier name would
/// overflow a Row at the test surface.
class _SupplierNcrCard extends StatelessWidget {
  const _SupplierNcrCard({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final row = supplierNcr;

    return Card(
      key: SupplierNcrsScreen.rowKey(row.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.go('${Routes.supplierNcrs}/${row.id}'),
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
                    row.ncrNo,
                    style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                _subject(row),
                style: AppTypography.dense(context)
                    ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _marks(row),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                row.dueLabel,
                key: SupplierNcrsScreen.rowDueKey(row.id),
                style: AppTypography.floor(context)?.copyWith(
                  color: row.isOverdue ? palette.statusDanger : palette.textMuted,
                ),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                _dispositionLabel(row),
                key: SupplierNcrsScreen.rowDispositionKey(row.id),
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                _control(row),
                key: SupplierNcrsScreen.rowControlledKey(row.id),
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton(
                key: SupplierNcrsScreen.rowOpenKey(row.id),
                onPressed: () => context.go('${Routes.supplierNcrs}/${row.id}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
