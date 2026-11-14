/// The meters list: the instruments an Asset's accumulated use is read from
/// (issue #79).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// the Work orders, Requests, Downtime and PM schedule Screens document. The
/// define button and the record-reading action are offered only to a caller
/// who holds a write Grant somewhere: an action the server would refuse is not
/// offered in the first place (the coarse `orgUnitScope.canWriteSomewhere`
/// signal those Screens already use).
///
/// CONTEXT.md's PM schedule entry is the point of the copy: a meter is how a
/// schedule comes due on accumulated use rather than elapsed time, and only a
/// cumulative meter can drive one.
///
/// **A register of eight columns (seven for a caller who cannot act), and a card
/// per meter below 960px of content.** At or above
/// [MetersScreen.narrowBreakpoint] (at a text scale of 1) the meters are an
/// `AppTableHeader` band and one `AppTableRow` per meter, both built from the one
/// column spec [_columns]; below it, the card this Screen has always had. The
/// Site dropdown stays in the header, not in the list's toolbar: it must stay
/// reachable when the list is absent (a Site with no meters shows `_MetersEmpty`),
/// while the filter box needs the rows it narrows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
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
import 'meter.dart';
import 'meter_form_dialog.dart';
import 'meters_bloc.dart';
import 'reading_form_dialog.dart';

class MetersScreen extends StatelessWidget {
  const MetersScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the PM schedule
  /// Screen applies to its own actions.
  final bool canAct;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per meter, measured by `_MetersList`'s `LayoutBuilder`, never the
  /// window. It is 960, the page's own width, rather than the 700 of a five-column
  /// register: this one has eight, and at 960 the cells have about 904px (the box
  /// less the list's and the row's padding). The kind, the two number columns and
  /// the action are measured and take about 470 of that, which leaves about 430 for
  /// the four flex columns over their 10 shares: about 43px a share, so a code of
  /// about 85px, a name of about 130, an Asset of about 170 and a unit of about
  /// 35. Every band label fits its cell; the code, name and Asset text clip on
  /// many rows and `DisclosingText` discloses it, as it does the carried-forward
  /// line. Narrower and the shares fall under what the labels need. The register
  /// is therefore drawn only when the page frame is at its full width.
  static const double narrowBreakpoint = 960;

