/// The Employee directory (issue #86, CONTEXT.md's Directory entry): who
/// works here, searched, filtered by Org Unit and by job role, Departed
/// Employees excluded by default.
///
/// Offered to every approved Account (AC1) — unlike Assets or Work orders,
/// there is no role gate on this Screen or its destination: ADR-0009 is
/// exactly the decision that a plant directory is not a secret.
///
/// **It is a register, and the register has to scale to a plant (#392,
/// `design-language.md` §5, §6).** A directory is read *across*: a reader
/// comparing two people compares their Org Units, their job roles and whether
/// they still work here, and none of those comparisons is possible when every
/// person is a card whose facts are stacked three lines deep. So the page names
/// its columns once, as [_columns], and builds the band and every row's cells
/// from that list — the same `AppTableHeader`/`AppTableRow` pair the Work order
/// register and the maintenance registers use, so a Directory row and a Work
/// order row are the same kind of thing at the same height. Each row opens the
/// Employee; the row itself is the tap target, so it is never shorter than
/// [AppTouchTarget.min].
///
/// **Dense at 1280, one card per Employee at 700.** Six columns in a 988px box
/// is the density the reference board's own tables are read at; below
/// [narrowBreakpoint] of *content* width — read from the box the list is handed,
/// never the window, and scaled by the reader's own text size (§10, the bug
/// class of #379 and #381) — one card per Employee, carrying the same facts
/// stacked, because a narrow box is a narrow box rather than a reason to drop
/// what a reader looks someone up by.
///
/// **Every cell that can hold unbounded user text discloses it.** A name, an Org
/// Unit and a job role are free text, so at a 1280 window they clip and
/// [DisclosingText] says so in a tooltip, in a long press and to a screen reader
/// (issue #168). Nothing is silently truncated, and the row's own identity — the
/// avatar block and the name — is the first cell, so a clipped name is still the
/// cell a pointer starts from.
///
/// **The avatar block carries the person's initials.** A directory of forty rows
/// of identical person glyphs gives the eye nothing to stop on; two initials do,
/// and they are drawn from the name already on the row, so nothing new is asked
/// of the wire. The initials are decoration — the name beside them is the fact —
/// which is why they are fitted rather than scaled: at twice the reader's text
/// the block stays 32px and the letters shrink to fit it instead of overflowing
/// a circle.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'directory_bloc.dart';
import 'directory_org_unit_filter_dialog.dart';
import 'employee.dart';
import 'employee_form_dialog.dart';
import 'employment_type.dart';

