/// Assigning a Work order to an Employee, and reassigning it to a different
/// one — one act, one dialog (issue #62).
///
/// This is the ticket's own central claim, restated for the client: a
/// qualification is shown here, never enforced. Every candidate is
/// selectable regardless of what they hold, a lapsed qualification is shown
/// as lapsed rather than left out, and nothing here is evaluative — no
/// warning banner, no "not qualified" text, no disabled row. See ADR-0018.
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
///
/// **Finding a person (issue #187).** The candidate read behind this dialog is
/// deliberately unbounded — `listAssigneeCandidates` (directory.js) refuses
/// nothing and limits nothing, because ADR-0018 asks "who could do this job"
/// rather than an Org Unit question (issue #62). A plant therefore offers every
/// Active Employee here, so the dialog carries a filter box over the rows it has
/// already read: typing narrows them by display name, employee number, or the
/// name of a qualification the candidate holds — "who can weld" is as
/// answerable as "Nguyen". It is a filter and not a second read: the set is
/// complete in this dialog already, and `AppFilterField` never touches the
/// network (see its own doc comment for why this is a different control from
/// `AppSearchField`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../status_tone.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/status_chip.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderAssignDialog extends StatefulWidget {
  const WorkOrderAssignDialog({super.key, required this.workOrder});

  /// The Work order being given away — its current assignee, if any, decides
  /// whether the dialog's own caller renders "Assign" or "Reassign".
  final WorkOrder workOrder;

  /// The filter box's `name`, seeding [searchFieldKey]/[searchClearKey]/
  /// [searchCountKey] — kept in one place so none of them can drift from what
  /// `build` actually renders.
  static const String searchFieldName = 'work-order-assign-search';

  static ValueKey<String> candidateKey(String employeeId) =>
      ValueKey<String>('assign-candidate-$employeeId');
  static ValueKey<String> skillChipKey(String employeeId, String skillId) =>
      ValueKey<String>('assign-skill-$employeeId-$skillId');
  static ValueKey<String> lapsedChipKey(String employeeId, String skillId) =>
      ValueKey<String>('assign-skill-lapsed-$employeeId-$skillId');
  static const ValueKey<String> submitKey = ValueKey<String>('work-order-assign-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('work-order-assign-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-assign-failure');
  static const ValueKey<String> candidatesFailedKey =
      ValueKey<String>('work-order-assign-candidates-failed');
  static const ValueKey<String> noCandidatesKey = ValueKey<String>('work-order-assign-none');

  /// Present instead of [noCandidatesKey] when the candidates were read fine
  /// but the term matches none of them — a different fact, and one the reader
  /// can act on by typing something else.
  static const ValueKey<String> noMatchesKey = ValueKey<String>('work-order-assign-no-matches');

  static ValueKey<String> get searchFieldKey => AppFilterField.fieldKey(searchFieldName);
  static ValueKey<String> get searchClearKey => AppFilterField.clearKey(searchFieldName);
  static ValueKey<String> get searchCountKey => AppFilterField.countKey(searchFieldName);


  @override
  State<WorkOrderAssignDialog> createState() => _WorkOrderAssignDialogState();
}

enum _CandidatesStatus { loading, ready, failed }

class _WorkOrderAssignDialogState extends State<WorkOrderAssignDialog> {
  _CandidatesStatus _status = _CandidatesStatus.loading;
  List<AssigneeCandidate> _candidates = const [];
  String? _candidatesFailure;

  /// Null until chosen — never defaulted, the same discipline
  /// `WorkOrderFormDialog` keeps for its own `_assetId`.
  String? _employeeId;

  /// What the filter box is narrowing the candidate list to, `''` when nothing
  /// is. The rows are filtered in `build` off this, so typing costs a rebuild
  /// and nothing else — no request, no Bloc event (issue #187).
  String _term = '';

  bool _awaiting = false;
  String? _failure;

