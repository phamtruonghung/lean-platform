/// The five things a team does to a CAPA's fishbone (issue #213), each at its
/// own address (ADR-0021) and each nested under the investigation's own route
/// so it shares the `CapaDetailBloc` the Screen behind it is reading:
///
///   - `${Routes.actions}/capas/:id/causes/:category/new` — record a candidate
///     cause under one 6M category,
///   - `${Routes.actions}/capas/:id/causes/:category/:causeId/edit` — revise it,
///     or file it under another of the six,
///   - `${Routes.actions}/capas/:id/causes/:category/:causeId/verdict` — decide
///     it, with the evidence for that decision,
///   - `${Routes.actions}/capas/:id/causes/:category/:causeId/remove` — take it
///     off the fishbone,
///   - `${Routes.actions}/capas/:id/causes/:category/:causeId/why` — start one
///     of the two chains from a cause the evidence confirmed.
///
/// **The category is in the address, and the cause is too.** Which of the six a
/// new cause hangs from is the decision the caller made by opening this
/// address, exactly as the chain is for a Why; and an address naming a cause
/// that is not in the category it names is refused rather than quietly edited,
/// because the one thing a fishbone is legible by is which bone a cause sits
/// on. A cause *may* be re-filed once it exists, which is what the edit form's
/// own chooser is for — the address says where it is now, the form says where
/// it should be.
///
/// **The verdict is its own address, and it takes the evidence with it.** The
/// API refuses `confirmed` or `ruled_out` without an `evidenceNote` in the same
/// request, so deciding a cause is a form rather than a button: the verdict and
/// the evidence for it are one act, and a control that sent one without the
/// other would be a control whose request is always refused. The form is
/// pre-filled with the verdict and the note already recorded, so changing a
/// decision is the same two fields rather than a second dialog.
///
/// **A fishbone address refuses where the server would**, so far as it can
/// without the record: the caller may not write this CAPA (`mayEditCapaChains`
/// — the same rule the chains use, edit access at the CAPA's Org Unit or a
/// place on its team), the investigation is closed, the category is not one of
/// the six, or the cause is not the category's. Each is said on the address
/// rather than shown as a form whose submit would come back 403, 404 or 409 —
/// the same shape `CapaWhyDialog` takes.
///
/// What the forms deliberately do not offer: a `capaId`, a `causeId` or a
/// `causeType`. Every one of those is already said by the address or by the
/// row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'capa.dart';
import 'capa_detail_bloc.dart';

/// The keys every one of the five addresses shares, because the refusals are
/// the same refusals: no CAPA read yet, a CAPA that cannot be read, a category
/// that is not one of the six, an investigation that is over, a caller who may
/// not write one, and a cause that is not in the category the address names.
abstract final class CapaCauseKeys {
  static const ValueKey<String> loadingKey = ValueKey<String>('capa-cause-loading');
  static const ValueKey<String> notLoadedKey = ValueKey<String>('capa-cause-not-loaded');
  static const ValueKey<String> unknownCategoryKey =
      ValueKey<String>('capa-cause-unknown-category');
  static const ValueKey<String> closedKey = ValueKey<String>('capa-cause-closed');
  static const ValueKey<String> refusedKey = ValueKey<String>('capa-cause-refused');
  static const ValueKey<String> missingCauseKey = ValueKey<String>('capa-cause-missing');

  /// The way out of a refusal. Every one of these dialogs carries one, because
  /// a `DialogPage` is not `barrierDismissible` (see `dialog_page.dart`): a
  /// refusal with no control of its own would leave a person tapping outside a
  /// dialog that never closes.
  static const ValueKey<String> dismissKey = ValueKey<String>('capa-cause-dismiss');
}

/// The one way out every refusal here offers, and where it goes: back to the
/// investigation the address was reached from.
Widget _dismissButton(BuildContext context) => TextButton(
      key: CapaCauseKeys.dismissKey,
      onPressed: () => context.pop(),
      child: const Text('Back to the CAPA'),
    );

