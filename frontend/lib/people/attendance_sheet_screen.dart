/// The shift's attendance sheet (issue #249, CONTEXT.md's Attendance
/// section, ADR-0040): the pre-filled rows, marked exceptions inline, a
/// stand-in added from the Directory, and Confirm. Reached at its own
/// address, `/people/attendance/:shiftInstanceId` — see `router.dart` and
/// `destinations.dart`'s `Attendance` Destination, which lands on
/// `AttendancePickerScreen` first, since there is no shift calendar Screen
/// yet to open a sheet from directly (#250 is the worklist that will do
/// that job properly).
///
/// [canRecord] gates every write affordance on this Screen — marking a row,
/// adding a stand-in, removing one, and Confirm — the same shape
/// `EmployeeDetailScreen.canAssign` already uses for a Grant-gated write:
/// read once at the router from `OrgUnitScope`, not re-derived here. Reading
/// the sheet needs only visibility of the Site (issue #249's own criterion),
/// so the Screen itself never refuses to *show* what `GET .../attendance-sheet`
/// already answered — the server is the only real gate on a write, and a
/// refused one surfaces as [AttendanceSheetLoaded.mutationFailure], the same
/// as every other Screen in this Module.
///
/// **The sheet is a matrix: people down, the sheet's own columns across
/// (issue #393, `docs/design-language.md` sections 5, 6 and 13).** One sheet
/// belongs to one shift instance (`AttendanceSheet` above), so the axis across
/// is the record's own fields rather than days: the Employee's name, whether
/// they were there, and the two quantities the sheet keeps, in minutes. The
/// row is `AppTableRow`'s own arithmetic without being that widget — a row of
/// this matrix is two stacks (the frozen name column and the columns that
/// scroll) that must read as one row, which a single `Row` widget cannot
/// express: 44 high (the row holds controls, so it is given the tap floor),
/// `Spacing.xs` above and below its content, `Spacing.md` at each end, and one
/// `edge` hairline under it across both halves.
///
/// **The name column is frozen, and the answer at 700px is a horizontal
/// scroll.** `_SheetMatrix` measures the box it is handed (never the window,
/// section 10) and compares it with the width its columns need at the reader's
/// text size: wider, and the columns take the slack; narrower, and they scroll
/// sideways *inside* the frozen name column, which never moves. At a 700px
/// window the Shell leaves the page 440 (section 2), so that is the box where
/// this Screen is narrowest — the widget test scrolls it and finds the name
/// where it was (`people_attendance_geometry_test.dart`).
///
/// **A cell's state is a tone and its word.** Present, Late, the two absences,
/// Training and Not scheduled are painted through `StatusChip`, whose label is
/// always rendered, so the colour is never the only carrier (WCAG 1.4.1); the
/// legend above the matrix names each tone the sheet actually paints, built
/// from the records rather than from a fixed set (section 13).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'attendance.dart';
import 'attendance_record_dialog.dart';
import 'attendance_sheet_bloc.dart';
import 'employee.dart';

class AttendanceSheetScreen extends StatelessWidget {
  const AttendanceSheetScreen({super.key, required this.shiftInstanceId, required this.canRecord});

  final String shiftInstanceId;

  /// Whether this caller holds an edit Grant reaching the shift instance's
  /// Org Unit, or is an administrator — read at the router the same way
  /// `EmployeeDetailScreen.canAssign` is. The server is the real gate either
  /// way (403 `OUTSIDE_GRANTED_ORG_UNITS`).
  final bool canRecord;

  /// The page's width. 1040 rather than the default 900 because this page is a
  /// matrix read across: the Work order detail names the same number for the
  /// same reason (section 10). Measured at a text scale of 1, the matrix needs
  /// 560.9px — a 108.4px name column plus 452.5px of columns — so it already
  /// fits inside a 900px window's 608px card and does not scroll there. The
  /// wider page is for the 1280px window, where it gives the matrix 988 and
  /// hands the slack to the name column rather than leaving a gutter beside a
  /// register whose names are the widest thing in it.
  static const double maxWidth = 1040;

