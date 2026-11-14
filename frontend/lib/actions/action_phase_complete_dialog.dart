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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'action.dart';
import 'action_detail_bloc.dart';
import '../l10n/vocabulary.dart';

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
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => AppDialog(
          key: notLoadedKey,
          title: l10n.commonThatActionCouldNotBeRead,
          description: message,
          size: AppDialogSize.decision,
          actions: [
            AppDialogAction(
              id: 'close',
              label: l10n.commonBack,
              kind: AppDialogActionKind.dismiss,
              onPressed: () => context.pop(),
            ),
          ],
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
    final l10n = AppLocalizations.of(context);
    final waitingOn = action.openPhase;
    return AppDialog(
      key: notOpenKey,
      title: l10n.actionPhaseCompleteThatIsNotTheOpenPhase,
      description: waitingOn == null
          ? l10n.actionPhaseCompleteThisActionHasNoOpenPhaseLeft
          : l10n.actionPhaseCompleteThisActionIsWaitingOnItsPhase(waitingOn.phaseLabel(l10n).toLowerCase(), actionPhaseLabel(l10n, phase).toLowerCase()),
      size: AppDialogSize.decision,
      actions: [
        AppDialogAction(
          id: 'close',
          label: l10n.routerBackToAction,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}

class ActionPhaseCompleteDialog extends StatefulWidget {
  const ActionPhaseCompleteDialog({super.key, required this.action});

  final Action action;

  static const ValueKey<String> noteKey = ValueKey<String>('action-phase-note');
  static const ValueKey<String> outcomeKey = ValueKey<String>('action-phase-outcome');
  static final ValueKey<String> submitKey = AppDialog.actionKey('complete');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('cancel');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = _phase.phaseLabel(l10n);
    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.actionPhaseCompleteCompleteThe(label),
        // A short form with a radio pair on a Check (issue #398's four widths).
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => context.pop(),
          ),
          AppDialogAction(
            id: 'complete',
            label: l10n.actionPhaseCompleteCompleteThe(label),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                switch (_phase.phase) {
                  'plan' => l10n.actionPhaseCompletePlanProse,
                  'do' => l10n.actionPhaseCompleteDoProse,
                  'check' => l10n.actionPhaseCompleteCheckProse,
                  _ => l10n.actionPhaseCompleteActProse,
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
                  labelText: _isCheck ? l10n.actionPhaseCompleteWhatWasMeasured : l10n.actionPhaseCompleteWhatWasDone,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_isCheck) ...[
                const SizedBox(height: Spacing.md),
                Text(l10n.actionPhaseCompleteDidItHold, style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xxs),
                Text(
                  l10n.actionPhaseCompleteAnsweringThatItDidNotOpensThe,
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
                      for (final (outcome, label) in actionCheckOutcomeChoices(l10n))
                        RadioListTile<String>(
                          key: ActionPhaseCompleteDialog.outcomeOptionKey(outcome),
                          value: outcome,
                          title: Text(label),
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
    );
  }
}
