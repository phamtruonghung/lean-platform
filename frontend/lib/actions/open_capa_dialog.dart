/// Opening a CAPA on a Concern (issue #209, ADR-0034).
///
/// Addressed rather than popped — `${Routes.actions}/:id/capa` (ADR-0021) — so
/// a refresh lands on the Concern with the form open, and so the act has
/// somewhere to be linked to.
///
/// What the form collects is exactly what an investigation adds on top of the
/// Concern: **the team** (D1 — a lead, and any number of members, all chosen
/// from the Employee directory) and **the problem description** (D2). It
/// deliberately collects no kind of Action, no Org Unit and no title: a CAPA is
/// filed at its Concern's own Org Unit, it answers the Concern's problem, and
/// ADR-0034's whole point is that its *work* is the Concern's Containments,
/// Countermeasures and Preventive actions — recorded in the action log, once,
/// rather than chosen again here.
///
/// The team is optional on purpose. Opening the investigation is the judgement;
/// who investigates it is a decision somebody may make next, and the server
/// takes a CAPA with no team at all.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

class OpenCapaDialog extends StatefulWidget {
  const OpenCapaDialog({super.key, required this.concern});

  /// The Concern the investigation is opened on.
  final Action concern;

  static const ValueKey<String> refusedKey = ValueKey<String>('open-capa-refused');
  static const ValueKey<String> loadingKey = ValueKey<String>('open-capa-loading');
  static const ValueKey<String> descriptionKey = ValueKey<String>('open-capa-description');
  static const ValueKey<String> teamLeadKey = ValueKey<String>('open-capa-team-lead');
  static const ValueKey<String> submitKey = ValueKey<String>('open-capa-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('open-capa-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('open-capa-failure');
  static const ValueKey<String> noMembersKey = ValueKey<String>('open-capa-no-members');

  /// The box a further team member is searched for in. Its key carries the
  /// team's own size, so the field is remounted after every pick and the last
  /// name chosen is not left sitting in it looking like the selection — the
  /// team is the list of rows below it.
  static Key memberSearchKey(int alreadyChosen) =>
      AppSearchField.fieldKey('open-capa-members-$alreadyChosen');

  static String memberSearchName(int alreadyChosen) => 'open-capa-members-$alreadyChosen';

  static ValueKey<String> memberRowKey(String employeeId) =>
      ValueKey<String>('open-capa-member-$employeeId');

  static ValueKey<String> memberRemoveKey(String employeeId) =>
      ValueKey<String>('open-capa-member-remove-$employeeId');

  @override
  State<OpenCapaDialog> createState() => _OpenCapaDialogState();
}

class _OpenCapaDialogState extends State<OpenCapaDialog> {
  final TextEditingController _description = TextEditingController();

  Employee? _lead;
  final List<Employee> _members = [];
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<ActionDetailBloc>().add(
          ActionCapaRequested(
            concernId: widget.concern.id,
            teamLeadEmployeeId: _lead?.id,
            teamMemberEmployeeIds: [for (final member in _members) member.id],
            problemStatement: description.isEmpty ? null : description,
          ),
        );
  }