class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key, required this.isAdmin});

  /// Whether this caller may add an Employee (issue #87) — read off `/me`'s
  /// own role, the same shape `AssetsScreen.canPlaceAnAsset` follows, except
  /// this is a role gate rather than a Grant one: the four write routes are
  /// `requireAdmin`, not Org-Unit-scoped (ADR-0009). False hides the "Add
  /// Employee" affordance entirely, the same reasoning `canPlaceAnAsset`
  /// gives for hiding rather than disabling.
  final bool isAdmin;

  /// A register's width (#392). Six columns and an avatar block do not read at a
  /// catalogue's 900.
  static const double maxWidth = 1100;

  /// The content width (at a text scale of 1) at or above which the Directory is
  /// a table of six columns; below it, one card per Employee. Six columns is one
  /// more than `AppBreakpoints.registerTable` (700) was measured for, so this
  /// Screen states its own number — 900, the same one the complaint register
  /// argues for its six (#390) — and reads it through [AppBreakpoints.effective].
  static const double narrowBreakpoint = 900;

  /// The `name` the Directory's own `AppSearchField` is seeded with (issue
  /// #128) — kept in one place so [searchFieldKey] and [searchSuggestionKey]
  /// can never drift from what `_Header.build` actually renders, the same
  /// device `SiteFormDialog._timezoneFieldName` uses (issue #127).
  static const String _searchFieldName = 'directory-search';

  /// How many suggestions a fetch asks for (issue #123's own `limit`) — matches
  /// `AppSearchField`'s own cap on rendered rows (issue #125), so nothing
  /// beyond what could ever be shown is pulled over the wire.
  static const int _suggestionLimit = 10;

  static const ValueKey<String> addKey = ValueKey<String>('directory-add');

  /// Kept as the accessor's existing name (issue #128) even though the control
  /// behind it changed from a `TextField` to `AppSearchField` — this now
  /// resolves to that field's own key rather than a bespoke one, the same
  /// change `SiteFormDialog.timezoneKey` made for issue #127.
  static ValueKey<String> get searchFieldKey => AppSearchField.fieldKey(_searchFieldName);

  /// One search suggestion row's own `Key`, keyed by the Employee's own id.
  static ValueKey<String> searchSuggestionKey(String employeeId) =>
      AppSearchField.suggestionKey(_searchFieldName, employeeId);

  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('directory-org-unit-filter');
  static const ValueKey<String> jobRoleFilterKey = ValueKey<String>('directory-job-role-filter');
  static const ValueKey<String> includeDepartedKey = ValueKey<String>('directory-include-departed');
  static const ValueKey<String> myRecordKey = ValueKey<String>('directory-my-record');
  static const ValueKey<String> emptyKey = ValueKey<String>('directory-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('directory-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('directory-retry');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('directory-row-$id');
  static ValueKey<String> departedChipKey(String id) => ValueKey<String>('directory-departed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DirectoryBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, isAdmin: isAdmin),
          Expanded(
            child: switch (state) {
              DirectoryLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
              DirectoryUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: 'The Directory could not be read',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<DirectoryBloc>().add(const DirectoryStarted()),
                ),
              DirectoryLoaded(isLoadingList: true) => const SkeletonList(rows: 5, maxWidth: maxWidth),
              // The Directory's list is bounded by the server's own `search`, so
              // a Directory with no rows is a search that matched nothing — the
              // *none matched* variant, whose wording this Screen has always
              // used. `docs/design-language.md` §7: the four states are the
              // shared widgets, not a private copy per Screen.
              DirectoryLoaded(employees: final employees) when employees.isEmpty =>
                const PlatformEmptyState.noneMatched(
                  key: emptyKey,
                  title: 'Nobody matches this search',
                  message: 'Try a different name, or clear a filter.',
                  icon: Icons.people_outline,
                ),
              DirectoryLoaded(employees: final employees) => _DirectoryRegister(employees: employees),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.state, required this.isAdmin});

  final DirectoryState state;
  final bool isAdmin;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  /// A dumb fetch, per `AppSearchField`'s own contract (issue #125): the
  /// widget itself owns the 300ms debounce and the 2-character minimum, so
  /// this issues one request per term it is actually asked for and nothing
  /// more. Throwing (rather than returning an empty list) on a signed-out
  /// session is what lets `AppSearchField` show `PlatformFailureState`
  /// instead of a suggestion list quietly going empty for a reason it never
  /// reports.
  Future<List<Employee>> _fetchSuggestions(String term) async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      throw PeopleApiException(DirectoryBloc.signedOutMessage);
    }
    return context.read<PeopleApi>().fetchEmployees(
          token,
          search: term,
          limit: DirectoryScreen._suggestionLimit,
        );
  }

  @override
  Widget build(BuildContext context) {
    final loaded = widget.state is DirectoryLoaded ? widget.state as DirectoryLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: DirectoryScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          // The buttons are the header's actions: `AppPageHeader` puts them at
          // the row's far end, and wraps them under the title when the box is
          // too narrow to share (the failure the old comment here guarded
          // against: "Directory" itself wrapping character by character).
          child: AppPageHeader(
            title: 'Directory',
            description:
                'Who works here — searched, filtered, and Departed Employees kept '
                'out of sight until asked for.',
            actions: [
              if (widget.isAdmin)
                FilledButton.icon(
                  key: DirectoryScreen.addKey,
                  onPressed: loaded != null && loaded.isAdding
                      ? null
                      : () => EmployeeFormDialog.open(context),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add Employee'),
                ),
              OutlinedButton.icon(
                key: DirectoryScreen.myRecordKey,
                onPressed: () => context.go('${Routes.directory}/me'),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('My record'),
              ),
            ],
            below: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // As-you-type suggestions (issue #128, ADR-0023 point 5) sit
                // alongside the list filter below, not in place of it: picking
                // a suggestion navigates straight to that Employee
                // (`onSelected`), while pressing Enter without picking one
                // still narrows the list underneath exactly as it always has
                // (`onSubmitted` → `DirectorySearchChanged`) — "show me
                // everyone called Nguyen" is a real thing to want, and is not
                // the same as jumping to one person (this ticket's own "Why").
                AppSearchField<Employee>(
                  name: DirectoryScreen._searchFieldName,
                  label: 'Search by name',
                  // No confirmed selection to seed or track here — unlike
                  // `SiteFormDialog`'s timezone field, a pick here navigates
                  // away rather than settling into this field, so there is
                  // never a chosen Employee this field itself needs to display.
                  value: null,
                  onChanged: (_) {},
                  onSelected: (employee) => context.go('${Routes.directory}/${employee.id}'),
                  fetchSuggestions: _fetchSuggestions,
                  suggestionBuilder: (context, employee) {
                    final theme = Theme.of(context);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(employee.displayName),
                          Text(
                            _employeeSubtitle(employee),
                            style: AppTypography.floor(context)
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                  idOf: (employee) => employee.id,
                  displayStringFor: (employee) => employee.displayName,
                  onSubmitted: (value) =>
                      context.read<DirectoryBloc>().add(DirectorySearchChanged(value)),
                ),
                if (loaded != null) ...[
                  const SizedBox(height: Spacing.sm),
                  // The narrowing controls are the page's toolbar (#392): the
                  // widgets `AppToolbar` was written for, so the filters lead,
                  // wrap under each other on a narrow box, and every action is
                  // laid out to the 44px floor without this Screen restating
                  // either rule (§5, §6).
                  AppToolbar(
                    filters: [
                      OutlinedButton.icon(
                        key: DirectoryScreen.orgUnitFilterKey,
                        onPressed: () => DirectoryOrgUnitFilterDialog.open(context),
                        icon: const Icon(Icons.account_tree_outlined, size: 18),
                        label: Text(loaded.orgUnitName ?? 'All Org Units'),
                      ),
                      SizedBox(
                        width: AppLayout.atTextScale(context, 220),
                        child: DropdownButtonFormField<String>(
                          key: DirectoryScreen.jobRoleFilterKey,
                          initialValue: loaded.jobRoleId,
                          isDense: true,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Job role', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('All job roles')),
                            for (final jobRole in loaded.jobRoles)
                              DropdownMenuItem<String>(value: jobRole.id, child: Text(jobRole.name)),
                          ],
                          onChanged: (jobRoleId) => context
                              .read<DirectoryBloc>()
                              .add(DirectoryJobRoleFilterChanged(jobRoleId)),
                        ),
                      ),
                      FilterChip(
                        key: DirectoryScreen.includeDepartedKey,
                        label: const Text('Include Departed'),
                        selected: loaded.includeDeparted,
                        onSelected: (value) =>
                            context.read<DirectoryBloc>().add(DirectoryIncludeDepartedChanged(value)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The job role and Org Unit line shown beneath an Employee's name — shared
/// by the register's own card and `_HeaderState`'s own search suggestion row
/// (issue #128), so the two can never phrase the same fact differently. A
/// missing job role reads as "No job role", never a blank the reader has to
/// interpret (issue #91's own criterion); the Org Unit is appended only when
/// there is one to name at all — directory.js's own fallback rule means it is
/// usually there even with no current Assignment, but not always (neither a
/// current Assignment nor a `defaultOrgUnitId`).
String _employeeSubtitle(Employee employee) => employee.orgUnitName == null
    ? (employee.jobRoleName ?? 'No job role')
    : '${employee.jobRoleName ?? 'No job role'} · ${employee.orgUnitName}';

/// The two letters on an Employee's avatar block: the first letter of the name
/// they are read by and of its last word.
///
/// A name the plant records as one word gets one letter; a name with no letters
/// at all (an empty display name, which the wire allows) gets a middot rather
/// than an empty circle, the same "nothing versus zero" rule §13 gives a cell.
String _initials(String displayName) {
  final words = displayName.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return '·';
  final first = words.first.characters.first.toUpperCase();
  if (words.length == 1) return first;
  return '$first${words.last.characters.first.toUpperCase()}';
}

/// The register's one column spec: [AppTableHeader] and every [AppTableRow] are
/// built from it, so a band label and its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context, List<Employee> rows) => [
      const AppTableColumn('Employee', flex: 5),
      AppTableColumn('Code', width: _codeColumnWidth(context, rows)),
      const AppTableColumn('Org Unit', flex: 4),
      const AppTableColumn('Job role', flex: 4),
      const AppTableColumn('Employment', flex: 2),
      AppTableColumn('State', width: _stateColumnWidth(context, rows), align: AppColumnAlign.start),
    ];

/// The employee number column: the widest code in the list, plus the slot's own
/// gutter. A code is never truncated — it is what a reader quotes.
double _codeColumnWidth(BuildContext context, List<Employee> rows) {
  var widest = 0.0;
  for (final row in rows) {
    final width = _measure(context, row.employeeNo, AppTypography.dense(context));
    if (width > widest) widest = width;
  }
  final header = _measure(context, 'Code', Theme.of(context).textTheme.labelMedium);
  return (widest > header ? widest : header) + 2 * Spacing.sm;
}

/// The state column: the widest word it can carry, so the column does not
/// resize as people leave the plant.
double _stateColumnWidth(BuildContext context, List<Employee> rows) {
  final label = Theme.of(context).textTheme.labelMedium;
  final departed = _measure(context, 'Departed', label);
  final active = _measure(context, 'Active', label);
  return (departed > active ? departed : active) + 4 * Spacing.md;
}

double _measure(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _DirectoryRegister extends StatelessWidget {
  const _DirectoryRegister({required this.employees});

  final List<Employee> employees;

  @override
  Widget build(BuildContext context) {
    // The box this list actually got from its parent, scaled by the reader's
    // text size (§10) — never the window.
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth <
            AppBreakpoints.effective(context, DirectoryScreen.narrowBreakpoint);
        final columns = _columns(context, employees);

        return Center(
          child: AppPageFrame(
            maxWidth: DirectoryScreen.maxWidth,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                if (!narrow) AppTableHeader(columns: columns),
                for (var index = 0; index < employees.length; index++) ...[
                  if (narrow && index > 0) const SizedBox(height: Spacing.sm),
                  if (narrow)
                    _EmployeeCard(employee: employees[index])
                  else
                    _EmployeeTableRow(columns: columns, employee: employees[index]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The avatar block: two letters on the palette's own primary container. The
/// block is a fixed 32px because it is chrome, and the letters are fitted rather
/// than scaled, so twice the reader's text shrinks them inside the circle
/// instead of overflowing it.
class _Initials extends StatelessWidget {
  const _Initials({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: Text(
            _initials(displayName),
            style: AppTypography.floor(context)?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The state cell: a chip, because a state is a tone (§6's alignment table). The
/// Departed chip keeps its key — a test that finds it today still finds it, and
/// finds it only on a Departed Employee, which is what it always meant.
Widget _stateCell(Employee employee) => employee.isActive
    ? const StatusChip(label: 'Active', tone: StatusTone.success)
    : StatusChip(
        key: DirectoryScreen.departedChipKey(employee.id),
        label: 'Departed',
        tone: StatusTone.neutral,
      );

class _EmployeeTableRow extends StatelessWidget {
  const _EmployeeTableRow({required this.columns, required this.employee});

  final List<AppTableColumn> columns;
  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = employee;

    return KeyedSubtree(
      key: DirectoryScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        onTap: () => context.go('${Routes.directory}/${row.id}'),
        cells: [
          Row(
            children: [
              _Initials(displayName: row.displayName),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: DisclosingText(
                  row.displayName,
                  style: dense?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          DisclosingText(row.employeeNo, style: dense?.copyWith(color: palette.textMuted)),
          DisclosingText(
            row.orgUnitName ?? '—',
            style: dense?.copyWith(color: palette.textMuted),
          ),
          DisclosingText(
            row.jobRoleName ?? 'No job role',
            style: dense?.copyWith(color: palette.textPrimary),
          ),
          DisclosingText(
            employmentTypeLabel(row.employmentType),
            style: dense?.copyWith(color: palette.textMuted),
          ),
          _stateCell(row),
        ],
      ),
    );
  }
}

/// One Employee as a card, for a box that cannot hold six columns. The same
/// facts as the table row, stacked, because a narrow box is a narrow box rather
/// than a reason to drop what a reader looks someone up by.
class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    final row = employee;

    return Card(
      key: DirectoryScreen.rowKey(row.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.go('${Routes.directory}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              _Initials(displayName: row.displayName),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          row.displayName,
                          style: AppTypography.dense(context)
                              ?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        _stateCell(row),
                      ],
                    ),
                    Text(
                      '${row.employeeNo} · ${employmentTypeLabel(row.employmentType)}',
                      style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                    ),
                    Text(
                      _employeeSubtitle(row),
                      style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
