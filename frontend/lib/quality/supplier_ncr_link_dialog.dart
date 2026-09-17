/// Linking a Non-conformance that already exists to a supplier NCR
/// (issue #215) — the second road to "the complained-of product is controlled".
///
/// It is the right road when somebody has already recorded the problem: a lot
/// was quarantined and written down when it was found, and the supplier's
/// supplier NCR about the same lot is the same Non-conformance. Recording a second
/// one would be one problem with two numbers.
///
/// **The picker offers only this supplier NCR's own Product.** The server refuses
/// a Non-conformance about another Product (409, because it does not control
/// what the supplier complained about), so the candidates are read with that
/// filter — a list a caller can pick from rather than one to guess at. The read
/// happens here, once, and a list that cannot be fetched blocks submission
/// rather than falling back to a typed id (ADR-0023).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import 'supplier_ncr_detail_bloc.dart';
import 'supplier_ncr.dart';
import 'nonconformance.dart';
import 'quality_api.dart';

class SupplierNcrLinkDialog extends StatefulWidget {
  const SupplierNcrLinkDialog({super.key, required this.supplierNcr});

  final SupplierNcr supplierNcr;

  static const ValueKey<String> candidateKey = ValueKey<String>('supplier-ncr-link-candidate');
  static const ValueKey<String> loadingKey = ValueKey<String>('supplier-ncr-link-loading');
  static const ValueKey<String> submitKey = ValueKey<String>('supplier-ncr-link-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('supplier-ncr-link-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('supplier-ncr-link-failure');
  static const ValueKey<String> candidatesFailedKey =
      ValueKey<String>('supplier-ncr-link-candidates-failed');
  static const ValueKey<String> candidatesRetryKey =
      ValueKey<String>('supplier-ncr-link-candidates-retry');
  static const ValueKey<String> noneKey = ValueKey<String>('supplier-ncr-link-none');

  @override
  State<SupplierNcrLinkDialog> createState() => _SupplierNcrLinkDialogState();
}

class _SupplierNcrLinkDialogState extends State<SupplierNcrLinkDialog> {
  bool _loading = true;
  String? _loadFailure;
  List<Nonconformance> _candidates = const [];

  String? _chosenId;
  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCandidates());
  }

  Future<void> _loadCandidates() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _loading = false;
        _loadFailure = SupplierNcrDetailBloc.signedOutMessage;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    try {
      final register = await context.read<QualityApi>().fetchNonconformances(
            token,
            widget.supplierNcr.siteId,
            filters: NonconformanceFilters(productId: widget.supplierNcr.productId),
          );
      if (!mounted) return;
      setState(() {
        // A cancelled record controls nothing, so it is not offered.
        _candidates = [
          for (final row in register.nonconformances)
            if (row.status != NonconformanceStatus.cancelled) row,
        ];
        _loading = false;
      });
    } on QualityApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailure = error.message;
      });
    }
  }

  void _submit() {
    if (_chosenId == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SupplierNcrDetailBloc>().add(
          SupplierNcrLinkConfirmed(id: widget.supplierNcr.id, nonconformanceId: _chosenId!),
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

    return BlocListener<SupplierNcrDetailBloc, SupplierNcrDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Link a Non-conformance'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A Non-conformance that already exists'
                  '${widget.supplierNcr.productName == null ? '' : ' for ${widget.supplierNcr.productName}'}'
                  ' can be linked to this supplier NCR, instead of recording a second one for the '
                  'same problem.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_loadFailure != null)
                  PlatformFailureState(
                    key: SupplierNcrLinkDialog.candidatesFailedKey,
                    title: 'The Non-conformances could not be read',
                    message: _loadFailure!,
                    retryKey: SupplierNcrLinkDialog.candidatesRetryKey,
                    onRetry: _loadCandidates,
                  )
                else if (_candidates.isEmpty)
                  Text(
                    'No Non-conformance has been recorded for this Product yet, so there is '
                    'nothing to link. Record one from this supplier NCR instead.',
                    key: SupplierNcrLinkDialog.noneKey,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: SupplierNcrLinkDialog.candidateKey,
                    initialValue: _chosenId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'The Non-conformance that controls it',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final candidate in _candidates)
                        DropdownMenuItem<String>(
                          value: candidate.id,
                          child: Text(
                            '${candidate.issueNo} · ${NonconformanceStatus.label(candidate.status)}'
                            '${candidate.lotRef == null ? '' : ' · ${candidate.lotRef}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _chosenId = value),
                  ),
                if (_failure != null)
                  Padding(
                    key: SupplierNcrLinkDialog.failureKey,
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
            key: SupplierNcrLinkDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SupplierNcrLinkDialog.submitKey,
            onPressed: _chosenId == null || _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Linking…' : 'Link it'),
          ),
        ],
      ),
    );
  }
}
