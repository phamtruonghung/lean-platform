/// The three things a team does to a CAPA's 5 Why chains (issue #210), each at
/// its own address (ADR-0021) and each nested under the investigation's own
/// route so it shares the `CapaDetailBloc` the Screen behind it is reading:
///
///   - `${Routes.actions}/capas/:id/whys/:chain/new` — add a Why to a chain,
///   - `${Routes.actions}/capas/:id/whys/:chain/:whyId/edit` — revise one,
///   - `${Routes.actions}/capas/:id/whys/:chain/:whyId/remove` — take one out.
///
/// Addressed rather than popped for the reason every other dialog in this
/// Platform is: a refresh lands on the investigation with the form open, and
/// the act has somewhere to be linked to.
///
/// **A chain's dialogs refuse where the server would.** Two of this ticket's
/// rules can be answered without a round trip — the caller may not write this
/// CAPA's chains (`mayEditCapaChains`: edit access at its Org Unit, or a place
/// on its team), and a closed investigation is a record. Each of those is said
/// on the address rather than shown as a form whose submit would come back 403
/// or 409, which is the same shape `OpenCapaDialog` takes for an address
/// reached by somebody without the authority to open one.
///
/// What the forms deliberately do not offer: choosing a chain (the address the
/// form was reached at names it), a position (a Why is added at the next one,
/// and moved by the chain's own controls), or a `capaId`. Every one of those is
/// already said by the address or by the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'capa.dart';
import 'capa_detail_bloc.dart';

/// The keys every one of the three addresses shares, because the refusals are
/// the same refusals: no CAPA read yet, a CAPA that cannot be read, a chain
/// that does not exist, an investigation that is over, a caller who may not
/// write one, and a Why that is not in the chain the address names.
abstract final class CapaWhyKeys {
  static const ValueKey<String> loadingKey = ValueKey<String>('capa-why-loading');
  static const ValueKey<String> notLoadedKey = ValueKey<String>('capa-why-not-loaded');
  static const ValueKey<String> unknownChainKey = ValueKey<String>('capa-why-unknown-chain');
  static const ValueKey<String> closedKey = ValueKey<String>('capa-why-closed');
  static const ValueKey<String> refusedKey = ValueKey<String>('capa-why-refused');
  static const ValueKey<String> missingWhyKey = ValueKey<String>('capa-why-missing');

  /// The way out of a refusal. Every one of these dialogs carries one, because
  /// a `DialogPage` is not `barrierDismissible` (see `dialog_page.dart`): a
  /// refusal with no control of its own would leave a person tapping outside a
  /// dialog that never closes.
  static const ValueKey<String> dismissKey = ValueKey<String>('capa-why-dismiss');
}

/// The one way out every refusal here offers, and where it goes: back to the
/// investigation the address was reached from.
Widget _dismissButton(BuildContext context) => TextButton(
      key: CapaWhyKeys.dismissKey,
      onPressed: () => context.pop(),
      child: const Text('Back to the CAPA'),
    );

