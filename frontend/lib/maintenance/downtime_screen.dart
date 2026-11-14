/// The Downtime Screen: the machines not running at a Site, each offering
/// Close and Classify, with one action to report a Breakdown (issue #73).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// `WorkOrdersScreen` and `RequestsScreen` document. The row actions and the
/// report button are offered only to a caller who holds a write Grant
/// somewhere: an action the server would refuse is not offered in the first
/// place (the coarse `orgUnitScope.canWriteSomewhere` signal those Screens
/// already use).
///
/// CONTEXT.md's distinction is load-bearing in the copy: reporting a Breakdown
/// is the machine stopping, and the Downtime it produces is the period the
/// machine was not running — this Screen never derives or shows a
/// client-computed duration, only the status and reason the server sent.
///
/// **A register of seven columns, and a card per stop below 900px of content.**
/// At or above [DowntimeScreen.narrowBreakpoint] (at a text scale of 1) the stops
/// are an `AppTableHeader` band and one `AppTableRow` per stop, both built from
/// the one column spec [_columns]; below it, the card this Screen has always had.
/// A stop's description is prose, not a value to compare down a column, so the
/// register keeps it one press away in a `RowDisclosure` under the row. A row
/// offers Close inline while the stop is open and keeps Classify, which only an
/// unclassified stop has, in a kebab beside it, the shape `WorkOrdersScreen`'s rows
/// settled. The Site dropdown stays in the header, not in the list's toolbar: it
/// must stay reachable when the list is absent (a Site with no stops shows
/// `_DowntimeEmpty`, and a failed read shows the failure state), while the filter
/// box needs the rows it narrows.
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
import 'breakdown_report_dialog.dart';
import 'downtime_bloc.dart';
import 'downtime_classify_dialog.dart';
import 'downtime_close_dialog.dart';
import 'downtime_event.dart';
import 'row_disclosure.dart';
import '../widgets/notice_text.dart';
import '../l10n/vocabulary.dart';

class DowntimeScreen extends StatelessWidget {
  const DowntimeScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the Work order and
  /// Triage queues apply to their own row actions. False hides Close, Classify
  /// and Report entirely; it does not grey them out, because a disabled button
  /// is still an invitation to fail.
  final bool canAct;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per stop, measured by `_DowntimeList`'s `LayoutBuilder`, never
  /// the window. It is 900 rather than the 700 of a five-column register: this one
  /// has seven. At 900 the cells have about 844px (the box less the list's and
  /// the row's padding); the status, the start, the description toggle and the
  /// actions are measured and take about 500 of that, which leaves about 344 for
  /// the three flex columns over their 7 shares: about 49px a share, so an Asset
  /// of about 147px and a Reason and a Reported by of about 98 each. The longest
  /// band label, "Reported by", needs about 72px in its two shares, so it fits;
  /// below about 835px of content it stops fitting, and 900 leaves a margin. The
  /// register is therefore drawn only from 900.
  static const double narrowBreakpoint = 900;

  /// The toggle that opens a register row's description.
  static ValueKey<String> detailsKey(String id) => ValueKey<String>('downtime-details-$id');

  /// The overflow trigger of a register row: a kebab holding Classify under
  /// [classifyKey]. Its own `onPressed` is null while an act is in flight, as
  /// Close's is. Present in the register only; the card keeps both acts inline.
  static ValueKey<String> rowActionsKey(String id) => ValueKey<String>('downtime-actions-$id');

