/// Adding people to an Assessment that is already assigned (issue #588,
/// ADR-0068, slice 6): the create form's assign group, as a dialog.
///
/// Org Units, crews and named Employees are chosen with the same search boxes
/// the create form uses and kept as chips (a crew's chip shows how many
/// Employees it holds), and under them the server says how many Employees the
/// group reaches (`GET /assessments/assign-preview`, asked through
/// `AssessmentDetailBloc`, so the number here and the number of Attempts the
/// confirm creates are one expansion). The confirm is off while the group is
/// empty. The dialog pops the group and sends nothing: the Screen dispatches the
/// write and shows a refusal where the person is looking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import '../widgets/notice_text.dart';
import 'assessment_create_bloc.dart' show AssessmentCreateGroupChanged;
import 'assessment_detail_bloc.dart';
import 'crew.dart';
import 'employee.dart';
import 'org_unit.dart';

class AssessmentAssignDialog extends StatefulWidget {
  const AssessmentAssignDialog({
    super.key,
    required this.peopleApi,
    required this.authGateway,
    required this.siteId,
  });

  final PeopleApi peopleApi;
  final AuthGateway authGateway;

  /// The Site the Assessment belongs to: the Org Unit search is within it.
  final String siteId;

  static const String orgUnitFieldName = 'assessment-assign-org-unit';
  static const String crewFieldName = 'assessment-assign-crew';
  static const String employeeFieldName = 'assessment-assign-employee';

  static ValueKey<String> get orgUnitSearchKey => AppSearchField.fieldKey(orgUnitFieldName);
  static ValueKey<String> orgUnitSuggestionKey(String id) =>
      AppSearchField.suggestionKey(orgUnitFieldName, id);
  static ValueKey<String> get crewSearchKey => AppSearchField.fieldKey(crewFieldName);
  static ValueKey<String> crewSuggestionKey(String id) =>
      AppSearchField.suggestionKey(crewFieldName, id);
  static ValueKey<String> get employeeSearchKey => AppSearchField.fieldKey(employeeFieldName);
  static ValueKey<String> employeeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(employeeFieldName, id);
  static ValueKey<String> orgUnitChipKey(String id) => ValueKey<String>('assessment-assign-unit-$id');
  static ValueKey<String> crewChipKey(String id) => ValueKey<String>('assessment-assign-crew-$id');
  static ValueKey<String> employeeChipKey(String id) => ValueKey<String>('assessment-assign-employee-$id');
  static const ValueKey<String> reachKey = ValueKey<String>('assessment-assign-reach');
  static const ValueKey<String> reachFailureKey = ValueKey<String>('assessment-assign-reach-failure');
  static final ValueKey<String> submitKey = AppDialog.actionKey('submit');
  static final ValueKey<String> backKey = AppDialog.actionKey('back');

  /// Opens the dialog over the detail Screen, handing across its own
  /// [AssessmentDetailBloc] (`showDialog`'s route sits outside the route-scoped
  /// provider). Completes with the group, or null when the person went back.
  static Future<AssessmentCreateGroupChanged?> open(BuildContext context, {required String siteId}) {
    final bloc = context.read<AssessmentDetailBloc>();
    final api = context.read<PeopleApi>();
    final auth = context.read<AuthGateway>();
    bloc.add(const AssessmentDetailGroupChanged(AssessmentCreateGroupChanged()));
    return showDialog<AssessmentCreateGroupChanged>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AssessmentDetailBloc>.value(
        value: bloc,
        child: AssessmentAssignDialog(peopleApi: api, authGateway: auth, siteId: siteId),
      ),
    );
  }

  @override
  State<AssessmentAssignDialog> createState() => _AssessmentAssignDialogState();
}

class _AssessmentAssignDialogState extends State<AssessmentAssignDialog> {
  List<OrgUnitNode> _orgUnits = const [];
  List<Crew> _crews = const [];
  List<Employee> _employees = const [];

  bool get _empty => _group.isEmpty;

  AssessmentCreateGroupChanged get _group =>
      AssessmentCreateGroupChanged(orgUnits: _orgUnits, crews: _crews, employees: _employees);

  void _changed() {
    setState(() {});
    context.read<AssessmentDetailBloc>().add(AssessmentDetailGroupChanged(_group));
  }

