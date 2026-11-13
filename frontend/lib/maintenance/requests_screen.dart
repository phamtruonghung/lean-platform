/// The triage queue: the Requests still waiting for a decision at a Site, each
/// offering Accept, Decline and Mark duplicate (issue #72).
///
/// Readable by anyone whose role earns the Module, whatever their Grants — the
/// same reasoning `WorkOrdersScreen`'s own header documents. The three row
/// actions are offered only to a caller who holds a write Grant somewhere: an
/// action the server would refuse is not offered in the first place (the
/// coarse `orgUnitScope.canWriteSomewhere` signal, as `WorkOrdersScreen`
/// already uses).
///
/// Accepting raises a Work order for the Request; after any of the three
/// actions the Request has been triaged and leaves this queue. The link back
/// to the Work order an accepted Request produced is ADR-0014's, and the
/// requester follows it on `MyRequestsScreen`.
///
/// **A triage register, and a card per Request below 960px of content.** At or
/// above [RequestsScreen.narrowBreakpoint] (at a text scale of 1) the queue is an
/// `AppTableHeader` band and one `AppTableRow` per Request, both built from the one
/// column spec [_columns], chosen for deciding rather than for reading a record:
/// the number, the summary (and whether production is stopped), the Asset, who
/// raised it and when, the state, the urgency, and the decision itself. Accept is
/// the one act inline; Decline and Mark duplicate sit behind a kebab beside it, the
/// shape `WorkOrdersScreen`'s rows settled. The Raised column is the date the
/// Request was raised, read as a person says it (`formatRequestDate`); the card
/// does not show it. The Site dropdown stays in the header, not in the list's
/// toolbar: it must stay reachable when the list is absent (a Site with nothing
/// waiting shows `_RequestsEmpty`, and a failed read shows the failure state),
/// while the filter box needs the rows it narrows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
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
import 'request.dart';
import 'request_accept_dialog.dart';
import 'request_decline_dialog.dart';
import 'request_duplicate_dialog.dart';
import 'requests_bloc.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.canTriage});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule `WorkOrdersScreen`
  /// applies to its own row actions. False hides Accept, Decline and Mark
  /// duplicate entirely; it does not grey them out, because a disabled button
  /// is still an invitation to fail.
  final bool canTriage;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per Request, measured by `_RequestsList`'s `LayoutBuilder`, never
  /// the window. It is 960, the page's own width, rather than the 700 of a
  /// five-column register: this one has eight. At 960 the cells have about 904px
  /// (the box less the list's and the row's padding); the date, the state, the
  /// urgency and the actions are measured and take about 450 of that, which leaves
  /// about 450 for the four flex columns over their 13 shares: about 35px a share,
  /// so a Request number of about 140px (the length of `MR-BUC-2026-00001`), a
  /// summary of about 140, an Asset of about 105 and a Raised by of about 70,
  /// enough for their band labels and for `DisclosingText` to disclose the rest.
  /// Narrower and the shares fall under what the number and the labels need. The
  /// register is therefore drawn only when the page frame is at its full width.
  static const double narrowBreakpoint = 960;

  /// The overflow trigger of a register row: a kebab holding Decline and Mark
  /// duplicate under [declineKey] and [duplicateKey]. Its own `onPressed` is null
  /// while a triage act is in flight, as Accept's is. Present in the register
  /// only; the card keeps all three acts inline.
  static ValueKey<String> rowActionsKey(String id) => ValueKey<String>('request-actions-$id');

  static const ValueKey<String> siteKey = ValueKey<String>('requests-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('requests-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('requests-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('requests-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('requests-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('request-row-$id');
  static ValueKey<String> acceptKey(String id) => ValueKey<String>('request-accept-$id');
  static ValueKey<String> declineKey(String id) => ValueKey<String>('request-decline-$id');
  static ValueKey<String> duplicateKey(String id) => ValueKey<String>('request-duplicate-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'requests-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's waiting Requests renders — a
  /// different fact from [emptyKey]: "nothing matched" is not "there is
  /// nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('requests-no-match');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<RequestsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          if (state is RequestsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              RequestsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              RequestsUnavailable(message: final message) => PlatformFailureState(
                key: RequestsScreen.failedKey,
                title: l10n.requestsUnavailableTitle,
                message: message,
                retryKey: RequestsScreen.retryKey,
                onRetry: () => context.read<RequestsBloc>().add(const RequestsStarted()),
              ),
              RequestsLoaded(isLoadingRequests: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              RequestsLoaded(requests: final requests) when requests.isEmpty =>
                const _RequestsEmpty(),
              RequestsLoaded(requests: final requests) => _RequestsList(
                requests: requests,
                canTriage: canTriage,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RequestsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = state is RequestsLoaded ? state as RequestsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: RequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.navTriageQueue,
            description: l10n.requestsDescription,
            below: loaded != null && loaded.sites.length > 1
                ? SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: RequestsScreen.siteKey,
                      initialValue: loaded.siteId,
                      isDense: true,
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
                        context.read<RequestsBloc>().add(RequestsSiteSelected(siteId));
                      },
                    ),
                  )
                : null,
          ),
        ),
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
        maxWidth: RequestsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: RequestsScreen.noticeKey,
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

