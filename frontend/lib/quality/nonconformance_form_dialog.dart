/// Recording a Non-conformance (issue #205): what was found not to conform,
/// against which Product and Defect code, where it was found, how much of it
/// there is and what was done about it at once.
///
/// Addressed rather than popped — `/non-conformances/new` (ADR-0021) — so a
/// refresh lands on the register with the form open, and a widget test drives
/// it through the router the way `work_orders_test.dart` drives its own
/// dialogs.
///
/// **Every value with a known set is chosen, never typed** (ADR-0023). The
/// Product and the optional Asset are `AppSearchField`s that suggest records —
/// and filter the list the dialog already holds, in memory, so typing issues
/// no request — while the Defect code, the detection point and the severity
/// are dropdowns over closed sets. The Org Unit is People's own chooser, the
/// same one the Asset form and the raise-a-concern form use. The quantity is
/// the one genuinely free value on this page, because it is a count.
///
/// The severity offered is deliberately only the chosen Defect code's default
/// and anything worse than it: the API refuses a lower one with a 403 in this
/// slice, because deciding that nonconforming product is less bad than the
/// Defect code says is a Quality-authority decision (ADR-0035) that issue #206
/// owns. Offering a lower one and reporting the refusal back would be a form
/// asking a question it already knows the answer to.
///
/// The Asset is optional on purpose: a Non-conformance about a batch need not
/// name a machine. Its own read failing therefore blocks nothing — the field
/// says it could not be read and the rest of the form still submits, the same
/// treatment the raise-a-concern form gives its own optional Pillar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';

import '../maintenance/maintenance.dart';
import '../maintenance/maintenance_api.dart';
import '../people/people.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import '../widgets/app_search_field.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';
import 'nonconformances_bloc.dart';
import 'product.dart';

/// How the optional Asset list is being read — the same three states, and the
/// same reason, as the Work order form's own Asset picker.
enum _AssetsStatus { loading, ready, failed }

class NonconformanceFormDialog extends StatefulWidget {
  const NonconformanceFormDialog({super.key, required this.siteId});

  /// The Site the register is showing. The Org Unit chooser opens on it, the
  /// Asset list is read from it, and the recording is sent to it.
  final String siteId;

  static const ValueKey<String> productKey = ValueKey<String>('nonconformance-form-product');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('nonconformance-form-defect-code');
  static const ValueKey<String> detectionPointKey =
      ValueKey<String>('nonconformance-form-detection-point');
  static const ValueKey<String> quantityKey = ValueKey<String>('nonconformance-form-quantity');
  static const ValueKey<String> severityKey = ValueKey<String>('nonconformance-form-severity');
  static const ValueKey<String> lotRefKey = ValueKey<String>('nonconformance-form-lot');
  static const ValueKey<String> descriptionKey = ValueKey<String>('nonconformance-form-description');
  static const ValueKey<String> containmentKey = ValueKey<String>('nonconformance-form-containment');
  static const ValueKey<String> detectedAtKey = ValueKey<String>('nonconformance-form-detected-at');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-form-failure');
  static const ValueKey<String> assetsFailedKey =
      ValueKey<String>('nonconformance-form-assets-failed');
  static const ValueKey<String> chosenOrgUnitKey =
      ValueKey<String>('nonconformance-form-chosen-org-unit');

  /// The Asset picker's own name, which its `Key`s are derived from.
  static const String assetFieldName = 'nonconformance-asset';

  /// The Product picker's own name, and the two `Key`s an `AppSearchField`
  /// derives from it — the field itself and each suggestion row. A test types
  /// into the field and taps a suggestion through these (AGENTS.md §7: the
  /// widget exposes its own accessors rather than a test building a `Key`).
  static const String productFieldName = 'nonconformance-product';

  static ValueKey<String> productFieldKey() => AppSearchField.fieldKey(productFieldName);

  static ValueKey<String> productSuggestionKey(String id) =>
      AppSearchField.suggestionKey(productFieldName, id);

