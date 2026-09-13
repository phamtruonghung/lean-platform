/// Receiving stock into a store (issue #80): `POST
/// /api/maintenance/stores/:storeId/receipts`. The part is chosen from the
/// catalogue — a value with a known set, never typed (ADR-0023) — and the
/// server is the one that refuses a movement that would take the shelf below
/// zero, reporting its part-naming message back through the Bloc so the dialog
/// stays open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'part.dart';
import 'store_stock_bloc.dart';

class ReceiveDialog extends StatefulWidget {
  const ReceiveDialog({super.key, required this.parts});

  /// The catalogue the part is chosen from. Empty is impossible to submit:
  /// the dialog only opens from a Screen that loaded it non-empty.
  final List<Part> parts;

  static const ValueKey<String> partKey = ValueKey<String>('receive-part');
  static const ValueKey<String> quantityKey = ValueKey<String>('receive-quantity');
  static const ValueKey<String> reasonKey = ValueKey<String>('receive-reason');
  static const ValueKey<String> submitKey = ValueKey<String>('receive-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('receive-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('receive-failure');

  /// Opens the form over the store's stock. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<StoreStockBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly.
  static Future<void> open(BuildContext context, {required List<Part> parts}) {
    final bloc = context.read<StoreStockBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<StoreStockBloc>.value(
        value: bloc,
        child: ReceiveDialog(parts: parts),
      ),
    );
  }

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  String? _partId;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  num? get _parsedQuantity {
    final value = num.tryParse(_quantity.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  bool get _complete => _partId != null && _parsedQuantity != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<StoreStockBloc>().add(
          StockReceiveConfirmed(
            partId: _partId!,
            quantity: _parsedQuantity!,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          ),
        );
  }

  void _onChanged(BuildContext context, StoreStockState state) {
    if (!_awaiting || state is! StoreStockLoaded || state.isReceiving) return;
    if (state.receiveFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.receiveFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<StoreStockBloc, StoreStockState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Receive stock'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ReceiveDialog.partKey,
                  initialValue: _partId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Part', border: OutlineInputBorder()),
                  items: [
                    for (final part in widget.parts)
                      DropdownMenuItem<String>(
                        value: part.id,
                        child: Text(
                          '${part.partNo} · ${part.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _partId = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ReceiveDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ReceiveDialog.reasonKey,
                  controller: _reason,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: ReceiveDialog.failureKey,
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
            key: ReceiveDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ReceiveDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Receiving…' : 'Receive'),
          ),
        ],
      ),
    );
  }
}
