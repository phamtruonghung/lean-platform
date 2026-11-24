/// The create form for an Assessment (issue #588, ADR-0068, slice 3), at
/// `/assessments/new`.
///
/// **Six facts and a group.** The process whose bank a paper is drawn from, a
/// title, the paper size (10 or 15), how long a sitting runs, the pass mark and
/// an optional due date — then the people it reaches: Org Units and named
/// Employees as chips, with the count the server says that group reaches under
/// them (`GET /assessments/assign-preview`).
///
/// **Two numbers move together, and both are defaults you can override.**
/// `minutes` starts at two per Question (20 for 10, 30 for 15) and `passMark` at
/// 80 % rounded up (8 or 12); changing the paper size restates both only while
/// they are still untouched, so a person who typed 25 minutes keeps 25.
///
/// **The live bank count is the process's own.** It is what the paper size is
/// checked against — the draw is an exact match on the process, never its
/// children (spec section 3.1) — so a size larger than the bank is visible here,
/// before the server refuses it, and the server still refuses it.
///
/// **The form is the widget's; the server's answers are the Bloc's.** Text and
/// numbers live in controllers, as in `AssessmentQuestionFormDialog`; the Sites,
/// the active count, the reach and the submit live in `AssessmentCreateBloc`.
///
/// Crews are not offered here: they have no client surface yet
/// (`PeopleApi.createAssignment`'s own note). The route takes `crewIds`, and the
/// register's assign action is slice 6.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../people/employee.dart';
import '../people/org_unit.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_search_field.dart';
import '../widgets/failure_state.dart';
import '../widgets/notice_text.dart';
import '../widgets/skeleton_list.dart';
import 'assessment_create_bloc.dart';

class AssessmentCreateScreen extends StatefulWidget {
  const AssessmentCreateScreen({super.key});

  static const double maxWidth = 760;

  static const String processFieldName = 'assessment-create-process';
  static const String orgUnitFieldName = 'assessment-create-org-unit';
  static const String employeeFieldName = 'assessment-create-employee';

  static const ValueKey<String> siteKey = ValueKey<String>('assessment-create-site');
  static const ValueKey<String> titleKey = ValueKey<String>('assessment-create-title');
  static const ValueKey<String> minutesKey = ValueKey<String>('assessment-create-minutes');
  static const ValueKey<String> passMarkKey = ValueKey<String>('assessment-create-pass-mark');
  static const ValueKey<String> activeCountKey = ValueKey<String>('assessment-create-active-count');
  static const ValueKey<String> reachKey = ValueKey<String>('assessment-create-reach');
  static const ValueKey<String> reachFailureKey = ValueKey<String>('assessment-create-reach-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('assessment-create-submit');
  static const ValueKey<String> failureKey = ValueKey<String>('assessment-create-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-create-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-create-retry');

  static ValueKey<String> get processSearchKey => AppSearchField.fieldKey(processFieldName);
  static ValueKey<String> processSuggestionKey(String id) =>
      AppSearchField.suggestionKey(processFieldName, id);
  static ValueKey<String> get orgUnitSearchKey => AppSearchField.fieldKey(orgUnitFieldName);
  static ValueKey<String> orgUnitSuggestionKey(String id) =>
      AppSearchField.suggestionKey(orgUnitFieldName, id);
  static ValueKey<String> get employeeSearchKey => AppSearchField.fieldKey(employeeFieldName);
  static ValueKey<String> employeeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(employeeFieldName, id);
  static ValueKey<String> sizeKey(int count) => ValueKey<String>('assessment-create-size-$count');
  static ValueKey<String> orgUnitChipKey(String id) => ValueKey<String>('assessment-create-unit-$id');
  static ValueKey<String> employeeChipKey(String id) => ValueKey<String>('assessment-create-employee-$id');

  @override
  State<AssessmentCreateScreen> createState() => _AssessmentCreateScreenState();
}

class _AssessmentCreateScreenState extends State<AssessmentCreateScreen> {
  final _title = TextEditingController();
  final _minutes = TextEditingController();
  final _passMark = TextEditingController();

  int _questionCount = 10;
  String? _dueOn;

  /// True until a person types a number of their own: only then does changing
  /// the paper size stop restating the default.
  bool _minutesTouched = false;
  bool _passMarkTouched = false;

  @override
  void initState() {
    super.initState();
    _restateDefaults();
  }

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _passMark.dispose();
    super.dispose();
  }

  int get _defaultMinutes => _questionCount * 2;
  int get _defaultPassMark => (_questionCount * 0.8).ceil();