  static const ValueKey<String> failedKey = ValueKey<String>('attendance-sheet-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('attendance-sheet-retry');
  static const ValueKey<String> notStartedKey = ValueKey<String>('attendance-sheet-not-started');
  static const ValueKey<String> confirmedChipKey = ValueKey<String>('attendance-sheet-confirmed');
  static const ValueKey<String> confirmKey = ValueKey<String>('attendance-sheet-confirm');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-sheet-empty');
  static const ValueKey<String> legendKey = ValueKey<String>('attendance-sheet-legend');
  static const ValueKey<String> matrixKey = ValueKey<String>('attendance-sheet-matrix');

  /// The horizontal scroll view the columns after the name live in, so a test
  /// can drag it and prove the name column does not move with it.
  static const ValueKey<String> scrollKey = ValueKey<String>('attendance-sheet-columns');
  static const String standInFieldName = 'attendance-sheet-stand-in';
  static ValueKey<String> standInFieldKey() => AppSearchField.fieldKey(standInFieldName);
  static ValueKey<String> rowKey(String id) => ValueKey<String>('attendance-sheet-row-$id');
  static ValueKey<String> markKey(String id) => ValueKey<String>('attendance-sheet-mark-$id');
  static ValueKey<String> removeKey(String id) => ValueKey<String>('attendance-sheet-remove-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttendanceSheetBloc>().state;
    return Scaffold(
      body: switch (state) {
        AttendanceSheetLoading() => const SkeletonList(maxWidth: AttendanceSheetScreen.maxWidth),
        AttendanceSheetUnavailable(message: final message) => PlatformFailureState(
            key: AttendanceSheetScreen.failedKey,
            title: 'The attendance sheet could not be read',
            message: message,
            retryKey: AttendanceSheetScreen.retryKey,
            onRetry: () => context
                .read<AttendanceSheetBloc>()
                .add(AttendanceSheetRequested(shiftInstanceId)),
          ),
        // Not started (issue #249's Grant fix): this caller could not have
        // started the sheet either, so no write affordance is offered
        // regardless of [canRecord]'s own coarse signal — see
        // `AttendanceSheetLoaded.started`'s own doc comment.
        AttendanceSheetLoaded(started: false) => const _NotStarted(),
        AttendanceSheetLoaded() => _Sheet(state: state, canRecord: canRecord),
      },
    );
  }
}

class _NotStarted extends StatelessWidget {
  const _NotStarted();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: AttendanceSheetScreen.maxWidth,
        child: Padding(
          key: AttendanceSheetScreen.notStartedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          child: const AppPageHeader(
            title: 'Attendance sheet',
            description:
                'Nobody with an edit Grant here has opened this sheet yet, so there '
                'is nothing to show. Only a supervisor holding an edit Grant reaching '
                'this shift — or an administrator — can start it.',
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.state, required this.canRecord});

