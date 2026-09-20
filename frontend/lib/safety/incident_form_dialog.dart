/// Recording a Safety incident (issue #226): when it occurred, what kind of
/// event it was, where it sits on the severity ladder, a description, the
/// Asset involved if there is one, and the immediate action taken.
///
/// Addressed rather than popped — `/safety/incidents/record` (ADR-0021, the
/// binding design comment on #223) — so a refresh lands on the register with
/// the form open, and a widget test drives it through the router the way
/// `nonconformances_test.dart` drives its own record form.
///
/// **Incident type and severity level are `DropdownButtonFormField`s, not
/// search fields** — seven and six fixed values, `docs/frontend-layout.md`'s
/// set-size rule. **The severity dropdown renders in ladder order — no
/// injury through fatality, never alphabetical — and marks where the
/// recordable line falls** (the binding design comment on #223): a rung at or
/// above `medical_treatment` is labelled "recordable" in the menu.
///
/// The optional Asset and the optional Employee involved are both
/// `AppSearchField`s (ADR-0023) — the Asset filters the Site's own register
/// the dialog already read, in memory; the Employee involved searches the
/// platform-wide directory through the server the same way the Action form's
/// own owner picker does, since the directory is a set nobody can scan
/// (`docs/frontend-layout.md`'s trigger).
///
/// No injury type, no body part and no anonymous option anywhere in this
/// form — issue #224 is the ticket that classifies an injury, and ADR-0036
/// is the decision that there is no anonymous path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../maintenance/maintenance_api.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import '../widgets/app_search_field.dart';
import 'safety_incident.dart';
import 'safety_incidents_bloc.dart';

/// How the optional Asset list is being read — the same three states, and
/// the same reason, as the Non-conformance form's own Asset picker.
enum _AssetsStatus { loading, ready, failed }

class SafetyIncidentFormDialog extends StatefulWidget {
  const SafetyIncidentFormDialog({super.key, required this.siteId});

  /// The Site the register is showing. The Org Unit chooser opens on it, the
  /// Asset list is read from it, and the recording is sent to it.
  final String siteId;

  static const ValueKey<String> incidentTypeKey =
      ValueKey<String>('safety-incident-form-type');
  static const ValueKey<String> severityKey = ValueKey<String>('safety-incident-form-severity');
  static const ValueKey<String> descriptionKey =
      ValueKey<String>('safety-incident-form-description');
  static const ValueKey<String> immediateActionKey =
      ValueKey<String>('safety-incident-form-immediate-action');
  static const ValueKey<String> occurredAtKey =
      ValueKey<String>('safety-incident-form-occurred-at');
  static const ValueKey<String> reportedAtKey =
      ValueKey<String>('safety-incident-form-reported-at');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-form-failure');
  static const ValueKey<String> assetsFailedKey =
      ValueKey<String>('safety-incident-form-assets-failed');
  static const ValueKey<String> chosenOrgUnitKey =
      ValueKey<String>('safety-incident-form-chosen-org-unit');

  /// The Asset picker's own name, which its `Key`s are derived from.
  static const String assetFieldName = 'safety-incident-asset';

  static ValueKey<String> assetFieldKey() => AppSearchField.fieldKey(assetFieldName);

  static ValueKey<String> assetSuggestionKey(String id) =>
      AppSearchField.suggestionKey(assetFieldName, id);

  /// The Employee involved picker's own name, and the two `Key`s an
  /// `AppSearchField` derives from it (AGENTS.md §7).
  static const String employeeFieldName = 'safety-incident-employee';

  static ValueKey<String> employeeFieldKey() => AppSearchField.fieldKey(employeeFieldName);

  static ValueKey<String> employeeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(employeeFieldName, id);

  @override
  State<SafetyIncidentFormDialog> createState() => _SafetyIncidentFormDialogState();
}

