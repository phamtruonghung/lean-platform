/// Filing many Questions at once from one pasted block of text (issue #588,
/// section 12): `POST /api/people/assessment-questions/bulk`.
///
/// The paste is **all-or-nothing**, and this dialog says so wherever it speaks:
/// a malformed block (400, naming the line), a block that repeats an earlier
/// one (400, naming both lines) and a block already in the bank (409, naming
/// the line and the existing Question) each refuse the whole paste, and the
/// dialog stays open with the text as it was so the one bad block can be fixed
/// and the paste sent again. A half-imported bank is worse than none.
///
/// **Preview** reads the text on the client (`parseAssessmentPaste`) and
/// reports either "N questions, keys C, A" or the first offending line, before
/// anything is sent. It is a courtesy, not a gate: Paste is always available
/// once there is text, and the server parses again and is the authority — a
/// client parse that disagreed with it must not be able to refuse a paste the
/// server would have taken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/notice_text.dart';
import 'assessment_paste.dart';
import 'assessment_questions_bloc.dart';

class AssessmentBankPasteDialog extends StatefulWidget {
  const AssessmentBankPasteDialog({super.key});

  static const ValueKey<String> textKey = ValueKey<String>('assessment-paste-text');
  static const ValueKey<String> previewResultKey = ValueKey<String>('assessment-paste-preview-result');
  static const ValueKey<String> refusalKey = ValueKey<String>('assessment-paste-refusal');
  static const ValueKey<String> refusalLineKey = ValueKey<String>('assessment-paste-refusal-line');
  static const ValueKey<String> previewKey = ValueKey<String>('assessment-paste-preview');
  static final ValueKey<String> submitKey = AppDialog.actionKey('assessment-paste-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('assessment-paste-cancel');

  /// Opens the dialog over the bank, handing the Screen's Bloc across the
  /// Navigator boundary as every dialog in this Module does.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<AssessmentQuestionsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AssessmentQuestionsBloc>.value(
        value: bloc,
        child: const AssessmentBankPasteDialog(),
      ),
    );
  }

  @override
  State<AssessmentBankPasteDialog> createState() => _AssessmentBankPasteDialogState();
}

class _AssessmentBankPasteDialogState extends State<AssessmentBankPasteDialog> {
  final TextEditingController _text = TextEditingController();

  bool _awaiting = false;
  AssessmentPasteRefusal? _refusal;
  AssessmentPasteResult? _preview;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _runPreview() {
    setState(() => _preview = parseAssessmentPaste(_text.text));
  }

  void _submit() {
    if (_awaiting || _text.text.trim().isEmpty) return;
    setState(() {
      _awaiting = true;
      _refusal = null;
    });
    context.read<AssessmentQuestionsBloc>().add(AssessmentQuestionsPasteSubmitted(_text.text));
  }

  void _onBankChanged(BuildContext context, AssessmentQuestionsState state) {
    if (!_awaiting || state is! AssessmentQuestionsLoaded || state.saving) return;
    if (state.pasteError != null) {
      setState(() {
        _awaiting = false;
        _refusal = state.pasteError;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  String _issueText(AppLocalizations l10n, AssessmentPasteIssue issue) {
    final line = issue.line ?? 0;
    final question = issue.question ?? 0;
    return switch (issue.problem) {
      AssessmentPasteProblem.empty => l10n.assessmentPasteIssueEmpty,
      AssessmentPasteProblem.stem => l10n.assessmentPasteIssueStem(line),
      AssessmentPasteProblem.options => l10n.assessmentPasteIssueOptions(line, question),
      AssessmentPasteProblem.noKey => l10n.assessmentPasteIssueNoKey(line, question),
      AssessmentPasteProblem.twoKeys => l10n.assessmentPasteIssueTwoKeys(line, question),
      AssessmentPasteProblem.stray => l10n.assessmentPasteIssueStray(line, question),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = _preview;
    final refusal = _refusal;

    return BlocListener<AssessmentQuestionsBloc, AssessmentQuestionsState>(
      listener: _onBankChanged,
      child: AppDialog(
        title: l10n.assessmentPasteTitle,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: 'assessment-paste-cancel',
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: 'assessment-paste-submit',
            label: _awaiting ? l10n.commonSaving : l10n.assessmentPasteSubmit,
            onPressed: _awaiting || _text.text.trim().isEmpty ? null : _submit,
          ),
        ],
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.assessmentPasteGuide,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: AssessmentBankPasteDialog.textKey,
                controller: _text,
                enabled: !_awaiting,
                maxLines: 8,
                onChanged: (_) => setState(() => _preview = null),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l10n.assessmentPasteHint,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: AssessmentBankPasteDialog.previewKey,
                  onPressed: _awaiting || _text.text.trim().isEmpty ? null : _runPreview,
                  child: Text(l10n.assessmentPastePreview),
                ),
              ),
              if (preview != null)
                Padding(
                  key: AssessmentBankPasteDialog.previewResultKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: preview.issue != null
                      ? Text(
                          _issueText(l10n, preview.issue!),
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        )
                      : Text(
                          l10n.assessmentPastePreviewSummary(
                            preview.blocks.length,
                            preview.blocks.map((block) => block.key).join(', '),
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                ),
              if (refusal != null)
                Padding(
                  key: AssessmentBankPasteDialog.refusalKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (refusal.line != null)
                        Text(
                          l10n.assessmentPasteLine(refusal.line!),
                          key: AssessmentBankPasteDialog.refusalLineKey,
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.error),
                        ),
                      NoticeText(
                        refusal.message,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(l10n.assessmentPasteNothingWritten, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
