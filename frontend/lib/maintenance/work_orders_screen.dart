/// The open Work order list: what is currently raised against the Site's
/// Assets, who has it, and a way to raise a new one (issue #57).
///
/// Readable by anyone whose role earns the Module, whatever their Grants —
/// the same reasoning `AssetsScreen`'s own header documents. Raising is
/// offered only to a caller who holds a write Grant somewhere: an action the
/// server would refuse is not offered in the first place.
///
/// **This is the reference Screen for Maintenance (issue #104, parent #99).**
/// Requests, Breakdowns, Downtime, PM schedules, Job plans and Parts
/// (#72–#80) each copy the shape settled here rather than re-deciding it:
///
/// - **The dialog-versus-Screen rule.** A transition or a creation against
///   one record of this Screen's own kind (raise, assign, complete, cancel)
///   gets its own `go_router` address — `${Routes.workOrders}/new`,
///   `${Routes.workOrders}/:id/assign`, and so on — linkable, and
///   reconstructed from the list already in memory (or a loading/not-found/
///   not-available placeholder while that resolves) on a fresh load. This is
///   what keeps ADR-0019 holding on the client: the backend already gives
///   `start`/`complete`/`cancel` their own route each, and this Screen gives
///   each of `complete`/`cancel`/`assign`/raise its own address so a
///   supervisor can send a colleague straight to the job. See
///   `WorkOrderDialogHost` (`work_order_dialog_host.dart`) for how a dialog
///   address resolves the Work order it names, and `router.dart`'s own
///   nested `ShellRoute` for how the four dialog addresses share one
///   `WorkOrdersBloc` with the list underneath them.
///
///   Every dialog address is reached with `context.go`, never
///   `context.push`: a `Page`-based child route like these four is not
///   something `push` can navigate to at all (`push` only ever appends an
///   *imperative* route on top of whatever `go_router` already resolved from
///   the URL — the location it reports never moves to match, which is
///   exactly the address-survives-a-refresh property ADR-0019 asks for).
///   `go` also means the browser's back button, not just a dialog's own
///   Cancel, correctly returns to the list.
///
///   One consequence worth naming for the next Screen's author: because the
///   nested `ShellRoute` above owns its own Navigator (so the list and its
///   four dialogs can all share one `WorkOrdersBloc` — see that file's own
///   comment for why), a dialog reached this way paints over the *content
///   pane* next to the sidebar, not the whole window the way a bare
///   `showDialog` used to. The Shell's own destinations stay reachable while
///   a dialog is open; nothing here relies on them being covered.
///
///   A control that only returns a value to its *caller*, with no record of
///   its own — the Org Unit filter picker below — stays a plain,
///   address-less `showDialog`: there is no clean way for a route to hand a
///   chosen value back to whoever navigated to it.
///
///   A write with no confirmation step — Start, which asks for nothing and
///   dispatches `WorkOrderStartConfirmed` straight from the row — gets no
///   address at all, ever. An address must never be something that performs
///   a write merely by being loaded: a refresh, a shared link, or a chat
///   client's own link preview would re-fire it.
///
/// - **Row actions.** One primary button — the next *status* transition —
///   plus one overflow holding everything else, never four buttons in a
///   row. See `_RowActions`'s own header below.
///
/// - **Filters live in the header, as removable chips**, with room left for
///   a second filter dimension and a "Clear all" affordance once one
///   arrives — see `_Header`'s own comment on its filter row.
///
/// - **Below 800px of this Screen's own content width, cards; at or above,
///   a table — never horizontal scroll.** See `_WorkOrdersList`'s own
///   header.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'org_unit_chooser.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrdersScreen extends StatelessWidget {
  const WorkOrdersScreen({
    super.key,
    required this.canRaiseWorkOrder,
    required this.canAssignWorkOrder,
    required this.canWorkWorkOrder,
  });

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule `AssetsScreen`
  /// applies to its own "Add an Asset" button. False hides the raise
  /// affordance entirely; it does not grey it out, because a disabled button
  /// is still an invitation to fail.
  final bool canRaiseWorkOrder;

  /// Whether this caller holds a write Grant *reaching the Org Unit a given
  /// Work order sits at* (issue #62) — read off `/me`'s own `orgUnitScope`
  /// (issue #43), and since issue #110 (ADR-0027) that scope names every Org
  /// Unit beneath each Grant, so this is the same mechanism `HomeBloc`'s
  /// awaiting-assignment count reads rather than a second, coarser rule. A
  /// predicate, not a bool, because the answer is per-record: a write Grant on
  /// one line says nothing about a Work order on another. False for a row
  /// hides that row's assign affordance; the server is still the real gate
  /// (403).
  final bool Function(String orgUnitId) canAssignWorkOrder;

  /// The same coarse signal as [canRaiseWorkOrder], and the same reason (issue
  /// #63): a separate flag rather than reusing [canAssignWorkOrder] — each
  /// affordance carries its own justification in this codebase. This one still
  /// reads `orgUnitScope.canWriteSomewhere` (a write Grant anywhere at all),
  /// because Start, Complete and Cancel are transitions the row's own status
  /// offers; only assigning has moved to the per-Org-Unit [canAssignWorkOrder]
  /// check (issue #110). False hides Start, Complete and Cancel entirely —
  /// absent, not disabled.
  final bool canWorkWorkOrder;

  static const double maxWidth = 960;

  /// The breakpoint below which the list renders as one card per Work order
  /// rather than a table (issue #104, Decision E) — measured against this
  /// Screen's own *content* width (`_WorkOrdersList`'s own `LayoutBuilder`,
  /// issue #105), not the browser window. It no longer shares its number
  /// with `platform/shell.dart`'s rail breakpoint on purpose: that one is
  /// against the window, correctly, since the Shell is the thing that owns
  /// the window; this Screen only ever sees what the Shell hands it after
  /// its own sidebar (260px expanded, 64px rail) is already subtracted, so
  /// the two breakpoints answer different questions and coincidentally
  /// sharing a number was the bug, not a feature to preserve. #99's own
  /// Implementation Decisions freeze the Shell's 700px/260px/64px; this
  /// constant is free to be whatever keeps the table legible on its own.
  ///
  /// 800, not 700: at 700px of content the table still fits without
  /// overlapping anything, but WO# — the one column every row is identified
  /// by — is itself ellipsized ("WO-…"), and at 750px "Assignee" and
  /// "Actions" run together with no gap between the header labels at all.
  /// 800px is the first width sampled (in 50px steps) where every header
  /// label sits on its own line with visible spacing and WO#, Summary, Org
  /// Unit and Status all render in full — Asset and a long Assignee name are
  /// still free to ellipsize, the same accepted trade-off the table's other
  /// flexed cells already make. Chosen by rendering the actual Screen at
  /// each width and reading it, not derived from the column arithmetic.
  static const double narrowBreakpoint = 800;

  static const ValueKey<String> raiseKey = ValueKey<String>('work-orders-add');
  static const ValueKey<String> siteKey = ValueKey<String>('work-orders-site');
  static const ValueKey<String> filterKey = ValueKey<String>('work-orders-org-unit-filter');
  static const ValueKey<String> clearFilterKey = ValueKey<String>('work-orders-clear-filter');
  static const ValueKey<String> noticeKey = ValueKey<String>('work-orders-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('work-orders-retry');

  /// The line that says how many Work orders are on screen (issue #168).
  static const ValueKey<String> countKey = ValueKey<String>('work-orders-count');

  /// What [countKey]'s line reads, given the loaded state (issue #168).
  ///
  /// Private, and the tests go through the Screen rather than calling this: a
  /// review of the first version pointed out that it was public "so the wording
  /// is asserted directly", while every test asserting the wording did so
  /// through `find.text` — a public accessor with no caller, kept alive by a
  /// doc comment. The three wordings it can produce *are* covered
  /// (`work_orders_test.dart`'s own `legibility (#168)` group asserts the
  /// plural, the singular, a narrowing and the history opt-in, and asserts the
  /// line is absent where the empty state speaks).
  ///
  /// The noun is the domain's own ("Work order", per CONTEXT.md), singular
  /// when there is exactly one. Narrowing and history are named only when
  /// they are actually in force, so nothing here claims a filter nobody set.
  static String _countLabel(WorkOrdersLoaded loaded) {
    final count = loaded.workOrders.length;
    final noun = count == 1 ? 'Work order' : 'Work orders';
    final narrowed =
        loaded.orgUnitFilterName == null ? '' : ', narrowed to ${loaded.orgUnitFilterName}';
    final history = loaded.showHistory ? ', including completed and cancelled' : '';
    return '$count $noun$narrowed$history';
  }

  /// The "nothing has ever been raised" empty state (issue #103's
  /// `EmptyStateVariant.noneExist`) — unfiltered, genuinely nothing at this
  /// Site. Kept as `work-orders-empty`, its pre-#103 name, so the existing
  /// test asserting this key stays meaningful rather than silently starting
  /// to assert on the wrong variant.
  static const ValueKey<String> emptyKey = ValueKey<String>('work-orders-empty');

  /// The "your filter matched nothing" empty state
  /// (`EmptyStateVariant.noneMatched`) — an Org Unit filter is narrowing the
  /// list and nothing in that narrower scope is currently open.
  static const ValueKey<String> emptyFilteredKey = ValueKey<String>('work-orders-empty-filtered');

  static const ValueKey<String> emptyRaiseKey = ValueKey<String>('work-orders-empty-raise');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('work-orders-empty-clear-filters');
  static const ValueKey<String> failedKey = ValueKey<String>('work-orders-failed');
  static const ValueKey<String> scopeRefusedKey = ValueKey<String>('work-orders-scope-refused');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('work-order-row-$id');

  /// The affordance that opens a row's detail (`/work-orders/:id`, issue #74)
  /// — the whole row is tappable, so the tasks copied from the Job plan are
  /// one tap away without the Site-wide list carrying them itself. Present on
  /// every row regardless of role or status, since reading is not a write.
  static ValueKey<String> detailsKey(String id) => ValueKey<String>('work-order-details-$id');

  /// One key, two labels — unlike `AssetsScreen.retireKey`/`reinstateKey`,
  /// which are two keys because they are two different acts. Assigning and
  /// reassigning are one act (AC5), so the key is stable and only the label
  /// changes. Since #104, this key lives on the overflow menu's own item
  /// (`_RowActions`) rather than an inline button — present in the widget
  /// tree only once the overflow is open, per [rowActionsKey]'s own doc
  /// comment.
  static ValueKey<String> assignKey(String id) => ValueKey<String>('work-order-assign-$id');

  /// Three separate keys, not one — unlike [assignKey]: starting, completing
  /// and cancelling are three different acts, so this follows
  /// `AssetsScreen.retireKey`/`reinstateKey` instead (issue #63). [startKey]
  /// and [completeKey] stay on an inline primary button (issue #104,
  /// Decision C); [cancelKey] moved to the overflow menu alongside
  /// [assignKey].
  static ValueKey<String> startKey(String id) => ValueKey<String>('work-order-start-$id');
  static ValueKey<String> completeKey(String id) => ValueKey<String>('work-order-complete-$id');
  static ValueKey<String> cancelKey(String id) => ValueKey<String>('work-order-cancel-$id');

  /// The overflow trigger for one row (issue #104, Decision C) — a single
  /// kebab icon button holding whichever of Assign/Reassign and Cancel apply
  /// to this row, so a row never lays out more than one primary button plus
  /// this one trigger. Its own `onPressed` is `null` (disabled), not merely
  /// its menu items, while any assign or transition is in flight anywhere on
  /// the Screen — that is what stops a caller from even opening the menu, so
  /// a test proves "no transition offered while one is in flight" by reading
  /// this key's own `onPressed` rather than reaching into a menu that cannot
  /// be open in the first place.
  static ValueKey<String> rowActionsKey(String id) => ValueKey<String>('work-order-actions-$id');

  static const ValueKey<String> showHistoryKey = ValueKey<String>('work-orders-show-history');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrdersBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canRaiseWorkOrder: canRaiseWorkOrder),
          if (state is WorkOrdersLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              WorkOrdersLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              // The scope refusal (#103's fifth case) is checked before the
              // ordinary failure below, and matched on its own field pattern
              // rather than folded into it, so a scope-refused read can
              // never fall through to `PlatformFailureState`'s generic
              // wording — see `WorkOrdersUnavailable.isScopeRefused`'s own
              // doc comment for why this read cannot actually produce one
              // today and why the branch is kept anyway.
              WorkOrdersUnavailable(isScopeRefused: true) =>
                const PlatformScopeRefusedState(key: WorkOrdersScreen.scopeRefusedKey),
              WorkOrdersUnavailable(message: final message) => PlatformFailureState(
                  key: WorkOrdersScreen.failedKey,
                  title: 'The Work orders could not be read',
                  message: message,
                  retryKey: WorkOrdersScreen.retryKey,
                  onRetry: () => context.read<WorkOrdersBloc>().add(const WorkOrdersStarted()),
                ),
              WorkOrdersLoaded(isLoadingWorkOrders: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              WorkOrdersLoaded(
                workOrders: final workOrders,
                orgUnitFilterId: final filterId,
                orgUnitFilterName: final filterName,
                showHistory: final showHistory
              )
                  when workOrders.isEmpty =>
                _WorkOrdersEmpty(
                  orgUnitFilterId: filterId,
                  orgUnitFilterName: filterName,
                  showHistory: showHistory,
                  canRaiseWorkOrder: canRaiseWorkOrder,
                ),
              WorkOrdersLoaded(workOrders: final workOrders) => _WorkOrdersList(
                  workOrders: workOrders,
                  canAssign: canAssignWorkOrder,
                  canWork: canWorkWorkOrder,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canRaiseWorkOrder});

  final WorkOrdersState state;
  final bool canRaiseWorkOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is WorkOrdersLoaded ? state as WorkOrdersLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrdersScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
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
                        Text('Work orders', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        // "Every open job" stopped being true once the history
                        // toggle can bring completed and cancelled rows back
                        // (issue #63) — neutral wording that holds either way.
                        Text(
                          'The work raised at this Site, which Asset it is '
                          'against, and who has it.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canRaiseWorkOrder && loaded != null)
                    FilledButton.icon(
                      key: WorkOrdersScreen.raiseKey,
                      // Its own address (issue #104, Decision A/B) —
                      // `${Routes.workOrders}/new` — rather than a bare
                      // `showDialog`, so a refresh mid-raise does not lose
                      // the form and the address can be sent to a
                      // colleague.
                      onPressed: loaded.isRaising
                          ? null
                          : () => context.go('${Routes.workOrders}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Raise a Work order'),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: WorkOrdersScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<WorkOrdersBloc>().add(WorkOrdersSiteSelected(siteId));
                    },
                  ),
                ),
              ],
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                // Filters live here, as removable chips (issue #104,
                // Decision D). Today there is exactly one filter dimension
                // (the Org Unit narrow), so there is nothing yet to offer a
                // "Clear all" over — but this `Wrap` is where a second
                // dimension (a status filter, say, that a future Maintenance
                // Screen adds) would sit alongside this one, with "Clear
                // all" appearing once there are two chips to clear at once.
                // "Show completed and cancelled" below is deliberately kept
                // out of this row: it broadens the read rather than
                // narrowing it, so it stays the plain `FilterChip` toggle it
                // already was rather than being folded in as a third
                // "applied filter".
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (loaded.orgUnitFilterId == null)
                      OutlinedButton.icon(
                        key: WorkOrdersScreen.filterKey,
                        onPressed: () => _openOrgUnitFilter(context, loaded.siteId!),
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: const Text('Narrow to an Org Unit'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                      )
                    else
                      // A `Chip` plus its own adjacent `IconButton`, not
                      // `Chip.onDeleted`/`deleteIcon` directly: passing
                      // `Chip.deleteIconBoxConstraints` — the documented way
                      // to guarantee this icon's 44×44 target (#99 user
                      // story 28) — triggers a framework semantics assertion
                      // on the pinned SDK the moment a `Chip` carrying one
                      // first enters the tree (reproduced in isolation
                      // against a bare `Chip`, nothing specific to this
                      // Screen or this filter). This sidesteps that bug
                      // entirely rather than shipping a Screen that crashes
                      // its own tests, while keeping the same look (a
                      // removable chip) and the same [clearFilterKey] the
                      // clear affordance always carried.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(
                              'Narrowed to ${loaded.orgUnitFilterName}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            key: WorkOrdersScreen.clearFilterKey,
                            tooltip: 'Show the whole Site again',
                            icon: const Icon(Icons.close),
                            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                            onPressed: () => context
                                .read<WorkOrdersBloc>()
                                .add(const WorkOrdersOrgUnitFilterCleared()),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                FilterChip(
                  key: WorkOrdersScreen.showHistoryKey,
                  label: const Text('Show completed and cancelled'),
                  selected: loaded.showHistory,
                  // Same guard `AssetsScreen.showRetiredKey` uses for its own
                  // chip: toggling while a raise, assign or transition is in
                  // flight would interleave the re-read with that write's own
                  // mutation and could wipe a pending success notice before
                  // the caller ever sees it.
                  onSelected: loaded.isRaising || loaded.isAssigning || loaded.isTransitioning
                      ? null
                      : (value) =>
                          context.read<WorkOrdersBloc>().add(WorkOrdersShowHistoryChanged(value)),
                ),
                // How much is on screen, in the domain's own words (issue
                // #168). Not a footer under the list, and that is a deliberate
                // departure from the ticket's own first wording: the list is a
                // lazy `ListView`, so a footer is only reached by scrolling to
                // the bottom — the one place a reader who is wondering "is this
                // everything?" is least likely to be. Here, beside the controls
                // that changed it, it is always visible.
                //
                // Suppressed when nothing is shown: the empty state already
                // speaks, and "0 Work orders" above it would be the same fact
                // said twice (and would read as an error rather than as the
                // state the Screen has its own words for).
                if (loaded.workOrders.isNotEmpty) ...[
                  const SizedBox(height: Spacing.md),
                  Text(
                    WorkOrdersScreen._countLabel(loaded),
                    key: WorkOrdersScreen.countKey,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a chooser over the same tree `OrgUnitChooser` already browses for
/// placing an Asset (#56) — the real tree engine (`OrgUnitPickerBloc`), not
/// the Grant-editing `OrgUnitPicker` widget, which carries a mandatory level
/// on every row that has no meaning here.
///
/// Deliberately still a bare `showDialog`, not a `go_router` address (issue
/// #104, Decision A) — this picker only returns a value to its caller
/// (`showDialog<OrgUnitNode>`), it names no record of its own, and a route
/// has no clean channel to hand a chosen value back to whoever navigated to
/// it.
Future<void> _openOrgUnitFilter(BuildContext context, String siteId) async {
  final bloc = context.read<WorkOrdersBloc>();
  final peopleApi = context.read<PeopleApi>();
  final authGateway = context.read<AuthGateway>();
  final chosen = await showDialog<OrgUnitNode>(
    context: context,
    builder: (dialogContext) => BlocProvider<OrgUnitPickerBloc>(
      create: (_) => OrgUnitPickerBloc(
        peopleApi: peopleApi,
        authGateway: authGateway,
        initialSiteId: siteId,
      )..add(const OrgUnitPickerStarted()),
      child: const _OrgUnitFilterDialog(),
    ),
  );
  if (chosen != null) {
    bloc.add(WorkOrdersOrgUnitFilterSelected(orgUnitId: chosen.id, orgUnitName: chosen.name));
  }
}

class _OrgUnitFilterDialog extends StatelessWidget {
  const _OrgUnitFilterDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Narrow to an Org Unit'),
      content: SizedBox(
        width: 480,
        child: OrgUnitChooser(
          selectedId: null,
          onSelected: (node) => Navigator.of(context).pop(node),
          // The filter is scoped to the Site the list is already showing —
          // browsing a different Site's tree from inside it would let the
          // header end up naming an Org Unit outside that Site.
          showSitePicker: false,
          title: 'Narrow the list',
          description: 'Choose the Org Unit to narrow the list to. Everything beneath it is '
              'included too.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrdersScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: WorkOrdersScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Work order list, laid out one of two ways depending on this Screen's
/// own *content* width, read off a `LayoutBuilder` rather than
/// `MediaQuery.sizeOf(context).width` (issue #104, Decision E; measured
/// correctly since issue #105 — see [WorkOrdersScreen.narrowBreakpoint]'s
/// own doc comment for why the window was never the right thing to ask) —
/// never a third, horizontally-scrolling shape:
///
/// - At or above [WorkOrdersScreen.narrowBreakpoint] (800px of content): a
///   table —
///   a header row of column labels, then one `Row` of cells per Work order,
///   built from `Expanded`/`Flexible` cells with `TextOverflow.ellipsis`,
///   sized so it never needs to scroll sideways. Deliberately not Flutter's
///   `DataTable`: its default is a horizontally-scrolling
///   `SingleChildScrollView`, which is exactly the shape this ticket bans at
///   every width, not only below the breakpoint.
/// - Below it: one card per Work order, carrying at minimum the Work order
///   number, summary, Asset, Org Unit, status and the single primary action
///   — issue #104's own floor. The assignee stays too, since #99's own wide
///   layout already shows it and there is no reason to drop it narrow, and
///   so does the overflow (Assign/Reassign, Cancel), same trigger and same
///   keys as the wide layout.
///
/// Both shapes key their outer widget with [WorkOrdersScreen.rowKey], so a
/// test written against one Work order's row does not need to know which
/// layout is rendering it.
class _WorkOrdersList extends StatelessWidget {
  const _WorkOrdersList({required this.workOrders, required this.canAssign, required this.canWork});

  final List<WorkOrder> workOrders;

  /// The per-Org-Unit write check [WorkOrdersScreen.canAssignWorkOrder]
  /// carries — applied to each row's own Org Unit here, once, rather than
  /// once for the whole Screen.
  final bool Function(String orgUnitId) canAssign;
  final bool canWork;

  @override
  Widget build(BuildContext context) {
    // `constraints.maxWidth` — the box this Screen actually got from its own
    // parent — not `MediaQuery.sizeOf(context).width`, the whole browser
    // window (issue #105). This Screen always renders inside the Shell's
    // content area, never the full window: at exactly 700px of *window*,
    // `PlatformShell`'s own rail breakpoint (`shell.dart`, frozen by #99's
    // own Implementation Decisions, not touched here) has just switched to
    // its 260px expanded sidebar, leaving only 440px of actual content — so
    // measuring the window told this Screen it had 700px when it truly had
    // 440, and it chose the table on that false premise. A `LayoutBuilder`
    // reads the real number instead, so [WorkOrdersScreen.narrowBreakpoint]
    // keeps meaning what its own doc comment says: content width, not window
    // width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < WorkOrdersScreen.narrowBreakpoint;
        return Center(
          child: AppPageFrame(
            maxWidth: WorkOrdersScreen.maxWidth,
            child: narrow
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    itemCount: workOrders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) => _WorkOrderCard(
                      workOrder: workOrders[index],
                      canAssign: canAssign(workOrders[index].orgUnitId),
                      canWork: canWork,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                    children: [
                      const _WorkOrderTableHeader(),
                      for (final workOrder in workOrders)
                        _WorkOrderTableRow(
                          workOrder: workOrder,
                          canAssign: canAssign(workOrder.orgUnitId),
                          canWork: canWork,
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// The wide table's own fixed width for its trailing actions column — wide
/// enough for one primary button plus the overflow trigger side by side,
/// shared between [_WorkOrderTableHeader]'s spacer and every
/// [_WorkOrderTableRow]'s own actions cell so the columns before it stay
/// aligned regardless of which row does or does not offer a primary button.
const double _actionsColumnWidth = 232;

/// The wide table's own fixed width for its Status column (issue #105) —
/// sized to whichever of [WorkOrder.knownStatusLabels] paints widest under
/// the `Chip`'s own Material 3 default label style (`textTheme.labelLarge`,
/// `chip.dart`'s own `_ChipDefaultsM3.labelStyle`), plus that `Chip`'s own
/// horizontal chrome at text scale 1 (`padding`: 8px each side; default
/// `labelPadding`: 8px each side — both from `chip.dart`'s own defaults),
/// with a further buffer on top rather than the exact figure.
///
/// This replaced an `Expanded(flex: 2)` cell that clipped "Approved" at the
/// chip's own right edge — a `Chip` clips its label rather than overflowing
/// loudly, so nothing here ever threw and no widget test caught it before a
/// golden did (issue #105). A fixed width tied to the actual label set,
/// rather than a bigger flex number tuned to fit today's longest label
/// ("In progress"), keeps a later status added to `work_order.dart`'s own
/// label map sized correctly without anyone needing to remember to also
/// widen a column.
///
/// Shared between [_WorkOrderTableHeader]'s own label cell and every
/// [_WorkOrderTableRow]'s own status cell, the same way [_actionsColumnWidth]
/// already is, so the columns after Status stay aligned between rows.
double _statusColumnWidth(BuildContext context) {
  final style = Theme.of(context).textTheme.labelLarge;
  final direction = Directionality.of(context);
  final painter = TextPainter(textDirection: direction);
  var widest = 0.0;
  for (final label in WorkOrder.knownStatusLabels) {
    painter.text = TextSpan(text: label, style: style);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + 32 + Spacing.sm;
}

class _WorkOrderTableHeader extends StatelessWidget {
  const _WorkOrderTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The header reads as a header (issue #168) by spending two things the
    // data rows do not: a band behind it, and weight on its labels. The
    // labels were `onSurfaceVariant` in `labelMedium` — the same colour and
    // size as the metadata in the rows below, separated from them by one
    // hairline, which is why the row read as a fifth row of data.
    //
    // Sentence case and 12px are kept deliberately: uppercasing is the
    // Shell's own Destination-group device (`_GroupHeading`), and the column
    // names are the domain's words ("WO#", "Org Unit"), not decoration. The
    // hairline under the band is the same `outlineVariant` every row's own
    // bottom border uses, so the table still reads as one table.
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    Widget label(String text, int flex) => Expanded(flex: flex, child: Text(text, style: style));
    return Container(
      decoration: BoxDecoration(
        color: AppComponentColors.tableHeaderFill,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        children: [
          label('WO#', 2),
          label('Summary', 4),
          label('Asset', 4),
          label('Org Unit', 2),
          SizedBox(width: _statusColumnWidth(context), child: Text('Status', style: style)),
          label('Assignee', 3),
          SizedBox(width: _actionsColumnWidth, child: Text('Actions', style: style)),
        ],
      ),
    );
  }
}

class _WorkOrderTableRow extends StatelessWidget {
  const _WorkOrderTableRow({required this.workOrder, required this.canAssign, required this.canWork});

  final WorkOrder workOrder;
  final bool canAssign;
  final bool canWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<WorkOrdersBloc>().state;
    final busy = state is WorkOrdersLoaded && (state.isAssigning || state.isTransitioning);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    // `disclose` covers the two cells whose values are genuinely unbounded —
    // an Asset's name and code, and an Assignee's name — so a clipped value
    // can still be read in full (issue #168, `DisclosingText`). The other
    // cells hold values this Screen's own schema bounds (a Work order number,
    // a status label, an Org Unit name that the column split now fits), so
    // wrapping them too would put a tooltip on every cell of every row for no
    // reason.
    Widget cell(String text, int flex, {TextStyle? style, bool disclose = false}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: disclose
                ? DisclosingText(text, style: style)
                : Text(text, overflow: TextOverflow.ellipsis, style: style),
          ),
        );

    return Container(
      key: WorkOrdersScreen.rowKey(workOrder.id),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: InkWell(
        key: WorkOrdersScreen.detailsKey(workOrder.id),
        onTap: () => context.go('${Routes.workOrders}/${workOrder.id}'),
        // A deliberate highlight rather than Material's own faint default
        // (issue #168) — see [AppComponentColors.rowHoverFill]. Set here, on
        // this row, rather than globally on `ThemeData.hoverColor`: the reason
        // a row needs to be trackable is that this row is seven columns wide,
        // and nothing about the rest of the Platform's InkWells follows from
        // it.
        hoverColor: AppComponentColors.rowHoverFill,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            cell(workOrder.workOrderNo, 2, style: muted),
            cell(workOrder.summary, 4, style: theme.textTheme.bodyMedium),
            // Asset and Assignee each hold one more share of the table than
            // they did before (issue #168): 3→4 and 2→3. These are the two
            // cells whose values are unbounded, and both used to ellipsize in
            // ordinary use ("Press 1 (PRESS-…", "Unassign…"). The two that
            // clip nothing — the Work order number, which the Site's own
            // sequence bounds, and the Org Unit name — keep what they had, and
            // Summary is unchanged at 4 rather than being raided to pay for
            // the rest.
            cell('${workOrder.assetName} (${workOrder.assetCode}) · ${workOrder.workTypeLabel}', 4,
                style: muted, disclose: true),
            cell(workOrder.orgUnitName, 2, style: muted),
            SizedBox(
              width: _statusColumnWidth(context),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(
                  label: workOrder.statusLabel,
                  tone: workOrder.statusTone,
                ),
              ),
            ),
            cell(workOrder.assigneeName ?? 'Unassigned', 3, style: theme.textTheme.bodyMedium,
                disclose: true),
            SizedBox(
              width: _actionsColumnWidth,
              child:
                  _RowActions(workOrder: workOrder, canAssign: canAssign, canWork: canWork, busy: busy),
            ),
          ],
        ),
      ),
    );
  }
}

/// The narrow (<800px of content) card — one Work order's number, summary,
/// Asset, Org Unit, status, assignee and actions stacked vertically, issue
/// #104's own floor for the narrow layout (see `_WorkOrdersList`'s own
/// header).
class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.workOrder, required this.canAssign, required this.canWork});

  final WorkOrder workOrder;
  final bool canAssign;
  final bool canWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<WorkOrdersBloc>().state;
    final busy = state is WorkOrdersLoaded && (state.isAssigning || state.isTransitioning);

    return Card(
      key: WorkOrdersScreen.rowKey(workOrder.id),
      margin: EdgeInsets.zero,
      child: InkWell(
        key: WorkOrdersScreen.detailsKey(workOrder.id),
        onTap: () => context.go('${Routes.workOrders}/${workOrder.id}'),
        // The same deliberate highlight the wide row carries (issue #168): a
        // card is one Work order and its actions sit at the bottom of it, so
        // the pointer needs the same help staying with the card it started on.
        hoverColor: AppComponentColors.rowHoverFill,
        child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
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
                      Text(
                        workOrder.workOrderNo,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(workOrder.summary, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${workOrder.assetName} (${workOrder.assetCode}) · ${workOrder.workTypeLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                StatusChip(
                  label: workOrder.statusLabel,
                  tone: workOrder.statusTone,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                // Never a blank when nobody has it yet — "Unassigned" says so
                // plainly, the contract issue #57 sets for a null assignee.
                Text(workOrder.assigneeName ?? 'Unassigned', style: theme.textTheme.bodyMedium),
                const SizedBox(width: Spacing.lg),
                Icon(Icons.account_tree_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    workOrder.orgUnitName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _RowActions(workOrder: workOrder, canAssign: canAssign, canWork: canWork, busy: busy),
          ],
        ),
        ),
      ),
    );
  }
}

/// One row's own actions (issue #104, Decision C): at most one primary
/// button — the next *status* transition this row offers, if any — plus one
/// overflow trigger holding everything else that applies to it. Shared
/// between the wide table row and the narrow card so both layouts offer
/// exactly the same actions through exactly the same keys.
///
/// - **Primary** (inline `OutlinedButton`): [offersStart] → "Start", which
///   dispatches straight to the Bloc with no dialog and no address (there is
///   nothing to confirm); [offersComplete] → "Complete", which navigates to
///   its own address. Any other status offers no primary button — a row
///   reachable only through history is terminal.
/// - **Overflow** (kebab `IconButton`, opened with [showMenu] rather than a
///   `PopupMenuButton`, so its own `onPressed` is a real, directly
///   assertable field — see [WorkOrdersScreen.rowActionsKey]'s own doc
///   comment for why a test reads *that* rather than reaching into a menu
///   that is not open): Assign/Reassign when [canAssign] (regardless of
///   status, matching this Screen's own pre-#104 behaviour), and Cancel when
///   [canWork] and [offersCancel]. Both navigate to their own address.
///
/// [busy] — an assign or a transition in flight anywhere on the Screen —
/// disables the primary button and the overflow trigger itself, so a second
/// write cannot even be started while the first is still settling.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.workOrder,
    required this.canAssign,
    required this.canWork,
    required this.busy,
  });

  final WorkOrder workOrder;
  final bool canAssign;
  final bool canWork;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final status = workOrder.status;
    final items = <_RowOverflowItem>[
      if (canAssign)
        _RowOverflowItem(
          key: WorkOrdersScreen.assignKey(workOrder.id),
          label: workOrder.assignedTo == null ? 'Assign' : 'Reassign',
          onSelected: () => context.go('${Routes.workOrders}/${workOrder.id}/assign'),
        ),
      if (canWork && offersCancel(status))
        _RowOverflowItem(
          key: WorkOrdersScreen.cancelKey(workOrder.id),
          label: 'Cancel',
          onSelected: () => context.go('${Routes.workOrders}/${workOrder.id}/cancel'),
        ),
    ];

    Widget? primary;
    if (canWork && offersStart(status)) {
      primary = OutlinedButton(
        key: WorkOrdersScreen.startKey(workOrder.id),
        onPressed:
            busy ? null : () => context.read<WorkOrdersBloc>().add(WorkOrderStartConfirmed(workOrder.id)),
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        child: const Text('Start'),
      );
    } else if (canWork && offersComplete(status)) {
      primary = OutlinedButton(
        key: WorkOrdersScreen.completeKey(workOrder.id),
        onPressed: busy ? null : () => context.go('${Routes.workOrders}/${workOrder.id}/complete'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        child: const Text('Complete'),
      );
    }

    if (primary == null && items.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?primary,
        if (primary != null && items.isNotEmpty) const SizedBox(width: Spacing.sm),
        if (items.isNotEmpty)
          _RowOverflowButton(workOrderId: workOrder.id, items: items, enabled: !busy),
      ],
    );
  }
}

/// One entry in a row's overflow menu (issue #104) — a [key] so a test can
/// find it once the menu is open, a [label], and what happens when it is
/// chosen.
class _RowOverflowItem {
  const _RowOverflowItem({required this.key, required this.label, required this.onSelected});

  final Key key;
  final String label;
  final VoidCallback onSelected;
}

/// The kebab trigger a row's overflow menu opens from (issue #104). A plain
/// `IconButton` driving [showMenu] directly, rather than `PopupMenuButton`
/// wrapping it: `PopupMenuButton` exposes only an `enabled` flag, and
/// [WorkOrdersScreen.rowActionsKey]'s own contract is that a test can read
/// this trigger's `onPressed` field directly to prove it is disabled while
/// busy, the same shape every other disabled control on this Screen already
/// carries.
class _RowOverflowButton extends StatelessWidget {
  const _RowOverflowButton({required this.workOrderId, required this.items, required this.enabled});

  final String workOrderId;
  final List<_RowOverflowItem> items;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: WorkOrdersScreen.rowActionsKey(workOrderId),
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert),
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      onPressed: enabled ? () => _open(context) : null,
    );
  }

  Future<void> _open(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selectedKey = await showMenu<Key>(
      context: context,
      position: position,
      items: [
        for (final item in items)
          PopupMenuItem<Key>(key: item.key, value: item.key, child: Text(item.label)),
      ],
    );
    if (selectedKey == null) return;
    for (final item in items) {
      if (item.key == selectedKey) {
        item.onSelected();
        return;
      }
    }
  }
}