class _SafetyIncidentFormDialogState extends State<SafetyIncidentFormDialog> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _immediateAction = TextEditingController();

  String? _incidentType;
  String? _severityLevel;
  String? _assetId;
  Employee? _employee;
  OrgUnitNode? _orgUnit;

  // Defaulted to now rather than left null: occurredAt is required, and a
  // form that opened with no value would force every caller through the
  // picker just to record "now" — the common case.
  DateTime? _occurredAt = DateTime.now();
  DateTime? _reportedAt;

  List<Asset> _assets = const [];
  _AssetsStatus _assetsStatus = _AssetsStatus.loading;
  String? _assetsFailure;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    _description.dispose();
    _immediateAction.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _assetsStatus = _AssetsStatus.loading;
      _assetsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = SafetyIncidentsBloc.signedOutMessage;
      });
      return;
    }
    try {
      final assets =
          await context.read<MaintenanceApi>().fetchAssets(token, siteId: widget.siteId);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _assetsStatus = _AssetsStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _assetsStatus = _AssetsStatus.failed;
        _assetsFailure = error.message;
      });
    }
  }

  bool get _complete =>
      _orgUnit != null &&
      _incidentType != null &&
      _severityLevel != null &&
      _occurredAt != null &&
      _description.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });

    final description = _description.text.trim();
    final immediateAction = _immediateAction.text.trim();

    context.read<SafetyIncidentsBloc>().add(
          SafetyIncidentRecordConfirmed(
            orgUnitId: _orgUnit!.id,
            occurredAt: _occurredAt!.toUtc().toIso8601String(),
            incidentType: _incidentType!,
            severityLevel: _severityLevel!,
            description: description,
            assetId: _assetId,
            employeeId: _employee?.id,
            reportedAt: _reportedAt?.toUtc().toIso8601String(),
            immediateAction: immediateAction.isEmpty ? null : immediateAction,
          ),
        );
  }

  /// Whether this form has finished with its one act — the same guard
  /// `NonconformanceFormDialog._done` keeps, and for the same reason: the
  /// Bloc emits twice on the way out (once when the recording lands, once
  /// when the re-read answers), and both look like success to this listener.
  bool _done = false;

  void _onRegisterChanged(BuildContext context, SafetyIncidentsState state) {
    if (_done || !_awaiting || state is! SafetyIncidentsLoaded || state.isRecording) return;
    if (state.recordFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.recordFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  void _onOrgUnitSiteChanged() {
    setState(() => _orgUnit = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<SafetyIncidentsBloc, SafetyIncidentsState>(
      listener: _onRegisterChanged,
      child: BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
        listenWhen: (previous, current) => previous.siteId != current.siteId,
        listener: (context, state) => _onOrgUnitSiteChanged(),
        child: AlertDialog(
          title: const Text('Record a Safety incident'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: Spacing.md,
                    runSpacing: Spacing.sm,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String?>(
                          key: SafetyIncidentFormDialog.incidentTypeKey,
                          initialValue: _incidentType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Incident type',
                            helperText: 'What kind of event this was.',
                            border: OutlineInputBorder(),
                          ),
                          items: IncidentType.dropdownItems(),
                          onChanged: _awaiting
                              ? null
                              : (type) => setState(() => _incidentType = type),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String?>(
                          key: SafetyIncidentFormDialog.severityKey,
                          initialValue: _severityLevel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Severity',
                            helperText: 'The worst actual outcome to a person. Ladder order.',
                            border: OutlineInputBorder(),
                          ),
                          // Ladder order, never alphabetical, and marking
                          // where the recordable line falls (the binding
                          // design comment on #223) — built once by
                          // SeverityLevel.dropdownItems and shared with
                          // FloorSafetyIncidentDialog.
                          items: SeverityLevel.dropdownItems(),
                          onChanged: _awaiting
                              ? null
                              : (level) => setState(() => _severityLevel = level),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: SafetyIncidentFormDialog.descriptionKey,
                    controller: _description,
                    enabled: !_awaiting,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      helperText: 'What happened.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: SafetyIncidentFormDialog.immediateActionKey,
                    controller: _immediateAction,
                    enabled: !_awaiting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Immediate action (optional)',
                      helperText: 'What was done at once.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
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
                  AppSearchField<Employee>(
                    name: SafetyIncidentFormDialog.employeeFieldName,
                    label: 'Employee involved (optional)',
                    helperText: 'Who was hurt, if anyone.',
                    value: _employee,
                    enabled: !_awaiting,
                    onChanged: (employee) => setState(() => _employee = employee),
                    onSelected: (employee) => setState(() => _employee = employee),
                    fetchSuggestions: (term) async {
                      final token = context.read<AuthGateway>().currentAccessToken;
                      if (token == null) return const [];
                      return context.read<PeopleApi>().fetchEmployees(token, search: term);
                    },
                    suggestionBuilder: (context, employee) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(employee.displayName),
                    ),
                    idOf: (employee) => employee.id,
                    displayStringFor: (employee) => employee.displayName,
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateTimeField(
                    key: SafetyIncidentFormDialog.occurredAtKey,
                    name: 'safety-incident-occurred-at',
                    label: 'Occurred at',
                    helperText: 'When it happened. This is what decides the production day and '
                        'shift it is filed against.',
                    value: _occurredAt,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _occurredAt = value),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppDateTimeField(
                    key: SafetyIncidentFormDialog.reportedAtKey,
                    name: 'safety-incident-reported-at',
                    label: 'Reported at (optional)',
                    helperText: 'When it was reported, if that is not now.',
                    value: _reportedAt,
                    optional: true,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() => _reportedAt = value),
                  ),
                  const SizedBox(height: Spacing.lg),
                  OrgUnitChooser(
                    selectedId: _orgUnit?.id,
                    enabled: !_awaiting,
                    showSitePicker: false,
                    title: 'Where it happened',
                    description: 'Choose the Org Unit the incident occurred at. This is what '
                        'decides who may act on it.',
                    onSelected: (node) => setState(() => _orgUnit = node),
                  ),
                  if (_orgUnit != null)
                    Padding(
                      key: SafetyIncidentFormDialog.chosenOrgUnitKey,
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        'This Safety incident will be recorded at ${_orgUnit!.name}.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (_failure != null)
                    Padding(
                      key: SafetyIncidentFormDialog.failureKey,
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Text(
                        _failure!,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: SafetyIncidentFormDialog.cancelKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: SafetyIncidentFormDialog.submitKey,
              onPressed: _complete && !_awaiting ? _submit : null,
              child: const Text('Record it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The optional Asset picker: a search field over the Site's register, or the
/// reason it could not be read — mirrors `NonconformanceFormDialog`'s own
/// `_AssetField` exactly.
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
          key: SafetyIncidentFormDialog.assetsFailedKey,
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
          name: SafetyIncidentFormDialog.assetFieldName,
          label: 'Asset (optional)',
          helperText: 'Which machine, if the incident was on one. It must sit at that Org Unit.',
          value: _selected,
          enabled: enabled,
          onChanged: (asset) => onChanged(asset?.id),
          onSelected: (asset) => onChanged(asset.id),
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
