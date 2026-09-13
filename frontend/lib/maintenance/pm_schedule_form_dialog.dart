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
import 'asset.dart';
import 'job_plan.dart';
import 'maintenance_api.dart';
import 'pm_schedule.dart';
import 'pm_schedules_bloc.dart';

class PmScheduleFormDialog extends StatefulWidget {
  const PmScheduleFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  static const ValueKey<String> assetKey = ValueKey<String>('pm-schedule-form-asset');
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('pm-schedule-form-assets-failed');
  static const ValueKey<String> jobPlanKey = ValueKey<String>('pm-schedule-form-job-plan');
  static const ValueKey<String> jobPlansFailedKey =
      ValueKey<String>('pm-schedule-form-job-plans-failed');
  static const ValueKey<String> intervalKey = ValueKey<String>('pm-schedule-form-interval');
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

class _PmScheduleFormDialogState extends State<PmScheduleFormDialog> {
  final TextEditingController _interval = TextEditingController();
  final TextEditingController _leadTime = TextEditingController(text: '7');

  _LoadStatus _assetsStatus = _LoadStatus.loading;
  _LoadStatus _plansStatus = _LoadStatus.loading;
  List<Asset> _assets = const [];
  List<JobPlan> _jobPlans = const [];
  String? _assetsFailure;
  String? _plansFailure;

  String? _assetId;
  String? _jobPlanId;
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

  num? get _intervalValue => num.tryParse(_interval.text.trim());
  int? get _leadTimeValue => int.tryParse(_leadTime.text.trim());

  bool get _complete {
    final interval = _intervalValue;
    final leadTime = _leadTimeValue;
    return _assetId != null &&
        _jobPlanId != null &&
        interval != null &&
        interval > 0 &&
        interval == interval.roundToDouble() &&
        leadTime != null &&
        leadTime >= 0;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<PmSchedulesBloc>().add(
          PmScheduleCreateConfirmed(
            assetId: _assetId!,
            jobPlanId: _jobPlanId!,
            intervalDays: _intervalValue!.toInt(),
            anchor: _anchor.wire,
            leadTimeDays: _leadTimeValue,
            priority: _priority,
            nextDueOn: _nextDueOn,
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
                  onChanged: (id) => setState(() => _assetId = id),
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
                ),
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
        return DropdownButtonFormField<String>(
          key: PmScheduleFormDialog.assetKey,
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
        return DropdownButtonFormField<String>(
          key: PmScheduleFormDialog.jobPlanKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Job plan', border: OutlineInputBorder()),
          items: [
            for (final plan in jobPlans)
              DropdownMenuItem<String>(value: plan.id, child: Text(plan.name)),
          ],
          onChanged: enabled ? onChanged : null,
        );
    }
  }
}
