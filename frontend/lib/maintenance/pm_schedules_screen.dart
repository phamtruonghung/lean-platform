/// The PM schedule list: the plans attached to a Site's Assets that raise a
/// Work order before something breaks (issue #74).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// `WorkOrdersScreen`, `RequestsScreen` and `DowntimeScreen` document. The
/// create button and the deactivate/reactivate action are offered only to a
/// caller who holds a write Grant somewhere: an action the server would refuse
/// is not offered in the first place (the coarse `orgUnitScope.
/// canWriteSomewhere` signal those Screens already use).
///
/// CONTEXT.md's distinction is load-bearing in the copy: a PM schedule is what
/// raises a Work order ahead of a failure, and the anchor says which way its
/// calendar rolls when work runs late.
///
/// **A register of seven columns, and a card per schedule below 960px of
/// content.** At or above [PmSchedulesScreen.narrowBreakpoint] (at a text scale of
/// 1) the schedules are an `AppTableHeader` band and one `AppTableRow` per
/// schedule, both built from the one column spec [_columns]. The rules that do not
/// compare down a column (`Rolls from…`, `Raised N days early`, `Accumulated…`)
/// stay one press away in a `RowDisclosure` under the row, verbatim; the card
/// below the breakpoint shows them all, as it always has. The Site selector stays
/// in the header, not in the list's toolbar: it must stay reachable when the list
/// is absent (a Site with nothing scheduled shows `_PmSchedulesEmpty`), while the
/// filter box needs the rows it narrows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
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
import 'pm_schedule.dart';
import 'name_with_chip.dart';
import 'pm_schedule_form_dialog.dart';
import 'pm_schedules_bloc.dart';
import 'row_disclosure.dart';

class PmSchedulesScreen extends StatelessWidget {
  const PmSchedulesScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the Downtime and
  /// Triage queues apply to their own actions. False hides the create button
  /// and the row toggle entirely; it does not grey them out, because a
  /// disabled button is still an invitation to fail.
  final bool canAct;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per schedule, measured by `_PmSchedulesList`'s `LayoutBuilder`,
  /// never the window. It is 960, the page's own width, rather than the 700 of a
  /// five-column register: this one has seven, and at 960 the cells have about
  /// 904px (the box less the list's and the row's padding). The Priority and the
  /// Actions columns are measured and take about 180 of that, which leaves about
  /// 724 for the five flex columns over their 15 shares: about 48px a share, so a
  /// plan or an Interval cell of about 145px, an Asset of about 190 and a Rules
  /// cell of about 95, enough for the toggle. Every band label fits its cell; the
  /// plan, Asset, Interval and Due text clip on most rows and
  /// `DisclosingText` discloses it. Below 960 it stops holding: at 800 a share is
  /// about 38px, the Rules cell about 75 less its gutter, and the toggle no longer
  /// fits it. The register is therefore drawn only when the page frame is at its
  /// full width.
  static const double narrowBreakpoint = 960;

  /// The toggle that opens a register row's rules.
  static ValueKey<String> rulesKey(String id) => ValueKey<String>('pm-schedule-rules-$id');

