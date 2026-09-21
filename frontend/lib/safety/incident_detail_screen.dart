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
/// this Screen gates nothing about *reading* the incident itself.
///
/// **Issue #224, ADR-0037 — the injury section, and what it says to whom.**
/// Three fields are different from the rest of the record: the identified
/// Employee, the Injury type and the Body part are health information about
/// one named person, and the API returns them only to a holder of Safety
/// authority reaching the Org Unit and to the injured person's own Account.
/// Everyone else receives a record with those keys **absent**, which is what
/// `SafetyIncident.injuryDetailsVisible` reads off.
///
/// The section renders in three ways (the binding design comment on #223):
///
///   - **No-injury rung** — no injury section at all, for anybody. The
///     ladder's own CHECK forbids an injury type and a body part there, so
///     there is nothing to classify and a section saying so would be noise on
///     every near miss the plant records.
///   - **Any rung above it, a reader without authority** — the section renders
///     with one line saying the details are restricted. Deliberately not
///     hidden: the severity rung is public and that CHECK makes "does this
///     incident have injury details" already derivable from it, so hiding the
///     section protects nothing and costs the reader the difference between
///     "not classified yet" and "not mine to see".
///   - **A holder of authority, or the injured person's own Account** — the
///     values, and the classify dialog beside them.
///
/// The **identified Employee moved out of the "What happened" card** and into
/// that section, where issue #226 had put it beside the Asset. It is one of
/// the three restricted fields now, so it cannot render where every reader
/// sees it.
///
/// What the restriction does NOT cover is as deliberate as what it does, and
/// this Screen says nothing implying otherwise: `description` and
/// `immediateAction` are free text a person writes whatever they like into,
/// and ADR-0037 names them as outside the restriction rather than pretending
/// to a protection that is not there. No copy here calls them private.
///
/// **Issue #228 — making the record answerable.** The event history (every
/// severity change, status move, days change, closure and classification
/// change, oldest first) is shown on every read. Five acts are offered, each
/// its own address
/// (ADR-0021): the investigation due date and the ordinary status move need
/// only an edit Grant reaching the Org Unit, so they are always offered and
/// the server is the gate, exactly like recording itself. Correcting the
/// severity, recording the days and closing each need Safety authority
/// (ADR-0039) and are offered **only** to a caller who holds it at the
/// incident's Org Unit — nobody is shown a control whose only answer would be
/// a 403. Issue #224's classify dialog is the fourth of those.
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
import 'body_part.dart';
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
  static const ValueKey<String> classifyKey =
      ValueKey<String>('safety-incident-detail-classify');
  static const ValueKey<String> closedKey = ValueKey<String>('safety-incident-detail-closed');
  static const ValueKey<String> dueDateFactKey =
      ValueKey<String>('safety-incident-detail-due-date-fact');

  // The injury section (issue #224, ADR-0037). `injuryKey` is the section
  // itself — absent entirely on the no-injury rung; `injuryRestrictedKey` is
  // the one line a reader without authority sees instead of the values;
  // `injuryUnclassifiedKey` is what a reader WITH authority sees on an
  // incident nobody has classified yet. The last two are the two facts the
  // design comment on #223 insists stay tellable apart.
  static const ValueKey<String> injuryKey = ValueKey<String>('safety-incident-detail-injury');
  static const ValueKey<String> injuryRestrictedKey =
      ValueKey<String>('safety-incident-detail-injury-restricted');
  static const ValueKey<String> injuryUnclassifiedKey =
      ValueKey<String>('safety-incident-detail-injury-unclassified');
  static const ValueKey<String> injuredEmployeeKey =
      ValueKey<String>('safety-incident-detail-injured-employee');
  static const ValueKey<String> injuryTypeKey =
      ValueKey<String>('safety-incident-detail-injury-type');
  static const ValueKey<String> bodyPartKey =
      ValueKey<String>('safety-incident-detail-body-part');

  // The event history (issue #228).
  static const ValueKey<String> eventsKey = ValueKey<String>('safety-incident-detail-events');
  static const ValueKey<String> noEventsKey =
      ValueKey<String>('safety-incident-detail-no-events');

  static ValueKey<String> eventRowKey(String id) => ValueKey<String>('safety-incident-event-$id');

  // The Concern raised from this incident (issue #229): the section, its
  // empty state, one row per Concern, the notice from the last raise, and the
  // control that raises one.
  static const ValueKey<String> concernsKey = ValueKey<String>('safety-incident-detail-concerns');
  static const ValueKey<String> noConcernsKey =
      ValueKey<String>('safety-incident-detail-no-concerns');
  static const ValueKey<String> raiseConcernKey =
      ValueKey<String>('safety-incident-detail-raise-concern');
  static const ValueKey<String> concernNoticeKey =
      ValueKey<String>('safety-incident-detail-concern-notice');

  static ValueKey<String> concernRowKey(String id) =>
      ValueKey<String>('safety-incident-concern-$id');

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
            if (row.hasInjurySection) ...[
              const SizedBox(height: Spacing.lg),
              _InjuryCard(incident: row),
            ],
            const SizedBox(height: Spacing.lg),
            _EventHistoryCard(events: row.events),
            const SizedBox(height: Spacing.lg),
            // What is being done about the cause (issue #229). Below the
            // record's own story, the same order the Non-conformance Screen
            // keeps: the event itself comes first, the problem behind it
            // second.
            _ConcernsCard(
              incident: row,
              notice: state.notice,
              busy: state.isRaisingConcern,
            ),
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
                  // Only where there is something to classify: the ladder's
                  // own CHECK forbids an injury type and a body part on the
                  // no-injury rung, so offering the dialog there would offer a
                  // form whose every answer is a 400.
                  if (row.hasInjurySection)
                    FilledButton.icon(
                      key: SafetyIncidentDetailScreen.classifyKey,
                      onPressed: state.isMutating
                          ? null
                          : () => context.go('${Routes.safetyIncidents}/${row.id}/classify'),
                      icon: const Icon(Icons.medical_information_outlined),
                      label: const Text('Classify the injury'),
                    ),
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

