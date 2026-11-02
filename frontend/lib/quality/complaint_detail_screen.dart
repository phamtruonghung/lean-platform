/// One customer complaint (issue #214): what the customer said, which Product
/// it is about, who is answering it, and the Non-conformance that controls the
/// product they complained about.
///
/// The Screen is built around the two questions a reader opens a complaint
/// with. **Is the product under control?** — either the Non-conformance that
/// controls it is named, with a door to it, or the two ways to make one are
/// offered: record a Non-conformance from this complaint (`detection_point =
/// customer`, the complaint's own Product and Defect code) or link one that
/// already exists. **Has the customer been answered?** — the response the
/// complaint was closed with is shown, or the door to closing it is.
///
/// Nothing here is gated on a role: the server is the real gate on every write
/// (an edit Grant reaching the complaint's Org Unit), and hiding a control
/// would gate an address that answers a clean refusal with a sentence the
/// reader can act on. The refusal is rendered beside the action that made it.
///
/// **The page answers "what, whose, how bad, what next" above the fold (issue
/// #390).** A summary card carries the number, the tone chips, who complained
/// about what, the complaint in the customer's own words, and the eight facts a
/// reader asks for first; the two sections below it are the two decisions — the
/// product's control and the response — and they sit side by side from
/// [AppBreakpoints.detailTwoColumn] of box, which is why this page names
/// [maxWidth] 1040: at a 1280px window the Shell leaves a page box of 1020, and
/// a page left on the default 900 could never reach the breakpoint (design-
/// language §10). The control that ties the complaint to its Non-conformance is
/// inside that first section rather than at the foot of the page, so the CAPA
/// trail is one visible step from the record rather than a hunt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'complaint_detail_bloc.dart';
import 'customer_complaint.dart';
import 'issue_image.dart';
import 'issue_images_bloc.dart';
import 'issue_images_section.dart';
import 'quality_api.dart';
import 'quality_photo_picker.dart';
import 'slide_show_toggle.dart';

class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final String complaintId;

  /// The page names 1040 so a box of 1000 is reachable: at a 1280px window the
  /// Shell leaves 1020, and [AppBreakpoints.detailTwoColumn] is compared with
  /// that box. Under the old 900 it was unreachable at any window.
  static const double maxWidth = 1040;

  static const ValueKey<String> loadedKey = ValueKey<String>('complaint-detail-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('complaint-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('complaint-detail-retry');
  static const ValueKey<String> backKey = ValueKey<String>('complaint-detail-back');

  /// The slide-show switch on this record (issue #418).
  static const ValueKey<String> slideShowKey = ValueKey<String>('complaint-detail-slide-show');
  static const ValueKey<String> statusKey = ValueKey<String>('complaint-detail-status');
  static const ValueKey<String> overdueKey = ValueKey<String>('complaint-detail-overdue');
  static const ValueKey<String> failureKey = ValueKey<String>('complaint-detail-failure');
  static const ValueKey<String> respondKey = ValueKey<String>('complaint-detail-respond');
  static const ValueKey<String> recordKey = ValueKey<String>('complaint-detail-record');
  static const ValueKey<String> linkKey = ValueKey<String>('complaint-detail-link');
  static const ValueKey<String> responseNoteKey = ValueKey<String>('complaint-detail-response');
  static const ValueKey<String> noControlKey = ValueKey<String>('complaint-detail-no-control');
  static const ValueKey<String> summaryKey = ValueKey<String>('complaint-detail-summary');
  static ValueKey<String> controlledKey(String issueNo) =>
      ValueKey<String>('complaint-detail-controlled-$issueNo');

  /// The two affordances are 44 tall wherever they are laid out.
  static final ButtonStyle actionStyle =
      FilledButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));
  static final ButtonStyle secondaryStyle =
      OutlinedButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ComplaintDetailBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          Expanded(
            child: switch (state) {
              ComplaintDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              ComplaintDetailUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: 'That complaint could not be read',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context
                      .read<ComplaintDetailBloc>()
                      .add(ComplaintDetailStarted(complaintId)),
                ),
              ComplaintDetailLoaded(complaint: final complaint) => _Loaded(
                  complaint: complaint,
                  failure: state.mutationFailure,
                ),
            },
          ),
        ],
      ),
    );
  }
}