  static const ValueKey<String> createKey = ValueKey<String>('pm-schedules-create');
  static const ValueKey<String> siteKey = ValueKey<String>('pm-schedules-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('pm-schedules-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('pm-schedules-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('pm-schedules-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('pm-schedules-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('pm-schedule-row-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'pm-schedules-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's PM schedules renders — a different
  /// fact from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('pm-schedules-no-match');
  static ValueKey<String> toggleKey(String id) => ValueKey<String>('pm-schedule-toggle-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('pm-schedule-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PmSchedulesBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is PmSchedulesLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              PmSchedulesLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              PmSchedulesUnavailable(message: final message) => PlatformFailureState(
                key: PmSchedulesScreen.failedKey,
                title: 'The PM schedules could not be read',
                message: message,
                retryKey: PmSchedulesScreen.retryKey,
                onRetry: () => context.read<PmSchedulesBloc>().add(const PmSchedulesStarted()),
              ),
              PmSchedulesLoaded(isLoadingSchedules: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              PmSchedulesLoaded(schedules: final schedules) when schedules.isEmpty =>
                const _PmSchedulesEmpty(),
              PmSchedulesLoaded(schedules: final schedules) => _PmSchedulesList(
                schedules: schedules,
                canAct: canAct,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final PmSchedulesState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final loaded = state is PmSchedulesLoaded ? state as PmSchedulesLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: PmSchedulesScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'PM schedules',
            description:
                'The Job plans attached to this Site\'s Assets that raise a Work order '
                'before something breaks.',
            actions: [
              if (canAct && loaded != null)
                FilledButton.icon(
                  key: PmSchedulesScreen.createKey,
                  onPressed: loaded.isMutating || loaded.siteId == null
                      ? null
                      : () => PmScheduleFormDialog.open(context, siteId: loaded.siteId!),
                  icon: const Icon(Icons.event_repeat_outlined),
                  label: const Text('Add a PM schedule'),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
            below: loaded != null && loaded.sites.length > 1
                ? SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: PmSchedulesScreen.siteKey,
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
                        context.read<PmSchedulesBloc>().add(PmSchedulesSiteSelected(siteId));
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
        maxWidth: PmSchedulesScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: PmSchedulesScreen.noticeKey,
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

/// The list of PM schedules. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _PmSchedulesList extends StatefulWidget {
  const _PmSchedulesList({required this.schedules, required this.canAct});

  final List<PmSchedule> schedules;
  final bool canAct;

  @override
  State<_PmSchedulesList> createState() => _PmSchedulesListState();
}

class _PmSchedulesListState extends State<_PmSchedulesList> {
  /// What the filter box is narrowing the Site's PM schedules to, `''` when
  /// nothing is.
  String _term = '';

  /// Whether [schedule] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the schedule's own name and code, the
  /// Asset it is due on, and the Job plan it runs — the four ways a planner
  /// names the schedule they mean. "A change of plan starts at the Asset",
  /// so the Asset's name and code are the fields this filter most has to
  /// carry (issue #191, user story 6).
  static bool _matches(PmSchedule schedule, String term) =>
      schedule.name.toLowerCase().contains(term) ||
      schedule.code.toLowerCase().contains(term) ||
      schedule.assetName.toLowerCase().contains(term) ||
      schedule.assetCode.toLowerCase().contains(term) ||
      schedule.jobPlanName.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<PmSchedule> get _matchingSchedules {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.schedules;
    return widget.schedules.where((schedule) => _matches(schedule, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingSchedules;
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            AppBreakpoints.effective(context, PmSchedulesScreen.narrowBreakpoint);
        final columns = _columns(context, canAct: widget.canAct);
        return Center(
          child: AppPageFrame(
            maxWidth: PmSchedulesScreen.maxWidth,
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
                            name: PmSchedulesScreen.filterFieldName,
                            label: 'Filter PM schedules',
                            helperText: 'By schedule name, Asset or Job plan.',
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.schedules.length,
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
                          key: PmSchedulesScreen.noMatchKey,
                          title: 'No PM schedules match',
                          message:
                              'This Site has PM schedules, but none matches '
                              '"${_term.trim()}". Try a different name, Asset or Job plan.',
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) =>
                              _PmScheduleCard(schedule: matches[index], canAct: widget.canAct),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            // Keyed by the schedule's id so a row that is open
                            // stays open when the list rebuilds on a filter
                            // keystroke.
                            for (final schedule in matches)
                              _PmScheduleTableRow(
                                key: ValueKey<String>('pm-schedule-disclosure-${schedule.id}'),
                                columns: columns,
                                schedule: schedule,
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

/// The widest of [labels] in the button label style at the reader's text scale.
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

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a label and its cells start at the same x. The first
/// cell carries the Job plan's name and the `Inactive` chip, as the card's header
/// does; the Asset cell is the card's own `name (code) · Org Unit` line; the
/// priority is a number, so end-aligned in tabular figures. Only a caller who can
/// act has the Actions column, because only they are offered the act.
List<AppTableColumn> _columns(BuildContext context, {required bool canAct}) => [
  const AppTableColumn('Job plan', flex: 3),
  const AppTableColumn('Asset', flex: 4),
  const AppTableColumn('Interval', flex: 3),
  // A number column is sized to its label, which is wider than its digits.
  AppTableColumn(
    'Priority',
    width: _bandLabelWidth(context, 'Priority') + Spacing.sm,
    align: AppColumnAlign.end,
  ),
  const AppTableColumn('Due', flex: 3),
  const AppTableColumn('Rules', flex: 2),
  if (canAct)
    AppTableColumn(
      'Actions',
      // The button's widest label, its own horizontal padding either side
      // (`Spacing.xl`), and the slot's gutter.
      width:
          _widestLabel(context, const ['Deactivate', 'Reactivate']) + 2 * Spacing.xl + Spacing.sm,
      align: AppColumnAlign.end,
    ),
];

class _PmScheduleTableRow extends StatelessWidget {
  const _PmScheduleTableRow({
    super.key,
    required this.columns,
    required this.schedule,
    required this.canAct,
  });

  final List<AppTableColumn> columns;
  final PmSchedule schedule;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final state = context.watch<PmSchedulesBloc>().state;
    final busy = state is PmSchedulesLoaded && state.isMutating;
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    final hasAccumulated =
        schedule.isMeterDriven && schedule.currentMeter != null && schedule.nextDueMeter != null;
    final ruleCount = hasAccumulated ? 3 : 2;
    // The framework's padded tap target is lifted on the chip and the button: the
    // button states its own 44 through `minimumSize`.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    return RowDisclosure(
      toggleKey: PmSchedulesScreen.rulesKey(schedule.id),
      label: '$ruleCount rules',
      rowBuilder: (context, toggle) => KeyedSubtree(
        key: PmSchedulesScreen.rowKey(schedule.id),
        child: AppTableRow(
          columns: columns,
          cells: [
            NameWithChip(
              name: DisclosingText(
                schedule.jobPlanName,
                style: dense?.copyWith(color: palette.textPrimary),
              ),
              chipLabel: 'Inactive',
              chip: schedule.isActive
                  ? null
                  : shrinkWrapTargets(
                      StatusChip(
                        key: PmSchedulesScreen.inactiveChipKey(schedule.id),
                        label: 'Inactive',
                        tone: StatusTone.neutral,
                      ),
                    ),
            ),
            DisclosingText(
              '${schedule.assetName} (${schedule.assetCode}) · ${schedule.orgUnitName}',
              style: muted,
            ),
            DisclosingText(_intervalLabel(schedule), style: muted),
            Text(
              '${schedule.priority}',
              maxLines: 1,
              style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
            ),
            DisclosingText(_PmScheduleCard._dueLabel(schedule), style: muted),
            toggle,
            if (canAct)
              shrinkWrapTargets(
                OutlinedButton(
                  key: PmSchedulesScreen.toggleKey(schedule.id),
                  onPressed: busy
                      ? null
                      : () => context.read<PmSchedulesBloc>().add(
                          PmScheduleActiveToggled(
                            pmScheduleId: schedule.id,
                            isActive: !schedule.isActive,
                          ),
                        ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(schedule.isActive ? 'Deactivate' : 'Reactivate'),
                ),
              ),
          ],
        ),
      ),
      // The card's rules, in its words and its order.
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.xxs,
        children: [
          Text('Rolls from ${schedule.anchorLabel}', style: muted),
          Text('Raised ${schedule.leadTimeDays} days early', style: muted),
          if (hasAccumulated)
            Text(
              'Accumulated ${_PmScheduleCard._trim(schedule.currentMeter)} of '
              '${_PmScheduleCard._trim(schedule.nextDueMeter)}',
              style: muted,
            ),
        ],
      ),
    );
  }
}

/// The interval in the card's words: a meter target or a number of days.
String _intervalLabel(PmSchedule schedule) {
  if (schedule.isMeterDriven) {
    return 'Every ${_PmScheduleCard._trim(schedule.intervalMeter)} of '
        '${schedule.meterName ?? schedule.meterCode ?? 'the meter'}';
  }
  return 'Every ${schedule.intervalDays} days';
}

class _PmScheduleCard extends StatelessWidget {
  const _PmScheduleCard({required this.schedule, required this.canAct});

  final PmSchedule schedule;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final state = context.watch<PmSchedulesBloc>().state;
    final busy = state is PmSchedulesLoaded && state.isMutating;

    return Card(
      key: PmSchedulesScreen.rowKey(schedule.id),
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
                        schedule.jobPlanName,
                        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${schedule.assetName} (${schedule.assetCode}) · ${schedule.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                if (!schedule.isActive)
                  StatusChip(
                    key: PmSchedulesScreen.inactiveChipKey(schedule.id),
                    label: 'Inactive',
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (schedule.isMeterDriven)
                  Text(
                    'Every ${_trim(schedule.intervalMeter)} of ${schedule.meterName ?? schedule.meterCode ?? 'the meter'}',
                    style: muted,
                  )
                else
                  Text('Every ${schedule.intervalDays} days', style: muted),
                Text('Rolls from ${schedule.anchorLabel}', style: muted),
                Text('Raised ${schedule.leadTimeDays} days early', style: muted),
                Text('Priority ${schedule.priority}', style: muted),
                if (schedule.isMeterDriven &&
                    schedule.currentMeter != null &&
                    schedule.nextDueMeter != null)
                  Text(
                    'Accumulated ${_trim(schedule.currentMeter)} of ${_trim(schedule.nextDueMeter)}',
                    style: muted,
                  ),
                Text(_dueLabel(schedule), style: muted),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: PmSchedulesScreen.toggleKey(schedule.id),
                onPressed: busy
                    ? null
                    : () => context.read<PmSchedulesBloc>().add(
                        PmScheduleActiveToggled(
                          pmScheduleId: schedule.id,
                          isActive: !schedule.isActive,
                        ),
                      ),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(schedule.isActive ? 'Deactivate' : 'Reactivate'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The next due point in words, using the server's own computed state
  /// rather than doing arithmetic on the client. A meter-driven schedule has
  /// no date; it is due once accumulated use reaches its target (ADR-0029).
  static String _dueLabel(PmSchedule schedule) {
    if (schedule.isMeterDriven) {
      if (schedule.meterDue) return 'Due now';
      if (schedule.nextDueMeter == null) return 'No meter target yet';
      return 'Due at ${_trim(schedule.nextDueMeter)}';
    }
    final nextDueOn = schedule.nextDueOn;
    if (nextDueOn == null) return 'No due date yet';
    final days = schedule.daysUntilDue;
    if (days == null) return 'Next due $nextDueOn';
    if (days < 0) return 'Overdue since $nextDueOn';
    if (days == 0) return 'Due today';
    return 'Due $nextDueOn (in $days days)';
  }

  /// A number without a trailing `.0`, the same way the meter list shows its
  /// readings.
  static String _trim(num? value) {
    if (value == null) return '—';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _PmSchedulesEmpty extends StatelessWidget {
  const _PmSchedulesEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: PmSchedulesScreen.emptyKey,
      title: 'Nothing is scheduled',
      message: 'No PM schedule is attached to this Site\'s Assets yet.',
    );
  }
}
