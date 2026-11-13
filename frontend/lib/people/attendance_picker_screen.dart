/// The Attendance Destination's own landing Screen (issue #249): choose an
/// Org Unit and a production day, then open the sheet for one of that day's
/// shift instances. There is no shift calendar Screen to link a sheet from
/// yet — #250, the "attendance to confirm" worklist reached via the button
/// this Screen now carries, is what does that job properly — this picker
/// exists so the sheet Screen (`/attendance/:shiftInstanceId`) has a real
/// address to be reached from, per issue #249's own "at its own address
/// under the People Destination group" criterion.
///
/// Org Unit browsing reuses `OrgUnitPickerBloc`, the same Bloc
/// `DirectoryOrgUnitFilterDialog` already drives for a single-select choice
/// over the same tree — that file's own header explains why the full
/// `OrgUnitPicker` widget (a Grant editor) is not reused instead.
///
/// **One page rhythm, and the picker is read in one column** (issue #393,
/// `docs/design-language.md` sections 1, 2 and 5). The title row is the shared
/// `AppPageHeader` with the worklist link as its own action, so the title, the
/// description, the browser and the shifts below all start at the same left
/// edge — before this pass the title was a `Wrap` of its own with its button
/// beside it, and the description began 8px under it rather than at the
/// header's own baseline. The browser and the day choice sit in one card
/// (`AppListCard`'s hairline between rows is not wanted here: these are two
/// controls, not a list of records), and each shift below is a row of a
/// catalogue whose trailing cell is its state chip.
///
/// **A shift's state is a chip, not a second line of prose.** The three
/// sentences — Not opened yet, Started, not yet confirmed, Confirmed — are
/// unchanged; they moved from a `ListTile` subtitle to the row's trailing
/// `StatusChip`, which paints the meaning as well as saying it. A `ListTile`
/// was also the wrong row for this page: 56 high and padded to its own spec,
/// where the row here is [AppTouchTarget.min] and shares the card's own edges.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
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
import 'attendance_picker_bloc.dart';
import 'org_unit_picker_bloc.dart';

/// The height a `SkeletonList` is given when it stands in for a list inside a
/// page that is itself scrolling: the placeholder scrolls its own rows, so it
/// needs a bounded box where the page hands out an unbounded one.
const double _skeletonHeight = 288;

class AttendancePickerScreen extends StatelessWidget {
  const AttendancePickerScreen({super.key});

  static const double maxWidth = 640;

