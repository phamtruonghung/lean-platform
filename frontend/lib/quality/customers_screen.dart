/// The Customer list (issue #214, CONTEXT.md's **Customer**): who the plant's
/// customers are, laid over an administrator's own write surface for the list
/// (`POST`/`PATCH /api/quality/customers`, customer-routes.js).
///
/// Offered to every approved Account, the same openness `ProductsScreen` and
/// `JobRolesScreen` already have and for the same reason: the read carries no
/// admin and no Org Unit scope of its own — "any active Account can search
/// Customers" is the ticket's own criterion — so hiding this Screen behind a
/// role would gate a destination the route itself never refuses. Only the write
/// affordances inside it ([isAdmin]) are gated.
///
/// The filter box narrows the rows this Screen already holds and issues no
/// request at all: it is the *finding* control of this client's two search
/// controls (issue #187), and it matches on the code and the name — the two
/// things a caller has to hand when they are looking up who a complaint came
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
import 'customer.dart';
import 'customer_form_dialog.dart';
import 'customers_bloc.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct a Customer — read off `/me`'s
  /// own role, the same shape `ProductsScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): a catalogue page is the width
  /// every other catalogue is.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('customers-add');
  static const ValueKey<String> failedKey = ValueKey<String>('customers-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('customers-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('customers-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('customers-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('customers-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('customers-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('customers-inactive-$id');

  /// The filter box's `name`, seeding the keys a test reaches it by — kept in
  /// one place so the field's own name and those keys cannot drift
  /// (`JobRolesScreen.filterFieldName`'s device).
  static const String filterFieldName = 'customers-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the rows renders — a different fact from
  /// [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('customers-no-match');

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _term = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomersBloc>().state;

    return Scaffold(
      body: switch (state) {
        CustomersLoading() => const SkeletonList(maxWidth: CustomersScreen.maxWidth),
        CustomersUnavailable(message: final message) => PlatformFailureState(
            key: CustomersScreen.failedKey,
            title: 'The Customer list could not be read',
            message: message,
            retryKey: CustomersScreen.retryKey,
            onRetry: () => context.read<CustomersBloc>().add(const CustomersStarted()),
          ),
        CustomersLoaded() => _Loaded(
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

  final CustomersLoaded state;
  final bool isAdmin;
  final String term;
  final ValueChanged<String> onTermChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = [for (final customer in state.customers) if (customer.matches(term)) customer];

    return Center(
      child: AppPageFrame(
        maxWidth: CustomersScreen.maxWidth,
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
                    Text('Customers', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      // Straight quotes, not a typographic apostrophe: the
                      // repo's copy is plain ASCII throughout (`theme_skeleton`
                      // and the goldens both read it back).
                      'Who the plant\'s customers are, so a complaint has someone to belong to '
                      'and a response has somewhere to go.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: CustomersScreen.addKey,
                    onPressed:
                        state.isMutating ? null : () => CustomerFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Customer'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.customers.isEmpty)
              PlatformEmptyState.noneExist(
                key: CustomersScreen.emptyKey,
                title: 'No Customers yet',
                message: 'Nothing has been defined in the list.',
                icon: Icons.handshake_outlined,
                actionLabel: isAdmin ? 'Add Customer' : null,
                actionKey: CustomersScreen.emptyAddKey,
                onAction: isAdmin ? () => CustomerFormDialog.open(context) : null,
              )
            else ...[
              AppFilterField(
                name: CustomersScreen.filterFieldName,
                label: 'Filter Customers',
                helperText: 'By name or code.',
                term: term,
                onChanged: onTermChanged,
                shown: matches.length,
                total: state.customers.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: CustomersScreen.noMatchKey,
                  title: 'No Customers match',
                  message: 'Nothing in the list matches "${term.trim()}". Try a different '
                      'name or code, or clear the filter.',
                )
              else
                AppListCard(
                  rows: [
                    for (final customer in matches)
                      _CustomerRow(
                        customer: customer,
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.isAdmin,
    required this.isMutating,
  });

  final Customer customer;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: CustomersScreen.rowKey(customer.id),
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
              Text(customer.summary, style: theme.textTheme.bodyMedium),
              if (!customer.isActive)
                StatusChip(
                  key: CustomersScreen.inactiveChipKey(customer.id),
                  label: 'Inactive',
                  tone: StatusTone.neutral,
                ),
            ],
          ),
          if (isAdmin)
            OutlinedButton(
              key: CustomersScreen.correctKey(customer.id),
              onPressed: isMutating ? null : () => CustomerFormDialog.open(context, customer: customer),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}
