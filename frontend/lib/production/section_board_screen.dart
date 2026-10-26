/// A Section's production day (issue #339, spec #332), at
/// `/production/sections/:orgUnitId/board?date=`: every shift instance of the
/// day, earliest first, with its handover and what is wrong at that shift
/// boundary — the exceptions the server reports (`no handover recorded`,
/// `unacknowledged`, `amended after acknowledgement`), the late flag, and how
/// long after the shift began the handover was acknowledged.
///
/// An absent handover is shown as absent: there is no row to fill, only a
/// shift with no handover on it, which is the exception (ADR-0054's "derived,
/// never a fake row"). From a submitted handover the incoming Team Leader opens
/// the acknowledgement (`.../board/acknowledge/:handoverId`).
///
/// **The Production Destination lands here without a Section**
/// (`/production/sections`): the Screen then offers the Site's Org Unit tree
/// and opens the board of the Section chosen — the same shape the Attendance
/// picker gives its sheet, so this Screen has a real address to be reached
/// from. Only a Section can be chosen, because a handover is recorded at one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'handover.dart';
import 'handover_format.dart';
import 'handover_vocabulary.dart';
import 'section_board_bloc.dart';

class SectionBoardScreen extends StatelessWidget {
  const SectionBoardScreen({super.key, this.orgUnitId, this.date});

  /// Null at the Destination's own address, before a Section is chosen.
  final String? orgUnitId;
  final String? date;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> loadedKey = ValueKey<String>('section-board-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('section-board-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('section-board-retry');
  static const ValueKey<String> dateFieldKey = ValueKey<String>('section-board-date');
  static const ValueKey<String> emptyKey = ValueKey<String>('section-board-empty');
  static const ValueKey<String> chooserKey = ValueKey<String>('section-board-chooser');
  static ValueKey<String> sectionRowKey(String id) => ValueKey<String>('section-board-section-$id');
  static ValueKey<String> shiftRowKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId');
  static ValueKey<String> handoverStatusKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-status');
  static ValueKey<String> exceptionKey(String shiftInstanceId, String exception) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-$exception');
  static ValueKey<String> lateKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-late');
  static ValueKey<String> latencyKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-latency');
  static ValueKey<String> openHandoverKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-open');
  static ValueKey<String> acknowledgeKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-acknowledge');

  @override
  Widget build(BuildContext context) {
    final orgUnitId = this.orgUnitId;
    if (orgUnitId == null) return const _SectionChooser();

    final state = context.watch<SectionBoardBloc>().state;
    return Scaffold(
      body: switch (state) {
        SectionBoardLoading() => const SkeletonList(maxWidth: maxWidth),
        SectionBoardUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: "That Section's day could not be read",
            message: message,
            retryKey: retryKey,
            onRetry: () =>
                context.read<SectionBoardBloc>().add(SectionBoardStarted(orgUnitId: orgUnitId, date: date)),
          ),
        SectionBoardLoaded(day: final day) => _Board(orgUnitId: orgUnitId, day: day),
      },
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.orgUnitId, required this.day});

