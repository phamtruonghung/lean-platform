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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
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
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: ActionEscalateDialogHost.loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => _EscalateRefusal(
          key: ActionEscalateDialogHost.endedKey,
          title: l10n.commonThatActionCouldNotBeRead,
          message: message,
          dismissLabel: l10n.commonBack,
        ),
      ActionDetailLoaded(action: final action) => switch (action.status) {
          'done' || 'cancelled' => _EscalateRefusal(
              key: ActionEscalateDialogHost.endedKey,
              title: l10n.commonThatActionHasEnded,
              // `action.status` is the wire token (`done`, `cancelled`), never a
              // word a person reads — comparing it to a localised label would
              // only be true in English.
              message: action.status == 'done'
                  ? l10n.actionEscalateItIsClosedWhoeverNeededToKnow
                  : l10n.actionEscalateItWasCalledOffSoThereIs,
              dismissLabel: l10n.routerBackToAction,
            ),
          _ when state.isLoadingEscalationTargets => const AlertDialog(
              key: ActionEscalateDialogHost.loadingKey,
              content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            ),
          // A failure to read the targets is about the list, not about the
          // Action: it is said here, in the dialog that wanted it.
          _ when state.escalationFailure != null && state.escalationTargets.isEmpty =>
            _EscalateRefusal(
              key: ActionEscalateDialogHost.endedKey,
              title: l10n.actionEscalateNowhereToHandItUpTo,
              message: state.escalationFailure!,
              dismissLabel: l10n.commonBack,
            ),
          _ when state.escalationTargets.isEmpty => _EscalateRefusal(
              key: ActionEscalateDialogHost.nowhereKey,
              title: l10n.actionEscalateThereIsNobodyAboveThis,
              message: l10n.actionEscalateSitsAtWhichIsAlreadyTheTop(action.actionNo, action.orgUnitName),
              dismissLabel: l10n.routerBackToAction,
            ),
          _ => ActionEscalateDialog(action: action, targets: state.escalationTargets),
        },
    };
  }
}

/// One of this address's refusals: a sentence about why there is no form, and
/// the one way back to the Action the address was reached from.
///
/// A `DialogPage` is not `barrierDismissible` (see `dialog_page.dart`), so a
/// refusal with no control of its own would leave a person tapping outside a
/// dialog that never closes.
class _EscalateRefusal extends StatelessWidget {
  const _EscalateRefusal({
    super.key,
    required this.title,
    required this.message,
    required this.dismissLabel,
  });

  final String title;
  final String message;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) => AppDialog(
        title: title,
        description: message,
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: 'close',
            label: dismissLabel,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => context.pop(),
          ),
        ],
      );
}

class ActionEscalateDialog extends StatefulWidget {
  const ActionEscalateDialog({super.key, required this.action, required this.targets});

  final Action action;
  final List<EscalationTarget> targets;

  static final ValueKey<String> submitKey = AppDialog.actionKey('hand-it-up');
  static final ValueKey<String> backKey = AppDialog.actionKey('not-now');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Nearest first, as the server ordered them: the Org Unit that already
    // holds the work is the one the caller usually means.
    final recommended = widget.targets.first;

    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.actionEscalateHandUp(widget.action.actionNo),
        // A list to choose one Org Unit from, and the sentence that says what
        // raising it does (issue #398's four widths).
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: 'not-now',
            label: l10n.employeeDepartureNotNow,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => context.pop(),
          ),
          AppDialogAction(
            id: 'hand-it-up',
            label: l10n.actionEscalateHandItUp,
            onPressed: _awaiting || _targetId == null ? null : _submit,
          ),
        ],
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.action.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                Text(
                  l10n.actionEscalateRaisingThisTellsTheOrgUnitYou,
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
                                ? l10n.actionEscalateNearestAboveIt(target.code)
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
    );
  }
}