  void _restateDefaults() {
    if (!_minutesTouched) _minutes.text = '$_defaultMinutes';
    if (!_passMarkTouched) _passMark.text = '$_defaultPassMark';
  }

  void _onSizeChanged(int count) {
    setState(() {
      _questionCount = count;
      _restateDefaults();
    });
  }

  /// The reach is recomputed by the Bloc from the group the chips represent, so
  /// this Screen keeps no copy of it.
  void _sendGroup(BuildContext context, {List<OrgUnitNode>? orgUnits, List<Employee>? employees}) {
    final state = context.read<AssessmentCreateBloc>().state;
    if (state is! AssessmentCreateLoaded) return;
    final group = state.group;
    context.read<AssessmentCreateBloc>().add(AssessmentCreateGroupChanged(
          orgUnits: orgUnits ?? group.orgUnits,
          employees: employees ?? group.employees,
        ));
  }

  void _submit(BuildContext context) {
    final state = context.read<AssessmentCreateBloc>().state;
    if (state is! AssessmentCreateLoaded) return;
    final process = state.process;
    if (process == null) return;

    final minutes = int.tryParse(_minutes.text.trim());
    final passMark = int.tryParse(_passMark.text.trim());
    context.read<AssessmentCreateBloc>().add(AssessmentCreateSubmitted(
          body: {
            'orgUnitId': process.id,
            'title': _title.text.trim(),
            'questionCount': _questionCount,
            'minutes': ?minutes,
            'passMark': ?passMark,
            'dueOn': ?_dueOn,
          },
          group: state.group,
        ));
  }

