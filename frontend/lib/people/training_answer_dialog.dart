/// The signature step of confirming a Training record (issue #318, ADR-0052,
/// CONTEXT.md's Signature): before a Trainee's `confirmed` answer is sent they
/// choose what it is signed with - the Signature they keep, one drawn now, or
/// nothing at all.
///
/// It is a dialog, not a Screen, and it knows nothing about where the answer
/// goes: it resolves to a [TrainingAnswerSignature] (or null when dismissed,
/// so nothing is sent) and the Screen that opened it dispatches the answer.
/// Declining never opens it - a decline carries no Signature. The drawing
/// surface is the shared `SignaturePad`, and "no Signature" is a first-class
/// choice: signing never gates an answer, so a Trainee with no mark still
/// confirms and their cell stays empty for a hand signature.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/signature_pad.dart';
import 'training_record.dart';

/// Opens the dialog; null when the person dismissed it.
Future<TrainingAnswerSignature?> showTrainingAnswerDialog(BuildContext context) =>
    showDialog<TrainingAnswerSignature>(
      context: context,
      builder: (_) => const TrainingAnswerDialog(),
    );

class TrainingAnswerDialog extends StatefulWidget {
  const TrainingAnswerDialog({super.key});

  static const ValueKey<String> dialogKey = ValueKey<String>('training-answer-dialog');
  static const ValueKey<String> useStoredKey = ValueKey<String>('training-answer-use-stored');
  static const ValueKey<String> drawKey = ValueKey<String>('training-answer-draw');
  static const ValueKey<String> noneKey = ValueKey<String>('training-answer-none');
  static const ValueKey<String> padKey = ValueKey<String>('training-answer-pad');
  static const ValueKey<String> submitDrawnKey = ValueKey<String>('training-answer-submit-drawn');
  static const ValueKey<String> clearDrawnKey = ValueKey<String>('training-answer-clear-drawn');
  static const ValueKey<String> cancelKey = ValueKey<String>('training-answer-cancel');

  @override
  State<TrainingAnswerDialog> createState() => _TrainingAnswerDialogState();
}

class _TrainingAnswerDialogState extends State<TrainingAnswerDialog> {
  final SignaturePadController _pad = SignaturePadController();
  bool _drawing = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _submitDrawn() async {
    final navigator = Navigator.of(context);
    final png = await _pad.toPng();
    if (png == null) return;
    navigator.pop(DrawnAnswerSignature(png));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: TrainingAnswerDialog.dialogKey,
      title: const Text('Sign your confirmation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose what your answer is signed with. You can also confirm without a Signature.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                FilledButton(
                  key: TrainingAnswerDialog.useStoredKey,
                  onPressed: () => Navigator.of(context).pop(const StoredAnswerSignature()),
                  child: const Text('Use my Signature'),
                ),
                OutlinedButton(
                  key: TrainingAnswerDialog.drawKey,
                  onPressed: _drawing ? null : () => setState(() => _drawing = true),
                  child: const Text('Draw one now'),
                ),
                OutlinedButton(
                  key: TrainingAnswerDialog.noneKey,
                  onPressed: () => Navigator.of(context).pop(const NoAnswerSignature()),
                  child: const Text('No Signature'),
                ),
              ],
            ),
            if (_drawing) ...[
              const SizedBox(height: Spacing.lg),
              SignaturePad(key: TrainingAnswerDialog.padKey, controller: _pad),
              const SizedBox(height: Spacing.md),
              ListenableBuilder(
                listenable: _pad,
                builder: (context, _) => Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    FilledButton(
                      key: TrainingAnswerDialog.submitDrawnKey,
                      onPressed: _pad.isEmpty ? null : _submitDrawn,
                      child: const Text('Confirm with this Signature'),
                    ),
                    OutlinedButton(
                      key: TrainingAnswerDialog.clearDrawnKey,
                      onPressed: _pad.isEmpty ? null : _pad.clear,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: TrainingAnswerDialog.cancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
