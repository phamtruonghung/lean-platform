/// The daily KPI Review (ADR-0055) at `/kpi/review`: for one day, a tiled matrix
/// of one cell per KPI of the MTU line, each with the Daily Target that day had
/// and a three-way judgement — Met, Missed or Not measured — chosen by icon.
///
/// - A cell with **no Target** shows "No target — set one first", cannot be
///   judged Met, and can still be reviewed Missed or Not measured.
/// - Choosing **Missed** opens a popup asking for a note of at least 10
///   characters after trimming (the database's own CHECK), naming the Target
///   that was missed. Nothing is drafted until the popup is confirmed, so
///   cancelling it leaves the judgement and the note as they were, and a
///   cancelled popup can never leave an invalid Missed draft behind.
/// - A cell with a note shows a note icon that opens it read-only, with an Edit
///   button when the judgement is Missed and the caller may write.
/// - A cell with a saved Review shows it in place — `Met · A B · 2026-10-30
///   08:12` — as the server holds it (`app_user`, `entered_at`).
/// - **Save** posts every changed KPI in one request; it is disabled when
///   nothing changed or any changed Missed KPI's note is too short.
///
/// "Today" is the server's. `review_date` is the heading's day (with no date
/// chosen, the Site's last working day), and the date picker opens another
/// day: its first day is fixed, its last is the Site's today, `site_today`
/// (the day on screen cannot be the last day, or choosing a past day would
/// shut the way forward).
///
/// The value a reviewer read off the chart (`observed`) has no field here: the
/// brief for this Screen does not ask for one, and the entries go out with
/// `observed: null`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'kpi_catalogue.dart';
import 'kpi_matrix.dart' show kpiMatchesSearch;
import 'kpi_review_bloc.dart';

class KpiReviewScreen extends StatelessWidget {
  const KpiReviewScreen({super.key, this.canWrite = true});

  /// Whether the caller holds a write Grant anywhere. Without one the cells are
  /// read-only; the server is still the gate on a save.
  final bool canWrite;

  static const double maxWidth = AppLayout.pageWidth;

  /// The earliest day the picker offers.
  static final DateTime firstReviewDate = DateTime(2020, 1, 1);

  /// A note owed on a Missed KPI: at least this many characters once trimmed.
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

  static const ValueKey<String> noMatchKey = ValueKey<String>('kpi-review-no-match');

  /// The sentence naming changed KPIs the filter hides, beside Save.
  static const ValueKey<String> hiddenChangesKey = ValueKey<String>('kpi-review-hidden-changes');
  static const String filterFieldName = 'kpi-review-filter';
  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  static ValueKey<String> statusKey(int kpiId, String status) =>
      ValueKey<String>('kpi-review-$kpiId-$status');

  /// The popup that asks for the note, and its field, confirm and cancel.
  static ValueKey<String> noteDialogKey(int kpiId) => ValueKey<String>('kpi-review-note-dialog-$kpiId');
  static ValueKey<String> noteKey(int kpiId) => ValueKey<String>('kpi-review-note-$kpiId');
  static ValueKey<String> noteSaveKey(int kpiId) => ValueKey<String>('kpi-review-note-save-$kpiId');
  static ValueKey<String> noteCancelKey(int kpiId) => ValueKey<String>('kpi-review-note-cancel-$kpiId');

  /// The cell's note icon, and the read-only popup it opens.
  static ValueKey<String> notePopupKey(int kpiId) => ValueKey<String>('kpi-review-note-popup-$kpiId');
  static ValueKey<String> noteReadDialogKey(int kpiId) => ValueKey<String>('kpi-review-note-read-$kpiId');
  static ValueKey<String> noteEditKey(int kpiId) => ValueKey<String>('kpi-review-note-edit-$kpiId');
  static ValueKey<String> noteCloseKey(int kpiId) => ValueKey<String>('kpi-review-note-close-$kpiId');
  static ValueKey<String> noTargetHintKey(int kpiId) => ValueKey<String>('kpi-review-no-target-$kpiId');

  /// The cell's saved state in place, e.g. `Met · A B · 2026-10-30 08:12`.
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

/// What a person has chosen for one KPI so far.
class _Draft {
  const _Draft({required this.status, required this.note});

  final String status;
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
  /// Per KPI, what the cells report. A KPI that has not been touched has no
  /// entry. Cleared whenever a fresh read arrives (a day, a Site or a save).
  final Map<int, _Draft> _drafts = {};

  /// What the filter box is narrowing the cells to, `''` when nothing is. It
  /// survives a day change and is cleared only when the Site changes. It never
  /// touches [_drafts]: a hidden cell's unsaved judgement is still saved.
  String _term = '';

