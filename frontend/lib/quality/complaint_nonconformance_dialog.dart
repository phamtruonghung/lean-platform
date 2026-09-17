/// Recording the Non-conformance that controls the product a customer
/// complained about (issue #214) — `detection_point = customer`, the
/// complaint's own Product, and its Defect code, quantity and description
/// unless the caller names their own.
///
/// **The Defect code is only a field when the complaint has none.** The
/// complaint usually carries one (the person who wrote it down knew what was
/// wrong), and when it does, the record copies it — so this dialog shows it
/// read-only rather than asking the caller to pick it again. When the complaint
/// carries none, the catalogue is read here, once, and a list that cannot be
/// fetched blocks submission rather than falling back to free text (ADR-0023).
///
/// The quantity is prefilled from what the customer said when they said
/// anything; a complaint without a figure needs one here, because a
/// Non-conformance's affected quantity is NOT NULL in the baseline and
/// recording one is the act that says how much product is in question.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';
import 'defect_code.dart';
import 'quality_api.dart';

class ComplaintNonconformanceDialog extends StatefulWidget {
  const ComplaintNonconformanceDialog({super.key, required this.complaint});

  final CustomerComplaint complaint;

  static const ValueKey<String> quantityKey = ValueKey<String>('complaint-nc-quantity');
  static const ValueKey<String> loadingKey = ValueKey<String>('complaint-nc-loading');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('complaint-nc-defect-code');
  static const ValueKey<String> containmentKey = ValueKey<String>('complaint-nc-containment');
  static const ValueKey<String> submitKey = ValueKey<String>('complaint-nc-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('complaint-nc-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-nc-failure');
  static const ValueKey<String> codesFailedKey = ValueKey<String>('complaint-nc-codes-failed');
  static const ValueKey<String> codesRetryKey = ValueKey<String>('complaint-nc-codes-retry');

  @override
  State<ComplaintNonconformanceDialog> createState() => _ComplaintNonconformanceDialogState();
}

class _ComplaintNonconformanceDialogState extends State<ComplaintNonconformanceDialog> {
  late final TextEditingController _quantity = TextEditingController(
    text: widget.complaint.quantityAffected == null
        ? ''
        : _plainNumber(widget.complaint.quantityAffected!),
  );
  final TextEditingController _containment = TextEditingController();

  /// Only read when the complaint carries no Defect code of its own.
  bool _loadingCodes = false;
  String? _codesFailure;
  List<DefectCode> _codes = const [];
  String? _defectCodeId;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    if (widget.complaint.defectCodeId == null) {
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

  Future<void> _loadCodes() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _codesFailure = ComplaintDetailBloc.signedOutMessage;
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

  bool get _complete =>
      _quantityValue != null && (widget.complaint.defectCodeId != null || _defectCodeId != null);

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ComplaintDetailBloc>().add(
          ComplaintNonconformanceConfirmed(
            id: widget.complaint.id,
            quantity: _quantityValue,
            defectCodeId: _defectCodeId,
            immediateContainment: _containment.text.trim(),
          ),
        );
  }

  void _onDetailChanged(BuildContext context, ComplaintDetailState state) {
    if (!_awaiting || state is! ComplaintDetailLoaded || state.isMutating) return;
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
    final complaint = widget.complaint;

    return BlocListener<ComplaintDetailBloc, ComplaintDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Control the product'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A Non-conformance is recorded at ${complaint.orgUnitName} for '
                  '${complaint.productName}, found by the customer.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ComplaintNonconformanceDialog.quantityKey,
                  controller: _quantity,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantity affected',
                    helperText: 'How much product is in question, in the Product\'s own unit.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                if (complaint.defectCodeId != null)
                  TextFormField(
                    key: ComplaintNonconformanceDialog.defectCodeKey,
                    initialValue: '${complaint.defectCodeName} · ${complaint.defectCodeCode}',
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Defect code',
                      helperText: 'The complaint\'s own Defect code is carried onto the record.',
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
                    key: ComplaintNonconformanceDialog.codesFailedKey,
                    title: 'The Defect codes could not be read',
                    message: _codesFailure!,
                    retryKey: ComplaintNonconformanceDialog.codesRetryKey,
                    onRetry: _loadCodes,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ComplaintNonconformanceDialog.defectCodeKey,
                    initialValue: _defectCodeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Defect code',
                      helperText: 'This complaint carries none, so choose the one to record '
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
                  key: ComplaintNonconformanceDialog.containmentKey,
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
                    key: ComplaintNonconformanceDialog.failureKey,
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
            key: ComplaintNonconformanceDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ComplaintNonconformanceDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Recording…' : 'Record it'),
          ),
        ],
      ),
    );
  }
}
