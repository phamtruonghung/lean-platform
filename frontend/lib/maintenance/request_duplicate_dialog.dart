/// Marking a Request as a duplicate of another, naming the Request that
/// survives (issue #72, ADR-0014's own `duplicate_of_id`).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'request.dart';
import 'requests_bloc.dart';

class RequestDuplicateDialog extends StatefulWidget {
  const RequestDuplicateDialog({super.key, required this.request, required this.candidates});

  /// The Request being marked a duplicate.
  final Request request;

  /// The Requests that could survive it — the other open Requests in the
  /// triage queue. A Request cannot be a duplicate of itself, so [request] is
  /// never among these (the server refuses that with a 400).
  final List<Request> candidates;

  static ValueKey<String> candidateKey(String id) =>
      ValueKey<String>('request-duplicate-candidate-$id');
  static const ValueKey<String> submitKey = ValueKey<String>('request-duplicate-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('request-duplicate-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('request-duplicate-failure');
  static const ValueKey<String> noneKey = ValueKey<String>('request-duplicate-none');

  @override
  State<RequestDuplicateDialog> createState() => _RequestDuplicateDialogState();
}

class _RequestDuplicateDialogState extends State<RequestDuplicateDialog> {
  String? _duplicateOfId;
  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_duplicateOfId == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<RequestsBloc>().add(
          RequestDuplicateConfirmed(
            requestId: widget.request.id,
            duplicateOfId: _duplicateOfId!,
          ),
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
        title: const Text('Mark as a duplicate'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: widget.candidates.isEmpty
              ? Center(
                  key: RequestDuplicateDialog.noneKey,
                  child: Text(
                    'There is no other open Request for this one to duplicate.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Which Request survives? ${widget.request.requestNo} leaves the queue.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Expanded(
                      child: RadioGroup<String>(
                        groupValue: _duplicateOfId,
                        onChanged: (id) {
                          if (!_awaiting && id != null) setState(() => _duplicateOfId = id);
                        },
                        child: ListView.separated(
                          itemCount: widget.candidates.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final candidate = widget.candidates[index];
                            return RadioListTile<String>(
                              key: RequestDuplicateDialog.candidateKey(candidate.id),
                              value: candidate.id,
                              enabled: !_awaiting,
                              title: Text(candidate.summary),
                              subtitle: Text('${candidate.requestNo} · ${candidate.assetName}'),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          if (_failure != null)
            Padding(
              key: RequestDuplicateDialog.failureKey,
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Text(
                _failure!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          TextButton(
            key: RequestDuplicateDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it separate'),
          ),
          FilledButton(
            key: RequestDuplicateDialog.submitKey,
            onPressed: _duplicateOfId != null && !_awaiting ? _submit : null,
            child: const Text('Mark duplicate'),
          ),
        ],
      ),
    );
  }
}
