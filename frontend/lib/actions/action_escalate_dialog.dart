/// Handing an Action up the tree (issue #180).
///
/// Addressed rather than popped — `${Routes.actions}/:id/escalate` (ADR-0021) —
/// so the address survives a refresh and an Action that has already ended is
/// refused by the route rather than by a form the caller has to fill in first.
///
/// The list of Org Units comes from the server, not from the client's idea of
/// the tree: what counts as "above" is the Site's own hierarchy, and a client
/// that walked it would be a second implementation of that rule. An empty list
/// is a real answer — the Action already sits at the top — and it says so
/// rather than showing an empty picker.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

class ActionEscalateDialogHost extends StatefulWidget {
  const ActionEscalateDialogHost({super.key});

  static const ValueKey<String> loadingKey = ValueKey<String>('action-escalate-loading');
  static const ValueKey<String> endedKey = ValueKey<String>('action-escalate-ended');
  static const ValueKey<String> nowhereKey = ValueKey<String>('action-escalate-nowhere');

  @override
  State<ActionEscalateDialogHost> createState() => _ActionEscalateDialogHostState();
}

class _ActionEscalateDialogHostState extends State<ActionEscalateDialogHost> {
  @override
  void initState() {
    super.initState();
    // Asked once, from the address rather than from a button: the list is what
    // this dialog *is*, and a caller who arrives by URL gets the same thing.
    final state = context.read<ActionDetailBloc>().state;
    if (state is ActionDetailLoaded &&
        state.action.status != 'done' &&
        state.action.status != 'cancelled') {
      context.read<ActionDetailBloc>().add(
            ActionEscalationTargetsRequested(actionId: state.action.id),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: ActionEscalateDialogHost.loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => AlertDialog(
          key: ActionEscalateDialogHost.endedKey,
          title: const Text('That Action could not be read'),
          content: Text(message),
          actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back'))],
        ),
      ActionDetailLoaded(action: final action) => switch (action.status) {
          'done' || 'cancelled' => AlertDialog(
              key: ActionEscalateDialogHost.endedKey,
              title: const Text('That Action has ended'),
              content: Text(
                action.status == 'done'
                    ? 'It is closed. Whoever needed to know about it was told before it was.'
                    : 'It was called off, so there is nothing to hand up.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to the Action'),
                ),
              ],
            ),
          _ when state.isLoadingEscalationTargets => const AlertDialog(
              key: ActionEscalateDialogHost.loadingKey,
              content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            ),
          // A failure to read the targets is about the list, not about the
          // Action: it is said here, in the dialog that wanted it.
          _ when state.escalationFailure != null && state.escalationTargets.isEmpty =>
            AlertDialog(
              key: ActionEscalateDialogHost.endedKey,
              title: const Text('Nowhere to hand it up to'),
              content: Text(state.escalationFailure!),
              actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back'))],
            ),
          _ when state.escalationTargets.isEmpty => AlertDialog(
              key: ActionEscalateDialogHost.nowhereKey,
              title: const Text('There is nobody above this'),
              content: Text(
                '${action.actionNo} sits at ${action.orgUnitName}, which is already the top of '
                'this Site. Nothing above it can be told.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to the Action'),
                ),
              ],
            ),
          _ => ActionEscalateDialog(action: action, targets: state.escalationTargets),
        },
    };
  }
}

class ActionEscalateDialog extends StatefulWidget {
  const ActionEscalateDialog({super.key, required this.action, required this.targets});

  final Action action;
  final List<EscalationTarget> targets;

  static const ValueKey<String> submitKey = ValueKey<String>('action-escalate-submit');
  static const ValueKey<String> backKey = ValueKey<String>('action-escalate-back');
  static const ValueKey<String> failureKey = ValueKey<String>('action-escalate-failure');

  static ValueKey<String> targetKey(String id) => ValueKey<String>('action-escalate-target-$id');

  @override
  State<ActionEscalateDialog> createState() => _ActionEscalateDialogState();
}

class _ActionEscalateDialogState extends State<ActionEscalateDialog> {
  String? _targetId;
  bool _awaiting = false;
  String? _failure;

  void _submit() {
    final targetId = _targetId;
    if (_awaiting || targetId == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ActionDetailBloc>().add(
          ActionEscalationRequested(actionId: widget.action.id, orgUnitId: targetId),
        );
  }

  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (!_awaiting || state is! ActionDetailLoaded || state.isEscalating) return;
    if (state.escalationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.escalationFailure;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Nearest first, as the server ordered them: the Org Unit that already
    // holds the work is the one the caller usually means.
    final recommended = widget.targets.first;

    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Hand ${widget.action.actionNo} up'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.action.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Raising this tells the Org Unit you choose. It stays where it is and keeps its '
                  'owner and its cycle — this asks somebody above to know about it, not to take it '
                  'over.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                RadioGroup<String>(
                  groupValue: _targetId,
                  onChanged: _awaiting
                      ? (_) {}
                      : (value) => setState(() => _targetId = value),
                  child: Column(
                    children: [
                      for (final target in widget.targets)
                        RadioListTile<String>(
                          key: ActionEscalateDialog.targetKey(target.id),
                          value: target.id,
                          title: Text(target.name),
                          subtitle: Text(
                            target.id == recommended.id
                                ? '${target.code} · nearest above it'
                                : target.code,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: ActionEscalateDialog.failureKey,
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
            key: ActionEscalateDialog.backKey,
            onPressed: _awaiting ? null : () => context.pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: ActionEscalateDialog.submitKey,
            onPressed: _awaiting || _targetId == null ? null : _submit,
            child: const Text('Hand it up'),
          ),
        ],
      ),
    );
  }
}
