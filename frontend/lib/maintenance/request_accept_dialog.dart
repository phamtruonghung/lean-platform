/// Accepting a Request, choosing the priority of the Work order it raises
/// (issue #72).
///
/// The reporter's `urgency` is not the Work order's `priority` — they are
/// different judgements by different people (CONTEXT.md's own Request entry) —
/// so accepting asks maintenance to set the priority deliberately rather than
/// letting the server default stand silently. The picker opens on 3, the
/// schema's own default, so a caller who agrees with it submits without
/// touching it while the choice is still offered.
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
///
/// The decision width (420): one sentence and one dropdown that holds only
/// `3 - Normal` and its neighbours, so nothing needs more room. Accepting raises
/// a Work order rather than destroying anything, so the act is a primary action.
///
/// While a request is in flight the dismiss is disabled, as it always was, and so is
/// `Esc`: `AppDialog` runs the dismiss action, which does nothing while it is null.
/// The `AlertDialog` this replaces let `Esc` pop the route mid-request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'request.dart';
import 'requests_bloc.dart';

/// The word next to each priority level, indexed `level - 1` — 1 is the CHECK
/// constraint's most urgent end, 5 its least, made visible at the point of
/// choosing rather than left as a bare digit whose direction is not obvious.
/// The same labelling `WorkOrderFormDialog` offers when a Work order is raised
/// directly.
List<String> _priorityLabels(AppLocalizations l10n) => [
      l10n.commonPriorityMostUrgent,
      l10n.commonPriorityUrgent,
      l10n.commonPriorityNormal,
      l10n.commonPriorityLow,
      l10n.commonPriorityLeastUrgent,
    ];

class RequestAcceptDialog extends StatefulWidget {
  const RequestAcceptDialog({super.key, required this.request});

  /// The Request being accepted.
  final Request request;

  static const ValueKey<String> priorityKey = ValueKey<String>('request-accept-priority');
  static const ValueKey<String> failureKey = ValueKey<String>('request-accept-failure');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'request-accept-submit';
  static const String _dismissId = 'request-accept-dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);

  @override
  State<RequestAcceptDialog> createState() => _RequestAcceptDialogState();
}

class _RequestAcceptDialogState extends State<RequestAcceptDialog> {
  /// The schema's own default, so the common case needs no interaction but the
  /// choice is still made explicitly.
  int _priority = 3;

  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<RequestsBloc>().add(
      RequestAcceptConfirmed(requestId: widget.request.id, priority: _priority),
    );
  }

  void _onRequestsChanged(BuildContext context, RequestsState state) {
    if (!_awaiting || state is! RequestsLoaded || state.isTriaging) return;
    if (state.triageFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.triageFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return BlocListener<RequestsBloc, RequestsState>(
      listener: _onRequestsChanged,
      child: AppDialog(
        title: l10n.requestAcceptTitle(widget.request.requestNo),
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: RequestAcceptDialog._dismissId,
            label: l10n.requestAcceptDismiss,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: RequestAcceptDialog._submitId,
            label: l10n.requestAcceptSubmit,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.requestAcceptBody,
              style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<int>(
              key: RequestAcceptDialog.priorityKey,
              initialValue: _priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonPriority,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (var level = 1; level <= 5; level++)
                  DropdownMenuItem<int>(
                    value: level,
                    child: Text('$level - ${_priorityLabels(l10n)[level - 1]}'),
                  ),
              ],
              onChanged: _awaiting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _priority = value);
                    },
            ),
            if (_failure != null)
              Padding(
                key: RequestAcceptDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
