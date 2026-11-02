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
///   button when the judgement is Missed and the caller may write. Under any
///   other judgement the note stays readable and the popup says Save clears it.
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
///
/// **The header says whose day it is (issue #395).** The title is the shared
/// `AppPageHeader`'s, so it wears the page's one title style; under it a line
/// names the Site and the day again, because a person with one Site never saw the
/// Site selector and so never saw whose day they were judging. The Site selector
/// and the Day field sit beneath the header's hairline, on the page's own left
/// edge.
///
/// **The icon set is taught, not guessed.** Three judgement icons and their
/// colours are a puzzle on first use, so the legend under the filter names all
/// three — the outline icon, the word the stored Review is written with, and the
/// colour that means it. Colour is never the only carrier: the word is beside
/// every icon, in the legend and in the saved line.
///
/// **The matrix is rows of equal-height cells.** Each row is at most four
/// `Expanded` cells in an `IntrinsicHeight`, so the cells of a row share one
/// width and one height and the eye reads a band; the count per row is the
/// #374 rule (four at 1080, three at 820, two at 560), now compared at the
/// reader's text scale so twice the text drops to fewer columns rather than
/// squeezing a cell until its judgements cannot be pressed. A cell's name is
/// `AppTypography.dense` at w600 and everything it says about the KPI is the 12px
/// floor — the reference board's density, with the name one weight above its
/// metadata rather than one size above it.
///
/// **Both popups are `AppDialog`** (`widgets/app_dialog.dart`, #398): the note
/// popup is a `form` width and the read-only popup a `decision` width, both
/// becoming sheets at a narrow box or a large text size, with `Esc` cancelling,
/// focus trapped and restored, and the actions in the document's order. Their
/// fields, validators, keys, enable conditions and dismissal policy are
/// unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
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

  /// This Screen names its own width because it is a tiled matrix of up to four
  /// cells, and [AppPageFrame] leaves a Screen that lays out a wide table or a
  /// board to pass its own. The number is arithmetic: the sidebar is 260 and the
  /// list pads 32, so a 1100px frame (the registers' width) would leave 1068 of
  /// content, under the 1080 a fourth column needs. 1200 leaves 1168 at the
  /// widest window, and four across starts at a 1372px window with cells of 261
  /// (283 at the widest), which is what a cell's title, Daily Target, three
  /// judgement icons, note icon and saved line need at `bodyMedium`.
  static const double maxWidth = 1200;

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
  /// The Screen's title. It is `AppPageHeader`'s title text now, and this key sits
  /// on the header itself, so the name every caller and test knows still finds the
  /// page's header (#395).
  static const ValueKey<String> headingKey = ValueKey<String>('kpi-review-heading');
  static ValueKey<String> rowKey(int kpiId) => ValueKey<String>('kpi-review-row-$kpiId');

  static const ValueKey<String> noMatchKey = ValueKey<String>('kpi-review-no-match');

  /// The line under the title that says which Site and which day this matrix is
  /// for (issue #395), and the legend of the three judgement icons.
  static const ValueKey<String> siteDayKey = ValueKey<String>('kpi-review-site-day');
  static const ValueKey<String> legendKey = ValueKey<String>('kpi-review-legend');
  static ValueKey<String> legendItemKey(String status) =>
      ValueKey<String>('kpi-review-legend-$status');

  /// A note popup's own actions, by the id `AppDialog` keys them with.
  static String noteSaveId(int kpiId) => 'kpi-review-note-save-$kpiId';
  static String noteCancelId(int kpiId) => 'kpi-review-note-cancel-$kpiId';
  static String noteEditId(int kpiId) => 'kpi-review-note-edit-$kpiId';
  static String noteCloseId(int kpiId) => 'kpi-review-note-close-$kpiId';

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
  static ValueKey<String> noteSaveKey(int kpiId) => AppDialog.actionKey(noteSaveId(kpiId));
  static ValueKey<String> noteCancelKey(int kpiId) => AppDialog.actionKey(noteCancelId(kpiId));

  /// The cell's note icon, and the read-only popup it opens.
  static ValueKey<String> notePopupKey(int kpiId) => ValueKey<String>('kpi-review-note-popup-$kpiId');
  static ValueKey<String> noteReadDialogKey(int kpiId) => ValueKey<String>('kpi-review-note-read-$kpiId');
  static ValueKey<String> noteEditKey(int kpiId) => AppDialog.actionKey(noteEditId(kpiId));
  static ValueKey<String> noteCloseKey(int kpiId) => AppDialog.actionKey(noteCloseId(kpiId));
  static ValueKey<String> noteClearsKey(int kpiId) => ValueKey<String>('kpi-review-note-clears-$kpiId');
  static ValueKey<String> noTargetHintKey(int kpiId) => ValueKey<String>('kpi-review-no-target-$kpiId');

  /// The cell's saved state in place, e.g. `Met · A B · 2026-10-30 08:12`.
  static ValueKey<String> savedStateKey(int kpiId) => ValueKey<String>('kpi-review-saved-state-$kpiId');

  static const String noTargetHint = 'No target — set one first';

  /// What the read-only popup says of a note the judgement on screen will drop.
  static const String clearsNoteText = 'Saving this KPI as Met or Not measured clears this note';

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
  /// (Cancel, a browser back) answers null and leaves [_drafts] alone, so there
  /// is nothing to restore.
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
        status: status,
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
    final siteName = [
      for (final site in state.sites)
        if (site.id == state.siteId) site.name,
    ];
    return Center(
      child: AppPageFrame(
        maxWidth: KpiReviewScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              key: KpiReviewScreen.headingKey,
              title: reviewDate == null ? 'KPI Review' : 'KPI Review for $reviewDate',
              description:
                  'Judge each KPI of the MTU line against its Daily Target: met, missed or not measured.',
              // The title names the day; this line names the Site the day belongs
              // to, which the Screen never said when the person has one Site and
              // so never saw the selector (issue #395).
              below: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: Spacing.xs),
                      Flexible(
                        child: Text(
                          siteName.isEmpty
                              ? (reviewDate ?? '')
                              : '${siteName.first}${reviewDate == null ? '' : ' · $reviewDate'}',
                          key: KpiReviewScreen.siteDayKey,
                          style: AppTypography.floor(context)
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
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
                            decoration:
                                const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
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
                              if (date != null) {
                                context.read<KpiReviewBloc>().add(ReviewDateSelected(date));
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
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
              const SizedBox(height: Spacing.md),
              const _JudgementLegend(),
              const SizedBox(height: Spacing.md),
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

/// How many cells fit across a box of [width] at a text scale of 1: the
/// matrix's four, three, two or one.
///
/// These three numbers are what makes four-across reachable at all (issue #374):
/// 1080 is four cells of 261 plus three 12px gaps, which a 1200px page holds as
/// 1168 of content; 820 is three of them; 560 is two. They are compared against
/// the box **at the reader's text scale** (`AppBreakpoints.effective`), so twice
/// the text drops to fewer columns instead of squeezing a cell until its
/// judgement row cannot be pressed (#379, #381 — the bug that shipped twice when
/// a breakpoint read the box as it is).
int _gridColumns(double width) => switch (width) {
      >= 1080 => 4,
      >= 820 => 3,
      >= 560 => 2,
      _ => 1,
    };

/// The legend of the three judgements: the icon a cell draws, and the word the
/// stored Review is written with (issue #395).
///
/// A cell's judgement is an icon and its colour, and an icon set nobody has been
/// taught is a puzzle on first use. The legend is the teaching: filled or outline,
/// what each one means, in the palette's own meaning colours — and the word beside
/// every icon, so the set never depends on telling a tint apart.
class _JudgementLegend extends StatelessWidget {
  const _JudgementLegend();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final floor = AppTypography.floor(context)?.copyWith(color: colors.onSurfaceVariant);
    return Wrap(
      key: KpiReviewScreen.legendKey,
      spacing: Spacing.lg,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final status in ReviewStatus.all)
          Row(
            key: KpiReviewScreen.legendItemKey(status),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_judgementIcons(colors, status).$2, size: 16, color: _judgementIcons(colors, status).$3),
              const SizedBox(width: Spacing.xs),
              Text(ReviewStatus.label(status), style: floor),
            ],
          ),
      ],
    );
  }
}

