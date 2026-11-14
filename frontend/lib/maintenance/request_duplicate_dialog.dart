/// Marking a Request as a duplicate of another, naming the Request that
/// survives (issue #72, ADR-0014's own `duplicate_of_id`).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
///
/// The picker width (460): a list of the other open Requests to choose one from.
/// The shell's content area is the one scroller, so the list is a plain column of
/// radio rows (each at least 44px tall) that scrolls with the dialog, and the
/// failure line sits in the content where it can be read, not among the buttons.
/// Marking a duplicate takes the Request out of the queue but deletes nothing, so
/// the act is a primary action. Submit stays disabled until a Request is chosen.
///
/// While a request is in flight the dismiss is disabled, as it always was, and so
/// is `Esc`: `AppDialog` runs the dismiss action, which does nothing while it is
/// null. The `AlertDialog` this replaces let `Esc` pop the route mid-request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'request.dart';
import 'requests_bloc.dart';
import '../widgets/notice_text.dart';

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

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'request-duplicate-submit';
  static const String _dismissId = 'request-duplicate-dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);
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
      RequestDuplicateConfirmed(requestId: widget.request.id, duplicateOfId: _duplicateOfId!),
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
    final dense = AppTypography.dense(context);
    return BlocListener<RequestsBloc, RequestsState>(
      listener: _onRequestsChanged,
      child: AppDialog(
        title: l10n.requestDuplicateTitle,
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: RequestDuplicateDialog._dismissId,
            label: l10n.requestDuplicateDismiss,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: RequestDuplicateDialog._submitId,
            label: l10n.requestsMarkDuplicate,
            onPressed: _duplicateOfId != null && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.candidates.isEmpty)
              Center(
                key: RequestDuplicateDialog.noneKey,
                child: Text(
                  l10n.requestDuplicateNone,
                  textAlign: TextAlign.center,
                  style: dense?.copyWith(color: palette.textPrimary),
                ),
              )
            else ...[
              Text(
                l10n.requestDuplicateWhich(widget.request.requestNo),
                style: dense?.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              RadioGroup<String>(
                groupValue: _duplicateOfId,
                onChanged: (id) {
                  if (!_awaiting && id != null) setState(() => _duplicateOfId = id);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < widget.candidates.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      RadioListTile<String>(
                        key: RequestDuplicateDialog.candidateKey(widget.candidates[index].id),
                        value: widget.candidates[index].id,
                        enabled: !_awaiting,
                        title: Text(widget.candidates[index].summary),
                        subtitle: Text(
                          '${widget.candidates[index].requestNo} · '
                          '${widget.candidates[index].assetName}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_failure != null)
              Padding(
                key: RequestDuplicateDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(_failure!, style: dense?.copyWith(color: palette.statusDanger)),
              ),
          ],
        ),
      ),
    );
  }
}
