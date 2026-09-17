/// Raising a Concern from a Non-conformance (issue #208).
///
/// Addressed rather than popped — `/non-conformances/:id/raise-concern`
/// (ADR-0021): a refresh lands on the record with the form open, and a
/// colleague can be handed the address of the act itself.
///
/// **This form is short on purpose, and the shortness is the design.** Raising
/// a Concern from a Non-conformance is the case where somebody has just found
/// a failure and wants the cause looked at; the register's own raise form is
/// where a Concern is raised deliberately, with a Pillar, an owner and a due
/// date. What is offered here is the least a Concern may be — a title, what is
/// known, and the priority — and the server fills the rest in by its own rules:
/// the Org Unit is the record's own (the Screen says so rather than offering a
/// chooser whose only correct answer the server would ignore), the number
/// comes from the Site's own sequence, and the Concern starts on a cycle-1
/// Plan of its own. Everything the Act log's rules require is required here
/// too: a title is the one field the API refuses without, so the submit button
/// is closed until there is one.
///
/// The write goes to the Actions Module (its own route, through its own client
/// entry point) and the answer is the Concern, so the dialog closes on the
/// Bloc's own `notice` and the Screen beneath it re-reads the record.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
import '../theme.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceRaiseConcernDialog extends StatefulWidget {
  const NonconformanceRaiseConcernDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-raise-concern-loading');
  static const ValueKey<String> titleKey = ValueKey<String>('nonconformance-raise-concern-title');
  static const ValueKey<String> descriptionKey =
      ValueKey<String>('nonconformance-raise-concern-description');
  static const ValueKey<String> priorityKey =
      ValueKey<String>('nonconformance-raise-concern-priority');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-raise-concern-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-raise-concern-cancel');
  static const ValueKey<String> failureKey =
      ValueKey<String>('nonconformance-raise-concern-failure');

  @override
  State<NonconformanceRaiseConcernDialog> createState() =>
      _NonconformanceRaiseConcernDialogState();
}

class _NonconformanceRaiseConcernDialogState extends State<NonconformanceRaiseConcernDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  int _priority = 3;
  bool _awaiting = false;
  bool _done = false;
  String? _failure;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _complete => _title.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceConcernRaised(
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            priority: _priority,
          ),
        );
  }

  /// The Bloc reports the outcome on its own state rather than returning one,
  /// so this is where the dialog learns it landed: still in flight, refused
  /// with a sentence, or done and ready to close.
  void _onDetailChanged(BuildContext context, NonconformanceDetailState state) {
    if (_done || !_awaiting) return;
    if (state is! NonconformanceDetailLoaded) return;
    if (state.isRaisingConcern) return;
    final failure = state.concernRaiseFailure;
    if (failure != null) {
      setState(() {
        _awaiting = false;
        _failure = failure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.nonconformance;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Raise a Concern'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${record.issueNo} is recorded at ${record.orgUnitName}, and the Concern is raised '
                  'there — a problem is solved where it happened.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceRaiseConcernDialog.titleKey,
                  controller: _title,
                  enabled: !_awaiting,
                  maxLines: 1,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'What is the problem to solve?',
                    helperText: 'The Concern is read in the action log, so say the problem, not the '
                        'product.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceRaiseConcernDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Anything known yet',
                    helperText: 'Optional. The Non-conformance itself is already linked as evidence.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<int>(
                  key: NonconformanceRaiseConcernDialog.priorityKey,
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    helperText: '1 is worst.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in actionPriorityLabels.entries)
                      DropdownMenuItem<int>(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _priority = value ?? 3),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceRaiseConcernDialog.failureKey,
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
            key: NonconformanceRaiseConcernDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceRaiseConcernDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Raise it'),
          ),
        ],
      ),
    );
  }
}