/// What this address says when it is not one the CAPA it names can answer — or
/// null when it is, in which case the caller renders its own form.
///
/// Ordered as the server's own gates are: is there a record to read at all, is
/// the category one of the six, is the investigation still open, may this
/// caller write, and is the cause in the category the address names. The order
/// is what a person needs to fix first — an address naming a category that does
/// not exist is a typo whether or not the CAPA is closed.
Widget? capaCauseAddressRefusal(
  BuildContext context,
  CapaDetailState state, {
  required String category,
  required String? causeId,
}) {
  switch (state) {
    case CapaDetailLoading():
      return const AlertDialog(
        key: CapaCauseKeys.loadingKey,
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    case CapaDetailUnavailable(message: final message):
      return AlertDialog(
        key: CapaCauseKeys.notLoadedKey,
        title: const Text('That CAPA could not be read'),
        content: Text(message),
        actions: [_dismissButton(context)],
      );
    case CapaDetailLoaded(capa: final capa):
      if (!capaCauseCategoryOrder.contains(category)) {
        return AlertDialog(
          key: CapaCauseKeys.unknownCategoryKey,
          title: const Text('That is not a 6M category'),
          content: const Text(
            'A fishbone has six bones: Man, Machine, Method, Material, Measurement and Environment.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (!capa.isOpen) {
        return AlertDialog(
          key: CapaCauseKeys.closedKey,
          title: const Text('This investigation is over'),
          content: Text(
            '${capa.capaNo} is ${capa.statusLabel.toLowerCase()}, so its fishbone is a record '
            'rather than a worklist.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (!mayEditCapaChains(context, capa)) {
        return AlertDialog(
          key: CapaCauseKeys.refusedKey,
          title: const Text('Not yours to write'),
          content: const Text(
            "Writing a CAPA's root causes needs edit access at its Org Unit, or a place on "
            'its team.',
          ),
          actions: [_dismissButton(context)],
        );
      }
      if (causeId != null && capa.causesIn(category).every((cause) => cause.id != causeId)) {
        return AlertDialog(
          key: CapaCauseKeys.missingCauseKey,
          title: const Text('That cause is not on this bone'),
          content: const Text('It may have been removed a moment ago by somebody else.'),
          actions: [_dismissButton(context)],
        );
      }
      return null;
  }
}

/// Recording a candidate cause under one 6M category — `.../causes/:category/new`.
class CapaCauseDialog extends StatelessWidget {
  const CapaCauseDialog({super.key, required this.category});

  /// The bone the address named. Taken from the address rather than chosen in
  /// the form: which of the six a cause hangs from is the decision the caller
  /// made by opening this address — and the one thing a fishbone is read by.
  final String category;

  static const ValueKey<String> statementKey = ValueKey<String>('capa-cause-add-statement');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-cause-add-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-cause-add-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-cause-add-failure');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaCauseAddressRefusal(context, state, category: category, causeId: null);
    if (refusal != null) return refusal;

    return _CauseForm(
      title: 'Record a candidate cause',
      blurb: '${capaCauseCategoryLabel(category)} — something that could be behind the problem.',
      submitLabel: 'Record it',
      category: category,
      statementKey: statementKey,
      submitKey: submitKey,
      cancelKey: cancelKey,
      failureKey: failureKey,
      onSubmit: (chosenCategory, statement) => context.read<CapaDetailBloc>().add(
            CapaDetailCauseAdded(category: chosenCategory, statement: statement),
          ),
    );
  }
}

/// Revising a candidate cause, or filing it under another of the six —
/// `.../causes/:category/:causeId/edit`.
class CapaCauseEditDialog extends StatelessWidget {
  const CapaCauseEditDialog({super.key, required this.category, required this.causeId});

  final String category;
  final String causeId;

  static const ValueKey<String> statementKey = ValueKey<String>('capa-cause-edit-statement');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-cause-edit-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-cause-edit-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-cause-edit-failure');

  /// One of the six, as a choice — a cause genuinely may be re-filed (the team
  /// argues about whether a worn jig is Machine or Method), so the form offers
  /// the decision the address did not.
  static ValueKey<String> categoryKey(String wire) =>
      ValueKey<String>('capa-cause-edit-category-$wire');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaCauseAddressRefusal(context, state, category: category, causeId: causeId);
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final cause = capa.causesIn(category).firstWhere((each) => each.id == causeId);

    return _CauseForm(
      title: 'Revise the cause',
      blurb: 'What it says, and which of the six it is filed under.',
      submitLabel: 'Save it',
      category: cause.category,
      choosesCategory: true,
      statementKey: statementKey,
      submitKey: submitKey,
      cancelKey: cancelKey,
      failureKey: failureKey,
      initial: cause.statement,
      onSubmit: (chosen, statement) => context.read<CapaDetailBloc>().add(
            CapaDetailCauseChanged(
              causeId: causeId,
              // The category is sent only when it actually moved: a revision of
              // the sentence alone is one field, the partial update the API takes.
              category: chosen == cause.category ? null : chosen,
              statement: statement,
            ),
          ),
    );
  }
}

/// Deciding a candidate cause — `.../causes/:category/:causeId/verdict`.
///
/// The one address here whose form is not a revision: `confirmed` and
/// `ruled_out` are what a fishbone exists to produce, and the API will not take
/// either without the evidence note that backs it, so the two fields are
/// written together.
class CapaCauseVerdictDialog extends StatelessWidget {
  const CapaCauseVerdictDialog({super.key, required this.category, required this.causeId});

  final String category;
  final String causeId;

  static const ValueKey<String> evidenceKey = ValueKey<String>('capa-cause-verdict-evidence');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-cause-verdict-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-cause-verdict-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-cause-verdict-failure');

  /// One of the two decisions, as a choice.
  static ValueKey<String> verdictKey(String wire) =>
      ValueKey<String>('capa-cause-verdict-$wire');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaCauseAddressRefusal(context, state, category: category, causeId: causeId);
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final cause = capa.causesIn(category).firstWhere((each) => each.id == causeId);

    return _VerdictForm(cause: cause);
  }
}

/// Taking a candidate cause off the fishbone — `.../causes/:category/:causeId/remove`.
///
/// A confirmation rather than a one-tap button, because the row does not come
/// back: the fishbone is the record of what the team considered, and a cause
/// removed is one the reader will never see.
class CapaCauseRemoveDialog extends StatefulWidget {
  const CapaCauseRemoveDialog({super.key, required this.category, required this.causeId});

  final String category;
  final String causeId;

  static const ValueKey<String> confirmKey = ValueKey<String>('capa-cause-remove-confirm');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-cause-remove-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-cause-remove-failure');

  @override
  State<CapaCauseRemoveDialog> createState() => _CapaCauseRemoveDialogState();
}

class _CapaCauseRemoveDialogState extends State<CapaCauseRemoveDialog> {
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
    context.read<CapaDetailBloc>().add(CapaDetailCauseRemoved(widget.causeId));
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
    final refusal = capaCauseAddressRefusal(
      context,
      state,
      category: widget.category,
      causeId: widget.causeId,
    );
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final cause = capa.causesIn(widget.category).firstWhere((each) => each.id == widget.causeId);

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Remove this cause?'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cause.statement,
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'It is taken off the ${cause.categoryLabel} bone for good'
                '${cause.isConfirmed ? ', including the verdict your evidence backed' : ''}. '
                'A chain started from it keeps the Why it began with.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_failure != null)
                Padding(
                  key: CapaCauseRemoveDialog.failureKey,
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
            key: CapaCauseRemoveDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CapaCauseRemoveDialog.confirmKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Remove it'),
          ),
        ],
      ),
    );
  }
}

