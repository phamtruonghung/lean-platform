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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'request.dart';
import 'requests_bloc.dart';

/// The word next to each priority level, indexed `level - 1` — 1 is the CHECK
/// constraint's most urgent end, 5 its least, made visible at the point of
/// choosing rather than left as a bare digit whose direction is not obvious.
/// The same labelling `WorkOrderFormDialog` offers when a Work order is raised
/// directly.
const List<String> _priorityLabels = ['Most urgent', 'Urgent', 'Normal', 'Low', 'Least urgent'];

class RequestAcceptDialog extends StatefulWidget {
  const RequestAcceptDialog({super.key, required this.request});

  /// The Request being accepted.
  final Request request;

  static const ValueKey<String> priorityKey = ValueKey<String>('request-accept-priority');
  static const ValueKey<String> submitKey = ValueKey<String>('request-accept-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('request-accept-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('request-accept-failure');

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
    final theme = Theme.of(context);
    return BlocListener<RequestsBloc, RequestsState>(
      listener: _onRequestsChanged,
      child: AlertDialog(
        title: Text('Accept ${widget.request.requestNo}?'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Accepting raises a Work order for this Request. Its priority '
                  'is your call, not the reporter\'s urgency.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<int>(
                  key: RequestAcceptDialog.priorityKey,
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var level = 1; level <= 5; level++)
                      DropdownMenuItem<int>(
                        value: level,
                        child: Text('$level - ${_priorityLabels[level - 1]}'),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) {
                    if (value != null) setState(() => _priority = value);
                  },
                ),
                if (_failure != null)
                  Padding(
                    key: RequestAcceptDialog.failureKey,
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
            key: RequestAcceptDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it waiting'),
          ),
          FilledButton(
            key: RequestAcceptDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Accept this Request'),
          ),
        ],
      ),
    );
  }
}