/// The two empty stories issue #103 asks this Screen to tell apart — see
/// `PlatformEmptyState`'s own header for the general reasoning, and this
/// class for the worked example the ticket names.
class _WorkOrdersEmpty extends StatelessWidget {
  const _WorkOrdersEmpty({
    required this.orgUnitFilterId,
    required this.orgUnitFilterName,
    required this.showHistory,
    required this.canRaiseWorkOrder,
  });

  /// The Org Unit the list is narrowed to, or null for the whole Site. Its
  /// presence, not [showHistory], is what decides which of the two empty
  /// stories this is: a filter can matched-nothing, but broadening the read
  /// with "Show completed and cancelled" on an unfiltered, genuinely-empty
  /// Site is still "nothing exists", not "nothing matched" — there is no
  /// filter for a caller to clear in that case.
  final String? orgUnitFilterId;
  final String? orgUnitFilterName;

  /// Whether the list is currently showing completed and cancelled Work
  /// orders too (issue #63) — "No open work" is wrong once the caller has
  /// asked to see everything and there is still nothing at all.
  final bool showHistory;

  /// Same coarse signal `_Header`'s own raise button reads — whether this
  /// caller holds a write Grant anywhere at all. Read again here rather than
  /// shared through the header: the empty state carries its own action per
  /// #103's own requirement ("it carries the action that resolves it"), on
  /// top of — not instead of — the persistent one in the header.
  final bool canRaiseWorkOrder;

