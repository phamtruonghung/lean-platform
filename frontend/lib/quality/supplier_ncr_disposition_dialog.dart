/// Recording the Supplier's disposition and what was recovered (issue #215) —
/// the commercial half of an incoming non-conformance.
///
/// The disposition is the plant's own answer for the material and comes from
/// the baseline's five (ADR-0023: a value with a known set is chosen, never
/// typed), so it is a menu rather than a text box. The cost recovered is
/// optional and a real state when absent: a lot returned to the Supplier
/// recovers nothing, and an NCR whose claim is still being argued says so by
/// staying empty rather than by holding a zero.
///
/// Both are written in one act, and the refusal the service returns (a
/// disposition outside the five, a negative recovery, an NCR somebody else
/// closed first) is shown beside the button with the caller's values still on
/// screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'supplier_ncr.dart';
import 'supplier_ncr_detail_bloc.dart';
import '../widgets/notice_text.dart';
import '../l10n/vocabulary.dart';

class SupplierNcrDispositionDialog extends StatefulWidget {
  const SupplierNcrDispositionDialog({super.key, required this.supplierNcr});

  final SupplierNcr supplierNcr;

  static const ValueKey<String> dispositionKey =
      ValueKey<String>('supplier-ncr-disposition-choice');
  static const ValueKey<String> costKey = ValueKey<String>('supplier-ncr-disposition-cost');
  static const ValueKey<String> currencyKey =
      ValueKey<String>('supplier-ncr-disposition-currency');
  static const ValueKey<String> loadingKey =
      ValueKey<String>('supplier-ncr-disposition-loading');
  static final ValueKey<String> submitKey =
      AppDialog.actionKey('supplier-ncr-disposition-submit');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('supplier-ncr-disposition-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-disposition-failure');

  @override
  State<SupplierNcrDispositionDialog> createState() =>
      _SupplierNcrDispositionDialogState();
}

class _SupplierNcrDispositionDialogState extends State<SupplierNcrDispositionDialog> {
  late final TextEditingController _cost = TextEditingController(
    text: widget.supplierNcr.costRecovered == null
        ? ''
        : _plainNumber(widget.supplierNcr.costRecovered!),
  );
  late final TextEditingController _currency =
      TextEditingController(text: widget.supplierNcr.currency);

  late String _disposition = widget.supplierNcr.disposition;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _cost.dispose();
    _currency.dispose();
    super.dispose();
  }

  static String _plainNumber(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  num? get _costValue {
    final text = _cost.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  bool get _complete => _currency.text.trim().length == 3;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SupplierNcrDetailBloc>().add(
          SupplierNcrDispositionConfirmed(
            id: widget.supplierNcr.id,
            disposition: _disposition,
            costRecovered: _costValue,
            currency: _currency.text.trim(),
          ),
        );
  }

  void _onDetailChanged(BuildContext context, SupplierNcrDetailState state) {
    if (!_awaiting || state is! SupplierNcrDetailLoaded || state.isMutating) return;
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocListener<SupplierNcrDetailBloc, SupplierNcrDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.supplierNcrDispositionDecideTheMaterial,
        size: AppDialogSize.picker,
        actions: [
          // `DialogPage` is not barrier-dismissible, so a dialog that refuses
          // its own request still needs a way out of its own.
          AppDialogAction(
            id: 'supplier-ncr-disposition-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'supplier-ncr-disposition-submit',
            label: _awaiting ? l10n.commonSaving : l10n.commonRecordTheDisposition,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.supplierNcrDispositionWhatHappensToThatCameFromOn(widget.supplierNcr.quantityLabel, widget.supplierNcr.supplierName, widget.supplierNcr.ncrNo),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              key: SupplierNcrDispositionDialog.dispositionKey,
              initialValue: _disposition,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonDisposition,
                helperText: l10n.supplierNcrDispositionWhatThePlantDecidedHappensToThe,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final disposition in SupplierNcrDisposition.values)
                  DropdownMenuItem<String>(
                    value: disposition,
                    child: Text(
                      supplierNcrDispositionLabel(l10n, disposition),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged:
                  _awaiting ? null : (value) => setState(() => _disposition = value!),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SupplierNcrDispositionDialog.costKey,
              controller: _cost,
              enabled: !_awaiting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.supplierNcrDispositionCostRecoveredOptional,
                helperText: l10n.supplierNcrDispositionWhatWasClawedBackFromTheSupplier,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SupplierNcrDispositionDialog.currencyKey,
              controller: _currency,
              enabled: !_awaiting,
              maxLength: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonCurrency,
                helperText: l10n.supplierNcrDispositionThreeLettersTheCurrencyTheCostRecovered,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: SupplierNcrDispositionDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
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
