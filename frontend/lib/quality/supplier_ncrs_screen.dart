/// The supplier NCR register (issue #215, CONTEXT.md's **Supplier NCR**): what
/// came in wrong at this Site, which Supplier it came from, what was decided
/// about the material, and whether it is under control.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Non-conformance register, the Customer complaint register and
/// the Work order list already follow (#55, ADR-0009). Recording is offered to
/// everyone too: the server is the real gate on where an NCR may be filed (an
/// edit Grant reaching that Org Unit), and hiding the button would gate an
/// address that answers a clean refusal with a sentence the caller can act on.
///
/// The three filters are read filters over the already-visible register and send
/// a request rather than hiding rows client-side — the Supplier and the status
/// are what the ticket names, and the Org Unit one includes everything *beneath*
/// the chosen area, which is the server's ltree walk rather than a filter this
/// client applies.
///
/// A row that is past the day the Supplier was given says so on its own face:
/// the server marks it ([SupplierNcr.isOverdue]) and the row renders that as a
/// chip, because the one thing a reader must not have to work out from two dates
/// is who owes an answer.
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
import 'supplier_ncr.dart';
import 'supplier_ncr_org_unit_filter_dialog.dart';
import 'supplier_ncr_supplier_filter_dialog.dart';
import 'supplier_ncrs_bloc.dart';

class SupplierNcrsScreen extends StatelessWidget {
  const SupplierNcrsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('supplier-ncrs-record');
  static const ValueKey<String> siteKey = ValueKey<String>('supplier-ncrs-site');
  static const ValueKey<String> supplierFilterKey =
      ValueKey<String>('supplier-ncrs-filter-supplier');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('supplier-ncrs-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('supplier-ncrs-filter-status');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('supplier-ncrs-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('supplier-ncrs-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('supplier-ncrs-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('supplier-ncrs-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('supplier-ncrs-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('supplier-ncrs-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('supplier-ncrs-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('supplier-ncrs-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('supplier-ncrs-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('supplier-ncr-row-$id');
  static ValueKey<String> rowStatusKey(String id) => ValueKey<String>('supplier-ncr-status-$id');
  static ValueKey<String> rowOverdueKey(String id) => ValueKey<String>('supplier-ncr-overdue-$id');
  static ValueKey<String> rowDueKey(String id) => ValueKey<String>('supplier-ncr-due-$id');
  static ValueKey<String> rowDispositionKey(String id) =>
      ValueKey<String>('supplier-ncr-disposition-$id');
  static ValueKey<String> rowControlledKey(String id) =>
      ValueKey<String>('supplier-ncr-controlled-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupplierNcrsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SupplierNcrsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SupplierNcrsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The supplier NCR register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () => context.read<SupplierNcrsBloc>().add(const SupplierNcrsStarted()),
                  ),
                SupplierNcrsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                SupplierNcrsLoaded(supplierNcrs: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SupplierNcrsLoaded(supplierNcrs: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SupplierNcrsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183):
/// the `ShellRoute` creates `SupplierNcrsBloc` once and keeps it alive while a
/// caller reads an NCR and comes back, so a Screen that only read on
/// `SupplierNcrsStarted` painted the list as it was when they left.
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
      context.read<SupplierNcrsBloc>().add(const SupplierNcrsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SupplierNcrsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is SupplierNcrsLoaded ? state as SupplierNcrsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrsScreen.maxWidth,
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
                      Text('Supplier NCRs', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What arrived wrong from a Supplier at this Site, and whether the '
                        'material it came in with is under control.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: SupplierNcrsScreen.recordKey,
                      onPressed: loaded.isRecording || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.supplierNcrs}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a supplier NCR'),
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

  final SupplierNcrsLoaded loaded;

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
              key: SupplierNcrsScreen.siteKey,
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
                context.read<SupplierNcrsBloc>().add(SupplierNcrsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SupplierNcrsScreen.supplierFilterKey,
          onPressed: () => SupplierNcrSupplierFilterDialog.open(context),
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(filters.supplierName ?? 'All Suppliers'),
        ),
        OutlinedButton.icon(
          key: SupplierNcrsScreen.orgUnitFilterKey,
          onPressed: () => SupplierNcrOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SupplierNcrsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in SupplierNcrStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(SupplierNcrStatus.label(status)),
                ),
            ],
            onChanged: (status) =>
                context.read<SupplierNcrsBloc>().add(SupplierNcrsStatusFilterChanged(status)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: SupplierNcrsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<SupplierNcrsBloc>().add(const SupplierNcrsFiltersCleared()),
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
        maxWidth: SupplierNcrsScreen.maxWidth,
        child: Padding(
          key: SupplierNcrsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more supplier NCRs than this list shows. Narrow it by Supplier or by '
            'status to see the rest.',
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
        key: SupplierNcrsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has supplier NCRs, but none of them is in the area, the Supplier '
            'or the state you picked.',
        actionLabel: 'Clear the filters',
        actionKey: SupplierNcrsScreen.emptyClearFiltersKey,
        onAction: () => context.read<SupplierNcrsBloc>().add(const SupplierNcrsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: SupplierNcrsScreen.emptyKey,
      title: 'No supplier NCRs',
      message: 'Nothing has come in wrong from a Supplier at this Site.',
      icon: Icons.local_shipping_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SupplierNcr> rows;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: SupplierNcrsScreen.maxWidth,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _SupplierNcrRow(supplierNcr: rows[index]),
        ),
      ),
    );
  }
}

class _SupplierNcrRow extends StatelessWidget {
  const _SupplierNcrRow({required this.supplierNcr});

  final SupplierNcr supplierNcr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = supplierNcr;
    final product = row.productName;

    return Card(
      key: SupplierNcrsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.supplierNcrs}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A `Wrap`, not a `Row`: the chips grow per ticket and a long
              // supplier name would overflow a Row at the test surface.
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(row.ncrNo, style: theme.textTheme.labelMedium),
                  StatusChip(
                    key: SupplierNcrsScreen.rowStatusKey(row.id),
                    label: row.statusLabel,
                    tone: row.statusTone,
                  ),
                  if (row.isOverdue)
                    StatusChip(
                      key: SupplierNcrsScreen.rowOverdueKey(row.id),
                      label: 'Past due',
                      tone: StatusTone.danger,
                    ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${row.supplierName}${product == null ? '' : ' · $product'}'
                '${row.defectCodeName == null ? '' : ' · ${row.defectCodeName}'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                row.dueLabel,
                key: SupplierNcrsScreen.rowDueKey(row.id),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: row.isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xxs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    // The answer for the material, and what was clawed back:
                    // the two facts the Cost pillar is built on.
                    '${row.dispositionLabel} · ${row.costRecoveredLabel}',
                    key: SupplierNcrsScreen.rowDispositionKey(row.id),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                // The control that exists, or the absence of one — the two
                // answers this register is read for.
                row.nonconformance == null
                    ? 'No Non-conformance controls this lot yet'
                    : 'Controlled by ${row.nonconformance!.issueNo}',
                key: SupplierNcrsScreen.rowControlledKey(row.id),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
