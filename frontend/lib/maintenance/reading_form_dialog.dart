/// Recording a reading against a meter (issue #79): the number on the
/// counter, an optional note, and — on a cumulative meter — whether this is an
/// explicit rollover or replacement rather than an ordinary reading.
///
/// CONTEXT.md's PM schedule entry is the point: the reading is what the
/// schedule comes due on, and a cumulative counter that resets makes
/// accumulated use ambiguous unless the reset is said out loud (ADR-0029).
/// The dialog never lets a lower reading pass silently: on a cumulative meter
/// the "counter was reset" choice is the only way a smaller number is offered,
/// and the server refuses one that goes down without it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'meter.dart';
import 'meters_bloc.dart';

class ReadingFormDialog extends StatefulWidget {
  const ReadingFormDialog({super.key, required this.meter});

  final AssetMeter meter;

  static const ValueKey<String> readingKey = ValueKey<String>('reading-form-reading');
  static const ValueKey<String> noteKey = ValueKey<String>('reading-form-note');
  static const ValueKey<String> rolloverKey = ValueKey<String>('reading-form-rollover');
  static const ValueKey<String> submitKey = ValueKey<String>('reading-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('reading-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('reading-form-failure');

  static Future<void> open(BuildContext context, {required AssetMeter meter}) {
    final bloc = context.read<MetersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<MetersBloc>.value(
        value: bloc,
        child: ReadingFormDialog(meter: meter),
      ),
    );
  }

  @override
  State<ReadingFormDialog> createState() => _ReadingFormDialogState();
}

class _ReadingFormDialogState extends State<ReadingFormDialog> {
  final TextEditingController _reading = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _rollover = false;
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _reading.dispose();
    _note.dispose();
    super.dispose();
  }

  num? get _readingValue => num.tryParse(_reading.text.trim());

  bool get _complete => _readingValue != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<MetersBloc>().add(
          MeterReadingConfirmed(
            meterId: widget.meter.id,
            reading: _readingValue!,
            isRollover: widget.meter.isCumulative && _rollover,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        );
  }

  void _onMetersChanged(BuildContext context, MetersState state) {
    if (!_awaiting || state is! MetersLoaded || state.isMutating) return;
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
    final meter = widget.meter;
    final isRollover = meter.isCumulative && _rollover;
    return BlocListener<MetersBloc, MetersState>(
      listener: _onMetersChanged,
      child: AlertDialog(
        title: Text('Record a reading on ${meter.name}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${meter.assetName} (${meter.assetCode}) · ${meter.code}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Accumulated use so far: ${meter.accumulatedLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ReadingFormDialog.readingKey,
                  controller: _reading,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: isRollover
                        ? 'What the new counter reads now'
                        : 'What the counter reads',
                    helperText: isRollover
                        ? 'The accumulated use is carried forward into the offset; the new counter usually reads 0.'
                        : 'In ${meter.uomCode}, exactly as the counter shows.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ReadingFormDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (meter.isCumulative) ...[
                  const SizedBox(height: Spacing.xs),
                  CheckboxListTile(
                    key: ReadingFormDialog.rolloverKey,
                    value: _rollover,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _awaiting ? null : (value) => setState(() => _rollover = value ?? false),
                    title: const Text('The counter was reset or replaced'),
                    subtitle: const Text(
                      'Carries the accumulated use into the offset and records this as the new counter\'s start.',
                    ),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: ReadingFormDialog.failureKey,
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
            key: ReadingFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ReadingFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (isRollover ? 'Record rollover' : 'Record reading')),
          ),
        ],
      ),
    );
  }
}