  Future<List<OrgUnitNode>> _searchOrgUnits(BuildContext context, String siteId, String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentCreateBloc.signedOutMessage);
    final result = await context.read<PeopleApi>().searchOrgUnits(token, siteId: siteId, search: term);
    return result.orgUnits;
  }

  Future<List<Employee>> _searchEmployees(BuildContext context, String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentCreateBloc.signedOutMessage);
    return context.read<PeopleApi>().fetchEmployees(token, search: term, limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentCreateBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentCreateLoading() => const SkeletonDetail(maxWidth: AssessmentCreateScreen.maxWidth),
        AssessmentCreateUnavailable(message: final message) => PlatformFailureState(
            key: AssessmentCreateScreen.failedKey,
            title: l10n.assessmentsFailedTitle,
            message: message,
            retryKey: AssessmentCreateScreen.retryKey,
            onRetry: () => context.read<AssessmentCreateBloc>().add(const AssessmentCreateStarted()),
          ),
        AssessmentCreateLoaded() => _form(context, l10n, state),
      },
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n, AssessmentCreateLoaded state) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final siteId = state.siteId;
    final process = state.process;

    // A submitted Assessment is a fact: the register is where it is read.
    if (state.created != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(Routes.assessments);
      });
    }

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentCreateScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.assessmentNewTitle,
              description: l10n.assessmentNewDescription,
              actions: [
                TextButton(
                  onPressed: () => context.go(Routes.assessments),
                  child: Text(l10n.commonCancel),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.sites.length > 1) ...[
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: AssessmentCreateScreen.siteKey,
                  initialValue: siteId,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: l10n.commonSite,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final site in state.sites)
                      DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<AssessmentCreateBloc>().add(AssessmentCreateSiteChosen(value));
                  },
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (siteId != null)
              KeyedSubtree(
                key: ValueKey<String>('assessment-create-process-$siteId'),
                child: AppSearchField<OrgUnitNode>(
                  name: AssessmentCreateScreen.processFieldName,
                  label: l10n.assessmentProcessSearchLabel,
                  helperText: l10n.assessmentNewProcessHelper,
                  value: process,
                  onChanged: (_) {},
                  onSelected: (picked) =>
                      context.read<AssessmentCreateBloc>().add(AssessmentCreateProcessChosen(picked)),
                  fetchSuggestions: (term) => _searchOrgUnits(context, siteId, term),
                  suggestionBuilder: (context, node) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm,
                    ),
                    child: Text('${node.name} · ${node.code}'),
                  ),
                  idOf: (node) => node.id,
                  displayStringFor: (node) => node.name,
                  codeOf: (node) => node.code,
                ),
              ),
            if (state.activeCount != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentProcessActiveCount(state.activeCount!),
                key: AssessmentCreateScreen.activeCountKey,
                style: theme.textTheme.labelLarge?.copyWith(color: palette.textMuted),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            TextField(
              key: AssessmentCreateScreen.titleKey,
              controller: _title,
              decoration: InputDecoration(
                labelText: l10n.assessmentTitleLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Spacing.lg),
            Text(l10n.assessmentPaperSizeLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              children: [
                for (final count in const [10, 15])
                  ChoiceChip(
                    key: AssessmentCreateScreen.sizeKey(count),
                    label: Text(l10n.assessmentQuestionCountShort(count)),
                    selected: _questionCount == count,
                    onSelected: (_) => _onSizeChanged(count),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: AssessmentCreateScreen.minutesKey,
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => _minutesTouched = true,
                    decoration: InputDecoration(
                      labelText: l10n.assessmentMinutesLabel,
                      helperText: l10n.assessmentMinutesHelper,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: TextField(
                    key: AssessmentCreateScreen.passMarkKey,
                    controller: _passMark,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => _passMarkTouched = true,
                    decoration: InputDecoration(
                      labelText: l10n.assessmentPassMarkLabel,
                      helperText: l10n.assessmentPassMarkHelper,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 260,
                child: AppDateField(
                  name: 'assessment-create-due-on',
                  label: l10n.assessmentDueDateLabel,
                  helperText: l10n.assessmentDueDateHelper,
                  value: _dueOn,
                  onChanged: (value) => setState(() => _dueOn = value),
                  optional: true,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(l10n.assessmentAssignGroupLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              l10n.assessmentAssignGroupHelper,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Spacing.md),
            if (siteId != null)
              AppSearchField<OrgUnitNode>(
                key: const ValueKey<String>('assessment-create-unit-field'),
                name: AssessmentCreateScreen.orgUnitFieldName,
                label: l10n.assessmentAssignOrgUnitLabel,
                value: null,
                onChanged: (_) {},
                onSelected: (picked) {
                  final group = state.group.orgUnits.any((unit) => unit.id == picked.id)
                      ? state.group.orgUnits
                      : [...state.group.orgUnits, picked];
                  _sendGroup(context, orgUnits: group);
                },
                fetchSuggestions: (term) => _searchOrgUnits(context, siteId, term),
                suggestionBuilder: (context, node) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                  child: Text('${node.name} · ${node.code}'),
                ),
                idOf: (node) => node.id,
                displayStringFor: (node) => node.name,
                codeOf: (node) => node.code,
              ),
            const SizedBox(height: Spacing.sm),
            AppSearchField<Employee>(
              key: const ValueKey<String>('assessment-create-employee-field'),
              name: AssessmentCreateScreen.employeeFieldName,
              label: l10n.assessmentAssignEmployeeLabel,
              value: null,
              onChanged: (_) {},
              onSelected: (picked) {
                final group = state.group.employees.any((employee) => employee.id == picked.id)
                    ? state.group.employees
                    : [...state.group.employees, picked];
                _sendGroup(context, employees: group);
              },
              fetchSuggestions: (term) => _searchEmployees(context, term),
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
                for (final unit in state.group.orgUnits)
                  InputChip(
                    key: AssessmentCreateScreen.orgUnitChipKey(unit.id),
                    label: Text(unit.name),
                    onDeleted: () => _sendGroup(
                      context,
                      orgUnits: [
                        for (final other in state.group.orgUnits)
                          if (other.id != unit.id) other,
                      ],
                    ),
                  ),
                for (final employee in state.group.employees)
                  InputChip(
                    key: AssessmentCreateScreen.employeeChipKey(employee.id),
                    label: Text(employee.displayName),
                    onDeleted: () => _sendGroup(
                      context,
                      employees: [
                        for (final other in state.group.employees)
                          if (other.id != employee.id) other,
                      ],
                    ),
                  ),
              ],
            ),
            if (state.previewing) ...[
              const SizedBox(height: Spacing.sm),
              const LinearProgressIndicator(),
            ],
            if (state.preview != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentReachCount(state.preview!.count),
                key: AssessmentCreateScreen.reachKey,
                style: theme.textTheme.labelLarge,
              ),
              if (state.preview!.unresolvedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: NoticeText(
                    l10n.assessmentReachUnresolved(
                      state.preview!.unresolvedCount,
                      state.preview!.unresolvedNames.join(', '),
                    ),
                  ),
                ),
            ],
            if (state.previewFailure != null) ...[
              const SizedBox(height: Spacing.sm),
              NoticeText(
                state.previewFailure!,
                key: AssessmentCreateScreen.reachFailureKey,
              ),
            ],
            const SizedBox(height: Spacing.xl),
            if (state.failure != null) ...[
              NoticeText(state.failure!, key: AssessmentCreateScreen.failureKey),
              const SizedBox(height: Spacing.md),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: AssessmentCreateScreen.submitKey,
                onPressed: state.submitting || process == null ? null : () => _submit(context),
                icon: const Icon(Icons.check),
                label: Text(l10n.assessmentCreateSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