  @override
  void didUpdateWidget(covariant _Loaded oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state.review, widget.state.review)) _drafts.clear();
    if (oldWidget.state.siteId != widget.state.siteId) _term = '';
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
      if (row == null) continue;
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

  void _draft(int kpiId, String status, String note) => setState(() => _drafts[kpiId] = _Draft(status: status, note: note));

  bool get _enabled => widget.canWrite && !widget.state.isMutating;

  String _noteOf(ReviewRow row) => _drafts[row.kpiId]?.note ?? row.note ?? '';

  void _choose(ReviewRow row, String status) {
    if (status == ReviewStatus.missed) {
      _writeNote(row);
    } else {
      _draft(row.kpiId, status, _noteOf(row));
    }
  }

  /// Asks for the note and only then drafts Missed. Every way out but confirm
  /// (Cancel, Escape, a browser back) answers null and leaves [_drafts] alone,
  /// so there is nothing to restore.
  Future<void> _writeNote(ReviewRow row) async {
    final review = widget.state.review;
    final note = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NoteDialog(row: row, note: _noteOf(row)),
    );
    if (note == null || !mounted || !identical(review, widget.state.review)) return;
    _draft(row.kpiId, ReviewStatus.missed, note);
  }

  Future<void> _readNote(ReviewRow row) async {
    final status = _drafts[row.kpiId]?.status ?? row.status;
    final edit = await showDialog<bool>(
      context: context,
      builder: (_) => _ReadNoteDialog(
        row: row,
        note: _noteOf(row).trim(),
        canEdit: _enabled && status == ReviewStatus.missed,
      ),
    );
    if (edit == true && mounted) await _writeNote(row);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final review = state.review;
    final changes = _changes;
    // Filtered here, immediately before the cells are built. `changes`
    // stays over every draft, visible or not.
    final rows = review?.rows ?? const <ReviewRow>[];
    final matches = [
      for (final row in rows)
        if (kpiMatchesSearch(code: '', title: row.title, term: _term)) row,
    ];
    final visibleIds = {for (final row in matches) row.kpiId};
    final hiddenChanges = changes.where((entry) => !visibleIds.contains(entry.kpiId)).length;
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
              AppFilterField(
                name: KpiReviewScreen.filterFieldName,
                label: 'Filter KPIs',
                helperText: 'By title.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: review.rows.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: KpiReviewScreen.noMatchKey,
                  title: 'No KPIs match',
                  message: 'No KPI of the review matches "${_term.trim()}". Try a '
                      'different title, or clear the filter.',
                )
              else
                _ReviewGrid(
                  cells: [
                    for (final row in matches)
                      _ReviewCell(
                        row: row,
                        status: _drafts[row.kpiId]?.status ?? row.status,
                        note: _noteOf(row),
                        enabled: _enabled,
                        onChoose: (status) => _choose(row, status),
                        onReadNote: () => _readNote(row),
                      ),
                  ],
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
                  if (hiddenChanges > 0) ...[
                    Flexible(
                      child: Text(
                        hiddenChanges == 1
                            ? '1 changed KPI is hidden by the search.'
                            : '$hiddenChanges changed KPIs are hidden by the search.',
                        key: KpiReviewScreen.hiddenChangesKey,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                  ],
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

/// How many cells fit across [width]: the matrix's four, three, two or one.
int _gridColumns(double width) => switch (width) {
      >= 1080 => 4,
      >= 820 => 3,
      >= 560 => 2,
      _ => 1,
    };

/// The tiled matrix: equal-width cells, so the columns line up.
class _ReviewGrid extends StatelessWidget {
  const _ReviewGrid({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth);
        // Floored: a width that rounds up would overflow the run by a fraction
        // of a pixel and drop its last cell onto the next one.
        final width = ((constraints.maxWidth - Spacing.md * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            for (final cell in cells) SizedBox(width: width, child: cell),
          ],
        );
      },
    );
  }
}

/// The filled and outline icon of one judgement, and the colour it takes when
/// chosen.
(IconData, IconData, Color) _judgementIcons(ColorScheme colors, String status) => switch (status) {
      ReviewStatus.met => (Icons.check_circle, Icons.check_circle_outline, colors.primary),
      ReviewStatus.missed => (Icons.cancel, Icons.cancel_outlined, colors.error),
      _ => (Icons.remove_circle, Icons.remove_circle_outline, colors.onSurfaceVariant),
    };

/// The Target line of a KPI on the day on screen, as the popups name it too.
String? _targetText(ReviewRow row) {
  final target = row.target;
  return target == null ? null : formatReviewTarget(row, target);
}

class _ReviewCell extends StatelessWidget {
  const _ReviewCell({
    required this.row,
    required this.status,
    required this.note,
    required this.enabled,
    required this.onChoose,
    required this.onReadNote,
  });

  final ReviewRow row;

  /// The draft judgement, else the saved one; null when neither exists.
  final String? status;

  /// The draft note, else the saved one.
  final String note;
  final bool enabled;
  final ValueChanged<String> onChoose;
  final VoidCallback onReadNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = _targetText(row);
    final saved = row.status == null
        ? null
        : [
            ReviewStatus.label(row.status!),
            if (row.appUser != null) row.appUser!,
            if (row.enteredAt != null) formatEnteredAt(row.enteredAt!),
          ].join(' · ');
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      key: KpiReviewScreen.rowKey(row.kpiId),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.title, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Spacing.xs),
            Text(targetText == null ? 'No target' : 'Daily target: $targetText', style: muted),
            if (targetText == null)
              Text(
                KpiReviewScreen.noTargetHint,
                key: KpiReviewScreen.noTargetHintKey(row.kpiId),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                for (final choice in ReviewStatus.all) _judgementButton(theme.colorScheme, choice),
                const Spacer(),
                if (note.trim().isNotEmpty)
                  IconButton(
                    key: KpiReviewScreen.notePopupKey(row.kpiId),
                    tooltip: 'Read the note',
                    icon: const Icon(Icons.sticky_note_2_outlined),
                    onPressed: onReadNote,
                  ),
              ],
            ),
            if (saved != null) Text(saved, key: KpiReviewScreen.savedStateKey(row.kpiId), style: muted),
          ],
        ),
      ),
    );
  }

  Widget _judgementButton(ColorScheme colors, String choice) {
    final (filled, outline, colour) = _judgementIcons(colors, choice);
    final selected = status == choice;
    return IconButton(
      key: KpiReviewScreen.statusKey(row.kpiId, choice),
      tooltip: ReviewStatus.label(choice),
      isSelected: selected,
      icon: Icon(selected ? filled : outline),
      color: selected ? colour : colors.onSurfaceVariant,
      // A read-only cell still shows what was judged, in its own colour.
      disabledColor: selected ? colour : null,
      // A KPI with no Target cannot have met one.
      onPressed: !enabled || (choice == ReviewStatus.met && row.target == null) ? null : () => onChoose(choice),
    );
  }
}