  static const ValueKey<String> createKey = ValueKey<String>('meters-create');
  static const ValueKey<String> siteKey = ValueKey<String>('meters-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('meters-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('meters-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('meters-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('meters-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('meter-row-$id');
  static ValueKey<String> readingKey(String id) => ValueKey<String>('meter-reading-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'meters-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's meters renders — a different fact
  /// from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('meters-no-match');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<MetersBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is MetersLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              MetersLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              MetersUnavailable(message: final message) => PlatformFailureState(
                key: MetersScreen.failedKey,
                title: l10n.metersUnavailableTitle,
                message: message,
                retryKey: MetersScreen.retryKey,
                onRetry: () => context.read<MetersBloc>().add(const MetersStarted()),
              ),
              MetersLoaded(isLoadingMeters: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              MetersLoaded(meters: final meters) when meters.isEmpty => const _MetersEmpty(),
              MetersLoaded(meters: final meters) => _MetersList(meters: meters, canAct: canAct),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final MetersState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = state is MetersLoaded ? state as MetersLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: MetersScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.navMeters,
            description: l10n.metersDescription,
            actions: [
              if (canAct && loaded != null)
                FilledButton.icon(
                  key: MetersScreen.createKey,
                  onPressed: loaded.isMutating || loaded.siteId == null
                      ? null
                      : () => MeterFormDialog.open(context, siteId: loaded.siteId!),
                  icon: const Icon(Icons.speed_outlined),
                  label: Text(l10n.metersDefine),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
            below: loaded != null && loaded.sites.length > 1
                ? SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: MetersScreen.siteKey,
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
                        context.read<MetersBloc>().add(MetersSiteSelected(siteId));
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
        maxWidth: MetersScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: MetersScreen.noticeKey,
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

/// The list of meters. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _MetersList extends StatefulWidget {
  const _MetersList({required this.meters, required this.canAct});

  final List<AssetMeter> meters;
  final bool canAct;

  @override
  State<_MetersList> createState() => _MetersListState();
}

class _MetersListState extends State<_MetersList> {
  /// What the filter box is narrowing the Site's meters to, `''` when nothing
  /// is.
  String _term = '';

  /// Whether [meter] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the meter's own name and code and the
  /// Asset it reads — the four ways a planner names the instrument they mean.
  /// No ranking and no fuzzy matching, the same rule the assign dialog's own
  /// filter uses (issue #187).
  static bool _matches(AssetMeter meter, String term) =>
      meter.name.toLowerCase().contains(term) ||
      meter.code.toLowerCase().contains(term) ||
      meter.assetName.toLowerCase().contains(term) ||
      meter.assetCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<AssetMeter> get _matchingMeters {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.meters;
    return widget.meters.where((meter) => _matches(meter, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingMeters;
    final l10n = AppLocalizations.of(context);
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < AppBreakpoints.effective(context, MetersScreen.narrowBreakpoint);
        final columns = _columns(context, canAct: widget.canAct);
        return Center(
          child: AppPageFrame(
            maxWidth: MetersScreen.maxWidth,
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
                            name: MetersScreen.filterFieldName,
                            label: l10n.metersFilter,
                            helperText: l10n.metersFilterHelp,
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.meters.length,
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
                          key: MetersScreen.noMatchKey,
                          title: l10n.metersNoMatch,
                          message: l10n.metersNoMatchMessage(_term.trim()),
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) =>
                              _MeterCard(meter: matches[index], canAct: widget.canAct),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            for (final meter in matches)
                              _MeterTableRow(columns: columns, meter: meter, canAct: widget.canAct),
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

/// The widest of [labels] in the button or chip label style at the reader's text
/// scale, for a column that must hold any of them.
double _widestLabel(BuildContext context, Iterable<String> labels) {
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
  return widest;
}

/// A band label's width in the band's own style (`AppTableHeader`: `labelMedium`,
/// w600, letter spacing 0.2) at the reader's text scale, so a number column
/// sized to it never ellipsizes its label.
double _bandLabelWidth(BuildContext context, String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// The Latest reading column's width: the wider of its band label and the
/// "No reading yet" a meter with no reading shows, plus the slot's gutter.
double _latestColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final painter = TextPainter(
    text: TextSpan(text: l10n.metersNoReading, style: AppTypography.dense(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final label = _bandLabelWidth(context, l10n.metersLatestReading);
  return (painter.width > label ? painter.width : label) + Spacing.sm;
}

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a header label and its cells start at the same x.
/// The values and their order are the card's: the meter's code, its name, the
/// Asset it reads (with its Org Unit), the kind, the unit, the latest reading and
/// the accumulated use (both numbers, so end-aligned in tabular figures), then the
/// one action. A caller who cannot act has no Actions column at all, as the card
/// has no button.
List<AppTableColumn> _columns(BuildContext context, {required bool canAct}) {
  final l10n = AppLocalizations.of(context);
  return [
    AppTableColumn(l10n.commonCode, flex: 2),
    AppTableColumn(l10n.commonName, flex: 3),
    AppTableColumn(l10n.commonAsset, flex: 4),
    // A compact `Chip`'s padding and label padding (`Spacing.xxl`), then the gutter.
    AppTableColumn(
      l10n.metersType,
      width:
          _widestLabel(context, [
                for (final type in MeterType.values) meterTypeLabel(l10n, type.wire),
              ]) +
          Spacing.xxl +
          Spacing.sm,
    ),
    AppTableColumn(l10n.metersUnit, flex: 1),
    // The number columns are sized to their label, which is wider than their
    // digits; the latest reading is also sized to its "No reading yet" words.
    AppTableColumn(l10n.metersLatestReading,
        width: _latestColumnWidth(context), align: AppColumnAlign.end),
    AppTableColumn(
      l10n.metersAccumulated,
      width: _bandLabelWidth(context, l10n.metersAccumulated) + Spacing.sm,
      align: AppColumnAlign.end,
    ),
    if (canAct)
      AppTableColumn(
        l10n.commonActions,
        // The button's label, its own horizontal padding either side (`Spacing.xl`),
        // and the slot's gutter.
        width:
            _widestLabel(context, [l10n.workOrderRecordReading]) + 2 * Spacing.xl + Spacing.sm,
        align: AppColumnAlign.end,
      ),
  ];
}

/// A reading as the card words it: a whole number without its `.0`.
String _number(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

class _MeterTableRow extends StatelessWidget {
  const _MeterTableRow({required this.columns, required this.meter, required this.canAct});

  final List<AppTableColumn> columns;
  final AssetMeter meter;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final state = context.watch<MetersBloc>().state;
    final busy = state is MetersLoaded && state.isMutating;
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    final number = AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary);
    // The framework's padded tap target is lifted on the chip and the button: the
    // button states its own 44 through `minimumSize`, and the padded target would
    // add height to the row.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    return KeyedSubtree(
      key: MetersScreen.rowKey(meter.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(meter.code, style: muted),
          DisclosingText(meter.name, style: dense?.copyWith(color: palette.textPrimary)),
          DisclosingText(
            '${meter.assetName} (${meter.assetCode}) · ${meter.orgUnitName}',
            style: muted,
          ),
          shrinkWrapTargets(
            Chip(
              label: Text(meterTypeLabel(l10n, meter.meterType)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          DisclosingText(meter.uomCode, style: muted),
          meter.latestReading == null
              ? Text(l10n.metersNoReading,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)
              : Text(_number(meter.latestReading!), maxLines: 1, style: number),
          // The carried-forward total is part of the card's story, so it stays,
          // under the accumulated number, and only on a meter that has one.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_number(meter.accumulatedUse), maxLines: 1, style: number),
              if (meter.rolloverOffset > 0)
                DisclosingText(
                  l10n.metersCarriedForward('${meter.rolloverOffset}', meter.uomCode),
                  style: muted,
                ),
            ],
          ),
          if (canAct)
            shrinkWrapTargets(
              OutlinedButton(
                key: MetersScreen.readingKey(meter.id),
                onPressed: busy ? null : () => ReadingFormDialog.open(context, meter: meter),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: Text(l10n.workOrderRecordReading),
              ),
            ),
        ],
      ),
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.meter, required this.canAct});

  final AssetMeter meter;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final state = context.watch<MetersBloc>().state;
    final busy = state is MetersLoaded && state.isMutating;

    return Card(
      key: MetersScreen.rowKey(meter.id),
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
                        '${meter.name} (${meter.code})',
                        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${meter.assetName} (${meter.assetCode}) · ${meter.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(
                  label: Text(meterTypeLabel(l10n, meter.meterType)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.metersLatestLine(meter.latestReadingLabel), style: muted),
                Text(l10n.metersAccumulatedLine(meter.accumulatedLabel), style: muted),
                if (meter.rolloverOffset > 0)
                  Text(l10n.metersCarriedForward('${meter.rolloverOffset}', meter.uomCode),
                      style: muted),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: MetersScreen.readingKey(meter.id),
                onPressed: busy ? null : () => ReadingFormDialog.open(context, meter: meter),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(l10n.workOrderRecordReading),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetersEmpty extends StatelessWidget {
  const _MetersEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlatformEmptyState.noneExist(
      key: MetersScreen.emptyKey,
      title: l10n.metersNoneExistTitle,
      message: l10n.metersNoneExistMessage,
    );
  }
}