/// Starting one of the two chains from a confirmed cause —
/// `.../causes/:category/:causeId/why`.
///
/// The one act on this Screen that is about the *chain* rather than the cause,
/// which is why the address sits under the cause: what a chain begins with is
/// the sentence the cause says, and the chain to begin is the other decision
/// the form collects. Only a cause the evidence confirmed is offered this
/// (see `_Fishbone`), and only a chain that has not started is offered as a
/// choice — a chain's first Why is written once.
///
/// A CAPA whose every chain has started is refused here with a sentence of its
/// own rather than shown a form with nothing to choose: that is a real state (a
/// team may confirm a cause after both chains are under way), and the honest
/// answer is that the Why belongs in a chain by `addCapaWhy` rather than at the
/// head of one.
class CapaWhyFromCauseDialog extends StatelessWidget {
  const CapaWhyFromCauseDialog({super.key, required this.category, required this.causeId});

  final String category;
  final String causeId;

  static const ValueKey<String> statementKey = ValueKey<String>('capa-cause-why-statement');
  static const ValueKey<String> submitKey = ValueKey<String>('capa-cause-why-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('capa-cause-why-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-cause-why-failure');
  static const ValueKey<String> noChainKey = ValueKey<String>('capa-cause-why-no-chain');

  /// One of the chains that has not started, as a choice.
  static ValueKey<String> chainKey(String chain) => ValueKey<String>('capa-cause-why-chain-$chain');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaCauseAddressRefusal(context, state, category: category, causeId: causeId);
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;
    final cause = capa.causesIn(category).firstWhere((each) => each.id == causeId);

    if (capa.chainsNotStarted.isEmpty) {
      return AlertDialog(
        key: noChainKey,
        title: const Text('Both chains have been started'),
        content: Text(
          '${capa.capaNo} already reasons both why the problem happened and why it was not '
          'detected, so the Why for this cause belongs in one of them rather than at the head '
          'of a chain.',
        ),
        actions: [_dismissButton(context)],
      );
    }

    return _StartChainForm(cause: cause, chains: capa.chainsNotStarted);
  }
}