  final String orgUnitId;
  final SectionDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SectionBoardScreen.maxWidth,
        child: ListView(
          key: SectionBoardScreen.loadedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go(Routes.production),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Choose another Section'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(day.sectionName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              'Every shift of the production day, with its handover and what is still open at each '
              'shift boundary.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: 260,
              child: AppDateField(
                key: SectionBoardScreen.dateFieldKey,
                name: 'section-board-date',
                label: 'Production day',
                value: day.productionDate,
                onChanged: (value) {
                  if (value != null) context.go(Routes.sectionBoard(orgUnitId, date: value));
                },
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (day.shifts.isEmpty)
              Text(
                'No shifts are scheduled at this Section on that day.',
                key: SectionBoardScreen.emptyKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final shift in day.shifts) _ShiftRow(orgUnitId: orgUnitId, day: day, shift: shift),
          ],
        ),
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.orgUnitId, required this.day, required this.shift});

  final String orgUnitId;
  final SectionDay day;
  final SectionShift shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = shift.shiftInstanceId;
    final handover = shift.handover;
    final latency = shift.acknowledgementLatencyMinutes;
    return Card(
      key: SectionBoardScreen.shiftRowKey(id),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shift ${formatClock(shift.startsAt)}–${formatClock(shift.endsAt)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (handover != null)
                  StatusChip(
                    key: SectionBoardScreen.handoverStatusKey(id),
                    label: switch (handover.status) {
                      'draft' => 'Draft',
                      'submitted' => 'Submitted',
                      'acknowledged' => 'Acknowledged',
                      _ => handover.status,
                    },
                    tone: switch (handover.status) {
                      'acknowledged' => StatusTone.success,
                      'submitted' => StatusTone.info,
                      _ => StatusTone.neutral,
                    },
                  ),
                if (shift.late == true)
                  StatusChip(key: SectionBoardScreen.lateKey(id), label: 'Late', tone: StatusTone.warning),
                for (final exception in shift.exceptions)
                  StatusChip(
                    key: SectionBoardScreen.exceptionKey(id, exception),
                    label: HandoverVocabulary.exceptionLabel(exception),
                    tone: StatusTone.danger,
                  ),
              ],
            ),
            if (handover?.authorDisplayName != null || latency != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  if (handover?.authorDisplayName != null) 'Handed over by ${handover!.authorDisplayName}',
                  if (latency != null) 'acknowledged ${formatMinutes(latency)} after the shift began',
                ].join(' · '),
                key: latency != null ? SectionBoardScreen.latencyKey(id) : null,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                OutlinedButton.icon(
                  key: SectionBoardScreen.openHandoverKey(id),
                  onPressed: () => context.go(Routes.shiftHandover(orgUnitId, id, date: day.productionDate)),
                  icon: Icon(handover == null || handover.isDraft ? Icons.edit_note_outlined : Icons.description_outlined),
                  label: Text(switch (handover?.status) {
                    null => 'Write the handover',
                    'draft' => 'Continue the handover',
                    _ => 'Open the handover',
                  }),
                ),
                if (handover != null && handover.status == 'submitted')
                  FilledButton.icon(
                    key: SectionBoardScreen.acknowledgeKey(id),
                    onPressed: () => context.go(
                      Routes.handoverAcknowledge(orgUnitId, handover.id, date: day.productionDate),
                    ),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: const Text('Acknowledge'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Destination's landing: the Site's Org Unit tree, browsed with People's
/// `OrgUnitPickerBloc`, where a Section opens its board and any other level
/// only expands.
class _SectionChooser extends StatelessWidget {
  const _SectionChooser();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrgUnitPickerBloc>(
      create: (context) => OrgUnitPickerBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      )..add(const OrgUnitPickerStarted()),
      child: const _ChooserBody(),
    );
  }
}

class _ChooserBody extends StatelessWidget {
  const _ChooserBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = Text(state.sitesFailure ?? 'The Sites are unavailable.');
    } else if (state.rootsFailure != null) {
      body = Text(state.rootsFailure!);
    } else if (state.rows.isEmpty) {
      body = const Text('Nothing to browse in this Site.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in state.rows) _OrgUnitRow(row: row, bloc: bloc)],
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: SectionBoardScreen.maxWidth,
          child: ListView(
            key: SectionBoardScreen.chooserKey,
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Text('Shift handovers', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                "Choose a Section to open its board: the day's shifts and the handover at each.",
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              if (state.sites.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: state.siteId,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Site'),
                  items: [
                    for (final site in state.sites) DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (siteId) {
                    if (siteId != null) bloc.add(OrgUnitPickerSiteSelected(siteId));
                  },
                ),
              const SizedBox(height: Spacing.sm),
              DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgUnitRow extends StatelessWidget {
  const _OrgUnitRow({required this.row, required this.bloc});

  final OrgUnitRow row;
  final OrgUnitPickerBloc bloc;

  static const String _sectionUnitType = 'section';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSection = row.node.unitType == _sectionUnitType;
    return Padding(
      padding: EdgeInsets.only(left: row.depth * Spacing.lg),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: row.isLoadingChildren
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.sm),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                    onPressed: () => bloc.add(
                      row.isExpanded ? OrgUnitPickerCollapsed(row.node.id) : OrgUnitPickerExpanded(row.node.id),
                    ),
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: InkWell(
              key: SectionBoardScreen.sectionRowKey(row.node.id),
              onTap: isSection ? () => context.go(Routes.sectionBoard(row.node.id)) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Text(
                  isSection ? row.node.name : '${row.node.name} · ${row.node.unitType}',
                  style: isSection
                      ? TextStyle(color: theme.colorScheme.primary)
                      : TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
