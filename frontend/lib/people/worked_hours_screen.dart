/// The per-Employee worked-hours summary (issue #263): one Employee's
/// confirmed worked hours across an optional date window, day by day plus
/// the window's totals. The HRM question the attendance sheet answers only
/// per shift ("who worked THIS shift") turned around — "how much did THIS
/// person work, across this window" — read from
/// `GET /api/people/employees/:employeeId/work-hours`.
///
/// **Address, deliberately nested under the Employee's directory detail
/// (`/directory/:id/work-hours`) rather than a new sidebar Destination.** The
/// summary is about one named Employee, so it belongs under that Employee's
/// own record — reached from a button on `EmployeeDetailScreen` — exactly as
/// `/attendance/to-confirm` nests under the Attendance Destination (see that
/// Screen's own header). It adds no new Destination and therefore reopens
/// none of the Shell's goldens (`frontend/test/GOLDENS.md`), the same reason
/// `attendance_to_confirm_screen.dart` gives for nesting.
///
/// Offered to every approved Account, the same openness `Routes.directory`'s
/// detail route itself has: the server decides access (here, none is
/// refused — ADR-0009 says an Employee's work record is not a secret, and
/// `attendance-routes.js`'s own header on the work-hours route argues the
/// scope explicitly), so a role check here would gate a door the route never
/// closes. Only the day rows and totals change as the window does; there is
/// no write and no action to gate.
///
/// **A day is shown with minutes, never re-derived into a screen-level
/// total**: the window's [WorkedHoursTotals] arrives from the same read as
/// [WorkedHoursDay]s, so the bottom line and the rows cannot disagree the way
/// two client-side sum could.
///
/// **A table that sums visibly** (issue #393, `docs/design-language.md`
/// sections 6 and 13). The days are one `AppTableHeader` band and one
/// `AppTableRow` each — Day, Worked, Overtime, the quantities end-aligned in
/// tabular figures so a column of durations compares down its right edge — and
/// the window's own totals are the *same table's* footer row rather than a
/// second card below it: the foot wears the band's own `surfaceMuted` fill and
/// a w600 weight, so the total reads as the sum of the rows above it instead of
/// as another card to evaluate. `—` is what a day with no overtime shows
/// (section 13: an absent value is never a blank cell). The window's two bounds
/// moved into `AppPageHeader.below`, so the title, the window and the table's
/// own left edge are one line. The foot's figures carry no word of their own —
/// `16h 30m`, not `16h 30m worked` — because the band above already names the
/// column, and a word wider than every day cell was what wrapped the totals
/// onto a second line (issue #424, S7 residue; see `_columnWidth`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'worked_hours.dart';
import 'worked_hours_bloc.dart';

/// The height a `SkeletonList` is given when it stands in for a list inside a
/// page that is itself scrolling: the placeholder scrolls its own rows, so it
/// needs a bounded box where the page hands out an unbounded one.
const double _skeletonHeight = 288;

class WorkedHoursScreen extends StatelessWidget {
  const WorkedHoursScreen({super.key, required this.employeeId});

  static const double maxWidth = 720;

  final String employeeId;

  static const ValueKey<String> failureKey = ValueKey<String>('work-hours-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('work-hours-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('work-hours-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('work-hours-loading');
  static const ValueKey<String> totalsKey = ValueKey<String>('work-hours-totals');
  static const ValueKey<String> tableKey = ValueKey<String>('work-hours-table');
  static const ValueKey<String> fromFieldKey = ValueKey<String>('work-hours-from');
  static const ValueKey<String> toFieldKey = ValueKey<String>('work-hours-to');
  static const ValueKey<String> backKey = ValueKey<String>('work-hours-back');
  static ValueKey<String> rowKey(String date) => ValueKey<String>('work-hours-date-$date');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return BlocProvider<WorkedHoursBloc>(
      create: (context) => WorkedHoursBloc(
        peopleApi: peopleApi,
        authGateway: authGateway,
        employeeId: employeeId,
      )..add(const WorkedHoursStarted()),
      child: _WorkedHoursBody(employeeId: employeeId),
    );
  }
}

class _WorkedHoursBody extends StatelessWidget {
  const _WorkedHoursBody({required this.employeeId});

