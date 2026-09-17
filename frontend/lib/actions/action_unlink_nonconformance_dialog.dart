/// Unlinking a Non-conformance from a Concern (issue #208).
///
/// Addressed rather than popped —
/// `/actions/:id/nonconformances/:nonconformanceId/unlink` (ADR-0021) — so a
/// refresh lands on the Concern with the confirmation open, and the address
/// names both ends of the link it is about.
///
/// **This is the act of taking an occurrence back out.** Two Non-conformances
/// that looked like the same problem and turned out not to be are two links
/// that should not be there, and what this removes is the link and never the
/// record: the Non-conformance keeps its number, its Dispositions and its
/// quantity history, and the Concern keeps every other occurrence it answers.
///
/// One refusal is worth reading, and the server says it: the Non-conformance
/// the Concern was *raised from* cannot be unlinked, because the Concern
/// records where it came from. The dialog stays open with that sentence in it
/// rather than closing as though something had happened.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

/// The address's own guard: it names one occurrence by id, and a Concern that
/// does not answer that occurrence has nothing to unlink. Saying so beats
/// opening a form whose only answer would be a 404.
class ActionUnlinkNonconformanceDialogHost extends StatelessWidget {
  const ActionUnlinkNonconformanceDialogHost({super.key, required this.nonconformanceId});

  final String nonconformanceId;

  static const ValueKey<String> loadingKey = ValueKey<String>('action-unlink-loading');
  static const ValueKey<String> notLinkedKey = ValueKey<String>('action-unlink-not-linked');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionDetailBloc>().state;

    return switch (state) {
      ActionDetailLoading() => const AlertDialog(
          key: loadingKey,
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      ActionDetailUnavailable(message: final message) => AlertDialog(
          key: notLinkedKey,
          title: const Text('That Concern could not be read'),
          content: Text(message),
          actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back'))],
        ),
      ActionDetailLoaded(action: final action) => () {
          LinkedNonconformance? found;
          for (final occurrence in action.nonconformances) {
            if (occurrence.id == nonconformanceId) found = occurrence;
          }
          if (found == null) {
            return AlertDialog(
              key: notLinkedKey,
              title: const Text('That Non-conformance is not linked here'),
              content: const Text(
                'This Concern answers nothing by that id. It may have been unlinked already, or '
                'the address may be wrong.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to the Concern'),
                ),
              ],
            );
          }
          return ActionUnlinkNonconformanceDialog(
            concernId: action.id,
            occurrence: found,
          );
        }(),
    };
  }
}

class ActionUnlinkNonconformanceDialog extends StatefulWidget {
  const ActionUnlinkNonconformanceDialog({
    super.key,
    required this.concernId,
    required this.occurrence,
  });

  final String concernId;
  final LinkedNonconformance occurrence;

  static const ValueKey<String> submitKey = ValueKey<String>('action-unlink-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-unlink-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('action-unlink-failure');

  @override
  State<ActionUnlinkNonconformanceDialog> createState() =>
      _ActionUnlinkNonconformanceDialogState();
}

class _ActionUnlinkNonconformanceDialogState extends State<ActionUnlinkNonconformanceDialog> {
  bool _awaiting = false;
  bool _done = false;
  String? _failure;

  void _submit() {
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<ActionDetailBloc>().add(
          ActionNonconformanceUnlinked(
            actionId: widget.concernId,
            nonconformanceId: widget.occurrence.id,
          ),
        );
  }

  /// The Bloc reports the outcome on its own state, so this is where the
  /// dialog learns the link is gone — or why it is not.
  void _onDetailChanged(BuildContext context, ActionDetailState state) {
    if (_done || !_awaiting) return;
    if (state is! ActionDetailLoaded) return;
    if (state.isUnlinking) return;
    final failure = state.unlinkFailure;
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
    final occurrence = widget.occurrence;

    return BlocListener<ActionDetailBloc, ActionDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Unlink this Non-conformance'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(occurrence.issueNo, style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                '${occurrence.productLabel} · ${occurrence.defectCodeLabel} · '
                '${occurrence.quantityLabel}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'It stops being one of the occurrences this Concern answers. The Non-conformance '
                'itself is untouched — it keeps its number, its Dispositions and its quantity.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_failure != null)
                Padding(
                  key: ActionUnlinkNonconformanceDialog.failureKey,
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
            key: ActionUnlinkNonconformanceDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it linked'),
          ),
          FilledButton(
            key: ActionUnlinkNonconformanceDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Unlink it'),
          ),
        ],
      ),
    );
  }
}