/// The triage queue. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _RequestsList extends StatefulWidget {
  const _RequestsList({required this.requests, required this.canTriage});

  final List<Request> requests;
  final bool canTriage;

  @override
  State<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends State<_RequestsList> {
  /// What the filter box is narrowing the waiting Requests to, `''` when
  /// nothing is.
  String _term = '';

  /// Whether [request] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a Request — its
  /// own number, the sentences that describe it, and the Asset it was raised
  /// against. No ranking and no fuzzy matching, the same rule the assign
  /// dialog's own filter uses (issue #187).
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
    final l10n = AppLocalizations.of(context);
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            AppBreakpoints.effective(context, RequestsScreen.narrowBreakpoint);
        final columns = _columns(context, canTriage: widget.canTriage, requests: widget.requests);
        return Center(
          child: AppPageFrame(
            maxWidth: RequestsScreen.maxWidth,
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
                            name: RequestsScreen.filterFieldName,
                            label: l10n.requestsFilter,
                            helperText: l10n.requestsFilterHelp,
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
                          key: RequestsScreen.noMatchKey,
                          title: l10n.requestsNoMatch,
                          message: l10n.requestsNoMatchMessage(_term.trim()),
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) =>
                              _RequestCard(request: matches[index], canTriage: widget.canTriage),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            for (final request in matches)
                              _RequestTableRow(
                                key: ValueKey<String>('request-table-row-${request.id}'),
                                columns: columns,
                                request: request,
                                canTriage: widget.canTriage,
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
/// are the card's: the Request number, the summary (with the production-stopped
/// line under it), the Asset with its Org Unit, who raised it, the urgency and the
/// acts; the state and the raised date are the queue's own. "Raised by" moves out
/// of the cell into the band. Every measured column is sized to its widest
/// possible content or its band label, whichever is wider, plus the slot's
/// `Spacing.sm` gutter. A caller who cannot triage has no Actions column at all.
///
/// [requests] is every Request the Screen holds, never the filtered few on screen:
/// a measured width that followed the filter would move the whole band, and every
/// label with it, each time a term hid the widest record.
List<AppTableColumn> _columns(
  BuildContext context, {
  required bool canTriage,
  required List<Request> requests,
}) {
  double sized(double content, String label) {
    final bandLabel = _bandLabelWidth(context, label);
    return (content > bandLabel ? content : bandLabel) + Spacing.sm;
  }

  final l10n = AppLocalizations.of(context);
  final numeric = AppTableRow.numberStyle(context);
  final labelLarge = Theme.of(context).textTheme.labelLarge;
  return [
    AppTableColumn(l10n.requestsNumberColumn, flex: 4),
    AppTableColumn(l10n.commonSummary, flex: 4),
    AppTableColumn(l10n.commonAsset, flex: 3),
    AppTableColumn(l10n.requestsRaisedBy, flex: 2),
    AppTableColumn(
      l10n.requestsRaisedDate,
      // The widest month, with the digits of a number cell (tabular, so each is
      // as wide as the next).
      width: sized(
        _widest(context, [for (final month in requestDateMonths) '00 $month 0000'], numeric),
        l10n.requestsRaisedDate,
      ),
      align: AppColumnAlign.end,
    ),
    AppTableColumn(
      l10n.commonStatus,
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
            ], labelLarge) +
            Spacing.xxl,
        l10n.commonStatus,
      ),
    ),
    AppTableColumn(
      l10n.requestsUrgency,
      width: sized(
        _widest(context, [
              for (final u in RequestUrgency.values) u.label,
              for (final r in requests) r.urgencyLabel,
            ], labelLarge) +
            Spacing.xxl,
        l10n.requestsUrgency,
      ),
    ),
    if (canTriage)
      AppTableColumn(
        l10n.commonActions,
        // Accept (its label and the button's horizontal padding either side, in
        // `Spacing.xl`), the gap, and the kebab at the 44px floor.
        width:
            _widest(context, [l10n.requestsAccept], labelLarge) +
            2 * Spacing.xl +
            Spacing.sm +
            AppTouchTarget.min +
            Spacing.sm,
        align: AppColumnAlign.end,
      ),
  ];
}

