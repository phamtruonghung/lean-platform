/// Recording a Disposition (issue #206): some of the product dealt with as
/// scrap, as rework, or returned to the supplier.
///
/// Addressed rather than popped — `/non-conformances/:id/disposition`
/// (ADR-0021) — so a refresh lands on the record with this control open, the
/// same choice the quantity dialog makes beside it.
///
/// **The quantity is bounded by what is still undecided**, which is what the
/// API refuses with a 409 and what this form refuses before sending anything:
/// product is dealt with in parts as it is sorted, so a Disposition covers
/// some of what is left and never more. The rework minutes are asked for only
/// where the kind is rework, because the API refuses them on anything else —
/// a value with a known set is chosen, never typed (ADR-0023), and a field
/// that cannot apply to the choice is not shown at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceDispositionDialog extends StatefulWidget {
  const NonconformanceDispositionDialog({super.key, required this.nonconformance});

  /// The record as the detail Screen is reading it: how much is still
  /// undecided, and the unit it is counted in.
  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-disposition-loading');
  static const ValueKey<String> kindKey = ValueKey<String>('nonconformance-disposition-kind');
  static const ValueKey<String> quantityKey =
      ValueKey<String>('nonconformance-disposition-quantity');
  static const ValueKey<String> minutesKey =
      ValueKey<String>('nonconformance-disposition-minutes');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-disposition-note');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-disposition-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-disposition-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-disposition-failure');

  @override
  State<NonconformanceDispositionDialog> createState() =>
      _NonconformanceDispositionDialogState();
}

class _NonconformanceDispositionDialogState extends State<NonconformanceDispositionDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _minutes = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _kind = DispositionType.scrap;
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _undecided => widget.nonconformance.undispositionedQuantity;

  double? get _parsedQuantity {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// Whole, positive and no more than what is left — the three things the API
  /// would refuse, checked here so the button is disabled rather than the
  /// request refused.
  bool get _quantityFits {
    final value = _parsedQuantity;
    return value != null && value > 0 && value <= _undecided;
  }

  bool get _minutesFit {
    if (_kind != DispositionType.rework) return true;
    final text = _minutes.text.trim();
    if (text.isEmpty) return false;
    final minutes = double.tryParse(text);
    return minutes != null && minutes >= 0;
  }

  bool get _complete => _quantityFits && _minutesFit && !_awaiting;

  void _submit() {
    final value = _parsedQuantity;
    if (!_complete || value == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    final minutes = _kind == DispositionType.rework ? double.parse(_minutes.text.trim()) : null;
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceDispositionRecorded(
            dispositionType: _kind,
            quantity: value,
            reworkMinutes: minutes,
            note: note.isEmpty ? null : note,
          ),
        );
  }

  /// Whether this dialog has already finished — a second pop would take the
  /// detail's own page off the stack behind it.
  bool _done = false;

  void _onDetailChanged(BuildContext context, NonconformanceDetailState state) {
    if (_done || !_awaiting || state is! NonconformanceDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.nonconformance;
    final unit = record.uomCode;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Record a Disposition'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${record.issueNo} has ${_number(_undecided)} $unit still undecided. Deal with '
                  'some of it here.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: NonconformanceDispositionDialog.kindKey,
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Disposition',
                    helperText: 'Scrap, rework, or back to the supplier.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final kind in DispositionType.choices)
                      DropdownMenuItem<String>(
                        value: kind,
                        child: Text(DispositionType.label(kind)),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _kind = value ?? _kind),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceDispositionDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    helperText: 'At most ${_number(_undecided)} $unit.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_kind == DispositionType.rework) ...[
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: NonconformanceDispositionDialog.minutesKey,
                    controller: _minutes,
                    enabled: !_awaiting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Rework minutes',
                      helperText: 'How long the rework took, for cost of poor quality.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceDispositionDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    helperText: 'What was done with it.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceDispositionDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: NonconformanceDispositionDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceDispositionDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Record it'),
          ),
        ],
      ),
    );
  }
}

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
