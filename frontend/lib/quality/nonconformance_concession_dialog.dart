/// Granting a Concession (issue #206): accepting the product as it is, rather
/// than dealing with it.
///
/// Addressed rather than popped — `/non-conformances/:id/concession`
/// (ADR-0021). The Screen offers this address only to a caller holding Quality
/// authority at the record's Org Unit (`OrgUnitScope.canHoldQualityAt`, the
/// client's half of the server's `canAct({ quality: true })`), and the API is
/// the gate: it refuses anyone else with a 403 whatever this dialog does.
///
/// **The reference and the note are both required**, because the two things an
/// auditor asks about a Concession are what authorises it and why it was
/// granted — the deviation number, and the reason. The granting Account is not
/// a field: the API records whoever sends the request, and the record reads it
/// back as the Disposition's own `decidedByAccountName`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceConcessionDialog extends StatefulWidget {
  const NonconformanceConcessionDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-concession-loading');
  static const ValueKey<String> quantityKey =
      ValueKey<String>('nonconformance-concession-quantity');
  static const ValueKey<String> referenceKey =
      ValueKey<String>('nonconformance-concession-reference');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-concession-note');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-concession-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-concession-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-concession-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('nonconformance-concession-refused');

  @override
  State<NonconformanceConcessionDialog> createState() =>
      _NonconformanceConcessionDialogState();
}

class _NonconformanceConcessionDialogState extends State<NonconformanceConcessionDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedQuantity {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  bool get _complete {
    final value = _parsedQuantity;
    return value != null &&
        value > 0 &&
        value <= widget.nonconformance.undispositionedQuantity &&
        _reference.text.trim().isNotEmpty &&
        _note.text.trim().isNotEmpty &&
        !_awaiting;
  }

  void _submit() {
    final value = _parsedQuantity;
    if (!_complete || value == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceConcessionGranted(
            quantity: value,
            reference: _reference.text,
            note: _note.text,
          ),
        );
  }

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

    // Quality authority is read here, in a build (ADR-0035) rather than passed
    // in from the route: this address can be reached by a refresh, and a
    // decision made before `/me` answered would be a decision made on a
    // half-known Account. The server refuses either way; this says why.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AlertDialog(
        key: NonconformanceConcessionDialog.refusedKey,
        content: const Text(
          'Granting a Concession needs Quality authority at this Non-conformance\'s Org Unit.',
        ),
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Grant a Concession'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Accepting the product as it is needs Quality authority, and your name stays '
                  'on ${record.issueNo}.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceConcessionDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity accepted as it is',
                    helperText: 'At most ${_number(record.undispositionedQuantity)} $unit.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceConcessionDialog.referenceKey,
                  controller: _reference,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reference',
                    helperText: 'The deviation or approval number it is granted under.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceConcessionDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    helperText: 'Why the product is acceptable as it is.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceConcessionDialog.failureKey,
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
            key: NonconformanceConcessionDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceConcessionDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Grant it'),
          ),
        ],
      ),
    );
  }
}

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
