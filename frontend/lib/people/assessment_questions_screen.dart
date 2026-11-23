/// The assessment Question bank (issue #588, ADR-0068): one process's Questions,
/// searched and paged, and — for a person who may change the bank — the Add,
/// Correct, Retire and Paste acts over it.
///
/// **A process is picked, not typed.** The bank is filed on one Org Unit, so the
/// Screen opens on a Site dropdown and an `AppSearchField` over that Site's Org
/// Units (`GET .../sites/:siteId/org-units/search`, ADR-0023) and shows nothing
/// until one is picked. The active count sits beside it: it is the number a
/// paper's size will be checked against, and it counts the process alone, never
/// the Org Units beneath it.
///
/// **A card per Question, not a register.** A Question is read as a whole - a
/// sentence, three Options, which one is the key, why - not compared down a
/// column, so each is one `Card` at every width rather than the table-above-
/// a-breakpoint shape `CostRatesScreen` uses for numbers. Long text is clipped
/// and disclosed in full by the tooltip (`DisclosingText`), as every list here
/// does.
///
/// **The key and the explanation are the server's to reveal.** They arrive null
/// unless the caller holds the maintain code and has write reach on this
/// process, and a null renders as a dash, never as the word "null". The Add and
/// Paste buttons follow the permission alone (see `AssessmentQuestionsBloc`);
/// reach is the server's judgement and is reported when it refuses.
///
/// **Retired Questions are asked for.** The default list is the active bank; the
/// **Include retired** switch re-reads with `includeInactive=true`, which needs
/// the read code alone. There is no way back to active in this slice, so a
/// retired Question carries no Retire or Correct action.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_search_field.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/notice_text.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assessment_bank_paste_dialog.dart';
import 'assessment_question.dart';
import 'assessment_question_form_dialog.dart';
import 'assessment_questions_bloc.dart';
import 'org_unit.dart';

class AssessmentQuestionsScreen extends StatefulWidget {
  const AssessmentQuestionsScreen({super.key});

  static const double maxWidth = 900;

  static const String _processFieldName = 'assessment-process';
  static const String _filterFieldName = 'assessment-questions';

  static const ValueKey<String> addKey = ValueKey<String>('assessment-questions-add');
  static const ValueKey<String> pasteKey = ValueKey<String>('assessment-questions-paste');
  static const ValueKey<String> includeRetiredKey =
      ValueKey<String>('assessment-questions-include-retired');
  static const ValueKey<String> siteKey = ValueKey<String>('assessment-questions-site');
  static const ValueKey<String> activeCountKey =
      ValueKey<String>('assessment-questions-active-count');
  static const ValueKey<String> chooseProcessKey =
      ValueKey<String>('assessment-questions-choose-process');
  static const ValueKey<String> emptyKey = ValueKey<String>('assessment-questions-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-questions-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-questions-retry');
  static const ValueKey<String> pageFailureKey =
      ValueKey<String>('assessment-questions-page-failure');
  static const ValueKey<String> pageRangeKey = ValueKey<String>('assessment-questions-page-range');
  static const ValueKey<String> previousKey = ValueKey<String>('assessment-questions-previous');
  static const ValueKey<String> nextKey = ValueKey<String>('assessment-questions-next');

  static ValueKey<String> get processSearchKey =>
      AppSearchField.fieldKey(_processFieldName);
  static ValueKey<String> processSuggestionKey(String orgUnitId) =>
      AppSearchField.suggestionKey(_processFieldName, orgUnitId);
  static ValueKey<String> get filterKey => AppFilterField.fieldKey(_filterFieldName);

  static ValueKey<String> rowKey(int id) => ValueKey<String>('assessment-question-row-$id');
  static ValueKey<String> editKey(int id) => ValueKey<String>('assessment-question-edit-$id');
  static ValueKey<String> retireKey(int id) => ValueKey<String>('assessment-question-retire-$id');
  static ValueKey<String> keyTextKey(int id) => ValueKey<String>('assessment-question-key-$id');
  static ValueKey<String> explanationTextKey(int id) =>
      ValueKey<String>('assessment-question-explanation-$id');
  static ValueKey<String> statusKey(int id) => ValueKey<String>('assessment-question-status-$id');

  @override
  State<AssessmentQuestionsScreen> createState() => _AssessmentQuestionsScreenState();
}

