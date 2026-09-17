/// Recording the Non-conformance that controls the material a supplier NCR is
/// about (issue #215) — `detection_point = incoming`, the NCR's own Product and
/// Defect code where it carries them, and the quantity, lot and description
/// unless the caller names their own.
///
/// **A field appears only when the NCR does not already carry it.** An NCR
/// usually names the Product it is destined for and the Defect code somebody
/// recognised, and when it does, the record copies them — so this dialog shows
/// each read-only rather than asking the caller to pick it again. A lot
/// received against a purchase order may name neither, and then the catalogue is
/// read here, once, and a list that cannot be fetched blocks submission rather
/// than falling back to free text (ADR-0023). A Non-conformance has to be about
/// one Product, which is why the Product is asked for at all: this is the one
/// thing a supplier NCR may leave open and a Non-conformance may not.
///
/// The quantity is prefilled from what arrived when it is known, and is required
/// whatever happens: a Non-conformance's affected quantity is NOT NULL in the
/// baseline, and recording one is the act that says how much material is in
/// question.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import 'defect_code.dart';
import 'product.dart';
import 'quality_api.dart';
import 'supplier_ncr.dart';
import 'supplier_ncr_detail_bloc.dart';

class SupplierNcrNonconformanceDialog extends StatefulWidget {
  const SupplierNcrNonconformanceDialog({super.key, required this.supplierNcr});

  final SupplierNcr supplierNcr;

  static const ValueKey<String> quantityKey = ValueKey<String>('supplier-ncr-nc-quantity');
  static const ValueKey<String> loadingKey = ValueKey<String>('supplier-ncr-nc-loading');
  static const ValueKey<String> productKey = ValueKey<String>('supplier-ncr-nc-product');
  static const ValueKey<String> productsFailedKey =
      ValueKey<String>('supplier-ncr-nc-products-failed');
  static const ValueKey<String> productsRetryKey =
      ValueKey<String>('supplier-ncr-nc-products-retry');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('supplier-ncr-nc-defect-code');
  static const ValueKey<String> containmentKey = ValueKey<String>('supplier-ncr-nc-containment');
  static const ValueKey<String> submitKey = ValueKey<String>('supplier-ncr-nc-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('supplier-ncr-nc-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-nc-failure');
  static const ValueKey<String> codesFailedKey = ValueKey<String>('supplier-ncr-nc-codes-failed');
  static const ValueKey<String> codesRetryKey = ValueKey<String>('supplier-ncr-nc-codes-retry');

  @override
  State<SupplierNcrNonconformanceDialog> createState() =>
      _SupplierNcrNonconformanceDialogState();
}

class _SupplierNcrNonconformanceDialogState extends State<SupplierNcrNonconformanceDialog> {
  late final TextEditingController _quantity =
      TextEditingController(text: _plainNumber(widget.supplierNcr.quantityAffected));
  final TextEditingController _containment = TextEditingController();

  /// Only read when the NCR carries no Product of its own — a Non-conformance
  /// has to be about one.
  bool _loadingProducts = false;
  String? _productsFailure;
  List<Product> _products = const [];
  String? _productId;

  /// Only read when the NCR carries no Defect code of its own.
  bool _loadingCodes = false;
  String? _codesFailure;
  List<DefectCode> _codes = const [];
  String? _defectCodeId;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    if (widget.supplierNcr.productId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
    }
    if (widget.supplierNcr.defectCodeId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCodes());
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _containment.dispose();
    super.dispose();
  }

