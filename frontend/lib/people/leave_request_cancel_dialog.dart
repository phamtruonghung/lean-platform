/// Cancelling a leave request (issue #265): a confirmation, nothing to fill
/// in. Reached at `/leave-requests/:id/cancel` (ADR-0021). A refusal is shown
/// in the dialog, which stays open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'leave_request.dart';
import 'leave_requests_bloc.dart';

class LeaveRequestCancelDialog extends StatefulWidget {
  const LeaveRequestCancelDialog({super.key, required this.request});

  final LeaveRequest request;

  static const ValueKey<String> loadingKey = ValueKey<String>('leave-cancel-loading');
  static const ValueKey<String> notFoundKey = ValueKey<String>('leave-cancel-not-found');
  static const ValueKey<String> submitKey = ValueKey<String>('leave-cancel-submit');
  static const ValueKey<String> backKey = ValueKey<String>('leave-cancel-back');
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
    final theme = Theme.of(context);
    final request = widget.request;
    return BlocListener<LeaveRequestsBloc, LeaveRequestsState>(
      listener: _onStateChanged,
      child: AlertDialog(
        title: const Text('Cancel leave request'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cancel the ${request.leaveTypeName} request for ${request.employee.displayName}, '
                '${request.periodLabel} (${request.daysLabel})?',
                style: theme.textTheme.bodyMedium,
              ),
              if (_failure != null)
                Padding(
                  key: LeaveRequestCancelDialog.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: LeaveRequestCancelDialog.backKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep request'),
          ),
          FilledButton(
            key: LeaveRequestCancelDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Cancelling…' : 'Cancel request'),
          ),
        ],
      ),
    );
  }
}
