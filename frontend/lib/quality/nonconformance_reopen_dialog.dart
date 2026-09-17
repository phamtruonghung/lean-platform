/// Reopening a closed Non-conformance (issue #206).
///
/// Addressed rather than popped — `/non-conformances/:id/reopen` (ADR-0021) —
/// and offered only to a caller holding Quality authority at the record's Org
/// Unit; the API refuses anyone else with a 403.
///
/// Only a closed record can be reopened, which is why the Screen offers this
/// address on a closed record alone. A reopened record goes back to
/// `dispositioned`, and the way to close it again is the way it closed the
/// first time: raise the affected quantity because sorting found more, and
/// dispose of the rest. The note is required — the reason a record was
/// reopened is exactly what a later reader asks about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceReopenDialog extends StatefulWidget {
  const NonconformanceReopenDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  static const ValueKey<String> loadingKey = ValueKey<String>('nonconformance-reopen-loading');
  static const ValueKey<String> noteKey = ValueKey<String>('nonconformance-reopen-note');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-reopen-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-reopen-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-reopen-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('nonconformance-reopen-refused');

  @override
  State<NonconformanceReopenDialog> createState() => _NonconformanceReopenDialogState();
}

class _NonconformanceReopenDialogState extends State<NonconformanceReopenDialog> {
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
    context.read<NonconformanceDetailBloc>().add(NonconformanceReopened(note: _note.text));
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

    // Read here, in a build, for the reason the Screen reads it there. Only a
    // closed record can be reopened, which the API refuses with a 409 — this
    // says so at the address rather than letting a refresh land on a form that
    // cannot succeed.
    if (!holdsQualityAuthority(context, record.orgUnitId)) {
      return AlertDialog(
        key: NonconformanceReopenDialog.refusedKey,
        content: const Text(
          'Reopening a Non-conformance needs Quality authority at its Org Unit.',
        ),
      );
    }
    if (!record.canBeReopened) {
      return AlertDialog(
        key: NonconformanceReopenDialog.refusedKey,
        content: const Text('Only a closed Non-conformance can be reopened.'),
      );
    }

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Reopen this Non-conformance'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.nonconformance.issueNo} is closed. Reopening it puts it back to '
                  'dispositioned, and its closing time goes with it.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: NonconformanceReopenDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    helperText: 'Why it is being reopened.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: NonconformanceReopenDialog.failureKey,
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
            key: NonconformanceReopenDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceReopenDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Reopen it'),
          ),
        ],
      ),
    );
  }
}
