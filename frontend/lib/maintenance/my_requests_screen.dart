/// The Requests this caller raised, every status — what became of each,
/// including the Work order an accepted one turned into (issue #72, ADR-0014).
///
/// This is the operator-facing Destination: anyone admitted may reach it, and
/// raising a Request needs only a read Grant reaching the Asset's Org Unit
/// (the server's own rule). The "Raise a Request" button is offered only to a
/// caller who holds at least one Grant somewhere — an action the server would
/// refuse is not offered in the first place.
///
/// **A register of seven columns, and a card per Request below 900px of
/// content.** At or above [MyRequestsScreen.narrowBreakpoint] (at a text scale of
/// 1) the Requests are an `AppTableHeader` band and one `AppTableRow` per Request,
/// both built from the one column spec [_columns]. What became of a Request (the
/// Work order it turned into, or why it was declined) is prose, not a value to
/// compare down a column, so the register keeps it one press away in a
/// `RowDisclosure` under the row; the card shows it as it always has. The Raised
/// column is the date the Request was raised (`formatRequestDate`); the card does
/// not show it. The Site dropdown stays in the header, not in the list's toolbar:
/// it must stay reachable when the list is absent (a Site with nothing raised shows
/// `_MyRequestsEmpty`, and a failed read shows the failure state), while the filter
/// box needs the rows it narrows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'my_requests_bloc.dart';
import 'request.dart';
import 'request_form_dialog.dart';
import 'row_disclosure.dart';

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key, required this.canRaiseRequest});

  /// Whether this caller holds a Grant anywhere at all. Raising needs only a
  /// read Grant (the server passes `write: false`), so this is
  /// `orgUnitScope.canReadSomewhere` — deliberately not `canWriteSomewhere`,
  /// which would hide the affordance from a read-only Grant that the server
  /// would in fact allow. False hides the button entirely; it does not grey it
  /// out, because a disabled button is still an invitation to fail.
  final bool canRaiseRequest;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per Request, measured by `_MyRequestsList`'s `LayoutBuilder`,
  /// never the window. It is 900 rather than the 700 of a five-column register:
  /// this one has seven. At 900 the cells have about 844px (the box less the list's
  /// and the row's padding). The number, the urgency, the state, the date and the
  /// outcome toggle are measured and take about 490 of that, which leaves about 354
  /// for the two flex columns over their 7 shares: about 50px a share, so a summary
  /// of about 200px and an Asset of about 150, enough for their band labels and for
  /// `DisclosingText` to disclose the rest. All of these widths are real-font
  /// estimates worked by hand, not renders. Below 900 the measured columns leave
  /// the flex ones too little, so the register is drawn only from 900; measured in
  /// the app's own font at a 900 box the band and every row fit, while in
  /// `flutter_test`'s placeholder font, about twice as wide, they overflow by
  /// 9.9px there — which is why the tests that pin this register load the app's
  /// own fonts.
  static const double narrowBreakpoint = 900;

  /// The toggle that opens a register row's outcome.
  static ValueKey<String> outcomeKey(String id) => ValueKey<String>('my-request-outcome-$id');

  static const ValueKey<String> raiseKey = ValueKey<String>('my-requests-add');
  static const ValueKey<String> siteKey = ValueKey<String>('my-requests-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('my-requests-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('my-requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('my-requests-empty');
  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('my-requests-empty-raise');
  static const ValueKey<String> failedKey = ValueKey<String>('my-requests-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('my-request-row-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'my-requests-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the caller's own Requests renders — a
  /// different fact from [emptyKey]: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('my-requests-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MyRequestsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseRequest: canRaiseRequest),
          if (state is MyRequestsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              MyRequestsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              MyRequestsUnavailable(message: final message) => PlatformFailureState(
                key: MyRequestsScreen.failedKey,
                title: 'Your requests could not be read',
                message: message,
                retryKey: MyRequestsScreen.retryKey,
                onRetry: () => context.read<MyRequestsBloc>().add(const MyRequestsStarted()),
              ),
              MyRequestsLoaded(isLoadingRequests: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              MyRequestsLoaded(requests: final requests, siteId: final siteId)
                  when requests.isEmpty =>
                _MyRequestsEmpty(canRaiseRequest: canRaiseRequest, siteId: siteId),
              MyRequestsLoaded(requests: final requests) => _MyRequestsList(requests: requests),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canRaiseRequest});

  final MyRequestsState state;
  final bool canRaiseRequest;

  @override
  Widget build(BuildContext context) {
    final loaded = state is MyRequestsLoaded ? state as MyRequestsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: MyRequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'My requests',
            description: 'What you raised, and what became of each.',
            actions: [
              if (canRaiseRequest && loaded != null)
                FilledButton.icon(
                  key: MyRequestsScreen.raiseKey,
                  onPressed: loaded.isRaising || loaded.siteId == null
                      ? null
                      : () => _openRaise(context, loaded.siteId!),
                  icon: const Icon(Icons.add),
                  label: const Text('Raise a Request'),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
            below: loaded != null && loaded.sites.length > 1
                ? SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: MyRequestsScreen.siteKey,
                      initialValue: loaded.siteId,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Site',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final site in loaded.sites)
                          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                      ],
                      onChanged: (siteId) {
                        if (siteId == null) return;
                        context.read<MyRequestsBloc>().add(MyRequestsSiteSelected(siteId));
                      },
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _openRaise(BuildContext context, String siteId) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `MyRequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it, the same shape `WorkOrdersScreen._openOrgUnitFilter`
    // already uses for its picker's Bloc.
    final bloc = context.read<MyRequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<MyRequestsBloc>.value(
        value: bloc,
        child: RequestFormDialog(siteId: siteId),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: MyRequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: MyRequestsScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.dense(context)
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The caller's own Requests. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _MyRequestsList extends StatefulWidget {
  const _MyRequestsList({required this.requests});

  final List<Request> requests;

  @override
  State<_MyRequestsList> createState() => _MyRequestsListState();
}

class _MyRequestsListState extends State<_MyRequestsList> {
  /// What the filter box is narrowing the caller's own Requests to, `''` when
  /// nothing is.
  String _term = '';

  /// Whether [request] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a Request — its
  /// own number, the sentences that describe it, and the Asset it was raised
  /// against — so chasing one is one term rather than a walk through them all
  /// (issue #191, user story 7).
  static bool _matches(Request request, String term) =>
      request.requestNo.toLowerCase().contains(term) ||
      request.summary.toLowerCase().contains(term) ||
      (request.description ?? '').toLowerCase().contains(term) ||
      request.assetName.toLowerCase().contains(term) ||
      request.assetCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Request> get _matchingRequests {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.requests;
    return widget.requests.where((request) => _matches(request, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingRequests;
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            AppBreakpoints.effective(context, MyRequestsScreen.narrowBreakpoint);
        final columns = _columns(context, requests: widget.requests);
        return Center(
          child: AppPageFrame(
            maxWidth: MyRequestsScreen.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A toolbar's `Wrap` hands its children unbounded width, which a
                // text field cannot take, so the field is given the box's own width.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: LayoutBuilder(
                    builder: (context, box) => AppToolbar(
                      filters: [
                        SizedBox(
                          width: box.maxWidth,
                          child: AppFilterField(
                            name: MyRequestsScreen.filterFieldName,
                            label: 'Filter requests',
                            helperText: 'By description, Request number or Asset.',
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.requests.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Expanded(
                  child: matches.isEmpty
                      ? PlatformEmptyState.noneMatched(
                          key: MyRequestsScreen.noMatchKey,
                          title: 'No requests match',
                          message:
                              'You have Requests at this Site, but none matches '
                              '"${_term.trim()}". Try a different description or Asset.',
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) => _MyRequestCard(request: matches[index]),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            // Keyed by the Request's id so a row that is open
                            // stays open when the list rebuilds on a filter
                            // keystroke.
                            for (final request in matches)
                              _MyRequestTableRow(
                                key: ValueKey<String>('my-request-disclosure-${request.id}'),
                                columns: columns,
                                request: request,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The widest of [labels] in [style] at the reader's text scale.
double _widest(BuildContext context, Iterable<String> labels, TextStyle? style) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  var widest = 0.0;
  for (final label in labels) {
    painter.text = TextSpan(text: label, style: style);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest;
}

/// A band label's width in the band's own style (`AppTableHeader`: `labelMedium`,
/// w600, letter spacing 0.2) at the reader's text scale.
double _bandLabelWidth(BuildContext context, String label) => _widest(
  context,
  [label],
  Theme.of(context).textTheme.labelMedium
      ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
);

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a label and its cells start at the same x. The values
/// are the card's: the Request number, the summary, the Asset, the urgency (the
/// card writes it after the Asset; here it is its own column), the state, and the
/// outcome behind a toggle; the raised date is the register's own. Every measured
/// column is sized to its widest possible content or its band label, whichever is
/// wider, plus the slot's `Spacing.sm` gutter.
///
/// [requests] is every Request the Screen holds, never the filtered few on screen:
/// a measured width that followed the filter would move the whole band, and every
/// label with it, each time a term hid the widest record.
List<AppTableColumn> _columns(BuildContext context, {required List<Request> requests}) {
  double sized(double content, String label) {
    final bandLabel = _bandLabelWidth(context, label);
    return (content > bandLabel ? content : bandLabel) + Spacing.sm;
  }

  final dense = AppTypography.dense(context);
  return [
    AppTableColumn(
      'Request',
      // `MR-<Site code>-<year>-<five digits>`, as `next_document_number` issues it; the
      // Site code is the Site's own, so the numbers on screen are measured too.
      width: sized(
        _widest(context, ['MR-BUC-2026-00001', for (final r in requests) r.requestNo], dense),
        'Request',
      ),
    ),
    const AppTableColumn('Summary', flex: 4),
    const AppTableColumn('Asset', flex: 3),
    AppTableColumn(
      'Urgency',
      width: sized(
        _widest(context, [
          for (final u in RequestUrgency.values) u.label,
          for (final r in requests) r.urgencyLabel,
        ], dense),
        'Urgency',
      ),
    ),
    AppTableColumn(
      'Status',
      // A chip's own padding and label padding (`Spacing.xxl`).
      width: sized(
        // The five states the database allows (`maintenance_requests.status`), and
        // whatever label the rows on screen carry, so a state this build does not
        // know still fits.
        _widest(context, [
              'New',
              'Triaged',
              'Accepted',
              'Rejected',
              'Duplicate',
              for (final r in requests) r.statusLabel,
            ], Theme.of(context).textTheme.labelLarge) +
            Spacing.xxl,
        'Status',
      ),
    ),
    AppTableColumn(
      'Raised',
      // The widest month, with the digits of a number cell (tabular, so each is
      // as wide as the next).
      width: sized(
        _widest(context, [
          for (final month in requestDateMonths) '00 $month 0000',
        ], AppTableRow.numberStyle(context)),
        'Raised',
      ),
      align: AppColumnAlign.end,
    ),
    AppTableColumn(
      'Outcome',
      // The toggle's label, its gap and chevron (`Spacing.xl` square).
      width: sized(_widest(context, const ['Outcome'], dense) + Spacing.xs + Spacing.xl, 'Outcome'),
    ),
  ];
}

/// One Request as a row of the register. A Request that became a Work order or was
/// declined gets a `RowDisclosure` and its toggle in the Outcome cell; one that
/// did neither renders the same row with an empty Outcome cell, so the columns
/// line up either way.
class _MyRequestTableRow extends StatelessWidget {
  const _MyRequestTableRow({super.key, required this.columns, required this.request});

  final List<AppTableColumn> columns;
  final Request request;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    final workOrder = request.workOrder;
    final declined = request.status == 'rejected' && request.rejectionReason != null;
    // The framework's padded tap target is lifted on the chips.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    Widget row(Widget outcome) => KeyedSubtree(
      key: MyRequestsScreen.rowKey(request.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(request.requestNo, style: muted),
          DisclosingText(request.summary, style: dense?.copyWith(color: palette.textPrimary)),
          DisclosingText('${request.assetName} (${request.assetCode})', style: muted),
          Text(request.urgencyLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          shrinkWrapTargets(StatusChip(label: request.statusLabel, tone: request.statusTone)),
          Text(
            formatRequestDate(request.reportedAt),
            maxLines: 1,
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
          ),
          outcome,
        ],
      ),
    );

    if (workOrder == null && !declined) return row(const SizedBox.shrink());
    return RowDisclosure(
      toggleKey: MyRequestsScreen.outcomeKey(request.id),
      label: 'Outcome',
      rowBuilder: (context, toggle) => row(toggle),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (workOrder != null)
            Row(
              children: [
                Icon(Icons.build_outlined, size: Spacing.lg, color: palette.textMuted),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    'Became Work order ${workOrder.workOrderNo}',
                    style: dense?.copyWith(color: palette.textPrimary),
                  ),
                ),
              ],
            ),
          if (workOrder != null && declined) const SizedBox(height: Spacing.sm),
          if (declined) Text('Declined: ${request.rejectionReason}', style: muted),
        ],
      ),
    );
  }
}

class _MyRequestCard extends StatelessWidget {
  const _MyRequestCard({required this.request});

  final Request request;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final workOrder = request.workOrder;

    return Card(
      key: MyRequestsScreen.rowKey(request.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.requestNo, style: muted),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        request.summary,
                        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${request.assetName} (${request.assetCode}) · ${request.urgencyLabel}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                StatusChip(label: request.statusLabel, tone: request.statusTone),
              ],
            ),
            if (workOrder != null) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(Icons.build_outlined, size: 16, color: AppColors.of(context).textMuted),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      'Became Work order ${workOrder.workOrderNo}',
                      style: AppTypography.dense(context),
                    ),
                  ),
                ],
              ),
            ],
            if (request.status == 'rejected' && request.rejectionReason != null) ...[
              const SizedBox(height: Spacing.sm),
              Text('Declined: ${request.rejectionReason}', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyRequestsEmpty extends StatelessWidget {
  const _MyRequestsEmpty({required this.canRaiseRequest, required this.siteId});

  final bool canRaiseRequest;
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    return PlatformEmptyState.noneExist(
      key: MyRequestsScreen.emptyKey,
      title: 'Nothing raised yet',
      message:
          'You have not raised any Requests at this Site. Raise one and it will '
          'show up here with whatever becomes of it.',
      actionLabel: canRaiseRequest && siteId != null ? 'Raise a Request' : null,
      actionKey: MyRequestsScreen.emptyRaiseKey,
      onAction: canRaiseRequest && siteId != null
          ? () {
              final bloc = context.read<MyRequestsBloc>();
              showDialog<void>(
                context: context,
                builder: (_) => BlocProvider<MyRequestsBloc>.value(
                  value: bloc,
                  child: RequestFormDialog(siteId: siteId!),
                ),
              );
            }
          : null,
    );
  }
}
