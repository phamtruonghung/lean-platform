/// The decisions maintenance makes on an open Request (issue #72).
///
/// Three dialogs, one file, because they are three answers to the same queue
/// row: accept (which raises a Work order — the commitment), decline (which
/// requires a reason), and mark-a-duplicate (of another Request in the queue).
/// Each is a thin dialog that captures its fields and dispatches the matching
/// decision to `TriageBloc`; the Bloc lets the server refuse an illegal one
/// (a Request already triaged, an accept outside the caller's write Grants).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'maintenance_request.dart';
import 'triage_bloc.dart';

/// Accepting a Request: raises the Work order for it. Maintenance sets the
/// `workType` and `priority` here — urgency is the operator's judgement and is
/// never copied across, so this dialog asks for the plan rather than assuming
/// one from the ask.
class AcceptRequestDialog extends StatefulWidget {
  const AcceptRequestDialog({super.key, required this.request});

  final MaintenanceRequest request;

  static const ValueKey<String> workTypeKey = ValueKey<String>('accept-dialog-work-type');
  static const ValueKey<String> priorityKey = ValueKey<String>('accept-dialog-priority');
  static const ValueKey<String> cancelKey = ValueKey<String>('accept-dialog-cancel');
  static const ValueKey<String> confirmKey = ValueKey<String>('accept-dialog-confirm');

  static Future<void> open(BuildContext context, {required MaintenanceRequest request}) {
    final bloc = context.read<TriageBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TriageBloc>.value(
        value: bloc,
        child: AcceptRequestDialog(request: request),
      ),
    );
  }

  @override
  State<AcceptRequestDialog> createState() => _AcceptRequestDialogState();
}

class _AcceptRequestDialogState extends State<AcceptRequestDialog> {
  String? _workType;
  int? _priority;
  bool _awaiting = false;
  String? _failure;

  void _onTriageChanged(BuildContext context, TriageState state) {
    if (!_awaiting || state is! TriageLoaded) return;
    if (state.actingOnId != null) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _workType != null && _priority != null;
    return BlocListener<TriageBloc, TriageState>(
      listener: _onTriageChanged,
      child: AlertDialog(
        title: const Text('Accept this Request'),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Accepting raises a Work order for ${widget.request.requestNo}. "
                "The Work order's type and priority are your plan — the requester's "
                'urgency is not copied across.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                key: AcceptRequestDialog.workTypeKey,
                initialValue: _workType,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Work type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'corrective', child: Text('Corrective')),
                  DropdownMenuItem(value: 'preventive', child: Text('Preventive')),
                  DropdownMenuItem(value: 'predictive', child: Text('Predictive')),
                  DropdownMenuItem(value: 'inspection', child: Text('Inspection')),
                  DropdownMenuItem(value: 'improvement', child: Text('Improvement')),
                  DropdownMenuItem(value: 'calibration', child: Text('Calibration')),
                ],
                onChanged: _awaiting ? null : (value) => setState(() => _workType = value),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<int>(
                key: AcceptRequestDialog.priorityKey,
                initialValue: _priority,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 - Most urgent')),
                  DropdownMenuItem(value: 2, child: Text('2 - Urgent')),
                  DropdownMenuItem(value: 3, child: Text('3 - Normal')),
                  DropdownMenuItem(value: 4, child: Text('4 - Low')),
                  DropdownMenuItem(value: 5, child: Text('5 - Least urgent')),
                ],
                onChanged: _awaiting ? null : (value) => setState(() => _priority = value),
              ),
              if (_failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: AcceptRequestDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AcceptRequestDialog.confirmKey,
            onPressed: ready && !_awaiting
                ? () {
                    setState(() => _awaiting = true);
                    context.read<TriageBloc>().add(RequestAcceptConfirmed(
                          widget.request.id,
                          workType: _workType!,
                          priority: _priority!,
                        ));
                  }
                : null,
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}

/// Declining a Request — which requires a reason (the server refuses one
/// without it, and the schema's CHECK constraint backstops it).
class DeclineRequestDialog extends StatefulWidget {
  const DeclineRequestDialog({super.key, required this.request});

  final MaintenanceRequest request;

