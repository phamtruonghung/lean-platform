/// The attendance-to-confirm worklist (issue #250): the past shift instances
/// whose sheet is missing or unconfirmed, oldest first, restricted to the
/// Org Units this caller's own edit Grants reach (or every Site's list, for
/// an administrator) — "the sheets it could confirm" (issue #250's own
/// wording). Under #247 decision 9, a single unconfirmed shift makes the
/// injury rates `no_data`, so this Screen is where that gap actually gets
/// closed.
///
/// **Address, deliberately nested under `/attendance` rather than a new
/// sidebar Destination.** Issue #250 asks for "its own address under the
/// People Destination group" — `/attendance/to-confirm` (`Routes.attendance`,
/// `router.dart`) is exactly that: its own bookmarkable address, filed under
/// the same Attendance Destination the picker (`/attendance`) already
/// occupies, per
/// CONTEXT.md's own Screen/Destination distinction ("a Screen has its own
/// address... a Destination is an entry in the Shell's sidebar"). Reached
/// from a button on `AttendancePickerScreen` rather than a second sidebar
/// entry, so this ticket adds no new Destination and therefore reopens
/// none of the Shell's own full-app goldens (`frontend/test/GOLDENS.md`
/// goldens only the Shell and the Work orders Screen; neither reads the
/// Destination list itself, but a new Destination would still shift
/// `shell_test.dart`'s own sidebar assertions and is exactly the kind of
/// change GOLDENS.md asks to not make quietly).
///
/// Org Unit browsing reuses `OrgUnitPickerBloc`, the same Bloc
/// `AttendancePickerScreen`'s own `_OrgUnitBrowser` already drives for a
/// single-select choice over the same tree.
///
/// **A decision row, and the filters under the title's own rule** (issue #393,
/// `docs/design-language.md` sections 1, 6, 8 and 12). The two filters and the
/// window now live in `AppPageHeader.below`, so the title, the filters and the
/// first row share one left edge and the readers' eye has one line to follow
/// down the page; before this pass the filters were three free-standing rows
/// under the description. Each entry is a row of the catalogue rather than a
/// `ListTile`: the shift and its production day on the first line, the Org Unit
/// and Site on the second, the sheet's own state as a `StatusChip` (Not opened
/// yet reads `danger` — there is no record at all — where Started, not yet
/// confirmed reads `warning`), and the act at the row's end. Below
/// `AppBreakpoints.toolbarWrap` of box, or at a text size that makes the same
/// box that narrow, the chip and the act drop under the shift name rather than
/// squeezing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'attendance.dart';
import 'attendance_to_confirm_bloc.dart';
import 'org_unit_picker_bloc.dart';

/// The height a `SkeletonList` is given when it stands in for a list inside a
/// page that is itself scrolling: the placeholder scrolls its own rows, so it
/// needs a bounded box where the page hands out an unbounded one.
const double _skeletonHeight = 288;

class AttendanceToConfirmScreen extends StatelessWidget {
  const AttendanceToConfirmScreen({super.key});

  static const double maxWidth = 720;

  static const ValueKey<String> failureKey = ValueKey<String>('attendance-to-confirm-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('attendance-to-confirm-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-to-confirm-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('attendance-to-confirm-loading');
  static const ValueKey<String> catalogueKey = ValueKey<String>('attendance-to-confirm-entries');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('attendance-to-confirm-org-unit-chosen');
  static const ValueKey<String> orgUnitClearKey = ValueKey<String>('attendance-to-confirm-org-unit-clear');
  static const ValueKey<String> orgUnitBrowseToggleKey = ValueKey<String>('attendance-to-confirm-org-unit-toggle');
  static const ValueKey<String> fromFieldKey = ValueKey<String>('attendance-to-confirm-from');
  static const ValueKey<String> toFieldKey = ValueKey<String>('attendance-to-confirm-to');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('attendance-to-confirm-org-unit-$id');
  static ValueKey<String> entryKey(String shiftInstanceId) =>
      ValueKey<String>('attendance-to-confirm-entry-$shiftInstanceId');
  static ValueKey<String> openKey(String shiftInstanceId) =>
      ValueKey<String>('attendance-to-confirm-open-$shiftInstanceId');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendanceToConfirmBloc>(
          create: (_) => AttendanceToConfirmBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const AttendanceToConfirmStarted()),
        ),
        BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
        ),
      ],
      child: const _WorklistBody(),
    );
  }
}

