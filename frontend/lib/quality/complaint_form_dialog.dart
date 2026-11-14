/// Recording a customer complaint (issue #214): what the customer said, about
/// which Product, filed at the Org Unit that will answer it.
///
/// Every value with a known set is **chosen, never typed** (ADR-0023): the
/// Customer, the Product and the Defect code come from the catalogues
/// `ComplaintsBloc` read with the register, so this dialog issues no request for
/// them at all; the Org Unit comes from the shared tree chooser; and the
/// response due day is a date, not free text. The Customer and the Product are
/// what a complaint is — the submit button stays shut until both are named —
/// and the Defect code, the quantity and the due day are optional, because a
/// customer can ring up without knowing any of them.
///
/// The quantity is measured in the Product's own unit, which is why there is no
/// unit field here: the server takes the Product's unit unless the caller names
/// another, and a person writing down what a customer said is not choosing a
/// unit of measure.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import 'complaints_bloc.dart';

class ComplaintFormDialog extends StatefulWidget {
  const ComplaintFormDialog({super.key, required this.siteId});

  /// The Site the register is showing — the Org Unit chooser opens on it, and
  /// it is the address the record goes to.
  final String siteId;

  static const ValueKey<String> customerKey = ValueKey<String>('complaint-form-customer');
  static const ValueKey<String> productKey = ValueKey<String>('complaint-form-product');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('complaint-form-defect-code');
  static const ValueKey<String> quantityKey = ValueKey<String>('complaint-form-quantity');
  static const ValueKey<String> responseDueKey = ValueKey<String>('complaint-form-response-due');
  static const ValueKey<String> warrantyKey = ValueKey<String>('complaint-form-warranty');
  static const ValueKey<String> descriptionKey = ValueKey<String>('complaint-form-description');
  static const ValueKey<String> chosenOrgUnitKey = ValueKey<String>('complaint-form-org-unit');
  static final ValueKey<String> submitKey = AppDialog.actionKey('complaint-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('complaint-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-form-failure');

  @override
  State<ComplaintFormDialog> createState() => _ComplaintFormDialogState();
}

class _ComplaintFormDialogState extends State<ComplaintFormDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String? _customerId;
  String? _productId;
  String? _defectCodeId;
  String? _responseDueDate;
  bool _isWarranty = false;

  OrgUnitNode? _orgUnit;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _complete =>
      _customerId != null &&
      _productId != null &&
      _orgUnit != null &&
      _description.text.trim().isNotEmpty;

  num? get _quantityValue {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ComplaintsBloc>().add(
          ComplaintRecordConfirmed(
            orgUnitId: _orgUnit!.id,
            customerId: _customerId!,
            productId: _productId!,
            description: _description.text.trim(),
            defectCodeId: _defectCodeId,
            quantity: _quantityValue,
            responseDueDate: _responseDueDate,
            isWarranty: _isWarranty,
          ),
        );
  }

  void _onComplaintsChanged(BuildContext context, ComplaintsState state) {
    if (!_awaiting || state is! ComplaintsLoaded || state.isRecording) return;
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
    final state = context.watch<ComplaintsBloc>().state;
    final loaded = state is ComplaintsLoaded ? state : null;

    return BlocListener<ComplaintsBloc, ComplaintsState>(
      listener: _onComplaintsChanged,
      child: AppDialog(
        title: l10n.complaintFormRecordACustomerComplaint,
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: 'complaint-form-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'complaint-form-submit',
            label: _awaiting ? l10n.commonSaving : l10n.nonconformanceFormRecord,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ComplaintFormDialog.customerKey,
              initialValue: _customerId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.complaintFormCustomer,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final customer in loaded?.customers ?? const [])
                  DropdownMenuItem<String>(
                    value: customer.id,
                    child: Text(customer.summary, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _awaiting ? null : (value) => setState(() => _customerId = value),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              key: ComplaintFormDialog.productKey,
              initialValue: _productId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonProduct,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final product in loaded?.products ?? const [])
                  DropdownMenuItem<String>(
                    value: product.id,
                    child: Text('${product.name} · ${product.code}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _awaiting ? null : (value) => setState(() => _productId = value),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String?>(
              key: ComplaintFormDialog.defectCodeKey,
              initialValue: _defectCodeId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonDefectCodeOptional,
                helperText: l10n.complaintFormWhatTheCustomerSaysIsWrongA,
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l10n.commonNotKnownYet)),
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
              key: ComplaintFormDialog.quantityKey,
              controller: _quantity,
              enabled: !_awaiting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.complaintFormQuantityOptional,
                helperText: l10n.complaintFormInTheProductSOwnUnitOf,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            AppDateField(
              key: ComplaintFormDialog.responseDueKey,
              name: 'complaint-response-due',
              label: l10n.complaintFormResponseDueOptional,
              helperText: l10n.complaintFormTheDayTheCustomerWasPromisedAn,
              value: _responseDueDate,
              optional: true,
              enabled: !_awaiting,
              onChanged: (value) => setState(() => _responseDueDate = value),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: ComplaintFormDialog.descriptionKey,
              controller: _description,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.complaintFormWhatTheCustomerSaid,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              key: ComplaintFormDialog.warrantyKey,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commonWarrantyClaim),
              value: _isWarranty,
              onChanged: _awaiting ? null : (value) => setState(() => _isWarranty = value),
            ),
            const SizedBox(height: Spacing.lg),
            OrgUnitChooser(
              selectedId: _orgUnit?.id,
              enabled: !_awaiting,
              showSitePicker: false,
              title: l10n.complaintFormWhoAnswersIt,
              description: l10n.complaintFormChooseTheOrgUnitThatWillAnswer,
              onSelected: (node) => setState(() => _orgUnit = node),
            ),
            if (_orgUnit != null)
              Padding(
                key: ComplaintFormDialog.chosenOrgUnitKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  l10n.complaintFormThisComplaintWillBeFiledAt(_orgUnit!.name),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (_failure != null)
              Padding(
                key: ComplaintFormDialog.failureKey,
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
