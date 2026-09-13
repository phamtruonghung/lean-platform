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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'downtime_bloc.dart';
import 'downtime_event.dart';

class DowntimeCloseDialog extends StatefulWidget {
  const DowntimeCloseDialog({super.key, required this.downtimeEvent});

  /// The stop being closed.
  final DowntimeEvent downtimeEvent;

  static const ValueKey<String> endedAtKey = ValueKey<String>('downtime-close-ended-at');
  static const ValueKey<String> submitKey = ValueKey<String>('downtime-close-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('downtime-close-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('downtime-close-failure');

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
    final theme = Theme.of(context);
    return BlocListener<DowntimeBloc, DowntimeState>(
      listener: _onDowntimeChanged,
      child: AlertDialog(
        title: Text('Close the stop for ${widget.downtimeEvent.assetName}?'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'The machine is running again. The server records how long it was down.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                AppDateTimeField(
                  key: DowntimeCloseDialog.endedAtKey,
                  name: 'downtime-close-ended-at',
                  label: 'Ended at (optional)',
                  helperText: 'Leave blank to record now.',
                  value: _endedAt,
                  optional: true,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _endedAt = value),
                ),
                if (_failure != null)
                  Padding(
                    key: DowntimeCloseDialog.failureKey,
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
            key: DowntimeCloseDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it open'),
          ),
          FilledButton(
            key: DowntimeCloseDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Close this stop'),
          ),
        ],
      ),
    );
  }
}
