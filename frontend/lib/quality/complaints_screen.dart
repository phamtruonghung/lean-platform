/// The customer complaint register (issue #214, CONTEXT.md's **Customer**): what
/// customers complained about at this Site, which Product it was, what it is
/// costing them to wait, and whether the complained-of product has been
/// controlled.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Non-conformance register, the Work order list and the Asset
/// register already follow (#55, ADR-0009). Recording is offered to everyone
/// too: the server is the real gate on where a complaint may be filed (an edit
/// Grant reaching that Org Unit), and hiding the button would gate an address
/// that answers a clean refusal with a sentence the caller can act on.
///
/// Both filters are read filters over the already-visible register and send a
/// request rather than hiding rows client-side — the status and the Org Unit
/// are what the ticket names, and the Org Unit one includes everything
/// *beneath* the chosen area, which is the server's ltree walk rather than a
/// filter this client applies.
///
/// A row that is past the day the customer was promised an answer says so on
/// its own face: the server marks it ([CustomerComplaint.isOverdue]) and the
/// row renders that as a chip, because the one thing a reader must not have to
/// work out from two dates is who is waiting.
///
/// **The register is a table above [narrowBreakpoint] of its own content width,
/// and the card below it (issue #390).** Six columns — the number, who
/// complained about what, the tone chips, the day an answer is owed, what
/// controls the product, and the way in — are more than the five
/// [AppBreakpoints.registerTable] (700) was measured for, and at a 1280px window
/// this page is handed 988px of box, so the number this Screen states is 900:
/// the table is drawn when the box really can hold six columns, and a card per
/// complaint below it. At twice the reader's text the same 988px box is under
/// 1800, so the cards come back sooner rather than squeezing six columns past
/// legibility (design-language §10 — the class of bug #379 and #381).
///
/// **Every cell that can hold unbounded user text discloses it.** The customer
/// and product line, the due line and the control line are free text, so at a
/// 1280 window they clip and `DisclosingText` says so in a tooltip, in a long
/// press and to a screen reader. Nothing is silently truncated, and nothing a
/// reader decides on is reachable only through the pointer: the record's own
/// number is the first column, the row is the tap target, and the Open action is
/// the right-most cell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'complaint_org_unit_filter_dialog.dart';
import 'complaints_bloc.dart';
import 'customer_complaint.dart';
import 'slide_show_toggle.dart';

class ComplaintsScreen extends StatelessWidget {
  const ComplaintsScreen({super.key});

  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the register is
  /// a table of six columns; below it, one card per complaint. Measured from the
  /// box the list is handed, never the window, and scaled by the reader's text
  /// size through [AppBreakpoints.effective].
  static const double narrowBreakpoint = 900;

