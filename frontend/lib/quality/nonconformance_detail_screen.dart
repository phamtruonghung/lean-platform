/// One Non-conformance (issue #205): what was found, where, how much of it
/// there is, what can be done about it next, the cause behind it, and every step
/// that number has taken since it was written down.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so this
/// Screen gates nothing except the four decisions ADR-0035 puts behind the
/// Grant's Quality authority. What it *offers* otherwise is gated by the server:
/// raising the severity, recording containment and increasing the quantity are
/// all writes at the Org Unit the record sits at, and a caller without a Grant
/// reaching it gets a sentence back rather than a hidden button.
///
/// The five affordances are addressed dialogs (ADR-0021): a refresh lands on the
/// record with the control open, and the change a caller was making is not lost
/// to a stray back-navigation.
///
/// **The page head** is `AppPageHeader('Non-conformance')`, drawn above the
/// state switch so every state carries it — the loading skeleton, a failed
/// read, the missing record and the loaded record alike (issue #391's design
/// law 3: one page rhythm). The record's own identity — its number, its state,
/// its severity — is the summary card's first line, never the page's title.
///
/// **The page answers "what, whose, how bad, what next" above the fold (issue
/// #390).** A summary card carries the record's number, its chips and the three
/// facts that identify it; the sections beneath it are ordered by what a reader
/// does next rather than by the order the tickets were built in:
///
/// 1. **What was found** and **what can be done** — the deciding facts and the
///    transitions, side by side, so the next step is not a scroll away.
/// 2. **The cause** (the Concerns this record is evidence behind, issue #208) —
///    hoisted above the record's own history, because the CAPA trail is the
///    thing this page exists to lead to and it used to sit at the foot of a
///    700-line page. Nothing about the link changed; only where it is read.
/// 3. **Quantity history**, **Dispositions** and **Corrections** — the evidence,
///    in the order it accumulated.
///
/// Sections pair up from [AppBreakpoints.detailTwoColumn] of box, which is why
/// [maxWidth] is 1040 rather than the old 900: at a 1280px window the Shell
/// leaves a page box of 1020, and a 900-page could never reach a 1000 breakpoint
/// (design-language §10).
///
/// **This Screen hides no field.** ADR-0037 restricts three *Safety* fields
/// (injury classification and its two companions); nothing on a Non-conformance
/// is restricted, so every fact below is rendered for every reader who can see
/// the Site — the same behaviour as before this pass, kept deliberately rather
/// than by omission. A future restricted field is rendered by leaving it out,
/// never by greying it out or hiding it behind a tooltip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'issue_image.dart';
import 'issue_images_bloc.dart';
import 'issue_images_section.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';
import 'quality_api.dart';
import 'quality_photo_picker.dart';
import 'slide_show_toggle.dart';
import '../widgets/notice_text.dart';

class NonconformanceDetailScreen extends StatelessWidget {
  const NonconformanceDetailScreen({super.key, required this.nonconformanceId});

  final String nonconformanceId;

  /// 1040, so a box of 1000 is reachable: at a 1280px window the Shell leaves
  /// 1020, and [AppBreakpoints.detailTwoColumn] compares against that box.
  static const double maxWidth = 1040;

  static const ValueKey<String> backKey = ValueKey<String>('nonconformance-back');

