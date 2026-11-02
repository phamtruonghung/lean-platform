/// Home: a role-scoped "your work" surface (issue #101), replacing the
/// placeholder this file used to admit it was — a green tick and "Welcome,
/// {name}", proving only that the authenticated path worked.
///
/// This is **not** the tier board. #76 owns KPI Screens — Pillars, MTBF,
/// availability, anything calculated as a measurement over time. Every card
/// here is a bare count plus a link into a Destination the Account already
/// earns (`destinationsFor`, platform/destinations.dart); nothing here shows
/// a trend, a target, or a Pillar heading. If a card ever wants one, it
/// belongs to #76, not here.
///
/// Reads no endpoint no other Screen already reads, and guards no route no
/// other Screen already guards: [HomeBloc] reuses exactly the reads
/// `WorkOrdersBloc` and `ApprovalQueueBloc` already make, and every card's
/// role gate mirrors the same role set `router.dart` already checks before
/// letting that Destination's own route through.
///
/// **The cards are one grid per Module (issue #188, regrouped by #395).**
/// Before #188 each of the three sections rendered its own `Wrap` of fixed
/// 260px cards, so an administrator's four cards arrived as one card, then two,
/// then one — a ragged grid with most of a row empty twice. #188 made them one
/// grid of equal cells, two columns on a wide page and one on a narrow one, but
/// left the five cards in one undifferentiated block. #395 groups them by the
/// Module that owns each card's Destination, in the order the cards already
/// had: **Actions** (what is assigned to you), **Maintenance** (the Work order
/// pair) and **People** (Accounts awaiting Approval, Training to confirm). The
/// grouping is by Module because that is what the cards already are — one
/// Destination each, and a Destination already belongs to a Module — so the
/// headings add no new vocabulary to the page. Within a group the cells are
/// the same grid #188 built; a section that cannot be read still says so across
/// its own group rather than taking the Screen with it.
///
/// **Identity (issues #375 and #395).** Home was the Screen with the least of
/// it: a greeting, a line of small print and four identical boxes. It now sets
/// its title in the shared `AppPageHeader` — the greeting as the Screen's
/// title, `email · role` as its description, the header's own hairline under
/// both — and each card is an `AppStatTile`, the primitive lifted out of this
/// file in #386: an icon tile, the label, the count at the top of the pinned
/// type scale, the caption, and a chevron that says the whole tile is a link.
/// A count of zero is deliberately quieter than a real one. This file's
/// private `_HomeCard` is gone; `AppStatTile` was lifted from it and is
/// byte-identical in behaviour, which is why the geometry and focus tests in
/// `home_test.dart` still hold.
///
/// **The zero state (issue #395).** When every section this role earns has
/// loaded and every count is zero, the page says so in one line under the
/// header — "Nothing is waiting on you." — rather than leaving a reader to add
/// up five quiet zeros. The tiles stay: the counts and the links are still the
/// page's purpose, and a person with nothing waiting still wants to know which
/// pages they can reach. The line is only drawn once every section has loaded;
/// a section still in flight, or one that failed, says its own thing instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'home_bloc.dart';
import 'people_api.dart';
import 'platform/router.dart';
import 'theme.dart';
import 'widgets/app_page_frame.dart';
import 'widgets/app_page_header.dart';
import 'widgets/app_stat_tile.dart';
import 'widgets/failure_state.dart';
import 'widgets/skeleton_list.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.account});

  final AccountActive account;

  static const double maxWidth = 900;

  /// The header's hairline (issue #375). The rule is now `AppPageHeader`'s own,
  /// which is the same `Divider` at the same left edge; the name is kept so the
  /// key every test and reader knows still finds it.
  static const ValueKey<String> headerRuleKey = AppPageHeader.ruleKey;

  /// The one line that says nothing is waiting (issue #395).
  static const ValueKey<String> nothingWaitingKey = ValueKey<String>('home-nothing-waiting');

  /// One Module's heading over its group of tiles.
  static ValueKey<String> groupKey(String module) => ValueKey<String>('home-group-$module');

  static const ValueKey<String> openWorkOrdersCardKey = ValueKey<String>('home-open-work-orders');
  static const ValueKey<String> unassignedCardKey = ValueKey<String>('home-unassigned-work-orders');
  static const ValueKey<String> approvalsCardKey = ValueKey<String>('home-approvals');
  static const ValueKey<String> myActionsCardKey = ValueKey<String>('home-my-actions');
  static const ValueKey<String> trainingToConfirmCardKey = ValueKey<String>('home-training-to-confirm');
  static const ValueKey<String> trainingToConfirmRetryKey = ValueKey<String>('home-training-to-confirm-retry');
  static const ValueKey<String> workRetryKey = ValueKey<String>('home-work-retry');
  static const ValueKey<String> approvalsRetryKey = ValueKey<String>('home-approvals-retry');
  static const ValueKey<String> myActionsRetryKey = ValueKey<String>('home-my-actions-retry');

  /// What the page says when every count it shows is zero.
  static const String nothingWaiting = 'Nothing is waiting on you.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          return switch (state) {
            // The whole-Screen placeholder only ever shows for the one frame
            // before HomeStarted settles which sections this role earns
            // (issue #103) — after that, loading is per-section, below. Its
            // four tiles over two columns are the shape the settled page takes
            // for the role that sees most (issue #188).
            HomeLoading() => const SkeletonGrid(tiles: 4, crossAxisCount: 2, maxWidth: maxWidth),
            HomeReady() => _HomeBody(account: account, state: state),
          };
        },
      ),
    );
  }
}

