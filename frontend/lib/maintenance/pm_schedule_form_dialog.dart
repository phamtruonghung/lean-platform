/// Attaching a Job plan to an Asset as a PM schedule (issue #74): which Asset,
/// which plan, how often, and how the calendar rolls.
///
/// CONTEXT.md's own line is the point of the anchor choice: a PM schedule is
/// what raises a Work order before something breaks. The two anchors differ
/// exactly when work runs late, so the form explains each rather than leaving
/// a bare word to be guessed at.
///
/// The Asset picker reads the Site's own register; the Job plan picker reads
/// the shared catalogue, active plans only — the server refuses an inactive
/// one with a 400, so it is not offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'asset.dart';
import 'job_plan.dart';
import 'maintenance_api.dart';
import 'meter.dart';
import 'pm_schedule.dart';
import 'pm_schedules_bloc.dart';

class PmScheduleFormDialog extends StatefulWidget {
  const PmScheduleFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  /// The Asset picker's own field name — the one string [assetKey] and
  /// [assetSuggestionKey] are both derived from, so neither can drift from
  /// what the field itself is built with (AGENTS.md §7).
  static const String _assetFieldName = 'pm-schedule-form-asset';

  /// The Asset picker's own `Key` (AGENTS.md §7). It was a
  /// `DropdownButtonFormField` until issue #190: a Site's whole register is a
  /// set nobody can scan, so the record is now found by typing rather than
  /// scrolled to (ADR-0023).
  static ValueKey<String> get assetKey => AppSearchField.fieldKey(_assetFieldName);

  /// One Asset suggestion row's own `Key`, keyed by the Asset's id
  /// (AGENTS.md §7).
  static ValueKey<String> assetSuggestionKey(String assetId) =>
      AppSearchField.suggestionKey(_assetFieldName, assetId);
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('pm-schedule-form-assets-failed');
  /// The Job plan picker's own field name — the one string [jobPlanKey] and
  /// [jobPlanSuggestionKey] are both derived from (AGENTS.md §7). The
  /// catalogue is the whole plant's plans, so it is found by typing rather
  /// than scrolled to (ADR-0023, issue #190).
  static const String _jobPlanFieldName = 'pm-schedule-form-job-plan';

  static ValueKey<String> get jobPlanKey => AppSearchField.fieldKey(_jobPlanFieldName);

  /// One Job plan suggestion row's own `Key`, keyed by the Job plan's id
  /// (AGENTS.md §7).
  static ValueKey<String> jobPlanSuggestionKey(String jobPlanId) =>
      AppSearchField.suggestionKey(_jobPlanFieldName, jobPlanId);
  static const ValueKey<String> jobPlansFailedKey =
      ValueKey<String>('pm-schedule-form-job-plans-failed');
  static const ValueKey<String> basisKey = ValueKey<String>('pm-schedule-form-basis');
  static const ValueKey<String> intervalKey = ValueKey<String>('pm-schedule-form-interval');
  static const ValueKey<String> meterKey = ValueKey<String>('pm-schedule-form-meter');
  static const ValueKey<String> metersFailedKey = ValueKey<String>('pm-schedule-form-meters-failed');
  static const ValueKey<String> intervalMeterKey = ValueKey<String>('pm-schedule-form-interval-meter');
  static const ValueKey<String> anchorKey = ValueKey<String>('pm-schedule-form-anchor');
  static const ValueKey<String> anchorExplanationKey =
      ValueKey<String>('pm-schedule-form-anchor-explanation');
  static const ValueKey<String> leadTimeKey = ValueKey<String>('pm-schedule-form-lead-time');
  static const ValueKey<String> priorityKey = ValueKey<String>('pm-schedule-form-priority');
  static const ValueKey<String> nextDueKey = ValueKey<String>('pm-schedule-form-next-due');
  static const ValueKey<String> submitKey = ValueKey<String>('pm-schedule-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('pm-schedule-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('pm-schedule-form-failure');

  /// Opens the form over the schedule list — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider<PmSchedulesBloc>`.
  static Future<void> open(BuildContext context, {required String siteId}) {
    final bloc = context.read<PmSchedulesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<PmSchedulesBloc>.value(
        value: bloc,
        child: PmScheduleFormDialog(siteId: siteId),
      ),
    );
  }

