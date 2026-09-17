/// Lowering a Non-conformance's severity (issue #206).
///
/// Addressed rather than popped — `/non-conformances/:id/lower-severity`
/// (ADR-0021). The Screen offers this address only to a caller holding Quality
/// authority at the record's Org Unit; the API refuses anyone else with a 403.
///
/// **The choices are the severities below the one on the record**, and a note
/// is required: deciding that nonconforming product is less bad than the
/// Defect code says is a judgement, and the reason for it is what the record
/// has to carry. Raising a severity is a different act, with its own address
/// and no authority behind it, so it is not offered here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceLowerSeverityDialog extends StatefulWidget {
  const NonconformanceLowerSeverityDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-lower-severity-loading');
  static const ValueKey<String> severityKey =
      ValueKey<String>('nonconformance-lower-severity-value');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-lower-severity-note');
  static const ValueKey<String> submitKey =
      ValueKey<String>('nonconformance-lower-severity-submit');
  static const ValueKey<String> cancelKey =
      ValueKey<String>('nonconformance-lower-severity-cancel');
  static const ValueKey<String> failureKey =
      ValueKey<String>('nonconformance-lower-severity-failure');
  static const ValueKey<String> refusedKey =
      ValueKey<String>('nonconformance-lower-severity-refused');

  @override
  State<NonconformanceLowerSeverityDialog> createState() =>
      _NonconformanceLowerSeverityDialogState();
}

class _NonconformanceLowerSeverityDialogState extends State<NonconformanceLowerSeverityDialog> {
  final TextEditingController _note = TextEditingController();

  String? _severity;
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The severities below the one on the record — what a lowering can be.
  List<String> get _offerableSeverities => [
        for (final severity in DefectSeverity.values)
          if (severityRank(severity) < severityRank(widget.nonconformance.severity)) severity,
      ];

  bool get _complete => _severity != null && _note.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    final severity = _severity;
    if (!_complete || severity == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceSeverityLowered(severity: severity, note: _note.text),
        );
  }

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
    final record = widget.nonconformance;
    final offerable = _offerableSeverities;

    // Read here, in a build, for the reason the Screen reads it there: a value
    // frozen when the route first built would answer for a half-known Account.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AlertDialog(
        key: NonconformanceLowerSeverityDialog.refusedKey,
        content: const Text(
          'Lowering a severity needs Quality authority at this Non-conformance\'s Org Unit.',
        ),
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Lower the severity'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${record.issueNo} is ${record.severityLabel.toLowerCase()} severity, and its '
                  'Defect code starts at ${DefectSeverity.label(record.defectCodeDefaultSeverity).toLowerCase()}.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                if (offerable.isEmpty)
                  Text(
                    'This Non-conformance is already at the lightest severity.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else
                  DropdownButtonFormField<String?>(
                    key: NonconformanceLowerSeverityDialog.severityKey,
                    initialValue: _severity,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Lower the severity to',
                      helperText: 'Lowering what the Defect code says needs Quality authority.',
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
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceLowerSeverityDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    helperText: 'Why it is less bad than the Defect code says.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceLowerSeverityDialog.failureKey,
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
            key: NonconformanceLowerSeverityDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceLowerSeverityDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Lower it'),
          ),
        ],
      ),
    );
  }
}
