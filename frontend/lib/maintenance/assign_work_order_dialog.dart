/// Assigning a Work order to somebody (issue #62): a picker of every active
/// Employee at the Work order's Site, each showing what they currently hold —
/// so the supervisor chooses with a lapsed qualification visible rather than
/// remembering who is valid.
///
/// Fetches its own candidates through `MaintenanceApi.fetchCandidates` when
/// opened (the same shape `WorkOrderFormDialog.open` uses for Assets), then
/// hands the decision to the `WorkOrdersBloc` via [WorkOrderAssignConfirmed].
/// The dialog decides; the Bloc only ever sees a decision already made.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'assignee_candidate.dart';
import 'maintenance_api.dart';
import 'work_orders_bloc.dart';

class AssignWorkOrderDialog extends StatefulWidget {
  const AssignWorkOrderDialog({super.key, required this.workOrderId});

  /// The Work order being assigned. The picked assignee is sent to the server
  /// for exactly this Work order; the returned row replaces it on the list.
  final String workOrderId;

  static const ValueKey<String> listKey = ValueKey<String>('assign-dialog-list');
  static const ValueKey<String> failedKey = ValueKey<String>('assign-dialog-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assign-dialog-retry');
  static const ValueKey<String> cancelKey = ValueKey<String>('assign-dialog-cancel');
  static const ValueKey<String> confirmKey = ValueKey<String>('assign-dialog-confirm');
  static const ValueKey<String> failureKey = ValueKey<String>('assign-dialog-failure');
  static ValueKey<String> candidateKey(String id) => ValueKey<String>('assign-dialog-candidate-$id');

  /// Opens the picker over the list. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<WorkOrdersBloc>` the list lives in — so the Bloc is handed
  /// across explicitly, the same shape `WorkOrderFormDialog.open` uses.
  static Future<void> open(BuildContext context, {required String workOrderId}) {
    final bloc = context.read<WorkOrdersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<WorkOrdersBloc>.value(
        value: bloc,
        child: AssignWorkOrderDialog(workOrderId: workOrderId),
      ),
    );
  }

  @override
  State<AssignWorkOrderDialog> createState() => _AssignWorkOrderDialogState();
}

enum _CandidatesStatus { loading, ready, failed }

class _AssignWorkOrderDialogState extends State<AssignWorkOrderDialog> {
  _CandidatesStatus _status = _CandidatesStatus.loading;
  List<AssigneeCandidate> _candidates = const [];
  String? _loadFailure;

  /// Null until chosen — never defaulted, so "somebody was chosen" is not
  /// true without the caller choosing them.
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
      _loadFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _status = _CandidatesStatus.failed;
        _loadFailure = WorkOrdersBloc.signedOutMessage;
      });
      return;
    }
    try {
      final candidates = await context.read<MaintenanceApi>().fetchCandidates(
            token,
            workOrderId: widget.workOrderId,
          );
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _status = _CandidatesStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CandidatesStatus.failed;
        _loadFailure = error.message;
      });
    }
  }

  void _confirm() {
    if (_employeeId == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<WorkOrdersBloc>().add(
          WorkOrderAssignConfirmed(
            workOrderId: widget.workOrderId,
            employeeId: _employeeId!,
          ),
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
        title: const Text('Assign this Work order'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Choose who takes this job. Qualifications are shown for '
                  'your judgement — the Platform does not refuse an assignment '
                  'over one.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                switch (_status) {
                  _CandidatesStatus.loading => const SizedBox(
                      height: 120,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  _CandidatesStatus.failed => Column(
                      key: AssignWorkOrderDialog.failedKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loadFailure ?? 'The assignable Employees could not be read.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                        TextButton(
                          key: AssignWorkOrderDialog.retryKey,
                          onPressed: _awaiting ? null : _loadCandidates,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  _CandidatesStatus.ready => _CandidatesList(
                      key: AssignWorkOrderDialog.listKey,
                      candidates: _candidates,
                      selectedId: _employeeId,
                      enabled: !_awaiting,
                      onSelected: (id) => setState(() => _employeeId = id),
                    ),
                },
                if (_failure != null)
                  Padding(
                    key: AssignWorkOrderDialog.failureKey,
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
            key: AssignWorkOrderDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AssignWorkOrderDialog.confirmKey,
            onPressed: _employeeId != null && !_awaiting ? _confirm : null,
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }
}

class _CandidatesList extends StatelessWidget {
  const _CandidatesList({
    super.key,
    required this.candidates,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final List<AssigneeCandidate> candidates;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Center(child: Text('No active Employees are assigned to this Site.')),
      );
    }
    return Column(
      children: [
        for (final candidate in candidates)
          ListTile(
            key: AssignWorkOrderDialog.candidateKey(candidate.id),
            enabled: enabled,
            selected: candidate.id == selectedId,
            contentPadding: EdgeInsets.zero,
            title: Text(candidate.displayName),
            subtitle: _Qualifications(candidate: candidate),
            trailing: candidate.id == selectedId
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: enabled ? () => onSelected(candidate.id) : null,
          ),
      ],
    );
  }
}

/// The qualifications this candidate currently holds, with a lapsed one shown
/// as lapsed. An empty `qualifications` list shows "No qualifications
/// recorded" — deliberately different wording from "Lapsed", so "never
/// trained" and "needs revalidating" stay distinct (issue #62's own claim).
class _Qualifications extends StatelessWidget {
  const _Qualifications({required this.candidate});

  final AssigneeCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qualifications = candidate.qualifications;
    if (qualifications.isEmpty) {
      return Text(
        'No qualifications recorded',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final qualification in qualifications)
          Text(
            qualification.isLapsed
                ? '${qualification.skillName} — lapsed'
                : qualification.skillName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: qualification.isLapsed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: qualification.isLapsed ? FontWeight.w600 : null,
            ),
          ),
      ],
    );
  }
}