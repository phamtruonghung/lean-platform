/// Recording a supplier NCR (issue #215): which Supplier, which lot, how much of
/// what came in wrong, and where it was found.
///
/// Every value with a known set is **chosen, never typed** (ADR-0023): the
/// Supplier, the Product and the Defect code come from the catalogues
/// `SupplierNcrsBloc` read with the register, so this dialog issues no request
/// for them at all; the unit of measure comes from Maintenance's own list
/// (`fetchUnitsOfMeasure`); the Org Unit comes from the shared tree chooser; and
/// the day the Supplier is given is a date, not free text.
///
/// **The Supplier and the quantity are what an NCR is**, so the submit button
/// stays shut until both are there — and so is the unit of measure, because the
/// baseline's quantity column has to be in a unit the plant uses and a lot that
/// names no Product has none to inherit. The Product, the Defect code, the lot
/// reference, the purchase reference and the due day are optional: an inspector
/// has a pallet in front of them, and what it is destined for may not be known
/// yet (supplier-ncrs.js's own header).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import 'supplier_ncrs_bloc.dart';

class SupplierNcrFormDialog extends StatefulWidget {
  const SupplierNcrFormDialog({super.key, required this.siteId});

  /// The Site the register is showing — the Org Unit chooser opens on it, and
  /// it is the address the record goes to.
  final String siteId;

  static const ValueKey<String> supplierKey = ValueKey<String>('supplier-ncr-form-supplier');
  static const ValueKey<String> productKey = ValueKey<String>('supplier-ncr-form-product');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('supplier-ncr-form-defect-code');
  static const ValueKey<String> quantityKey = ValueKey<String>('supplier-ncr-form-quantity');
  static const ValueKey<String> uomKey = ValueKey<String>('supplier-ncr-form-uom');
  static const ValueKey<String> lotKey = ValueKey<String>('supplier-ncr-form-lot');
  static const ValueKey<String> purchaseKey = ValueKey<String>('supplier-ncr-form-purchase');
  static const ValueKey<String> responseDueKey = ValueKey<String>('supplier-ncr-form-response-due');
  static const ValueKey<String> descriptionKey = ValueKey<String>('supplier-ncr-form-description');
  static const ValueKey<String> chosenOrgUnitKey = ValueKey<String>('supplier-ncr-form-org-unit');
  static const ValueKey<String> submitKey = ValueKey<String>('supplier-ncr-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('supplier-ncr-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-form-failure');

  @override
  State<SupplierNcrFormDialog> createState() => _SupplierNcrFormDialogState();
}

class _SupplierNcrFormDialogState extends State<SupplierNcrFormDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _lot = TextEditingController();
  final TextEditingController _purchase = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String? _supplierId;
  String? _productId;
  String? _defectCodeId;
  String? _uomCode;
  String? _responseDueDate;