  /// The slide-show switch on this record (issue #419).
  static const ValueKey<String> slideShowKey =
      ValueKey<String>('nonconformance-detail-slide-show');
  static const ValueKey<String> statusKey = ValueKey<String>('nonconformance-detail-status');
  static const ValueKey<String> severityKey = ValueKey<String>('nonconformance-detail-severity');
  static const ValueKey<String> filedKey = ValueKey<String>('nonconformance-detail-filed');
  static const ValueKey<String> quantityKey = ValueKey<String>('nonconformance-detail-quantity');
  static const ValueKey<String> quantityHistoryKey =
      ValueKey<String>('nonconformance-detail-quantity-history');
  static const ValueKey<String> noHistoryKey =
      ValueKey<String>('nonconformance-detail-no-history');
  static const ValueKey<String> increaseQuantityKey =
      ValueKey<String>('nonconformance-detail-increase');
  static const ValueKey<String> updateKey = ValueKey<String>('nonconformance-detail-update');
  static const ValueKey<String> dispositionKey =
      ValueKey<String>('nonconformance-detail-disposition');
  static const ValueKey<String> concessionKey =
      ValueKey<String>('nonconformance-detail-concession');
  static const ValueKey<String> lowerSeverityKey =
      ValueKey<String>('nonconformance-detail-lower-severity');
  static const ValueKey<String> reopenKey = ValueKey<String>('nonconformance-detail-reopen');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-detail-cancel');
  static const ValueKey<String> dispositionsKey =
      ValueKey<String>('nonconformance-detail-dispositions');
  static const ValueKey<String> noDispositionsKey =
      ValueKey<String>('nonconformance-detail-no-dispositions');
  static const ValueKey<String> correctionsKey =
      ValueKey<String>('nonconformance-detail-corrections');
  static const ValueKey<String> noCorrectionsKey =
      ValueKey<String>('nonconformance-detail-no-corrections');
  static const ValueKey<String> closedKey = ValueKey<String>('nonconformance-detail-closed');
  static const ValueKey<String> failureKey = ValueKey<String>('nonconformance-detail-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('nonconformance-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformance-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('nonconformance-detail-missing');
  static const ValueKey<String> summaryKey = ValueKey<String>('nonconformance-detail-summary');

  /// The page's own scrollable, so a test (or a future sticky header) can name
  /// what it is scrolling rather than guessing at the ListView in the tree.
  static const ValueKey<String> contentKey = ValueKey<String>('nonconformance-detail-content');

  static ValueKey<String> changeKey(String id) => ValueKey<String>('nonconformance-change-$id');

  static ValueKey<String> dispositionRowKey(String id) =>
      ValueKey<String>('nonconformance-disposition-$id');

  static ValueKey<String> correctionRowKey(String id) =>
      ValueKey<String>('nonconformance-correction-$id');

  /// The Concerns this record is evidence behind (issue #208): the section, its
  /// empty state, one row per Concern, and the two controls that change it.
  static const ValueKey<String> concernsKey = ValueKey<String>('nonconformance-detail-concerns');
  static const ValueKey<String> noConcernsKey =
      ValueKey<String>('nonconformance-detail-no-concerns');
  static const ValueKey<String> raiseConcernKey =
      ValueKey<String>('nonconformance-detail-raise-concern');
  static const ValueKey<String> linkConcernKey =
      ValueKey<String>('nonconformance-detail-link-concern');
  static const ValueKey<String> concernNoticeKey =
      ValueKey<String>('nonconformance-detail-concern-notice');

  static ValueKey<String> concernRowKey(String id) => ValueKey<String>('nonconformance-concern-$id');

  static final ButtonStyle actionStyle =
      FilledButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));
  static final ButtonStyle secondaryStyle =
      OutlinedButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NonconformanceDetailBloc>().state;
    final l10n = AppLocalizations.of(context);

    // The page head sits above the state switch, so a load, a failed read, a
    // missing record and the record itself all carry the same title row and
    // back control (issue #391's design law 3). The missing state is the one
    // state whose back control belongs to its empty state — that state already
    // offers exactly this control under [NonconformanceDetailScreen.backKey],
    // and two widgets may not share one key.
    final missing = state is NonconformanceDetailMissing;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(showBack: !missing),
          Expanded(
            child: switch (state) {
              NonconformanceDetailLoading() =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              NonconformanceDetailMissing() => PlatformEmptyState.noneExist(
                  key: missingKey,
                  title: l10n.nonconformanceDetailMissingTitle,
                  message: l10n.nonconformanceDetailMissingMessage,
                  icon: Icons.search_off_outlined,
                  actionLabel: l10n.nonconformanceDetailBack,
                  actionKey: backKey,
                  onAction: () => context.go(Routes.nonConformances),
                ),
              NonconformanceDetailUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: l10n.nonconformanceDetailUnavailableTitle,
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context
                      .read<NonconformanceDetailBloc>()
                      .add(const NonconformanceDetailRefreshed()),
                ),
              NonconformanceDetailLoaded() => _Loaded(state: state),
            },
          ),
        ],
      ),
    );
  }
}

