/// A Section's production day (issue #339, spec #332), at
/// `/production/sections/:orgUnitId/board?date=`: every shift instance of the
/// day, earliest first, with its handover and what is wrong at that shift
/// boundary — the exceptions the server reports (`no handover recorded`,
/// `unacknowledged`, `amended after acknowledgement`), the late flag, and how
/// long after the shift began the handover was acknowledged.
///
/// An absent handover is shown as absent: there is no row to fill, only a
/// shift with no handover on it, which is the exception (ADR-0054's "derived,
/// never a fake row"). From a submitted handover the incoming Team Leader opens
/// the acknowledgement (`.../board/acknowledge/:handoverId`).
///
/// **The Production Destination lands here without a Section**
/// (`/production/sections`): the Screen then offers the Site's Org Unit tree
/// and opens the board of the Section chosen — the same shape the Attendance
/// picker gives its sheet, so this Screen has a real address to be reached
/// from. Only a Section can be chosen, because a handover is recorded at one.
///
/// **The shape, and why (issue #389's design pass).** A board is read at a
/// glance before it is read line by line, so the page answers three questions
/// in that order: how the day is going (the counts row, above the fold), which
/// shift each card is and how far through it the plant is (a shift-instance
/// header and a position bar), and what each machine was left as (tiles, at a
/// 44px target, each naming its state in words). `docs/design-language.md` §6
/// ("the shift board") is where those three are written down; this file is the
/// only Screen that spends them.
///
/// **Everything it shows is the server's.** The counts are a tally of the
/// exceptions `getSectionDay` already reported — the board adds them up and
/// decides nothing; the position bar is the reader's own clock against the
/// shift's two timestamps, which is a clock reading rather than an answer about
/// the day (nothing on this Screen recomputes a flag, a latency or an
/// exception). `now` is injectable for the one reason every clock in a widget
/// is: a test cannot assert "3 h into the shift" against the hour it happens to
/// run.
///
/// **The Section's name is the page's title, not each card's.** Three cards
/// repeating "Self-Closing" under a title that already says it would be three
/// copies of one fact; a shift card's own header says which shift it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_stat_tile.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'handover.dart';
import 'handover_format.dart';
import 'handover_vocabulary.dart';
import 'section_board_bloc.dart';

class SectionBoardScreen extends StatelessWidget {
  const SectionBoardScreen({super.key, this.orgUnitId, this.date, this.now});

  /// Null at the Destination's own address, before a Section is chosen.
  final String? orgUnitId;
  final String? date;

  /// The reader's clock, read once per build so every shift card on the board
  /// measures its own position against the same instant. Null reads
  /// `DateTime.now()`; only a test passes one, so that "2 h 10 min into the
  /// shift" is a fact of the fixture rather than of the hour the suite ran.
  final DateTime? now;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> loadedKey = ValueKey<String>('section-board-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('section-board-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('section-board-retry');
  static const ValueKey<String> dateFieldKey = ValueKey<String>('section-board-date');
  static const ValueKey<String> emptyKey = ValueKey<String>('section-board-empty');
  static const ValueKey<String> chooserKey = ValueKey<String>('section-board-chooser');
  static ValueKey<String> sectionRowKey(String id) => ValueKey<String>('section-board-section-$id');
  static ValueKey<String> shiftRowKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId');
  static ValueKey<String> handoverStatusKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-status');
  static ValueKey<String> exceptionKey(String shiftInstanceId, String exception) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-$exception');
  static ValueKey<String> lateKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-late');
  static ValueKey<String> latencyKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-latency');
  static ValueKey<String> openHandoverKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-open');
  static ValueKey<String> acknowledgeKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-acknowledge');

  /// A shift card's own header, and the line that says where in the shift the
  /// reader is (issue #389).
  static ValueKey<String> shiftTitleKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-title');
  static ValueKey<String> shiftPositionKey(String shiftInstanceId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-position');

  /// One machine tile, by the shift it was recorded on and the Asset it names.
  static ValueKey<String> machineTileKey(String shiftInstanceId, String assetId) =>
      ValueKey<String>('section-board-shift-$shiftInstanceId-machine-$assetId');

  /// The counts row, and each of its four tiles by what it counts.
  static const ValueKey<String> countsKey = ValueKey<String>('section-board-counts');
  static ValueKey<String> countKey(String what) => ValueKey<String>('section-board-count-$what');

  /// The chooser's own shared states (issue #389: the Destination's landing is
  /// part of this Screen, so it designs its states with the shared widgets).
  static const ValueKey<String> chooserRetryKey = ValueKey<String>('section-board-chooser-retry');
  static const ValueKey<String> chooserEmptyKey = ValueKey<String>('section-board-chooser-empty');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final orgUnitId = this.orgUnitId;
    if (orgUnitId == null) return const _SectionChooser();

    final state = context.watch<SectionBoardBloc>().state;
    return Scaffold(
      body: switch (state) {
        SectionBoardLoading() => const SkeletonList(maxWidth: maxWidth),
        SectionBoardUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.sectionThatSectionSDayCouldNotBe,
            message: message,
            retryKey: retryKey,
            onRetry: () =>
                context.read<SectionBoardBloc>().add(SectionBoardStarted(orgUnitId: orgUnitId, date: date)),
          ),
        SectionBoardLoaded(day: final day) => _Board(orgUnitId: orgUnitId, day: day, now: now),
      },
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.orgUnitId, required this.day, required this.now});