  OrgUnitNode? _orgUnit;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _lot.dispose();
    _purchase.dispose();
    _description.dispose();
    super.dispose();
  }

  num? get _quantityValue {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  bool get _complete {
    final quantity = _quantityValue;
    return _supplierId != null &&
        quantity != null &&
        quantity > 0 &&
        _uomCode != null &&
        _orgUnit != null;
  }

  /// Choosing a Product fills the unit with the one the Product is measured in
  /// — the server's own rule when both are sent — and the caller may still
  /// name another unit the plant uses.
  void _chooseProduct(BuildContext context, String? productId) {
    setState(() {
      _productId = productId;
      if (productId != null) {
        final state = context.read<SupplierNcrsBloc>().state;
        if (state is SupplierNcrsLoaded) {
          for (final product in state.products) {
            if (product.id == productId) _uomCode = product.uomCode;
          }
        }
      }
    });
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SupplierNcrsBloc>().add(
          SupplierNcrRecordConfirmed(
            orgUnitId: _orgUnit!.id,
            supplierId: _supplierId!,
            quantity: _quantityValue!,
            uomCode: _uomCode!,
            productId: _productId,
            defectCodeId: _defectCodeId,
            incomingLotRef: _lot.text.trim(),
            purchaseRef: _purchase.text.trim(),
            description: _description.text.trim(),
            responseDueDate: _responseDueDate,
          ),
        );
  }

  void _onSupplierNcrsChanged(BuildContext context, SupplierNcrsState state) {
    if (!_awaiting || state is! SupplierNcrsLoaded || state.isRecording) return;
    if (state.recordFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.recordFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<SupplierNcrsBloc>().state;
    final loaded = state is SupplierNcrsLoaded ? state : null;

    return BlocListener<SupplierNcrsBloc, SupplierNcrsState>(
      listener: _onSupplierNcrsChanged,
      child: AlertDialog(
        title: const Text('Record a supplier NCR'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: SupplierNcrFormDialog.supplierKey,
                  initialValue: _supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final supplier in loaded?.suppliers ?? const [])
                      DropdownMenuItem<String>(
                        value: supplier.id,
                        child: Text(supplier.summary, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _supplierId = value),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String?>(
                  key: SupplierNcrFormDialog.productKey,
                  initialValue: _productId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Product (optional)',
                    helperText: 'What the lot is, when that is known. A Non-conformance recorded '
                        'from this NCR needs one.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not named yet')),
                    for (final product in loaded?.products ?? const [])
                      DropdownMenuItem<String?>(
                        value: product.id,
                        child: Text('${product.name} · ${product.code}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => _chooseProduct(context, value),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String?>(
                  key: SupplierNcrFormDialog.defectCodeKey,
                  initialValue: _defectCodeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Defect code (optional)',
                    helperText: 'What is wrong with it. A Non-conformance recorded from this NCR '
                        'carries it.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not known yet')),
                    for (final code in loaded?.defectCodes ?? const [])
                      DropdownMenuItem<String?>(
                        value: code.id,
                        child: Text('${code.name} · ${code.code}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _defectCodeId = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrFormDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantity affected',
                    helperText: 'How much came in wrong.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String?>(
                  key: SupplierNcrFormDialog.uomKey,
                  initialValue: _uomCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Unit of measure',
                    helperText: 'What the quantity is counted in. Taken from the Product when one '
                        'is named.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final unit in loaded?.unitsOfMeasure ?? const <UnitOfMeasure>[])
                      DropdownMenuItem<String?>(
                        value: unit.code,
                        child: Text(unit.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _uomCode = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrFormDialog.lotKey,
                  controller: _lot,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Incoming lot reference (optional)',
                    helperText: 'The lot the delivery note says.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrFormDialog.purchaseKey,
                  controller: _purchase,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Purchase reference (optional)',
                    helperText: 'The order it arrived against.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppDateField(
                  key: SupplierNcrFormDialog.responseDueKey,
                  name: 'supplier-ncr-response-due',
                  label: 'Answer due (optional)',
                  helperText: 'The day the Supplier was given to answer.',
                  value: _responseDueDate,
                  optional: true,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _responseDueDate = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrFormDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'What is wrong with it (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                OrgUnitChooser(
                  selectedId: _orgUnit?.id,
                  enabled: !_awaiting,
                  showSitePicker: false,
                  title: 'Who works it',
                  description: 'Choose the Org Unit that will work this supplier NCR. This is '
                      'what decides who may act on it.',
                  onSelected: (node) => setState(() => _orgUnit = node),
                ),
                if (_orgUnit != null)
                  Padding(
                    key: SupplierNcrFormDialog.chosenOrgUnitKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      'This supplier NCR will be filed at ${_orgUnit!.name}.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (_failure != null)
                  Padding(
                    key: SupplierNcrFormDialog.failureKey,
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
            key: SupplierNcrFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SupplierNcrFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Record it'),
          ),
        ],
      ),
    );
  }
}
