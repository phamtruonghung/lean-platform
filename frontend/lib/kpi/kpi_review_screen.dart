/// The daily KPI Review (ADR-0055) at `/kpi/review`: for one day, one row per
/// KPI of the MTU line with the Daily Target that day had, and a three-way
/// judgement — Met, Missed or Not measured.
///
/// - A row with **no Target** shows "No target — set one first", cannot be
///   judged Met, and can still be reviewed Missed or Not measured.
/// - Choosing **Missed** reveals a required note of at least 10 characters
///   after trimming (the database's own CHECK), validated inline; the note area
///   names the Target that was missed.
/// - A row with a saved Review shows it in place — `Met · A B · 2026-10-30
///   08:12` — as the server holds it (`app_user`, `entered_at`).
/// - **Save** posts every changed row in one request; it is disabled when
///   nothing changed or any changed Missed row's note is too short.
///
/// "Today" is the server's. `review_date` is the heading's day, and the date
/// picker opens a past day: its first day is fixed, its last is the Site's
/// today (the day on screen cannot be the last day, or choosing a past day
/// would shut the way forward).
///
/// The value a reviewer read off the chart (`observed`) has no field here: the
/// brief for this Screen does not ask for one, and the entries go out with
/// `observed: null`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'kpi_catalogue.dart';
import 'kpi_review_bloc.dart';

class KpiReviewScreen extends StatelessWidget {
  const KpiReviewScreen({super.key, this.canWrite = true});

  /// Whether the caller holds a write Grant anywhere. Without one the rows are
  /// read-only; the server is still the gate on a save.
  final bool canWrite;

  static const double maxWidth = AppLayout.pageWidth;

  /// The earliest day the picker offers.
  static final DateTime firstReviewDate = DateTime(2020, 1, 1);

  /// A note owed on a Missed row: at least this many characters once trimmed.
  static const int minNoteLength = 10;

  static const ValueKey<String> siteKey = ValueKey<String>('kpi-review-site');
  static const String dateName = 'kpi-review-date';
  static ValueKey<String> get dateKey => AppDateField.fieldKey(dateName);
  static const ValueKey<String> saveKey = ValueKey<String>('kpi-review-save');
  static const ValueKey<String> savedKey = ValueKey<String>('kpi-review-saved');
  static const ValueKey<String> failureKey = ValueKey<String>('kpi-review-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('kpi-review-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('kpi-review-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('kpi-review-empty');
  static const ValueKey<String> headingKey = ValueKey<String>('kpi-review-heading');
  static ValueKey<String> rowKey(int kpiId) => ValueKey<String>('kpi-review-row-$kpiId');
  static ValueKey<String> statusKey(int kpiId, String status) =>
      ValueKey<String>('kpi-review-$kpiId-$status');
  static ValueKey<String> noteKey(int kpiId) => ValueKey<String>('kpi-review-note-$kpiId');
  static ValueKey<String> noTargetHintKey(int kpiId) => ValueKey<String>('kpi-review-no-target-$kpiId');

  /// The row's saved state in place, e.g. `Met · A B · 2026-10-30 08:12`.
  static ValueKey<String> savedStateKey(int kpiId) => ValueKey<String>('kpi-review-saved-state-$kpiId');

  static const String noTargetHint = 'No target — set one first';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<KpiReviewBloc>().state;
    return Scaffold(
      body: switch (state) {
        KpiReviewLoading() => const SkeletonList(maxWidth: KpiReviewScreen.maxWidth),
        KpiReviewUnavailable(message: final message) => PlatformFailureState(
            key: KpiReviewScreen.failedKey,
            title: 'The KPI Review could not be read',
            message: message,
            retryKey: KpiReviewScreen.retryKey,
            onRetry: () => context.read<KpiReviewBloc>().add(const KpiReviewStarted()),
          ),
        KpiReviewLoaded() => _Loaded(state: state, canWrite: canWrite),
      },
    );
  }
}

/// What a person has chosen on one row so far.
class _Draft {
  const _Draft({required this.status, required this.note});