  /// The dialog is watching for the answer to its own request: the CAPA the
  /// server opened (which the Screen behind does not need, because the whole
  /// point is to go and read it) or the reason it refused.
  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (!_awaiting || state is! ActionDetailLoaded || state.isOpeningCapa) return;
    if (state.capaFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.capaFailure;
      });
      return;
    }
    final openedCapaId = state.openedCapaId;
    if (openedCapaId == null) return;
    // Straight to the investigation that was just opened: the next thing
    // anybody does with one is read it, and its address is what they send on.
    context.go('${Routes.actions}/capas/$openedCapaId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Quality authority is read here, in a build (ADR-0035), rather than passed
    // in from the route: this address can be reached by a refresh, and a
    // decision taken before `/me` answered would be a decision taken on a
    // half-known Account. The server refuses either way; this says why.
    if (!holdsQualityAuthority(context, widget.concern.orgUnitId)) {
      return AlertDialog(
        key: OpenCapaDialog.refusedKey,
        content: const Text(
          "Opening a CAPA needs Quality authority at this Concern's Org Unit.",
        ),
      );
    }

    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Open a CAPA on ${widget.concern.actionNo}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.concern.title} — an 8D investigation, in the action log, on this '
                  'Concern. Its containments, countermeasures and preventive actions are the '
                  'Concern\u2019s own and are read on the CAPA rather than recorded again.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: OpenCapaDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'The problem (optional)',
                    helperText: 'D2 — what the investigation is about, in the words a team will '
                        'work from.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text('The team', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Chosen from the Employee directory. Leave it empty to decide the team later — '
                  'the investigation is what is being opened here.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                AppSearchField<Employee>(
                  key: OpenCapaDialog.teamLeadKey,
                  name: 'open-capa-team-lead',
                  label: 'Team lead (optional)',
                  helperText: 'Who is answerable for the investigation.',
                  value: _lead,
                  enabled: !_awaiting,
                  onChanged: (employee) => setState(() => _lead = employee),
                  fetchSuggestions: _fetchEmployees,
                  suggestionBuilder: _suggestionRow,
                  idOf: (employee) => employee.id,
                  displayStringFor: (employee) => employee.displayName,
                  onSelected: (employee) => setState(() => _lead = employee),
                ),
                const SizedBox(height: Spacing.md),
                AppSearchField<Employee>(
                  key: OpenCapaDialog.memberSearchKey(_members.length),
                  name: OpenCapaDialog.memberSearchName(_members.length),
                  label: 'Add a team member (optional)',
                  value: null,
                  enabled: !_awaiting,
                  // Nothing here is a *chosen value* to be retired — a pick
                  // adds a row to the team and remounts this box (its key
                  // carries the team's size), so a retired value has nothing to
                  // clear.
                  onChanged: (_) {},
                  fetchSuggestions: _fetchEmployees,
                  suggestionBuilder: _suggestionRow,
                  idOf: (employee) => employee.id,
                  displayStringFor: (employee) => employee.displayName,
                  onSelected: _addMember,
                ),
                if (_members.isEmpty)
                  Padding(
                    key: OpenCapaDialog.noMembersKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      'Nobody else is on this investigation yet.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final member in _members)
                          InputChip(
                            key: OpenCapaDialog.memberRowKey(member.id),
                            label: Text(member.displayName),
                            onDeleted: _awaiting ? null : () => _removeMember(member),
                            deleteButtonTooltipMessage: 'Take ${member.displayName} off the team',
                          ),
                      ],
                    ),
                  ),
                if (_failure != null)
                  Padding(
                    key: OpenCapaDialog.failureKey,
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
            key: OpenCapaDialog.cancelKey,
            onPressed: _awaiting ? null : () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: OpenCapaDialog.submitKey,
            // Anything is enough: an investigation with no team and no
            // description yet is a real state, so nothing here blocks a caller
            // who has decided the problem needs one.
            onPressed: _awaiting ? null : _submit,
            child: const Text('Open the CAPA'),
          ),
        ],
      ),
    );
  }

  /// The box suggests every Employee the Platform knows of, narrowed by the
  /// term the field's own debounce produced — never free text: the team is
  /// People's directory's to answer (ADR-0023, the choosing control).
  Future<List<Employee>> _fetchEmployees(String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) return const [];
    return context.read<PeopleApi>().fetchEmployees(token, search: term);
  }

  Widget _suggestionRow(BuildContext context, Employee employee) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
        child: Text(employee.displayName),
      );

  void _addMember(Employee employee) {
    setState(() {
      if (!_members.any((member) => member.id == employee.id)) {
        _members.add(employee);
      }
    });
  }

  void _removeMember(Employee employee) {
    setState(() => _members.removeWhere((member) => member.id == employee.id));
  }
}