  static const ValueKey<String> dateFieldKey = ValueKey<String>('attendance-picker-date');
  static const ValueKey<String> toConfirmLinkKey = ValueKey<String>('attendance-picker-to-confirm-link');
  static const ValueKey<String> orgUnitChosenKey = ValueKey<String>('attendance-picker-org-unit-chosen');
  static const ValueKey<String> emptyKey = ValueKey<String>('attendance-picker-empty');
  static const ValueKey<String> failureKey = ValueKey<String>('attendance-picker-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('attendance-picker-retry');
  static const ValueKey<String> catalogueKey = ValueKey<String>('attendance-picker-shifts');
  static ValueKey<String> orgUnitRowKey(String id) => ValueKey<String>('attendance-picker-org-unit-$id');
  static ValueKey<String> shiftRowKey(String id) => ValueKey<String>('attendance-picker-shift-$id');

  @override
  Widget build(BuildContext context) {
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendancePickerBloc>(
          create: (_) => AttendancePickerBloc(peopleApi: peopleApi, authGateway: authGateway),
        ),
        BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
        ),
      ],
      child: const _PickerBody(),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AttendancePickerBloc>().state;

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: AttendancePickerScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(
                title: l10n.navAttendance,
                description: l10n.attendancePickerChooseAnOrgUnitAndAProduction,
                actions: [
                  // The worklist (issue #250): every past shift this caller
                  // could confirm whose sheet is missing or unconfirmed —
                  // its own address nested under this one, reached from
                  // here rather than from a second sidebar entry (see
                  // `attendance_to_confirm_screen.dart`'s own header).
                  OutlinedButton.icon(
                    key: AttendancePickerScreen.toConfirmLinkKey,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppTouchTarget.min),
                    ),
                    onPressed: () => context.go('${Routes.attendance}/to-confirm'),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(l10n.titleAttendanceToConfirm),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              if (state.orgUnitName == null)
                const _OrgUnitBrowser()
              else
                _ChosenOrgUnit(name: state.orgUnitName!),
              const SizedBox(height: Spacing.md),
              AppDateField(
                key: AttendancePickerScreen.dateFieldKey,
                name: 'attendance-picker-date',
                label: l10n.attendancePickerProductionDay,
                value: state.date,
                onChanged: (value) {
                  if (value != null) {
                    context.read<AttendancePickerBloc>().add(AttendancePickerDateChosen(value));
                  }
                },
              ),
              const SizedBox(height: Spacing.lg),
              if (state.failure != null)
                PlatformFailureState(
                  key: AttendancePickerScreen.failureKey,
                  title: l10n.attendancePickerTheShiftsCouldNotBeRead,
                  message: state.failure!,
                  // The same read again, with the Org Unit and day the caller
                  // already chose: `_reload` reads both off the state, so this
                  // asks for nothing they did not already ask for.
                  retryKey: AttendancePickerScreen.retryKey,
                  onRetry: () => context
                      .read<AttendancePickerBloc>()
                      .add(AttendancePickerDateChosen(state.date!)),
                )
              else if (state.isLoading)
                // `SkeletonList` scrolls its own rows, so inside this page's
                // ListView it is given a bounded height rather than an
                // unbounded one — a ghost of the list's own length, then the
                // real rows in the same place.
                SizedBox(
                  height: _skeletonHeight,
                  child: const SkeletonList(rows: 3, maxWidth: AttendancePickerScreen.maxWidth),
                )
              else if (state.orgUnitId != null && state.date != null && state.shiftInstances.isEmpty)
                PlatformEmptyState.noneExist(
                  key: AttendancePickerScreen.emptyKey,
                  title: l10n.attendancePickerNoShiftsAreScheduledHereOnThat,
                  message: l10n.attendancePickerChooseAnotherProductionDayOrAnotherOrg,
                  icon: Icons.event_busy_outlined,
                )
              else
                AppListCard(
                  key: AttendancePickerScreen.catalogueKey,
                  rows: [
                    for (final shiftInstance in state.shiftInstances)
                      _ShiftRow(shiftInstance: shiftInstance),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Org Unit a caller has already chosen, in the same card the browser
/// would have drawn — so choosing one does not make the page jump by a card.
class _ChosenOrgUnit extends StatelessWidget {
  const _ChosenOrgUnit({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.md),
        child: Row(
          children: [
            Icon(Icons.account_tree_outlined, size: 18, color: palette.textMuted),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                name,
                key: AttendancePickerScreen.orgUnitChosenKey,
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shift instance: what it was, when, and whether its sheet is missing,
/// started or confirmed. The whole row opens the sheet (the address the old
/// `context.go('/people/attendance/…')` got wrong and #250 fixed).
class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shiftInstance});

  final ShiftInstanceSummary shiftInstance;

  /// The three sentences, unchanged — they now say their meaning in colour as
  /// well (`StatusChip`'s own rule: the label is always rendered).
  (String, StatusTone) get _state {
    if (!shiftInstance.hasSheet) return ('Not opened yet', StatusTone.warning);
    if (shiftInstance.confirmedAt != null) return ('Confirmed', StatusTone.success);
    return ('Started, not yet confirmed', StatusTone.warning);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final (label, tone) = _state;
    return InkWell(
      key: AttendancePickerScreen.shiftRowKey(shiftInstance.id),
      onTap: () => context.go('${Routes.attendance}/${shiftInstance.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shiftInstance.shiftDefinitionName,
                  style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              StatusChip(label: label, tone: tone),
              const SizedBox(width: Spacing.xs),
              Icon(Icons.chevron_right, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgUnitBrowser extends StatelessWidget {
  const _OrgUnitBrowser();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      // The browser is a control inside the card above, not one of this
      // page's list surfaces, so it keeps its own small placeholder: a
      // `SkeletonList` here would draw a card inside a card and read as the
      // page loading twice.
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = Text(state.sitesFailure ?? l10n.commonTheSitesAreUnavailable);
    } else if (state.rootsFailure != null) {
      body = Text(state.rootsFailure!);
    } else if (state.sites.isEmpty) {
      body = Text(l10n.commonThereAreNoSitesToBrowseYet);
    } else if (state.rows.isEmpty) {
      body = Text(l10n.commonNothingToBrowseInThisSite);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in state.rows) _OrgUnitRow(row: row, bloc: bloc)],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.commonOrgUnit,
              style: AppTypography.floor(context)?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (state.sites.length > 1)
              DropdownButtonFormField<String>(
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
              ),
            const SizedBox(height: Spacing.sm),
            DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
          ],
        ),
      ),
    );
  }
}

class _OrgUnitRow extends StatelessWidget {
  const _OrgUnitRow({required this.row, required this.bloc});

  final OrgUnitRow row;
  final OrgUnitPickerBloc bloc;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      tooltip: row.isExpanded ? l10n.commonCollapse : l10n.commonExpand,
                      onPressed: () => bloc.add(
                        row.isExpanded
                            ? OrgUnitPickerCollapsed(row.node.id)
                            : OrgUnitPickerExpanded(row.node.id),
                      ),
                      icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                    ),
            ),
            Expanded(
              child: InkWell(
                key: AttendancePickerScreen.orgUnitRowKey(row.node.id),
                onTap: () => context.read<AttendancePickerBloc>().add(
                      AttendancePickerOrgUnitChosen(
                        orgUnitId: row.node.id,
                        orgUnitName: row.node.name,
                      ),
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