  /// Whether [candidate] matches [term], already lower-cased and trimmed. Three
  /// fields, because those are the three ways a supervisor knows who they mean:
  /// the name they would say, the number they read off a badge or a work sheet,
  /// and the qualification the job needs. No ranking and no fuzzy matching —
  /// see issue #187's own decision.
  static bool _matches(AssigneeCandidate candidate, String term) =>
      candidate.displayName.toLowerCase().contains(term) ||
      candidate.employeeNo.toLowerCase().contains(term) ||
      candidate.skills.any((skill) => skill.name.toLowerCase().contains(term));

  /// The candidates the term selects — every one of them when it is empty.
  List<AssigneeCandidate> _matchingCandidates() {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return _candidates;
    return _candidates.where((candidate) => _matches(candidate, term)).toList(growable: false);
  }

  /// The rows actually rendered: the matches, with the chosen candidate pinned
  /// **first** when the term excludes them. A supervisor who picks a person and
  /// then edits the term must not be able to submit a name that is off-screen —
  /// the same silently-wrong-value hazard ADR-0023 point 4 exists to remove —
  /// and appending the kept row would leave it below the fold of a 420px box.
  List<AssigneeCandidate> _visibleCandidates(List<AssigneeCandidate> matches) {
    final id = _employeeId;
    if (id == null || matches.any((candidate) => candidate.id == id)) return matches;
    for (final candidate in _candidates) {
      if (candidate.id == id) return [candidate, ...matches];
    }
    return matches;
  }

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _status = _CandidatesStatus.loading;
      _candidatesFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _status = _CandidatesStatus.failed;
        _candidatesFailure = WorkOrdersBloc.signedOutMessage;
      });
      return;
    }
    try {
      final candidates = await context.read<PeopleApi>().fetchAssigneeCandidates(token);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _status = _CandidatesStatus.ready;
      });
    } on PeopleApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CandidatesStatus.failed;
        _candidatesFailure = error.message;
      });
    }
  }

  void _submit() {
    if (_employeeId == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<WorkOrdersBloc>().add(
          WorkOrderAssignConfirmed(workOrderId: widget.workOrder.id, employeeId: _employeeId!),
        );
  }

  void _onWorkOrdersChanged(BuildContext context, WorkOrdersState state) {
    if (!_awaiting || state is! WorkOrdersLoaded || state.isAssigning) return;
    if (state.assignFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.assignFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matching = _matchingCandidates();
    final visible = _visibleCandidates(matching);
    final hasTerm = _term.trim().isNotEmpty;
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      child: AlertDialog(
        title: Text(widget.workOrder.assignedTo == null ? 'Assign' : 'Reassign'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Only while there is a list to narrow. A filter box over a set
              // that failed to load, or has not arrived yet, is a control that
              // can do nothing, and the dialog's own failure state is what
              // those two states need to be read as.
              if (_status == _CandidatesStatus.ready && _candidates.isNotEmpty) ...[
                AppFilterField(
                  name: WorkOrderAssignDialog.searchFieldName,
                  label: 'Find a person',
                  helperText: 'By name, employee number, or the qualification they hold.',
                  term: _term,
                  enabled: !_awaiting,
                  onChanged: (term) => setState(() => _term = term),
                  shown: visible.length,
                  total: _candidates.length,
                ),
                const SizedBox(height: Spacing.md),
              ],
              Expanded(
                child: _CandidatesList(
                  status: _status,
                  candidates: visible,
                  failure: _candidatesFailure,
                  selectedId: _employeeId,
                  term: _term,
                  isFiltered: hasTerm,
                  enabled: !_awaiting,
                  onRetry: _loadCandidates,
                  onChanged: (id) => setState(() => _employeeId = id),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_failure != null)
            Padding(
              key: WorkOrderAssignDialog.failureKey,
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Text(
                _failure!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          TextButton(
            key: WorkOrderAssignDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: WorkOrderAssignDialog.submitKey,
            onPressed: _employeeId != null && !_awaiting ? _submit : null,
            child: Text(widget.workOrder.assignedTo == null ? 'Assign' : 'Reassign'),
          ),
        ],
      ),
    );
  }
}

class _CandidatesList extends StatelessWidget {
  const _CandidatesList({
    required this.status,
    required this.candidates,
    required this.failure,
    required this.selectedId,
    required this.term,
    required this.isFiltered,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _CandidatesStatus status;
  final List<AssigneeCandidate> candidates;
  final String? failure;
  final String? selectedId;

  /// The filter box's own term, carried only so the empty-list sentence can
  /// name what was typed.
  final String term;

  /// Whether a term is narrowing the list at all — the difference between
  /// "there is nobody this Work order could be given to" (a fact about the
  /// plant) and "nobody matches what you typed" (a fact about the search). The
  /// two must never read the same, which is why this is passed in rather than
  /// inferred from `candidates.isEmpty` (issue #187).
  final bool isFiltered;

  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _CandidatesStatus.loading:
        return const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case _CandidatesStatus.failed:
        return Column(
          key: WorkOrderAssignDialog.candidatesFailedKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The candidates could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _CandidatesStatus.ready:
        if (candidates.isEmpty) {
          return Center(
            key: isFiltered
                ? WorkOrderAssignDialog.noMatchesKey
                : WorkOrderAssignDialog.noCandidatesKey,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text(
                isFiltered
                    ? 'Nobody matches "${term.trim()}" — try a different name, number, or skill.'
                    : 'There is nobody this Work order could be given to.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        }
        // RadioGroup, not each tile's own groupValue/onChanged (deprecated
        // since Flutter 3.32) — the same shape `AdmissionDialog` already uses
        // for its own role choice.
        return RadioGroup<String>(
          groupValue: selectedId,
          // Guarded rather than nulled out: RadioGroup.onChanged is not
          // nullable, and each tile is disabled anyway while an assign is in
          // flight.
          onChanged: (id) {
            if (!enabled || id == null) return;
            onChanged(id);
          },
          child: ListView.separated(
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _CandidateRow(candidate: candidates[index], enabled: enabled),
          ),
        );
    }
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.enabled});

  final AssigneeCandidate candidate;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RadioListTile<String>(
      key: WorkOrderAssignDialog.candidateKey(candidate.id),
      value: candidate.id,
      enabled: enabled,
      title: Text(candidate.displayName),
      subtitle: candidate.skills.isEmpty
          ? const Text('No qualifications recorded')
          : Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [for (final skill in candidate.skills) _skillChip(theme, candidate, skill)],
              ),
            ),
    );
  }

  /// Each held skill is a `Chip`, always keyed with [skillChipKey]. A lapsed
  /// one additionally sits inside a `KeyedSubtree` carrying [lapsedChipKey] —
  /// present only for a lapsed skill and absent for a current one — so a test
  /// can assert "lapsed distinguished from absent" by key rather than by
  /// reading a colour. A lapsed qualification is shown, never filtered out
  /// (AC3), and nothing here is evaluative: the colour and the trailing
  /// "· Lapsed" state a fact about what the candidate holds, never a claim
  /// about whether they should get this Work order — see ADR-0018 for why
  /// this dialog never renders a warning or a disabled row either.
  Widget _skillChip(ThemeData theme, AssigneeCandidate candidate, HeldSkill skill) {
    // The lapsed chip used to wear the error container's red, which is the one
    // colour this doc comment says this dialog never renders — a judgement
    // about a candidate. It is the neutral tone now (issues #168/#169), so the
    // colour agrees with the rule: the chip states what somebody holds, and
    // "· Lapsed" carries the rest.
    final chip = skill.isLapsed
        ? StatusChip(
            key: WorkOrderAssignDialog.skillChipKey(candidate.id, skill.skillId),
            label: '${skill.name} · Lapsed',
            tone: StatusTone.neutral,
          )
        : Chip(
            key: WorkOrderAssignDialog.skillChipKey(candidate.id, skill.skillId),
            label: Text(skill.name),
            visualDensity: VisualDensity.compact,
          );
    return skill.isLapsed
        ? KeyedSubtree(
            key: WorkOrderAssignDialog.lapsedChipKey(candidate.id, skill.skillId),
            child: chip,
          )
        : chip;
  }
}
