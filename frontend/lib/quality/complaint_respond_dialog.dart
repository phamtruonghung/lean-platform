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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';
import '../widgets/notice_text.dart';

class ComplaintRespondDialog extends StatefulWidget {
  const ComplaintRespondDialog({super.key, required this.complaint});

  final CustomerComplaint complaint;

  static const ValueKey<String> noteKey = ValueKey<String>('complaint-respond-note');
  static const ValueKey<String> loadingKey = ValueKey<String>('complaint-respond-loading');
  static final ValueKey<String> submitKey = AppDialog.actionKey('complaint-respond-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('complaint-respond-cancel');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocListener<ComplaintDetailBloc, ComplaintDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.complaintRespondAnswerTheCustomer,
        size: AppDialogSize.picker,
        actions: [
          // `DialogPage` is not barrier-dismissible, so a dialog that refuses
          // its own request still needs a way out of its own.
          AppDialogAction(
            id: 'complaint-respond-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'complaint-respond-submit',
            label: _awaiting ? l10n.complaintRespondClosing : l10n.complaintRespondCloseTheComplaint,
            onPressed: _note.text.trim().isEmpty || _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.complaintRespondWhatWasSaidBackToAboutThis(widget.complaint.customerName, widget.complaint.complaintNo),
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
              decoration: InputDecoration(
                labelText: l10n.commonTheResponse,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: ComplaintRespondDialog.failureKey,
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
