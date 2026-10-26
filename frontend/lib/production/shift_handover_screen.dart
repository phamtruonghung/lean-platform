/// One Section's Shift handover for one shift instance (issue #339, spec
/// #332), at `/production/sections/:orgUnitId/handover/:shiftInstanceId`.
///
/// The six blocks render in the order the paper form is walked: the numbers the
/// shift closed on (frozen at submit, so a draft shows `—` for each), one
/// Machine status line per Asset in the Section, the Change points grouped by
/// the 4M, the Section's open Actions and what this handover does with each,
/// and the handover evidence. Submit is last.
///
/// **Submit is never greyed out.** A handover that is not complete is refused
/// by the server with everything it is missing at once (409,
/// `INCOMPLETE_HANDOVER`), and that list renders at the top of the form —
/// which Asset has no line, which line is short of what, which block is
/// unanswered, which Action has no disposition. A disabled button would say
/// "not yet" without saying why.
///
/// A sealed handover renders the same blocks read-only: what was handed over
/// is the record, and an amendment is its own act, not an edit of this one.
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
import '../widgets/app_page_frame.dart';
import '../widgets/app_search_field.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'handover.dart';
import 'handover_format.dart';
import 'handover_vocabulary.dart';
import 'shift_handover_bloc.dart';

class ShiftHandoverScreen extends StatelessWidget {
  const ShiftHandoverScreen({
    super.key,
    required this.orgUnitId,
    required this.shiftInstanceId,
    this.date,
  });

  final String orgUnitId;
  final String shiftInstanceId;

  /// The production day the board was showing, carried so the day read finds
  /// this shift and Back returns to the same day.
  final String? date;

  /// The registers' wider measure rather than `AppLayout.pageWidth`: a row of
  /// thirteen frozen numbers and a machine line's pickers side by side are a
  /// form's width, the same reason the CAPA report spends 1100.
  static const double maxWidth = 1100;

  static const ValueKey<String> loadedKey = ValueKey<String>('shift-handover-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('shift-handover-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('shift-handover-retry');
  static const ValueKey<String> backKey = ValueKey<String>('shift-handover-back');
  static const ValueKey<String> statusKey = ValueKey<String>('shift-handover-status');
  static const ValueKey<String> failureKey = ValueKey<String>('shift-handover-failure');
  static const ValueKey<String> refusalKey = ValueKey<String>('shift-handover-refusal');
  static const ValueKey<String> submitKey = ValueKey<String>('shift-handover-submit');

  static ValueKey<String> statusCardKey(String field) => ValueKey<String>('shift-handover-card-$field');

  static ValueKey<String> machineRowKey(String assetId) => ValueKey<String>('shift-handover-machine-$assetId');
  static ValueKey<String> machineStateKey(String assetId) =>
      ValueKey<String>('shift-handover-machine-$assetId-state');
  static ValueKey<String> machineAbnormalityKey(String assetId) =>
      ValueKey<String>('shift-handover-machine-$assetId-abnormality');
  static ValueKey<String> machineNoteKey(String assetId) => ValueKey<String>('shift-handover-machine-$assetId-note');
  static ValueKey<String> machineWatchKey(String assetId) =>
      ValueKey<String>('shift-handover-machine-$assetId-watch');
  static ValueKey<String> machineWalkedKey(String assetId) =>
      ValueKey<String>('shift-handover-machine-$assetId-walked');
  static ValueKey<String> machineSaveKey(String assetId) => ValueKey<String>('shift-handover-machine-$assetId-save');

  static const ValueKey<String> changePointsNoneKey = ValueKey<String>('shift-handover-change-points-none');
  static const ValueKey<String> changePointDimensionKey = ValueKey<String>('shift-handover-change-point-dimension');
  static const ValueKey<String> changePointDescriptionKey =
      ValueKey<String>('shift-handover-change-point-description');
  static const ValueKey<String> changePointWatchKey = ValueKey<String>('shift-handover-change-point-watch');
  static const ValueKey<String> changePointAddKey = ValueKey<String>('shift-handover-change-point-add');
  static ValueKey<String> changePointGroupKey(String dimension) =>
      ValueKey<String>('shift-handover-change-points-$dimension');
  static ValueKey<String> changePointKey(String id) => ValueKey<String>('shift-handover-change-point-$id');
  static ValueKey<String> changePointRemoveKey(String id) =>
      ValueKey<String>('shift-handover-change-point-$id-remove');

  static ValueKey<String> openActionKey(String actionId) => ValueKey<String>('shift-handover-action-$actionId');
  static ValueKey<String> actionDispositionKey(String actionId) =>
      ValueKey<String>('shift-handover-action-$actionId-disposition');
  static ValueKey<String> actionOwnerKey(String actionId) => ValueKey<String>('shift-handover-action-$actionId-owner');
  static ValueKey<String> actionClosureNoteKey(String actionId) =>
      ValueKey<String>('shift-handover-action-$actionId-closure-note');
  static ValueKey<String> actionRecordKey(String actionId) =>
      ValueKey<String>('shift-handover-action-$actionId-record');
  static ValueKey<String> actionErrorKey(String actionId) => ValueKey<String>('shift-handover-action-$actionId-error');
  static ValueKey<String> actionLinkKey(String linkId) => ValueKey<String>('shift-handover-link-$linkId');
  static ValueKey<String> actionLinkRemoveKey(String linkId) =>
      ValueKey<String>('shift-handover-link-$linkId-remove');

  static const ValueKey<String> jointWalkKey = ValueKey<String>('shift-handover-joint-walk');
  static const ValueKey<String> criticalItemsKey = ValueKey<String>('shift-handover-critical-items');
  static const ValueKey<String> deviationReasonKey = ValueKey<String>('shift-handover-deviation-reason');
  static const ValueKey<String> evidenceSaveKey = ValueKey<String>('shift-handover-evidence-save');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftHandoverBloc>().state;

    return Scaffold(
      body: switch (state) {
        ShiftHandoverLoading() => const SkeletonList(maxWidth: maxWidth),
        ShiftHandoverUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That handover could not be opened',
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<ShiftHandoverBloc>().add(
                  ShiftHandoverStarted(orgUnitId: orgUnitId, shiftInstanceId: shiftInstanceId, date: date),
                ),
          ),
        ShiftHandoverLoaded() => _Loaded(state: state, orgUnitId: orgUnitId, date: date),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.orgUnitId, this.date});