  static String _plainNumber(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  Future<void> _loadProducts() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _productsFailure = SupplierNcrDetailBloc.signedOutMessage;
      });
      return;
    }
    setState(() {
      _loadingProducts = true;
      _productsFailure = null;
    });
    try {
      final products = await context.read<QualityApi>().fetchProducts(token);
      if (!mounted) return;
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
    } on QualityApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _productsFailure = error.message;
      });
    }
  }

  Future<void> _loadCodes() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _codesFailure = SupplierNcrDetailBloc.signedOutMessage;
      });
      return;
    }
    setState(() {
      _loadingCodes = true;
      _codesFailure = null;
    });
    try {
      final codes = await context.read<QualityApi>().fetchDefectCodes(token);
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _loadingCodes = false;
      });
    } on QualityApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCodes = false;
        _codesFailure = error.message;
      });
    }
  }

  num? get _quantityValue {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  bool get _complete {
    final quantity = _quantityValue;
    final hasProduct = widget.supplierNcr.productId != null || _productId != null;
    final hasDefectCode = widget.supplierNcr.defectCodeId != null || _defectCodeId != null;
    return quantity != null && quantity > 0 && hasProduct && hasDefectCode;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SupplierNcrDetailBloc>().add(
          SupplierNcrNonconformanceConfirmed(
            id: widget.supplierNcr.id,
            productId: _productId,
            quantity: _quantityValue,
            defectCodeId: _defectCodeId,
            immediateContainment: _containment.text.trim(),
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
    final theme = Theme.of(context);
    final ncr = widget.supplierNcr;
    final productName = ncr.productName;

    return BlocListener<SupplierNcrDetailBloc, SupplierNcrDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Control the material'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A Non-conformance is recorded at ${ncr.orgUnitName}'
                  '${productName == null ? '' : ' for $productName'}, found at goods-in.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrNonconformanceDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantity affected',
                    helperText: 'How much material is in question, in the unit it came in.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                if (ncr.productId != null)
                  TextFormField(
                    key: SupplierNcrNonconformanceDialog.productKey,
                    initialValue: '$productName · ${ncr.productCode}',
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      helperText: "The supplier NCR's own Product is carried onto the record.",
                      border: OutlineInputBorder(),
                    ),
                  )
                else if (_loadingProducts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_productsFailure != null)
                  PlatformFailureState(
                    key: SupplierNcrNonconformanceDialog.productsFailedKey,
                    title: 'The Products could not be read',
                    message: _productsFailure!,
                    retryKey: SupplierNcrNonconformanceDialog.productsRetryKey,
                    onRetry: _loadProducts,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: SupplierNcrNonconformanceDialog.productKey,
                    initialValue: _productId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      helperText: 'This supplier NCR names none, so choose what the lot was for.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final product in _products)
                        DropdownMenuItem<String>(
                          value: product.id,
                          child: Text('${product.name} · ${product.code}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _productId = value),
                  ),
                const SizedBox(height: Spacing.md),
                if (ncr.defectCodeId != null)
                  TextFormField(
                    key: SupplierNcrNonconformanceDialog.defectCodeKey,
                    initialValue: '${ncr.defectCodeName} · ${ncr.defectCodeCode}',
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Defect code',
                      helperText: "The supplier NCR's own Defect code is carried onto the record.",
                      border: OutlineInputBorder(),
                    ),
                  )
                else if (_loadingCodes)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_codesFailure != null)
                  PlatformFailureState(
                    key: SupplierNcrNonconformanceDialog.codesFailedKey,
                    title: 'The Defect codes could not be read',
                    message: _codesFailure!,
                    retryKey: SupplierNcrNonconformanceDialog.codesRetryKey,
                    onRetry: _loadCodes,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: SupplierNcrNonconformanceDialog.defectCodeKey,
                    initialValue: _defectCodeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Defect code',
                      helperText: 'This supplier NCR carries none, so choose the one to record '
                          'it against.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final code in _codes)
                        DropdownMenuItem<String>(
                          value: code.id,
                          child: Text('${code.name} · ${code.code}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _defectCodeId = value),
                  ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SupplierNcrNonconformanceDialog.containmentKey,
                  controller: _containment,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Immediate containment (optional)',
                    helperText: 'What was done at once. Recording it makes the record contained.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: SupplierNcrNonconformanceDialog.failureKey,
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
            key: SupplierNcrNonconformanceDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SupplierNcrNonconformanceDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Recording…' : 'Record it'),
          ),
        ],
      ),
    );
  }
}
