/// Linking a Non-conformance that already exists to a customer complaint
/// (issue #214) — the second road to "the complained-of product is controlled".
///
/// It is the right road when somebody has already recorded the problem: a lot
/// was quarantined and written down when it was found, and the customer's
/// complaint about the same lot is the same Non-conformance. Recording a second
/// one would be one problem with two numbers.
///
/// **The picker offers only this complaint's own Product.** The server refuses
/// a Non-conformance about another Product (409, because it does not control
/// what the customer complained about), so the candidates are read with that
/// filter — a list a caller can pick from rather than one to guess at. The read
/// happens here, once, and a list that cannot be fetched blocks submission
/// rather than falling back to a typed id (ADR-0023).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/failure_state.dart';
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';
import 'nonconformance.dart';
import 'quality_api.dart';
import '../l10n/vocabulary.dart';

class ComplaintLinkDialog extends StatefulWidget {
  const ComplaintLinkDialog({super.key, required this.complaint});

  final CustomerComplaint complaint;

  static const ValueKey<String> candidateKey = ValueKey<String>('complaint-link-candidate');
  static const ValueKey<String> loadingKey = ValueKey<String>('complaint-link-loading');
  static final ValueKey<String> submitKey = AppDialog.actionKey('complaint-link-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('complaint-link-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-link-failure');
  static const ValueKey<String> candidatesFailedKey =
      ValueKey<String>('complaint-link-candidates-failed');
  static const ValueKey<String> candidatesRetryKey =
      ValueKey<String>('complaint-link-candidates-retry');
  static const ValueKey<String> noneKey = ValueKey<String>('complaint-link-none');

  @override
  State<ComplaintLinkDialog> createState() => _ComplaintLinkDialogState();
}

class _ComplaintLinkDialogState extends State<ComplaintLinkDialog> {
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
        _loadFailure = ComplaintDetailBloc.signedOutMessage;
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
            widget.complaint.siteId,
            filters: NonconformanceFilters(productId: widget.complaint.productId),
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
    context.read<ComplaintDetailBloc>().add(
          ComplaintLinkConfirmed(id: widget.complaint.id, nonconformanceId: _chosenId!),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return BlocListener<ComplaintDetailBloc, ComplaintDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.commonLinkANonConformance,
        size: AppDialogSize.picker,
        actions: [
          AppDialogAction(
            id: 'complaint-link-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'complaint-link-submit',
            label: _awaiting ? l10n.commonLinking : l10n.commonLinkIt,
            onPressed: _chosenId == null || _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.complaintLinkANonConformanceThatAlreadyExistsFor(widget.complaint.productName),
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
                key: ComplaintLinkDialog.candidatesFailedKey,
                title: l10n.commonTheNonConformancesCouldNotBeRead,
                message: _loadFailure!,
                retryKey: ComplaintLinkDialog.candidatesRetryKey,
                onRetry: _loadCandidates,
              )
            else if (_candidates.isEmpty)
              Text(
                l10n.complaintLinkNoNonConformanceHasBeenRecordedFor,
                key: ComplaintLinkDialog.noneKey,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              DropdownButtonFormField<String>(
                key: ComplaintLinkDialog.candidateKey,
                initialValue: _chosenId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.commonTheNonConformanceThatControlsIt,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final candidate in _candidates)
                    DropdownMenuItem<String>(
                      value: candidate.id,
                      child: Text(
                        '${candidate.issueNo} · ${nonconformanceStatusLabel(l10n, candidate.status)}'
                        '${candidate.lotRef == null ? '' : ' · ${candidate.lotRef}'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _awaiting ? null : (value) => setState(() => _chosenId = value),
              ),
            if (_failure != null)
              Padding(
                key: ComplaintLinkDialog.failureKey,
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