  final ShiftHandoverLoaded state;
  final String orgUnitId;
  final String? date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handover = state.handover;
    final editable = handover.isDraft && !state.isMutating;

    return Center(
      child: AppPageFrame(
        maxWidth: ShiftHandoverScreen.maxWidth,
        child: ListView(
          key: ShiftHandoverScreen.loadedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ShiftHandoverScreen.backKey,
                onPressed: () => context.go(Routes.sectionBoard(orgUnitId, date: date ?? handover.productionDate)),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to the Section board'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (handover.handoverNo != null) Text(handover.handoverNo!, style: theme.textTheme.labelMedium),
                StatusChip(
                  key: ShiftHandoverScreen.statusKey,
                  label: _statusLabel(handover.status),
                  tone: _statusTone(handover.status),
                ),
                if (handover.late == true) const StatusChip(label: 'Late', tone: StatusTone.warning),
                if (handover.version > 1) StatusChip(label: 'Version ${handover.version}', tone: StatusTone.info),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Shift handover · ${handover.sectionName ?? 'Section'}',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${handover.productionDate ?? ''} · ${formatClock(handover.shiftStartsAt)}–'
              '${formatClock(handover.shiftEndsAt)}'
              '${handover.authorDisplayName != null ? ' · handed over by ${handover.authorDisplayName}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (state.refusal != null) ...[
              const SizedBox(height: Spacing.lg),
              _RefusalPanel(refusal: state.refusal!),
            ],
            if (state.mutationFailure != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                state.mutationFailure!,
                key: ShiftHandoverScreen.failureKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            _Heading('The numbers the shift closed on',
                handover.isDraft ? 'Frozen when the handover is submitted.' : 'Frozen at submit.'),
            _StatusCards(handover: handover),
            const SizedBox(height: Spacing.xl),
            _Heading('Machines', 'One line per Asset in the Section.'),
            if (state.assets.isEmpty)
              Text('This Section has no active Assets.', style: theme.textTheme.bodyMedium)
            else
              for (final asset in state.assets)
                _MachineRow(
                  key: ShiftHandoverScreen.machineRowKey(asset.id),
                  asset: asset,
                  line: handover.lineFor(asset.id),
                  enabled: editable,
                  showSave: handover.isDraft,
                ),
            const SizedBox(height: Spacing.xl),
            _Heading('Change points', 'What the incoming shift will meet that differs, and what to watch.'),
            _ChangePoints(handover: handover, enabled: editable),
            const SizedBox(height: Spacing.xl),
            _Heading('Carried actions', 'Every open Action of the Section is carried, reassigned or closed.'),
            _Actions(handover: handover, enabled: editable),
            const SizedBox(height: Spacing.xl),
            _Heading('Handover evidence', null),
            _Evidence(handover: handover, enabled: editable),
            if (handover.isDraft) ...[
              const SizedBox(height: Spacing.xl),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: ShiftHandoverScreen.submitKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.read<ShiftHandoverBloc>().add(const HandoverSubmitted()),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Submit the handover'),
                ),
              ),
            ] else if (handover.acknowledgedAt != null) ...[
              const SizedBox(height: Spacing.xl),
              Text(
                'Acknowledged ${formatClock(handover.acknowledgedAt)}'
                '${handover.acknowledgementNote != null ? ' — ${handover.acknowledgementNote}' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'draft' => 'Draft',
      'submitted' => 'Submitted',
      'acknowledged' => 'Acknowledged',
      _ => status,
    };

StatusTone _statusTone(String status) => switch (status) {
      'draft' => StatusTone.neutral,
      'submitted' => StatusTone.info,
      'acknowledged' => StatusTone.success,
      _ => StatusTone.neutral,
    };

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.description);

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (description != null)
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Submit's refusal, with every gap it named — at the top of the form, where
/// the person who pressed Submit reads first.
class _RefusalPanel extends StatelessWidget {
  const _RefusalPanel({required this.refusal});

  final HandoverRefusal refusal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lines = [
      for (final asset in refusal.missingAssets) 'No machine status line for ${asset.code} · ${asset.name}',
      for (final line in refusal.incompleteLines) '${line.code} · ${line.name} is missing its ${line.missing.join(' and ')}',
      for (final block in refusal.unansweredBlocks)
        if (block == 'changePoints')
          'The change points are unanswered: add one, or declare there are none this shift'
        else
          '$block is unanswered',
      for (final action in refusal.undispositionedActions) 'No disposition for ${action.code} · ${action.name}',
    ];
    return Container(
      key: ShiftHandoverScreen.refusalKey,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This handover cannot be submitted yet',
            style: theme.textTheme.titleSmall?.copyWith(color: colors.onErrorContainer),
          ),
          const SizedBox(height: Spacing.xs),
          if (lines.isEmpty)
            Text(refusal.message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer))
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xxs),
                child: Text('• $line', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer)),
              ),
        ],
      ),
    );
  }
}

