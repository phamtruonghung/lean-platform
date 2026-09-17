/// The Supplier list (issue #215, CONTEXT.md's **Supplier**): who the plant's
/// suppliers are, laid over an administrator's own write surface for the list
/// (`POST`/`PATCH /api/quality/suppliers`, supplier-routes.js).
///
/// Offered to every approved Account, the same openness `ProductsScreen` and
/// `JobRolesScreen` already have and for the same reason: the read carries no
/// admin and no Org Unit scope of its own — "any active Account can search
/// Suppliers" is the ticket's own criterion — so hiding this Screen behind a
/// role would gate a destination the route itself never refuses. Only the write
/// affordances inside it ([isAdmin]) are gated.
///
/// The filter box narrows the rows this Screen already holds and issues no
/// request at all: it is the *finding* control of this client's two search
/// controls (issue #187), and it matches on the code and the name — the two
/// things a caller has to hand when they are looking up who a bad lot came
/// from. The API's own `?search=` is exercised by `quality_api_test.dart`; a
/// caller who wants the server to narrow a list they do not hold uses that
/// address.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'supplier.dart';
import 'supplier_form_dialog.dart';
import 'suppliers_bloc.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct a Supplier — read off `/me`'s
  /// own role, the same shape `ProductsScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): a catalogue page is the width
  /// every other catalogue is.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('suppliers-add');
  static const ValueKey<String> failedKey = ValueKey<String>('suppliers-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('suppliers-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('suppliers-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('suppliers-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('suppliers-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('suppliers-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('suppliers-inactive-$id');

  /// The filter box's `name`, seeding the keys a test reaches it by — kept in
  /// one place so the field's own name and those keys cannot drift
  /// (`JobRolesScreen.filterFieldName`'s device).
  static const String filterFieldName = 'suppliers-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the rows renders — a different fact from
  /// [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('suppliers-no-match');

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String _term = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersBloc>().state;

    return Scaffold(
      body: switch (state) {
        SuppliersLoading() => const SkeletonList(maxWidth: SuppliersScreen.maxWidth),
        SuppliersUnavailable(message: final message) => PlatformFailureState(
            key: SuppliersScreen.failedKey,
            title: 'The Supplier list could not be read',
            message: message,
            retryKey: SuppliersScreen.retryKey,
            onRetry: () => context.read<SuppliersBloc>().add(const SuppliersStarted()),
          ),
        SuppliersLoaded() => _Loaded(
            state: state,
            isAdmin: widget.isAdmin,
            term: _term,
            onTermChanged: (term) => setState(() => _term = term),
          ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.isAdmin,
    required this.term,
    required this.onTermChanged,
  });

  final SuppliersLoaded state;
  final bool isAdmin;
  final String term;
  final ValueChanged<String> onTermChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = [for (final supplier in state.suppliers) if (supplier.matches(term)) supplier];

    return Center(
      child: AppPageFrame(
        maxWidth: SuppliersScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            // A `Wrap`, not a `Row`: the button's label is long and the header
            // must not overflow at a narrow width.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suppliers', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      // Straight quotes, not a typographic apostrophe: the
                      // repo's copy is plain ASCII throughout (`theme_skeleton`
                      // and the goldens both read it back).
                      'Who the plant buys from, so an incoming lot that is wrong has someone '
                      'to belong to and a claim has somewhere to go.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: SuppliersScreen.addKey,
                    onPressed:
                        state.isMutating ? null : () => SupplierFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Supplier'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.suppliers.isEmpty)
              PlatformEmptyState.noneExist(
                key: SuppliersScreen.emptyKey,
                title: 'No Suppliers yet',
                message: 'Nothing has been defined in the list.',
                icon: Icons.handshake_outlined,
                actionLabel: isAdmin ? 'Add Supplier' : null,
                actionKey: SuppliersScreen.emptyAddKey,
                onAction: isAdmin ? () => SupplierFormDialog.open(context) : null,
              )
            else ...[
              AppFilterField(
                name: SuppliersScreen.filterFieldName,
                label: 'Filter Suppliers',
                helperText: 'By name or code.',
                term: term,
                onChanged: onTermChanged,
                shown: matches.length,
                total: state.suppliers.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: SuppliersScreen.noMatchKey,
                  title: 'No Suppliers match',
                  message: 'Nothing in the list matches "${term.trim()}". Try a different '
                      'name or code, or clear the filter.',
                )
              else
                AppListCard(
                  rows: [
                    for (final supplier in matches)
                      _SupplierRow(
                        supplier: supplier,
                        isAdmin: isAdmin,
                        isMutating: state.isMutating,
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

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.isAdmin,
    required this.isMutating,
  });

  final Supplier supplier;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: SuppliersScreen.rowKey(supplier.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Spacing.md,
        runSpacing: Spacing.sm,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.xxs,
            children: [
              Text(supplier.summary, style: theme.textTheme.bodyMedium),
              if (!supplier.isActive)
                StatusChip(
                  key: SuppliersScreen.inactiveChipKey(supplier.id),
                  label: 'Inactive',
                  tone: StatusTone.neutral,
                ),
            ],
          ),
          if (isAdmin)
            OutlinedButton(
              key: SuppliersScreen.correctKey(supplier.id),
              onPressed: isMutating ? null : () => SupplierFormDialog.open(context, supplier: supplier),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}