  final String employeeId;

  /// The cell strings, built once so the column is cut to exactly what the
  /// cells render: a width measured from one set of strings and spent drawing
  /// another is how the footer wrapped (see [_columnWidth]).
  ///
  /// **The footer shows the bare figure, not `… worked` / `… overtime`**
  /// (issue #424, S7 residue). The band above already names the column, and the
  /// suffix made the footer's string wider than every day cell it sums — wider
  /// than its own column, which the days sized — so both totals wrapped onto a
  /// second line at every window width and every text scale. The words were the
  /// only thing wider: the figure alone is measured with the days below.
  static String _dayWorked(WorkedHoursDay day) => formatWorkedMinutes(day.workedMinutes);

  static String _dayOvertime(WorkedHoursDay day) =>
      '(+${formatWorkedMinutes(day.overtimeMinutes)} OT)';

  static String _totalWorked(WorkedHoursTotals totals) =>
      formatWorkedMinutes(totals.workedMinutes);

  static String _totalOvertime(WorkedHoursTotals totals) =>
      formatWorkedMinutes(totals.overtimeMinutes);

  /// The quantity columns are as wide as their longest figure at the reader's
  /// own text size, so a duration never wraps and the column never grows a
  /// second line the row above it does not have.
  ///
  /// **The footer's figures are measured in the same pass as the days'**
  /// (issue #424, S7 residue). Sizing the column from the day cells alone is a
  /// column cut to yesterday's data: the window's total is the longest number
  /// in its own column (`16h 30m` over days of `7h 30m` and `9h 0m`), so the
  /// foot was drawn wider than the slot it inherited and wrapped. Each string is
  /// measured in the style it is actually rendered in — the footer is heavier
  /// ([_totalFigure]) and so is wider at the same text — and the column is cut
  /// to the widest thing on screen, footer included.
  static double _columnWidth(
    BuildContext context,
    List<(String, TextStyle?)> figures,
    double bandWidth,
  ) {
    var widest = bandWidth;
    for (final (text, style) in figures) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    return widest + Spacing.sm;
  }

  static double _bandWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final state = context.watch<WorkedHoursBloc>().state;
    final bloc = context.read<WorkedHoursBloc>();
    final totals = state.totals;