/// The form every fishbone address uses to collect what a cause says and, when
/// the address allows it, which of the six it belongs to.
///
/// Shared because four of the five addresses collect the same fields and differ
/// only in what they do with them — and because a second copy of a form is a
/// second place its rules have to be kept. The keys differ per address so a
/// test can say which one it drove.
class _CauseForm extends StatefulWidget {
  const _CauseForm({
    required this.title,
    required this.blurb,
    required this.submitLabel,
    required this.category,
    required this.statementKey,
    required this.submitKey,
    required this.cancelKey,
    required this.failureKey,
    required this.onSubmit,
    this.choosesCategory = false,
    this.initial,
  });

  final String title;
  final String blurb;
  final String submitLabel;

  /// The category the cause is under, and the one the form starts at. On the
  /// add address it is the address's own bone; on the revise address it is
  /// where the cause sits now, and [choosesCategory] is what lets it move.
  final String category;

  /// Whether the form offers the other five bones — set only by the revise
  /// address, which is the one that may re-file a cause.
  final bool choosesCategory;

  final ValueKey<String> statementKey;
  final ValueKey<String> submitKey;
  final ValueKey<String> cancelKey;
  final ValueKey<String> failureKey;
  final String? initial;

  /// The chosen category and what the cause says.
  final void Function(String category, String statement) onSubmit;

  @override
  State<_CauseForm> createState() => _CauseFormState();
}

class _CauseFormState extends State<_CauseForm> {
  late final TextEditingController _statement = TextEditingController(text: widget.initial ?? '');
  late String _category = widget.category;

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

  /// A cause has to say something: the same rule the server enforces with a 400,
  /// said here so the button is closed rather than the request refused.
  bool get _complete => _statement.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    widget.onSubmit(_category, _statement.text.trim());
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
    final choosesCategory = widget.choosesCategory;

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
              Text(widget.blurb, style: theme.textTheme.bodyMedium),
              if (choosesCategory) ...[
                const SizedBox(height: Spacing.md),
                Text('The bone it hangs from', style: theme.textTheme.bodySmall),
                const SizedBox(height: Spacing.xs),
                // A `Wrap` of choices rather than a `Row`, for the reason every
                // row of controls in this client is one: six labels at the
                // widget tests' own surface would overflow a Row.
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final category in capaCauseCategoryOrder)
                      ChoiceChip(
                        key: CapaCauseEditDialog.categoryKey(category),
                        label: Text(capaCauseCategoryLabel(category)),
                        selected: _category == category,
                        onSelected: _awaiting
                            ? null
                            : (_) => setState(() => _category = category),
                      ),
                  ],
                ),
              ],
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
                  labelText: 'The candidate cause',
                  helperText: 'What you suspect, said so the next person can check it.',
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

