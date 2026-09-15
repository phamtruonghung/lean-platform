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

import '../theme.dart';
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
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => AlertDialog(
          key: alreadyEndedKey,
          title: const Text('That Action could not be read'),
          content: Text(message),
          actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back'))],
        ),
      ActionDetailLoaded(action: final action) => action.status == 'done' || action.status == 'cancelled'
          ? AlertDialog(
              key: alreadyEndedKey,
              title: const Text('That Action has ended'),
              content: Text(
                action.status == 'done'
                    ? 'It is closed, so there is nothing left to call off.'
                    : 'It was already cancelled.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to the Action'),
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
  static const ValueKey<String> submitKey = ValueKey<String>('action-cancel-submit');
  static const ValueKey<String> backKey = ValueKey<String>('action-cancel-back');
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
    final theme = Theme.of(context);
    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Call off ${widget.action.actionNo}?'),
        content: SizedBox(
          width: 520,
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
                  'Calling it off ends the record without claiming anything was done about it. '
                  'The row stays, with the reason you give it.',
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
                  decoration: const InputDecoration(
                    labelText: 'Why (optional)',
                    helperText: 'Raised in error, a duplicate, overtaken by events.',
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
        actions: [
          TextButton(
            key: ActionCancelDialog.backKey,
            onPressed: _awaiting ? null : () => context.pop(),
            child: const Text('Leave it alone'),
          ),
          FilledButton(
            key: ActionCancelDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Call it off'),
          ),
        ],
      ),
    );
  }
}