    // The exact strings the cells below render, in the style they render in:
    // the columns are cut to this list's widest entry (footer included).
    final figureStyle = AppTableRow.numberStyle(context);
    final totalStyle = _totalFigure(context);
    final columns = [
      AppTableColumn(l10n.workedHoursDay, flex: 3),
      AppTableColumn(
        l10n.workedHoursWorked,
        width: _columnWidth(
          context,
          [
            for (final day in state.days) (_dayWorked(day), figureStyle),
            if (totals != null) (_totalWorked(totals), totalStyle),
          ],
          _bandWidth(context, 'Worked'),
        ),
        align: AppColumnAlign.end,
      ),
      AppTableColumn(
        l10n.commonOvertime,
        width: _columnWidth(
          context,
          [
            for (final day in state.days) (_dayOvertime(day), figureStyle),
            if (totals != null && totals.overtimeMinutes > 0)
              (_totalOvertime(totals), totalStyle),
          ],
          _bandWidth(context, 'Overtime'),
        ),
        align: AppColumnAlign.end,
      ),
    ];

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: WorkedHoursScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              // A crumb, not a second title: the rule this page sits one level
              // below (`docs/design-language.md` section 6).
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: WorkedHoursScreen.backKey,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppTouchTarget.min),
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  ),
                  onPressed: () => context.go('${Routes.directory}/$employeeId'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.workedHoursBackToEmployee),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              AppPageHeader(
                title: l10n.titleWorkedHours,
                description:
                    l10n.workedHoursTheConfirmedHoursThisEmployeeActuallyWorked,
                below: _WindowFields(state: state, bloc: bloc),
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                PlatformFailureState(
                  key: WorkedHoursScreen.failureKey,
                  title: l10n.workedHoursTheWorkedHoursSummaryCouldNotBe,
                  message: state.failure!,
                  retryKey: WorkedHoursScreen.retryKey,
                  // The same window again: `WorkedHoursStarted` takes the bounds
                  // it is given, so a retry asks for exactly what is on screen.
                  onRetry: () => bloc.add(WorkedHoursStarted(from: state.from, to: state.to)),
                )
              else if (state.isLoading)
                // Bounded, because `SkeletonList` scrolls its own rows and this
                // page's ListView hands out no height of its own.
                SizedBox(
                  height: _skeletonHeight,
                  child: const SkeletonList(
                    key: WorkedHoursScreen.loadingKey,
                    rows: 5,
                    maxWidth: WorkedHoursScreen.maxWidth,
                  ),
                )
              else if (state.days.isEmpty)
                PlatformEmptyState.noneExist(
                  key: WorkedHoursScreen.emptyKey,
                  title: l10n.workedHoursNoConfirmedWorkedHoursInThisWindow,
                  message: l10n.workedHoursWidenTheWindowOrConfirmTheShift,
                  icon: Icons.schedule_outlined,
                )
              else
                Card(
                  key: WorkedHoursScreen.tableKey,
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTableHeader(columns: columns),
                      for (final day in state.days)
                        AppTableRow(
                          key: WorkedHoursScreen.rowKey(day.date),
                          columns: columns,
                          cells: [
                            Text(day.date, style: AppTypography.dense(context)),
                            Text(
                              _dayWorked(day),
                              key: ValueKey<String>('work-hours-worked-${day.date}'),
                              style: AppTableRow.numberStyle(context),
                            ),
                            day.overtimeMinutes > 0
                                ? Text(
                                    _dayOvertime(day),
                                    style: AppTableRow.numberStyle(context)
                                        ?.copyWith(color: palette.textMuted),
                                  )
                                : Text('—', style: AppTableRow.numberStyle(context)),
                          ],
                        ),
                      if (state.totals != null)
                        Container(
                          key: WorkedHoursScreen.totalsKey,
                          color: palette.tableHeaderFill,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTableRow(
                                columns: columns,
                                cells: [
                                  Text(
                                    l10n.workedHoursTotals,
                                    style: AppTypography.dense(context)?.copyWith(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _totalWorked(state.totals!),
                                    style: _totalFigure(context),
                                  ),
                                  state.totals!.overtimeMinutes > 0
                                      ? Text(
                                          _totalOvertime(state.totals!),
                                          style: _totalFigure(context),
                                        )
                                      : Text('—', style: _totalFigure(context)),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Spacing.md,
                                  0,
                                  Spacing.md,
                                  Spacing.sm,
                                ),
                                child: Text(
                                  l10n.workedHoursOfScheduled(formatWorkedMinutes(state.totals!.scheduledMinutes)),
                                  style: AppTypography.floor(context)?.copyWith(
                                    color: palette.textMuted,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  /// The footer's own figures: the row's tabular style, heavier, so the foot
  /// reads as a sum rather than as one more day.
  TextStyle? _totalFigure(BuildContext context) =>
      AppTableRow.numberStyle(context)?.copyWith(fontWeight: FontWeight.w600);
}

/// The two bounds of the window: one row when the box holds them side by side,
/// stacked when it does not — the box, scaled by the reader's text size
/// (`AppBreakpoints.effective`), never the window.
class _WindowFields extends StatelessWidget {
  const _WindowFields({required this.state, required this.bloc});

  final WorkedHoursState state;
  final WorkedHoursBloc bloc;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final from = AppDateField(
      key: WorkedHoursScreen.fromFieldKey,
      name: 'work-hours-from',
      label: l10n.commonFrom,
      value: state.from,
      optional: true,
      onChanged: (value) => bloc.add(WorkedHoursFromChosen(value)),
    );
    final to = AppDateField(
      key: WorkedHoursScreen.toFieldKey,
      name: 'work-hours-to',
      label: l10n.commonTo,
      value: state.to,
      optional: true,
      onChanged: (value) => bloc.add(WorkedHoursToChosen(value)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < AppBreakpoints.effective(context, AppBreakpoints.toolbarWrap)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [from, const SizedBox(height: Spacing.md), to],
          );
        }
        return Row(
          children: [
            Expanded(child: from),
            const SizedBox(width: Spacing.md),
            Expanded(child: to),
          ],
        );
      },
    );
  }
}
