/// Approving or rejecting a pending leave request (issue #265), with an
/// optional note the requester will read. Reached at
/// `/leave-requests/:id/approve` and `/leave-requests/:id/reject`
/// (ADR-0021). A refusal — someone decided first, a 409 — is shown beside the
/// button with the note still in the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'leave_request.dart';
import 'leave_requests_bloc.dart';

class LeaveRequestDecisionDialog extends StatefulWidget {
  const LeaveRequestDecisionDialog({super.key, required this.request, required this.approve});

  final LeaveRequest request;

  /// True to approve, false to reject.
  final bool approve;

  static const ValueKey<String> loadingKey = ValueKey<String>('leave-decision-loading');
  static const ValueKey<String> notFoundKey = ValueKey<String>('leave-decision-not-found');
  static const ValueKey<String> noteKey = ValueKey<String>('leave-decision-note');
  static const ValueKey<String> submitKey = ValueKey<String>('leave-decision-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('leave-decision-cancel');
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
    final theme = Theme.of(context);
    final request = widget.request;
    final verb = widget.approve ? 'Approve' : 'Reject';
    return BlocListener<LeaveRequestsBloc, LeaveRequestsState>(
      listener: _onStateChanged,
      child: AlertDialog(
        title: Text('$verb leave request'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${request.employee.displayName} · ${request.leaveTypeName} · '
                  '${request.periodLabel} (${request.daysLabel})',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: LeaveRequestDecisionDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: LeaveRequestDecisionDialog.failureKey,
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
            key: LeaveRequestDecisionDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          FilledButton(
            key: LeaveRequestDecisionDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Saving…' : verb),
          ),
        ],
      ),
    );
  }
}
