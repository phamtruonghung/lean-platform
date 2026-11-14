/// Approving or rejecting a pending leave request (issue #265), with an
/// optional note the requester will read. Reached at
/// `/leave-requests/:id/approve` and `/leave-requests/:id/reject`
/// (ADR-0021). A refusal — someone decided first, a 409 — is shown beside the
/// button with the note still in the field.
///
/// **Its shell is `AppDialog` at the `form` width** (issue #393,
/// `docs/design-language.md` section 11). It asks one question, but it asks it
/// with a field for the note, and the table's `decision` width is the one with
/// no fields; one field plus two actions is the shape `form` names, so the
/// dialog is 520 rather than the 420 it drew for itself. The request's own line
/// (who, which leave, which days) is the shell's `description`, so the question
/// and the record it is about share one left edge. What did not change: the
/// note field and its key, the failure text inside the dialog, the enable
/// conditions, what Approve/Reject sends, that the dialog pops itself once the
/// Bloc reports success, and `DialogPage`'s own route. `Esc` now runs Back
/// rather than popping blindly, and the two action `Key`s are the shell's
/// (`app-dialog-action-back` / `app-dialog-action-submit`) — the accessors
/// below are unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'leave_request.dart';
import 'leave_requests_bloc.dart';
import '../widgets/notice_text.dart';

class LeaveRequestDecisionDialog extends StatefulWidget {
  const LeaveRequestDecisionDialog({super.key, required this.request, required this.approve});

  final LeaveRequest request;

  /// True to approve, false to reject.
  final bool approve;

  static const ValueKey<String> loadingKey = ValueKey<String>('leave-decision-loading');
  static const ValueKey<String> notFoundKey = ValueKey<String>('leave-decision-not-found');
  static const ValueKey<String> noteKey = ValueKey<String>('leave-decision-note');
  static final ValueKey<String> submitKey = AppDialog.actionKey('submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('back');
  static const ValueKey<String> failureKey = ValueKey<String>('leave-decision-failure');

  @override
  State<LeaveRequestDecisionDialog> createState() => _LeaveRequestDecisionDialogState();
}

class _LeaveRequestDecisionDialogState extends State<LeaveRequestDecisionDialog> {
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    context.read<LeaveRequestsBloc>().add(
          LeaveRequestDecided(
            id: widget.request.id,
            approve: widget.approve,
            note: note.isEmpty ? null : note,
          ),
        );
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
    final verb = widget.approve ? l10n.leaveRequestsApprove : l10n.commonReject;
    return BlocListener<LeaveRequestsBloc, LeaveRequestsState>(
      listener: _onStateChanged,
      child: AppDialog(
        title: widget.approve
            ? l10n.leaveRequestDecisionApproveLeaveRequest
            : l10n.leaveRequestDecisionRejectLeaveRequest,
        description: '${request.employee.displayName} · ${request.leaveTypeName} · '
            '${request.periodLabel} (${request.daysLabel})',
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'back',
            label: l10n.commonBack,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'submit',
            label: _awaiting ? l10n.commonSaving : verb,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: LeaveRequestDecisionDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.commonNoteOptional,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: LeaveRequestDecisionDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
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