class _AssessmentQuestionsScreenState extends State<AssessmentQuestionsScreen> {
  /// The text in the search box, kept apart from the Bloc's `q` so typing is
  /// never overwritten by an answer to an earlier keystroke.
  String _term = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onTermChanged(String term) {
    setState(() => _term = term);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      context.read<AssessmentQuestionsBloc>().add(AssessmentQuestionsSearchChanged(term.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentQuestionsBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentQuestionsLoading() =>
          const SkeletonList(maxWidth: AssessmentQuestionsScreen.maxWidth),
        AssessmentQuestionsUnavailable(message: final message) => PlatformFailureState(
            key: AssessmentQuestionsScreen.failedKey,
            title: l10n.assessmentQuestionsFailedTitle,
            message: message,
            retryKey: AssessmentQuestionsScreen.retryKey,
            onRetry: () =>
                context.read<AssessmentQuestionsBloc>().add(const AssessmentQuestionsStarted()),
          ),
        AssessmentQuestionsLoaded() => _Loaded(
            state: state,
            term: _term,
            onTermChanged: _onTermChanged,
          ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.term, required this.onTermChanged});

  final AssessmentQuestionsLoaded state;
  final String term;
  final ValueChanged<String> onTermChanged;

  /// `AppSearchField`'s own dumb fetch, straight to `PeopleApi` as
  /// `OrgUnitsScreen` does: the endpoint scopes itself, nothing here filters.
  Future<List<OrgUnitNode>> _fetchProcesses(BuildContext context, String siteId, String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) throw PeopleApiException(AssessmentQuestionsBloc.signedOutMessage);
    final result = await context.read<PeopleApi>().searchOrgUnits(token, siteId: siteId, search: term);
    return result.orgUnits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final orgUnit = state.orgUnit;
    final siteId = state.siteId;

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentQuestionsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.assessmentQuestionsTitle,
              description: l10n.assessmentQuestionsDescription,
              actions: [
                if (state.mayChange && orgUnit != null) ...[
                  OutlinedButton.icon(
                    key: AssessmentQuestionsScreen.pasteKey,
                    onPressed: state.saving ? null : () => AssessmentBankPasteDialog.open(context),
                    icon: const Icon(Icons.content_paste_outlined),
                    label: Text(l10n.assessmentPasteQuestions),
                  ),
                  FilledButton.icon(
                    key: AssessmentQuestionsScreen.addKey,
                    onPressed: state.saving ? null : () => AssessmentQuestionFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.assessmentAddQuestion),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.sites.length > 1) ...[
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: AssessmentQuestionsScreen.siteKey,
                  initialValue: siteId,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: l10n.commonSite,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final site in state.sites)
                      DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<AssessmentQuestionsBloc>().add(AssessmentQuestionsSiteChosen(value));
                  },
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (siteId != null)
              // Keyed by Site so a new Site starts a fresh search box rather
              // than carrying the old process's name into it.
              KeyedSubtree(
                key: ValueKey<String>('assessment-process-$siteId'),
                child: AppSearchField<OrgUnitNode>(
                  name: AssessmentQuestionsScreen._processFieldName,
                  label: l10n.assessmentProcessSearchLabel,
                  helperText: l10n.assessmentProcessSearchHelper,
                  value: orgUnit,
                  onChanged: (_) {},
                  onSelected: (picked) => context
                      .read<AssessmentQuestionsBloc>()
                      .add(AssessmentQuestionsProcessChosen(picked)),
                  fetchSuggestions: (term) => _fetchProcesses(context, siteId, term),
                  suggestionBuilder: (context, node) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm,
                    ),
                    child: Text('${node.name} · ${node.code}'),
                  ),
                  idOf: (node) => node.id,
                  displayStringFor: (node) => node.name,
                  codeOf: (node) => node.code,
                ),
              ),
            if (orgUnit != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentProcessActiveCount(state.activeCount),
                key: AssessmentQuestionsScreen.activeCountKey,
                style: theme.textTheme.labelLarge?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Spacing.md),
              AppFilterField(
                name: AssessmentQuestionsScreen._filterFieldName,
                label: l10n.assessmentSearchQuestions,
                term: term,
                onChanged: onTermChanged,
              ),
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  key: AssessmentQuestionsScreen.includeRetiredKey,
                  label: Text(l10n.assessmentIncludeRetired),
                  selected: state.includeInactive,
                  onSelected: (value) => context
                      .read<AssessmentQuestionsBloc>()
                      .add(AssessmentQuestionsIncludeInactiveToggled(value)),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            _Body(state: state),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final AssessmentQuestionsLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (state.orgUnit == null) {
      return PlatformEmptyState.noneExist(
        key: AssessmentQuestionsScreen.chooseProcessKey,
        title: l10n.assessmentChooseProcessTitle,
        message: l10n.assessmentChooseProcessMessage,
        icon: Icons.quiz_outlined,
      );
    }