  final String? status;
  final String note;
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.canWrite});

  final KpiReviewLoaded state;
  final bool canWrite;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// Per KPI, what the rows report. A row that has not been touched has no
  /// entry. Cleared whenever a fresh read arrives (a day, a Site or a save),
  /// because the row tiles are rebuilt on it.
  final Map<int, _Draft> _drafts = {};

  @override
  void didUpdateWidget(covariant _Loaded oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state.review, widget.state.review)) _drafts.clear();
  }

  ReviewRow? _rowOf(int kpiId) {
    for (final row in widget.state.review?.rows ?? const <ReviewRow>[]) {
      if (row.kpiId == kpiId) return row;
    }
    return null;
  }

  /// The rows whose judgement differs from what the server holds.
  List<ReviewEntryInput> get _changes {
    final entries = <ReviewEntryInput>[];
    for (final MapEntry(key: kpiId, value: draft) in _drafts.entries) {
      final row = _rowOf(kpiId);
      final status = draft.status;
      if (row == null || status == null) continue;
      final note = draft.note.trim();
      final sameStatus = status == row.status;
      final sameNote = status != ReviewStatus.missed || note == (row.note ?? '').trim();
      if (sameStatus && sameNote) continue;
      entries.add(
        ReviewEntryInput(
          kpiId: kpiId,
          status: status,
          note: status == ReviewStatus.missed ? note : null,
        ),
      );
    }
    return entries;
  }

  bool _noteTooShort(ReviewEntryInput entry) =>
      entry.status == ReviewStatus.missed && (entry.note ?? '').length < KpiReviewScreen.minNoteLength;

  void _draft(int kpiId, String? status, String note) => setState(() => _drafts[kpiId] = _Draft(status: status, note: note));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final review = state.review;
    final changes = _changes;
    final canSave = widget.canWrite &&
        !state.isMutating &&
        changes.isNotEmpty &&
        !changes.any(_noteTooShort);
    final reviewDate = review?.reviewDate;
    final lastDate = DateTime.tryParse(state.siteToday ?? reviewDate ?? '');
    return Center(
      child: AppPageFrame(
        maxWidth: KpiReviewScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Text(
              reviewDate == null ? 'KPI Review' : 'KPI Review for $reviewDate',
              key: KpiReviewScreen.headingKey,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Judge each KPI of the MTU line against its Daily Target: met, missed or not measured.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (state.sites.length > 1)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: KpiReviewScreen.siteKey,
                      initialValue: state.siteId,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                      items: [
                        for (final site in state.sites)
                          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                      ],
                      onChanged: (siteId) {
                        if (siteId == null) return;
                        context.read<KpiReviewBloc>().add(KpiReviewSiteSelected(siteId));
                      },
                    ),
                  ),
                if (reviewDate != null && lastDate != null)
                  SizedBox(
                    width: 220,
                    child: AppDateField(
                      name: KpiReviewScreen.dateName,
                      label: 'Day',
                      value: reviewDate,
                      firstDate: KpiReviewScreen.firstReviewDate,
                      lastDate: lastDate,
                      onChanged: (date) {
                        if (date != null) context.read<KpiReviewBloc>().add(ReviewDateSelected(date));
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.isLoadingReview || review == null)
              const SkeletonList(rows: 3, maxWidth: KpiReviewScreen.maxWidth)
            else if (review.rows.isEmpty)
              const PlatformEmptyState.noneExist(
                key: KpiReviewScreen.emptyKey,
                title: 'No KPIs to review',
                message: 'The KPI catalogue has no KPI yet.',
                icon: Icons.fact_check_outlined,
              )
            else ...[
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < review.rows.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ReviewRowTile(
                        key: ObjectKey(review.rows[i]),
                        row: review.rows[i],
                        enabled: widget.canWrite && !state.isMutating,
                        onChanged: _draft,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Row(
                children: [
                  FilledButton(
                    key: KpiReviewScreen.saveKey,
                    onPressed: canSave
                        ? () => context.read<KpiReviewBloc>().add(ReviewSaveRequested(changes))
                        : null,
                    child: Text(state.isMutating ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(width: Spacing.md),
                  if (state.savedCount != null)
                    Flexible(
                      child: Text(
                        'Saved ${state.savedCount} ${state.savedCount == 1 ? 'KPI Review' : 'KPI Reviews'} '
                        'for ${review.reviewDate}.',
                        key: KpiReviewScreen.savedKey,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
              if (state.mutationFailure != null)
                Padding(
                  key: KpiReviewScreen.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    state.mutationFailure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewRowTile extends StatefulWidget {
  const _ReviewRowTile({super.key, required this.row, required this.enabled, required this.onChanged});

  final ReviewRow row;
  final bool enabled;
  final void Function(int kpiId, String? status, String note) onChanged;

  @override
  State<_ReviewRowTile> createState() => _ReviewRowTileState();
}

class _ReviewRowTileState extends State<_ReviewRowTile> {
  /// Starts on the saved judgement, if any; a row with no review starts with
  /// nothing selected.
  late String? _status = widget.row.status;
  late final TextEditingController _note = TextEditingController(text: widget.row.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _choose(String status) {
    setState(() => _status = status);
    widget.onChanged(widget.row.kpiId, _status, _note.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final target = row.target;
    final targetText = target == null ? null : formatReviewTarget(row, target);
    final saved = row.status == null
        ? null
        : [
            ReviewStatus.label(row.status!),
            if (row.appUser != null) row.appUser!,
            if (row.enteredAt != null) formatEnteredAt(row.enteredAt!),
          ].join(' · ');
    final noteLength = _note.text.trim().length;
    return Padding(
      key: KpiReviewScreen.rowKey(row.kpiId),
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, style: theme.textTheme.bodyLarge),
                    Text(
                      targetText ?? 'No target',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (target == null)
                      Text(
                        KpiReviewScreen.noTargetHint,
                        key: KpiReviewScreen.noTargetHintKey(row.kpiId),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    if (saved != null)
                      Text(
                        saved,
                        key: KpiReviewScreen.savedStateKey(row.kpiId),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  for (final status in ReviewStatus.all)
                    ChoiceChip(
                      key: KpiReviewScreen.statusKey(row.kpiId, status),
                      label: Text(ReviewStatus.label(status)),
                      selected: _status == status,
                      // A KPI with no Target cannot have met one.
                      onSelected: !widget.enabled || (status == ReviewStatus.met && target == null)
                          ? null
                          : (_) => _choose(status),
                    ),
                ],
              ),
            ],
          ),
          if (_status == ReviewStatus.missed) ...[
            const SizedBox(height: Spacing.md),
            TextField(
              key: KpiReviewScreen.noteKey(row.kpiId),
              controller: _note,
              enabled: widget.enabled,
              minLines: 2,
              maxLines: 4,
              onChanged: (value) {
                setState(() {});
                widget.onChanged(row.kpiId, _status, value);
              },
              decoration: InputDecoration(
                labelText: targetText == null ? 'Why was it missed?' : 'Why was the Target ($targetText) missed?',
                errorText: noteLength < KpiReviewScreen.minNoteLength
                    ? 'A note of at least ${KpiReviewScreen.minNoteLength} characters is required '
                        'when a KPI is missed ($noteLength so far).'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
