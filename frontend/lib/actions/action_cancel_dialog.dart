/// Calling an Action off (issue #179).
///
/// Addressed rather than popped — `${Routes.actions}/:id/cancel` (ADR-0021) —
/// so the address survives a refresh, and the host refuses it for an Action
/// that has already ended.
///
/// The reason is optional and the form says so: cancelling withdraws a claim
/// rather than making one, and demanding prose to undo a mistake is friction a
/// plant does not need. What the refusal *is* worth reading is the one that
/// arrives instead: an Action whose measures are still open cannot be called
/// off, and the dialog stays open with that sentence in it.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

/// The address's own guard: an Action that has already ended is not offered a
/// cancel form, and says so rather than silently opening one the server would
/// refuse.
class ActionCancelDialogHost extends StatelessWidget {
  const ActionCancelDialogHost({super.key});

  static const ValueKey<String> loadingKey = ValueKey<String>('action-cancel-loading');
  static const ValueKey<String> alreadyEndedKey = ValueKey<String>('action-cancel-ended');

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
          key: alreadyEndedKey,
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
      ActionDetailLoaded(action: final action) => action.status == 'done' || action.status == 'cancelled'
          ? AppDialog(
              key: alreadyEndedKey,
              title: l10n.commonThatActionHasEnded,
              description: action.status == l10n.commonDone
                  ? l10n.actionCancelItIsClosedSoThereIsNothing
                  : l10n.actionCancelItWasAlreadyCancelled,
              size: AppDialogSize.decision,
              actions: [
                AppDialogAction(
                  id: 'close',
                  label: l10n.routerBackToAction,
                  kind: AppDialogActionKind.dismiss,
                  onPressed: () => context.pop(),
                ),
              ],
            )
          : ActionCancelDialog(action: action),
    };
  }
}

class ActionCancelDialog extends StatefulWidget {
  const ActionCancelDialog({super.key, required this.action});

  final Action action;

  static const ValueKey<String> reasonKey = ValueKey<String>('action-cancel-reason');
  static final ValueKey<String> submitKey = AppDialog.actionKey('call-it-off');
  static final ValueKey<String> backKey = AppDialog.actionKey('leave-alone');
  static const ValueKey<String> failureKey = ValueKey<String>('action-cancel-failure');

  @override
  State<ActionCancelDialog> createState() => _ActionCancelDialogState();
}

class _ActionCancelDialogState extends State<ActionCancelDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final reason = _reason.text.trim();
    context.read<ActionDetailBloc>().add(
          ActionCancellationRequested(
            actionId: widget.action.id,
            reason: reason.isEmpty ? null : reason,
          ),
        );
  }

  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (!_awaiting || state is! ActionDetailLoaded || state.isCancelling) return;
    if (state.cancellationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.cancellationFailure;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.actionCancelCallOff(widget.action.actionNo),
        // A short form: one optional field (issue #398's four widths).
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'leave-alone',
            label: l10n.actionCancelLeaveItAlone,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => context.pop(),
          ),
          // Destructive: the record ends and the server keeps no way back, so
          // the button that does it is the danger colour and sits apart from
          // the way out rather than first.
          AppDialogAction(
            id: 'call-it-off',
            label: l10n.actionCancelCallItOff,
            kind: AppDialogActionKind.destructive,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.action.title,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.actionCancelCallingItOffEndsTheRecordWithout,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: ActionCancelDialog.reasonKey,
                controller: _reason,
                enabled: !_awaiting,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.actionCancelWhyOptional,
                  helperText: l10n.actionCancelRaisedInErrorADuplicateOvertakenBy,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_failure != null)
                Padding(
                  key: ActionCancelDialog.failureKey,
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