class _WorklistBody extends StatefulWidget {
  const _WorklistBody();

  @override
  State<_WorklistBody> createState() => _WorklistBodyState();
}

class _WorklistBodyState extends State<_WorklistBody> {
  bool _browsingOrgUnit = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttendanceToConfirmBloc>().state;
    final bloc = context.read<AttendanceToConfirmBloc>();

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: AttendanceToConfirmScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(
                title: 'Attendance to confirm',
                description:
                    "Past shifts whose sheet is missing or hasn't been confirmed yet, "
                    'oldest first, across the Org Units you can confirm one at.',
                below: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrgUnitFilter(
                      state: state,
                      bloc: bloc,
                      browsing: _browsingOrgUnit,
                      onToggleBrowse: () => setState(() => _browsingOrgUnit = !_browsingOrgUnit),
                      onCleared: () => setState(() => _browsingOrgUnit = false),
                    ),
                    const SizedBox(height: Spacing.md),
                    _WindowFields(state: state, bloc: bloc),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                PlatformFailureState(
                  key: AttendanceToConfirmScreen.failureKey,
                  title: 'The worklist could not be read',
                  message: state.failure!,
                  retryKey: AttendanceToConfirmScreen.retryKey,
                  // The same read again: `_reload` reads the Org Unit and the
                  // window off the state, so a retry asks for nothing the
                  // caller has not already asked for.
                  onRetry: () => bloc.add(const AttendanceToConfirmStarted()),
                )
              else if (state.isLoading)
                // Bounded, because `SkeletonList` scrolls its own rows and this
                // page's ListView hands out no height of its own.
                SizedBox(
                  height: _skeletonHeight,
                  child: const SkeletonList(
                    key: AttendanceToConfirmScreen.loadingKey,
                    rows: 4,
                    maxWidth: AttendanceToConfirmScreen.maxWidth,
                  ),
                )
              else if (state.entries.isEmpty)
                PlatformEmptyState.noneExist(
                  key: AttendanceToConfirmScreen.emptyKey,
                  title: 'Nothing to confirm here.',
                  message: 'Every past shift you can confirm has a confirmed sheet.',
                  icon: Icons.fact_check_outlined,
                )
              else
                AppListCard(
                  key: AttendanceToConfirmScreen.catalogueKey,
                  rows: [
                    for (final entry in state.entries) _EntryRow(entry: entry),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two bounds of the window. One row when the box can hold them side by
/// side, stacked when it cannot — read from the box, and from the box scaled by
/// the reader's text size (`AppBreakpoints.effective`), never from the window.
class _WindowFields extends StatelessWidget {
  const _WindowFields({required this.state, required this.bloc});

  final AttendanceToConfirmState state;
  final AttendanceToConfirmBloc bloc;

  @override
  Widget build(BuildContext context) {
    final from = AppDateField(
      key: AttendanceToConfirmScreen.fromFieldKey,
      name: 'attendance-to-confirm-from',
      label: 'From',
      value: state.from,
      optional: true,
      onChanged: (value) => bloc.add(AttendanceToConfirmFromChosen(value)),
    );
    final to = AppDateField(
      key: AttendanceToConfirmScreen.toFieldKey,
      name: 'attendance-to-confirm-to',
      label: 'To',
      value: state.to,
      optional: true,
      onChanged: (value) => bloc.add(AttendanceToConfirmToChosen(value)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < AppBreakpoints.effective(context, AppBreakpoints.toolbarWrap)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [from, const SizedBox(height: Spacing.md), to],
          );
        }
        return Row(
          children: [
            Expanded(child: from),
            const SizedBox(width: Spacing.md),
            Expanded(child: to),
          ],
        );
      },
    );
  }
}

class _OrgUnitFilter extends StatelessWidget {
  const _OrgUnitFilter({
    required this.state,
    required this.bloc,
    required this.browsing,
    required this.onToggleBrowse,
    required this.onCleared,
  });

  final AttendanceToConfirmState state;
  final AttendanceToConfirmBloc bloc;
  final bool browsing;
  final VoidCallback onToggleBrowse;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    if (state.orgUnitId != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Org Unit: ${state.orgUnitName}',
              key: AttendanceToConfirmScreen.orgUnitChosenKey,
              style: AppTypography.dense(context)?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: AppTouchTarget.min,
            height: AppTouchTarget.min,
            child: IconButton(
              key: AttendanceToConfirmScreen.orgUnitClearKey,
              tooltip: 'Clear',
              iconSize: 18,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close),
              onPressed: () {
                bloc.add(const AttendanceToConfirmOrgUnitCleared());
                onCleared();
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: AttendanceToConfirmScreen.orgUnitBrowseToggleKey,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouchTarget.min)),
            onPressed: onToggleBrowse,
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text(browsing ? 'Hide Org Units' : 'Filter by Org Unit'),
          ),
        ),
        if (browsing) ...[
          const SizedBox(height: Spacing.sm),
          _OrgUnitBrowser(bloc: bloc),
        ],
      ],
    );
  }
}