/// The page's own head: the way back, then the shared `AppPageHeader`. What the
/// record *is* — its number, its state, its severity — is the summary card's.
///
/// It lives above the state switch, so the loading, failed, missing and loaded
/// states are told apart by their body and never by a missing page head.
class _Header extends StatelessWidget {
  const _Header({this.showBack = true});

  /// False in the missing state, whose empty state carries the back control
  /// under the same [NonconformanceDetailScreen.backKey].
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: NonconformanceDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack) ...[
                TextButton.icon(
                  key: NonconformanceDetailScreen.backKey,
                  onPressed: () => context.go(Routes.nonConformances),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.nonconformanceDetailBack),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              AppPageHeader(title: l10n.nonconformanceTitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final NonconformanceDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final row = state.nonconformance;
    // Read here, in a build, rather than passed in from the route: a value
    // computed when the route first built would freeze the Account state as it
    // was before `/me` answered, and a holder of Quality authority would never
    // be offered the four decisions that authority gates (ADR-0035).
    final holdsQuality = holdsQualityAuthority(context, row.orgUnitId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: AppPageFrame(
              maxWidth: NonconformanceDetailScreen.maxWidth,
              // The box is the page's, before its inset: 1020 at a 1280px
              // window, over [AppBreakpoints.detailTwoColumn], so each pair of
              // sections sits side by side; the sections themselves are handed
              // 988. At 2x the page goes back to one column.
              child: LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >=
                      AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
                  return ListView(
                    key: NonconformanceDetailScreen.contentKey,
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    children: [
                      _SummaryCard(row: row),
                      const SizedBox(height: Spacing.md),
                      _SectionRows(
                        wide: wide,
                        sections: [
                          _FoundSection(row: row),
                          _ActionsSection(row: row, state: state, holdsQuality: holdsQuality),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      _SectionRows(
                        wide: wide,
                        sections: [
                          _ConcernsSection(
                            row: row,
                            notice: state.notice,
                            busy: state.isRaisingConcern || state.isLinkingConcern,
                          ),
                          _QuantityHistorySection(row: row),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      _SectionRows(
                        wide: wide,
                        sections: [
                          _DispositionsSection(row: row),
                          _CorrectionsSection(row: row),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      _SectionRows(
                        wide: wide,
                        sections: [
                          _PicturesSection(row: row),
                        ],
                      ),
                      if (state.mutationFailure != null)
                        Padding(
                          key: NonconformanceDetailScreen.failureKey,
                          padding: const EdgeInsets.only(top: Spacing.md),
                          child: NoticeText(
                            state.mutationFailure!,
                            style: AppTypography.dense(context)
                                ?.copyWith(color: palette.statusDanger),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two sections side by side when [wide], one above the other when not — the
/// shape `AppSectionGrid` draws, asked of the page's box rather than the list's
/// inner one (see `complaint_detail_screen.dart`'s copy for the arithmetic, and
/// `work_order_detail_screen.dart` for the precedent). A pair shares a height,
/// so a section whose text wraps does not leave its neighbour a short card.
class _SectionRows extends StatelessWidget {
  const _SectionRows({required this.wide, required this.sections});

  final bool wide;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: Spacing.md),
            sections[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var start = 0; start < sections.length; start += 2) ...[
          if (start > 0) const SizedBox(height: Spacing.md),
          if (start + 1 >= sections.length)
            sections[start]
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: sections[start]),
                  const SizedBox(width: Spacing.md),
                  Expanded(child: sections[start + 1]),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One label-and-value pair, for the summary's own `Wrap` of facts: the label
/// quiet and above, the value readable and below, so a long value wraps instead
/// of being clipped.
class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.floor(context)?.copyWith(color: palette.textMuted)),
        Text(value, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
      ],
    );
  }
}

/// The record's identity and the facts a reader takes in first: the number, the
/// state and the severity, what it is and where it was found.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      key: NonconformanceDetailScreen.summaryKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A `Wrap`: the number and its chips must not overflow at a narrow
            // width, and the record's own number is what a reader looks for.
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  row.issueNo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                ),
                StatusChip(
                  key: NonconformanceDetailScreen.statusKey,
                  label: row.statusLabel(l10n),
                  tone: row.statusTone,
                ),
                StatusChip(
                  key: NonconformanceDetailScreen.severityKey,
                  label: l10n.nonconformanceDetailSeverityChip(row.severityLabel(l10n)),
                  tone: _severityTone(row.severity),
                ),
                if (row.closedAt != null)
                  StatusChip(
                    key: NonconformanceDetailScreen.closedKey,
                    label: l10n.nonconformanceDetailFinishedAt('${row.closedAt}'),
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${row.productName} · ${row.defectCodeName}',
              style: AppTypography.dense(context)
                  ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.md,
              children: [
                _Fact(
                  label: l10n.nonconformanceDetailDetail,
                  value: row.description ?? l10n.commonNoneGiven,
                ),
                _Fact(label: l10n.commonProduct, value: '${row.productName} · ${row.productCode}'),
                _Fact(label: l10n.commonOrgUnit, value: row.orgUnitName),
                _Fact(
                  label: l10n.nonconformanceFormDetectionPoint,
                  value: detectionPointLabel(l10n, row.detectionPoint),
                ),
                _Fact(
                  label: l10n.nonconformanceDetailQuantityAffected,
                  key: NonconformanceDetailScreen.quantityKey,
                  value: '${_number(row.quantityAffected)} ${row.uomCode}',
                ),
                _Fact(
                  label: l10n.nonconformanceDetailFiledAgainst,
                  key: NonconformanceDetailScreen.filedKey,
                  value: row.filedAgainst,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // The slide-show switch belongs beside the record's own facts
            // rather than in a card of its own (issue #419): it is a fact about
            // this record, and a separate card pushed every section below it
            // down the page.
            SlideShowToggle(
              key: NonconformanceDetailScreen.slideShowKey,
              expanded: true,
              inSlideShow: row.inSlideShow,
              busy: context.select<NonconformanceDetailBloc, bool>((bloc) {
                final state = bloc.state;
                return state is NonconformanceDetailLoaded && state.isMutating;
              }),
              onChanged: (chosen) => context.read<NonconformanceDetailBloc>().add(
                    NonconformanceDetailSlideShowToggled(id: row.id, chosen: chosen),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What was found: the recorded facts about the defect itself.
class _FoundSection extends StatelessWidget {
  const _FoundSection({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDetailSection(
      title: l10n.nonconformancesFoundColumn,
      children: [
        Wrap(
          spacing: Spacing.xl,
          runSpacing: Spacing.md,
          children: [
            _Fact(
              label: l10n.commonDefectCode,
              value: l10n.nonconformanceDetailDefectCodeValue(
                row.defectCodeName,
                row.defectCodeCode,
                defectSeverityLabel(l10n, row.defectCodeDefaultSeverity),
              ),
            ),
            _Fact(
              label: l10n.commonAsset,
              value: row.assetName == null
                  ? l10n.commonNoneNamed
                  : '${row.assetName} · ${row.assetCode}',
            ),
            _Fact(label: l10n.nonconformanceDetailLotRef, value: row.lotRef ?? l10n.commonNotGiven),
            _Fact(
              label: l10n.nonconformanceFloorDetectedAt,
              value: row.detectedAt ?? l10n.commonNotRecorded,
            ),
            _Fact(
              label: l10n.nonconformanceDetailContainment,
              value: row.immediateContainment ?? l10n.commonNoneRecorded,
            ),
          ],
        ),
      ],
    );
  }
}

/// What can be done next: every transition this record offers, in one section so
/// the reader does not have to know which of six cards a given button lives in.
class _ActionsSection extends StatelessWidget {
  const _ActionsSection({required this.row, required this.state, required this.holdsQuality});

  final Nonconformance row;
  final NonconformanceDetailLoaded state;
  final bool holdsQuality;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDetailSection(
      title: l10n.nonconformanceDetailActionsSection,
      children: [
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: NonconformanceDetailScreen.increaseQuantityKey,
              onPressed: state.isMutating
                  ? null
                  : () => context.go('${Routes.nonConformances}/${row.id}/quantity'),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(l10n.nonconformanceIncreaseQuantity),
              style: NonconformanceDetailScreen.actionStyle,
            ),
            OutlinedButton.icon(
              key: NonconformanceDetailScreen.updateKey,
              onPressed: state.isMutating
                  ? null
                  : () => context.go('${Routes.nonConformances}/${row.id}/update'),
              icon: const Icon(Icons.build_outlined),
              label: Text(l10n.nonconformanceUpdate),
              style: NonconformanceDetailScreen.secondaryStyle,
            ),
            // A Disposition is offered wherever the record still has undecided
            // quantity — the server is the gate on the Grant reaching the Org
            // Unit, exactly as it is for recording.
            if (row.acceptsDisposition)
              FilledButton.icon(
                key: NonconformanceDetailScreen.dispositionKey,
                onPressed: state.isMutating
                    ? null
                    : () => context.go('${Routes.nonConformances}/${row.id}/disposition'),
                icon: const Icon(Icons.rule_outlined),
                label: Text(l10n.nonconformanceDisposition),
                style: NonconformanceDetailScreen.actionStyle,
              ),
            // The four decisions only a holder of Quality authority may take
            // (ADR-0035). None of them is offered to anyone else, so no request
            // is ever sent that the server would refuse for a reason the caller
            // could not see.
            if (holdsQuality) ...[
              if (row.acceptsConcession)
                FilledButton.icon(
                  key: NonconformanceDetailScreen.concessionKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/concession'),
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(l10n.nonconformanceConcession),
                  style: NonconformanceDetailScreen.actionStyle,
                ),
              if (row.canBeLowered)
                OutlinedButton.icon(
                  key: NonconformanceDetailScreen.lowerSeverityKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/lower-severity'),
                  icon: const Icon(Icons.arrow_downward),
                  label: Text(l10n.nonconformanceLowerSeverity),
                  style: NonconformanceDetailScreen.secondaryStyle,
                ),
              if (row.canBeReopened)
                OutlinedButton.icon(
                  key: NonconformanceDetailScreen.reopenKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/reopen'),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: Text(l10n.nonconformanceReopen),
                  style: NonconformanceDetailScreen.secondaryStyle,
                ),
              if (row.canBeCancelled)
                OutlinedButton.icon(
                  key: NonconformanceDetailScreen.cancelKey,
                  onPressed: state.isMutating
                      ? null
                      : () => context.go('${Routes.nonConformances}/${row.id}/cancel'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(l10n.nonconformanceCancel),
                  style: NonconformanceDetailScreen.secondaryStyle,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The quantity's own story (issue #206): sorting finds more than the first
/// count, every change is kept, and the affected quantity never shrinks.
class _QuantityHistorySection extends StatelessWidget {
  const _QuantityHistorySection({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return AppDetailSection(
      title: l10n.nonconformanceDetailQuantityHistory,
      children: [
        Text(
          l10n.nonconformanceDetailQuantityHistoryNote,
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
        if (row.quantityChanges.isEmpty)
          Text(
            l10n.nonconformanceDetailNoQuantityHistory,
            key: NonconformanceDetailScreen.noHistoryKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          )
        else
          Column(
            key: NonconformanceDetailScreen.quantityHistoryKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in row.quantityChanges)
                Padding(
                  key: NonconformanceDetailScreen.changeKey(change.id),
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: Text(
                    '${_number(change.previousQuantity)} → '
                    '${_number(change.newQuantity)} ${row.uomCode} · '
                    '${change.changedBy}'
                    '${change.changedAt == null ? '' : ' · ${change.changedAt}'}'
                    '${change.note == null ? '' : ' · ${change.note}'}',
                    style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// What has been decided about the product (issue #206): every Disposition in the
/// order it was decided, with the quantity it covers, who decided it and when —
/// and, for a Concession, the reference it was granted under.
///
/// The section is drawn even when nothing has been dispositioned, because "none
/// of this has been decided yet" is the state a reader of an open record needs,
/// said rather than left blank.
class _DispositionsSection extends StatelessWidget {
  const _DispositionsSection({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return AppDetailSection(
      title: l10n.nonconformanceDetailDispositions,
      children: [
        Text(
          l10n.nonconformanceDetailDispositionsNote,
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
        Text(
          l10n.nonconformanceDetailDispositioned(
            _number(row.quantityDispositioned),
            _number(row.quantityAffected),
            row.uomCode,
          ),
          style: AppTypography.dense(context)
              ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
        ),
        if (row.dispositions.isEmpty)
          Text(
            l10n.nonconformanceDetailNoDispositions,
            key: NonconformanceDetailScreen.noDispositionsKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          )
        else
          Column(
            key: NonconformanceDetailScreen.dispositionsKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final disposition in row.dispositions)
                Padding(
                  key: NonconformanceDetailScreen.dispositionRowKey(disposition.id),
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${disposition.label(l10n)} · ${_number(disposition.quantity)} '
                        '${disposition.uomCode}'
                        '${disposition.reworkMinutes > 0 ? ' · ${l10n.nonconformanceDetailReworkMinutes(disposition.reworkMinutes.round())}' : ''}',
                        style: AppTypography.dense(context)
                            ?.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        '${disposition.decidedBy}'
                        '${disposition.decidedAt == null ? '' : ' · ${disposition.decidedAt}'}'
                        '${disposition.reference == null ? '' : ' · ${disposition.reference}'}'
                        '${disposition.note == null ? '' : ' · ${disposition.note}'}',
                        style: AppTypography.floor(context)
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The corrections a holder of Quality authority has made to the record (issue
/// #206): a lowered severity, a reopen, a cancel — each with what changed, why,
/// and who decided it, which is what "readable back with who and when" asks a
/// client to show.
class _CorrectionsSection extends StatelessWidget {
  const _CorrectionsSection({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return AppDetailSection(
      title: l10n.nonconformanceDetailCorrections,
      children: [
        Text(
          l10n.nonconformanceDetailCorrectionsNote,
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
        if (row.corrections.isEmpty)
          Text(
            l10n.nonconformanceDetailNoCorrections,
            key: NonconformanceDetailScreen.noCorrectionsKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          )
        else
          Column(
            key: NonconformanceDetailScreen.correctionsKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final correction in row.corrections)
                Padding(
                  key: NonconformanceDetailScreen.correctionRowKey(correction.id),
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        correction.summary(l10n),
                        style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        '${namedOrUnknown(l10n, correction.correctedByAccountDisplayName)}'
                        '${correction.correctedAt == null ? '' : ' · ${correction.correctedAt}'}'
                        '${correction.note == null ? '' : ' · ${correction.note}'}',
                        style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The Concerns this Non-conformance is evidence behind (issue #208) — the one
/// raised from it first, then any further occurrence of the same problem gathered
/// to the same Concern. Each row is a link to the Concern's own address, which is
/// the half of "each record shows the other" that lives on this Screen.
///
/// The section is drawn even when there is nothing, because "nobody is answering
/// this yet" is the state a reader of a Non-conformance needs to see, and the two
/// controls that change it sit exactly there: raising a Concern from the record,
/// and linking it to one that already exists. Both are writes to the action log,
/// and the server is the gate on either — a caller who cannot see the Site gets a
/// sentence back rather than a hidden button, which is the same rule every other
/// control on this Screen follows.
///
/// It sits immediately under the summary card in this pass (issue #390): the CAPA
/// trail is what the record is read for, and it used to be the last section of a
/// 700-line page.
class _ConcernsSection extends StatelessWidget {
  const _ConcernsSection({required this.row, required this.busy, this.notice});

  final Nonconformance row;

  /// One of the two writes is in flight: both controls go quiet together, so a
  /// second one cannot be started against a record mid-change.
  final bool busy;

  /// What the last raise or link had to say for itself, from the Bloc's own
  /// state — the dialog that asked has closed by the time it is worth reading.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final concerns = row.concerns;

    return AppDetailSection(
      key: NonconformanceDetailScreen.concernsKey,
      title: l10n.nonconformanceDetailCause,
      children: [
        Text(
          l10n.nonconformanceDetailCauseNote,
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
        if (notice != null)
          NoticeText(
            key: NonconformanceDetailScreen.concernNoticeKey,
            notice!,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          ),
        if (concerns.isEmpty)
          Text(
            key: NonconformanceDetailScreen.noConcernsKey,
            l10n.nonconformanceDetailNoConcerns,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final concern in concerns)
                // The row's own `Key`, so a test finds it by the Concern's id
                // rather than by its text.
                Padding(
                  key: NonconformanceDetailScreen.concernRowKey(concern.id),
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Material(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('${Routes.actions}/${concern.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    concern.title,
                                    style: AppTypography.dense(context)
                                        ?.copyWith(color: palette.textPrimary),
                                  ),
                                  const SizedBox(height: Spacing.xxs),
                                  Text(
                                    [
                                      concern.actionNo,
                                      concern.typeLabel,
                                      // The one it was raised from, said rather
                                      // than implied: the reader of a
                                      // Non-conformance wants to know which
                                      // Concern this occurrence started.
                                      if (concern.isSource) l10n.nonconformanceDetailRaisedFrom,
                                      if (concern.ownerName != null) concern.ownerName!,
                                      if (concern.isOverdue) l10n.nonconformanceDetailOverdue,
                                    ].join(' · '),
                                    style: AppTypography.floor(context)
                                        ?.copyWith(color: palette.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            StatusChip(
                              label: concern.statusLabel(l10n),
                              tone: concern.statusTone,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: NonconformanceDetailScreen.raiseConcernKey,
              onPressed: busy
                  ? null
                  : () => context.go('${Routes.nonConformances}/${row.id}/raise-concern'),
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(l10n.nonconformanceRaiseConcern),
              style: NonconformanceDetailScreen.actionStyle,
            ),
            OutlinedButton.icon(
              key: NonconformanceDetailScreen.linkConcernKey,
              onPressed: busy
                  ? null
                  : () => context.go('${Routes.nonConformances}/${row.id}/link-concern'),
              icon: const Icon(Icons.link),
              label: Text(l10n.nonconformanceLinkConcern),
              style: NonconformanceDetailScreen.secondaryStyle,
            ),
          ],
        ),
      ],
    );
  }
}

/// A severity's meaning in the shared status vocabulary (issue #168).
StatusTone _severityTone(String severity) => switch (severity) {
      'critical' => StatusTone.danger,
      'major' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

/// A quantity without a trailing `.0` — 12, not 12.0.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

/// The record's pictures (issue #419) — the shared section with a Bloc of its
/// own for this record.
class _PicturesSection extends StatelessWidget {
  const _PicturesSection({required this.row});

  final Nonconformance row;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<IssueImagesBloc>(
      create: (context) => IssueImagesBloc(
        qualityApi: context.read<QualityApi>(),
        authGateway: context.read<AuthGateway>(),
        kind: IssueKind.nonconformance,
        issueId: row.id,
      )..add(const IssueImagesStarted()),
      child: Builder(
        builder: (context) => IssueImagesSection(
          bloc: context.read<IssueImagesBloc>(),
          canWrite: true,
          picker: context.read<QualityPhotoPicker>(),
        ),
      ),
    );
  }
}