  static const ValueKey<String> recordKey = ValueKey<String>('complaints-record');
  static const ValueKey<String> siteKey = ValueKey<String>('complaints-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('complaints-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('complaints-filter-status');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('complaints-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('complaints-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('complaints-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('complaints-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey = ValueKey<String>('complaints-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('complaints-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('complaints-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('complaints-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('complaints-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('complaint-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('complaint-status-$id');
  static ValueKey<String> rowOverdueKey(String id) => ValueKey<String>('complaint-overdue-$id');
  static ValueKey<String> rowDueKey(String id) => ValueKey<String>('complaint-due-$id');
  static ValueKey<String> rowControlledKey(String id) =>
      ValueKey<String>('complaint-controlled-$id');

  /// The way into one complaint, right-most on its row. New in #390: the row
  /// used to be the only way in, which is a target a pointer has to find and a
  /// keyboard reaches only by tabbing through everything before it.
  static ValueKey<String> rowOpenKey(String id) => ValueKey<String>('complaint-open-$id');

  /// The row's slide-show toggle (issue #419), and the banner a refused toggle
  /// renders in.
  static ValueKey<String> slideShowKey(String id) => ValueKey<String>('complaint-slide-show-$id');
  static const ValueKey<String> slideShowFailureKey =
      ValueKey<String>('complaint-slide-show-failure');

  /// The row's height: a control is 44 and the row pads it by [Spacing.xs]
  /// either side. A card row carries the same controls, so the two agree.
  static const double rowHeight = AppTouchTarget.min + 2 * Spacing.xs;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ComplaintsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            if (state is ComplaintsLoaded && state.slideShowFailure != null)
              _SlideShowFailure(
                message: state.slideShowFailure!,
                maxWidth: maxWidth,
                onDismiss: () =>
                    context.read<ComplaintsBloc>().add(const ComplaintsRefreshed()),
              ),
            Expanded(
              child: switch (state) {
                ComplaintsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                ComplaintsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The complaint register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<ComplaintsBloc>().add(const ComplaintsStarted()),
                  ),
                ComplaintsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                ComplaintsLoaded(complaints: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                ComplaintsLoaded(complaints: final rows) => _Register(rows: rows),
              },
            ),
            if (state is ComplaintsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183):
/// the `ShellRoute` creates `ComplaintsBloc` once and keeps it alive while a
/// caller reads a complaint and comes back, so a Screen that only read on
/// `ComplaintsStarted` painted the list as it was when they left.
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
      context.read<ComplaintsBloc>().add(const ComplaintsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ComplaintsState state;

  @override
  Widget build(BuildContext context) {
    final loaded = state is ComplaintsLoaded ? state as ComplaintsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Customer complaints',
            description:
                'What customers have complained about at this Site, and whether the '
                'product they complained about is under control.',
            actions: [
              if (loaded != null)
                FilledButton.icon(
                  key: ComplaintsScreen.recordKey,
                  onPressed: loaded.isRecording || loaded.siteId == null
                      ? null
                      : () => context.go('${Routes.complaints}/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Record a complaint'),
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

  final ComplaintsLoaded loaded;

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
              key: ComplaintsScreen.siteKey,
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
                context.read<ComplaintsBloc>().add(ComplaintsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: ComplaintsScreen.orgUnitFilterKey,
          onPressed: () => ComplaintOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
          ),
        ),
        SizedBox(
          width: AppLayout.atTextScale(context, 190),
          child: DropdownButtonFormField<String?>(
            key: ComplaintsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in ComplaintStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(ComplaintStatus.label(status)),
                ),
            ],
            onChanged: (status) =>
                context.read<ComplaintsBloc>().add(ComplaintsStatusFilterChanged(status)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: ComplaintsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<ComplaintsBloc>().add(const ComplaintsFiltersCleared()),
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
/// a list that happens to end (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintsScreen.maxWidth,
        child: Padding(
          key: ComplaintsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more complaints than this list shows. Narrow it by Org Unit or by status '
            'to see the rest.',
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
        key: ComplaintsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has complaints, but none of them is in the area or state you '
            'picked.',
        actionLabel: 'Clear the filters',
        actionKey: ComplaintsScreen.emptyClearFiltersKey,
        onAction: () => context.read<ComplaintsBloc>().add(const ComplaintsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: ComplaintsScreen.emptyKey,
      title: 'No complaints',
      message: 'No customer has complained about anything from this Site.',
      icon: Icons.support_agent_outlined,
    );
  }
}

/// The number column: a complaint number is a fixed-width code — `CC-2026-00001`
/// — so the column is measured to fit one at the reader's text scale rather than
/// taking a share of the flex, and the number is never the value that clips.
double _numberColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'CC-2026-00001', style: AppTypography.dense(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width + Spacing.sm + 8;
}

/// A chip's own width in the reader's text scale: its label, the compact chip's
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

/// The State column: wide enough for the status chip and one marking beside it,
/// which is the commonest pair (a complaint that is open *and* past due). A row
/// that carries all three marks — open, past due and a warranty claim — wraps the
/// third onto a second line inside the same cell and grows, rather than the
/// column being sized for a combination most rows do not have.
double _stateColumnWidth(BuildContext context) {
  var widestStatus = 0.0;
  for (final status in ComplaintStatus.values) {
    final width = _chipWidth(context, ComplaintStatus.label(status));
    if (width > widestStatus) widestStatus = width;
  }
  final overdue = _chipWidth(context, 'Past due');
  final warranty = _chipWidth(context, 'Warranty');
  return widestStatus + Spacing.xs + (overdue > warranty ? overdue : warranty);
}

/// The Actions column: the one Open button's label, the button's own horizontal
/// padding either side ([Spacing.xl]) and the slot's gutter.
double _openColumnWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'Open', style: Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // The Open button and the slide-show toggle beside it (issue #419); see
  // `nonconformances_screen.dart`'s own note on the same measurement.
  return painter.width + 2 * Spacing.xl + Spacing.sm + AppTouchTarget.min + Spacing.xs;
}

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a band label and its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context) => [
      AppTableColumn('Complaint', width: _numberColumnWidth(context)),
      const AppTableColumn('Customer and product', flex: 4),
      AppTableColumn('State', width: _stateColumnWidth(context)),
      const AppTableColumn('Response due', flex: 3),
      const AppTableColumn('Control', flex: 4),
      AppTableColumn('Actions', width: _openColumnWidth(context), align: AppColumnAlign.end),
    ];

/// The numbering a reader scans for, and the sentence the row is read as: who
/// complained, about which Product, and against which Defect code. One string,
/// because that is how the record is spoken about on the floor.
String _subject(CustomerComplaint row) =>
    '${row.customerName} · ${row.productName}'
    '${row.defectCodeName == null ? '' : ' · ${row.defectCodeName}'}';

/// What controls the product, or the absence of a control — the two answers this
/// register is read for.
String _control(CustomerComplaint row) => row.nonconformance == null
    ? 'No Non-conformance controls this product yet'
    : 'Controlled by ${row.nonconformance!.issueNo}';

/// The tone chips a complaint carries: its state, and the two markings that
/// change what a reader should do next.
List<Widget> _marks(BuildContext context, CustomerComplaint row) => [
      StatusChip(
        key: ComplaintsScreen.rowStatusKey(row.id),
        label: row.statusLabel,
        tone: row.statusTone,
      ),
      if (row.isOverdue)
        StatusChip(
          key: ComplaintsScreen.rowOverdueKey(row.id),
          label: 'Past due',
          tone: StatusTone.danger,
        ),
      if (row.isWarranty)
        const StatusChip(label: 'Warranty', tone: StatusTone.info),
    ];

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<CustomerComplaint> rows;

  @override
  Widget build(BuildContext context) {
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, box) {
        final narrow =
            box.maxWidth < AppBreakpoints.effective(context, ComplaintsScreen.narrowBreakpoint);
        final columns = _columns(context);
        return Center(
          child: AppPageFrame(
            maxWidth: ComplaintsScreen.maxWidth,
            child: narrow
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) => _ComplaintCard(complaint: rows[index]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    children: [
                      AppTableHeader(columns: columns),
                      for (final row in rows)
                        _ComplaintTableRow(columns: columns, complaint: row),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// The framework's padded tap target is lifted on the chips and the buttons: each
/// control states its own [AppTouchTarget.min] through `minimumSize`, and the
/// padded target would add height to a row that is already 44.
Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

class _ComplaintTableRow extends StatelessWidget {
  const _ComplaintTableRow({required this.columns, required this.complaint});

  final List<AppTableColumn> columns;
  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = complaint;

    return KeyedSubtree(
      key: ComplaintsScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.complaints}/${row.id}'),
        cells: [
          DisclosingText(row.complaintNo, style: dense?.copyWith(color: palette.textMuted)),
          DisclosingText(_subject(row), style: dense?.copyWith(color: palette.textPrimary)),
          _shrinkWrapTargets(
            context,
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: _marks(context, row),
            ),
          ),
          DisclosingText(
            row.dueLabel,
            key: ComplaintsScreen.rowDueKey(row.id),
            style: dense?.copyWith(color: row.isOverdue ? palette.statusDanger : palette.textMuted),
          ),
          DisclosingText(
            _control(row),
            key: ComplaintsScreen.rowControlledKey(row.id),
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          _shrinkWrapTargets(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SlideShowToggle(
                  key: ComplaintsScreen.slideShowKey(row.id),
                  inSlideShow: row.inSlideShow,
                  busy: _slideShowPending(context, row.id),
                  onChanged: (chosen) => context.read<ComplaintsBloc>().add(
                        ComplaintSlideShowToggled(id: row.id, chosen: chosen),
                      ),
                ),
                const SizedBox(width: Spacing.xs),
                OutlinedButton(
                  key: ComplaintsScreen.rowOpenKey(row.id),
                  onPressed: () => context.go('${Routes.complaints}/${row.id}'),
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

/// One complaint as a card, for a box that cannot hold six columns. The same
/// facts as the table row, stacked, because a narrow box is a narrow box rather
/// than a reason to drop what a reader decides on.
class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final row = complaint;

    return Card(
      key: ComplaintsScreen.rowKey(row.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.go('${Routes.complaints}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A `Wrap`, not a `Row`: the chips grow per ticket and a long
              // buyer reference would overflow a Row at the test surface.
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.complaintNo,
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
                children: _marks(context, row),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                row.dueLabel,
                key: ComplaintsScreen.rowDueKey(row.id),
                style: AppTypography.floor(context)?.copyWith(
                  color: row.isOverdue ? palette.statusDanger : palette.textMuted,
                ),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                _control(row),
                key: ComplaintsScreen.rowControlledKey(row.id),
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                // Open at the card's own left padding first, then the slide-show
                // toggle; see `nonconformances_screen.dart`'s note on the same
                // row.
                children: [
                  OutlinedButton(
                    key: ComplaintsScreen.rowOpenKey(row.id),
                    onPressed: () => context.go('${Routes.complaints}/${row.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: const Text('Open'),
                  ),
                  const SizedBox(width: Spacing.xs),
                  SlideShowToggle(
                    key: ComplaintsScreen.slideShowKey(row.id),
                    inSlideShow: row.inSlideShow,
                    busy: _slideShowPending(context, row.id),
                    onChanged: (chosen) => context.read<ComplaintsBloc>().add(
                          ComplaintSlideShowToggled(id: row.id, chosen: chosen),
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

/// Whether this row's slide-show request is in flight (issue #419) — the
/// complaint's half of `NonconformancesScreen`'s own helper, and `select` for
/// the same reason: only the row that changed rebuilds.
bool _slideShowPending(BuildContext context, String id) =>
    context.select<ComplaintsBloc, bool>((bloc) {
      final state = bloc.state;
      return state is ComplaintsLoaded && state.slideShowPending.contains(id);
    });

/// A refused slide-show toggle, above the register (design-language §12).
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
            key: ComplaintsScreen.slideShowFailureKey,
            tone: StatusTone.danger,
            message: message,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }
}
