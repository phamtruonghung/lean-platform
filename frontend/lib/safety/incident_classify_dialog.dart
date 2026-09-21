/// Classifying a Safety incident's injury (issue #224, ADR-0037): who was
/// hurt, what the injury was, and where on the body.
///
/// Addressed rather than popped — `/safety/incidents/:id/classify` (ADR-0021,
/// the binding design comment on #223). The Screen offers the address only to
/// a caller holding Safety authority at the incident's Org Unit, and this
/// dialog asks the same question again in its own build: the API refuses
/// anyone else with a 403, and nobody should be shown a form whose only
/// possible answer is a refusal.
///
/// **The one dialog in this Module whose result most callers may not read
/// back.** The three fields it writes are the three ADR-0037 restricts, so the
/// record returned by the write carries them only for a caller allowed to read
/// them — a holder of Safety authority, or the injured person's own Account.
/// That is why the detail Screen's own rendering keys off
/// `SafetyIncident.injuryDetailsVisible` rather than assuming that having
/// written a value means being able to see it.
///
/// **Three pickers, each three-state.** Absent leaves a field alone, an
/// explicit clear empties it, a pick sets it — which is the contract
/// `classifySafetyIncident` (safety-incidents.js) keeps at the other end, and
/// it exists because a classification is three independent facts arrived at at
/// different moments: who was hurt is known immediately, what the injury was
/// often only after a clinic visit.
///
/// The Employee searches the platform-wide directory through the server, the
/// same way the record form's own picker does (the directory is a set nobody
/// can scan — `docs/frontend-layout.md`'s trigger). The **Injury type** and
/// **Body part** are `AppSearchField`s over the list this dialog already read
/// in full (the binding design comment on #223: catalogues that grow past a
/// dozen in any real plant), filtering in memory — **no `search` parameter is
/// added to either endpoint** (#190's own rule).
///
/// Deactivated catalogue entries are not read here at all: a retired entry is
/// excluded from the choices offered to whoever is classifying, and stays
/// perfectly readable on an incident that already names it, which is the
/// incident's own joined row rather than this list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/failure_state.dart';
import 'body_part.dart';
import 'incident_detail_bloc.dart';
import 'injury_type.dart';
import 'safety_api.dart';
import 'safety_incident.dart';

/// How the two catalogues are being read — the same three states, and the same
/// reason, as the record form's own Asset picker.
enum _CatalogueStatus { loading, ready, failed }

class SafetyIncidentClassifyDialog extends StatefulWidget {
  const SafetyIncidentClassifyDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-classify-loading');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-classify-refused');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-classify-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-classify-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-classify-failure');
  static const ValueKey<String> cataloguesFailedKey =
      ValueKey<String>('safety-incident-classify-catalogues-failed');
  static const ValueKey<String> cataloguesRetryKey =
      ValueKey<String>('safety-incident-classify-catalogues-retry');
  static const ValueKey<String> clearEmployeeKey =
      ValueKey<String>('safety-incident-classify-clear-employee');
  static const ValueKey<String> clearInjuryTypeKey =
      ValueKey<String>('safety-incident-classify-clear-injury-type');
  static const ValueKey<String> clearBodyPartKey =
      ValueKey<String>('safety-incident-classify-clear-body-part');

  /// The three pickers' own names, and the `Key`s an `AppSearchField` derives
  /// from each (AGENTS.md §7).
  static const String employeeFieldName = 'safety-incident-classify-employee';
  static const String injuryTypeFieldName = 'safety-incident-classify-injury-type';
  static const String bodyPartFieldName = 'safety-incident-classify-body-part';

  static ValueKey<String> employeeFieldKey() => AppSearchField.fieldKey(employeeFieldName);
  static ValueKey<String> employeeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(employeeFieldName, id);

  static ValueKey<String> injuryTypeFieldKey() => AppSearchField.fieldKey(injuryTypeFieldName);
  static ValueKey<String> injuryTypeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(injuryTypeFieldName, id);

  static ValueKey<String> bodyPartFieldKey() => AppSearchField.fieldKey(bodyPartFieldName);
  static ValueKey<String> bodyPartSuggestionKey(String id) =>
      AppSearchField.suggestionKey(bodyPartFieldName, id);

  @override
  State<SafetyIncidentClassifyDialog> createState() => _SafetyIncidentClassifyDialogState();
}

class _SafetyIncidentClassifyDialogState extends State<SafetyIncidentClassifyDialog> {
  Employee? _employee;
  InjuryType? _injuryType;
  BodyPart? _bodyPart;

  // Whether the caller has actually decided something about each field. This
  // is the three-state contract, and it is a flag rather than an inference off
  // the value: the form opens showing what the record already holds, so "the
  // field is filled in" says nothing about whether this caller changed it. A
  // key reaches the request only when its flag is true.
  bool _employeeTouched = false;
  bool _injuryTypeTouched = false;
  bool _bodyPartTouched = false;

