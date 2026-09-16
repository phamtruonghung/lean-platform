/// Raising a Work order: which Asset it is against, what the job is, what
/// kind of work it is, and how urgent it is (issue #57).
///
/// Raised against whatever Site the list screen is already showing — there is
/// no Site selector of its own. A caller covering more than one Site switches
/// Site on the list first, the same way narrowing to an Org Unit or raising
/// against a different Site's Asset both start from the list, not from inside
/// this dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import 'asset.dart';
import 'maintenance_api.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderFormDialog extends StatefulWidget {
  const WorkOrderFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets, and the raised Work order lands against one of
  /// them.
  final String siteId;

  /// The Asset picker's own field name — the one string [assetKey] and
  /// [assetSuggestionKey] are both derived from, so neither can drift from
  /// what the field itself is built with (AGENTS.md §7).
  static const String _assetFieldName = 'work-order-form-asset';

  /// The Asset picker's own `Key` (AGENTS.md §7). It was a
  /// `DropdownButtonFormField` until issue #190: a Site's whole register is a
  /// set nobody can scan, so the record is now found by typing rather than
  /// scrolled to (ADR-0023).
  static ValueKey<String> get assetKey => AppSearchField.fieldKey(_assetFieldName);

  /// One Asset suggestion row's own `Key`, keyed by the Asset's id
  /// (AGENTS.md §7).
  static ValueKey<String> assetSuggestionKey(String assetId) =>
      AppSearchField.suggestionKey(_assetFieldName, assetId);

  static const ValueKey<String> assetsFailedKey = ValueKey<String>('work-order-form-assets-failed');
  static const ValueKey<String> summaryKey = ValueKey<String>('work-order-form-summary');
  static const ValueKey<String> workTypeKey = ValueKey<String>('work-order-form-work-type');
  static const ValueKey<String> priorityKey = ValueKey<String>('work-order-form-priority');
  static const ValueKey<String> descriptionKey = ValueKey<String>('work-order-form-description');
  static const ValueKey<String> submitKey = ValueKey<String>('work-order-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('work-order-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-form-failure');

  @override
  State<WorkOrderFormDialog> createState() => _WorkOrderFormDialogState();
}

enum _AssetsStatus { loading, ready, failed }

/// The word next to each priority level, indexed `level - 1` — 1 is the CHECK
/// constraint's most urgent end, 5 its least, made visible at the point of
/// choosing rather than left as a bare digit whose direction is not obvious.
const List<String> _priorityLabels = ['Most urgent', 'Urgent', 'Normal', 'Low', 'Least urgent'];

class _WorkOrderFormDialogState extends State<WorkOrderFormDialog> {
  final TextEditingController _summary = TextEditingController();
  final TextEditingController _description = TextEditingController();

  _AssetsStatus _assetsStatus = _AssetsStatus.loading;
  List<Asset> _assets = const [];
  String? _assetsFailure;

  /// Null until chosen — never defaulted, so "an Asset was chosen" is not
  /// true without anybody choosing it, the same discipline `AssetFormDialog`
  /// keeps for its own `_type`.
  String? _assetId;
  WorkType? _workType;
  int? _priority;

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
        _assetsFailure = WorkOrdersBloc.signedOutMessage;
      });
      return;
    }
    try {
      // Retired Assets are out of service (#61) and must not be offered
      // here — the default read already excludes them, so nothing further
      // filters the result.
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

  bool get _complete =>
      _assetId != null &&
      _summary.text.trim().isNotEmpty &&
      _workType != null &&
      _priority != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<WorkOrdersBloc>().add(
          WorkOrderRaiseConfirmed(
            siteId: widget.siteId,
            assetId: _assetId!,
            summary: _summary.text.trim(),
            workType: _workType!.wire,
            priority: _priority!,
            description: description.isEmpty ? null : description,
          ),
        );
  }

  void _onWorkOrdersChanged(BuildContext context, WorkOrdersState state) {
    if (!_awaiting || state is! WorkOrdersLoaded || state.isRaising) return;
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
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      child: AlertDialog(
        title: const Text('Raise a Work order'),
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
                  key: WorkOrderFormDialog.summaryKey,
                  controller: _summary,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'Summary', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<WorkType>(
                        key: WorkOrderFormDialog.workTypeKey,
                        initialValue: _workType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Work type',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final type in WorkType.values)
                            DropdownMenuItem<WorkType>(value: type, child: Text(type.label)),
                        ],
                        onChanged: _awaiting ? null : (value) => setState(() => _workType = value),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: WorkOrderFormDialog.priorityKey,
                        initialValue: _priority,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var level = 1; level <= 5; level++)
                            DropdownMenuItem<int>(
                              value: level,
                              child: Text(
                                '$level - ${_priorityLabels[level - 1]}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _awaiting ? null : (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: WorkOrderFormDialog.descriptionKey,
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
                    key: WorkOrderFormDialog.failureKey,
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
            key: WorkOrderFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: WorkOrderFormDialog.submitKey,
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

  /// The Asset the dialog's own id currently names, or null — the dialog
  /// keeps holding the `String?` id its submit body already reads, while the
  /// picker is controlled by the record itself, so this is how the two agree.
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
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _AssetsStatus.failed:
        return Column(
          key: WorkOrderFormDialog.assetsFailedKey,
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
          name: WorkOrderFormDialog._assetFieldName,
          label: 'Asset',
          value: _selected,
          enabled: enabled,
          // A pick sets the dialog's own id; typing over the chosen Asset
          // retires it, so this form can never submit an id its own field has
          // stopped showing (ADR-0023 point 4).
          onChanged: (asset) => onChanged(asset?.id),
          onSelected: (asset) => onChanged(asset.id),
          // A dumb in-memory filter over the register `initState` already
          // read — no HTTP request of its own, so the field's per-term
          // debounce never reaches the wire (ADR-0023). Matched on the two
          // fields that identify an Asset: its name and its code.
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