  final AttendanceSheetLoaded state;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    // Non-null: this widget is only reached when `state.started` is true
    // (`AttendanceSheetScreen.build`'s own switch), and the server never
    // answers `started: true` with a null `sheet`.
    final sheet = state.sheet!;
    return Center(
      child: AppPageFrame(
        maxWidth: AttendanceSheetScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: 'Attendance sheet',
              actions: [
                if (sheet.isConfirmed)
                  Chip(
                    key: AttendanceSheetScreen.confirmedChipKey,
                    label: const Text('Confirmed'),
                    avatar: const Icon(Icons.check_circle_outline, size: 18),
                  )
                else if (canRecord)
                  FilledButton(
                    key: AttendanceSheetScreen.confirmKey,
                    onPressed: state.isMutating
                        ? null
                        : () => context.read<AttendanceSheetBloc>().add(const AttendanceSheetConfirmed()),
                    child: Text(state.isMutating ? 'Confirming…' : 'Confirm'),
                  ),
              ],
            ),
            if (state.mutationFailure != null) ...[
              const SizedBox(height: Spacing.md),
              AppBanner(tone: StatusTone.danger, message: state.mutationFailure!),
            ],
            const SizedBox(height: Spacing.lg),
            if (state.records.isEmpty)
              PlatformEmptyState.noneExist(
                key: AttendanceSheetScreen.emptyKey,
                title: 'Nobody is on this sheet yet.',
                message: canRecord
                    ? 'Add a stand-in from the Directory below to open the sheet with '
                        'somebody on it.'
                    : 'A supervisor holding an edit Grant reaching this shift adds the '
                        'people who were on it.',
                icon: Icons.groups_outlined,
              )
            else ...[
              _Legend(records: state.records),
              const SizedBox(height: Spacing.md),
              _SheetMatrix(
                key: AttendanceSheetScreen.matrixKey,
                records: state.records,
                state: state,
                canRecord: canRecord,
              ),
            ],
            if (canRecord) ...[
              const SizedBox(height: Spacing.md),
              _StandIn(
                enabled: !state.isMutating,
                onSelected: (employee) => context
                    .read<AttendanceSheetBloc>()
                    .add(AttendanceStandInAdded(employeeId: employee.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tones the sheet paints, named (section 13).
///
/// Built from the records on screen rather than from a fixed four: a sheet on
/// which everybody was present shows one chip, and telling a reader what the
/// amber means when the amber is nowhere on the page is the speculative
/// generality `theme.dart` already refuses for palette tokens. The words are
/// the domain's, not the tone enum's — [StatusTone.success] is painted for a
/// person who was there, [StatusTone.info] for a planned absence (leave) or a
/// training day, [StatusTone.danger] for an unplanned one, and
/// [StatusTone.neutral] for somebody who was not scheduled.
class _Legend extends StatelessWidget {
  const _Legend({required this.records});

  final List<AttendanceRecord> records;

  /// One entry per tone the sheet can paint, in the order a reader meets them.
  static const List<(StatusTone, String)> _words = [
    (StatusTone.success, 'Present'),
    (StatusTone.info, 'Leave'),
    (StatusTone.danger, 'Absent'),
    (StatusTone.neutral, 'Not recorded'),
  ];

  @override
  Widget build(BuildContext context) {
    final painted = {for (final record in records) attendanceRecordTone(record)};
    return Wrap(
      key: AttendanceSheetScreen.legendKey,
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        for (final (tone, word) in _words)
          if (painted.contains(tone)) StatusChip(label: word, tone: tone),
      ],
    );
  }
}

/// The matrix itself: a frozen name column, and the sheet's own columns
/// scrolling sideways beside it.
///
/// See the library comment for why the row is not `AppTableRow` and why the
/// name column is a stack of its own rather than the table's first cell. The
/// band is the shared `AppTableHeader` on both halves, so a label and its cells
/// start at the same x by construction; the frozen half's own band cell is the
/// same container with the same fill, weight and hairline, because a label
/// cannot be split across two `AppTableHeader`s.
class _SheetMatrix extends StatelessWidget {
  const _SheetMatrix({
    super.key,
    required this.records,
    required this.state,
    required this.canRecord,
  });

  final List<AttendanceRecord> records;
  final AttendanceSheetLoaded state;
  final bool canRecord;

  /// The frozen column's own band label.
  static const String _nameLabel = 'Employee';

  /// A row is this tall at a text scale of 1, and this tall times the reader's
  /// text scale at any other: the row holds controls, so it is given the tap
  /// floor, and both halves of the row are given the same height so the frozen
  /// cell and its columns read as one row at any text size.
  static double rowHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return AppTouchTarget.min * (scale < 1 ? 1 : scale);
  }

  @override
  Widget build(BuildContext context) {
    final height = rowHeight(context);
    final columns = _columns(context, records: records, canRecord: canRecord);
    final frozenWidth = _frozenWidth(context, records);
    // The columns' own widths plus the `Spacing.md` gutter at each end that
    // both `AppTableHeader` and this matrix's own rows apply — without it the
    // band overflows its own scroll view by exactly two gutters.
    final columnsWidth =
        columns.fold<double>(0, (sum, column) => sum + column.width!) + 2 * Spacing.md;
    return Card(
      margin: EdgeInsets.zero,
      // The columns scroll under the card's own rounded right edge; without
      // this a column would paint over the corner.
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          // The box this matrix is handed, not the window (section 10). Any
          // width the columns do not need goes to the name column, so a wide
          // page has no empty gutter beside a short one.
          final spare = box.maxWidth - frozenWidth - columnsWidth;
          final frozen = spare > 0 ? frozenWidth + spare : frozenWidth;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: frozen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FrozenBand(width: frozen),
                    for (final record in records) _FrozenCell(record: record, height: height),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: AttendanceSheetScreen.scrollKey,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: columnsWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTableHeader(columns: columns),
                        for (final record in records)
                          _RecordCells(
                            record: record,
                            columns: columns,
                            state: state,
                            canRecord: canRecord,
                            height: height,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The frozen half's band cell: `AppTableHeader`'s own container, because the
/// band is one visual rule across two stacks.
class _FrozenBand extends StatelessWidget {
  const _FrozenBand({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppTableHeader.height),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: palette.tableHeaderFill,
        border: Border(bottom: BorderSide(color: palette.edge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                _SheetMatrix._nameLabel,
                key: AppTableHeader.labelKey(_SheetMatrix._nameLabel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One record's name — the frozen column's cell, outside the horizontal
/// scroll view so it cannot move with the columns.
class _FrozenCell extends StatelessWidget {
  const _FrozenCell({required this.record, required this.height});

  final AttendanceRecord record;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      key: AttendanceSheetScreen.rowKey(record.id),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      foregroundDecoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.edge))),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DisclosingText(
          record.displayName,
          style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
        ),
      ),
    );
  }
}

/// The columns after the name, for one record.
class _RecordCells extends StatelessWidget {
  const _RecordCells({
    required this.record,
    required this.columns,
    required this.state,
    required this.canRecord,
    required this.height,
  });

  final AttendanceRecord record;
  final List<AppTableColumn> columns;
  final AttendanceSheetLoaded state;
  final bool canRecord;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final reason = record.absenceReason;
    final cells = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: attendanceStatusLabel(record.attendanceStatus),
            tone: attendanceRecordTone(record),
          ),
          if (reason != null && reason.name.isNotEmpty) ...[
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                reason.name,
                style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      if (attendanceStatusNeedsReason(record.attendanceStatus))
        _AbsentFigure()
      else
        Text(formatAttendanceMinutes(record.workedMinutes), style: AppTableRow.numberStyle(context)),
      if (attendanceStatusNeedsReason(record.attendanceStatus))
        _AbsentFigure()
      else
        Text(formatAttendanceMinutes(record.overtimeMinutes), style: AppTableRow.numberStyle(context)),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canRecord) ...[
            _RowIcon(
              key: AttendanceSheetScreen.markKey(record.id),
              tooltip: 'Mark an exception',
              icon: Icons.edit_outlined,
              onPressed: state.isMutating
                  ? null
                  : () => AttendanceRecordDialog.open(context, record, state.absenceReasons),
            ),
            _RowIcon(
              key: AttendanceSheetScreen.removeKey(record.id),
              tooltip: 'Remove from the sheet',
              icon: Icons.remove_circle_outline,
              onPressed: state.isMutating
                  ? null
                  : () => context
                      .read<AttendanceSheetBloc>()
                      .add(AttendanceRecordRemoved(recordId: record.id)),
            ),
          ],
        ],
      ),
    ];
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      foregroundDecoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.edge))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: columns[i].width,
              child: Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: Align(
                  alignment: columns[i].align == AppColumnAlign.end
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: cells[i],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A quantity this record does not have: an absent Employee's minutes are not
/// zero, they were never recorded, and `—` is section 13's mark for that
/// (never `0`, never a blank cell).
class _AbsentFigure extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('—', style: AppTableRow.numberStyle(context));
  }
}

/// An icon control at the tap floor, so the row can hold two of them and still
/// be the row's own 44.
class _RowIcon extends StatelessWidget {
  const _RowIcon({super.key, required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppTouchTarget.min,
      height: AppTouchTarget.min,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

/// The Directory search that adds a stand-in, in a card of its own so it reads
/// as the one act below the sheet rather than as a ninth row of it.
class _StandIn extends StatelessWidget {
  const _StandIn({required this.enabled, required this.onSelected});

  final bool enabled;
  final void Function(Employee employee) onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a stand-in',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),
            AppSearchField<Employee>(
              name: AttendanceSheetScreen.standInFieldName,
              label: 'Search the Directory',
              value: null,
              enabled: enabled,
              onChanged: (_) {},
              onSelected: onSelected,
              fetchSuggestions: (term) async {
                final token = context.read<AuthGateway>().currentAccessToken;
                if (token == null) return const [];
                return context.read<PeopleApi>().fetchEmployees(token, search: term);
              },
              suggestionBuilder: (context, employee) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                child: Text(employee.displayName),
              ),
              idOf: (employee) => employee.id,
              displayStringFor: (employee) => employee.displayName,
              codeOf: (employee) => employee.employeeNo,
            ),
          ],
        ),
      ),
    );
  }
}

