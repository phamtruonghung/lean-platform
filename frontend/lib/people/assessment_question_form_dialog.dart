/// Adding a Question to a process's bank, and correcting one (issue #588) —
/// `POST` and `PATCH /api/people/assessment-questions`.
///
/// One dialog for both, the choice `CostRateFormDialog` makes for its three:
/// a Question has one shape of fields, and the two acts differ only in what
/// the form opens on and which event it sends. **Correct is a full
/// restatement**, the contract the server's PATCH keeps: every field is sent,
/// and a blank explanation sends null, which clears it.
///
/// The key is a three-way choice, A, B or C, **chosen and never typed**
/// (ADR-0023): a value with a known set. When the server withheld the key
/// (the caller has the maintain code but no write reach on this process) the
/// correct form opens with no letter chosen, and the person must pick one to
/// save; the server is still the one that decides whether the write may land.
///
/// The form refuses what the table's CHECKs would — a stem under five
/// characters, a blank Option, two Options that read the same — before sending,
/// and says which; the server's own refusal (a fingerprint clash naming the
/// existing Question, a scope refusal) is reported in the dialog, which stays
/// open so nothing typed is lost.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/notice_text.dart';
import 'assessment_question.dart';
import 'assessment_questions_bloc.dart';

class AssessmentQuestionFormDialog extends StatefulWidget {
  const AssessmentQuestionFormDialog({super.key, this.question});

  /// The Question being corrected; null to add a new one.
  final AssessmentQuestion? question;

  static const ValueKey<String> stemKey = ValueKey<String>('assessment-form-stem');
  static ValueKey<String> optionKey(String letter) =>
      ValueKey<String>('assessment-form-option-$letter');
  static ValueKey<String> keyChoiceKey(String letter) =>
      ValueKey<String>('assessment-form-key-$letter');
  static const ValueKey<String> explanationKey = ValueKey<String>('assessment-form-explanation');
  static const ValueKey<String> failureKey = ValueKey<String>('assessment-form-failure');
  static final ValueKey<String> submitKey = AppDialog.actionKey('assessment-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('assessment-form-cancel');

  /// Opens the form over the bank. The dialog's route is built under the
  /// Navigator, not under the Screen's `BlocProvider`, so the Bloc is handed
  /// across explicitly, the device every dialog in this Module uses.
  static Future<void> open(BuildContext context, {AssessmentQuestion? question}) {
    final bloc = context.read<AssessmentQuestionsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AssessmentQuestionsBloc>.value(
        value: bloc,
        child: AssessmentQuestionFormDialog(question: question),
      ),
    );
  }

  @override
  State<AssessmentQuestionFormDialog> createState() => _AssessmentQuestionFormDialogState();
}

class _AssessmentQuestionFormDialogState extends State<AssessmentQuestionFormDialog> {
  late final TextEditingController _stem =
      TextEditingController(text: widget.question?.questionText ?? '');
  late final Map<String, TextEditingController> _options = {
    for (final letter in assessmentOptionLetters)
      letter: TextEditingController(text: widget.question?.optionFor(letter) ?? ''),
  };
  late final TextEditingController _explanation =
      TextEditingController(text: widget.question?.explanation ?? '');
  late String? _correct = widget.question?.correctOption;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.question != null;

  @override
  void dispose() {
    _stem.dispose();
    for (final controller in _options.values) {
      controller.dispose();
    }
    _explanation.dispose();
    super.dispose();
  }

  String get _stemText => _stem.text.trim();
  List<String> get _optionTexts =>
      [for (final letter in assessmentOptionLetters) _options[letter]!.text.trim()];

  bool get _stemTooShort => _stemText.isNotEmpty && _stemText.length < assessmentQuestionTextMin;
  bool get _optionsRepeat => _optionTexts.where((text) => text.isNotEmpty).toSet().length !=
      _optionTexts.where((text) => text.isNotEmpty).length;

  bool get _complete =>
      _stemText.length >= assessmentQuestionTextMin &&
      _optionTexts.every((text) => text.isNotEmpty) &&
      !_optionsRepeat &&
      _correct != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    final explanation = _explanation.text.trim();
    final body = <String, Object?>{
      'questionText': _stemText,
      'optionA': _optionTexts[0],
      'optionB': _optionTexts[1],
      'optionC': _optionTexts[2],
      'correctOption': _correct,
      'explanation': explanation.isEmpty ? null : explanation,
    };
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final bloc = context.read<AssessmentQuestionsBloc>();
    if (_isCorrection) {
      bloc.add(AssessmentQuestionCorrected(id: widget.question!.id, body: body));
    } else {
      bloc.add(AssessmentQuestionCreated(body: body));
    }
  }

  void _onBankChanged(BuildContext context, AssessmentQuestionsState state) {
    if (!_awaiting || state is! AssessmentQuestionsLoaded || state.saving) return;
    if (state.formFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.formFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return BlocListener<AssessmentQuestionsBloc, AssessmentQuestionsState>(
      listener: _onBankChanged,
      child: AppDialog(
        title: _isCorrection ? l10n.assessmentFormCorrectTitle : l10n.assessmentFormAddTitle,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'assessment-form-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'assessment-form-submit',
            label: _awaiting
                ? l10n.commonSaving
                : (_isCorrection ? l10n.commonSave : l10n.assessmentAddQuestion),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: AssessmentQuestionFormDialog.stemKey,
                controller: _stem,
                enabled: !_awaiting,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.assessmentFormQuestionText,
                  border: const OutlineInputBorder(),
                  errorText: _stemTooShort
                      ? l10n.assessmentFormTextTooShort(assessmentQuestionTextMin)
                      : null,
                ),
              ),
              for (final letter in assessmentOptionLetters) ...[
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AssessmentQuestionFormDialog.optionKey(letter),
                  controller: _options[letter],
                  enabled: !_awaiting,
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.assessmentFormOption(letter),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              if (_optionsRepeat)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    l10n.assessmentFormOptionsMustDiffer,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.md),
              Text(l10n.assessmentFormCorrectOption, style: theme.textTheme.labelLarge),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.sm,
                children: [
                  for (final letter in assessmentOptionLetters)
                    ChoiceChip(
                      key: AssessmentQuestionFormDialog.keyChoiceKey(letter),
                      label: Text(letter),
                      selected: _correct == letter,
                      onSelected: _awaiting ? null : (_) => setState(() => _correct = letter),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: AssessmentQuestionFormDialog.explanationKey,
                controller: _explanation,
                enabled: !_awaiting,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.assessmentFormExplanation,
                  helperText: l10n.assessmentFormExplanationHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_failure != null)
                Padding(
                  key: AssessmentQuestionFormDialog.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: NoticeText(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
