/// A reason, asked for before a record is changed (issue #588, ADR-0068,
/// slice 6): cancelling an Attempt and allowing a retake each keep the person's
/// words with the record, so the dialog will not close on fewer than three
/// characters (after trimming) and will not take more than 2000. The server
/// holds the same bounds; this is the courtesy of saying so before the request.
///
/// **It owns no request.** It pops the trimmed reason and the caller decides
/// what to send, so the refusal of a write (someone else got there first) is
/// shown on the Screen the person is looking at, not inside a dialog already
/// gone. Its shell is `AppDialog` at the `form` width, as the leave decision
/// dialog's is.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_dialog.dart';

class AssessmentReasonDialog extends StatefulWidget {
  const AssessmentReasonDialog({
    super.key,
    required this.title,
    required this.description,
    required this.label,
    required this.confirmLabel,
  });

  /// The shortest and longest reason the server accepts, trimmed.
  static const int minLength = 3;
  static const int maxLength = 2000;

  final String title;
  final String description;
  final String label;
  final String confirmLabel;

  static const ValueKey<String> fieldKey = ValueKey<String>('assessment-reason-field');
  static final ValueKey<String> submitKey = AppDialog.actionKey('submit');
  static final ValueKey<String> backKey = AppDialog.actionKey('back');

  /// Opens the dialog; completes with the trimmed reason, or null when the
  /// person went back.
  static Future<String?> open(
    BuildContext context, {
    required String title,
    required String description,
    required String label,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AssessmentReasonDialog(
        title: title,
        description: description,
        label: label,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<AssessmentReasonDialog> createState() => _AssessmentReasonDialogState();
}

class _AssessmentReasonDialogState extends State<AssessmentReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _tooShort = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.length < AssessmentReasonDialog.minLength) {
      setState(() => _tooShort = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: widget.title,
      description: widget.description,
      size: AppDialogSize.form,
      actions: [
        AppDialogAction(
          id: 'back',
          label: l10n.commonBack,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'submit',
          label: widget.confirmLabel,
          onPressed: _submit,
        ),
      ],
      child: TextField(
        key: AssessmentReasonDialog.fieldKey,
        controller: _reason,
        minLines: 2,
        maxLines: 5,
        maxLength: AssessmentReasonDialog.maxLength,
        onChanged: (_) {
          if (_tooShort) setState(() => _tooShort = false);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: l10n.assessmentReasonHelper,
          errorText: _tooShort ? l10n.assessmentReasonTooShort : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