/// The page's own head: the way back, then the shared `AppPageHeader`. What the
/// complaint *is* — its number, its Customer and Product, its state — is the
/// summary card's, below, once it has loaded.
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `go`, never `maybePop` — every navigation in this Platform
              // replaces the location rather than pushing a page, so a Back
              // button is an address. The label names the Destination.
              TextButton.icon(
                key: ComplaintDetailScreen.backKey,
                onPressed: () => context.go(Routes.complaints),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Customer complaints'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              const AppPageHeader(title: 'Customer complaint'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.complaint, this.failure});

  final CustomerComplaint complaint;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintDetailScreen.maxWidth,
        // The box is the page's, before its `Spacing.lg` inset: at a 1280px
        // window that is 1020, over [AppBreakpoints.detailTwoColumn]'s 1000, so
        // the two decisions sit side by side; the sections themselves are handed
        // 988. It is the box, not the window, and it is compared at the reader's
        // text scale, so at 2x the page goes back to one column.
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >=
                AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
            return ListView(
              key: ComplaintDetailScreen.loadedKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                _SummaryCard(complaint: complaint),
                const SizedBox(height: Spacing.md),
                _SectionRows(
                  wide: wide,
                  sections: [
                    _ControlSection(complaint: complaint),
                    _ResponseSection(complaint: complaint),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                _SectionRows(
                  wide: wide,
                  sections: [
                    _PicturesSection(complaint: complaint),
                  ],
                ),
                if (failure != null)
                  Padding(
                    key: ComplaintDetailScreen.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      failure!,
                      style: AppTypography.dense(context)
                          ?.copyWith(color: AppColors.of(context).statusDanger),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Two sections side by side when [wide], one above the other when not.
///
/// This is the shape `AppSectionGrid` draws, asked of the *page's* box rather
/// than of the list's inner one. At a 1280px window the page is handed 1020 and
/// the list then insets it to 988, so a grid measuring its own box answers "one
/// column" on the widest window this app sees — the trap
/// `work_order_detail_screen.dart` avoids the same way, and the reason
/// `docs/design-language.md` says the one-or-two-column choice is made on the
/// page's box before its inset.
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
    // `IntrinsicHeight`, so a section whose text wraps does not leave its
    // neighbour a short card floating beside it.
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

/// The complaint's own fields, first — the reader's "what, whose, how bad". The
/// number and the chips lead, because the number is what the record is called
/// everywhere it is quoted, and the chips are what state it is in.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final row = complaint;

    Widget fact(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTypography.floor(context)?.copyWith(color: palette.textMuted)),
            Text(value, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
          ],
        );

    return Card(
      key: ComplaintDetailScreen.summaryKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        row.complaintNo,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                      ),
                      StatusChip(
                        key: ComplaintDetailScreen.statusKey,
                        label: row.statusLabel,
                        tone: row.statusTone,
                      ),
                      if (row.isOverdue)
                        StatusChip(
                          key: ComplaintDetailScreen.overdueKey,
                          label: 'Past due',
                          tone: StatusTone.danger,
                        ),
                      if (row.isWarranty)
                        const StatusChip(label: 'Warranty claim', tone: StatusTone.info),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${row.customerName} · ${row.productName}',
              style: AppTypography.dense(context)
                  ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: Spacing.xxs),
            Text(row.description, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.md,
              children: [
                fact('Customer', '${row.customerName} · ${row.customerCode}'),
                fact('Product', '${row.productName} · ${row.productCode}'),
                fact(
                  'Defect code',
                  row.defectCodeName == null
                      ? 'Not known yet'
                      : '${row.defectCodeName} · ${row.defectCodeCode}',
                ),
                fact('Quantity', row.quantityLabel),
                fact('Filed at', row.orgUnitName),
                fact('Received', row.receivedAt),
                fact('Response', row.dueLabel),
                fact('Type', row.typeLabel),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // The slide-show switch, beside the record's own facts (issue #418)
            // — see `nonconformance_detail_screen.dart` for the same choice.
            SlideShowToggle(
              key: ComplaintDetailScreen.slideShowKey,
              expanded: true,
              inSlideShow: row.inSlideShow,
              busy: context.select<ComplaintDetailBloc, bool>((bloc) {
                final state = bloc.state;
                return state is ComplaintDetailLoaded && state.isMutating;
              }),
              onChanged: (chosen) => context.read<ComplaintDetailBloc>().add(
                    ComplaintSlideShowToggled(id: row.id, chosen: chosen),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Is the product under control?" — the Non-conformance that controls it, with
/// a door to it, or the two ways to make one.
class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final record = complaint.nonconformance;

    return AppDetailSection(
      title: 'The product this is about',
      children: [
        if (record == null) ...[
          Text(
            'Nothing controls the product this customer complained about yet. Record a '
            'Non-conformance from this complaint, or link one that already exists for the '
            'same Product.',
            key: ComplaintDetailScreen.noControlKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.sm,
            children: [
              FilledButton.icon(
                key: ComplaintDetailScreen.recordKey,
                onPressed: complaint.isFinished
                    ? null
                    : () => context.go('${Routes.complaints}/${complaint.id}/nonconformance'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Record a Non-conformance'),
                style: ComplaintDetailScreen.actionStyle,
              ),
              OutlinedButton.icon(
                key: ComplaintDetailScreen.linkKey,
                onPressed: complaint.isFinished
                    ? null
                    : () => context.go('${Routes.complaints}/${complaint.id}/link'),
                icon: const Icon(Icons.link_outlined),
                label: const Text('Link one that exists'),
                style: ComplaintDetailScreen.secondaryStyle,
              ),
            ],
          ),
        ] else ...[
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                record.issueNo,
                key: ComplaintDetailScreen.controlledKey(record.issueNo),
                style: AppTypography.dense(context)
                    ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w500),
              ),
              const StatusChip(label: 'Open record', tone: StatusTone.info),
            ],
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            record.detectionPoint == 'customer'
                ? 'Found by the customer, so this complaint is where it started.'
                : 'Recorded at ${record.detectionPoint ?? 'another detection point'}, and '
                    'linked to this complaint.',
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: () => context.go('${Routes.nonConformances}/${record.id}'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open the Non-conformance'),
            style: ComplaintDetailScreen.secondaryStyle,
          ),
        ],
      ],
    );
  }
}

/// "Has the customer been answered?" — the response the complaint was closed
/// with, or the door to closing it.
class _ResponseSection extends StatelessWidget {
  const _ResponseSection({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);

    return AppDetailSection(
      title: 'The response',
      children: [
        if (complaint.responseNote != null) ...[
          Text(
            complaint.responseNote!,
            key: ComplaintDetailScreen.responseNoteKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          ),
          if (complaint.closedAt != null) ...[
            const SizedBox(height: Spacing.xxs),
            Text(
              'Closed ${complaint.closedAt}',
              style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
            ),
          ],
        ] else ...[
          Text(
            'Nothing has been said back to this customer yet.',
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton.icon(
            key: ComplaintDetailScreen.respondKey,
            onPressed: complaint.isFinished
                ? null
                : () => context.go('${Routes.complaints}/${complaint.id}/respond'),
            icon: const Icon(Icons.reply_outlined),
            label: const Text('Close with the response'),
            style: ComplaintDetailScreen.actionStyle,
          ),
        ],
      ],
    );
  }
}

/// The complaint's pictures (issue #418): the section, with a Bloc of its own
/// per record — the same one the Non-conformance detail Screen uses.
class _PicturesSection extends StatelessWidget {
  const _PicturesSection({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<IssueImagesBloc>(
      create: (context) => IssueImagesBloc(
        qualityApi: context.read<QualityApi>(),
        authGateway: context.read<AuthGateway>(),
        kind: IssueKind.complaint,
        issueId: complaint.id,
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