/// The injury classification (issue #224, ADR-0037) — rendered on every rung
/// above the no-injury one, and rendered *differently* depending on whether
/// this caller may read the three fields.
///
/// It is a **stated restriction, not an absence**. A reader without authority
/// is told in one line that the details are restricted to Safety authority for
/// this area, and told nothing about who or what. That is deliberate: the
/// severity rung is public and the schema's own CHECK forbids injury details
/// below the no-injury rung, so whether details exist is already derivable
/// from a field everybody reads — hiding the section would protect nothing and
/// would cost this reader the ability to tell "not classified yet" from "not
/// mine to see".
class _InjuryCard extends StatelessWidget {
  const _InjuryCard({required this.incident});

  final SafetyIncident incident;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: SafetyIncidentDetailScreen.injuryKey,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The injury', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (!incident.injuryDetailsVisible)
              Text(
                'Restricted — visible to Safety authority for this area.',
                key: SafetyIncidentDetailScreen.injuryRestrictedKey,
                style: theme.textTheme.bodyMedium,
              )
            else if (!incident.isClassified)
              Text(
                'Not classified yet. Who was hurt, what the injury was and where on the '
                'body have not been recorded.',
                key: SafetyIncidentDetailScreen.injuryUnclassifiedKey,
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              _Fact(
                key: SafetyIncidentDetailScreen.injuredEmployeeKey,
                label: 'Injured Employee',
                value: incident.employeeName ?? 'Not recorded',
              ),
              _Fact(
                key: SafetyIncidentDetailScreen.injuryTypeKey,
                label: 'Injury type',
                value: incident.injuryTypeName ?? 'Not recorded',
              ),
              _Fact(
                key: SafetyIncidentDetailScreen.bodyPartKey,
                label: 'Body part',
                value: incident.bodyPartName == null
                    ? 'Not recorded'
                    : '${incident.bodyPartName} · '
                        '${BodyPartRegion.label(incident.bodyPartRegion ?? BodyPartRegion.other)}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Concern raised from this incident (issue #229) — mirrors Quality's own
/// `_ConcernsCard` shape closely: the card is drawn even when there is
/// nothing, because "nobody is answering this yet" is a state a reader of an
/// incident needs to see, and the control that changes it (raising a Concern)
/// sits exactly there. Anyone who can see the Site may raise one — a Grant is
/// not asked here or by the server (#198's Concern rule, #223's own
/// acceptance criterion for this path).
class _ConcernsCard extends StatelessWidget {
  const _ConcernsCard({required this.incident, required this.busy, this.notice});

  final SafetyIncident incident;

  /// The raise is in flight: the control goes quiet so a second one cannot be
  /// started against the incident mid-change.
  final bool busy;

  /// What the last raise had to say for itself, from the Bloc's own state —
  /// the dialog that asked has closed by the time it is worth reading.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concerns = incident.concerns;

    return Card(
      key: SafetyIncidentDetailScreen.concernsKey,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The cause', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'The incident itself is recorded here; the cause behind it is solved in the action '
              'log, as a Concern.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (notice != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                key: SafetyIncidentDetailScreen.concernNoticeKey,
                notice!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: Spacing.sm),
            if (concerns.isEmpty)
              Text(
                key: SafetyIncidentDetailScreen.noConcernsKey,
                'Nothing is being done about the cause yet.',
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final concern in concerns)
                    // `ListTile` carries the row's own `Key`, so a test finds
                    // the row by the Concern's id rather than by its text.
                    Card(
                      key: SafetyIncidentDetailScreen.concernRowKey(concern.id),
                      margin: const EdgeInsets.only(bottom: Spacing.sm),
                      child: ListTile(
                        onTap: () => context.go('${Routes.actions}/${concern.id}'),
                        title: Text(concern.title),
                        subtitle: Text(
                          [
                            concern.actionNo,
                            concern.typeLabel,
                            if (concern.ownerName != null) concern.ownerName!,
                            if (concern.isOverdue) 'overdue',
                          ].join(' · '),
                        ),
                        trailing: StatusChip(
                          label: concern.statusLabel,
                          tone: concern.statusTone,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.sm),
            FilledButton.icon(
              key: SafetyIncidentDetailScreen.raiseConcernKey,
              onPressed: busy
                  ? null
                  : () => context.go('${Routes.safetyIncidents}/${incident.id}/raise-concern'),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Raise a Concern'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The event history (issue #228): every severity change, status move, days
/// change, closure and classification change (issue #224), oldest first, with
/// who made it and when — mirrors Quality's own `_CorrectionsCard` shape.
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
              'Every severity change, status move, days change, closure and classification '
              'change, kept with who and when.',
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
