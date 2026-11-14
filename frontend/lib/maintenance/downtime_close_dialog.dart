/// Closing a still-open Downtime event (issue #73).
///
/// Closing is the honest end of a stop: the server stamps `ended_at` and the
/// generated duration and status resolve from it. [endedAt] is optional — left
/// blank the server records now(), which is what closing a stop as it ends
/// means. Nothing here computes a duration from the two timestamps; that is
/// the server's fact (CONTEXT.md's Downtime).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
///
/// The form width (520): one sentence and one optional date-time field. It is not
/// the decision width (420), which is for a question with no fields; the field
/// and its helper line want the room, and the 480 this used to set inside an
/// `AlertDialog`'s content left the title and the action row at a width the
/// platform chose. Closing is the honest end of a stop, not a destruction, so the
/// act is a primary action, not a destructive one.
///
/// A dismiss that is disabled while the request is in flight stays disabled, and
/// so does `Esc` then: `AppDialog` runs the dismiss action, which does nothing
/// while it is null. The `AlertDialog` this replaces let `Esc` pop the route
/// mid-request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_date_time_field.dart';
import 'downtime_bloc.dart';
import 'downtime_event.dart';
import '../widgets/notice_text.dart';

class DowntimeCloseDialog extends StatefulWidget {
  const DowntimeCloseDialog({super.key, required this.downtimeEvent});

  /// The stop being closed.
  final DowntimeEvent downtimeEvent;

  static const ValueKey<String> endedAtKey = ValueKey<String>('downtime-close-ended-at');
  static const ValueKey<String> failureKey = ValueKey<String>('downtime-close-failure');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'downtime-close-submit';
  static const String _dismissId = 'downtime-close-dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);

  @override
  State<DowntimeCloseDialog> createState() => _DowntimeCloseDialogState();
}

class _DowntimeCloseDialogState extends State<DowntimeCloseDialog> {
  /// Null means the server records now().
  DateTime? _endedAt;

  bool _awaiting = false;
  String? _failure;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<DowntimeBloc>().add(
      DowntimeCloseConfirmed(downtimeEventId: widget.downtimeEvent.id, endedAt: _endedAt),
    );
  }

  void _onDowntimeChanged(BuildContext context, DowntimeState state) {
    if (!_awaiting || state is! DowntimeLoaded || state.isActing) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return BlocListener<DowntimeBloc, DowntimeState>(
      listener: _onDowntimeChanged,
      child: AppDialog(
        title: l10n.downtimeCloseCloseTheStopFor(widget.downtimeEvent.assetName),
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: DowntimeCloseDialog._dismissId,
            label: l10n.commonKeepItOpen,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: DowntimeCloseDialog._submitId,
            label: l10n.downtimeCloseCloseThisStop,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.downtimeCloseTheMachineIsRunningAgainTheServer,
              style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            AppDateTimeField(
              key: DowntimeCloseDialog.endedAtKey,
              name: 'downtime-close-ended-at',
              label: l10n.downtimeCloseEndedAtOptional,
              helperText: l10n.commonLeaveBlankToRecordNow,
              value: _endedAt,
              optional: true,
              enabled: !_awaiting,
              onChanged: (value) => setState(() => _endedAt = value),
            ),
            if (_failure != null)
              Padding(
                key: DowntimeCloseDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
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
