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
///
/// The form width (520): an Asset search field, an optional date-time field and
/// a three-line note, in one column — a short form, like every other
/// single-column form of this Module (Part, meter, reading). Nothing here has
/// columns of its own to spend the wide dialog's extra 120 on.
/// The 560 this used to set inside an `AlertDialog`'s content left the title and
/// the action row at a width the platform chose.
///
/// A dismiss that is disabled while the request is in flight stays disabled, and
/// so does `Esc` then: `AppDialog` runs the dismiss action, which does nothing
/// while it is null. The `AlertDialog` this replaces let `Esc` pop the route
/// mid-request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_date_time_field.dart';
import '../widgets/app_search_field.dart';
import 'asset.dart';
import 'downtime_bloc.dart';
import 'maintenance_api.dart';
import '../widgets/notice_text.dart';

class BreakdownReportDialog extends StatefulWidget {
  const BreakdownReportDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  /// The Asset picker's own field name — the one string [assetKey] and
  /// [assetSuggestionKey] are both derived from, so neither can drift from
  /// what the field itself is built with (AGENTS.md §7).
  static const String _assetFieldName = 'breakdown-report-asset';

  /// The Asset picker's own `Key` (AGENTS.md §7). It was a
  /// `DropdownButtonFormField` until issue #190: a Site's whole register is a
  /// set nobody can scan, so the record is now found by typing rather than
  /// scrolled to (ADR-0023).
  static ValueKey<String> get assetKey => AppSearchField.fieldKey(_assetFieldName);

  /// One Asset suggestion row's own `Key`, keyed by the Asset's id
  /// (AGENTS.md §7).
  static ValueKey<String> assetSuggestionKey(String assetId) =>
      AppSearchField.suggestionKey(_assetFieldName, assetId);
  static const ValueKey<String> assetsFailedKey = ValueKey<String>(
    'breakdown-report-assets-failed',
  );
  static const ValueKey<String> startedAtKey = ValueKey<String>('breakdown-report-started-at');
  static const ValueKey<String> descriptionKey = ValueKey<String>('breakdown-report-description');
  static const ValueKey<String> failureKey = ValueKey<String>('breakdown-report-failure');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'breakdown-report-submit';
  static const String _dismissId = 'breakdown-report-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);

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
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return BlocListener<DowntimeBloc, DowntimeState>(
      listener: _onDowntimeChanged,
      child: AppDialog(
        title: l10n.breakdownReportReportABreakdown,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: BreakdownReportDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: BreakdownReportDialog._submitId,
            label: l10n.breakdownReportReport,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
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
              label: l10n.breakdownReportStartedAtOptional,
              helperText: l10n.commonLeaveBlankToRecordNow,
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
              decoration: InputDecoration(
                labelText: l10n.jobPlanFormDescriptionOptional,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: BreakdownReportDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
                  _failure!,
                  style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
                ),
              ),
          ],
        ),
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
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
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
          key: BreakdownReportDialog.assetsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoticeText(
              failure ?? l10n.commonAssetsFailed,
              style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: Text(l10n.commonTryAgain)),
          ],
        );
      case _AssetsStatus.ready:
        return AppSearchField<Asset>(
          name: BreakdownReportDialog._assetFieldName,
          label: l10n.commonAsset,
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
          codeOf: (asset) => asset.code,
        );
    }
  }
}
