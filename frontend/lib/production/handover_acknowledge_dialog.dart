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
///
/// **Its shell is `AppDialog`** (issue #389, the pattern F1/ADR-0058 wrote into
/// `docs/design-language.md` §11): the width is the primitive's `wide` rather
/// than a `SizedBox(460)` inside the content, the title and the action row are
/// the width the author chose, the action row is ordered dismiss-then-primary
/// with each action at 44px, focus is trapped and restored, `Esc` cancels, and
/// at a 700px box or a text scale of 1.5 the whole thing is a bottom sheet. What
/// the acknowledgement *records* — every key, every field, every Bloc event, the
/// wording of every sentence — is unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'handover.dart';
import 'handover_vocabulary.dart';
import 'production_api.dart';
import 'section_board_bloc.dart';
import '../widgets/notice_text.dart';
import '../l10n/vocabulary.dart';

class HandoverAcknowledgeDialog extends StatefulWidget {
  const HandoverAcknowledgeDialog({super.key, required this.handoverId});

  final String handoverId;

  static const ValueKey<String> loadingKey = ValueKey<String>('handover-acknowledge-loading');
  static const ValueKey<String> readFailureKey = ValueKey<String>('handover-acknowledge-read-failure');
  static const ValueKey<String> noteKey = ValueKey<String>('handover-acknowledge-note');

  /// The two actions' keys, which `AppDialog` owns the shape of: the id names
  /// the action, the primitive derives the `Key`. The accessors are unchanged,
  /// so every caller and test that finds the control by them still does; the
  /// values moved from `handover-acknowledge-submit` to
  /// `app-dialog-action-handover-acknowledge-submit` (listed in the PR).
  static final ValueKey<String> submitKey = AppDialog.actionKey('handover-acknowledge-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('handover-acknowledge-cancel');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final handover = _handover;

    final Widget content;
    if (_readFailure != null) {
      content = NoticeText(
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
            l10n.handoverAcknowledgeYouAreAcceptingAndTheShift(handover.sectionName ?? 'the Section', handover.authorDisplayName != null ? ' from ${handover.authorDisplayName}' : ''),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          if (points.isEmpty)
            Text(
              handover.changePointsNone
                  ? l10n.handoverAcknowledgeTheOutgoingShiftDeclaredNoChangePoints
                  : l10n.handoverAcknowledgeThereAreNoChangePointsToWatch,
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Text(l10n.handoverAcknowledgeWhatEachWatchShowed, style: theme.textTheme.titleSmall),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${handoverDimensionLabel(l10n, point.dimension)} · ${point.description}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      l10n.handoverAcknowledgeWatch(point.watchNote),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.xs),
                    DropdownButtonFormField<String?>(
                      key: HandoverAcknowledgeDialog.resultKey(point.id),
                      initialValue: _results[point.id],
                      isDense: true,
                      decoration: InputDecoration(labelText: l10n.handoverAcknowledgeFound),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.handoverAcknowledgeNotAnswered)),
                        for (final choice in HandoverVocabulary.watchResults)
                          DropdownMenuItem<String?>(value: choice, child: Text(handoverWatchResultLabel(l10n, choice))),
                      ],
                      onChanged: _awaiting ? null : (value) => setState(() => _results[point.id] = value),
                    ),
                    TextField(
                      key: HandoverAcknowledgeDialog.resultNoteKey(point.id),
                      controller: _resultNotes[point.id],
                      enabled: !_awaiting,
                      decoration: InputDecoration(labelText: l10n.commonNoteOptional),
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
            decoration: InputDecoration(labelText: l10n.handoverAcknowledgeNoteOnTheHandoverOptional, border: OutlineInputBorder()),
          ),
          if (_failure != null)
            Padding(
              key: HandoverAcknowledgeDialog.failureKey,
              padding: const EdgeInsets.only(top: Spacing.md),
              child: NoticeText(_failure!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      );
    }

    return BlocListener<SectionBoardBloc, SectionBoardState>(
      listener: _onBoardChanged,
      child: AppDialog(
        title: l10n.handoverAcknowledgeAcknowledgeTheHandover,
        // A watch block per Change point, each with two fields, plus the note:
        // content with its own shape rather than a six-field form (§11).
        size: AppDialogSize.wide,
        actions: [
          AppDialogAction(
            id: 'handover-acknowledge-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'handover-acknowledge-submit',
            label: _awaiting ? l10n.handoverAcknowledgeAcknowledging : l10n.commonAcknowledge,
            onPressed: handover == null || _awaiting ? null : _submit,
          ),
        ],
        child: content,
      ),
    );
  }
}