  Future<List<OrgUnitNode>> _searchOrgUnits(String term) async {
    final token = widget.authGateway.currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentDetailBloc.signedOutMessage);
    final result = await widget.peopleApi.searchOrgUnits(token, siteId: widget.siteId, search: term);
    return result.orgUnits;
  }

  Future<List<Crew>> _searchCrews(String term) async {
    final token = widget.authGateway.currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentDetailBloc.signedOutMessage);
    return widget.peopleApi.searchCrews(token, siteId: widget.siteId, search: term);
  }

  Future<List<Employee>> _searchEmployees(String term) async {
    final token = widget.authGateway.currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentDetailBloc.signedOutMessage);
    return widget.peopleApi.fetchEmployees(token, search: term, limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<AssessmentDetailBloc>().state;
    final loaded = state is AssessmentDetailLoaded ? state : null;
    final preview = loaded?.preview;

    return AppDialog(
      title: l10n.assessmentAssignTitle,
      description: l10n.assessmentAssignGroupHelper,
      size: AppDialogSize.picker,
      actions: [
        AppDialogAction(
          id: 'back',
          label: l10n.commonBack,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'submit',
          label: l10n.assessmentAssignConfirm,
          onPressed: _empty ? null : () => Navigator.of(context).pop(_group),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSearchField<OrgUnitNode>(
            name: AssessmentAssignDialog.orgUnitFieldName,
            label: l10n.assessmentAssignOrgUnitLabel,
            value: null,
            onChanged: (_) {},
            onSelected: (picked) {
              if (_orgUnits.any((unit) => unit.id == picked.id)) return;
              _orgUnits = [..._orgUnits, picked];
              _changed();
            },
            fetchSuggestions: _searchOrgUnits,
            suggestionBuilder: (context, node) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              child: Text('${node.name} · ${node.code}'),
            ),
            idOf: (node) => node.id,
            displayStringFor: (node) => node.name,
            codeOf: (node) => node.code,
          ),
          const SizedBox(height: Spacing.sm),
          AppSearchField<Crew>(
            name: AssessmentAssignDialog.crewFieldName,
            label: l10n.assessmentAssignCrewLabel,
            value: null,
            onChanged: (_) {},
            onSelected: (picked) {
              if (_crews.any((crew) => crew.id == picked.id)) return;
              _crews = [..._crews, picked];
              _changed();
            },
            fetchSuggestions: _searchCrews,
            suggestionBuilder: (context, crew) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              child: Text(l10n.assessmentCrewWithCount(crew.name, crew.employeeCount)),
            ),
            idOf: (crew) => crew.id,
            displayStringFor: (crew) => crew.name,
            codeOf: (crew) => crew.code,
          ),
          const SizedBox(height: Spacing.sm),
          AppSearchField<Employee>(
            name: AssessmentAssignDialog.employeeFieldName,
            label: l10n.assessmentAssignEmployeeLabel,
            value: null,
            onChanged: (_) {},
            onSelected: (picked) {
              if (_employees.any((employee) => employee.id == picked.id)) return;
              _employees = [..._employees, picked];
              _changed();
            },
            fetchSuggestions: _searchEmployees,
            suggestionBuilder: (context, employee) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              child: Text('${employee.displayName} · ${employee.employeeNo}'),
            ),
            idOf: (employee) => employee.id,
            displayStringFor: (employee) => employee.displayName,
            codeOf: (employee) => employee.employeeNo,
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              for (final unit in _orgUnits)
                InputChip(
                  key: AssessmentAssignDialog.orgUnitChipKey(unit.id),
                  label: Text(unit.name),
                  onDeleted: () {
                    _orgUnits = [
                      for (final other in _orgUnits)
                        if (other.id != unit.id) other,
                    ];
                    _changed();
                  },
                ),
              for (final crew in _crews)
                InputChip(
                  key: AssessmentAssignDialog.crewChipKey(crew.id),
                  label: Text(l10n.assessmentCrewWithCount(crew.name, crew.employeeCount)),
                  onDeleted: () {
                    _crews = [
                      for (final other in _crews)
                        if (other.id != crew.id) other,
                    ];
                    _changed();
                  },
                ),
              for (final employee in _employees)
                InputChip(
                  key: AssessmentAssignDialog.employeeChipKey(employee.id),
                  label: Text(employee.displayName),
                  onDeleted: () {
                    _employees = [
                      for (final other in _employees)
                        if (other.id != employee.id) other,
                    ];
                    _changed();
                  },
                ),
            ],
          ),
          if (loaded?.previewing ?? false) ...[
            const SizedBox(height: Spacing.sm),
            const LinearProgressIndicator(),
          ],
          if (preview != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              l10n.assessmentReachCount(preview.count),
              key: AssessmentAssignDialog.reachKey,
              style: theme.textTheme.labelLarge,
            ),
            if (preview.unresolvedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: NoticeText(
                  l10n.assessmentReachUnresolved(
                    preview.unresolvedCount,
                    preview.unresolvedNames.join(', '),
                  ),
                ),
              ),
          ],
          if (loaded?.previewFailure != null) ...[
            const SizedBox(height: Spacing.sm),
            NoticeText(loaded!.previewFailure!, key: AssessmentAssignDialog.reachFailureKey),
          ],
        ],
      ),
    );
  }
}
