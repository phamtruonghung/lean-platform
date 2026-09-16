/// The parts catalogue (issue #80, ADR-0005's shared catalogue, CONTEXT.md's
/// Part entry): every part the plant recognises, defined once and reused, laid
/// over an administrator's own write surface for it
/// (`POST /api/maintenance/parts`).
///
/// Offered to the Maintenance role set, the same as Assets and Work orders.
/// The read is open to any approved Account server-side; the add affordance is
/// gated to [isAdmin] because the write is administrator-only
/// (inventory-routes.js) — the same shape `JobRolesScreen` uses for its own
/// administrator-only catalogue write.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'part.dart';
import 'part_form_dialog.dart';
import 'parts_bloc.dart';

class PartsScreen extends StatelessWidget {
  const PartsScreen({super.key, required this.isAdmin});

  /// Whether this caller may define a part — read off `/me`'s own role.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 800, one of five numbers six catalogue Screens each picked for themselves.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('parts-add');
  static const ValueKey<String> failedKey = ValueKey<String>('parts-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('parts-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('parts-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('parts-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('parts-row-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PartsBloc>().state;

    return Scaffold(
      body: switch (state) {
        PartsLoading() => const SkeletonList(maxWidth: PartsScreen.maxWidth),
        PartsUnavailable(message: final message) => PlatformFailureState(
            key: PartsScreen.failedKey,
            title: 'The parts catalogue could not be read',
            message: message,
            retryKey: PartsScreen.retryKey,
            onRetry: () => context.read<PartsBloc>().add(const PartsStarted()),
          ),
        PartsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final PartsLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PartsScreen.maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Parts', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'The shared catalogue — defined once, reused at every Site.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: PartsScreen.addKey,
                    onPressed: state.isAdding ? null : () => PartFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add part'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.parts.isEmpty)
              PlatformEmptyState.noneExist(
                key: PartsScreen.emptyKey,
                title: 'No parts yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.inventory_2_outlined,
                actionLabel: isAdmin ? 'Add part' : null,
                actionKey: PartsScreen.emptyAddKey,
                onAction: isAdmin ? () => PartFormDialog.open(context) : null,
              )
            else
              // One row per part, ruled apart from its neighbours
              // (issue #189).
              AppListCard(
                rows: [for (final part in state.parts) _PartRow(part: part)],
              ),
          ],
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part});

  final Part part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: PartsScreen.rowKey(part.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.partNo, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  part.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(part.uomCode, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