/// One Module's share of Home: its heading and the cells beneath it.
class _ModuleGroup {
  const _ModuleGroup({required this.name, required this.cells});

  final String name;
  final List<Widget> cells;
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.account, required this.state});

  final AccountActive account;
  final HomeReady state;

  /// The groups this role earns, in the order the cards have always had: what
  /// is assigned to *you* first (the one card a person is personally on the
  /// hook for, and the reason most people open Home at all), then the Work
  /// order pair, then the People pair. A Module with no section read for this
  /// role contributes no group at all rather than an empty heading.
  List<_ModuleGroup> _groups(BuildContext context) => [
        if (state.myActions != null)
          _ModuleGroup(name: 'Actions', cells: _myActionsCells(context, state.myActions!)),
        if (state.workSummary != null)
          _ModuleGroup(name: 'Maintenance', cells: _workSummaryCells(context, state.workSummary!)),
        if (state.approvals != null || state.trainingToConfirm != null)
          _ModuleGroup(
            name: 'People',
            cells: [
              if (state.approvals != null) ..._approvalsCells(context, state.approvals!),
              if (state.trainingToConfirm != null)
                ..._trainingToConfirmCells(context, state.trainingToConfirm!),
            ],
          ),
      ];

  /// Whether every number the page shows is zero *and* every section has
  /// loaded. A section still in flight, or one that failed, answers false: the
  /// page cannot claim nothing is waiting while it does not know.
  bool get _everythingZero {
    var sawOne = false;
    for (final count in [
      if (state.myActions != null) _countOf(state.myActions, (d) => d.openCount),
      if (state.workSummary != null)
        _countOf(state.workSummary, (d) => d.openCount + d.unassignedCount),
      if (state.approvals != null) _countOf(state.approvals, (d) => d),
      if (state.trainingToConfirm != null) _countOf(state.trainingToConfirm, (d) => d),
    ]) {
      if (count == null || count != 0) return false;
      sawOne = true;
    }
    return sawOne;
  }

  /// A section's own number, or null while it is loading or has failed.
  static int? _countOf<T>(HomeSectionState<T>? section, int Function(T data) count) =>
      switch (section) {
        HomeSectionLoaded<T>(:final data) => count(data),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final groups = _groups(context);
    return Center(
      child: AppPageFrame(
        maxWidth: HomeScreen.maxWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The Screen's title, in the shared header: the greeting as the
              // title (`headlineSmall`, a real header to a screen reader), the
              // Account's own `email · role` under it, and the header's hairline
              // under both — the same left edge for all three.
              AppPageHeader(
                title: 'Welcome, ${account.displayName}',
                description: '${account.email} · ${account.role}',
              ),
              const SizedBox(height: Spacing.lg),
              if (_everythingZero) ...[
                Text(
                  HomeScreen.nothingWaiting,
                  key: HomeScreen.nothingWaitingKey,
                  style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: Spacing.lg),
              ],
              for (var index = 0; index < groups.length; index++) ...[
                if (index > 0) const SizedBox(height: Spacing.xl),
                _GroupHeading(name: groups[index].name),
                const SizedBox(height: Spacing.md),
                _CardGrid(cells: groups[index].cells),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A Module's name over its own group of tiles: `titleSmall` at w600 in
/// `textMuted` (14px, the Dense body's own size, so no heading here outgrows
/// the text under it — #367's 1.3x rule), sentence case. Uppercase is the
/// Shell's Destination-group device and is deliberately not repeated inside a
/// page.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        name,
        key: HomeScreen.groupKey(name),
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.of(context).textMuted),
      ),
    );
  }
}