/// The tiled matrix: equal-width cells, so the columns line up.
///
/// **Rows of `Expanded` cells, not a `Wrap` of sized ones (issue #395).** A
/// `Wrap` cannot stretch a run, so the last row of a three-across matrix was
/// always short — and every cell in a row was its own height, because nothing
/// tied them together. Chunking into rows of `Expanded` cells fixes the widths by
/// construction (no floor-to-double rounding to defend), and an `IntrinsicHeight`
/// per row makes the cells of one row share the height of the tallest — the shape
/// a matrix of judgements needs, since the eye reads a row as one band.
///
/// The count per row is unchanged from #374: `_gridColumns`, at the reader's text
/// scale, decides four, three, two or one.
class _ReviewGrid extends StatelessWidget {
  const _ReviewGrid({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // The box divided by the text scale is the same comparison as
        // `AppBreakpoints.effective` (a threshold times the scale), stated once
        // for a function that answers in column counts.
        final columns = _gridColumns(constraints.maxWidth / (scale < 1 ? 1 : scale));
        final rows = <List<Widget>>[];
        for (var index = 0; index < cells.length; index += columns) {
          rows.add(cells.sublist(index, (index + columns).clamp(0, cells.length)));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const SizedBox(height: Spacing.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < rows[index].length; column++) ...[
                      if (column > 0) const SizedBox(width: Spacing.md),
                      Expanded(child: rows[index][column]),
                    ],
                  ],
                ),
              ),
            ],
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
    final palette = AppColors.of(context);
    final targetText = _targetText(row);
    final saved = row.status == null
        ? null
        : [
            ReviewStatus.label(row.status!),
            if (row.appUser != null) row.appUser!,
            if (row.enteredAt != null) formatEnteredAt(row.enteredAt!),
          ].join(' · ');
    // 12px floor for everything the cell says about the KPI, 14px w600 for its
    // name: the reference board's density, with the name one weight above the
    // metadata rather than one size above it (issue #395).
    final floor = AppTypography.floor(context)?.copyWith(color: palette.textMuted);
    return Card(
      key: KpiReviewScreen.rowKey(row.kpiId),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.title,
              style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Spacing.xs),
            Text(targetText == null ? 'No target' : 'Daily target: $targetText', style: floor),
            if (targetText == null)
              Text(
                KpiReviewScreen.noTargetHint,
                key: KpiReviewScreen.noTargetHintKey(row.kpiId),
                style: floor?.copyWith(color: theme.colorScheme.error),
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
            if (saved != null) Text(saved, key: KpiReviewScreen.savedStateKey(row.kpiId), style: floor),
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
    return AppDialog(
      key: KpiReviewScreen.noteDialogKey(kpiId),
      // The title is the KPI being judged; the field's own label names the Target
      // that was missed, so the shell adds no description on top of it.
      title: widget.row.title,
      size: AppDialogSize.form,
      actions: [
        AppDialogAction(
          id: KpiReviewScreen.noteCancelId(kpiId),
          label: 'Cancel',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: KpiReviewScreen.noteSaveId(kpiId),
          label: 'Confirm',
          onPressed: tooShort ? null : () => Navigator.of(context).pop(note),
        ),
      ],
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
    );
  }
}

