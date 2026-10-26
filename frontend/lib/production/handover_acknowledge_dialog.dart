/// The incoming Team Leader's Handover acknowledgement (issue #339), opened
/// from a submitted handover on the Section board at
/// `.../board/acknowledge/:handoverId` (ADR-0021: a dialog is an address).
///
/// It carries what the acknowledgement records beyond who and when: for each
/// Change point the outgoing shift asked to be watched, what the incoming shift
/// found (`ok`, `concern`, `not run`) with an optional note, and an optional
/// note on the whole. A Change point left unanswered is sent as nothing — the
/// server does not invent a result for it, and nor does this dialog.
///
/// The Change points are not on the board's own read of the day, so the dialog
/// reads the handover itself, the way `ActionFormDialog` reads its own Pillars.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'handover.dart';
import 'handover_vocabulary.dart';
import 'production_api.dart';
import 'section_board_bloc.dart';

class HandoverAcknowledgeDialog extends StatefulWidget {
  const HandoverAcknowledgeDialog({super.key, required this.handoverId});

  final String handoverId;

  static const ValueKey<String> loadingKey = ValueKey<String>('handover-acknowledge-loading');
  static const ValueKey<String> readFailureKey = ValueKey<String>('handover-acknowledge-read-failure');
  static const ValueKey<String> noteKey = ValueKey<String>('handover-acknowledge-note');
  static const ValueKey<String> submitKey = ValueKey<String>('handover-acknowledge-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('handover-acknowledge-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('handover-acknowledge-failure');
  static ValueKey<String> resultKey(String changePointId) =>
      ValueKey<String>('handover-acknowledge-result-$changePointId');
  static ValueKey<String> resultNoteKey(String changePointId) =>
      ValueKey<String>('handover-acknowledge-result-$changePointId-note');

  @override
  State<HandoverAcknowledgeDialog> createState() => _HandoverAcknowledgeDialogState();
}

class _HandoverAcknowledgeDialogState extends State<HandoverAcknowledgeDialog> {
  final TextEditingController _note = TextEditingController();
  final Map<String, String?> _results = {};
  final Map<String, TextEditingController> _resultNotes = {};

  ShiftHandover? _handover;
  String? _readFailure;
  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final controller in _resultNotes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() => _readFailure = SectionBoardBloc.signedOutMessage);
      return;
    }
    try {
      final handover = await context.read<ProductionApi>().fetchHandover(token, widget.handoverId);
      if (!mounted) return;
      setState(() {
        _handover = handover;
        for (final point in handover.allChangePoints) {
          _resultNotes[point.id] = TextEditingController();
        }
      });
    } on ProductionApiException catch (error) {
      if (!mounted) return;
      setState(() => _readFailure = error.message);
    }
  }

  void _submit() {
    final handover = _handover;
    if (handover == null || _awaiting) return;
    final note = _note.text.trim();
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SectionBoardBloc>().add(
          HandoverAcknowledgeConfirmed(
            handoverId: handover.id,
            note: note.isEmpty ? null : note,
            changePointResults: [
              for (final point in handover.allChangePoints)
                if (_results[point.id] != null)
                  {
                    'changePointId': point.id,
                    'result': _results[point.id],
                    if (_resultNotes[point.id]!.text.trim().isNotEmpty) 'note': _resultNotes[point.id]!.text.trim(),
                  },
            ],
          ),
        );
  }

  void _onBoardChanged(BuildContext context, SectionBoardState state) {
    if (!_awaiting || state is! SectionBoardLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handover = _handover;

    final Widget content;
    if (_readFailure != null) {
      content = Text(
        _readFailure!,
        key: HandoverAcknowledgeDialog.readFailureKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    } else if (handover == null) {
      content = const SizedBox(
        key: HandoverAcknowledgeDialog.loadingKey,
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final points = handover.allChangePoints;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You are accepting ${handover.sectionName ?? 'the Section'} and the shift'
            '${handover.authorDisplayName != null ? ' from ${handover.authorDisplayName}' : ''}.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          if (points.isEmpty)
            Text(
              handover.changePointsNone
                  ? 'The outgoing shift declared no change points.'
                  : 'There are no change points to watch.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Text('What each watch showed', style: theme.textTheme.titleSmall),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${HandoverVocabulary.dimensionLabel(point.dimension)} · ${point.description}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      'Watch: ${point.watchNote}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.xs),
                    DropdownButtonFormField<String?>(
                      key: HandoverAcknowledgeDialog.resultKey(point.id),
                      initialValue: _results[point.id],
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Found'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Not answered')),
                        for (final choice in HandoverVocabulary.watchResults)
                          DropdownMenuItem<String?>(value: choice.wire, child: Text(choice.label)),
                      ],
                      onChanged: _awaiting ? null : (value) => setState(() => _results[point.id] = value),
                    ),
                    TextField(
                      key: HandoverAcknowledgeDialog.resultNoteKey(point.id),
                      controller: _resultNotes[point.id],
                      enabled: !_awaiting,
                      decoration: const InputDecoration(labelText: 'Note (optional)'),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Spacing.md),
          TextField(
            key: HandoverAcknowledgeDialog.noteKey,
            controller: _note,
            enabled: !_awaiting,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note on the handover (optional)', border: OutlineInputBorder()),
          ),
          if (_failure != null)
            Padding(
              key: HandoverAcknowledgeDialog.failureKey,
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Text(_failure!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      );
    }

    return BlocListener<SectionBoardBloc, SectionBoardState>(
      listener: _onBoardChanged,
      child: AlertDialog(
        title: const Text('Acknowledge the handover'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: content)),
        actions: [
          TextButton(
            key: HandoverAcknowledgeDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: HandoverAcknowledgeDialog.submitKey,
            onPressed: handover == null || _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Acknowledging…' : 'Acknowledge'),
          ),
        ],
      ),
    );
  }
}
