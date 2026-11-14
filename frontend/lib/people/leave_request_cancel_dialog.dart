/// Cancelling a leave request (issue #265): a confirmation, nothing to fill
/// in. Reached at `/leave-requests/:id/cancel` (ADR-0021). A refusal is shown
/// in the dialog, which stays open.
///
/// **Its shell is `AppDialog` at the `decision` width** (issue #393,
/// `docs/design-language.md` section 11): one question, its answer in a
/// sentence, two actions and no fields — the row of the table this dialog
/// answers, at the width it already chose for itself. The sentence is the
/// shell's `description` rather than a block of content, so the question and
/// what it is about share one left edge. What did not change: the wording, the
/// key the failure keeps, the enable conditions, what Cancel request sends, and
/// that the dialog pops itself once the Bloc reports success. `Esc` now runs
/// Keep request rather than popping blindly past the callback the caller owns,
/// and the two action `Key`s are the shell's (`app-dialog-action-back` /
/// `app-dialog-action-submit`) — the accessors below are unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_dialog.dart';
import 'leave_request.dart';
import 'leave_requests_bloc.dart';

class LeaveRequestCancelDialog extends StatefulWidget {
  const LeaveRequestCancelDialog({super.key, required this.request});

  final LeaveRequest request;

  static const ValueKey<String> loadingKey = ValueKey<String>('leave-cancel-loading');
  static const ValueKey<String> notFoundKey = ValueKey<String>('leave-cancel-not-found');
  static final ValueKey<String> submitKey = AppDialog.actionKey('submit');
  static final ValueKey<String> backKey = AppDialog.actionKey('back');
  static const ValueKey<String> failureKey = ValueKey<String>('leave-cancel-failure');

  @override
  State<LeaveRequestCancelDialog> createState() => _LeaveRequestCancelDialogState();
}

class _LeaveRequestCancelDialogState extends State<LeaveRequestCancelDialog> {
  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<LeaveRequestsBloc>().add(LeaveRequestCancelled(widget.request.id));
  }

  void _onStateChanged(BuildContext context, LeaveRequestsState state) {
    if (!_awaiting || state is! LeaveRequestsLoaded || state.isMutating) return;
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
    final request = widget.request;
    return BlocListener<LeaveRequestsBloc, LeaveRequestsState>(
      listener: _onStateChanged,
      child: AppDialog(
        title: l10n.leaveRequestCancelCancelLeaveRequest,
        description: l10n.leaveRequestCancelCancelTheRequestFor(request.leaveTypeName,
            request.employee.displayName, request.periodLabel, request.daysLabel),
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: 'back',
            label: l10n.leaveRequestCancelKeepRequest,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'submit',
            label: _awaiting ? l10n.leaveRequestCancelCancelling : l10n.commonCancelRequest,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: _failure == null
            ? null
            : Text(
                _failure!,
                key: LeaveRequestCancelDialog.failureKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
      ),
    );
  }
}
