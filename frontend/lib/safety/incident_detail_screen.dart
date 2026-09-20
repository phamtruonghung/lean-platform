/// One Safety incident (issue #226): what happened, where, when, and where it
/// sits on the severity ladder.
///
/// The record's own number is the title rather than a page heading — the
/// same choice the Non-conformance, Work order and Action detail Screens
/// make, and why this Screen is excluded from `page_alignment_test.dart`'s
/// audit by name rather than audited in it.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so
/// this Screen gates nothing about *reading*. Nothing here is classified: no
/// injury type and no body part — issue #224's own writes.
///
/// **Issue #228 — making the record answerable.** The event history (every
/// severity change, status move, days change and closure, oldest first) is
/// shown on every read. Five acts are offered, each its own address
/// (ADR-0021): the investigation due date and the ordinary status move need
/// only an edit Grant reaching the Org Unit, so they are always offered and
/// the server is the gate, exactly like recording itself. Correcting the
/// severity, recording the days and closing each need Safety authority
/// (ADR-0039) and are offered **only** to a caller who holds it at the
/// incident's Org Unit — nobody is shown a control whose only answer would be
/// a 403.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentDetailScreen extends StatelessWidget {
  const SafetyIncidentDetailScreen({super.key, required this.incidentId});

  final String incidentId;

  static const double maxWidth = 900;

  static const ValueKey<String> backKey = ValueKey<String>('safety-incident-back');
  static const ValueKey<String> statusKey = ValueKey<String>('safety-incident-detail-status');
  static const ValueKey<String> severityKey = ValueKey<String>('safety-incident-detail-severity');
  static const ValueKey<String> recordableKey =
      ValueKey<String>('safety-incident-detail-recordable');
  static const ValueKey<String> filedKey = ValueKey<String>('safety-incident-detail-filed');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-detail-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-incident-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-incident-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('safety-incident-detail-missing');

  // Issue #228's own five acts, each its own address.
  static const ValueKey<String> dueDateKey = ValueKey<String>('safety-incident-detail-due-date');
  static const ValueKey<String> moveStatusKey =
      ValueKey<String>('safety-incident-detail-move-status');
  static const ValueKey<String> changeSeverityKey =
      ValueKey<String>('safety-incident-detail-change-severity');
  static const ValueKey<String> recordDaysKey =
      ValueKey<String>('safety-incident-detail-record-days');
  static const ValueKey<String> closeKey = ValueKey<String>('safety-incident-detail-close');
  static const ValueKey<String> closedKey = ValueKey<String>('safety-incident-detail-closed');
  static const ValueKey<String> dueDateFactKey =
      ValueKey<String>('safety-incident-detail-due-date-fact');

  // The event history (issue #228).
  static const ValueKey<String> eventsKey = ValueKey<String>('safety-incident-detail-events');
  static const ValueKey<String> noEventsKey =
      ValueKey<String>('safety-incident-detail-no-events');

  static ValueKey<String> eventRowKey(String id) => ValueKey<String>('safety-incident-event-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyIncidentDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        SafetyIncidentDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
        SafetyIncidentDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Safety incident',
            message: 'Nothing is recorded at this address. It may have been removed, or '
                'the address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Safety incidents',
            actionKey: backKey,
            onAction: () => context.go(Routes.safetyIncidents),
          ),
        SafetyIncidentDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'The Safety incident could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<SafetyIncidentDetailBloc>()
                .add(const SafetyIncidentDetailRefreshed()),
          ),
        SafetyIncidentDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SafetyIncidentDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = state.incident;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: SafetyIncidentDetailScreen.backKey,
                onPressed: () => context.go(Routes.safetyIncidents),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Safety incidents'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(row.incidentNo, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: SafetyIncidentDetailScreen.statusKey,
                  label: row.statusLabel,
                  tone: row.statusTone,
                ),
                StatusChip(
                  key: SafetyIncidentDetailScreen.severityKey,
                  label: row.severityLabel,
                  tone: row.severityTone,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              row.isRecordable ? 'Recordable' : 'Not recordable',
              key: SafetyIncidentDetailScreen.recordableKey,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What happened', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    _Fact(label: 'Incident type', value: row.incidentTypeLabel),
                    _Fact(label: 'Org Unit', value: row.orgUnitName),
                    _Fact(
                      label: 'Asset',
                      value:
                          row.assetName == null ? 'None named' : '${row.assetName} · ${row.assetCode}',
                    ),
                    _Fact(
                      label: 'Employee involved',
                      value: row.employeeName ?? 'None named',
                    ),
                    _Fact(
                      label: 'Filed against',
                      key: SafetyIncidentDetailScreen.filedKey,
                      value: row.filedAgainst,
                    ),
                    _Fact(label: 'Occurred at', value: row.occurredAt ?? 'Not recorded'),
                    _Fact(label: 'Reported at', value: row.reportedAt ?? 'Not recorded'),
                    _Fact(label: 'Reported by', value: row.reportedByLabel),
                    _Fact(label: 'Description', value: row.description ?? 'None given'),
                    _Fact(
                      label: 'Immediate action',
                      value: row.immediateAction ?? 'None recorded yet',
                    ),
                    if (row.lostTimeDays > 0)
                      _Fact(label: 'Lost-time days', value: row.lostTimeDays.toString()),
                    if (row.restrictedDays > 0)
                      _Fact(label: 'Restricted days', value: row.restrictedDays.toString()),
                    _Fact(
                      key: SafetyIncidentDetailScreen.dueDateFactKey,
                      label: 'Investigation due at',
                      value: row.investigationDueAt ?? 'No deadline set',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            _EventHistoryCard(events: row.events),
            const SizedBox(height: Spacing.lg),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The investigation due date and the ordinary status move
                // need only an edit Grant, exactly as recording itself does —
                // the server is the gate, so both are always offered.
                if (!row.isClosed)
                  OutlinedButton.icon(
                    key: SafetyIncidentDetailScreen.dueDateKey,
                    onPressed: state.isMutating
                        ? null
                        : () => context.go('${Routes.safetyIncidents}/${row.id}/due-date'),
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Investigation due date'),
                  ),
                if (row.nextStatus != null)
                  OutlinedButton.icon(
                    key: SafetyIncidentDetailScreen.moveStatusKey,
                    onPressed: state.isMutating
                        ? null
                        : () => context.go('${Routes.safetyIncidents}/${row.id}/status'),
                    icon: const Icon(Icons.trending_flat),
                    label: Text('Move to ${SafetyIncidentStatus.label(row.nextStatus!)}'),
                  ),
                // The three decisions Safety authority gates (ADR-0039):
                // correcting the severity, recording the days, and closing.
                // None of them is offered to anyone else, so no request is
                // ever sent that the server would refuse for a reason the
                // caller could not see.
                if (holdsSafetyAuthority(context, row.orgUnitId)) ...[
                  FilledButton.icon(
                    key: SafetyIncidentDetailScreen.changeSeverityKey,
                    onPressed: state.isMutating
                        ? null
                        : () => context.go('${Routes.safetyIncidents}/${row.id}/severity'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Correct the severity'),
                  ),
                  if (!row.isClosed)
                    OutlinedButton.icon(
                      key: SafetyIncidentDetailScreen.recordDaysKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.safetyIncidents}/${row.id}/days'),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Record the days'),
                    ),
                  if (!row.isClosed)
                    FilledButton.icon(
                      key: SafetyIncidentDetailScreen.closeKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.safetyIncidents}/${row.id}/close'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Close it'),
                    ),
                ],
                if (row.closedAt != null)
                  StatusChip(
                    key: SafetyIncidentDetailScreen.closedKey,
                    label: 'Closed ${row.closedAt}',
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
            if (state.mutationFailure != null)
              Padding(
                key: SafetyIncidentDetailScreen.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  state.mutationFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The event history (issue #228): every severity change, status move, days
/// change and closure, oldest first, with who made it and when — mirrors
/// Quality's own `_CorrectionsCard` shape.
class _EventHistoryCard extends StatelessWidget {
  const _EventHistoryCard({required this.events});

  final List<SafetyIncidentEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event history', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Every severity change, status move, days change and closure, kept with who and '
              'when.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            if (events.isEmpty)
              Text(
                'Nothing has changed about this record since it was recorded.',
                key: SafetyIncidentDetailScreen.noEventsKey,
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                key: SafetyIncidentDetailScreen.eventsKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in events)
                    Padding(
                      key: SafetyIncidentDetailScreen.eventRowKey(event.id),
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.summary, style: theme.textTheme.bodyMedium),
                          Text(
                            '${event.changedBy}'
                            '${event.changedAt == null ? '' : ' · ${event.changedAt}'}'
                            '${event.note == null ? '' : ' · ${event.note}'}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
