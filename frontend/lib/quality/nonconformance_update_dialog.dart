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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';
import '../l10n/vocabulary.dart';
import '../widgets/notice_text.dart';

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
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('nonconformance-update-cancel');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final row = widget.nonconformance;
    final offerable = _offerableSeverities;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.nonconformanceUpdate,
        size: AppDialogSize.wide,
        // The two writes live in the content rather than in the action row:
        // each has its own enabled condition on the field above it, so they sit
        // where their field is. The one action is the way out.
        actions: [
          AppDialogAction(
            id: 'nonconformance-update-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.nonconformanceUpdateIsSeverityAnd(row.issueNo, row.severityLabel(l10n).toLowerCase(), row.statusLabel(l10n).toLowerCase()),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            if (offerable.isEmpty)
              Text(
                l10n.nonconformanceUpdateThisNonConformanceIsAlreadyAtThe,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              DropdownButtonFormField<String?>(
                key: NonconformanceUpdateDialog.severityKey,
                initialValue: _severity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.nonconformanceUpdateRaiseTheSeverityTo,
                  helperText: l10n.nonconformanceUpdateSeverityCanBeRaisedHereLoweringIt,
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.commonLeaveTheSeverityAlone),
                  ),
                  for (final severity in offerable)
                    DropdownMenuItem<String?>(
                      value: severity,
                      child: Text(defectSeverityLabel(l10n, severity)),
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
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(l10n.actionFormRaiseIt),
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
              decoration: InputDecoration(
                labelText: l10n.nonconformanceDetailContainment,
                helperText: l10n.nonconformanceFormContainmentHelp,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: NonconformanceUpdateDialog.containKey,
                onPressed: _containment.text.trim().isEmpty || _awaiting ? null : _contain,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: Text(l10n.nonconformanceUpdateRecordContainment),
              ),
            ),
            if (_failure != null)
              Padding(
                key: NonconformanceUpdateDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
                  _failure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
