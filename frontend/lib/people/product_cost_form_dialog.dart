/// Adding a product standard cost, correcting one, and revising one (issue
/// #252) — the shared catalogue's own write surface (`POST`/`PATCH
/// /api/people/product-costs` and `POST /api/people/product-costs/:id/revision`,
/// administrator only).
///
/// `CostRateFormDialog`'s shape exactly, and for the same reasons — see that
/// file's own header for why one dialog serves all three acts, why Revise is
/// deliberately not the same control as Correct, and why a value with a known
/// set is chosen rather than typed (ADR-0023). Two differences, both because a
/// standard cost's key is the Product alone:
///
///   - the picker is over Products, not over four kinds of scope, so there is
///     no scope-type dropdown above it;
///   - the Product is what is not correctable, for the reason a rate's scope is
///     not: `product_standard_cost` finds a cost by it, so rewriting it would
///     move a whole price history onto a different Product.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'product_cost.dart';
import 'product_costs_bloc.dart';

/// Which of the three acts this dialog is performing — see [CostRateFormMode],
/// whose three values these mirror.
enum ProductCostFormMode { add, correct, revise }

class ProductCostFormDialog extends StatefulWidget {
  const ProductCostFormDialog({
    super.key,
    required this.mode,
    required this.products,
    this.productsFailure,
    this.productCost,
  });

  final ProductCostFormMode mode;

  /// The Products a cost may be recorded against, as the Screen read them.
  /// Only consulted in [ProductCostFormMode.add].
  final List<CostableProduct> products;

  /// Why the Product list could not be read, when it could not. Blocks Add.
  final String? productsFailure;

  /// The row being corrected or revised; null for Add.
  final ProductCost? productCost;

  static const String _productFieldName = 'product-cost-form-product';

  static ValueKey<String> get productKey => AppSearchField.fieldKey(_productFieldName);
  static ValueKey<String> productSuggestionKey(String productId) =>
      AppSearchField.suggestionKey(_productFieldName, productId);

  static const ValueKey<String> costKey = ValueKey<String>('product-cost-form-cost');
  static const ValueKey<String> currencyKey = ValueKey<String>('product-cost-form-currency');
  static const ValueKey<String> noteKey = ValueKey<String>('product-cost-form-note');
  static const ValueKey<String> submitKey = ValueKey<String>('product-cost-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('product-cost-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('product-cost-form-failure');
  static const ValueKey<String> productsFailureKey =
      ValueKey<String>('product-cost-form-products-failed');

  /// The two date pickers' own field names — see `CostRateFormDialog`'s own
  /// pair for why the `AppDateField`s carry no `key:` of their own.
  static const String _effectiveFromFieldName = 'product-cost-effective-from';
  static const String _effectiveToFieldName = 'product-cost-effective-to';

  static ValueKey<String> get effectiveFromKey =>
      AppDateField.fieldKey(_effectiveFromFieldName);
  static ValueKey<String> get effectiveToKey => AppDateField.fieldKey(_effectiveToFieldName);
  static ValueKey<String> get effectiveToClearKey =>
      AppDateField.clearKey(_effectiveToFieldName);

  static Future<void> open(
    BuildContext context, {
    required ProductCostFormMode mode,
    required List<CostableProduct> products,
    String? productsFailure,
    ProductCost? productCost,
  }) {
    final bloc = context.read<ProductCostsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<ProductCostsBloc>.value(
        value: bloc,
        child: ProductCostFormDialog(
          mode: mode,
          products: products,
          productsFailure: productsFailure,
          productCost: productCost,
        ),
      ),
    );
  }

  @override
  State<ProductCostFormDialog> createState() => _ProductCostFormDialogState();
}

class _ProductCostFormDialogState extends State<ProductCostFormDialog> {
  /// The chosen Product, in Add only — see [CostRateFormDialog]'s own `_scope`
  /// for why this is never seeded while correcting or revising.
  CostableProduct? _product;

  late final TextEditingController _cost = TextEditingController(
    text: widget.mode == ProductCostFormMode.correct ? '${widget.productCost!.standardCost}' : '',
  );
  late final TextEditingController _currency =
      TextEditingController(text: widget.productCost?.currency ?? 'USD');
  late final TextEditingController _note = TextEditingController(
    text: widget.mode == ProductCostFormMode.correct ? (widget.productCost?.note ?? '') : '',
  );

  late String? _effectiveFrom =
      widget.mode == ProductCostFormMode.correct ? widget.productCost!.effectiveFrom : null;
  late String? _effectiveTo =
      widget.mode == ProductCostFormMode.correct ? widget.productCost!.effectiveTo : null;

  bool _awaiting = false;
  String? _failure;

  bool get _isAdd => widget.mode == ProductCostFormMode.add;
  bool get _isCorrection => widget.mode == ProductCostFormMode.correct;
  bool get _isRevision => widget.mode == ProductCostFormMode.revise;

