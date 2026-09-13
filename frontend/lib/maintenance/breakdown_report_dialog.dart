/// Reporting a Breakdown: which Asset stopped, when it started, and what is
/// wrong (issue #73).
///
/// CONTEXT.md's own line is the point of this form: a Breakdown is a machine
/// stopping unplanned, so it bypasses the request-and-decline path entirely —
/// the server produces the Downtime event and the corrective Work order
/// together in one transaction from this one call.
///
/// A duplicate report of an Asset already recorded as down is refused with a
/// 409 whose message names the Asset and since when. That message is shown on
/// [failureKey] and the dialog stays open, because the actionable thing to do
/// is close the stop already open rather than retype this form.
///
/// Raised against whatever Site the list screen is already showing — there is
/// no Site selector of its own, mirroring `WorkOrderFormDialog`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'asset.dart';
import 'downtime_bloc.dart';
import 'maintenance_api.dart';

class BreakdownReportDialog extends StatefulWidget {
  const BreakdownReportDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  static const ValueKey<String> assetKey = ValueKey<String>('breakdown-report-asset');
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('breakdown-report-assets-failed');
  static const ValueKey<String> startedAtKey = ValueKey<String>('breakdown-report-started-at');
  static const ValueKey<String> descriptionKey = ValueKey<String>('breakdown-report-description');
  static const ValueKey<String> submitKey = ValueKey<String>('breakdown-report-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('breakdown-report-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('breakdown-report-failure');

  @override
  State<BreakdownReportDialog> createState() => _BreakdownReportDialogState();
}

enum _AssetsStatus { loading, ready, failed }

class _BreakdownReportDialogState extends State<BreakdownReportDialog> {
  final TextEditingController _description = TextEditingController();

  _AssetsStatus _assetsStatus = _AssetsStatus.loading;
  List<Asset> _assets = const [];
  String? _assetsFailure;

  /// Null until chosen — never defaulted, so "an Asset was chosen" is not true
  /// without anybody choosing it.
  String? _assetId;

  /// Null means the server records now(), which is the honest default for a
  /// machine somebody just found stopped.
  DateTime? _startedAt;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets(widget.siteId);
  }

  @override
  void dispose() {
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
        _assetsFailure = DowntimeBloc.signedOutMessage;
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

  bool get _complete => _assetId != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<DowntimeBloc>().add(
          BreakdownReportConfirmed(
            siteId: widget.siteId,
            assetId: _assetId!,
            startedAt: _startedAt,
            description: description.isEmpty ? null : description,
          ),
        );
  }

  void _onDowntimeChanged(BuildContext context, DowntimeState state) {
    if (!_awaiting || state is! DowntimeLoaded || state.isReporting) return;
    if (state.reportFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.reportFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<DowntimeBloc, DowntimeState>(
      listener: _onDowntimeChanged,
      child: AlertDialog(
        title: const Text('Report a Breakdown'),
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
                AppDateTimeField(
                  key: BreakdownReportDialog.startedAtKey,
                  name: 'breakdown-report-started-at',
                  label: 'Started at (optional)',
                  helperText: 'Leave blank to record now.',
                  value: _startedAt,
                  optional: true,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _startedAt = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: BreakdownReportDialog.descriptionKey,
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
                    key: BreakdownReportDialog.failureKey,
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
            key: BreakdownReportDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: BreakdownReportDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Report'),
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
          key: BreakdownReportDialog.assetsFailedKey,
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
          key: BreakdownReportDialog.assetKey,
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