/// Asks why a KPI was missed. Answers the trimmed note on confirm, and null
/// however else it closes.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.row, required this.note});

  final ReviewRow row;
  final String note;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kpiId = widget.row.kpiId;
    final targetText = _targetText(widget.row);
    final note = _note.text.trim();
    final tooShort = note.length < KpiReviewScreen.minNoteLength;
    return AlertDialog(
      key: KpiReviewScreen.noteDialogKey(kpiId),
      title: Text(widget.row.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: TextField(
          key: KpiReviewScreen.noteKey(kpiId),
          controller: _note,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: targetText == null ? 'Why was it missed?' : 'Why was the Target ($targetText) missed?',
            errorText: tooShort
                ? 'A note of at least ${KpiReviewScreen.minNoteLength} characters is required '
                    'when a KPI is missed (${note.length} so far).'
                : null,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: KpiReviewScreen.noteCancelKey(kpiId),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: KpiReviewScreen.noteSaveKey(kpiId),
          onPressed: tooShort ? null : () => Navigator.of(context).pop(note),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

/// A note, read-only. Answers true when the person asked to edit it.
class _ReadNoteDialog extends StatelessWidget {
  const _ReadNoteDialog({required this.row, required this.note, required this.canEdit});

  final ReviewRow row;
  final String note;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = _targetText(row);
    // A draft the person typed is not the server's, so it names nobody.
    final isSaved = row.note != null && row.note!.trim() == note;
    final author = [
      if (isSaved && row.appUser != null) row.appUser!,
      if (isSaved && row.enteredAt != null) formatEnteredAt(row.enteredAt!),
    ].join(' · ');
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AlertDialog(
      key: KpiReviewScreen.noteReadDialogKey(row.kpiId),
      title: Text(row.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(targetText == null ? 'No target' : 'Daily target: $targetText', style: muted),
            const SizedBox(height: Spacing.sm),
            Text(note, style: theme.textTheme.bodyMedium),
            if (author.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(author, style: muted),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: KpiReviewScreen.noteCloseKey(row.kpiId),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        if (canEdit)
          FilledButton(
            key: KpiReviewScreen.noteEditKey(row.kpiId),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Edit'),
          ),
      ],
    );
  }
}