/// What this address says when it is not one the CAPA it names can answer — or
/// null when it is, in which case the caller renders its own form.
///
/// Ordered as the server's own gates are: is there a record to read at all, is
/// the chain one of the two, is the investigation still open, may this caller
/// write, and is the Why in the chain. The order is what a person needs to fix
/// first — an address naming a chain that does not exist is a typo whether or
/// not the CAPA is closed.
Widget? capaWhyAddressRefusal(
  BuildContext context,
  CapaDetailState state, {
  required String chain,
  required String? whyId,
}) {
  switch (state) {
    case CapaDetailLoading():
      return const AlertDialog(
        key: CapaWhyKeys.loadingKey,
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    case CapaDetailUnavailable(message: final message):
      return AlertDialog(
        key: CapaWhyKeys.notLoadedKey,
        title: const Text('That CAPA could not be read'),
        content: Text(message),
        actions: [_dismissButton(context)],
      );
    case CapaDetailLoaded(capa: final capa):
      if (!capaChainOrder.contains(chain)) {
        return AlertDialog(
          key: CapaWhyKeys.unknownChainKey,
          title: const Text('That is not a chain'),
          content: const Text(
            'A CAPA reasons with two chains: why the problem happened, and why it was not detected.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (!capa.isOpen) {
        return AlertDialog(
          key: CapaWhyKeys.closedKey,
          title: const Text('This investigation is over'),
          content: Text(
            '${capa.capaNo} is ${capa.statusLabel.toLowerCase()}, so its chains are a record '
            'rather than a worklist.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (!mayEditCapaChains(context, capa)) {
        return AlertDialog(
          key: CapaWhyKeys.refusedKey,
          title: const Text('Not yours to write'),
          content: const Text(
            "Writing a CAPA's root causes needs edit access at its Org Unit, or a place on "
            'its team.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (whyId != null && capa.whysIn(chain).every((why) => why.id != whyId)) {
        return AlertDialog(
          key: CapaWhyKeys.missingWhyKey,
          title: const Text('That Why is not in this chain'),
          content: const Text('It may have been removed a moment ago by somebody else.'),
          actions: [_dismissButton(context)],
        );
      }
      return null;
  }
}

/// Adding a Why to one of a CAPA's chains — `.../whys/:chain/new`.
class CapaWhyDialog extends StatelessWidget {
  const CapaWhyDialog({super.key, required this.chain});

  /// The chain the address named. Taken from the address rather than chosen in
  /// the form: which chain a Why belongs to is the decision the caller made by
  /// opening this address, and a Why never moves between chains.
  final String chain;

  static const ValueKey<String> statementKey = ValueKey<String>('capa-why-add-statement');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-why-add-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-why-add-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-why-add-failure');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaWhyAddressRefusal(context, state, chain: chain, whyId: null);
    if (refusal != null) return refusal;

    return _WhyForm(
      chain: chain,
      title: 'Add a Why',
      submitLabel: 'Add it',
      statementKey: statementKey,
      submitKey: submitKey,
      cancelKey: cancelKey,
      failureKey: failureKey,
      onSubmit: (statement) => context
          .read<CapaDetailBloc>()
          .add(CapaDetailWhyAdded(chain: chain, statement: statement)),
    );
  }
}

/// Revising a Why — `.../whys/:chain/:whyId/edit`.
class CapaWhyEditDialog extends StatelessWidget {
  const CapaWhyEditDialog({super.key, required this.chain, required this.whyId});

  final String chain;
  final String whyId;

  static const ValueKey<String> statementKey = ValueKey<String>('capa-why-edit-statement');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-why-edit-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-why-edit-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-why-edit-failure');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaWhyAddressRefusal(context, state, chain: chain, whyId: whyId);
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final why = capa.whysIn(chain).firstWhere((each) => each.id == whyId);

    return _WhyForm(
      chain: chain,
      title: 'Revise Why ${why.sequence}',
      submitLabel: 'Save it',
      statementKey: statementKey,
      submitKey: submitKey,
      cancelKey: cancelKey,
      failureKey: failureKey,
      initial: why.statement,
      onSubmit: (statement) => context
          .read<CapaDetailBloc>()
          .add(CapaDetailWhyChanged(whyId: whyId, statement: statement)),
    );
  }
}

/// Taking a Why out of a chain — `.../whys/:chain/:whyId/remove`.
///
/// A confirmation rather than a one-tap button, because the row does not come
/// back: the chain is the record of what the team reasoned, and a Why removed
/// is a line the reader of the chain will never see.
class CapaWhyRemoveDialog extends StatefulWidget {
  const CapaWhyRemoveDialog({super.key, required this.chain, required this.whyId});

  final String chain;
  final String whyId;

  static const ValueKey<String> confirmKey = ValueKey<String>('capa-why-remove-confirm');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-why-remove-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-why-remove-failure');

  @override
  State<CapaWhyRemoveDialog> createState() => _CapaWhyRemoveDialogState();
}

class _CapaWhyRemoveDialogState extends State<CapaWhyRemoveDialog> {
  bool _awaiting = false;
  String? _failure;

  /// Whether this dialog has already finished — a second pop would take the
  /// investigation's own page off the stack behind it.
  bool _done = false;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<CapaDetailBloc>().add(CapaDetailWhyRemoved(widget.whyId));
  }

  void _onChanged(BuildContext context, CapaDetailState state) {
    if (_done || !_awaiting || state is! CapaDetailLoaded || state.isMutating) return;
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
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaWhyAddressRefusal(
      context,
      state,
      chain: widget.chain,
      whyId: widget.whyId,
    );
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final why = capa.whysIn(widget.chain).firstWhere((each) => each.id == widget.whyId);

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: Text('Remove Why ${why.sequence}?'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                why.statement,
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'It is taken out of the chain for good, and the Whys after it move up one. '
                'The rest of the investigation is not touched.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_failure != null)
                Padding(
                  key: CapaWhyRemoveDialog.failureKey,
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
            key: CapaWhyRemoveDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CapaWhyRemoveDialog.confirmKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Remove it'),
          ),
        ],
      ),
    );
  }
}

/// The one-line form both the add and the revise address use: what the Why
/// says, and nothing else.
///
/// Shared because the two addresses collect the same field and differ only in
/// what they do with it — and because a second copy of a form is a second place
/// its rules have to be kept. The keys differ per address so a test can say
/// which one it drove.
class _WhyForm extends StatefulWidget {
  const _WhyForm({
    required this.chain,
    required this.title,
    required this.submitLabel,
    required this.statementKey,
    required this.submitKey,
    required this.cancelKey,
    required this.failureKey,
    required this.onSubmit,
    this.initial,
  });

  final String chain;
  final String title;
  final String submitLabel;
  final ValueKey<String> statementKey;
  final ValueKey<String> submitKey;
  final ValueKey<String> cancelKey;
  final ValueKey<String> failureKey;
  final String? initial;
  final void Function(String statement) onSubmit;

  @override
  State<_WhyForm> createState() => _WhyFormState();
}

class _WhyFormState extends State<_WhyForm> {
  late final TextEditingController _statement = TextEditingController(text: widget.initial ?? '');

  bool _awaiting = false;
  String? _failure;

  /// Whether this form has already finished — a second pop would take the
  /// investigation's own page off the stack behind it.
  bool _done = false;

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  /// A Why has to say something: the same rule the server enforces with a 400,
  /// said here so the button is closed rather than the request refused.
  bool get _complete => _statement.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    widget.onSubmit(_statement.text.trim());
  }

  void _onChanged(BuildContext context, CapaDetailState state) {
    if (_done || !_awaiting || state is! CapaDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      // The refusal stays in the form with what was written still in it.
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

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${capaChainLabel(widget.chain)} — one step of the reasoning, in your own words.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: widget.statementKey,
                controller: _statement,
                enabled: !_awaiting,
                autofocus: true,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'The Why',
                  helperText: 'What you found, said so the next person can follow it.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_failure != null)
                Padding(
                  key: widget.failureKey,
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
            key: widget.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: widget.submitKey,
            onPressed: _complete ? _submit : null,
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
