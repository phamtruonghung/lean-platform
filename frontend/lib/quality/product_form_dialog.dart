/// Adding a Product, and correcting one (issue #203): the shared catalogue's
/// own write surface (`POST`/`PATCH /api/quality/products`, product-routes.js,
/// administrator only).
///
/// One dialog for both, the same choice `JobRoleFormDialog` makes: a Product
/// carries a code, a name and a unit of measure, and the Active switch, not
/// enough surface to earn two files. [product] null means Add; non-null means
/// Correct, and Correct sends only the fields that actually changed — the
/// `hasOwnProperty` contract `JobRoleFormDialog` already keeps, on
/// `updateProduct`'s (products.js) own end.
///
/// Two differences from that dialog, both forced by what products.js accepts.
/// First, a Product's **code and unit of measure are not correctable**: the
/// code is what a Non-conformance, a report and a label quote, and the unit
/// decides how a quantity is read, so both are shown read-only while
/// correcting and never offered. Second, the unit of measure is a **choice**,
/// not a field: this dialog fetches the units the plant uses once, when it
/// opens, and a list it cannot fetch blocks submission rather than falling
/// back to free text (ADR-0023) — the same device `PartFormDialog` uses for
/// the same catalogue.
///
/// A Product is deactivated, never deleted (products.js's own header) — the
/// "Active" switch, offered only while correcting an existing row, is the one
/// way this dialog ever reaches `isActive`; there is no delete anywhere on this
/// Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import 'product.dart';
import 'products_bloc.dart';
import 'quality_api.dart';

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({super.key, this.product});

  /// Null for Add; the row being corrected otherwise.
  final Product? product;

  static const ValueKey<String> codeKey = ValueKey<String>('product-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('product-form-name');
  static const ValueKey<String> uomKey = ValueKey<String>('product-form-uom');
  static const ValueKey<String> activeKey = ValueKey<String>('product-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('product-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('product-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('product-form-failure');
  static const ValueKey<String> unitsFailedKey = ValueKey<String>('product-form-units-failed');
  static const ValueKey<String> unitsRetryKey = ValueKey<String>('product-form-units-retry');

  /// Opens the form over the Product catalogue. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<ProductsBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the same device every other dialog in this Platform
  /// uses.
  static Future<void> open(BuildContext context, {Product? product}) {
    final bloc = context.read<ProductsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<ProductsBloc>.value(
        value: bloc,
        child: ProductFormDialog(product: product),
      ),
    );
  }

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final TextEditingController _code = TextEditingController(text: widget.product?.code ?? '');
  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late bool _isActive = widget.product?.isActive ?? true;

  String? _uomCode;

  bool _loadingUnits = true;
  String? _unitsFailure;
  List<UnitOfMeasure> _units = const [];

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.product != null;

  @override
  void initState() {
    super.initState();
    // Only the Add form needs the list: a correction shows the unit the row
    // already carries and cannot change it (products.js refuses a `uomCode`
    // correction), so opening one asks the server for nothing it will not use.
    if (!_isCorrection) {
      _uomCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnits());
    } else {
      _loadingUnits = false;
      _uomCode = widget.product!.uomCode;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _loadingUnits = false;
        _unitsFailure = ProductsBloc.signedOutMessage;
      });
      return;
    }
    setState(() {
      _loadingUnits = true;
      _unitsFailure = null;
    });
    try {
      final units = await context.read<QualityApi>().fetchUnitsOfMeasure(token);
      if (!mounted) return;
      setState(() {
        _units = units;
        _uomCode = units.any((unit) => unit.code == _uomCode) ? _uomCode : null;
        _loadingUnits = false;
      });
    } on QualityApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingUnits = false;
        _unitsFailure = error.message;
      });
    }
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty && (_isCorrection || _uomCode != null);

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — never the whole form. Only called while correcting an existing
  /// row, where `widget.product` is non-null. The code and the unit of measure
  /// are absent by construction: neither is correctable, so neither is ever
  /// sent.
  Map<String, Object?> get _changes {
    final original = widget.product!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    if (_isActive != original.isActive) changes['isActive'] = _isActive;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
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
      context
          .read<ProductsBloc>()
          .add(ProductsCorrectionConfirmed(id: widget.product!.id, changes: changes));
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<ProductsBloc>().add(
            ProductsAddConfirmed(
              code: _code.text.trim(),
              name: _name.text.trim(),
              uomCode: _uomCode!,
            ),
          );
    }
  }

  void _onProductsChanged(BuildContext context, ProductsState state) {
    if (!_awaiting || state is! ProductsLoaded || state.isMutating) return;
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
    return BlocListener<ProductsBloc, ProductsState>(
      listener: _onProductsChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct Product' : 'Add Product'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: ProductFormDialog.codeKey,
                  controller: _code,
                  // A code is the one field a correction cannot rewrite.
                  enabled: !_isCorrection && !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Code',
                    border: const OutlineInputBorder(),
                    helperText: _isCorrection ? 'A Product\'s code cannot be corrected' : null,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ProductFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                if (_isCorrection)
                  TextFormField(
                    key: ProductFormDialog.uomKey,
                    initialValue: widget.product!.uomName,
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Unit of measure',
                      border: const OutlineInputBorder(),
                      helperText: 'A Product\'s unit of measure cannot be corrected',
                    ),
                  )
                else if (_loadingUnits)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_unitsFailure != null)
                  PlatformFailureState(
                    key: ProductFormDialog.unitsFailedKey,
                    title: 'The units of measure could not be read',
                    message: _unitsFailure!,
                    retryKey: ProductFormDialog.unitsRetryKey,
                    onRetry: _loadUnits,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ProductFormDialog.uomKey,
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
                          child: Text(unit.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _uomCode = value),
                  ),
                if (_isCorrection) ...[
                  const SizedBox(height: Spacing.md),
                  SwitchListTile(
                    key: ProductFormDialog.activeKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: ProductFormDialog.failureKey,
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
            key: ProductFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ProductFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add Product')),
          ),
        ],
      ),
    );
  }
}
