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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderAssignDialog extends StatefulWidget {
  const WorkOrderAssignDialog({super.key, required this.workOrder});

  /// The Work order being given away — its current assignee, if any, decides
  /// whether the dialog's own caller renders "Assign" or "Reassign".
  final WorkOrder workOrder;

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

  bool _awaiting = false;
  String? _failure;

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
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      child: AlertDialog(
        title: Text(widget.workOrder.assignedTo == null ? 'Assign' : 'Reassign'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: _CandidatesList(
            status: _status,
            candidates: _candidates,
            failure: _candidatesFailure,
            selectedId: _employeeId,
            enabled: !_awaiting,
            onRetry: _loadCandidates,
            onChanged: (id) => setState(() => _employeeId = id),
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
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _CandidatesStatus status;
  final List<AssigneeCandidate> candidates;
  final String? failure;
  final String? selectedId;
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
            key: WorkOrderAssignDialog.noCandidatesKey,
            child: Text(
              'There is nobody this Work order could be given to.',
              style: theme.textTheme.bodyMedium,
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
    final chip = Chip(
      key: WorkOrderAssignDialog.skillChipKey(candidate.id, skill.skillId),
      label: Text(skill.isLapsed ? '${skill.name} · Lapsed' : skill.name),
      backgroundColor: skill.isLapsed ? theme.colorScheme.errorContainer : null,
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
