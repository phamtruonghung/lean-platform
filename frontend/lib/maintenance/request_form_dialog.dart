/// Raising a Request (issue #72): which Asset it is against, what the reporter
/// noticed, and whether it is stopping production right now.
///
/// Raised against whatever Site the requester screen is already showing, the
/// same way `WorkOrderFormDialog` raises against the Work order list's Site.
/// `urgency` is the operator's judgement of how urgently they need an answer;
/// it stays separate from the priority maintenance assigns on acceptance (the
/// gap is a real signal about how the plant is run), so this form never asks
/// for a priority and the server never copies urgency into one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'asset.dart';
import 'maintenance_api.dart';
import 'requests_bloc.dart';

class RequestFormDialog extends StatefulWidget {
  const RequestFormDialog({super.key, required this.siteId});

  /// The Site the requester screen is already showing — the Asset dropdown
  /// lists only that Site's Assets, and the raised Request lands against one
  /// of them.
  final String siteId;

  static const ValueKey<String> assetKey = ValueKey<String>('request-form-asset');
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('request-form-assets-failed');
  static const ValueKey<String> summaryKey = ValueKey<String>('request-form-summary');
  static const ValueKey<String> urgencyKey = ValueKey<String>('request-form-urgency');
  static const ValueKey<String> stoppedKey = ValueKey<String>('request-form-production-stopped');
  static const ValueKey<String> descriptionKey = ValueKey<String>('request-form-description');
  static const ValueKey<String> submitKey = ValueKey<String>('request-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('request-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('request-form-failure');

  static Future<void> open(BuildContext context, {required String siteId}) {
    final bloc = context.read<RequestsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: RequestFormDialog(siteId: siteId),
      ),
    );
  }

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

  String? _assetId;
  String? _urgency;
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
        _assetsFailure = RequestsBloc.signedOutMessage;
      });
      return;
    }
    try {
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
    context.read<RequestsBloc>().add(
          RequestRaiseConfirmed(
            siteId: widget.siteId,
            assetId: _assetId!,
            summary: _summary.text.trim(),
            urgency: _urgency!,
            productionStopped: _productionStopped,
            description: description.isEmpty ? null : description,
          ),
        );
  }

  void _onRequestsChanged(BuildContext context, RequestsState state) {
    if (!_awaiting || state is! RequestsLoaded) return;
    if (state.raiseFailure != null || state.isRaising) {
      if (state.raiseFailure != null) {
        setState(() {
          _awaiting = false;
          _failure = state.raiseFailure;
        });
      }
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<RequestsBloc, RequestsState>(
      listener: _onRequestsChanged,
      child: AlertDialog(
        title: const Text('Raise a Request'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ask maintenance to look at something. This commits them to '
                  'nothing — they may accept it into a Work order or decline it.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
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
                  decoration:
                      const InputDecoration(labelText: 'Summary', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: RequestFormDialog.urgencyKey,
                  initialValue: _urgency,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Urgency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'immediate', child: Text('Immediate')),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) => setState(() => _urgency = value),
                ),
                const SizedBox(height: Spacing.md),
                CheckboxListTile(
                  key: RequestFormDialog.stoppedKey,
                  value: _productionStopped,
                  onChanged: _awaiting ? null : (value) => setState(() => _productionStopped = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Production is stopped right now'),
                ),
                const SizedBox(height: Spacing.md),
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