  @override
  State<PmScheduleFormDialog> createState() => _PmScheduleFormDialogState();
}

enum _LoadStatus { loading, ready, failed }

/// Which of CONTEXT.md's two PM mechanisms this schedule runs on: elapsed time
/// or accumulated use (issue #79).
enum _IntervalBasis { days, meter }

class _PmScheduleFormDialogState extends State<PmScheduleFormDialog> {
  final TextEditingController _interval = TextEditingController();
  final TextEditingController _intervalMeter = TextEditingController();
  final TextEditingController _leadTime = TextEditingController(text: '7');

  _LoadStatus _assetsStatus = _LoadStatus.loading;
  _LoadStatus _plansStatus = _LoadStatus.loading;
  _LoadStatus _metersStatus = _LoadStatus.ready;
  List<Asset> _assets = const [];
  List<JobPlan> _jobPlans = const [];
  List<AssetMeter> _meters = const [];
  String? _assetsFailure;
  String? _plansFailure;
  String? _metersFailure;

  String? _assetId;
  String? _jobPlanId;
  String? _meterId;
  _IntervalBasis _basis = _IntervalBasis.days;
  PmScheduleAnchor _anchor = PmScheduleAnchor.completed;
  int _priority = 3;
  String? _nextDueOn;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadJobPlans();
  }

  @override
  void dispose() {
    _interval.dispose();
    _intervalMeter.dispose();
    _leadTime.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _assetsStatus = _LoadStatus.loading;
      _assetsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _assetsStatus = _LoadStatus.failed;
        _assetsFailure = PmSchedulesBloc.signedOutMessage;
      });
      return;
    }
    try {
      // Retired Assets are out of service and must not be offered.
      final assets = await context.read<MaintenanceApi>().fetchAssets(token, siteId: widget.siteId);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _assetsStatus = _LoadStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _assetsStatus = _LoadStatus.failed;
        _assetsFailure = error.message;
      });
    }
  }

  Future<void> _loadJobPlans() async {
    setState(() {
      _plansStatus = _LoadStatus.loading;
      _plansFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _plansStatus = _LoadStatus.failed;
        _plansFailure = PmSchedulesBloc.signedOutMessage;
      });
      return;
    }
    try {
      final plans = await context.read<MaintenanceApi>().fetchJobPlans(token, includeInactive: false);
      if (!mounted) return;
      setState(() {
        _jobPlans = plans;
        _plansStatus = _LoadStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _plansStatus = _LoadStatus.failed;
        _plansFailure = error.message;
      });
    }
  }

  // The Asset's cumulative meters, loaded when an Asset is chosen. Only a
  // cumulative meter can drive a schedule (ADR-0029), so a gauge is not
  // offered — the server would refuse it anyway.
  Future<void> _loadMeters(String assetId) async {
    setState(() {
      _metersStatus = _LoadStatus.loading;
      _metersFailure = null;
      _meters = const [];
      _meterId = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _metersStatus = _LoadStatus.failed;
        _metersFailure = PmSchedulesBloc.signedOutMessage;
      });
      return;
    }
    try {
      final meters = await context.read<MaintenanceApi>().fetchMeters(
            token,
            siteId: widget.siteId,
            assetId: assetId,
          );
      if (!mounted) return;
      setState(() {
        _meters = [for (final meter in meters) if (meter.isCumulative) meter];
        _metersStatus = _LoadStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _metersStatus = _LoadStatus.failed;
        _metersFailure = error.message;
      });
    }
  }

  void _onAssetChanged(String? id) {
    setState(() {
      _assetId = id;
      _meterId = null;
      _meters = const [];
      _metersStatus = _LoadStatus.ready;
    });
    if (id != null) _loadMeters(id);
  }

  num? get _intervalValue => num.tryParse(_interval.text.trim());
  num? get _intervalMeterValue => num.tryParse(_intervalMeter.text.trim());
  int? get _leadTimeValue => int.tryParse(_leadTime.text.trim());

  AssetMeter? get _selectedMeter {
    for (final meter in _meters) {
      if (meter.id == _meterId) return meter;
    }
    return null;
  }

  bool get _complete {
    final leadTime = _leadTimeValue;
    if (_assetId == null || _jobPlanId == null || leadTime == null || leadTime < 0) return false;
    if (_basis == _IntervalBasis.days) {
      final interval = _intervalValue;
      return interval != null && interval > 0 && interval == interval.roundToDouble();
    }
    final interval = _intervalMeterValue;
    return _meterId != null && interval != null && interval > 0;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final onMeter = _basis == _IntervalBasis.meter;
    context.read<PmSchedulesBloc>().add(
          PmScheduleCreateConfirmed(
            assetId: _assetId!,
            jobPlanId: _jobPlanId!,
            anchor: _anchor.wire,
            intervalDays: onMeter ? null : _intervalValue!.toInt(),
            assetMeterId: onMeter ? _meterId : null,
            intervalMeter: onMeter ? _intervalMeterValue : null,
            leadTimeDays: _leadTimeValue,
            priority: _priority,
            nextDueOn: onMeter ? null : _nextDueOn,
          ),
        );
  }

  void _onSchedulesChanged(BuildContext context, PmSchedulesState state) {
    if (!_awaiting || state is! PmSchedulesLoaded || state.isMutating) return;
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
    return BlocListener<PmSchedulesBloc, PmSchedulesState>(
      listener: _onSchedulesChanged,
      child: AlertDialog(
        title: const Text('Schedule preventive maintenance'),
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
                  onRetry: _loadAssets,
                  onChanged: _onAssetChanged,
                ),
                const SizedBox(height: Spacing.md),
                _JobPlanField(
                  status: _plansStatus,
                  jobPlans: _jobPlans,
                  failure: _plansFailure,
                  selectedId: _jobPlanId,
                  enabled: !_awaiting,
                  onRetry: _loadJobPlans,
                  onChanged: (id) => setState(() => _jobPlanId = id),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<_IntervalBasis>(
                  key: PmScheduleFormDialog.basisKey,
                  initialValue: _basis,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Comes round on',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<_IntervalBasis>(
                      value: _IntervalBasis.days,
                      child: Text('Elapsed time'),
                    ),
                    DropdownMenuItem<_IntervalBasis>(
                      value: _IntervalBasis.meter,
                      child: Text('Accumulated use'),
                    ),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _basis = value);
                        },
                ),
                const SizedBox(height: Spacing.md),
                if (_basis == _IntervalBasis.days)
                  TextField(
                    key: PmScheduleFormDialog.intervalKey,
                    controller: _interval,
                    enabled: !_awaiting,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Every how many days',
                      border: OutlineInputBorder(),
                    ),
                  )
                else ...[
                  _MeterField(
                    status: _metersStatus,
                    meters: _meters,
                    failure: _metersFailure,
                    selectedId: _meterId,
                    enabled: !_awaiting,
                    onRetry: () {
                      final assetId = _assetId;
                      if (assetId != null) _loadMeters(assetId);
                    },
                    onChanged: (id) => setState(() => _meterId = id),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: PmScheduleFormDialog.intervalMeterKey,
                    controller: _intervalMeter,
                    enabled: !_awaiting,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Every how much accumulated use',
                      helperText: _selectedMeter == null
                          ? 'Choose a cumulative meter first.'
                          : 'In ${_selectedMeter!.uomCode}, one interval past where the meter stands now.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<PmScheduleAnchor>(
                  key: PmScheduleFormDialog.anchorKey,
                  initialValue: _anchor,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'The interval rolls from',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final anchor in PmScheduleAnchor.values)
                      DropdownMenuItem<PmScheduleAnchor>(value: anchor, child: Text(anchor.label)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _anchor = value!),
                ),
                Padding(
                  key: PmScheduleFormDialog.anchorExplanationKey,
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(_anchor.explanation, style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: PmScheduleFormDialog.leadTimeKey,
                        controller: _leadTime,
                        enabled: !_awaiting,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Raise this many days early',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: PmScheduleFormDialog.priorityKey,
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem<int>(value: 1, child: Text('1 — most urgent')),
                          DropdownMenuItem<int>(value: 2, child: Text('2')),
                          DropdownMenuItem<int>(value: 3, child: Text('3')),
                          DropdownMenuItem<int>(value: 4, child: Text('4')),
                          DropdownMenuItem<int>(value: 5, child: Text('5 — least urgent')),
                        ],
                        onChanged: _awaiting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _priority = value);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                if (_basis == _IntervalBasis.days) ...[
                  AppDateField(
                    key: PmScheduleFormDialog.nextDueKey,
                    name: 'pm-schedule-next-due',
                    label: 'First due date (optional)',
                    helperText: 'Left blank, the first due date is the interval from today.',
                    value: _nextDueOn,
                    onChanged: (value) => setState(() => _nextDueOn = value),
                    optional: true,
                    enabled: !_awaiting,
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: PmScheduleFormDialog.failureKey,
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
            key: PmScheduleFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: PmScheduleFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Schedule'),
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

  final _LoadStatus status;
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
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: PmScheduleFormDialog.assetsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Assets could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _LoadStatus.ready:
        return AppSearchField<Asset>(
          name: PmScheduleFormDialog._assetFieldName,
          label: 'Asset',
          value: _selected,
          enabled: enabled,
          // A pick sets the dialog's own id — which also re-reads that Asset's
          // meters — and typing over the chosen Asset retires it, so this form
          // can never submit an id its own field has stopped showing
          // (ADR-0023 point 4).
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

class _JobPlanField extends StatelessWidget {
  const _JobPlanField({
    required this.status,
    required this.jobPlans,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _LoadStatus status;
  final List<JobPlan> jobPlans;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  /// The Job plan the dialog's own id currently names, or null — the same
  /// controlled-value agreement `_AssetField` keeps above.
  JobPlan? get _selected {
    for (final plan in jobPlans) {
      if (plan.id == selectedId) return plan;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: PmScheduleFormDialog.jobPlansFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Job plans could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _LoadStatus.ready:
        return AppSearchField<JobPlan>(
          name: PmScheduleFormDialog._jobPlanFieldName,
          label: 'Job plan',
          value: _selected,
          enabled: enabled,
          onChanged: (plan) => onChanged(plan?.id),
          onSelected: (plan) => onChanged(plan.id),
          // A dumb in-memory filter over the catalogue `initState` already
          // read, matching the Job plan's own name (ADR-0023, issue #190's
          // rule). The read is the same one it always was: active plans only,
          // because the server refuses an inactive one with a 400.
          fetchSuggestions: (term) async {
            final lower = term.toLowerCase();
            return [
              for (final plan in jobPlans)
                if (plan.name.toLowerCase().contains(lower)) plan,
            ];
          },
          suggestionBuilder: (context, plan) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Text(plan.name),
          ),
          idOf: (plan) => plan.id,
          displayStringFor: (plan) => plan.name,
        );
    }
  }
}

/// The chosen Asset's cumulative meters — the instrument an accumulated-use
/// schedule comes due on. A gauge is filtered out by the dialog before it ever
/// reaches here, so an empty list means "this Asset has no cumulative meter
/// yet", which the empty dropdown says by showing nothing to choose.
class _MeterField extends StatelessWidget {
  const _MeterField({
    required this.status,
    required this.meters,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _LoadStatus status;
  final List<AssetMeter> meters;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: PmScheduleFormDialog.metersFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The meters could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _LoadStatus.ready:
        return DropdownButtonFormField<String>(
          key: PmScheduleFormDialog.meterKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Meter',
            helperText: 'Only cumulative meters can drive a schedule.',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final meter in meters)
              DropdownMenuItem<String>(
                value: meter.id,
                child: Text('${meter.name} (${meter.code}) — ${meter.accumulatedLabel}'),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        );
    }
  }
}