class _RequestTableRow extends StatelessWidget {
  const _RequestTableRow({
    super.key,
    required this.columns,
    required this.request,
    required this.canTriage,
  });

  final List<AppTableColumn> columns;
  final Request request;
  final bool canTriage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    // The framework's padded tap target is lifted on the chips and the buttons:
    // each button states its own 44 through `minimumSize`.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    return KeyedSubtree(
      key: RequestsScreen.rowKey(request.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(request.requestNo, style: muted),
          // Two dense lines are 40px, inside the 52px of a row with a control.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DisclosingText(request.summary, style: dense?.copyWith(color: palette.textPrimary)),
              if (request.productionStopped)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: Spacing.lg,
                      color: palette.statusDanger,
                    ),
                    const SizedBox(width: Spacing.xxs),
                    Flexible(
                      child: Text(
                        l10n.requestsProductionStopped,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dense?.copyWith(color: palette.statusDanger),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          DisclosingText(
            '${request.assetName} (${request.assetCode}) · ${request.orgUnitName}',
            style: muted,
          ),
          // An unknown value is the em dash, never a blank (design-language §13).
          DisclosingText(request.reporterName ?? '—', style: muted),
          Text(
            formatRequestDate(request.reportedAt),
            maxLines: 1,
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
          ),
          shrinkWrapTargets(StatusChip(label: request.statusLabel, tone: request.statusTone)),
          shrinkWrapTargets(
            Chip(label: Text(request.urgencyLabel), visualDensity: VisualDensity.compact),
          ),
          if (canTriage) shrinkWrapTargets(_RequestRowActions(request: request)),
        ],
      ),
    );
  }
}

/// A register row's acts: Accept inline, and Decline and Mark duplicate in a
/// kebab — the shape of `WorkOrdersScreen`'s `_RowActions`. Both are disabled
/// while a triage act is in flight, and each is read off its own `onPressed`.
class _RequestRowActions extends StatelessWidget {
  const _RequestRowActions({required this.request});

  final Request request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<RequestsBloc>().state;
    final busy = state is RequestsLoaded && state.isTriaging;
    const size = Size(AppTouchTarget.min, AppTouchTarget.min);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          key: RequestsScreen.acceptKey(request.id),
          onPressed: busy ? null : () => _openAccept(context, request),
          style: FilledButton.styleFrom(minimumSize: size),
          child: Text(l10n.requestsAccept),
        ),
        const SizedBox(width: Spacing.sm),
        Builder(
          builder: (buttonContext) => IconButton(
            key: RequestsScreen.rowActionsKey(request.id),
            tooltip: l10n.commonMoreActions,
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : () => _openMenu(buttonContext),
          ),
        ),
      ],
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final l10n = AppLocalizations.of(context);
    final decline = RequestsScreen.declineKey(request.id);
    final duplicate = RequestsScreen.duplicateKey(request.id);
    final selected = await showMenu<Key>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<Key>(key: decline, value: decline, child: Text(l10n.requestsDecline)),
        PopupMenuItem<Key>(
            key: duplicate, value: duplicate, child: Text(l10n.requestsMarkDuplicate)),
      ],
    );
    if (selected == null || !context.mounted) return;
    if (selected == decline) {
      await _openDecline(context, request);
    } else {
      await _openDuplicate(context, request);
    }
  }
}

