/// Declining a Request, with a reason that is required (issue #72).
///
/// The database refuses a rejection without a reason
/// (`maintenance_requests_rejected_has_reason`), and "why was my ask refused"
/// is a fair question — so the submit button is disabled until the field says
/// something, rather than letting a caller discover the rule from a refusal.
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
///
/// The decision width (420): one question and the required reason in a text box.
/// Declining is a decision, not a destruction: the Request is kept with its reason
/// and the requester reads it on My requests, so the act is a primary action and
/// not a destructive one. Submit stays disabled until the reason says something.
///
/// While a request is in flight the dismiss is disabled, as it always was, and so is
/// `Esc`: `AppDialog` runs the dismiss action, which does nothing while it is null.
/// The `AlertDialog` this replaces let `Esc` pop the route mid-request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'request.dart';
import 'requests_bloc.dart';

class RequestDeclineDialog extends StatefulWidget {
  const RequestDeclineDialog({super.key, required this.request});

  /// The Request being declined.
  final Request request;

  static const ValueKey<String> reasonKey = ValueKey<String>('request-decline-reason');
  static const ValueKey<String> failureKey = ValueKey<String>('request-decline-failure');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'request-decline-submit';
  static const String _dismissId = 'request-decline-dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);

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
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return BlocListener<RequestsBloc, RequestsState>(
      listener: _onRequestsChanged,
      child: AppDialog(
        title: l10n.requestDeclineTitle(widget.request.requestNo),
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: RequestDeclineDialog._dismissId,
            label: l10n.requestAcceptDismiss,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: RequestDeclineDialog._submitId,
            label: l10n.requestDeclineSubmit,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
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
              decoration: InputDecoration(
                labelText: l10n.requestDeclineReason,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: RequestDeclineDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
