/// Declining a Request, with a reason that is required (issue #72).
///
/// The database refuses a rejection without a reason
/// (`maintenance_requests_rejected_has_reason`), and "why was my ask refused"
/// is a fair question — so the submit button is disabled until the field says
/// something, rather than letting a caller discover the rule from a refusal.
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'request.dart';
import 'requests_bloc.dart';

class RequestDeclineDialog extends StatefulWidget {
  const RequestDeclineDialog({super.key, required this.request});

  /// The Request being declined.
  final Request request;

  static const ValueKey<String> reasonKey = ValueKey<String>('request-decline-reason');
  static const ValueKey<String> submitKey = ValueKey<String>('request-decline-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('request-decline-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('request-decline-failure');

  @override
  State<RequestDeclineDialog> createState() => _RequestDeclineDialogState();
}

class _RequestDeclineDialogState extends State<RequestDeclineDialog> {
  final TextEditingController _reason = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _complete => _reason.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<RequestsBloc>().add(
          RequestDeclineConfirmed(requestId: widget.request.id, reason: _reason.text.trim()),
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
        title: Text('Decline ${widget.request.requestNo}?'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: RequestDeclineDialog.reasonKey,
                  controller: _reason,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Why is this being declined?',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: RequestDeclineDialog.failureKey,
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
            key: RequestDeclineDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it waiting'),
          ),
          FilledButton(
            key: RequestDeclineDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Decline this Request'),
          ),
        ],
      ),
    );
  }
}