Future<void> _openAccept(BuildContext context, Request request) {
  // `showDialog` pushes onto the root Navigator, above the route-scoped
  // `RequestsBloc` — re-provide the same instance so the dialog's own context can
  // read it.
  final bloc = context.read<RequestsBloc>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider<RequestsBloc>.value(
      value: bloc,
      child: RequestAcceptDialog(request: request),
    ),
  );
}

Future<void> _openDecline(BuildContext context, Request request) {
  final bloc = context.read<RequestsBloc>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider<RequestsBloc>.value(
      value: bloc,
      child: RequestDeclineDialog(request: request),
    ),
  );
}

Future<void> _openDuplicate(BuildContext context, Request request) {
  final bloc = context.read<RequestsBloc>();
  final state = bloc.state;
  final candidates = state is RequestsLoaded
      ? [
          for (final other in state.requests)
            if (other.id != request.id) other,
        ]
      : const <Request>[];
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider<RequestsBloc>.value(
      value: bloc,
      child: RequestDuplicateDialog(request: request, candidates: candidates),
    ),
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.canTriage});

  final Request request;
  final bool canTriage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<RequestsBloc>().state;
    final busy = state is RequestsLoaded && state.isTriaging;
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);

    return Card(
      key: RequestsScreen.rowKey(request.id),
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
                        '${request.assetName} (${request.assetCode}) · ${request.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(request.urgencyLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (request.reporterName != null)
                  Text(l10n.requestsRaisedByPerson(request.reporterName!), style: muted),
                if (request.productionStopped)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 16,
                        color: AppColors.of(context).statusDanger,
                      ),
                      const SizedBox(width: Spacing.xxs),
                      // Flexible, so at a large text size the words wrap inside the
                      // card rather than running past its edge.
                      Flexible(
                        child: Text(
                          l10n.requestsProductionStopped,
                          style: AppTypography.floor(context)
                              ?.copyWith(color: AppColors.of(context).statusDanger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (canTriage) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton(
                    key: RequestsScreen.acceptKey(request.id),
                    onPressed: busy ? null : () => _openAccept(context),
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: Text(l10n.requestsAccept),
                  ),
                  OutlinedButton(
                    key: RequestsScreen.declineKey(request.id),
                    onPressed: busy ? null : () => _openDecline(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: Text(l10n.requestsDecline),
                  ),
                  OutlinedButton(
                    key: RequestsScreen.duplicateKey(request.id),
                    onPressed: busy ? null : () => _openDuplicate(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: Text(l10n.requestsMarkDuplicate),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAccept(BuildContext context) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `RequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it.
    final bloc = context.read<RequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestAcceptDialog(request: request),
      ),
    );
  }

  Future<void> _openDecline(BuildContext context) {
    // `showDialog` pushes onto the root Navigator, above the route-scoped
    // `RequestsBloc` — re-provide the same instance so the dialog's own
    // context can read it.
    final bloc = context.read<RequestsBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestDeclineDialog(request: request),
      ),
    );
  }

  Future<void> _openDuplicate(BuildContext context) {
    final bloc = context.read<RequestsBloc>();
    final state = bloc.state;
    final candidates = state is RequestsLoaded
        ? [
            for (final other in state.requests)
              if (other.id != request.id) other,
          ]
        : const <Request>[];
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestDuplicateDialog(request: request, candidates: candidates),
      ),
    );
  }
}

class _RequestsEmpty extends StatelessWidget {
  const _RequestsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlatformEmptyState.noneExist(
      key: RequestsScreen.emptyKey,
      title: l10n.requestsNoneExistTitle,
      message: l10n.requestsNoneExistMessage,
    );
  }
}