class _OrgUnitBrowser extends StatelessWidget {
  const _OrgUnitBrowser({required this.bloc});

  final AttendanceToConfirmBloc bloc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final pickerBloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = Text(state.sitesFailure ?? 'The Sites are unavailable.');
    } else if (state.rootsFailure != null) {
      body = Text(state.rootsFailure!);
    } else if (state.sites.isEmpty) {
      body = const Text('There are no Sites to browse yet.');
    } else if (state.rows.isEmpty) {
      body = const Text('Nothing to browse in this Site.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in state.rows) _OrgUnitRow(row: row, bloc: bloc)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.sites.length > 1)
          DropdownButtonFormField<String>(
            initialValue: state.siteId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Site'),
            items: [
              for (final site in state.sites) DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
            ],
            onChanged: (siteId) {
              if (siteId != null) pickerBloc.add(OrgUnitPickerSiteSelected(siteId));
            },
          ),
        const SizedBox(height: Spacing.sm),
        DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
      ],
    );
  }
}

class _OrgUnitRow extends StatelessWidget {
  const _OrgUnitRow({required this.row, required this.bloc});

  final OrgUnitRow row;
  final AttendanceToConfirmBloc bloc;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(left: row.depth * Spacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
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
                      tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                      onPressed: () => context.read<OrgUnitPickerBloc>().add(
                            row.isExpanded
                                ? OrgUnitPickerCollapsed(row.node.id)
                                : OrgUnitPickerExpanded(row.node.id),
                          ),
                      icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                    ),
            ),
            Expanded(
              child: InkWell(
                key: AttendanceToConfirmScreen.orgUnitRowKey(row.node.id),
                onTap: () => bloc.add(
                  AttendanceToConfirmOrgUnitChosen(orgUnitId: row.node.id, orgUnitName: row.node.name),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Text(
                    row.node.name,
                    style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shift that needs a decision: the shift instance and its production day,
/// what it belongs to, what state its sheet is in, and the act — the sheet's own
/// address, which is also what tapping the row does.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AttendanceToConfirmEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final missing = entry.sheetState == 'missing';
    final label = attendanceSheetStateLabel(entry.sheetState);
    void open() => context.go('${Routes.attendance}/${entry.shiftInstanceId}');

    final state = StatusChip(
      label: label,
      // Not opened yet has no record behind it at all, which is the worse of
      // the two gaps the worklist exists to close; both want a decision, so
      // both stay inside the two "wants a decision" tones of the ladder.
      tone: missing ? StatusTone.danger : StatusTone.warning,
    );
    final act = OutlinedButton(
      key: AttendanceToConfirmScreen.openKey(entry.shiftInstanceId),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouchTarget.min)),
      onPressed: open,
      child: const Text('Open sheet'),
    );
    final record = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${entry.shiftDefinitionName} · ${entry.productionDate}',
          style: AppTypography.dense(context)?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.xxs),
        Text(
          '${entry.orgUnitName} (${entry.siteName})',
          style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
        ),
      ],
    );

    return InkWell(
      key: AttendanceToConfirmScreen.entryKey(entry.shiftInstanceId),
      onTap: open,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          child: LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < AppBreakpoints.effective(context, AppBreakpoints.toolbarWrap)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    record,
                    const SizedBox(height: Spacing.sm),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [state, act],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: record),
                  const SizedBox(width: Spacing.md),
                  state,
                  const SizedBox(width: Spacing.sm),
                  act,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
