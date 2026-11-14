/// Recording a supplier NCR (issue #215): which Supplier, which lot, how much of
/// what came in wrong, and where it was found.
///
/// Every value with a known set is **chosen, never typed** (ADR-0023): the
/// Supplier, the Product and the Defect code come from the catalogues
/// `SupplierNcrsBloc` read with the register, so this dialog issues no request
/// for them at all; the unit of measure comes from Maintenance's own list
/// (`fetchUnitsOfMeasure`); the Org Unit comes from the shared tree chooser; and
/// the day the Supplier is given is a date, not free text. The Defect code is a
/// search box over that catalogue rather than a menu, because it is the field a
/// person reads off the arriving pallet: a dropdown has no text buffer, so a
/// reader's burst cannot reach it, while a search field commits an exact code
/// as a pick (`app_search_field.dart`).
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

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import 'defect_code.dart';
import 'supplier_ncrs_bloc.dart';

class SupplierNcrFormDialog extends StatefulWidget {
  const SupplierNcrFormDialog({super.key, required this.siteId});

  /// The Site the register is showing — the Org Unit chooser opens on it, and
  /// it is the address the record goes to.
  final String siteId;

  static const ValueKey<String> supplierKey = ValueKey<String>('supplier-ncr-form-supplier');
  static const ValueKey<String> productKey = ValueKey<String>('supplier-ncr-form-product');
  static const ValueKey<String> quantityKey = ValueKey<String>('supplier-ncr-form-quantity');
  static const ValueKey<String> uomKey = ValueKey<String>('supplier-ncr-form-uom');
  static const ValueKey<String> lotKey = ValueKey<String>('supplier-ncr-form-lot');
  static const ValueKey<String> purchaseKey = ValueKey<String>('supplier-ncr-form-purchase');
  static const ValueKey<String> responseDueKey = ValueKey<String>('supplier-ncr-form-response-due');
  static const ValueKey<String> descriptionKey = ValueKey<String>('supplier-ncr-form-description');
  static const ValueKey<String> chosenOrgUnitKey = ValueKey<String>('supplier-ncr-form-org-unit');
  static final ValueKey<String> submitKey = AppDialog.actionKey('supplier-ncr-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('supplier-ncr-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-form-failure');

  /// The Defect code picker's own name and the two `Key`s it seeds — the field
  /// a test types or scans into, and each suggestion row it taps.
  static const String defectCodeFieldName = 'supplier-ncr-form-defect-code';

  static ValueKey<String> defectCodeFieldKey() => AppSearchField.fieldKey(defectCodeFieldName);

  static ValueKey<String> defectCodeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(defectCodeFieldName, id);

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

  /// The Defect code this NCR names, or `null` — optional here, as it was when
  /// the field was a menu: an inspector has a pallet in front of them, and what
  /// is wrong with it may not be coded yet. Clearing the field's own text clears
  /// it back to nothing named.
  DefectCode? _defectCode;
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
            defectCodeId: _defectCode?.id,
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<SupplierNcrsBloc>().state;
    final loaded = state is SupplierNcrsLoaded ? state : null;

    return BlocListener<SupplierNcrsBloc, SupplierNcrsState>(
      listener: _onSupplierNcrsChanged,
      child: AppDialog(
        title: l10n.commonRecordASupplierNcr,
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: 'supplier-ncr-form-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'supplier-ncr-form-submit',
            label: _awaiting ? l10n.commonSaving : l10n.nonconformanceFormRecord,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: SupplierNcrFormDialog.supplierKey,
              initialValue: _supplierId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonSupplier,
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
              decoration: InputDecoration(
                labelText: l10n.supplierNcrFormProductOptional,
                helperText: l10n.supplierNcrFormWhatTheLotIsWhenThatIs,
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l10n.supplierNcrFormNotNamedYet)),
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
            AppSearchField<DefectCode>(
              name: SupplierNcrFormDialog.defectCodeFieldName,
              label: l10n.commonDefectCodeOptional,
              helperText: l10n.supplierNcrFormWhatIsWrongWithItANon,
              value: _defectCode,
              enabled: !_awaiting,
              onChanged: (code) => setState(() => _defectCode = code),
              onSelected: (code) => setState(() => _defectCode = code),
              // A dumb in-memory filter over the catalogue the register already
              // read: typing issues no request (ADR-0023). Matched on the two
              // fields that identify a Defect code: its code and its name.
              fetchSuggestions: (term) async {
                final lower = term.toLowerCase();
                return [
                  for (final code in loaded?.defectCodes ?? const <DefectCode>[])
                    if (code.code.toLowerCase().contains(lower) ||
                        code.name.toLowerCase().contains(lower))
                      code,
                ];
              },
              suggestionBuilder: (context, code) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                child: Text('${code.name} · ${code.code}', overflow: TextOverflow.ellipsis),
              ),
              idOf: (code) => code.id,
              displayStringFor: (code) => '${code.name} · ${code.code}',
              codeOf: (code) => code.code,
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SupplierNcrFormDialog.quantityKey,
              controller: _quantity,
              enabled: !_awaiting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.nonconformanceDetailQuantityAffected,
                helperText: l10n.supplierNcrFormHowMuchCameInWrong,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String?>(
              key: SupplierNcrFormDialog.uomKey,
              initialValue: _uomCode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonUnitOfMeasure,
                helperText: l10n.supplierNcrFormWhatTheQuantityIsCountedInTaken,
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
              decoration: InputDecoration(
                labelText: l10n.supplierNcrFormIncomingLotReferenceOptional,
                helperText: l10n.supplierNcrFormTheLotTheDeliveryNoteSays,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SupplierNcrFormDialog.purchaseKey,
              controller: _purchase,
              enabled: !_awaiting,
              decoration: InputDecoration(
                labelText: l10n.supplierNcrFormPurchaseReferenceOptional,
                helperText: l10n.supplierNcrFormTheOrderItArrivedAgainst,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            AppDateField(
              key: SupplierNcrFormDialog.responseDueKey,
              name: 'supplier-ncr-response-due',
              label: l10n.supplierNcrFormAnswerDueOptional,
              helperText: l10n.supplierNcrFormTheDayTheSupplierWasGivenTo,
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
              decoration: InputDecoration(
                labelText: l10n.supplierNcrFormWhatIsWrongWithItOptional,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            OrgUnitChooser(
              selectedId: _orgUnit?.id,
              enabled: !_awaiting,
              showSitePicker: false,
              title: l10n.supplierNcrFormWhoWorksIt,
              description: l10n.supplierNcrFormChooseTheOrgUnitThatWillWork,
              onSelected: (node) => setState(() => _orgUnit = node),
            ),
            if (_orgUnit != null)
              Padding(
                key: SupplierNcrFormDialog.chosenOrgUnitKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  l10n.supplierNcrFormThisSupplierNcrWillBeFiledAt(_orgUnit!.name),
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
    );
  }
}