  @override
  void dispose() {
    _cost.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedCost {
    final text = _cost.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  bool get _currencyComplete => _currency.text.trim().length == 3;

  bool get _complete {
    if (_isAdd) {
      return widget.productsFailure == null &&
          _product != null &&
          _parsedCost != null &&
          _currencyComplete &&
          _effectiveFrom != null;
    }
    if (_isRevision) return _parsedCost != null && _currencyComplete && _effectiveFrom != null;
    return _cost.text.trim().isEmpty || _parsedCost != null;
  }

  Map<String, Object?> get _changes {
    final original = widget.productCost!;
    final changes = <String, Object?>{};
    final cost = _parsedCost;
    if (cost != null && cost != original.standardCost) changes['standardCost'] = cost;
    final currency = _currency.text.trim().toUpperCase();
    if (currency.length == 3 && currency != original.currency) changes['currency'] = currency;
    if (_effectiveFrom != null && _effectiveFrom != original.effectiveFrom) {
      changes['effectiveFrom'] = _effectiveFrom;
    }
    if (_effectiveTo != original.effectiveTo) changes['effectiveTo'] = _effectiveTo;
    final note = _note.text.trim();
    if (note != (original.note ?? '')) changes['note'] = note.isEmpty ? null : note;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    final bloc = context.read<ProductCostsBloc>();

    if (_isCorrection) {
      final changes = _changes;
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      bloc.add(ProductCostsCorrectionConfirmed(id: widget.productCost!.id, changes: changes));
      return;
    }

    setState(() {
      _awaiting = true;
      _failure = null;
    });

    final note = _note.text.trim();
    final currency = _currency.text.trim().toUpperCase();

    if (_isRevision) {
      bloc.add(ProductCostsRevisionConfirmed(
        id: widget.productCost!.id,
        body: {
          'standardCost': _parsedCost,
          'currency': currency,
          'effectiveFrom': _effectiveFrom,
          if (note.isNotEmpty) 'note': note,
        },
      ));
      return;
    }

    bloc.add(ProductCostsAddConfirmed(
      body: {
        'productId': _product!.id,
        'standardCost': _parsedCost,
        'currency': currency,
        'effectiveFrom': _effectiveFrom,
        if (_effectiveTo != null) 'effectiveTo': _effectiveTo,
        if (note.isNotEmpty) 'note': note,
      },
    ));
  }

  void _onCatalogueChanged(BuildContext context, ProductCostsState state) {
    if (!_awaiting || state is! ProductCostsLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  String get _title => switch (widget.mode) {
        ProductCostFormMode.add => 'Add standard cost',
        ProductCostFormMode.correct => 'Correct standard cost',
        ProductCostFormMode.revise => 'Revise standard cost',
      };

  String get _submitLabel => switch (widget.mode) {
        ProductCostFormMode.add => 'Add standard cost',
        ProductCostFormMode.correct => 'Save',
        ProductCostFormMode.revise => 'Revise from this date',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.productCost;

    return BlocListener<ProductCostsBloc, ProductCostsState>(
      listener: _onCatalogueChanged,
      child: AlertDialog(
        title: Text(_title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRevision)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      'The cost below is closed on the day the new one takes effect. It stays '
                      'readable, and scrap already costed at it keeps that figure.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (_isAdd && widget.productsFailure != null)
                  Padding(
                    key: ProductCostFormDialog.productsFailureKey,
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      'The Product list could not be read, so a Product cannot be chosen: '
                      '${widget.productsFailure}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                if (_isAdd)
                  AppSearchField<CostableProduct>(
                    name: ProductCostFormDialog._productFieldName,
                    label: 'Product',
                    value: _product,
                    enabled: !_awaiting && widget.productsFailure == null,
                    onChanged: (product) => setState(() => _product = product),
                    onSelected: (product) => setState(() => _product = product),
                    fetchSuggestions: (term) async {
                      final lower = term.toLowerCase();
                      return [
                        for (final product in widget.products)
                          if (product.name.toLowerCase().contains(lower) ||
                              product.code.toLowerCase().contains(lower))
                            product,
                      ];
                    },
                    suggestionBuilder: (context, product) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(product.label),
                    ),
                    idOf: (product) => product.id,
                    displayStringFor: (product) => product.label,
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      border: OutlineInputBorder(),
                      helperText: 'The Product a standard cost belongs to cannot be corrected — '
                          'record a cost against the other Product instead',
                    ),
                    child: Text(existing!.productLabel),
                  ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ProductCostFormDialog.costKey,
                  controller: _cost,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Standard cost, per unit',
                    border: const OutlineInputBorder(),
                    helperText: _isRevision ? 'The new cost, from the date below' : null,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ProductCostFormDialog.currencyKey,
                  controller: _currency,
                  enabled: !_awaiting,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                    counterText: '',
                    helperText: 'A three-letter code, such as USD',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppDateField(
                  name: ProductCostFormDialog._effectiveFromFieldName,
                  label: _isRevision ? 'New cost takes effect on' : 'Takes effect on',
                  helperText: _isRevision
                      ? 'The old cost is closed on this day, and the new one starts'
                      : null,
                  value: _effectiveFrom,
                  onChanged: (value) => setState(() => _effectiveFrom = value),
                  enabled: !_awaiting,
                ),
                if (!_isRevision) ...[
                  const SizedBox(height: Spacing.md),
                  AppDateField(
                    name: ProductCostFormDialog._effectiveToFieldName,
                    label: 'Applies until (optional)',
                    helperText: 'Left blank, this cost is the current one. Setting it closes the '
                        'cost on that day, which is the exclusive end of the period.',
                    value: _effectiveTo,
                    onChanged: (value) => setState(() => _effectiveTo = value),
                    optional: true,
                    enabled: !_awaiting,
                  ),
                ],
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ProductCostFormDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: ProductCostFormDialog.failureKey,
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
            key: ProductCostFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ProductCostFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : _submitLabel),
          ),
        ],
      ),
    );
  }
}
