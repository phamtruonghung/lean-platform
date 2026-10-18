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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import 'worked_hours.dart';
import 'worked_hours_bloc.dart';

class WorkedHoursScreen extends StatelessWidget {
  const WorkedHoursScreen({super.key, required this.employeeId});

  static const double maxWidth = 720;

  final String employeeId;

  static const ValueKey<String> failureKey = ValueKey<String>('work-hours-failure');
  static const ValueKey<String> emptyKey = ValueKey<String>('work-hours-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('work-hours-loading');
  static const ValueKey<String> totalsKey = ValueKey<String>('work-hours-totals');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<WorkedHoursBloc>().state;
    final bloc = context.read<WorkedHoursBloc>();

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: WorkedHoursScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              TextButton.icon(
                key: WorkedHoursScreen.backKey,
                onPressed: () => context.go('${Routes.directory}/$employeeId'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Employee'),
              ),
              const SizedBox(height: Spacing.sm),
              Text('Worked hours', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'The confirmed hours this Employee actually worked, day by day. '
                'Only confirmed attendance counts — an unconfirmed sheet is a draft.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppDateField(
                      key: WorkedHoursScreen.fromFieldKey,
                      name: 'work-hours-from',
                      label: 'From',
                      value: state.from,
                      optional: true,
                      onChanged: (value) => bloc.add(WorkedHoursFromChosen(value)),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: AppDateField(
                      key: WorkedHoursScreen.toFieldKey,
                      name: 'work-hours-to',
                      label: 'To',
                      value: state.to,
                      optional: true,
                      onChanged: (value) => bloc.add(WorkedHoursToChosen(value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                Text(
                  state.failure!,
                  key: WorkedHoursScreen.failureKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                )
              else if (state.isLoading)
                const Center(
                  key: WorkedHoursScreen.loadingKey,
                  child: CircularProgressIndicator(),
                )
              else if (state.days.isEmpty)
                Text(
                  'No confirmed worked hours in this window.',
                  key: WorkedHoursScreen.emptyKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final day in state.days) _WorkedHoursRow(day: day),
                    ],
                  ),
                ),
                if (state.totals != null) ...[
                  const SizedBox(height: Spacing.md),
                  _TotalsCard(totals: state.totals!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkedHoursRow extends StatelessWidget {
  const _WorkedHoursRow({required this.day});

  final WorkedHoursDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: WorkedHoursScreen.rowKey(day.date),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(day.date, style: theme.textTheme.bodyLarge)),
          Text(
            formatWorkedMinutes(day.workedMinutes),
            key: ValueKey<String>('work-hours-worked-${day.date}'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(width: Spacing.sm),
          if (day.overtimeMinutes > 0)
            Text(
              '(+${formatWorkedMinutes(day.overtimeMinutes)} OT)',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final WorkedHoursTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        key: WorkedHoursScreen.totalsKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Totals', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Text('${formatWorkedMinutes(totals.workedMinutes)} worked'),
            if (totals.overtimeMinutes > 0)
              Text('${formatWorkedMinutes(totals.overtimeMinutes)} overtime'),
            Text('of ${formatWorkedMinutes(totals.scheduledMinutes)} scheduled'),
          ],
        ),
      ),
    );
  }
}