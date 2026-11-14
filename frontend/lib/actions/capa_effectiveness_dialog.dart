/// Recording a CAPA's effectiveness check (issue #211), at its own address
/// (ADR-0021) and nested under the investigation's own route so it shares the
/// `CapaDetailBloc` the Screen behind it is reading:
///
///   - `${Routes.actions}/capas/:id/effectiveness` — the verdict, and the note
///     that is its evidence.
///
/// Addressed rather than popped for the same reason the three chain dialogs
/// are: a refresh lands on the investigation with the form open, and the act has
/// somewhere to be linked to.
///
/// **What this address says when it cannot answer.** Two of the server's own
/// rules can be answered without a round trip — the caller must hold Quality
/// authority at the CAPA's Org Unit, and must not be the team lead's Account —
/// and both are said on the address rather than shown as a form whose submit
/// would come back 403. The team lead gets words of their own, because "not
/// yours to do" and "not yours to do *because you are the one who led it*" are
/// different sentences and only the second explains the rule (CONTEXT.md's CAPA
/// entry: "someone holding Quality authority other than its team lead").
///
/// What the form deliberately does not offer: the verifier (it is the caller's
/// own Account — a check recorded on somebody else's behalf is not a check), a
/// time (the server's clock), and the due date, the status or the Concern's
/// reopening, every one of which is a consequence of the verdict rather than a
/// field to fill in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'capa.dart';
import 'capa_detail_bloc.dart';
import '../l10n/vocabulary.dart';
import '../widgets/notice_text.dart';

/// The keys this one address uses: no CAPA read yet, a CAPA that cannot be
/// read, an investigation that is over, a caller without Quality authority, a
/// caller who is the team lead, and the two controls the form itself has.
abstract final class CapaEffectivenessKeys {
  static const ValueKey<String> loadingKey = ValueKey<String>('capa-effectiveness-loading');
  static const ValueKey<String> notLoadedKey = ValueKey<String>('capa-effectiveness-not-loaded');
  static const ValueKey<String> closedKey = ValueKey<String>('capa-effectiveness-closed');
  static const ValueKey<String> refusedKey = ValueKey<String>('capa-effectiveness-refused');

  /// The team lead's own refusal, apart from [refusedKey] so a test — and a
  /// reader of the Screen — can tell which rule refused them. It is the rule
  /// the ticket names second, and the one that is not obvious.
  static const ValueKey<String> teamLeadKey = ValueKey<String>('capa-effectiveness-team-lead');

  /// The way out of a refusal. A `DialogPage` is not `barrierDismissible` (see
  /// `dialog_page.dart`), so a refusal with no control of its own would leave a
  /// person tapping outside a dialog that never closes.
  static final ValueKey<String> dismissKey = AppDialog.actionKey('back-to-the-capa');
}

/// One of this address's refusals: why there is no form, and the one way back
/// to the investigation the address was reached from.
class _EffectivenessRefusal extends StatelessWidget {
  const _EffectivenessRefusal({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => AppDialog(
        title: title,
        description: message,
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: 'back-to-the-capa',
            label: AppLocalizations.of(context).commonBackToTheCapa,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => context.pop(),
          ),
        ],
      );
}