  // Whether the caller has asked for a field to be emptied. Distinct from a
  // null pick, which only means "nothing chosen": `AppSearchField` reports
  // null when its text is typed over, which is not the same act as saying
  // "there is no injured Employee on this record".
  bool _clearEmployee = false;
  bool _clearInjuryType = false;
  bool _clearBodyPart = false;

  List<InjuryType> _injuryTypes = const [];
  List<BodyPart> _bodyParts = const [];
  _CatalogueStatus _catalogues = _CatalogueStatus.loading;
  String? _cataloguesFailure;

  bool _awaiting = false;
  bool _done = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    // All three fields are seeded from the **incident's own row**, never from
    // the catalogues this dialog is about to read. That is deliberate: a
    // catalogue entry that has since been deactivated is not in the list of
    // choices any more, and seeding from the list would silently blank a
    // retired classification the record legitimately still carries.
    final incident = widget.incident;

    final employeeId = incident.employeeId;
    final employeeName = incident.employeeName;
    if (employeeId != null && employeeName != null) {
      // A display-only stand-in: the incident carries the injured Employee's
      // id and name and nothing else, which is all this field renders. It is
      // replaced wholesale the moment the caller picks a different person.
      _employee = Employee(
        id: employeeId,
        employeeNo: '',
        displayName: employeeName,
        employmentType: '',
        isActive: true,
        orgUnitName: null,
        jobRoleName: null,
      );
    }

    final injuryTypeId = incident.injuryTypeId;
    if (injuryTypeId != null) {
      _injuryType = InjuryType(
        id: injuryTypeId,
        code: incident.injuryTypeCode ?? '',
        name: incident.injuryTypeName ?? '',
        isActive: true,
      );
    }

    final bodyPartId = incident.bodyPartId;
    if (bodyPartId != null) {
      _bodyPart = BodyPart(
        id: bodyPartId,
        code: incident.bodyPartCode ?? '',
        name: incident.bodyPartName ?? '',
        region: incident.bodyPartRegion ?? BodyPartRegion.other,
        isActive: true,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalogues());
  }

