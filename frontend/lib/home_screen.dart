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
/// **The cards are one grid (issue #188).** Before this, each of the three
/// sections rendered its own `Wrap` of fixed 260px cards, so an administrator's
/// four cards arrived as one card, then two, then one — a ragged grid with most
/// of a row empty twice, and a grouping whose only cue was a 16px gap against
/// the 12px between cards. They are now one grid of equal cells, two columns on
/// a wide page and one on a narrow one, in section order: what is assigned to
/// you, then the work summary, then Approvals. The sections still read, fail and
/// load independently — a section that cannot be read says so across the grid
/// rather than taking the Screen with it — and nothing about a card's own
/// content, count or Destination changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'home_bloc.dart';
import 'people_api.dart';
import 'platform/router.dart';
import 'theme.dart';
import 'widgets/app_page_frame.dart';
import 'widgets/failure_state.dart';
import 'widgets/skeleton_list.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.account});

  final AccountActive account;

  static const double maxWidth = 900;

  static const ValueKey<String> openWorkOrdersCardKey = ValueKey<String>('home-open-work-orders');
  static const ValueKey<String> unassignedCardKey = ValueKey<String>('home-unassigned-work-orders');
  static const ValueKey<String> approvalsCardKey = ValueKey<String>('home-approvals');
  static const ValueKey<String> myActionsCardKey = ValueKey<String>('home-my-actions');
  static const ValueKey<String> workRetryKey = ValueKey<String>('home-work-retry');
  static const ValueKey<String> approvalsRetryKey = ValueKey<String>('home-approvals-retry');
  static const ValueKey<String> myActionsRetryKey = ValueKey<String>('home-my-actions-retry');

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

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.account, required this.state});

  final AccountActive account;
  final HomeReady state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: HomeScreen.maxWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome, ${account.displayName}', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text('${account.email} · ${account.role}', style: AppTypography.body(context)),
              const SizedBox(height: Spacing.xl),
              // What is assigned to *you* comes first: it is the one card on
              // this Screen a person is personally on the hook for, and the
              // reason most people open Home at all.
              //
              // The old no-cards empty state (#99 user story 6) is gone with
              // it: the Actions Destination carries no `roles` set (ADR-0032),
              // so every role that can reach Home earns this card and there is
              // no longer a role whose Home has nothing on it. An Account with
              // no work to show now reads "Assigned to you — 0", which says
              // more than "nothing is waiting on you" did.
              // No no-cards branch any more: it was #99 user story 6, and the
              // Actions card above retired it — every role that can reach Home
              // earns at least that one (`HomeReady.earnsNoCards` says so in
              // the negative).
              //
              // One grid, in section order (issue #188). The sections stay
              // separate reads — each contributes the cells it has — and a
              // section that is still loading or has failed contributes a cell
              // that spans the row, so one unavailable read never takes the
              // page's other cards with it.
              _CardGrid(
                cells: [
                  if (state.myActions != null) ..._myActionsCells(context, state.myActions!),
                  if (state.workSummary != null) ..._workSummaryCells(context, state.workSummary!),
                  if (state.approvals != null) ..._approvalsCells(context, state.approvals!),
                ],
              ),
            ],
          ),
        ),
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
          context_: data.hasEmployeeLink
              ? 'Open Actions whose owner is you'
              : 'Your Account is not linked to an Employee record, so no Action can be '
                  'assigned to you — link one under Accounts',
          destination: Routes.actions,
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
          context_: 'Raised and not yet complete',
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
          context_: data.unassignedScopedToGrants
              ? 'On the Org Units granted to you, and everything beneath them'
              : 'Open, with nobody holding them yet',
          destination: Routes.workOrders,
        ),
      ],
  };
}

/// The administrator-only section: Accounts nobody has decided about yet.
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
          context_: 'Waiting to be admitted',
          destination: Routes.approvals,
        ),
      ],
  };
}

/// The one grid Home's cards are laid out in (issue #188).
///
/// **Two columns on a wide page, one on a narrow one.** [wideColumns] is spent
/// when the box this grid actually receives is at least [twoColumnWidth] wide,
/// which is the point below which a card's own context line starts wrapping to
/// three lines. Reading the box's width rather than the window's is deliberate:
/// it is the same input `WorkOrdersScreen` reads (its own `narrowBreakpoint`
/// doc comment has the full account of what reading the window instead cost),
/// and the Shell's rail breakpoint is a fact about the window, not about the
/// space this body has.
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
        final columns = constraints.maxWidth >= twoColumnWidth ? wideColumns : 1;
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
            for (var index = 0; index < rows.length; index++) ...[
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
/// loading or has failed says so across the grid, so its own placeholder or
/// failure keeps its place in the order without being squeezed into a column
/// beside cards that are fine.
class _SpanningCell extends StatelessWidget {
  const _SpanningCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// One card: a label, a count, a line of context, and a link to the
/// Destination that serves it (issue #101's own shape) — never a trend, a
/// target or a percentage against a goal, which is #76's tier board.
///
/// **It fills the cell it is given (issue #188).** It used to be a fixed 260px
/// wide, which is what made a row of cards ragged in the first place. It is now
/// as wide as its row's cell and as tall as its row's tallest card; its own
/// content is unchanged, so the count sits directly under the label and the
/// context line under that.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.cardKey,
    required this.icon,
    required this.label,
    required this.count,
    required this.context_,
    required this.destination,
  });

  final Key cardKey;
  final IconData icon;
  final String label;
  final int count;
  final String context_;

  /// The Destination this card carries to, as a route. A card states where it
  /// goes rather than how, so the same card shape can serve any of them.
  final String destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: cardKey,
        onTap: () => context.go(destination),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.actionPrimary),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.dense(context)?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text('$count', style: theme.textTheme.headlineMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                context_,
                style: AppTypography.dense(context)?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