/// A note, read-only. Answers true when the person asked to edit it.
class _ReadNoteDialog extends StatelessWidget {
  const _ReadNoteDialog({required this.row, required this.note, required this.status, required this.canEdit});

  final ReviewRow row;
  final String note;

  /// The draft judgement, else the saved one; null when neither exists.
  final String? status;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final targetText = _targetText(row);
    // A draft the person typed is not the server's, so it names nobody.
    final isSaved = row.note != null && row.note!.trim() == note;
    final author = [
      if (isSaved && row.appUser != null) row.appUser!,
      if (isSaved && row.enteredAt != null) formatEnteredAt(row.enteredAt!),
    ].join(' · ');
    final floor = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    return AppDialog(
      key: KpiReviewScreen.noteReadDialogKey(row.kpiId),
      title: row.title,
      // Reading one note is a decision-width dialog: no fields, two actions.
      size: AppDialogSize.decision,
      actions: [
        AppDialogAction(
          id: KpiReviewScreen.noteCloseId(row.kpiId),
          label: 'Close',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (canEdit)
          AppDialogAction(
            id: KpiReviewScreen.noteEditId(row.kpiId),
            label: 'Edit',
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(targetText == null ? 'No target' : 'Daily target: $targetText', style: floor),
          const SizedBox(height: Spacing.sm),
          Text(note, style: AppTypography.dense(context)),
          if (author.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(author, style: floor),
          ],
          if (status != ReviewStatus.missed) ...[
            const SizedBox(height: Spacing.sm),
            Text(KpiReviewScreen.clearsNoteText, key: KpiReviewScreen.noteClearsKey(row.kpiId), style: floor),
          ],
        ],
      ),
    );
  }
}
