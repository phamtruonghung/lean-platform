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

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';
import '../l10n/vocabulary.dart';

class NonconformanceLowerSeverityDialog extends StatefulWidget {
  const NonconformanceLowerSeverityDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-lower-severity-loading');
  static const ValueKey<String> severityKey =
      ValueKey<String>('nonconformance-lower-severity-value');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-lower-severity-note');
  static final ValueKey<String> submitKey =
      AppDialog.actionKey('nonconformance-lower-severity-submit');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('nonconformance-lower-severity-cancel');
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final record = widget.nonconformance;
    final offerable = _offerableSeverities;

    // Read here, in a build, for the reason the Screen reads it there: a value
    // frozen when the route first built would answer for a half-known Account.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AppDialog(
        key: NonconformanceLowerSeverityDialog.refusedKey,
        title: l10n.nonconformanceLowerSeverityCannotLowerIt,
        size: AppDialogSize.decision,
        description:
            l10n.nonconformanceLowerSeverityLoweringASeverityNeedsQualityAuthorityAt,
        actions: [
          AppDialogAction(
            id: 'nonconformance-lower-severity-refused-close',
            label: l10n.downtimeClose,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: l10n.nonconformanceLowerSeverity,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'nonconformance-lower-severity-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'nonconformance-lower-severity-submit',
            label: l10n.nonconformanceLowerSeverityLowerIt,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.nonconformanceLowerSeverityIsSeverityAndItsDefectCodeStarts(record.issueNo, record.severityLabel(l10n).toLowerCase(), defectSeverityLabel(l10n, record.defectCodeDefaultSeverity).toLowerCase()),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            if (offerable.isEmpty)
              Text(
                l10n.nonconformanceLowerSeverityThisNonConformanceIsAlreadyAtThe,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              DropdownButtonFormField<String?>(
                key: NonconformanceLowerSeverityDialog.severityKey,
                initialValue: _severity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.nonconformanceLowerSeverityLowerTheSeverityTo,
                  helperText: l10n.nonconformanceLowerSeverityLoweringWhatTheDefectCodeSaysNeeds,
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
            const SizedBox(height: Spacing.md),
            TextField(
              key: NonconformanceLowerSeverityDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonNote,
                helperText: l10n.nonconformanceLowerSeverityWhyItIsLessBadThanThe,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: NonconformanceLowerSeverityDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
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
