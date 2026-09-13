/// Raising a Request: which Asset it is against, what is wrong, how urgent the
/// reporter judges it, and whether production is stopped right now (issue #72).
///
/// CONTEXT.md's own line is the point of this form: a Request is an ask, not a
/// commitment — accepting it is maintenance's decision, made later on the
/// triage queue. `urgency` here is the reporter's judgement and is never the
/// Work order's `priority`, which maintenance sets on acceptance.
///
/// Raised against whatever Site the list screen is already showing — there is
/// no Site selector of its own, mirroring `WorkOrderFormDialog`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'asset.dart';
import 'maintenance_api.dart';
import 'my_requests_bloc.dart';
import 'request.dart';

class RequestFormDialog extends StatefulWidget {
  const RequestFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  static const ValueKey<String> assetKey = ValueKey<String>('request-form-asset');
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('request-form-assets-failed');
  static const ValueKey<String> summaryKey = ValueKey<String>('request-form-summary');
  static const ValueKey<String> urgencyKey = ValueKey<String>('request-form-urgency');
  static const ValueKey<String> productionStoppedKey =
      ValueKey<String>('request-form-production-stopped');
  static const ValueKey<String> descriptionKey = ValueKey<String>('request-form-description');
  static const ValueKey<String> submitKey = ValueKey<String>('request-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('request-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('request-form-failure');

  @override
  State<RequestFormDialog> createState() => _RequestFormDialogState();
}

enum _AssetsStatus { loading, ready, failed }

class _RequestFormDialogState extends State<RequestFormDialog> {
  final TextEditingController _summary = TextEditingController();
  final TextEditingController _description = TextEditingController();

  _AssetsStatus _assetsStatus = _AssetsStatus.loading;
  List<Asset> _assets = const [];
  String? _assetsFailure;

  /// Null until chosen — never defaulted, so "an Asset was chosen" is not true
  /// without anybody choosing it.
  String? _assetId;
  RequestUrgency? _urgency;
  bool _productionStopped = false;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets(widget.siteId);
  }

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadAssets(String siteId) async {
    setState(() {
      _assetsStatus = _AssetsStatus.loading;
      _assetsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = MyRequestsBloc.signedOutMessage;
      });
      return;
    }
    try {
      // Retired Assets are out of service and must not be offered — the
      // default read already excludes them.
      final assets = await context.read<MaintenanceApi>().fetchAssets(token, siteId: siteId);
      if (!mounted || siteId != widget.siteId) return;
      setState(() {
        _assets = assets;
        _assetsStatus = _AssetsStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted || siteId != widget.siteId) return;
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = error.message;
      });
    }
  }

  bool get _complete => _assetId != null && _summary.text.trim().isNotEmpty && _urgency != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<MyRequestsBloc>().add(
          RequestRaiseConfirmed(
            siteId: widget.siteId,
            assetId: _assetId!,
            summary: _summary.text.trim(),
            urgency: _urgency!.wire,
            productionStopped: _productionStopped,
            description: description.isEmpty ? null : description,
          ),
        );
  }

  void _onMyRequestsChanged(BuildContext context, MyRequestsState state) {
    if (!_awaiting || state is! MyRequestsLoaded || state.isRaising) return;
    if (state.raiseFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.raiseFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<MyRequestsBloc, MyRequestsState>(
      listener: _onMyRequestsChanged,
      child: AlertDialog(
        title: const Text('Raise a Request'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AssetField(
                  status: _assetsStatus,
                  assets: _assets,
                  failure: _assetsFailure,
                  selectedId: _assetId,
                  enabled: !_awaiting,
                  onRetry: () => _loadAssets(widget.siteId),
                  onChanged: (id) => setState(() => _assetId = id),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: RequestFormDialog.summaryKey,
                  controller: _summary,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Summary',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<RequestUrgency>(
                  key: RequestFormDialog.urgencyKey,
                  initialValue: _urgency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Urgency', border: OutlineInputBorder()),
                  items: [
                    for (final urgency in RequestUrgency.values)
                      DropdownMenuItem<RequestUrgency>(value: urgency, child: Text(urgency.label)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _urgency = value),
                ),
                const SizedBox(height: Spacing.sm),
                CheckboxListTile(
                  key: RequestFormDialog.productionStoppedKey,
                  value: _productionStopped,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Production is stopped right now'),
                  onChanged:
                      _awaiting ? null : (value) => setState(() => _productionStopped = value ?? false),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: RequestFormDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: RequestFormDialog.failureKey,
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
            key: RequestFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: RequestFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Raise'),
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _AssetsStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _AssetsStatus.failed:
        return Column(
          key: RequestFormDialog.assetsFailedKey,
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
        return DropdownButtonFormField<String>(
          key: RequestFormDialog.assetKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Asset', border: OutlineInputBorder()),
          items: [
            for (final asset in assets)
              DropdownMenuItem<String>(value: asset.id, child: Text('${asset.name} (${asset.code})')),
          ],
          onChanged: enabled ? onChanged : null,
        );
    }
  }
}
