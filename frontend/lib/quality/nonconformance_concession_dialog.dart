/// Granting a Concession (issue #206): accepting the product as it is, rather
/// than dealing with it.
///
/// Addressed rather than popped — `/non-conformances/:id/concession`
/// (ADR-0021). The Screen offers this address only to a caller holding Quality
/// authority at the record's Org Unit (`OrgUnitScope.canHoldQualityAt`, the
/// client's half of the server's `canAct({ quality: true })`), and the API is
/// the gate: it refuses anyone else with a 403 whatever this dialog does.
///
/// **The reference and the note are both required**, because the two things an
/// auditor asks about a Concession are what authorises it and why it was
/// granted — the deviation number, and the reason. The granting Account is not
/// a field: the API records whoever sends the request, and the record reads it
/// back as the Disposition's own `decidedByAccountName`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';
import '../widgets/notice_text.dart';

class NonconformanceConcessionDialog extends StatefulWidget {
  const NonconformanceConcessionDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-concession-loading');
  static const ValueKey<String> quantityKey =
      ValueKey<String>('nonconformance-concession-quantity');
  static const ValueKey<String> referenceKey =
      ValueKey<String>('nonconformance-concession-reference');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-concession-note');
  static final ValueKey<String> submitKey =
      AppDialog.actionKey('nonconformance-concession-submit');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('nonconformance-concession-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-concession-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('nonconformance-concession-refused');

  @override
  State<NonconformanceConcessionDialog> createState() =>
      _NonconformanceConcessionDialogState();
}

class _NonconformanceConcessionDialogState extends State<NonconformanceConcessionDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _quantity.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedQuantity {
    final text = _quantity.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  bool get _complete {
    final value = _parsedQuantity;
    return value != null &&
        value > 0 &&
        value <= widget.nonconformance.undispositionedQuantity &&
        _reference.text.trim().isNotEmpty &&
        _note.text.trim().isNotEmpty &&
        !_awaiting;
  }

  void _submit() {
    final value = _parsedQuantity;
    if (!_complete || value == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceConcessionGranted(
            quantity: value,
            reference: _reference.text,
            note: _note.text,
          ),
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
    final unit = record.uomCode;

    // Quality authority is read here, in a build (ADR-0035) rather than passed
    // in from the route: this address can be reached by a refresh, and a
    // decision made before `/me` answered would be a decision made on a
    // half-known Account. The server refuses either way; this says why.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AppDialog(
        key: NonconformanceConcessionDialog.refusedKey,
        title: l10n.nonconformanceConcessionCannotGrantIt,
        size: AppDialogSize.decision,
        description:
            l10n.nonconformanceConcessionGrantingAConcessionNeedsQualityAuthorityAt,
        actions: [
          AppDialogAction(
            id: 'nonconformance-concession-refused-close',
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
        title: l10n.nonconformanceConcession,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'nonconformance-concession-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'nonconformance-concession-submit',
            label: l10n.nonconformanceConcessionGrantIt,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.nonconformanceConcessionAcceptingTheProductAsItIsNeeds(record.issueNo),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: NonconformanceConcessionDialog.quantityKey,
              controller: _quantity,
              enabled: !_awaiting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.nonconformanceConcessionQuantityAcceptedAsItIs,
                helperText: l10n.nonconformanceConcessionAtMost(_number(record.undispositionedQuantity), unit),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: NonconformanceConcessionDialog.referenceKey,
              controller: _reference,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.nonconformanceConcessionReference,
                helperText: l10n.nonconformanceConcessionTheDeviationOrApprovalNumberItIs,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: NonconformanceConcessionDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonNote,
                helperText: l10n.nonconformanceConcessionWhyTheProductIsAcceptableAsIt,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: NonconformanceConcessionDialog.failureKey,
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

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