    if (state.isLoadingPage && state.questions.isEmpty) {
      return const SizedBox(
        height: 240,
        child: SkeletonList(
          rows: 3,
          maxWidth: AssessmentQuestionsScreen.maxWidth,
          padding: EdgeInsets.zero,
        ),
      );
    }

    final failure = state.pageFailure;
    final children = <Widget>[
      if (failure != null)
        Padding(
          key: AssessmentQuestionsScreen.pageFailureKey,
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: NoticeText(
            failure,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ),
    ];

    if (state.questions.isEmpty) {
      final filtered = state.q.isNotEmpty || state.includeInactive;
      children.add(
        filtered
            ? PlatformEmptyState.noneMatched(
                key: AssessmentQuestionsScreen.emptyKey,
                title: l10n.assessmentNoMatchTitle,
                message: l10n.assessmentNoMatchMessage,
              )
            : PlatformEmptyState.noneExist(
                key: AssessmentQuestionsScreen.emptyKey,
                title: l10n.assessmentNoQuestionsTitle,
                message: l10n.assessmentNoQuestionsMessage,
                icon: Icons.quiz_outlined,
              ),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    for (final question in state.questions) {
      children
        ..add(_QuestionCard(question: question, state: state))
        ..add(const SizedBox(height: Spacing.sm));
    }
    children.add(_Pager(state: state));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.state});

  final AssessmentQuestionsLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final from = state.offset + 1;
    final to = state.offset + state.questions.length;
    final hasPrevious = state.offset > 0;
    final hasNext = to < state.total;
    final bloc = context.read<AssessmentQuestionsBloc>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l10n.assessmentPageRange(from, to, state.total),
          key: AssessmentQuestionsScreen.pageRangeKey,
        ),
        Wrap(
          spacing: Spacing.sm,
          children: [
            OutlinedButton(
              key: AssessmentQuestionsScreen.previousKey,
              onPressed: hasPrevious && !state.isLoadingPage
                  ? () => bloc.add(AssessmentQuestionsPageChanged(state.offset - state.limit))
                  : null,
              child: Text(l10n.assessmentPreviousPage),
            ),
            OutlinedButton(
              key: AssessmentQuestionsScreen.nextKey,
              onPressed: hasNext && !state.isLoadingPage
                  ? () => bloc.add(AssessmentQuestionsPageChanged(state.offset + state.limit))
                  : null,
              child: Text(l10n.assessmentNextPage),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.state});

  final AssessmentQuestion question;
  final AssessmentQuestionsLoaded state;

  Future<void> _retire(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final bloc = context.read<AssessmentQuestionsBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppConfirmDialog(
        title: l10n.assessmentRetireTitle,
        description: l10n.assessmentRetireMessage,
        confirmLabel: l10n.orgUnitsRetire,
        dismissLabel: l10n.commonCancel,
        onDismiss: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed ?? false) bloc.add(AssessmentQuestionRetired(question.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dense = AppTypography.dense(context);
    final floor = AppTypography.floor(context);
    final palette = AppColors.of(context);
    final id = int.parse(question.id);
    final key = question.correctOption;
    final acting = state.mayChange && question.isActive;

    return Card(
      key: AssessmentQuestionsScreen.rowKey(id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DisclosingText(
                    question.questionText,
                    style: dense?.copyWith(color: palette.textPrimary),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                StatusChip(
                  key: AssessmentQuestionsScreen.statusKey(id),
                  label: question.isActive ? l10n.commonActive : l10n.commonInactive,
                  tone: question.isActive ? StatusTone.info : StatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            for (final letter in assessmentOptionLetters)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xxs),
                child: DisclosingText(
                  '$letter. ${question.optionFor(letter)}',
                  style: floor?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: key == letter ? FontWeight.w700 : null,
                  ),
                ),
              ),
            const SizedBox(height: Spacing.xs),
            Text(
              l10n.assessmentKeyIs(key ?? '—'),
              key: AssessmentQuestionsScreen.keyTextKey(id),
              style: floor?.copyWith(color: palette.textMuted),
            ),
            DisclosingText(
              l10n.assessmentExplanationIs(question.explanation ?? '—'),
              key: AssessmentQuestionsScreen.explanationTextKey(id),
              style: floor?.copyWith(color: palette.textMuted),
            ),
            if (acting) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: AssessmentQuestionsScreen.editKey(id),
                    onPressed: state.saving
                        ? null
                        : () => AssessmentQuestionFormDialog.open(context, question: question),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.commonCorrect),
                  ),
                  OutlinedButton(
                    key: AssessmentQuestionsScreen.retireKey(id),
                    onPressed: state.saving ? null : () => _retire(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.orgUnitsRetire),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