  final String orgUnitId;
  final SectionDay day;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final at = now ?? DateTime.now();
    final shifts = day.shifts;
    return Center(
      child: AppPageFrame(
        maxWidth: SectionBoardScreen.maxWidth,
        child: ListView(
          key: SectionBoardScreen.loadedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            // A crumb above the title rather than a back button beside it: the
            // reader arrived from the chooser, and the one thing above the page
            // is where it sits in that tree (`docs/design-language.md` §6).
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
                child: TextButton.icon(
                  onPressed: () => context.go(Routes.production),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.sectionChooseAnotherSection),
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            AppPageHeader(
              title: day.sectionName,
              description: l10n.sectionEveryShiftOfTheProductionDayWith,
              below: AppToolbar(
                filters: [
                  SizedBox(
                    width: 260,
                    child: AppDateField(
                      key: SectionBoardScreen.dateFieldKey,
                      name: 'section-board-date',
                      label: l10n.attendancePickerProductionDay,
                      value: day.productionDate,
                      onChanged: (value) {
                        if (value != null) context.go(Routes.sectionBoard(orgUnitId, date: value));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            _ShiftCounts(shifts: shifts),
            const SizedBox(height: Spacing.md),
            if (shifts.isEmpty)
              PlatformEmptyState.noneExist(
                key: SectionBoardScreen.emptyKey,
                title: l10n.sectionNoShiftsScheduled,
                message: l10n.sectionNoShiftsAreScheduledAtThisSection,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shifts.length; i++) ...[
                    if (i > 0) const SizedBox(height: Spacing.md),
                    _ShiftRow(orgUnitId: orgUnitId, day: day, shift: shifts[i], now: at),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The four counts the day is judged on, above the shift cards (issue #389).
///
/// Each is a tally of what `getSectionDay` already reported — a shift carrying
/// the `no_handover` exception, the `unacknowledged` one, and its own `late`
/// flag — never a second opinion about the day. A zero is painted quiet
/// (`AppStatTile.quiet`) so a clean day reads as clean at a glance rather than
/// as four loud zeroes.
class _ShiftCounts extends StatelessWidget {
  const _ShiftCounts({required this.shifts});

  final List<SectionShift> shifts;

  /// One tile's floor width. Four `AppTouchTarget.min`s, so two tiles fit the
  /// narrowest page box the Shell hands a Screen (440 − 2×16 = 408) and four
  /// fit this Screen's widest one (`AppLayout.pageWidth` 900 − 2×`Spacing.lg`
  /// = 868). That is why the row is two or four and never three: a run of three
  /// over a fourth tile leaves the last one alone on its row.
  static const double tileFloor = AppTouchTarget.min * 4;

  int _counted(String exception) =>
      shifts.where((shift) => shift.exceptions.contains(exception)).length;

  @override
  Widget build(BuildContext context) {
    final counts = <(String, String, String)>[
      ('shifts', 'Shifts', '${shifts.length}'),
      ('no_handover', 'No handover', '${_counted('no_handover')}'),
      ('unacknowledged', 'Unacknowledged', '${_counted('unacknowledged')}'),
      ('late', 'Late', '${shifts.where((shift) => shift.late == true).length}'),
    ];

    Widget tile((String, String, String) count) => AppStatTile(
          key: SectionBoardScreen.countKey(count.$1),
          label: count.$2,
          figure: count.$3,
          quiet: count.$3 == '0',
        );

    return LayoutBuilder(
      key: SectionBoardScreen.countsKey,
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= AppBreakpoints.effective(context, tileFloor * 4) ? 4 : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < counts.length; start += perRow) ...[
              if (start > 0) const SizedBox(height: Spacing.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < start + perRow && i < counts.length; i++) ...[
                      if (i > start) const SizedBox(width: Spacing.md),
                      Expanded(child: tile(counts[i])),
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

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.orgUnitId, required this.day, required this.shift, required this.now});

  final String orgUnitId;
  final SectionDay day;
  final SectionShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final id = shift.shiftInstanceId;
    final handover = shift.handover;
    final latency = shift.acknowledgementLatencyMinutes;
    final lines = handover?.machineLines ?? const <MachineLine>[];

    return Card(
      key: SectionBoardScreen.shiftRowKey(id),
      // The page frame's own left edge is the title's, and a card's default
      // margin would set the first row 4px inside it (issue #193's lesson,
      // restated by `page_alignment_test.dart`).
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The shift-instance header (issue #389): which shift this card is,
            // and everything the server decided about its boundary, on one
            // wrapping line so a narrow box drops the chips under the name
            // rather than squeezing it.
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.sectionShift(formatClock(shift.startsAt), formatClock(shift.endsAt)),
                  key: SectionBoardScreen.shiftTitleKey(id),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (handover != null)
                  StatusChip(
                    key: SectionBoardScreen.handoverStatusKey(id),
                    label: switch (handover.status) {
                      'draft' => 'Draft',
                      'submitted' => 'Submitted',
                      'acknowledged' => 'Acknowledged',
                      _ => handover.status,
                    },
                    tone: switch (handover.status) {
                      'acknowledged' => StatusTone.success,
                      'submitted' => StatusTone.info,
                      _ => StatusTone.neutral,
                    },
                  ),
                if (shift.late == true)
                  StatusChip(key: SectionBoardScreen.lateKey(id), label: l10n.commonLate, tone: StatusTone.warning),
                for (final exception in shift.exceptions)
                  StatusChip(
                    key: SectionBoardScreen.exceptionKey(id, exception),
                    label: HandoverVocabulary.exceptionLabel(exception),
                    tone: StatusTone.danger,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _ShiftPosition(shift: shift, now: now),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _MachineTiles(shiftInstanceId: id, lines: lines),
            ],
            if (handover?.authorDisplayName != null || latency != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                [
                  if (handover?.authorDisplayName != null) l10n.sectionHandedOverBy((handover!.authorDisplayName ?? '')),
                  if (latency != null) l10n.sectionAcknowledgedAfterTheShiftBegan(formatMinutes(latency)),
                ].join(' · '),
                key: latency != null ? SectionBoardScreen.latencyKey(id) : null,
                style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                OutlinedButton.icon(
                  key: SectionBoardScreen.openHandoverKey(id),
                  onPressed: () => context.go(Routes.shiftHandover(orgUnitId, id, date: day.productionDate)),
                  icon: Icon(handover == null || handover.isDraft ? Icons.edit_note_outlined : Icons.description_outlined),
                  label: Text(switch (handover?.status) {
                    null => 'Write the handover',
                    'draft' => 'Continue the handover',
                    _ => 'Open the handover',
                  }),
                ),
                if (handover != null && handover.status == 'submitted')
                  FilledButton.icon(
                    key: SectionBoardScreen.acknowledgeKey(id),
                    onPressed: () => context.go(
                      Routes.handoverAcknowledge(orgUnitId, handover.id, date: day.productionDate),
                    ),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: Text(l10n.commonAcknowledge),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where in the shift the reader is (issue #389): a bar filled to the reader's
/// own clock across the shift's two server-sent timestamps, and the span said in
/// words beneath it.
///
/// The bar is a reading, not a judgement — it decides nothing about the day, and
/// a shift that has not started reads "Starts in …" rather than an empty bar
/// with no explanation. `LinearProgressIndicator` with a `value` and no
/// animation rather than a hand-drawn bar, so the one maths lives in
/// `handover_format.dart` and is unit-testable without a widget.
class _ShiftPosition extends StatelessWidget {
  const _ShiftPosition({required this.shift, required this.now});

  final SectionShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final fraction = shiftProgressFraction(now, shift.startsAt, shift.endsAt);
    return Column(
      key: SectionBoardScreen.shiftPositionKey(shift.shiftInstanceId),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fraction != null)
          // Decorative on top of the words beneath it, which say the same thing
          // in a reader's own terms: announcing "progress 42 percent" and then
          // "3 h in · 5 h to go" says it twice.
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Spacing.xxs),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: Spacing.xs,
                color: palette.actionPrimary,
                backgroundColor: palette.surfaceMuted,
              ),
            ),
          ),
        if (fraction != null) const SizedBox(height: Spacing.xs),
        Text(
          formatShiftProgress(now, shift.startsAt, shift.endsAt),
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}

/// The machines a shift was left with, as tiles (issue #389).
///
/// A tile is at least [AppTouchTarget.min] tall and four targets wide, so two
/// fit the narrowest page box and each is comfortably reachable in a glove. It
/// carries the Asset's own code and name and a [StatusChip] naming the state in
/// words: colour groups the states, and no tile asks a reader to read a hue
/// without a word beside it (`docs/design-language.md` §6's legend rule, spent
/// per tile rather than as a page legend because each tile is one machine).
class _MachineTiles extends StatelessWidget {
  const _MachineTiles({required this.shiftInstanceId, required this.lines});

  final String shiftInstanceId;
  final List<MachineLine> lines;

  static const double tileFloor = AppTouchTarget.min * 4;

  /// What a machine's state means, in the vocabulary's own terms: running is
  /// live and in hand (`info`), down is the one state that wants a decision
  /// (`warning` — `StatusTone` names "an Asset that is down" under exactly
  /// that tone), and every planned state is `neutral` because somebody chose
  /// it on purpose.
  static StatusTone toneOf(String state) => switch (state) {
        'running' || 'running_manual' => StatusTone.info,
        'down' => StatusTone.warning,
        'idle' || 'maintenance' || 'cleaning' || 'changeover' || 'isolated' => StatusTone.neutral,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // A tile never asks for more room than the row it sits in has, so a
        // long Asset name wraps rather than overflowing a narrow box.
        final minWidth = constraints.maxWidth < tileFloor ? constraints.maxWidth : tileFloor;
        return Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final line in lines)
              ConstrainedBox(
                key: SectionBoardScreen.machineTileKey(shiftInstanceId, line.assetId),
                constraints: BoxConstraints(
                  minWidth: minWidth,
                  maxWidth: constraints.maxWidth,
                  minHeight: AppTouchTarget.min,
                ),
                child: Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.assetCode,
                        style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                      ),
                      Text(line.assetName, style: AppTypography.dense(context)),
                      const SizedBox(height: Spacing.xs),
                      StatusChip(
                        label: HandoverVocabulary.machineStateLabel(line.state),
                        tone: toneOf(line.state),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The Destination's landing: the Site's Org Unit tree, browsed with People's
/// `OrgUnitPickerBloc`, where a Section opens its board and any other level
/// only expands.
class _SectionChooser extends StatelessWidget {
  const _SectionChooser();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrgUnitPickerBloc>(
      create: (context) => OrgUnitPickerBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      )..add(const OrgUnitPickerStarted()),
      child: const _ChooserBody(),
    );
  }
}

class _ChooserBody extends StatelessWidget {
  const _ChooserBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    // A read that is outstanding is the whole body: the placeholder has the
    // shape of what will arrive, so the page does not flash a heading over a
    // 24px spinner (issue #103's four states).
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      return const Scaffold(body: SkeletonList(maxWidth: SectionBoardScreen.maxWidth));
    }

    final String? failure = state.sitesStatus == SitesStatus.failed
        ? (state.sitesFailure ?? 'The Sites are unavailable.')
        : state.rootsFailure;

    final Widget body;
    if (failure != null) {
      body = PlatformFailureState(
        key: SectionBoardScreen.failedKey,
        title: l10n.sectionThatSectionTreeCouldNotBeRead,
        message: failure,
        retryKey: SectionBoardScreen.chooserRetryKey,
        // Re-dispatching the read the chooser already opened with: the same
        // event, not a new one, so a retry asks the same question again.
        onRetry: () => bloc.add(const OrgUnitPickerStarted()),
      );
    } else if (state.rows.isEmpty) {
      body = PlatformEmptyState.noneExist(
        key: SectionBoardScreen.chooserEmptyKey,
        title: l10n.sectionNothingToOpenHere,
        message: l10n.commonNothingToBrowseInThisSite,
        icon: Icons.account_tree_outlined,
      );
    } else {
      body = AppListCard(
        rows: [for (final row in state.rows) _OrgUnitRow(row: row, bloc: bloc)],
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: SectionBoardScreen.maxWidth,
          child: ListView(
            key: SectionBoardScreen.chooserKey,
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(
                title: l10n.navShiftHandovers,
                description: l10n.sectionChooseASectionToOpenItsBoard,
                below: state.sites.length > 1
                    ? DropdownButtonFormField<String>(
                        initialValue: state.siteId,
                        isDense: true,
                        decoration: InputDecoration(labelText: l10n.commonSite),
                        items: [
                          for (final site in state.sites)
                            DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                        ],
                        onChanged: (siteId) {
                          if (siteId != null) bloc.add(OrgUnitPickerSiteSelected(siteId));
                        },
                      )
                    : null,
              ),
              const SizedBox(height: Spacing.md),
              DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodyMedium!, child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgUnitRow extends StatelessWidget {
  const _OrgUnitRow({required this.row, required this.bloc});

  final OrgUnitRow row;
  final OrgUnitPickerBloc bloc;

  static const String _sectionUnitType = 'section';

  /// The disclosure is the row's only icon-only control, so it carries its
  /// tooltip and its own 44px target (issue #389's access floor) — the 32px box
  /// it used to sit in is under every guideline this Platform holds itself to.
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final isSection = row.node.unitType == _sectionUnitType;
    return Padding(
      padding: EdgeInsets.only(left: row.depth * Spacing.lg),
      child: Row(
        children: [
          SizedBox(
            width: AppTouchTarget.min,
            height: AppTouchTarget.min,
            child: row.isLoadingChildren
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.md),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? l10n.commonCollapse : l10n.commonExpand,
                    onPressed: () => bloc.add(
                      row.isExpanded ? OrgUnitPickerCollapsed(row.node.id) : OrgUnitPickerExpanded(row.node.id),
                    ),
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: InkWell(
              key: SectionBoardScreen.sectionRowKey(row.node.id),
              onTap: isSection ? () => context.go(Routes.sectionBoard(row.node.id)) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isSection ? row.node.name : '${row.node.name} · ${row.node.unitType}',
                      style: isSection
                          ? TextStyle(color: palette.actionPrimary)
                          : TextStyle(color: palette.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
