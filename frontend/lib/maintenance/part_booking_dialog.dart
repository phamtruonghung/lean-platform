/// Booking a part against a Work order (issue #75): how it was sourced, what
/// it was, how many and at what cost.
///
/// `sourced` decides the rest of the form. A `stores` booking names a
/// catalogue Part and the Store it came from, and the server draws that shelf
/// down in the same transaction as the cost line (ADR-0015). A `purchased`,
/// `refurbished` or `cannibalised` booking names its own description and unit
/// — `partNo` is free text on purpose, because demanding a part number the
/// technician does not have means the line is left blank and the cost is
/// lost — and touches no stock, because it never came off a shelf.
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'maintenance_api.dart';
import 'part.dart';
import 'store.dart';
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class PartBookingDialog extends StatefulWidget {
  const PartBookingDialog({super.key, required this.siteId});

  /// The Site whose stores the `stores` path can draw from — read off the
  /// Work order's own Site, not the list Bloc.
  final String siteId;

  static const ValueKey<String> sourcedKey = ValueKey<String>('part-booking-sourced');
  static const ValueKey<String> quantityKey = ValueKey<String>('part-booking-quantity');
  static const ValueKey<String> unitCostKey = ValueKey<String>('part-booking-unit-cost');
  static const ValueKey<String> partKey = ValueKey<String>('part-booking-part');
  static const ValueKey<String> storeKey = ValueKey<String>('part-booking-store');
  static const ValueKey<String> partNoKey = ValueKey<String>('part-booking-part-no');
  static const ValueKey<String> descriptionKey = ValueKey<String>('part-booking-description');
  static const ValueKey<String> uomKey = ValueKey<String>('part-booking-uom');
  static const ValueKey<String> submitKey = ValueKey<String>('part-booking-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('part-booking-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('part-booking-failure');

  @override
  State<PartBookingDialog> createState() => _PartBookingDialogState();
}

enum _OptionsStatus { loading, ready, failed }

class _PartBookingDialogState extends State<PartBookingDialog> {
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _unitCost = TextEditingController();
  final TextEditingController _partNo = TextEditingController();
  final TextEditingController _description = TextEditingController();

  _OptionsStatus _status = _OptionsStatus.loading;
  List<Part> _parts = const [];
  List<Store> _stores = const [];
  List<UnitOfMeasure> _units = const [];
  String? _optionsFailure;

  String _sourced = PartSource.stores.wire;
  String? _partId;
  String? _storeId;
  String? _uomCode;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _partNo.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _status = _OptionsStatus.loading;
      _optionsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _status = _OptionsStatus.failed;
        _optionsFailure = WorkOrderDetailBloc.signedOutMessage;
      });
      return;
    }
    final api = context.read<MaintenanceApi>();
    try {
      final parts = await api.fetchParts(token);
      final stores = await api.fetchStores(token, siteId: widget.siteId);
      final units = await api.fetchUnitsOfMeasure(token);
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _stores = stores;
        _units = units;
        _status = _OptionsStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _OptionsStatus.failed;
        _optionsFailure = error.message;
      });
    }
  }

  num? get _parsedQuantity {
    final value = num.tryParse(_quantity.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  num? get _parsedUnitCost {
    final text = _unitCost.text.trim();
    if (text.isEmpty) return null;
    final value = num.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  bool get _complete {
    if (_parsedQuantity == null) return false;
    if (_unitCost.text.trim().isNotEmpty && _parsedUnitCost == null) return false;
    if (_sourced == PartSource.stores.wire) {
      return _partId != null && _storeId != null;
    }
    return _description.text.trim().isNotEmpty && _uomCode != null;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final stores = _sourced == PartSource.stores.wire;
    final description = _description.text.trim();
    final partNo = _partNo.text.trim();
    context.read<WorkOrderDetailBloc>().add(
          WorkOrderPartBookingConfirmed(
            sourced: _sourced,
            quantity: _parsedQuantity!,
            partId: stores ? _partId : null,
            storeId: stores ? _storeId : null,
            partNo: stores || partNo.isEmpty ? null : partNo,
            description: stores || description.isEmpty ? null : description,
            uomCode: stores ? null : _uomCode,
            unitCost: _parsedUnitCost,
          ),
        );
  }

  void _onChanged(BuildContext context, WorkOrderDetailState state) {
    if (!_awaiting || state is! WorkOrderDetailLoaded || state.isBooking) return;
    if (state.bookingFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.bookingFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<WorkOrderDetailBloc, WorkOrderDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Book a part'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: PartBookingDialog.sourcedKey,
                  initialValue: _sourced,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sourced', border: OutlineInputBorder()),
                  items: [
                    for (final source in PartSource.values)
                      DropdownMenuItem<String>(value: source.wire, child: Text(source.label)),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) => setState(() => _sourced = value ?? PartSource.stores.wire),
                ),
                const SizedBox(height: Spacing.md),
                if (_status == _OptionsStatus.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_status == _OptionsStatus.failed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _optionsFailure ?? 'The options could not be read.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                      TextButton(onPressed: _awaiting ? null : _loadOptions, child: const Text('Try again')),
                    ],
                  )
                else if (_sourced == PartSource.stores.wire) ...[
                  DropdownButtonFormField<String>(
                    key: PartBookingDialog.partKey,
                    initialValue: _partId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Part', border: OutlineInputBorder()),
                    items: [
                      for (final part in _parts)
                        DropdownMenuItem<String>(
                          value: part.id,
                          child: Text(part.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _partId = value),
                  ),
                  const SizedBox(height: Spacing.md),
                  DropdownButtonFormField<String>(
                    key: PartBookingDialog.storeKey,
                    initialValue: _storeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Store', border: OutlineInputBorder()),
                    items: [
                      for (final store in _stores)
                        DropdownMenuItem<String>(
                          value: store.id,
                          child: Text(store.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _storeId = value),
                  ),
                ] else ...[
                  TextField(
                    key: PartBookingDialog.partNoKey,
                    controller: _partNo,
                    enabled: !_awaiting,
                    decoration: const InputDecoration(
                      labelText: 'Part number (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: PartBookingDialog.descriptionKey,
                    controller: _description,
                    enabled: !_awaiting,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  DropdownButtonFormField<String>(
                    key: PartBookingDialog.uomKey,
                    initialValue: _uomCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unit of measure',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final unit in _units)
                        DropdownMenuItem<String>(
                          value: unit.code,
                          child: Text('${unit.name} (${unit.code})'),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _uomCode = value),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                TextField(
                  key: PartBookingDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: PartBookingDialog.unitCostKey,
                  controller: _unitCost,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Unit cost (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: PartBookingDialog.failureKey,
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
            key: PartBookingDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: PartBookingDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Book part'),
          ),
        ],
      ),
    );
  }
}
