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
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceCancelDialog extends StatefulWidget {
  const NonconformanceCancelDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey = ValueKey<String>('nonconformance-cancel-loading');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-cancel-note');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-cancel-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-cancel-dismiss');
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
      return AlertDialog(
        key: NonconformanceCancelDialog.refusedKey,
        content: const Text(
          'Cancelling a Non-conformance needs Quality authority at its Org Unit.',
        ),
      );
    }
    if (!record.canBeCancelled) {
      return AlertDialog(
        key: NonconformanceCancelDialog.refusedKey,
        content: const Text(
          'A Non-conformance that is closed or already cancelled cannot be cancelled.',
        ),
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Cancel this Non-conformance'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
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
            key: NonconformanceCancelDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Leave it alone'),
          ),
          FilledButton(
            key: NonconformanceCancelDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );
  }
}
