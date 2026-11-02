/// Cancelling a Non-conformance recorded in error (issue #206).
///
/// Addressed rather than popped — `/non-conformances/:id/cancel` (ADR-0021) —
/// and offered only to a caller holding Quality authority at the record's Org
/// Unit; the API refuses anyone else with a 403.
///
/// The mistake this control exists for is a record that should never have been
/// written down at all — the wrong Product, a duplicate of one already on the
/// log. A closed record is not offered it: the API refuses it with a 409 and
/// tells the caller to reopen first, because "this record was finished" and
/// "this record never happened" are two different statements about the same
/// row. The note is required, and a cancelled record accepts nothing further.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceCancelDialog extends StatefulWidget {
  const NonconformanceCancelDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey = ValueKey<String>('nonconformance-cancel-loading');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-cancel-note');
  static final ValueKey<String> submitKey =
      AppDialog.actionKey('nonconformance-cancel-submit');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('nonconformance-cancel-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-cancel-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('nonconformance-cancel-refused');

  @override
  State<NonconformanceCancelDialog> createState() => _NonconformanceCancelDialogState();
}

class _NonconformanceCancelDialogState extends State<NonconformanceCancelDialog> {
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _complete => _note.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(NonconformanceCancelled(note: _note.text));
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

    // Read here, in a build, for the reason the Screen reads it there. A
    // record that is closed or already cancelled cannot be cancelled, which
    // the API refuses with a 409 — said at the address rather than left to a
    // form that cannot succeed.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AppDialog(
        key: NonconformanceCancelDialog.refusedKey,
        title: 'Cannot cancel it',
        size: AppDialogSize.decision,
        description: 'Cancelling a Non-conformance needs Quality authority at its Org Unit.',
        actions: [
          AppDialogAction(
            id: 'nonconformance-cancel-refused-close',
            label: 'Close',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    if (!record.canBeCancelled) {
      return AppDialog(
        key: NonconformanceCancelDialog.refusedKey,
        title: 'Cannot cancel it',
        size: AppDialogSize.decision,
        description: 'A Non-conformance that is closed or already cancelled cannot be cancelled.',
        actions: [
          AppDialogAction(
            id: 'nonconformance-cancel-refused-close',
            label: 'Close',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: 'Cancel this Non-conformance',
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'nonconformance-cancel-dismiss',
            label: 'Leave it alone',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'nonconformance-cancel-submit',
            label: 'Cancel it',
            kind: AppDialogActionKind.destructive,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.nonconformance.issueNo} will be cancelled rather than dealt with. A '
              'cancelled Non-conformance accepts no further Dispositions or quantity changes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: NonconformanceCancelDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Note',
                helperText: 'Why it should never have been recorded.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: NonconformanceCancelDialog.failureKey,
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