enum _Unit { percent, minutes, count }

const List<(String, String, _Unit)> _snapshotCards = [
  ('oee', 'OEE', _Unit.percent),
  ('availability', 'Availability', _Unit.percent),
  ('performance', 'Performance', _Unit.percent),
  ('quality', 'Quality', _Unit.percent),
  ('plannedProductionMinutes', 'Planned minutes', _Unit.minutes),
  ('runMinutes', 'Run minutes', _Unit.minutes),
  ('unplannedDowntimeMinutes', 'Unplanned downtime', _Unit.minutes),
  ('goodQuantity', 'Good', _Unit.count),
  ('rejectQuantity', 'Reject', _Unit.count),
  ('reworkQuantity', 'Rework', _Unit.count),
  ('openStopCount', 'Open stops', _Unit.count),
  ('openQualityIssueCount', 'Open quality issues', _Unit.count),
  ('safetyEventCount', 'Safety events', _Unit.count),
];

/// The frozen snapshot, read-only. A null is shown as `—`, with the reason the
/// server gave for it when it gave one.
class _StatusCards extends StatelessWidget {
  const _StatusCards({required this.handover});

  final ShiftHandover handover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final (field, label, unit) in _snapshotCards)
          SizedBox(
            width: 160,
            child: Card(
              key: ShiftHandoverScreen.statusCardKey(field),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(_value(handover.snapshot[field], unit), style: theme.textTheme.titleLarge),
                    for (final gap in handover.snapshotGaps)
                      if (gap.field == field)
                        Text(
                          gap.reason,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _value(num? value, _Unit unit) {
    if (value == null) return '—';
    return switch (unit) {
      _Unit.percent => formatPercent(value),
      _Unit.minutes => formatMinutes(value),
      _Unit.count => value % 1 == 0 ? '${value.toInt()}' : '$value',
    };
  }
}

/// One Asset's Machine status line: the state it is left in, an abnormality
/// when one was found, the note, what the incoming shift must watch, and
/// whether it was walked.
class _MachineRow extends StatefulWidget {
  const _MachineRow({
    super.key,
    required this.asset,
    required this.line,
    required this.enabled,
    required this.showSave,
  });

  final SectionAsset asset;
  final MachineLine? line;
  final bool enabled;
  final bool showSave;

  @override
  State<_MachineRow> createState() => _MachineRowState();
}

class _MachineRowState extends State<_MachineRow> {
  late String? _state = widget.line?.state;
  late String? _abnormality = widget.line?.abnormalityType;
  late bool _walked = widget.line?.walked ?? false;
  late final TextEditingController _note = TextEditingController(text: widget.line?.note ?? '');
  late final TextEditingController _watch = TextEditingController(text: widget.line?.watchNote ?? '');

  @override
  void dispose() {
    _note.dispose();
    _watch.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _save() {
    final state = _state;
    if (state == null) return;
    final line = widget.line;
    context.read<ShiftHandoverBloc>().add(
          MachineLineSaved(
            assetId: widget.asset.id,
            line: {
              'state': state,
              'abnormalityType': _abnormality,
              'note': _trimmed(_note),
              'watchNote': _trimmed(_watch),
              'walked': _walked,
              // The PUT replaces the whole line; the references that explain it
              // are kept rather than cleared by a rewrite of the words.
              if (line?.downtimeEventId != null) 'downtimeEventId': line!.downtimeEventId,
              if (line?.qualityIssueId != null) 'qualityIssueId': line!.qualityIssueId,
              if (line?.workOrderId != null) 'workOrderId': line!.workOrderId,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.asset.id;
    final recorded = widget.line != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${widget.asset.code} · ${widget.asset.name}', style: theme.textTheme.titleSmall),
                if (!recorded) const StatusChip(label: 'No line yet', tone: StatusTone.warning),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ShiftHandoverScreen.machineStateKey(id),
                    initialValue: _state,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State'),
                    items: [
                      for (final choice in HandoverVocabulary.machineStates)
                        DropdownMenuItem<String>(value: choice.wire, child: Text(choice.label)),
                    ],
                    onChanged: widget.enabled ? (value) => setState(() => _state = value) : null,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String?>(
                    key: ShiftHandoverScreen.machineAbnormalityKey(id),
                    initialValue: _abnormality,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Abnormality'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None found')),
                      for (final choice in HandoverVocabulary.abnormalityTypes)
                        DropdownMenuItem<String?>(value: choice.wire, child: Text(choice.label)),
                    ],
                    onChanged: widget.enabled ? (value) => setState(() => _abnormality = value) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: ShiftHandoverScreen.machineNoteKey(id),
              controller: _note,
              enabled: widget.enabled,
              decoration: InputDecoration(
                labelText: 'Note',
                helperText: _state != null && !HandoverVocabulary.normalRunningStates.contains(_state)
                    ? 'Required: say why it is not running normally'
                    : null,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: ShiftHandoverScreen.machineWatchKey(id),
              controller: _watch,
              enabled: widget.enabled,
              decoration: const InputDecoration(labelText: 'What the incoming shift must watch'),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Checkbox(
                  key: ShiftHandoverScreen.machineWalkedKey(id),
                  value: _walked,
                  onChanged: widget.enabled ? (value) => setState(() => _walked = value ?? false) : null,
                ),
                const Text('Walked'),
                const Spacer(),
                if (widget.showSave)
                  OutlinedButton(
                    key: ShiftHandoverScreen.machineSaveKey(id),
                    onPressed: widget.enabled && _state != null ? _save : null,
                    child: Text(recorded ? 'Save line' : 'Record line'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 4M block: what is recorded under each dimension, the form to add one,
/// and the declaration that there are none this shift.
class _ChangePoints extends StatefulWidget {
  const _ChangePoints({required this.handover, required this.enabled});

  final ShiftHandover handover;
  final bool enabled;

  @override
  State<_ChangePoints> createState() => _ChangePointsState();
}

class _ChangePointsState extends State<_ChangePoints> {
  String _dimension = HandoverVocabulary.changePointDimensions.first.wire;
  final TextEditingController _description = TextEditingController();
  final TextEditingController _watch = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    _watch.dispose();
    super.dispose();
  }

  bool get _complete => _description.text.trim().isNotEmpty && _watch.text.trim().isNotEmpty;

  void _add() {
    if (!_complete) return;
    context.read<ShiftHandoverBloc>().add(
          ChangePointAdded(
            dimension: _dimension,
            description: _description.text.trim(),
            watchNote: _watch.text.trim(),
          ),
        );
    _description.clear();
    _watch.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handover = widget.handover;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              key: ShiftHandoverScreen.changePointsNoneKey,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: handover.changePointsNone,
              title: const Text('No change points this shift'),
              onChanged: widget.enabled
                  ? (value) => context
                      .read<ShiftHandoverBloc>()
                      .add(HandoverHeaderSaved({'changePointsNone': value ?? false}))
                  : null,
            ),
            for (final dimension in HandoverVocabulary.changePointDimensions)
              Padding(
                key: ShiftHandoverScreen.changePointGroupKey(dimension.wire),
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(dimension.label, style: theme.textTheme.titleSmall),
                    if ((handover.changePoints[dimension.wire] ?? const []).isEmpty)
                      Text(
                        'None recorded',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    for (final point in handover.changePoints[dimension.wire] ?? const <ChangePoint>[])
                      Row(
                        key: ShiftHandoverScreen.changePointKey(point.id),
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(point.description, style: theme.textTheme.bodyMedium),
                                Text(
                                  'Watch: ${point.watchNote}'
                                  '${point.watchResult != null ? ' · found ${HandoverVocabulary.watchResultLabel(point.watchResult)}' : ''}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (handover.isDraft)
                            IconButton(
                              key: ShiftHandoverScreen.changePointRemoveKey(point.id),
                              tooltip: 'Remove',
                              onPressed: widget.enabled
                                  ? () => context.read<ShiftHandoverBloc>().add(ChangePointRemoved(point.id))
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            if (handover.isDraft) ...[
              const Divider(height: Spacing.xl),
              Text('Add a change point', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ShiftHandoverScreen.changePointDimensionKey,
                  initialValue: _dimension,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Dimension'),
                  items: [
                    for (final choice in HandoverVocabulary.changePointDimensions)
                      DropdownMenuItem<String>(value: choice.wire, child: Text(choice.label)),
                  ],
                  onChanged: widget.enabled ? (value) => setState(() => _dimension = value ?? _dimension) : null,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: ShiftHandoverScreen.changePointDescriptionKey,
                controller: _description,
                enabled: widget.enabled,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'What is different'),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: ShiftHandoverScreen.changePointWatchKey,
                controller: _watch,
                enabled: widget.enabled,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'What the incoming shift must watch for'),
              ),
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: ShiftHandoverScreen.changePointAddKey,
                  onPressed: widget.enabled && _complete ? _add : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add change point'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Section's Actions: those this handover has already dispositioned, and
/// the open ones it still owes a disposition for.
class _Actions extends StatelessWidget {
  const _Actions({required this.handover, required this.enabled});

  final ShiftHandover handover;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (handover.actions.isEmpty && handover.openActions.isEmpty) {
      return Text(
        'The Section has no open Actions to hand over.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final link in handover.actions)
          Card(
            key: ShiftHandoverScreen.actionLinkKey(link.id),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${link.action.actionNo} · ${link.action.title}', style: theme.textTheme.titleSmall),
                        Text(
                          [
                            HandoverVocabulary.dispositionLabel(link.disposition),
                            if (link.ownerName != null) 'to ${link.ownerName}',
                            if (link.closureNote != null) link.closureNote!,
                            if (link.ageShifts != null && link.ageShifts! > 0)
                              '${link.ageShifts} ${link.ageShifts == 1 ? 'shift' : 'shifts'} old',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (handover.isDraft)
                    IconButton(
                      key: ShiftHandoverScreen.actionLinkRemoveKey(link.id),
                      tooltip: 'Remove',
                      onPressed: enabled
                          ? () => context.read<ShiftHandoverBloc>().add(ActionLinkRemoved(link.id))
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
          ),
        for (final action in handover.openActions)
          _OpenActionRow(key: ShiftHandoverScreen.openActionKey(action.id), action: action, enabled: enabled),
      ],
    );
  }
}

class _OpenActionRow extends StatefulWidget {
  const _OpenActionRow({super.key, required this.action, required this.enabled});

  final HandoverActionSummary action;
  final bool enabled;

  @override
  State<_OpenActionRow> createState() => _OpenActionRowState();
}

class _OpenActionRowState extends State<_OpenActionRow> {
  String? _disposition;
  Employee? _owner;
  final TextEditingController _closureNote = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _closureNote.dispose();
    super.dispose();
  }

  void _record() {
    final disposition = _disposition;
    if (disposition == null) {
      setState(() => _error = 'Choose what this handover does with the action.');
      return;
    }
    // Each disposition owes its evidence when it is written — the server's own
    // rule, said here before anything is sent so the field it wants is named.
    if (disposition == 'reassigned' && _owner == null) {
      setState(() => _error = 'A reassigned action names who now owns it.');
      return;
    }
    final note = _closureNote.text.trim();
    if (disposition == 'closed' && note.isEmpty) {
      setState(() => _error = 'Say what closed this action: the evidence is the point.');
      return;
    }
    setState(() => _error = null);
    context.read<ShiftHandoverBloc>().add(
          ActionDispositioned(
            actionId: widget.action.id,
            disposition: disposition,
            ownerEmployeeId: disposition == 'reassigned' ? _owner!.id : null,
            closureNote: disposition == 'closed' ? note : null,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.action;
    final id = action.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${action.actionNo} · ${action.title}', style: theme.textTheme.titleSmall),
            Text(
              [
                if (action.ownerName != null) 'Owner ${action.ownerName}',
                if (action.dueDate != null) 'due ${action.dueDate}',
                'no disposition yet',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ShiftHandoverScreen.actionDispositionKey(id),
                initialValue: _disposition,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Disposition'),
                items: [
                  for (final choice in HandoverVocabulary.dispositions)
                    DropdownMenuItem<String>(value: choice.wire, child: Text(choice.label)),
                ],
                onChanged: widget.enabled
                    ? (value) => setState(() {
                          _disposition = value;
                          _error = null;
                        })
                    : null,
              ),
            ),
            if (_disposition == 'reassigned') ...[
              const SizedBox(height: Spacing.sm),
              AppSearchField<Employee>(
                key: ShiftHandoverScreen.actionOwnerKey(id),
                name: 'handover-action-$id-owner',
                label: 'New owner',
                value: _owner,
                enabled: widget.enabled,
                onChanged: (employee) => setState(() => _owner = employee),
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
                onSelected: (employee) => setState(() => _owner = employee),
              ),
            ],
            if (_disposition == 'closed') ...[
              const SizedBox(height: Spacing.sm),
              TextField(
                key: ShiftHandoverScreen.actionClosureNoteKey(id),
                controller: _closureNote,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'What closed it'),
              ),
            ],
            if (_error != null)
              Padding(
                key: ShiftHandoverScreen.actionErrorKey(id),
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: ShiftHandoverScreen.actionRecordKey(id),
                onPressed: widget.enabled ? _record : null,
                child: const Text('Record disposition'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The handover's own evidence: whether the two Team Leaders walked the
/// Section together, the critical items said aloud, and why it went otherwise
/// than the standard way, when it did.
class _Evidence extends StatefulWidget {
  const _Evidence({required this.handover, required this.enabled});

  final ShiftHandover handover;
  final bool enabled;

  @override
  State<_Evidence> createState() => _EvidenceState();
}

class _EvidenceState extends State<_Evidence> {
  late bool _jointWalk = widget.handover.jointWalkDone;
  late String _deviation = widget.handover.deviationReason ?? HandoverVocabulary.deviationReasons.first.wire;
  late final TextEditingController _critical = TextEditingController(text: widget.handover.criticalItems ?? '');

  @override
  void dispose() {
    _critical.dispose();
    super.dispose();
  }

  void _save() {
    final critical = _critical.text.trim();
    context.read<ShiftHandoverBloc>().add(
          HandoverHeaderSaved({
            'jointWalkDone': _jointWalk,
            'criticalItems': critical.isEmpty ? null : critical,
            'deviationReason': _deviation,
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              key: ShiftHandoverScreen.jointWalkKey,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _jointWalk,
              title: const Text('Joint walk done'),
              onChanged: widget.enabled ? (value) => setState(() => _jointWalk = value ?? false) : null,
            ),
            TextField(
              key: ShiftHandoverScreen.criticalItemsKey,
              controller: _critical,
              enabled: widget.enabled,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Critical items'),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                key: ShiftHandoverScreen.deviationReasonKey,
                initialValue: _deviation,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Deviation from the standard handover'),
                items: [
                  for (final choice in HandoverVocabulary.deviationReasons)
                    DropdownMenuItem<String>(value: choice.wire, child: Text(choice.label)),
                ],
                onChanged: widget.enabled ? (value) => setState(() => _deviation = value ?? _deviation) : null,
              ),
            ),
            if (widget.handover.isDraft) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: ShiftHandoverScreen.evidenceSaveKey,
                  onPressed: widget.enabled ? _save : null,
                  child: const Text('Save evidence'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
