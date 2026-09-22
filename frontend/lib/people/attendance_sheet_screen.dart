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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_search_field.dart';
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

  static const double maxWidth = 900;

  static const ValueKey<String> failedKey = ValueKey<String>('attendance-sheet-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('attendance-sheet-retry');
  static const ValueKey<String> notStartedKey = ValueKey<String>('attendance-sheet-not-started');
  static const ValueKey<String> confirmedChipKey = ValueKey<String>('attendance-sheet-confirmed');
  static const ValueKey<String> confirmKey = ValueKey<String>('attendance-sheet-confirm');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-sheet-empty');
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
        AttendanceSheetLoading() => const Center(child: CircularProgressIndicator()),
        AttendanceSheetUnavailable(message: final message) =>
          _Failed(message: message, shiftInstanceId: shiftInstanceId),
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
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: AttendanceSheetScreen.maxWidth,
        child: Padding(
          key: AttendanceSheetScreen.notStartedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Attendance sheet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'Nobody with an edit Grant here has opened this sheet yet, so there '
                'is nothing to show. Only a supervisor holding an edit Grant reaching '
                'this shift — or an administrator — can start it.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.shiftInstanceId});

  final String message;
  final String shiftInstanceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: AttendanceSheetScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The attendance sheet could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: AttendanceSheetScreen.retryKey,
                onPressed: () =>
                    context.read<AttendanceSheetBloc>().add(AttendanceSheetRequested(shiftInstanceId)),
                child: const Text('Try again'),
              ),
            ],
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
    final theme = Theme.of(context);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Attendance sheet',
                    style: theme.textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.md),
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
            if (state.mutationFailure != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  state.mutationFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: Spacing.lg),
            if (state.records.isEmpty)
              Padding(
                key: AttendanceSheetScreen.emptyKey,
                padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Text(
                  'Nobody is on this sheet yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final record in state.records) _RecordRow(record: record, state: state, canRecord: canRecord),
            if (canRecord) ...[
              const SizedBox(height: Spacing.lg),
              Text('Add a stand-in', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              AppSearchField<Employee>(
                name: AttendanceSheetScreen.standInFieldName,
                label: 'Search the Directory',
                value: null,
                enabled: !state.isMutating,
                onChanged: (_) {},
                onSelected: (employee) => context
                    .read<AttendanceSheetBloc>()
                    .add(AttendanceStandInAdded(employeeId: employee.id)),
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.state, required this.canRecord});

  final AttendanceRecord record;
  final AttendanceSheetLoaded state;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = attendanceStatusNeedsReason(record.attendanceStatus)
        ? '${attendanceStatusLabel(record.attendanceStatus)}'
            '${record.absenceReason != null ? ' — ${record.absenceReason!.name}' : ''}'
        : '${attendanceStatusLabel(record.attendanceStatus)} · '
            '${record.workedMinutes} worked minutes'
            '${record.overtimeMinutes > 0 ? ' (${record.overtimeMinutes} overtime)' : ''}';
    return Padding(
      key: AttendanceSheetScreen.rowKey(record.id),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.displayName, style: theme.textTheme.bodyLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (canRecord) ...[
            IconButton(
              key: AttendanceSheetScreen.markKey(record.id),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Mark an exception',
              onPressed: state.isMutating
                  ? null
                  : () => AttendanceRecordDialog.open(context, record, state.absenceReasons),
            ),
            IconButton(
              key: AttendanceSheetScreen.removeKey(record.id),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove from the sheet',
              onPressed: state.isMutating
                  ? null
                  : () => context
                      .read<AttendanceSheetBloc>()
                      .add(AttendanceRecordRemoved(recordId: record.id)),
            ),
          ],
        ],
      ),
    );
  }
}