  @override
  Widget build(BuildContext context) {
    if (orgUnitFilterId != null) {
      return PlatformEmptyState.noneMatched(
        key: WorkOrdersScreen.emptyFilteredKey,
        title: 'No work orders match',
        message: 'There is work at this Site, but none of it is raised at '
            '${orgUnitFilterName ?? 'this Org Unit'} or beneath it'
            '${showHistory ? '' : ' and still open'}.',
        actionLabel: 'Clear filters',
        actionKey: WorkOrdersScreen.emptyClearFiltersKey,
        onAction: () => context.read<WorkOrdersBloc>().add(const WorkOrdersOrgUnitFilterCleared()),
      );
    }

    final state = context.watch<WorkOrdersBloc>().state;
    final loaded = state is WorkOrdersLoaded ? state : null;
    return PlatformEmptyState.noneExist(
      key: WorkOrdersScreen.emptyKey,
      title: showHistory ? 'No work at this Site' : 'No open work at this Site',
      message: 'Nothing has been raised against the Org Units you can act in. Raise a '
          'Work order and it will show up right away.',
      actionLabel: canRaiseWorkOrder && loaded?.siteId != null ? 'Raise a Work order' : null,
      actionKey: WorkOrdersScreen.emptyRaiseKey,
      onAction: canRaiseWorkOrder && loaded?.siteId != null
          ? () => context.go('${Routes.workOrders}/new')
          : null,
    );
  }
}