/// The width [text] takes on one line, in [style], at the reader's text scale —
/// how every fixed column here is measured rather than guessed.
double _widthOf(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// A band label's own width (`AppTableHeader`'s style: `labelMedium`, w600,
/// letter spacing 0.2) at the reader's text scale.
double _bandWidth(BuildContext context, String label) => _widthOf(
      context,
      label,
      Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    );

/// The frozen name column: the widest name on the sheet, or the band's own
/// label, whichever is wider, plus the cell's two `Spacing.md` gutters. Capped
/// so one long name cannot take the page — past that, `DisclosingText` says
/// what it clipped.
double _frozenWidth(BuildContext context, List<AttendanceRecord> records) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final widest = records.fold<double>(
    0,
    (width, record) => math.max(width, _widthOf(context, record.displayName, AppTypography.dense(context))),
  );
  final label = _bandWidth(context, _SheetMatrix._nameLabel);
  final content = math.max(widest, label);
  return math.min(content, 320 * (scale < 1 ? 1 : scale)) + 2 * Spacing.md;
}

/// The columns after the name: the state, the two quantities, and the row's own
/// controls. Every one states a `width`, never a `flex`: a flex column inside a
/// horizontal scroll view has no bounded box to divide.
List<AppTableColumn> _columns(
  BuildContext context, {
  required List<AttendanceRecord> records,
  required bool canRecord,
}) {
  double sized(double content, String label) {
    final band = _bandWidth(context, label);
    return (content > band ? content : band) + Spacing.sm;
  }

  final labelLarge = Theme.of(context).textTheme.labelLarge;
  final numeric = AppTableRow.numberStyle(context);
  final floor = AppTypography.floor(context);
  return [
    AppTableColumn(
      'Status',
      // The widest chip on the sheet — a chip's own horizontal padding is
      // `Spacing.xxl`, the measure the maintenance registers use — plus the
      // reason beside it when the record names one.
      width: sized(
        records.fold<double>(0, (width, record) {
          final chip = _widthOf(context, attendanceStatusLabel(record.attendanceStatus), labelLarge) +
              Spacing.xxl;
          final reason = record.absenceReason?.name;
          final withReason = reason == null || reason.isEmpty
              ? chip
              : chip + Spacing.sm + _widthOf(context, reason, floor);
          return width > withReason ? width : withReason;
        }),
        'Status',
      ),
    ),
    AppTableColumn(
      'Worked (min)',
      width: sized(
        records.fold<double>(0, (width, record) {
          final minutes = _widthOf(context, formatAttendanceMinutes(record.workedMinutes), numeric);
          return width > minutes ? width : minutes;
        }),
        'Worked (min)',
      ),
      align: AppColumnAlign.end,
    ),
    AppTableColumn(
      'Overtime (min)',
      width: sized(
        records.fold<double>(0, (width, record) {
          final minutes = _widthOf(context, formatAttendanceMinutes(record.overtimeMinutes), numeric);
          return width > minutes ? width : minutes;
        }),
        'Overtime (min)',
      ),
      align: AppColumnAlign.end,
    ),
    if (canRecord)
      AppTableColumn(
        'Actions',
        // Two icon controls at the tap floor, `Spacing.sm` apart.
        width: 2 * AppTouchTarget.min + Spacing.sm + Spacing.sm,
        align: AppColumnAlign.end,
      ),
  ];
}
