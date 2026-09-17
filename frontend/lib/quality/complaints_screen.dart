/// The customer complaint register (issue #214, CONTEXT.md's **Customer**): what
/// customers complained about at this Site, which Product it was, what it is
/// costing them to wait, and whether the complained-of product has been
/// controlled.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Non-conformance register, the Work order list and the Asset
/// register already follow (#55, ADR-0009). Recording is offered to everyone
/// too: the server is the real gate on where a complaint may be filed (an edit
/// Grant reaching that Org Unit), and hiding the button would gate an address
/// that answers a clean refusal with a sentence the caller can act on.
///
/// Both filters are read filters over the already-visible register and send a
/// request rather than hiding rows client-side — the status and the Org Unit
/// are what the ticket names, and the Org Unit one includes everything
/// *beneath* the chosen area, which is the server's ltree walk rather than a
/// filter this client applies.
///
/// A row that is past the day the customer was promised an answer says so on
/// its own face: the server marks it ([CustomerComplaint.isOverdue]) and the
/// row renders that as a chip, because the one thing a reader must not have to
/// work out from two dates is who is waiting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'complaint_org_unit_filter_dialog.dart';
import 'complaints_bloc.dart';
import 'customer_complaint.dart';

class ComplaintsScreen extends StatelessWidget {
  const ComplaintsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('complaints-record');
  static const ValueKey<String> siteKey = ValueKey<String>('complaints-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('complaints-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('complaints-filter-status');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('complaints-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('complaints-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('complaints-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('complaints-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey = ValueKey<String>('complaints-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('complaints-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('complaints-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('complaints-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('complaints-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('complaint-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('complaint-status-$id');
  static ValueKey<String> rowOverdueKey(String id) => ValueKey<String>('complaint-overdue-$id');
  static ValueKey<String> rowDueKey(String id) => ValueKey<String>('complaint-due-$id');
  static ValueKey<String> rowControlledKey(String id) =>
      ValueKey<String>('complaint-controlled-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ComplaintsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                ComplaintsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                ComplaintsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The complaint register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<ComplaintsBloc>().add(const ComplaintsStarted()),
                  ),
                ComplaintsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                ComplaintsLoaded(complaints: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                ComplaintsLoaded(complaints: final rows) => _Register(rows: rows),
              },
            ),
            if (state is ComplaintsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183):
/// the `ShellRoute` creates `ComplaintsBloc` once and keeps it alive while a
/// caller reads a complaint and comes back, so a Screen that only read on
/// `ComplaintsStarted` painted the list as it was when they left.
class _RefreshOnMount extends StatefulWidget {
  const _RefreshOnMount({required this.child});

  final Widget child;

  @override
  State<_RefreshOnMount> createState() => _RefreshOnMountState();
}

class _RefreshOnMountState extends State<_RefreshOnMount> {
  @override
  void initState() {
    super.initState();
    // After this frame, never during it: dispatching an event from `initState`
    // is a side effect while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ComplaintsBloc>().add(const ComplaintsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ComplaintsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is ComplaintsLoaded ? state as ComplaintsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A `Wrap`, not a `Row`: the button's label is long and the
              // header must not overflow at a narrow width.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer complaints', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What customers have complained about at this Site, and whether the '
                        'product they complained about is under control.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: ComplaintsScreen.recordKey,
                      onPressed: loaded.isRecording || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.complaints}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a complaint'),
                    ),
                ],
              ),
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                _Filters(loaded: loaded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final ComplaintsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = loaded.filters;

    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: ComplaintsScreen.siteKey,
              initialValue: loaded.siteId,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
              items: [
                for (final site in loaded.sites)
                  DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
              ],
              onChanged: (siteId) {
                if (siteId == null) return;
                context.read<ComplaintsBloc>().add(ComplaintsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: ComplaintsScreen.orgUnitFilterKey,
          onPressed: () => ComplaintOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: ComplaintsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in ComplaintStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(ComplaintStatus.label(status)),
                ),
            ],
            onChanged: (status) =>
                context.read<ComplaintsBloc>().add(ComplaintsStatusFilterChanged(status)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: ComplaintsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<ComplaintsBloc>().add(const ComplaintsFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped. Said out loud rather than left to be inferred from
/// a list that happens to end (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintsScreen.maxWidth,
        child: Padding(
          key: ComplaintsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more complaints than this list shows. Narrow it by Org Unit or by status '
            'to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103): a Site with nothing on its
/// register is a good-news empty, and a filter that matched nothing is a filter
/// to clear.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: ComplaintsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has complaints, but none of them is in the area or state you '
            'picked.',
        actionLabel: 'Clear the filters',
        actionKey: ComplaintsScreen.emptyClearFiltersKey,
        onAction: () => context.read<ComplaintsBloc>().add(const ComplaintsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: ComplaintsScreen.emptyKey,
      title: 'No complaints',
      message: 'No customer has complained about anything from this Site.',
      icon: Icons.support_agent_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<CustomerComplaint> rows;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: ComplaintsScreen.maxWidth,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _ComplaintRow(complaint: rows[index]),
        ),
      ),
    );
  }
}

class _ComplaintRow extends StatelessWidget {
  const _ComplaintRow({required this.complaint});

  final CustomerComplaint complaint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = complaint;

    return Card(
      key: ComplaintsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.complaints}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A `Wrap`, not a `Row`: the chips grow per ticket and a long
              // buyer reference would overflow a Row at the test surface.
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(row.complaintNo, style: theme.textTheme.labelMedium),
                  StatusChip(
                    key: ComplaintsScreen.rowStatusKey(row.id),
                    label: row.statusLabel,
                    tone: row.statusTone,
                  ),
                  if (row.isOverdue)
                    StatusChip(
                      key: ComplaintsScreen.rowOverdueKey(row.id),
                      label: 'Past due',
                      tone: StatusTone.danger,
                    ),
                  if (row.isWarranty)
                    const StatusChip(label: 'Warranty', tone: StatusTone.info),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${row.customerName} · ${row.productName}'
                '${row.defectCodeName == null ? '' : ' · ${row.defectCodeName}'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                row.dueLabel,
                key: ComplaintsScreen.rowDueKey(row.id),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: row.isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                // The control that exists, or the absence of one — the two
                // answers this register is read for.
                row.nonconformance == null
                    ? 'No Non-conformance controls this product yet'
                    : 'Controlled by ${row.nonconformance!.issueNo}',
                key: ComplaintsScreen.rowControlledKey(row.id),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
