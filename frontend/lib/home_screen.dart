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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'home_bloc.dart';
import 'people_api.dart';
import 'platform/router.dart';
import 'theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/failure_state.dart';
import 'widgets/skeleton_list.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.account});

  final AccountActive account;

  static const double maxWidth = 900;

  static const ValueKey<String> openWorkOrdersCardKey = ValueKey<String>('home-open-work-orders');
  static const ValueKey<String> unassignedCardKey = ValueKey<String>('home-unassigned-work-orders');
  static const ValueKey<String> approvalsCardKey = ValueKey<String>('home-approvals');
  static const ValueKey<String> workRetryKey = ValueKey<String>('home-work-retry');
  static const ValueKey<String> approvalsRetryKey = ValueKey<String>('home-approvals-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('home-empty');
  static const ValueKey<String> emptyDirectoryActionKey = ValueKey<String>('home-empty-directory');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          return switch (state) {
            // The whole-Screen placeholder only ever shows for the one frame
            // before HomeStarted settles which sections this role earns
            // (issue #103) — after that, loading is per-section, below.
            HomeLoading() => const SkeletonGrid(tiles: 3, crossAxisCount: 3, maxWidth: maxWidth),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: HomeScreen.maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome, ${account.displayName}', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text('${account.email} · ${account.role}', style: AppTypography.body(context)),
              const SizedBox(height: Spacing.xl),
              if (state.earnsNoCards)
                const _HomeEmpty()
              else ...[
                if (state.workSummary != null) _WorkSummarySection(section: state.workSummary!),
                if (state.workSummary != null && state.approvals != null) const SizedBox(height: Spacing.lg),
                if (state.approvals != null) _ApprovalsSection(section: state.approvals!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The no-cards case (#99 user story 6): an operator earns no Work orders
/// Destination and no Approvals, so there is nothing here to count. Still a
/// coherent Screen, never a blank one — offers the one Destination every
/// approved Account earns regardless of role (`destinationsFor`'s own
/// unconditional `Directory` entry, ADR-0009).
class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();

  @override
  Widget build(BuildContext context) {
    return PlatformEmptyState.noneExist(
      key: HomeScreen.emptyKey,
      title: 'Nothing is waiting on you',
      message: 'Your role carries no open work orders and no Approvals to decide. '
          'The Directory is still open to you, if you want to look around.',
      actionLabel: 'Open the Directory',
      actionKey: HomeScreen.emptyDirectoryActionKey,
      onAction: () => context.go(Routes.directory),
    );
  }
}

/// The maintenance-role section: open Work orders, and those still waiting
/// on an assignee within an Org Unit this Account holds a Grant on (issue
/// #101's own guidance). Both cards link to the same Destination —
/// `Routes.workOrders` offers no deep link into a pre-applied filter, so
/// this only carries a caller there, the way every other card here does.
class _WorkSummarySection extends StatelessWidget {
  const _WorkSummarySection({required this.section});

  final HomeSectionState<HomeWorkSummary> section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      HomeSectionLoading<HomeWorkSummary>() =>
        const SkeletonGrid(tiles: 2, crossAxisCount: 2, maxWidth: HomeScreen.maxWidth),
      HomeSectionFailed<HomeWorkSummary>(:final isScopeRefused, :final message) => isScopeRefused
          ? const PlatformScopeRefusedState()
          : PlatformFailureState(
              title: 'Work orders are unavailable',
              message: message,
              retryKey: HomeScreen.workRetryKey,
              onRetry: () => context.read<HomeBloc>().add(const HomeWorkSummaryRetried()),
            ),
      HomeSectionLoaded<HomeWorkSummary>(:final data) => Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            _HomeCard(
              cardKey: HomeScreen.openWorkOrdersCardKey,
              icon: Icons.build_outlined,
              label: 'Open work orders',
              count: data.openCount,
              context_: 'Raised and not yet complete',
              onTap: () => context.go(Routes.workOrders),
            ),
            _HomeCard(
              cardKey: HomeScreen.unassignedCardKey,
              icon: Icons.person_off_outlined,
              label: 'Awaiting assignment',
              count: data.unassignedCount,
              // A follow-up on #101, raised before this shipped: an Account
              // scoped to Grants only ever sees a Work order sitting exactly
              // on a granted Org Unit — `HomeWorkSummary.unassignedCount`'s
              // own doc comment has the full reasoning. The unscoped wording
              // below would tell that Account it is seeing every unassigned
              // Work order when it is not, so the card's own claim changes
              // with `unassignedScopedToGrants` rather than the count itself.
              context_: data.unassignedScopedToGrants
                  ? 'On the Org Units granted to you, not what sits beneath them'
                  : 'Open, with nobody holding them yet',
              onTap: () => context.go(Routes.workOrders),
            ),
          ],
        ),
    };
  }
}

/// The administrator-only section: Accounts nobody has decided about yet.
class _ApprovalsSection extends StatelessWidget {
  const _ApprovalsSection({required this.section});

  final HomeSectionState<int> section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      HomeSectionLoading<int>() =>
        const SkeletonGrid(tiles: 1, crossAxisCount: 1, maxWidth: HomeScreen.maxWidth),
      HomeSectionFailed<int>(:final isScopeRefused, :final message) => isScopeRefused
          ? const PlatformScopeRefusedState()
          : PlatformFailureState(
              title: 'Approvals are unavailable',
              message: message,
              retryKey: HomeScreen.approvalsRetryKey,
              onRetry: () => context.read<HomeBloc>().add(const HomeApprovalsRetried()),
            ),
      HomeSectionLoaded<int>(:final data) => Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            _HomeCard(
              cardKey: HomeScreen.approvalsCardKey,
              icon: Icons.how_to_reg_outlined,
              label: 'Accounts awaiting Approval',
              count: data,
              context_: 'Waiting to be admitted',
              onTap: () => context.go(Routes.approvals),
            ),
          ],
        ),
    };
  }
}

/// One card: a label, a count, a line of context, and a link to the
/// Destination that serves it (issue #101's own shape) — never a trend, a
/// target or a percentage against a goal, which is #76's tier board.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.cardKey,
    required this.icon,
    required this.label,
    required this.count,
    required this.context_,
    required this.onTap,
  });

  final Key cardKey;
  final IconData icon;
  final String label;
  final int count;
  final String context_;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          key: cardKey,
          onTap: onTap,
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
      ),
    );
  }
}