  static const ValueKey<String> reasonKey = ValueKey<String>('decline-dialog-reason');
  static const ValueKey<String> cancelKey = ValueKey<String>('decline-dialog-cancel');
  static const ValueKey<String> confirmKey = ValueKey<String>('decline-dialog-confirm');

  static Future<void> open(BuildContext context, {required MaintenanceRequest request}) {
    final bloc = context.read<TriageBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TriageBloc>.value(
        value: bloc,
        child: DeclineRequestDialog(request: request),
      ),
    );
  }

  @override
  State<DeclineRequestDialog> createState() => _DeclineRequestDialogState();
}

class _DeclineRequestDialogState extends State<DeclineRequestDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _awaiting = false;
  String? _failure;

  void _onTriageChanged(BuildContext context, TriageState state) {
    if (!_awaiting || state is! TriageLoaded) return;
    if (state.actingOnId != null) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<TriageBloc, TriageState>(
      listener: _onTriageChanged,
      child: AlertDialog(
        title: const Text('Decline this Request'),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Why is maintenance declining ${widget.request.requestNo}? This is '
                'the answer the requester will see.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: DeclineRequestDialog.reasonKey,
                controller: _reason,
                maxLines: 3,
                enabled: !_awaiting,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: DeclineRequestDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: DeclineRequestDialog.confirmKey,
            onPressed: _reason.text.trim().isEmpty || _awaiting
                ? null
                : () {
                    setState(() => _awaiting = true);
                    context.read<TriageBloc>().add(RequestDeclineConfirmed(
                          widget.request.id,
                          reason: _reason.text.trim(),
                        ));
                  },
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }
}

/// Marking a Request as a duplicate of one already raised. The surviving
/// Request is chosen here and is named on the row.
class DuplicateRequestDialog extends StatefulWidget {
  const DuplicateRequestDialog({super.key, required this.request, required this.queue});

  final MaintenanceRequest request;
  final List<MaintenanceRequest> queue;

  static const ValueKey<String> targetKey = ValueKey<String>('duplicate-dialog-target');
  static const ValueKey<String> cancelKey = ValueKey<String>('duplicate-dialog-cancel');
  static const ValueKey<String> confirmKey = ValueKey<String>('duplicate-dialog-confirm');

  static Future<void> open(
    BuildContext context, {
    required MaintenanceRequest request,
    required List<MaintenanceRequest> queue,
  }) {
    final bloc = context.read<TriageBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TriageBloc>.value(
        value: bloc,
        child: DuplicateRequestDialog(request: request, queue: queue),
      ),
    );
  }

  @override
  State<DuplicateRequestDialog> createState() => _DuplicateRequestDialogState();
}

class _DuplicateRequestDialogState extends State<DuplicateRequestDialog> {
  String? _targetId;
  bool _awaiting = false;
  String? _failure;

  void _onTriageChanged(BuildContext context, TriageState state) {
    if (!_awaiting || state is! TriageLoaded) return;
    if (state.actingOnId != null) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _targetId != null;
    return BlocListener<TriageBloc, TriageState>(
      listener: _onTriageChanged,
      child: AlertDialog(
        title: const Text('Mark as a duplicate'),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.request.requestNo} is a duplicate of which Request? The '
                'surviving Request is the one that keeps its place in the queue.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                key: DuplicateRequestDialog.targetKey,
                initialValue: _targetId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Duplicate of',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final other in widget.queue)
                    if (other.id != widget.request.id)
                      DropdownMenuItem<String>(
                        value: other.id,
                        child: Text(other.summary, overflow: TextOverflow.ellipsis),
                      ),
                ],
                onChanged: _awaiting ? null : (value) => setState(() => _targetId = value),
              ),
              if (_failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: DuplicateRequestDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: DuplicateRequestDialog.confirmKey,
            onPressed: ready && !_awaiting
                ? () {
                    setState(() => _awaiting = true);
                    context.read<TriageBloc>().add(RequestDuplicateConfirmed(
                          widget.request.id,
                          duplicateOfId: _targetId!,
                        ));
                  }
                : null,
            child: const Text('Mark duplicate'),
          ),
        ],
      ),
    );
  }
}