/// What this address says when it is not one the CAPA it names can answer — or
/// null when it is, in which case the caller renders the form.
///
/// Ordered as the server's own gates are: is there a record to read at all, is
/// the investigation still open, may this caller record a check, and are they
/// the team lead. The order is what a person needs to fix first — an address
/// naming a closed investigation says so whether or not the caller could have
/// recorded anything on it.
Widget? capaEffectivenessAddressRefusal(BuildContext context, CapaDetailState state) {
  final l10n = AppLocalizations.of(context);
  switch (state) {
    case CapaDetailLoading():
      return const AlertDialog(
        key: CapaEffectivenessKeys.loadingKey,
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    case CapaDetailUnavailable(message: final message):
      return _EffectivenessRefusal(
        key: CapaEffectivenessKeys.notLoadedKey,
        title: l10n.commonThatCapaCouldNotBeRead,
        message: message,
      );
    case CapaDetailLoaded(capa: final capa):
      if (!capa.isOpen) {
        return _EffectivenessRefusal(
          key: CapaEffectivenessKeys.closedKey,
          title: l10n.commonThisInvestigationIsOver,
          message: l10n.capaEffectivenessIsSoItsEffectivenessIsRecordedAnd(capa.capaNo, capa.statusLabel(l10n).toLowerCase()),
        );
      }
      if (!holdsQualityAuthority(context, capa.orgUnitId)) {
        return _EffectivenessRefusal(
          key: CapaEffectivenessKeys.refusedKey,
          title: l10n.capaEffectivenessNotYoursToDecide,
          message: l10n.capaEffectivenessRecordingACapaSEffectivenessCheckNeeds,
        );
      }
      if (isCapaTeamLeadAccount(context, capa)) {
        return _EffectivenessRefusal(
          key: CapaEffectivenessKeys.teamLeadKey,
          title: l10n.capaEffectivenessSomebodyElseHasToCheckThis,
          message: l10n.capaEffectivenessYouLeadTheInvestigationOnSoYou(capa.capaNo),
        );
      }
      return null;
  }
}

/// Recording the effectiveness check — `.../capas/:id/effectiveness`.
class CapaEffectivenessDialog extends StatefulWidget {
  const CapaEffectivenessDialog({super.key});

  static const ValueKey<String> outcomeKey = ValueKey<String>('capa-effectiveness-outcome');
  static const ValueKey<String> noteKey = ValueKey<String>('capa-effectiveness-note');
  static final ValueKey<String> submitKey = AppDialog.actionKey('record-it');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-effectiveness-failure');

  /// What the form says about the two chains before the caller picks
  /// `effective`: the server refuses that verdict while either chain has no
  /// confirmed root cause, and a sentence beside the field is cheaper than a
  /// refusal after the fact.
  static const ValueKey<String> chainsOpenKey =
      ValueKey<String>('capa-effectiveness-chains-open');

  @override
  State<CapaEffectivenessDialog> createState() => _CapaEffectivenessDialogState();
}

class _CapaEffectivenessDialogState extends State<CapaEffectivenessDialog> {
  String _outcome = capaEffectivenessOutcomeOrder.first;
  late final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  /// Whether this form has already finished — a second pop would take the
  /// investigation's own page off the stack behind it.
  bool _done = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// A note has to say something: the same rule the server enforces with a 400,
  /// said here so the button is closed rather than the request refused. A check
  /// with no evidence is the "list of good intentions" this whole field exists
  /// to refuse.
  bool get _complete => _note.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<CapaDetailBloc>().add(
          CapaDetailEffectivenessRecorded(outcome: _outcome, note: _note.text.trim()),
        );
  }

  void _onChanged(BuildContext context, CapaDetailState state) {
    if (_done || !_awaiting || state is! CapaDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      // The refusal stays in the form with what was written still in it — which
      // is what makes a 409 from the server correctable rather than a dead end.
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
    final state = context.watch<CapaDetailBloc>().state;
    final refusal = capaEffectivenessAddressRefusal(context, state);
    if (refusal != null) return refusal;

    final capa = (state as CapaDetailLoaded).capa;

    return BlocListener<CapaDetailBloc, CapaDetailState>(
      listener: _onChanged,
      child: AppDialog(
        title: l10n.commonRecordTheEffectivenessCheck,
        // Two fields and a sentence: a short form (issue #398's four widths).
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'record-it',
            label: l10n.nonconformanceFormRecord,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${capa.capaNo} · ${capa.title}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              capa.effectivenessCheckDueAt == null
                  ? l10n.capaEffectivenessTheCheckFallsDueDaysAfterThe(capa.effectivenessCheckDelayDays)
                  : l10n.capaEffectivenessTheConcernClosedAndTheCheckFell((capa.effectivenessCheckDueAt ?? '')),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            // A value with a known set is chosen, never typed (ADR-0023): the
            // two verdicts are the schema's own, and the label is the
            // sentence a person would say.
            DropdownButtonFormField<String>(
              key: CapaEffectivenessDialog.outcomeKey,
              initialValue: _outcome,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.capaEffectivenessWhatTheCheckFound,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final outcome in capaEffectivenessOutcomeOrder)
                  DropdownMenuItem<String>(
                    value: outcome,
                    child: Text(capaEffectivenessOutcomeLabel(l10n, outcome)),
                  ),
              ],
              onChanged: _awaiting
                  ? null
                  : (outcome) {
                      if (outcome == null) return;
                      setState(() => _outcome = outcome);
                    },
            ),
            if (!capa.bothChainsAnswered)
              Padding(
                key: CapaEffectivenessDialog.chainsOpenKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  l10n.capaEffectivenessAChainOfThisInvestigationHasNo(capaEffectivenessOutcomeLabel(l10n, 'effective')),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: CapaEffectivenessDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.capaEffectivenessWhatYouCheckedAndWhatYouFound,
                helperText: l10n.capaEffectivenessTheEvidenceForTheVerdictSoThe,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: CapaEffectivenessDialog.failureKey,
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