/// What is assigned to the caller: open Actions whose owner is their own
/// Employee record (issue #185).
///
/// One card, and three stories it has to tell apart: a count, a failure of its
/// own read, and the Account that cannot be assigned anything at all because
/// it carries no Employee link. The last is why this is not simply a count —
/// "0" and "nothing can be assigned to you" look the same in a number and mean
/// very different things to the person reading it.
List<Widget> _myActionsCells(BuildContext context, HomeSectionState<HomeMyActions> section) {
  return switch (section) {
    HomeSectionLoading<HomeMyActions>() => [
        const _SpanningCell(
          child: SkeletonGrid(
            tiles: 1,
            crossAxisCount: _CardGrid.wideColumns,
            maxWidth: HomeScreen.maxWidth,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    HomeSectionFailed<HomeMyActions>(:final isScopeRefused, :final message) => [
        _SpanningCell(
          child: isScopeRefused
              ? const PlatformScopeRefusedState()
              : PlatformFailureState(
                  title: 'Your Actions are unavailable',
                  message: message,
                  retryKey: HomeScreen.myActionsRetryKey,
                  onRetry: () => context.read<HomeBloc>().add(const HomeMyActionsRetried()),
                ),
        ),
      ],
    HomeSectionLoaded<HomeMyActions>(:final data) => [
        _HomeCard(
          cardKey: HomeScreen.myActionsCardKey,
          icon: Icons.assignment_ind_outlined,
          label: 'Assigned to you',
          count: data.openCount,
          caption: data.hasEmployeeLink
              ? 'Open Actions whose owner is you'
              : 'Your Account is not linked to an Employee record, so no Action can be '
                  'assigned to you — link one under Accounts',
          destination: Routes.actions,
        ),
      ],
  };
}

/// The Training records sent to the caller and not yet answered (issue #289):
/// a bare count that carries to `/training/to-confirm`, where the answers are
/// given. Every role earns it — any approved Account may be a Trainee.
List<Widget> _trainingToConfirmCells(BuildContext context, HomeSectionState<int> section) {
  return switch (section) {
    HomeSectionLoading<int>() => [
        const _SpanningCell(
          child: SkeletonGrid(
            tiles: 1,
            crossAxisCount: _CardGrid.wideColumns,
            maxWidth: HomeScreen.maxWidth,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    HomeSectionFailed<int>(:final isScopeRefused, :final message) => [
        _SpanningCell(
          child: isScopeRefused
              ? const PlatformScopeRefusedState()
              : PlatformFailureState(
                  title: 'Your Training to confirm is unavailable',
                  message: message,
                  retryKey: HomeScreen.trainingToConfirmRetryKey,
                  onRetry: () => context.read<HomeBloc>().add(const HomeTrainingToConfirmRetried()),
                ),
        ),
      ],
    HomeSectionLoaded<int>(:final data) => [
        _HomeCard(
          cardKey: HomeScreen.trainingToConfirmCardKey,
          icon: Icons.school_outlined,
          label: 'Training to confirm',
          count: data,
          caption: 'Training records sent to you that you have not answered',
          destination: Routes.trainingToConfirm,
        ),
      ],
  };
}

/// The maintenance-role section: open Work orders, and those still waiting
/// on an assignee within an Org Unit this Account holds a Grant on (issue
/// #101's own guidance). Both cards link to the same Destination —
/// `Routes.workOrders` offers no deep link into a pre-applied filter, so
/// this only carries a caller there, the way every other card here does.
List<Widget> _workSummaryCells(BuildContext context, HomeSectionState<HomeWorkSummary> section) {
  return switch (section) {
    HomeSectionLoading<HomeWorkSummary>() => [
        const _SpanningCell(
          child: SkeletonGrid(
            tiles: 2,
            crossAxisCount: _CardGrid.wideColumns,
            maxWidth: HomeScreen.maxWidth,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    HomeSectionFailed<HomeWorkSummary>(:final isScopeRefused, :final message) => [
        _SpanningCell(
          child: isScopeRefused
              ? const PlatformScopeRefusedState()
              : PlatformFailureState(
                  title: 'Work orders are unavailable',
                  message: message,
                  retryKey: HomeScreen.workRetryKey,
                  onRetry: () => context.read<HomeBloc>().add(const HomeWorkSummaryRetried()),
                ),
        ),
      ],
    HomeSectionLoaded<HomeWorkSummary>(:final data) => [
        _HomeCard(
          cardKey: HomeScreen.openWorkOrdersCardKey,
          icon: Icons.build_outlined,
          label: 'Open work orders',
          count: data.openCount,
          caption: 'Raised and not yet complete',
          destination: Routes.workOrders,
        ),
        _HomeCard(
          cardKey: HomeScreen.unassignedCardKey,
          icon: Icons.person_off_outlined,
          label: 'Awaiting assignment',
          count: data.unassignedCount,
          // Issue #110 (ADR-0027): the count now includes Work orders
          // anywhere beneath a granted Org Unit, because `/me` reports each
          // Grant's whole reach — so the old "not what sits beneath them"
          // caveat is no longer true and must go. The wording still differs
          // from an administrator's: a scoped Account's number is complete
          // across its Grants, not across the Site, and the card says so.
          caption: data.unassignedScopedToGrants
              ? 'On the Org Units granted to you, and everything beneath them'
              : 'Open, with nobody holding them yet',
          destination: Routes.workOrders,
        ),
      ],
  };
}

/// The People Module's approvals section: Accounts nobody has decided about
/// yet (administrators only).
List<Widget> _approvalsCells(BuildContext context, HomeSectionState<int> section) {
  return switch (section) {
    HomeSectionLoading<int>() => [
        const _SpanningCell(
          child: SkeletonGrid(
            tiles: 1,
            crossAxisCount: _CardGrid.wideColumns,
            maxWidth: HomeScreen.maxWidth,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    HomeSectionFailed<int>(:final isScopeRefused, :final message) => [
        _SpanningCell(
          child: isScopeRefused
              ? const PlatformScopeRefusedState()
              : PlatformFailureState(
                  title: 'Approvals are unavailable',
                  message: message,
                  retryKey: HomeScreen.approvalsRetryKey,
                  onRetry: () => context.read<HomeBloc>().add(const HomeApprovalsRetried()),
                ),
        ),
      ],
    HomeSectionLoaded<int>(:final data) => [
        _HomeCard(
          cardKey: HomeScreen.approvalsCardKey,
          icon: Icons.how_to_reg_outlined,
          label: 'Accounts awaiting Approval',
          count: data,
          caption: 'Waiting to be admitted',
          destination: Routes.approvals,
        ),
      ],
  };
}

/// The one grid a Module group's cards are laid out in (issue #188).
///
/// **Two columns on a wide page, one on a narrow one.** [wideColumns] is spent
/// when the box this grid actually receives reaches [twoColumnWidth] *at the
/// reader's text scale* (`AppBreakpoints.effective`), which is the point below
/// which a card's own context line starts wrapping to three lines. Reading the
/// box's width rather than the window's is deliberate: it is the same input
/// `WorkOrdersScreen` reads (its own `narrowBreakpoint` doc comment has the full
/// account of what reading the window instead cost), and the Shell's rail
/// breakpoint is a fact about the window, not about the space this body has.
/// **The text scale is counted as of #395**: at 200% text the same box holds
/// half the words, so the grid drops to one column sooner rather than squeezing
/// two cards past legibility (the class of bug #379 and #381).
///
/// **Every row is full.** The cells are chunked into rows of [wideColumns] and
/// each row is an `Expanded`-per-cell `Row`, so no row is ever partly filled —
/// a `Wrap` of sized children, which is what this replaced, cannot stretch a
/// run, which is exactly how a section with one card left two thirds of a row
/// empty. A cell of [_SpanningCell] takes a row of its own.
///
/// **A row's cards share one height.** The `Row` sits inside an `IntrinsicHeight`
/// with `CrossAxisAlignment.stretch`, so a card whose context line wraps to two
/// lines does not leave its neighbour floating above a ragged bottom edge. The
/// cost is one extra layout pass over at most [wideColumns] children — which is
/// why `IntrinsicHeight` is affordable here and would not be on a long list.
/// A spanning cell is never put through it: what it carries (a skeleton grid, a
/// failure state) is alone in its row, and a scrollable viewport has no
/// intrinsic height to ask for.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cells});

  /// How many columns a wide page gets. Named once, here, so the loading
  /// placeholders and the settled grid cannot disagree about it.
  static const int wideColumns = 2;

  /// The width of content at which [wideColumns] columns fit comfortably.
  static const double twoColumnWidth = 640;

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoWide = constraints.maxWidth >= AppBreakpoints.effective(context, twoColumnWidth);
        final columns = twoWide ? wideColumns : 1;
        final rows = <List<Widget>>[];
        var row = <Widget>[];
        for (final cell in cells) {
          if (cell is _SpanningCell) {
            if (row.isNotEmpty) {
              rows.add(row);
              row = <Widget>[];
            }
            rows.add([cell]);
            continue;
          }
          row.add(cell);
          if (row.length == columns) {
            rows.add(row);
            row = <Widget>[];
          }
        }
        if (row.isNotEmpty) rows.add(row);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++) ... [
              if (index > 0) const SizedBox(height: Spacing.md),
              _CardRow(cells: rows[index]),
            ],
          ],
        );
      },
    );
  }
}

/// One row of the grid: its cells side by side at equal width, and at equal
/// height when there is more than one of them (see [_CardGrid]).
class _CardRow extends StatelessWidget {
  const _CardRow({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    if (cells.length == 1) return cells.single;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cells.length; index++) ...[
            if (index > 0) const SizedBox(width: Spacing.md),
            Expanded(child: cells[index]),
          ],
        ],
      ),
    );
  }
}

/// A cell that takes the whole row rather than one column. A section that is
/// loading or has failed says so across its group, so its own placeholder or
/// failure keeps its place in the order without being squeezed into a column
/// beside cards that are fine.
class _SpanningCell extends StatelessWidget {
  const _SpanningCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// One card on Home: an `AppStatTile` pointed at a Destination.
///
/// The tile itself is `widgets/app_stat_tile.dart` — lifted from the private
/// class this file carried (#386) and adopted here in #395, so the shape has one
/// definition rather than two byte-similar ones. What this wrapper adds is the
/// only thing Home knows that the tile does not: a route string rather than a
/// callback, because a card states *where* it goes and Home is the only Screen
/// that renders these five links.
///
/// A null `destination` would mean the card is not a link at all; none of
/// Home's five is that, so the chevron and the pointer are always there.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.cardKey,
    required this.icon,
    required this.label,
    required this.count,
    required this.caption,
    required this.destination,
  });

  final Key cardKey;
  final IconData icon;
  final String label;
  final int count;

  /// The line of context under the count — `AppStatTile`'s own `caption`.
  final String caption;

  final String destination;

  @override
  Widget build(BuildContext context) {
    return AppStatTile(
      key: cardKey,
      icon: icon,
      label: label,
      figure: '$count',
      caption: caption,
      quiet: count == 0,
      onTap: () => context.go(destination),
    );
  }
}