  /// The optional Asset picker's own two accessors, the same shape.
  static ValueKey<String> assetFieldKey() => AppSearchField.fieldKey(assetFieldName);

  static ValueKey<String> assetSuggestionKey(String id) =>
      AppSearchField.suggestionKey(assetFieldName, id);

  @override
  State<NonconformanceFormDialog> createState() => _NonconformanceFormDialogState();
}

class _NonconformanceFormDialogState extends State<NonconformanceFormDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _lotRef = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _containment = TextEditingController();

  Product? _product;
  String? _defectCodeId;
  String? _detectionPoint;
  String? _severity;
  String? _assetId;
  OrgUnitNode? _orgUnit;
  DateTime? _detectedAt;

  List<Asset> _assets = const [];
  _AssetsStatus _assetsStatus = _AssetsStatus.loading;
  String? _assetsFailure;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _lotRef.dispose();
    _description.dispose();
    _containment.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _assetsStatus = _AssetsStatus.loading;
      _assetsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = NonconformancesBloc.signedOutMessage;
      });
      return;
    }
    try {
      // Retired Assets are out of service (#61) and must not be offered; the
      // default read already excludes them.
      final assets = await context
          .read<MaintenanceApi>()
          .fetchAssets(token, siteId: widget.siteId);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _assetsStatus = _AssetsStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = error.message;
      });
    }
  }

  DefectCode? get _defectCode {
    final state = context.read<NonconformancesBloc>().state;
    if (state is! NonconformancesLoaded) return null;
    for (final code in state.defectCodes) {
      if (code.id == _defectCodeId) return code;
    }
    return null;
  }

  /// The severities this form may send: the chosen Defect code's own default
  /// and anything worse. Empty until a Defect code is chosen, because until
  /// then there is no floor to compare against.
  List<String> get _offerableSeverities {
    final code = _defectCode;
    if (code == null) return const [];
    return [
      for (final severity in DefectSeverity.values)
        if (severityRank(severity) >= severityRank(code.defaultSeverity)) severity,
    ];
  }

  double? get _parsedQuantity {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  bool get _complete =>
      _orgUnit != null &&
      _product != null &&
      _defectCodeId != null &&
      _detectionPoint != null &&
      _parsedQuantity != null;

  void _submit() {
    final quantity = _parsedQuantity;
    if (!_complete || _awaiting || quantity == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });

    final code = _defectCode;
    final lotRef = _lotRef.text.trim();
    final description = _description.text.trim();
    final containment = _containment.text.trim();

    context.read<NonconformancesBloc>().add(
          NonconformanceRecordConfirmed(
            orgUnitId: _orgUnit!.id,
            productId: _product!.id,
            defectCodeId: _defectCodeId!,
            detectionPoint: _detectionPoint!,
            quantity: quantity,
            // Sent only when it was actually raised above the Defect code's
            // own default — a severity equal to the default is the server's
            // own answer and needs no field.
            severity: code != null && _severity != null && _severity != code.defaultSeverity
                ? _severity
                : null,
            assetId: _assetId,
            lotRef: lotRef.isEmpty ? null : lotRef,
            description: description.isEmpty ? null : description,
            immediateContainment: containment.isEmpty ? null : containment,
            detectedAt: _detectedAt?.toUtc().toIso8601String(),
          ),
        );
  }

  /// Whether this form has finished with its one act. Popping twice would take
  /// the register's own page off the stack behind the dialog — the Bloc emits
  /// twice on the way out (once when the recording lands, once when the
  /// re-read answers), and both emissions look like success to this listener.
  bool _done = false;

  void _onRegisterChanged(BuildContext context, NonconformancesState state) {
    if (_done || !_awaiting || state is! NonconformancesLoaded || state.isRecording) return;
    if (state.recordFailure != null) {
      // The refusal stays inside the dialog with the values still in it, so a
      // caller fixes the one thing that was wrong rather than retyping the
      // whole record.
      setState(() {
        _awaiting = false;
        _failure = state.recordFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  // A chosen Org Unit belongs to the Site it was chosen in, so a Site change
  // necessarily discards it.
  void _onOrgUnitSiteChanged() {
    setState(() => _orgUnit = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final register = context.watch<NonconformancesBloc>().state;
    final loaded = register is NonconformancesLoaded ? register : null;
    final products = loaded?.products ?? const <Product>[];
    final defectCodes = loaded?.defectCodes ?? const <DefectCode>[];

    return BlocListener<NonconformancesBloc, NonconformancesState>(
      listener: _onRegisterChanged,
      child: BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
        listenWhen: (previous, current) => previous.siteId != current.siteId,
        listener: (context, state) => _onOrgUnitSiteChanged(),
        child: AlertDialog(
          title: const Text('Record a Non-conformance'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSearchField<Product>(
                    key: NonconformanceFormDialog.productKey,
                    name: 'nonconformance-product',
                    label: 'Product',
                    helperText: 'What the nonconforming product is.',
                    value: _product,
                    enabled: !_awaiting,
                    onChanged: (product) => setState(() => _product = product),
                    onSelected: (product) => setState(() => _product = product),
                    // A dumb in-memory filter over the catalogue the register
                    // already read: typing issues no request (ADR-0023).
                    fetchSuggestions: (term) async {
                      final lower = term.toLowerCase();
                      return [
                        for (final product in products)
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
                      child: Text('${product.name} (${product.code})'),
                    ),
                    idOf: (product) => product.id,
                    displayStringFor: (product) => '${product.name} (${product.code})',
                  ),
                  const SizedBox(height: Spacing.md),
                  DropdownButtonFormField<String?>(
                    key: NonconformanceFormDialog.defectCodeKey,
                    initialValue: _defectCodeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Defect code',
                      helperText: 'What is wrong with it. The severity starts at this code own '
                          'default.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Choose a code')),
                      for (final code in defectCodes)
                        DropdownMenuItem<String?>(
                          value: code.id,
                          child: Text('${code.name} · ${code.code}'),
                        ),
                    ],
                    onChanged: _awaiting
                        ? null
                        : (id) => setState(() {
                              _defectCodeId = id;
                              // The severity follows the code: a new code means
                              // a new floor, and keeping the old choice would
                              // let the form offer one the API refuses.
                              _severity = null;
                            }),
                  ),
                  const SizedBox(height: Spacing.md),
                  Wrap(
                    spacing: Spacing.md,
                    runSpacing: Spacing.sm,
                    children: [
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String?>(
                          key: NonconformanceFormDialog.detectionPointKey,
                          initialValue: _detectionPoint,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Detection point',
                            helperText: 'Where the control plan caught it.',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Choose a point'),
                            ),
                            for (final point in DetectionPoint.values)
                              DropdownMenuItem<String?>(
                                value: point,
                                child: Text(DetectionPoint.label(point)),
                              ),
                          ],
                          onChanged: _awaiting
                              ? null
                              : (point) => setState(() => _detectionPoint = point),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String?>(
                          key: NonconformanceFormDialog.severityKey,
                          initialValue: _severity,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Severity',
                            helperText: _defectCode == null
                                ? 'Chosen with the Defect code.'
                                : 'Starts at ${DefectSeverity.label(_defectCode!.defaultSeverity)}. '
                                    'Raising it is allowed; lowering it is a later decision.',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                _defectCode == null
                                    ? 'Choose a Defect code first'
                                    : 'Starts at '
                                        '${DefectSeverity.label(_defectCode!.defaultSeverity)}',
                              ),
                            ),
                            for (final severity in _offerableSeverities)
                              DropdownMenuItem<String?>(
                                value: severity,
                                child: Text(DefectSeverity.label(severity)),
                              ),
                          ],
                          onChanged: _awaiting || _defectCode == null
                              ? null
                              : (severity) => setState(() => _severity = severity),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          key: NonconformanceFormDialog.quantityKey,
                          controller: _quantity,
                          enabled: !_awaiting,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            helperText: 'How many pieces.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: NonconformanceFormDialog.lotRefKey,
                    controller: _lotRef,
                    enabled: !_awaiting,
                    decoration: const InputDecoration(
                      labelText: 'Lot reference (optional)',
                      helperText: 'What else is affected — a batch number is better than nothing.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  _AssetField(
                    status: _assetsStatus,
                    assets: _assets,
                    failure: _assetsFailure,
                    selectedId: _assetId,
                    enabled: !_awaiting,
                    onRetry: _loadAssets,
                    onChanged: (id) => setState(() => _assetId = id),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: NonconformanceFormDialog.descriptionKey,
                    controller: _description,
                    enabled: !_awaiting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Detail (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: NonconformanceFormDialog.containmentKey,
                    controller: _containment,
                    enabled: !_awaiting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Immediate containment (optional)',
                      helperText: 'What was done at once. Recording it makes this contained.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateTimeField(
                    key: NonconformanceFormDialog.detectedAtKey,
                    name: 'nonconformance-detected-at',
                    label: 'Detected at (optional)',
                    helperText: 'When it was found, if that is not now. This is what decides the '
                        'production day and shift it is filed against.',
                    value: _detectedAt,
                    optional: true,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _detectedAt = value),
                  ),
                  const SizedBox(height: Spacing.lg),
                  OrgUnitChooser(
                    selectedId: _orgUnit?.id,
                    enabled: !_awaiting,
                    showSitePicker: false,
                    title: 'Where it was found',
                    description: 'Choose the Org Unit the nonconforming product was found at. '
                        'This is what decides who may act on it.',
                    onSelected: (node) => setState(() => _orgUnit = node),
                  ),
                  if (_orgUnit != null)
                    Padding(
                      key: NonconformanceFormDialog.chosenOrgUnitKey,
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        'This Non-conformance will be recorded at ${_orgUnit!.name}.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (_failure != null)
                    Padding(
                      key: NonconformanceFormDialog.failureKey,
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Text(
                        _failure!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: NonconformanceFormDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: NonconformanceFormDialog.submitKey,
              onPressed: _complete && !_awaiting ? _submit : null,
              child: const Text('Record it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The optional Asset picker: a search field over the Site's register, or the
/// reason it could not be read. Optional on purpose, so a failed read blocks
/// nothing — see this file's own header.
class _AssetField extends StatelessWidget {
  const _AssetField({
    required this.status,
    required this.assets,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _AssetsStatus status;
  final List<Asset> assets;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  Asset? get _selected {
    for (final asset in assets) {
      if (asset.id == selectedId) return asset;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _AssetsStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _AssetsStatus.failed:
        return Column(
          key: NonconformanceFormDialog.assetsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Assets could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _AssetsStatus.ready:
        return AppSearchField<Asset>(
          name: NonconformanceFormDialog.assetFieldName,
          label: 'Asset (optional)',
          helperText: 'Which machine, if the find was on one. It must sit at that Org Unit.',
          value: _selected,
          enabled: enabled,
          // A pick sets the dialog's own id; typing over the chosen Asset
          // retires it, so this form can never submit an id its field has
          // stopped showing (ADR-0023 point 4).
          onChanged: (asset) => onChanged(asset?.id),
          onSelected: (asset) => onChanged(asset.id),
          fetchSuggestions: (term) async {
            final lower = term.toLowerCase();
            return [
              for (final asset in assets)
                if (asset.name.toLowerCase().contains(lower) ||
                    asset.code.toLowerCase().contains(lower))
                  asset,
            ];
          },
          suggestionBuilder: (context, asset) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Text('${asset.name} (${asset.code})'),
          ),
          idOf: (asset) => asset.id,
          displayStringFor: (asset) => '${asset.name} (${asset.code})',
        );
    }
  }
}
