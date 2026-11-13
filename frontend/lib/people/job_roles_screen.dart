/// The job role catalogue (issue #88, ADR-0005's shared catalogue,
/// CONTEXT.md's Job role entry): every job role the plant recognises, laid
/// over an administrator's own write surface for it (`POST`/`PATCH /api/people/
/// job-roles`, job-role-routes.js).
///
/// Offered to every approved Account, the same openness `DirectoryScreen`
/// already has: `GET /api/people/job-roles` carries no admin or scope check of
/// its own (job-role-routes.js's own header), so hiding this Screen behind a
/// role would gate a destination the route itself never refuses. Only the
/// write affordances inside it ([isAdmin]) are gated — the same shape
/// `EmployeeDetailScreen` already uses for its own administrator-only writes.
///
/// **This is a catalogue, not a register** (`docs/frontend-layout.md` §5): a
/// list read *down* — a reader finds a role by its name and then acts on it —
/// so it is an `AppListCard` of rows with the record's own controls at the far
/// end and no column-label band.
///
/// **What #394 changed here.** The row used to set the name and the code in one
/// weight and one colour (`"Welder · WELD"`), so the identifier a reader scans
/// for and the code a spreadsheet is keyed on looked like the same kind of
/// thing; `name` is now `dense` w600 in `textPrimary` and the ` · CODE` tail is
/// `textMuted`, which is §6's own rule for a catalogue's name and code (the
/// reference board's `.z`). The line is one `Text.rich`, so the sentence a
/// reader hears — and the string the Module's tests assert — is unchanged. The
/// row's left edge and its control's right edge are now the card's own inset
/// rather than a `Wrap`'s idea of it, and **when the card's box is narrower than
/// `AppBreakpoints.headerActionsWrap` at the reader's text size the control
/// drops under the name** instead of being squeezed beside it: at a 700 window
/// with twice the text, "Correct" and a name beside it do not both fit, and a
/// `Row` would overflow rather than move.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'job_role.dart';
import 'job_role_form_dialog.dart';
import 'job_roles_bloc.dart';

class JobRolesScreen extends StatelessWidget {
  const JobRolesScreen({super.key, required this.isAdmin});