  static const ValueKey<String> reportKey = ValueKey<String>('downtime-report');
  static const ValueKey<String> siteKey = ValueKey<String>('downtime-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('downtime-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('downtime-retry');
  static const ValueKey<String> truncatedKey = ValueKey<String>('downtime-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('downtime-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('downtime-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('downtime-row-$id');
  static ValueKey<String> closeKey(String id) => ValueKey<String>('downtime-close-$id');
  static ValueKey<String> classifyKey(String id) => ValueKey<String>('downtime-classify-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'downtime-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's downtime records renders — a
  /// different fact from [emptyKey]: "nothing matched" is not "there is nothing
  /// here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('downtime-no-match');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<DowntimeBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is DowntimeLoaded && state.notice != null) _Notice(message: state.notice!),
          if (state is DowntimeLoaded && state.truncated) const _Truncated(),
          Expanded(
            child: switch (state) {
              DowntimeLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              DowntimeUnavailable(message: final message) => PlatformFailureState(
                key: DowntimeScreen.failedKey,
                title: l10n.downtimeUnavailableTitle,
                message: message,
                retryKey: DowntimeScreen.retryKey,
                onRetry: () => context.read<DowntimeBloc>().add(const DowntimeStarted()),
              ),
              DowntimeLoaded(isLoadingEvents: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              DowntimeLoaded(events: final events) when events.isEmpty => const _DowntimeEmpty(),
              DowntimeLoaded(events: final events) => _DowntimeList(events: events, canAct: canAct),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final DowntimeState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = state is DowntimeLoaded ? state as DowntimeLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: DowntimeScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.navDowntime,
            description: l10n.downtimeDescription,
            actions: [
              if (canAct && loaded != null)
                FilledButton.icon(
                  key: DowntimeScreen.reportKey,
                  onPressed: loaded.isReporting || loaded.siteId == null
                      ? null
                      : () => _openReport(context, loaded.siteId!),
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: Text(l10n.downtimeReport),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
            below: loaded != null && loaded.sites.length > 1
                ? SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: DowntimeScreen.siteKey,
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
                        context.read<DowntimeBloc>().add(DowntimeSiteSelected(siteId));
                      },
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// The report dialog is opened with the same `showDialog` shape the Triage
  /// queue's dialogs use: it pushes onto the root Navigator, above the
  /// route-scoped [DowntimeBloc], so the Bloc is re-provided by value.
  Future<void> _openReport(BuildContext context, String siteId) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: BreakdownReportDialog(siteId: siteId),
      ),
    );
  }
}

/// The list was capped. Said out loud rather than left to be inferred from a
/// list that happens to end (ADR-0026).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: DowntimeScreen.maxWidth,
        child: Padding(
          key: DowntimeScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            l10n.downtimeTruncated,
            style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textMuted),
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
        maxWidth: DowntimeScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: DowntimeScreen.noticeKey,
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
                  child: NoticeText(
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

/// The list of stops. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _DowntimeList extends StatefulWidget {
  const _DowntimeList({required this.events, required this.canAct});

  final List<DowntimeEvent> events;
  final bool canAct;

  @override
  State<_DowntimeList> createState() => _DowntimeListState();
}

class _DowntimeListState extends State<_DowntimeList> {
  /// What the filter box is narrowing the Site's stops to, `''` when nothing
  /// is.
  String _term = '';

  /// Whether [event] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over what identifies a stop — the Asset that
  /// went down, the reason it was classified as, and the words recorded
  /// against it. No ranking and no fuzzy matching, the same rule the assign
  /// dialog's own filter uses (issue #187).
  static bool _matches(DowntimeEvent event, String term) =>
      event.assetName.toLowerCase().contains(term) ||
      event.assetCode.toLowerCase().contains(term) ||
      (event.downtimeReasonName ?? '').toLowerCase().contains(term) ||
      (event.description ?? '').toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<DowntimeEvent> get _matchingEvents {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.events;
    return widget.events.where((event) => _matches(event, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingEvents;
    final l10n = AppLocalizations.of(context);
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            AppBreakpoints.effective(context, DowntimeScreen.narrowBreakpoint);
        final columns = _columns(context, canAct: widget.canAct);
        return Center(
          child: AppPageFrame(
            maxWidth: DowntimeScreen.maxWidth,
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
                            name: DowntimeScreen.filterFieldName,
                            label: l10n.downtimeFilter,
                            helperText: l10n.downtimeFilterHelp,
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.events.length,
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
                          key: DowntimeScreen.noMatchKey,
                          title: l10n.downtimeNoMatch,
                          message: l10n.downtimeNoMatchMessage(_term.trim()),
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) =>
                              _DowntimeCard(event: matches[index], canAct: widget.canAct),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            // Keyed by the stop's id so a row that is open stays
                            // open when the list rebuilds on a filter keystroke.
                            for (final event in matches)
                              _DowntimeTableRow(
                                key: ValueKey<String>('downtime-disclosure-${event.id}'),
                                columns: columns,
                                event: event,
                                canAct: widget.canAct,
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
/// and their order are the card's: the Asset (its name over `code · Org Unit`),
/// the status, when it started, the Reason and who reported it, then the acts.
/// "Started", "Reason" and "Reported by" move out of the cells into the band; the
/// description, which the card does not draw, is behind a toggle in Details.
/// A caller who cannot act has no Actions column at all, as the card has no
/// buttons.
///
/// The measured columns are the ones whose content is bounded: the status chip
/// (its widest label), the start (a fixed-format instant), the toggle, and the
/// actions (Close, the kebab, and the gap), each plus the slot's `Spacing.sm`
/// gutter, and never narrower than their own band label.
List<AppTableColumn> _columns(BuildContext context, {required bool canAct}) {
  double sized(double content, String label) {
    final bandLabel = _bandLabelWidth(context, label);
    return (content > bandLabel ? content : bandLabel) + Spacing.sm;
  }

  final dense = AppTypography.dense(context);
  final l10n = AppLocalizations.of(context);
  return [
    AppTableColumn(l10n.commonAsset, flex: 3),
    AppTableColumn(
      l10n.commonStatus,
      // A chip's own padding and label padding (`Spacing.xxl`).
      width: sized(
        _widest(context, const [
              'Open',
              'Unclassified',
              'Closed',
            ], Theme.of(context).textTheme.labelLarge) +
            Spacing.xxl,
        l10n.commonStatus,
      ),
    ),
    AppTableColumn(
      l10n.downtimeStarted,
      width: sized(
          _widest(context, const ['0000-00-00 00:00'], dense), l10n.downtimeStarted),
    ),
    AppTableColumn(l10n.downtimeReason, flex: 2),
    AppTableColumn(l10n.downtimeReportedByColumn, flex: 2),
    AppTableColumn(
      l10n.commonDetails,
      // The toggle's label, its gap and chevron (`Spacing.xl` square), at least a
      // 44px target.
      width: sized(
        _widest(context, [l10n.commonDescription], dense) + Spacing.xs + Spacing.xl,
        l10n.commonDetails,
      ),
    ),
    if (canAct)
      AppTableColumn(
        l10n.commonActions,
        // Close (its label and the button's horizontal padding either side, in
        // `Spacing.xl`), the gap, and the kebab at the 44px floor.
        width:
            _widest(context, [l10n.downtimeClose], Theme.of(context).textTheme.labelLarge) +
            2 * Spacing.xl +
            Spacing.sm +
            AppTouchTarget.min +
            Spacing.sm,
        align: AppColumnAlign.end,
      ),
  ];
}

/// One stop as a row of the register. A stop that carries a description gets a
/// `RowDisclosure` and its toggle in the Details cell; one that does not renders
/// the same row with an empty Details cell, so the columns line up either way.
class _DowntimeTableRow extends StatelessWidget {
  const _DowntimeTableRow({
    super.key,
    required this.columns,
    required this.event,
    required this.canAct,
  });

  final List<AppTableColumn> columns;
  final DowntimeEvent event;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    // The framework's padded tap target is lifted on the chip and the buttons:
    // each button states its own 44 through `minimumSize`.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    Widget row(Widget details) => KeyedSubtree(
      key: DowntimeScreen.rowKey(event.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DisclosingText(event.assetName, style: dense?.copyWith(color: palette.textPrimary)),
              DisclosingText('${event.assetCode} · ${event.orgUnitName}', style: muted),
            ],
          ),
          shrinkWrapTargets(StatusChip(label: event.statusLabel(l10n), tone: event.statusTone)),
          Text(
            _formatInstant(event.startedAt, l10n),
            maxLines: 1,
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          // An unknown value is the em dash, never a blank (design-language §13).
          DisclosingText(event.downtimeReasonName ?? '—', style: muted),
          DisclosingText(event.reporterName ?? '—', style: muted),
          details,
          if (canAct) shrinkWrapTargets(_DowntimeRowActions(event: event)),
        ],
      ),
    );

    final description = event.description;
    if (description == null || description.isEmpty) return row(const SizedBox.shrink());
    return RowDisclosure(
      toggleKey: DowntimeScreen.detailsKey(event.id),
      label: AppLocalizations.of(context).commonDescription,
      rowBuilder: (context, toggle) => row(toggle),
      child: Text(description, style: dense?.copyWith(color: palette.textPrimary)),
    );
  }
}

/// A register row's acts: Close inline while the stop is open, and Classify in a
/// kebab while it is unclassified — the shape of `WorkOrdersScreen`'s
/// `_RowActions`. A stop that needs neither renders nothing; a closed, unclassified
/// stop renders the kebab alone, at the cell's end, where the kebab of every other
/// row sits. Both are disabled while an act is in flight, and each is read off its
/// own `onPressed`.
class _DowntimeRowActions extends StatelessWidget {
  const _DowntimeRowActions({required this.event});

  final DowntimeEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<DowntimeBloc>().state;
    final busy = state is DowntimeLoaded && state.isActing;
    const size = Size(AppTouchTarget.min, AppTouchTarget.min);
    if (!event.isOpen && event.isClassified) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (event.isOpen)
          FilledButton(
            key: DowntimeScreen.closeKey(event.id),
            onPressed: busy ? null : () => _openClose(context, event),
            style: FilledButton.styleFrom(minimumSize: size),
            child: Text(l10n.downtimeClose),
          ),
        if (event.isOpen && !event.isClassified) const SizedBox(width: Spacing.sm),
        if (!event.isClassified)
          Builder(
            builder: (buttonContext) => IconButton(
              key: DowntimeScreen.rowActionsKey(event.id),
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
    final selected = await showMenu<Key>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<Key>(
          key: DowntimeScreen.classifyKey(event.id),
          value: DowntimeScreen.classifyKey(event.id),
          child: Text(AppLocalizations.of(context).downtimeClassify),
        ),
      ],
    );
    if (selected == null || !context.mounted) return;
    await _openClassify(context, event);
  }
}

Future<void> _openClose(BuildContext context, DowntimeEvent event) {
  final bloc = context.read<DowntimeBloc>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider<DowntimeBloc>.value(
      value: bloc,
      child: DowntimeCloseDialog(downtimeEvent: event),
    ),
  );
}

Future<void> _openClassify(BuildContext context, DowntimeEvent event) {
  final bloc = context.read<DowntimeBloc>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider<DowntimeBloc>.value(
      value: bloc,
      child: DowntimeClassifyDialog(downtimeEvent: event),
    ),
  );
}

class _DowntimeCard extends StatelessWidget {
  const _DowntimeCard({required this.event, required this.canAct});

  final DowntimeEvent event;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final state = context.watch<DowntimeBloc>().state;
    final busy = state is DowntimeLoaded && state.isActing;

    return Card(
      key: DowntimeScreen.rowKey(event.id),
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
                      Text(
                        event.assetName,
                        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text('${event.assetCode} · ${event.orgUnitName}', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                StatusChip(label: event.statusLabel(l10n), tone: event.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.downtimeStartedAt(_formatInstant(event.startedAt, l10n)),
                    style: muted),
                if (event.downtimeReasonName != null)
                  Text(l10n.downtimeReasonLine(event.downtimeReasonName!), style: muted),
                if (event.reporterName != null)
                  Text(l10n.downtimeReportedByPerson(event.reporterName!), style: muted),
              ],
            ),
            if (canAct && (event.isOpen || !event.isClassified)) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  if (event.isOpen)
                    FilledButton(
                      key: DowntimeScreen.closeKey(event.id),
                      onPressed: busy ? null : () => _openClose(context),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: Text(l10n.downtimeClose),
                    ),
                  if (!event.isClassified)
                    OutlinedButton(
                      key: DowntimeScreen.classifyKey(event.id),
                      onPressed: busy ? null : () => _openClassify(context),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: Text(l10n.downtimeClassify),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openClose(BuildContext context) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: DowntimeCloseDialog(downtimeEvent: event),
      ),
    );
  }

  Future<void> _openClassify(BuildContext context) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: DowntimeClassifyDialog(downtimeEvent: event),
      ),
    );
  }
}

class _DowntimeEmpty extends StatelessWidget {
  const _DowntimeEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlatformEmptyState.noneExist(
      key: DowntimeScreen.emptyKey,
      title: l10n.downtimeNoneExistTitle,
      message: l10n.downtimeNoneExistMessage,
    );
  }
}

/// A wire `timestamptz` shown in the device's own local time, formatted by
/// hand the way `AppDateField`/`AppDateTimeField` format theirs (no `intl`).
String _formatInstant(String? value, AppLocalizations l10n) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return l10n.commonNow;
  final local = parsed.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