/// The verdict and the evidence for it — one act, two fields.
///
/// The submit gate is the API's own rule: a cause cannot be confirmed or ruled
/// out without the note saying what the evidence was, so the button stays
/// closed until both are there rather than sending a request that comes back
/// 400. Both fields start at what the record already says, so changing a
/// decision somebody made earlier is an edit rather than starting again.
class _VerdictForm extends StatefulWidget {
  const _VerdictForm({required this.cause});

  final CapaCause cause;

  @override
  State<_VerdictForm> createState() => _VerdictFormState();
}

class _VerdictFormState extends State<_VerdictForm> {
  late final TextEditingController _evidence =
      TextEditingController(text: widget.cause.evidenceNote ?? '');
  late String _verdict =
      capaCauseDecisions.contains(widget.cause.verdict) ? widget.cause.verdict : 'confirmed';

  bool _awaiting = false;
  String? _failure;

  /// Whether this form has already finished — a second pop would take the
  /// investigation's own page off the stack behind it.
  bool _done = false;

  @override
  void dispose() {
    _evidence.dispose();
    super.dispose();
  }

  bool get _complete => _evidence.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<CapaDetailBloc>().add(
          CapaDetailCauseChanged(
            causeId: widget.cause.id,
            verdict: _verdict,
            evidenceNote: _evidence.text.trim(),
          ),
        );
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

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Decide this cause'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.cause.statement,
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'A verdict is a decision the report reads back, so it is recorded with the '
                'evidence for it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final decision in capaCauseDecisions)
                    ChoiceChip(
                      key: CapaCauseVerdictDialog.verdictKey(decision),
                      label: Text(capaCauseVerdictLabel(decision)),
                      selected: _verdict == decision,
                      onSelected:
                          _awaiting ? null : (_) => setState(() => _verdict = decision),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: CapaCauseVerdictDialog.evidenceKey,
                controller: _evidence,
                enabled: !_awaiting,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'The evidence',
                  helperText: 'What you looked at, and what it showed.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_failure != null)
                Padding(
                  key: CapaCauseVerdictDialog.failureKey,
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
            key: CapaCauseVerdictDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CapaCauseVerdictDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Record the verdict'),
          ),
        ],
      ),
    );
  }
}

/// Which chain to begin, and what its first Why says — defaulting to the cause's
/// own sentence, because that is what a chain started from a confirmed cause
/// begins with.
class _StartChainForm extends StatefulWidget {
  const _StartChainForm({required this.cause, required this.chains});

  final CapaCause cause;

  /// The chains that have not started, in the order they are reasoned.
  final List<String> chains;

  @override
  State<_StartChainForm> createState() => _StartChainFormState();
}

class _StartChainFormState extends State<_StartChainForm> {
  late final TextEditingController _statement =
      TextEditingController(text: widget.cause.statement);
  late String _chain = widget.chains.first;

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

  bool get _complete => _statement.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<CapaDetailBloc>().add(
          CapaDetailWhyStartedFromCause(
            causeId: widget.cause.id,
            chain: _chain,
            statement: _statement.text.trim(),
          ),
        );
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

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AlertDialog(
        title: const Text('Start a chain from this cause'),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The evidence confirmed this cause, so a chain may begin with it. What it says '
                'is the first Why.',
                style: theme.textTheme.bodyMedium,
              ),
              if (widget.chains.length > 1) ...[
                const SizedBox(height: Spacing.md),
                Text('Which chain it begins', style: theme.textTheme.bodySmall),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final chain in widget.chains)
                      ChoiceChip(
                        key: CapaWhyFromCauseDialog.chainKey(chain),
                        label: Text(capaChainLabel(chain)),
                        selected: _chain == chain,
                        onSelected:
                            _awaiting ? null : (_) => setState(() => _chain = chain),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Spacing.md),
              TextField(
                key: CapaWhyFromCauseDialog.statementKey,
                controller: _statement,
                enabled: !_awaiting,
                autofocus: true,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'The first Why',
                  helperText: 'The confirmed cause, said the way the chain should read.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_failure != null)
                Padding(
                  key: CapaWhyFromCauseDialog.failureKey,
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
            key: CapaWhyFromCauseDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CapaWhyFromCauseDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Start the chain'),
          ),
        ],
      ),
    );
  }
}
