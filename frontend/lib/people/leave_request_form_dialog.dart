/// Asking for leave (issue #265): a leave type chosen from the requestable
/// absence reasons, a first and last day chosen from date pickers, and an
/// optional note. Nothing here is typed but the note (AGENTS.md §7,
/// ADR-0023): when the leave types cannot be read the dialog shows
/// `FailureState` with a retry and the submit button stays shut rather than
/// falling back to free text.
///
/// Reached at `/leave-requests/new` (ADR-0021). A refusal (a clash, an
/// Account with no Employee behind it) is shown beside the button with what
/// the caller chose still in place.
///
/// **Its shell is `AppDialog` at the `form` width** (issue #393,
/// `docs/design-language.md` section 11): a leave type, two dates and a note is
/// the shape the `form` row names, so the dialog is 520 rather than the 420 it
/// drew for itself. What did not change: every field, key, label and enable
/// condition, the dates' own pickers, the inline failure, the leave types'
/// `FailureState` with its retry (which is the dialog's whole content when the
/// catalogue cannot be read), and that Request leave stays shut until the three
/// choices are made. `Esc` now runs Cancel rather than popping blindly past the
/// callback the caller owns, and the two action `Key`s are the shell's
/// (`app-dialog-action-cancel` / `app-dialog-action-submit`) — the accessors
/// below are unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import '../widgets/failure_state.dart';
import 'leave_requests_bloc.dart';

class LeaveRequestFormDialog extends StatefulWidget {
  const LeaveRequestFormDialog({super.key});

  static const ValueKey<String> loadingKey = ValueKey<String>('leave-request-form-loading');
  static const ValueKey<String> typeFieldKey = ValueKey<String>('leave-request-type');
  static const String startsOnName = 'leave-request-starts-on';
  static const String endsOnName = 'leave-request-ends-on';
  static const ValueKey<String> noteKey = ValueKey<String>('leave-request-note');
  static final ValueKey<String> submitKey = AppDialog.actionKey('submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('leave-request-failure');
  static const ValueKey<String> typesFailedKey = ValueKey<String>('leave-request-types-failed');
  static const ValueKey<String> typesRetryKey = ValueKey<String>('leave-request-types-retry');

  @override
  State<LeaveRequestFormDialog> createState() => _LeaveRequestFormDialogState();
}

class _LeaveRequestFormDialogState extends State<LeaveRequestFormDialog> {
  final TextEditingController _note = TextEditingController();
  String? _typeId;
  String? _startsOn;
  String? _endsOn;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _complete => _typeId != null && _startsOn != null && _endsOn != null;

  void _submit() {
    if (_awaiting || !_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    context.read<LeaveRequestsBloc>().add(
          LeaveRequestSubmitted(
            absenceReasonId: _typeId!,
            startsOn: _startsOn!,
            endsOn: _endsOn!,
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<LeaveRequestsBloc>().state;
    final loaded = state is LeaveRequestsLoaded ? state : null;
    final typesFailure = loaded?.leaveTypesFailure;
    final types = loaded?.leaveTypes ?? const [];
    return BlocListener<LeaveRequestsBloc, LeaveRequestsState>(
      listener: _onStateChanged,
      child: AppDialog(
        title: l10n.commonRequestLeave,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'submit',
            label: _awaiting ? l10n.leaveRequestFormRequesting : l10n.commonRequestLeave,
            onPressed: _awaiting || !_complete || typesFailure != null ? null : _submit,
          ),
        ],
        child: typesFailure != null
            ? PlatformFailureState(
                key: LeaveRequestFormDialog.typesFailedKey,
                title: l10n.leaveRequestFormLeaveTypesCouldNotBeRead,
                message: typesFailure,
                retryKey: LeaveRequestFormDialog.typesRetryKey,
                onRetry: () => context.read<LeaveRequestsBloc>().add(const LeaveTypesRequested()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: LeaveRequestFormDialog.typeFieldKey,
                    initialValue: _typeId,
                    decoration: InputDecoration(labelText: l10n.leaveRequestFormLeaveType),
                    items: [
                      for (final type in types)
                        DropdownMenuItem(value: type.id, child: Text(type.name)),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _typeId = value),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateField(
                    name: LeaveRequestFormDialog.startsOnName,
                    label: l10n.leaveRequestFormFirstDay,
                    value: _startsOn,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _startsOn = value),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateField(
                    name: LeaveRequestFormDialog.endsOnName,
                    label: l10n.leaveRequestFormLastDay,
                    value: _endsOn,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _endsOn = value),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: LeaveRequestFormDialog.noteKey,
                    controller: _note,
                    enabled: !_awaiting,
                    decoration: InputDecoration(labelText: l10n.commonNoteOptional),
                  ),
                  if (_failure != null)
                    Padding(
                      key: LeaveRequestFormDialog.failureKey,
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Text(
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