  /// Whether this caller may add or correct a job role — read off `/me`'s
  /// own role, the same shape `DirectoryScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189). This Screen used to declare
  /// 700 while the Directory and Org Units declared 900, which is why a
  /// catalogue page read as a narrower app than the two pages either side of
  /// it; the number now comes from [AppLayout.pageWidth].
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('job-roles-add');
  static const ValueKey<String> failedKey = ValueKey<String>('job-roles-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('job-roles-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('job-roles-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('job-roles-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('job-roles-row-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'job-roles-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the catalogue's rows renders — a different
  /// fact from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('job-roles-no-match');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('job-roles-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('job-roles-inactive-$id');

  /// One row's catalogue line: the name, then the code the plant keys it on.
  static ValueKey<String> nameKey(String id) => ValueKey<String>('job-roles-name-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<JobRolesBloc>().state;

    return Scaffold(
      body: switch (state) {
        // A generalised loading placeholder (issue #103) replaces the bare
        // spinner this Screen used before — six rows is the same default
        // `SkeletonList` itself defaults to, and this catalogue is rarely
        // long enough to need more.
        JobRolesLoading() => const SkeletonList(maxWidth: JobRolesScreen.maxWidth),
        JobRolesUnavailable(message: final message) => PlatformFailureState(
            key: JobRolesScreen.failedKey,
            title: l10n.jobRolesTheJobRoleCatalogueCouldNotBe,
            message: message,
            retryKey: JobRolesScreen.retryKey,
            onRetry: () => context.read<JobRolesBloc>().add(const JobRolesStarted()),
          ),
        JobRolesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

/// The catalogue's loaded view. Stateful only because the filter box's term
/// is the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final JobRolesLoaded state;
  final bool isAdmin;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the catalogue to, `''` when nothing is.
  String _term = '';

  /// Whether [jobRole] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify a job role —
  /// its name and its code. No ranking and no fuzzy matching, the same rule
  /// the assign dialog's own filter uses (issue #187).
  static bool _matches(JobRole jobRole, String term) =>
      jobRole.name.toLowerCase().contains(term) || jobRole.code.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<JobRole> get _matchingJobRoles {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.jobRoles;
    return widget.state.jobRoles
        .where((jobRole) => _matches(jobRole, term))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingJobRoles;
    return Center(
      child: AppPageFrame(
        maxWidth: JobRolesScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navJobRoles,
              description: l10n.jobRolesWhatAnEmployeeDoesDefinedOnceShared,
              actions: [
                if (widget.isAdmin)
                  FilledButton.icon(
                    key: JobRolesScreen.addKey,
                    onPressed: widget.state.isMutating
                        ? null
                        : () => JobRoleFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.commonAddJobRole),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (widget.state.jobRoles.isEmpty)
              // No "none matched" variant while there is nothing to narrow
              // (issue #103's own distinction, now carried by the filter box
              // above the rows): this catalogue's own empty story is the only
              // one to tell until it has rows.
              PlatformEmptyState.noneExist(
                key: JobRolesScreen.emptyKey,
                title: l10n.jobRolesNoJobRolesYet,
                message: l10n.commonNothingHasBeenDefinedInTheCatalogue,
                icon: Icons.badge_outlined,
                actionLabel: widget.isAdmin ? l10n.commonAddJobRole : null,
                actionKey: JobRolesScreen.emptyAddKey,
                onAction: widget.isAdmin ? () => JobRoleFormDialog.open(context) : null,
              )
            else ...[
              AppFilterField(
                name: JobRolesScreen.filterFieldName,
                label: l10n.jobRolesFilterJobRoles,
                helperText: l10n.jobRolesByNameOrCode,
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.state.jobRoles.length,
              ),
              const SizedBox(height: Spacing.md),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: JobRolesScreen.noMatchKey,
                  title: l10n.jobRolesNoJobRolesMatch,
                  message: l10n.jobRolesNothingInTheCatalogueMatchesTryA(_term.trim()),
                )
              else
                // One row per job role, ruled apart from its neighbours — the
                // catalogue's record has an edge to follow across the page now
                // (issue #189), rather than six lines of undifferentiated white.
                AppListCard(
                  rows: [
                    for (final jobRole in matches)
                      _JobRoleRow(
                        jobRole: jobRole,
                        isAdmin: widget.isAdmin,
                        isMutating: widget.state.isMutating,
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

/// One row of the catalogue: the role's own line at the card's left edge, its
/// control at the card's right-hand one (see this file's header for both
/// decisions).
class _JobRoleRow extends StatelessWidget {
  const _JobRoleRow({required this.jobRole, required this.isAdmin, required this.isMutating});

  final JobRole jobRole;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    // The two tones of one line, not two widgets: `Text.rich` keeps the
    // sentence ("Welder · WELD") whole for a screen reader and for the string
    // this Module's tests assert, while the eye gets the name first and the
    // code as its quieter tail.
    final line = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: jobRole.name,
            style: AppTypography.dense(context)?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: ' · ${jobRole.code}',
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
      key: JobRolesScreen.nameKey(jobRole.id),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final name = Row(
      children: [
        Flexible(child: line),
        if (!jobRole.isActive) ...[
          const SizedBox(width: Spacing.sm),
          StatusChip(key: JobRolesScreen.inactiveChipKey(jobRole.id), label: l10n.commonInactive, tone: StatusTone.neutral),
        ],
      ],
    );

    final Widget? action = isAdmin
        ? OutlinedButton(
            key: JobRolesScreen.correctKey(jobRole.id),
            onPressed: isMutating ? null : () => JobRoleFormDialog.open(context, jobRole: jobRole),
            child: Text(l10n.commonCorrect),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The box the row is handed, at the reader's text size (§10): the
        // control is dropped under the name rather than squeezed beside it.
        final stacked = constraints.maxWidth <
            AppBreakpoints.effective(context, AppBreakpoints.headerActionsWrap);
        return Padding(
          key: JobRolesScreen.rowKey(jobRole.id),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    name,
                    if (action != null) ...[
                      const SizedBox(height: Spacing.sm),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: name),
                    if (action != null) ...[
                      const SizedBox(width: Spacing.md),
                      action,
                    ],
                  ],
                ),
        );
      },
    );
  }
}
