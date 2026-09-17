/// Closing a complaint with the response the customer was given (issue #214).
///
/// The note is the whole point of the dialog and the service refuses a
/// complaint closed without one (400) — a complaint that ends with nothing said
/// back to the customer is the failure this record exists to make visible. So
/// the submit button stays shut until something is written, and a refusal that
/// still comes back (a complaint somebody else closed first, a 409) is shown
/// beside the button with the caller's text still in the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';

class ComplaintRespondDialog extends StatefulWidget {
  const ComplaintRespondDialog({super.key, required this.complaint});

  final CustomerComplaint complaint;

  static const ValueKey<String> noteKey = ValueKey<String>('complaint-respond-note');
  static const ValueKey<String> loadingKey = ValueKey<String>('complaint-respond-loading');
  static const ValueKey<String> submitKey = ValueKey<String>('complaint-respond-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('complaint-respond-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-respond-failure');

  @override
  State<ComplaintRespondDialog> createState() => _ComplaintRespondDialogState();
}

class _ComplaintRespondDialogState extends State<ComplaintRespondDialog> {
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_note.text.trim().isEmpty || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ComplaintDetailBloc>().add(
          ComplaintRespondConfirmed(
            id: widget.complaint.id,
            responseNote: _note.text.trim(),
          ),
        );
  }

  void _onDetailChanged(BuildContext context, ComplaintDetailState state) {
    if (!_awaiting || state is! ComplaintDetailLoaded || state.isMutating) return;
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
    return BlocListener<ComplaintDetailBloc, ComplaintDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Answer the customer'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'What was said back to ${widget.complaint.customerName} about '
                  '${widget.complaint.complaintNo}. This closes the complaint.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ComplaintRespondDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'The response',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: ComplaintRespondDialog.failureKey,
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
          // `DialogPage` is not barrier-dismissible, so a dialog that refuses
          // its own request still needs a way out of its own.
          TextButton(
            key: ComplaintRespondDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ComplaintRespondDialog.submitKey,
            onPressed: _note.text.trim().isEmpty || _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Closing…' : 'Close the complaint'),
          ),
        ],
      ),
    );
  }
}
