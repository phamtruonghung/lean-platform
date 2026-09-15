/// Completing an Action's open phase (issue #177), and the host that decides
/// whether the address it was opened at is still an offer.
///
/// Addressed rather than popped — `${Routes.actions}/:id/phases/:phase/complete`
/// (ADR-0021) — so a refresh lands on the Action with the dialog open, and a
/// widget test drives it through the router the way `work_orders_test.dart`
/// drives its own transition dialogs.
///
/// Two things the form asks and nothing else: what was done (the note every
/// phase requires, because a phase completed with no evidence is the "list of
/// good intentions" the Module exists to refuse), and — on a Check only — the
/// verdict. Both are chosen from what the server offers rather than typed,
/// where there is a set to choose from (ADR-0023).
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

/// Resolves the Action the address names out of the detail read this Screen
/// already holds, and refuses the address when the phase it names is no longer
/// the one the Action is waiting on — the shape `WorkOrderDialogHost` uses for
/// its own transition routes.
class ActionPhaseCompleteDialogHost extends StatelessWidget {
  const ActionPhaseCompleteDialogHost({super.key, required this.phase});

  /// The phase the address named.
  final String phase;

  static const ValueKey<String> loadingKey = ValueKey<String>('action-phase-loading');
  static const ValueKey<String> notLoadedKey = ValueKey<String>('action-phase-unavailable');
  static const ValueKey<String> notOpenKey = ValueKey<String>('action-phase-not-open');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => AlertDialog(
          key: notLoadedKey,
          title: const Text('That Action could not be read'),
          content: Text(message),
          actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back'))],
        ),
      ActionDetailLoaded(action: final action) => action.openPhase?.phase != phase
          ? _refusal(context, action)
          : ActionPhaseCompleteDialog(action: action),
    };
  }

  /// The dialog was opened at a phase the Action is not waiting on — a stale
  /// bookmarked address, or somebody else advanced it a moment ago. Said
  /// rather than silently redirected, and the same wording the server's own
  /// 409 uses.
  Widget _refusal(BuildContext context, Action action) {
    final waitingOn = action.openPhase;
    return AlertDialog(
      key: notOpenKey,
      title: const Text('That is not the open phase'),
      content: Text(
        waitingOn == null
            ? 'This Action has no open phase left.'
            : 'This Action is waiting on its ${waitingOn.phaseLabel.toLowerCase()} phase, not its '
                '${actionPhaseLabel(phase).toLowerCase()}.',
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Back to the Action')),
      ],
    );
  }
}

class ActionPhaseCompleteDialog extends StatefulWidget {
  const ActionPhaseCompleteDialog({super.key, required this.action});

  final Action action;

  static const ValueKey<String> noteKey = ValueKey<String>('action-phase-note');
  static const ValueKey<String> outcomeKey = ValueKey<String>('action-phase-outcome');
  static const ValueKey<String> submitKey = ValueKey<String>('action-phase-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-phase-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('action-phase-failure');
  static ValueKey<String> outcomeOptionKey(String wire) =>
      ValueKey<String>('action-phase-outcome-$wire');

  @override
  State<ActionPhaseCompleteDialog> createState() => _ActionPhaseCompleteDialogState();
}

class _ActionPhaseCompleteDialogState extends State<ActionPhaseCompleteDialog> {
  final TextEditingController _note = TextEditingController();
  String? _outcome;
  bool _awaiting = false;
  String? _failure;

  ActionPhase get _phase => widget.action.openPhase!;
  bool get _isCheck => _phase.phase == 'check';
  bool get _complete => _note.text.trim().isNotEmpty && (!_isCheck || _outcome != null);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ActionDetailBloc>().add(
          ActionPhaseCompletionRequested(
            actionId: widget.action.id,
            phase: _phase.phase,
            note: _note.text.trim(),
            outcome: _isCheck ? _outcome : null,
          ),
        );
  }

  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (!_awaiting || state is! ActionDetailLoaded || state.isCompleting) return;
    if (state.completionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.completionFailure;
      });
      return;
    }
    // `context.pop()`, not `Navigator.pop()`: the dialog is a `go_router`
    // page (ADR-0021), and popping it imperatively leaves the router's own
    // stack out of step with the Navigator's — which lands the caller further
    // back than the Action they were reading.
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _phase.phaseLabel;
    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Complete the $label'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (_phase.phase) {
                    'plan' => 'What will be different, and how you will know. The target belongs '
                        'here, in the plant\'s own words.',
                    'do' => 'What was actually done.',
                    'check' => 'What was measured, against what the Plan named.',
                    _ => 'Which standard now holds it, so the fix outlives the person who made it.',
                  },
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ActionPhaseCompleteDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _isCheck ? 'What was measured' : 'What was done',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_isCheck) ...[
                  const SizedBox(height: Spacing.md),
                  Text('Did it hold?', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    'Answering that it did not opens the next cycle rather than closing the '
                    'Action, and keeps this round on the record.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.sm),
                  RadioGroup<String>(
                    groupValue: _outcome,
                    // Guarded rather than nulled out: `RadioGroup.onChanged` is
                    // not nullable, and the tiles below are disabled anyway
                    // while a completion is in flight.
                    onChanged: (outcome) {
                      if (_awaiting) return;
                      setState(() => _outcome = outcome);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in actionCheckOutcomeLabels.entries)
                          RadioListTile<String>(
                            key: ActionPhaseCompleteDialog.outcomeOptionKey(entry.key),
                            value: entry.key,
                            title: Text(entry.value),
                            enabled: !_awaiting,
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: ActionPhaseCompleteDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: ActionPhaseCompleteDialog.cancelKey,
            onPressed: _awaiting ? null : () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ActionPhaseCompleteDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text('Complete the $label'),
          ),
        ],
      ),
    );
  }
}
