/// Raising a Non-conformance's severity, and recording the immediate
/// containment that makes it `contained` (issue #205).
///
/// Addressed rather than popped — `/non-conformances/:id/update` (ADR-0021).
/// One dialog for the two acts because they are the same act twice over:
/// finding out more about a failure and saying what was done about it at once,
/// and issue #205's own criteria name them together ("the recorder may set a
/// higher severity at recording or afterwards"; "becoming `contained` once
/// immediate containment is recorded").
///
/// **The severity list offers only values above the current one.** The API
/// refuses a lowering with a 403 in this slice — deciding that nonconforming
/// product is less bad than the Defect code says is a Quality-authority
/// decision (ADR-0035) that issue #206 owns — so a control that offered a
/// lower severity and reported the refusal back would be asking a question it
/// already knows the answer to. The values themselves are a closed set and are
/// chosen, never typed (ADR-0023).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceUpdateDialog extends StatefulWidget {
  const NonconformanceUpdateDialog({super.key, required this.nonconformance});

  /// The record as the detail Screen is reading it: the severity to compare
  /// against, and the containment already recorded, if any.
  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey = ValueKey<String>('nonconformance-update-loading');
  static const ValueKey<String> severityKey = ValueKey<String>('nonconformance-update-severity');
  static const ValueKey<String> raiseKey = ValueKey<String>('nonconformance-update-raise');
  static const ValueKey<String> containmentKey =
      ValueKey<String>('nonconformance-update-containment');
  static const ValueKey<String> containKey = ValueKey<String>('nonconformance-update-contain');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-update-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-update-failure');

  @override
  State<NonconformanceUpdateDialog> createState() => _NonconformanceUpdateDialogState();
}

class _NonconformanceUpdateDialogState extends State<NonconformanceUpdateDialog> {
  final TextEditingController _containment = TextEditingController();

  String? _severity;
  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _containment.text = widget.nonconformance.immediateContainment ?? '';
  }

  @override
  void dispose() {
    _containment.dispose();
    super.dispose();
  }

  /// The severities above the one on the record — what a raising can be, and
  /// all it can be in this slice.
  List<String> get _offerableSeverities => [
        for (final severity in DefectSeverity.values)
          if (severityRank(severity) > severityRank(widget.nonconformance.severity)) severity,
      ];

  void _raise() {
    final severity = _severity;
    if (severity == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(NonconformanceSeverityRaised(severity));
  }

  void _contain() {
    if (_containment.text.trim().isEmpty || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context
        .read<NonconformanceDetailBloc>()
        .add(NonconformanceContainmentRecorded(_containment.text));
  }

  /// Whether this dialog has already finished — a second pop would take the
  /// detail's own page off the stack behind it.
  bool _done = false;

  void _onDetailChanged(BuildContext context, NonconformanceDetailState state) {
    if (_done || !_awaiting || state is! NonconformanceDetailLoaded || state.isMutating) return;
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
    final row = widget.nonconformance;
    final offerable = _offerableSeverities;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Raise severity or contain it'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${row.issueNo} is ${row.severityLabel.toLowerCase()} severity and '
                  '${row.statusLabel.toLowerCase()}.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                if (offerable.isEmpty)
                  Text(
                    'This Non-conformance is already at the worst severity, so there is nothing '
                    'to raise it to.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else ...[
                  DropdownButtonFormField<String?>(
                    key: NonconformanceUpdateDialog.severityKey,
                    initialValue: _severity,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Raise the severity to',
                      helperText: 'Severity can be raised here; lowering it is a later decision.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Leave the severity alone'),
                      ),
                      for (final severity in offerable)
                        DropdownMenuItem<String?>(
                          value: severity,
                          child: Text(DefectSeverity.label(severity)),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _severity = value),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: NonconformanceUpdateDialog.raiseKey,
                      onPressed: _severity == null || _awaiting ? null : _raise,
                      child: const Text('Raise it'),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
                TextField(
                  key: NonconformanceUpdateDialog.containmentKey,
                  controller: _containment,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Immediate containment',
                    helperText: 'What was done at once. Recording it makes this contained.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: NonconformanceUpdateDialog.containKey,
                    onPressed: _containment.text.trim().isEmpty || _awaiting ? null : _contain,
                    child: const Text('Record containment'),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceUpdateDialog.failureKey,
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
            key: NonconformanceUpdateDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