  Future<void> _loadCatalogues() async {
    setState(() {
      _catalogues = _CatalogueStatus.loading;
      _cataloguesFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _catalogues = _CatalogueStatus.failed;
        _cataloguesFailure = SafetyIncidentDetailBloc.signedOutMessage;
      });
      return;
    }
    try {
      final api = context.read<SafetyApi>();
      final injuryTypes = await api.fetchInjuryTypes(token);
      final bodyParts = await api.fetchBodyParts(token);
      if (!mounted) return;
      setState(() {
        // The choices, and only the choices. What the record already holds was
        // seeded in initState from the record itself — see there for why a
        // deactivated entry must not be looked up in this list.
        _injuryTypes = injuryTypes;
        _bodyParts = bodyParts;
        _catalogues = _CatalogueStatus.ready;
      });
    } on SafetyApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogues = _CatalogueStatus.failed;
        _cataloguesFailure = error.message;
      });
    }
  }

  /// Whether this form asks for anything at all. A form that opened on an
  /// already-classified incident and was then submitted untouched would
  /// otherwise re-send three values nobody changed — and an empty
  /// classification is a 400 from the API, so the gate closes rather than
  /// sending one either way.
  bool get _asksForSomething => _employeeTouched || _injuryTypeTouched || _bodyPartTouched;

  void _submit() {
    if (!_asksForSomething || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(
          SafetyIncidentClassified(
            employeeId: _employeeTouched && !_clearEmployee ? _employee?.id : null,
            clearEmployee: _employeeTouched && _clearEmployee,
            injuryTypeId: _injuryTypeTouched && !_clearInjuryType ? _injuryType?.id : null,
            clearInjuryType: _injuryTypeTouched && _clearInjuryType,
            bodyPartId: _bodyPartTouched && !_clearBodyPart ? _bodyPart?.id : null,
            clearBodyPart: _bodyPartTouched && _clearBodyPart,
          ),
        );
  }

  void _onDetailChanged(BuildContext context, SafetyIncidentDetailState state) {
    if (_done || !_awaiting || state is! SafetyIncidentDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incident = widget.incident;

    // Read here, in a build, for the reason the Screen reads it there: a value
    // frozen when the route first built would answer for a half-known Account.
    if (!holdsSafetyAuthority(context, incident.orgUnitId)) {
      return AlertDialog(
        key: SafetyIncidentClassifyDialog.refusedKey,
        content: const Text(
          "Classifying the injury needs Safety authority at this Safety incident's Org Unit.",
        ),
      );
    }

    // The no-injury rung carries no classification, for anybody: the ladder's
    // own CHECK forbids an injury type and a body part there. The Screen does
    // not offer this address on that rung, and this is the same rule said
    // again where an address typed by hand cannot get round it.
    if (!incident.hasInjurySection) {
      return AlertDialog(
        key: SafetyIncidentClassifyDialog.refusedKey,
        content: Text(
          '${incident.incidentNo} sits on the no-injury rung. Nobody was hurt, so there is '
          'nothing to classify — correct the severity first if that is wrong.',
        ),
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Classify the injury'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Who was hurt, what the injury was and where on the body. These three '
                  'are read only by a holder of Safety authority for this area and by the '
                  "injured person's own Account.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                AppSearchField<Employee>(
                  name: SafetyIncidentClassifyDialog.employeeFieldName,
                  label: 'Injured Employee',
                  helperText: 'Who was hurt.',
                  value: _employee,
                  enabled: !_awaiting,
                  onChanged: (employee) => setState(() => _employee = employee),
                  onSelected: (employee) => setState(() {
                    _employee = employee;
                    _employeeTouched = true;
                    _clearEmployee = false;
                  }),
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
                _ClearRow(
                  clearKey: SafetyIncidentClassifyDialog.clearEmployeeKey,
                  label: 'Clear the injured Employee',
                  value: _clearEmployee,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() {
                    _clearEmployee = value;
                    _employeeTouched = value;
                    if (value) _employee = null;
                  }),
                ),
                const SizedBox(height: Spacing.md),
                if (_catalogues == _CatalogueStatus.loading)
                  const Padding(
                    key: SafetyIncidentClassifyDialog.loadingKey,
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_catalogues == _CatalogueStatus.failed)
                  PlatformFailureState(
                    key: SafetyIncidentClassifyDialog.cataloguesFailedKey,
                    title: 'The Injury type and Body part catalogues could not be read',
                    message: _cataloguesFailure!,
                    retryKey: SafetyIncidentClassifyDialog.cataloguesRetryKey,
                    onRetry: _loadCatalogues,
                  )
                else ...[
                  AppSearchField<InjuryType>(
                    name: SafetyIncidentClassifyDialog.injuryTypeFieldName,
                    label: 'Injury type',
                    helperText: 'What the injury was.',
                    value: _injuryType,
                    enabled: !_awaiting,
                    onChanged: (type) => setState(() => _injuryType = type),
                    onSelected: (type) => setState(() {
                      _injuryType = type;
                      _injuryTypeTouched = true;
                      _clearInjuryType = false;
                    }),
                    // Filters the list this dialog already read — no request
                    // reaches the wire, and no endpoint gains a `search`
                    // parameter (#190's own rule).
                    fetchSuggestions: (term) async => [
                      for (final type in _injuryTypes)
                        if (type.label.toLowerCase().contains(term.toLowerCase())) type,
                    ],
                    suggestionBuilder: (context, type) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(type.label),
                    ),
                    idOf: (type) => type.id,
                    displayStringFor: (type) => type.label,
                  ),
                  _ClearRow(
                    clearKey: SafetyIncidentClassifyDialog.clearInjuryTypeKey,
                    label: 'Clear the Injury type',
                    value: _clearInjuryType,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() {
                      _clearInjuryType = value;
                      _injuryTypeTouched = value;
                      if (value) _injuryType = null;
                    }),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppSearchField<BodyPart>(
                    name: SafetyIncidentClassifyDialog.bodyPartFieldName,
                    label: 'Body part',
                    helperText: 'Where on the body.',
                    value: _bodyPart,
                    enabled: !_awaiting,
                    onChanged: (part) => setState(() => _bodyPart = part),
                    onSelected: (part) => setState(() {
                      _bodyPart = part;
                      _bodyPartTouched = true;
                      _clearBodyPart = false;
                    }),
                    fetchSuggestions: (term) async => [
                      for (final part in _bodyParts)
                        if (part.label.toLowerCase().contains(term.toLowerCase())) part,
                    ],
                    suggestionBuilder: (context, part) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(part.label),
                    ),
                    idOf: (part) => part.id,
                    displayStringFor: (part) => part.label,
                  ),
                  _ClearRow(
                    clearKey: SafetyIncidentClassifyDialog.clearBodyPartKey,
                    label: 'Clear the Body part',
                    value: _clearBodyPart,
                    enabled: !_awaiting,
                    onChanged: (value) => setState(() {
                      _clearBodyPart = value;
                      _bodyPartTouched = value;
                      if (value) _bodyPart = null;
                    }),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: SafetyIncidentClassifyDialog.failureKey,
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
            key: SafetyIncidentClassifyDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyIncidentClassifyDialog.submitKey,
            onPressed: _asksForSomething && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Save the classification'),
          ),
        ],
      ),
    );
  }
}

/// The explicit clear beside each picker. It exists because `null` already
/// means "nothing chosen" and cannot also mean "empty what is there": a
/// mistaken pick has to be removable, not only replaceable, and the API's own
/// contract is absent-leaves-alone / null-clears.
class _ClearRow extends StatelessWidget {
  const _ClearRow({
    required this.clearKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ValueKey<String> clearKey;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: clearKey,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: enabled ? (checked) => onChanged(checked ?? false) : null,
    );
  }
}
