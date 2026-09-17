/// Increasing the affected quantity (issue #205): sorting found more of the
/// suspect product than the first count, and the number on the record has to
/// grow with it.
///
/// Addressed rather than popped — `/non-conformances/:id/quantity` (ADR-0021)
/// — so a refresh lands on the record with this control open, and the dialog
/// lives beside the detail Screen rather than over the register.
///
/// The form offers only a *greater* number and the Bloc refuses to send
/// anything else, because the record's rule is one-way in this slice: an
/// increase is a bigger containment, and a decrease would silently un-say a
/// figure that has already gone onto a label, into an email and onto the
/// customer's own paperwork. The API refuses a decrease with a 409 whatever
/// this dialog does, and a lowering is a Quality-authority decision (ADR-0035)
/// that issue #206 owns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceQuantityDialog extends StatefulWidget {
  const NonconformanceQuantityDialog({super.key, required this.nonconformance});

  /// The record as the detail Screen is reading it: what the current quantity
  /// is, and the unit it is counted in.
  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey = ValueKey<String>('nonconformance-quantity-loading');
  static const ValueKey<String> quantityKey = ValueKey<String>('nonconformance-quantity-value');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-quantity-note');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-quantity-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-quantity-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-quantity-failure');

  @override
  State<NonconformanceQuantityDialog> createState() => _NonconformanceQuantityDialogState();
}

class _NonconformanceQuantityDialogState extends State<NonconformanceQuantityDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedQuantity {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// Greater than what the record holds, and nothing else — the same test the
  /// Bloc makes before sending, so the button is disabled rather than the
  /// request refused.
  bool get _complete {
    final value = _parsedQuantity;
    return value != null && value > widget.nonconformance.quantityAffected && !_awaiting;
  }

  void _submit() {
    final value = _parsedQuantity;
    if (!_complete || value == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceQuantityIncreased(quantity: value, note: note.isEmpty ? null : note),
        );
  }

  /// Whether this dialog has already finished — a second pop would take the
  /// detail's own page off the stack behind it.
  bool _done = false;

  void _onDetailChanged(BuildContext context, NonconformanceDetailState state) {
    if (_done || !_awaiting || state is! NonconformanceDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      // The refusal stays in the dialog with the value still in it.
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
    final unit = widget.nonconformance.uomCode;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Increase the affected quantity'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.nonconformance.issueNo} currently covers '
                  '${_number(widget.nonconformance.quantityAffected)} $unit. It can only grow.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceQuantityDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'New affected quantity',
                    helperText: 'More than ${_number(widget.nonconformance.quantityAffected)} '
                        '$unit, or nothing at all.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceQuantityDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    helperText: 'Why it changed — "sorting the bin found eight more".',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceQuantityDialog.failureKey,
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
            key: NonconformanceQuantityDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceQuantityDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Increase it'),
          ),
        ],
      ),
    );
  }
}

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
