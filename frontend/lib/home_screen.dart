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
              if (state.myActions != null) _MyActionsSection(section: state.myActions!),
              if (state.myActions != null && state.workSummary != null)
                const SizedBox(height: Spacing.lg),
              if (state.workSummary != null) _WorkSummarySection(section: state.workSummary!),
              if ((state.myActions != null || state.workSummary != null) &&
                  state.approvals != null)
                const SizedBox(height: Spacing.lg),
              if (state.approvals != null) _ApprovalsSection(section: state.approvals!),
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
class _MyActionsSection extends StatelessWidget {
  const _MyActionsSection({required this.section});

  final HomeSectionState<HomeMyActions> section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      HomeSectionLoading<HomeMyActions>() =>
        const SkeletonGrid(tiles: 1, crossAxisCount: 1, maxWidth: HomeScreen.maxWidth),
      HomeSectionFailed<HomeMyActions>(:final isScopeRefused, :final message) =>
        isScopeRefused
            ? const PlatformScopeRefusedState()
            : PlatformFailureState(
                title: 'Your Actions are unavailable',
                message: message,
                retryKey: HomeScreen.myActionsRetryKey,
                onRetry: () => context.read<HomeBloc>().add(const HomeMyActionsRetried()),
              ),
      HomeSectionLoaded<HomeMyActions>(:final data) => Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            _HomeCard(
              cardKey: HomeScreen.myActionsCardKey,
              icon: Icons.assignment_ind_outlined,
              label: 'Assigned to you',
              count: data.openCount,
              context_: data.hasEmployeeLink
                  ? 'Open Actions whose owner is you'
                  : 'Your Account is not linked to an Employee record, so no Action can be '
                      'assigned to you — link one under Accounts',
              onTap: () => context.go(Routes.actions),
            ),
          ],
        ),
    };
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
              // Issue #110 (ADR-0027): the count now includes Work orders
              // anywhere beneath a granted Org Unit, because `/me` reports each
              // Grant's whole reach — so the old "not what sits beneath them"
              // caveat is no longer true and must go. The wording still differs
              // from an administrator's: a scoped Account's number is complete
              // across its Grants, not across the Site, and the card says so.
              context_: data.unassignedScopedToGrants
                  ? 'On the Org Units granted to you, and everything beneath them'
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
