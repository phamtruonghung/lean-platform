/// The Body part catalogue (issue #224, ADR-0005's shared catalogue): where on
/// the body an injury was, filed under the region it belongs to, in one list
/// shared by every Site, laid over an administrator's own write surface for it
/// (`POST`/`PATCH /api/safety/body-parts`, body-part-routes.js).
///
/// `InjuryTypesScreen`'s shape exactly — see that file's header for why the
/// Destination is an administrator's while the Screen itself is not gated, and
/// for why nothing on either catalogue is restricted by ADR-0037.
///
/// Rows are ordered by region and then by code, which is the order the API
/// sends them in: a catalogue of body parts groups naturally, and the region
/// is on the row rather than only in the form because it is what a reader
/// scans by.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'body_part.dart';
import 'body_part_form_dialog.dart';
import 'body_parts_bloc.dart';

class BodyPartsScreen extends StatelessWidget {
  const BodyPartsScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct a Body part — read off `/me`'s
  /// own role.
  final bool isAdmin;

  /// The Platform's own page width (issue #189).
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('body-parts-add');
  static const ValueKey<String> failedKey = ValueKey<String>('body-parts-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('body-parts-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('body-parts-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('body-parts-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('body-parts-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('body-parts-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('body-parts-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodyPartsBloc>().state;

    return Scaffold(
      body: switch (state) {
        BodyPartsLoading() => const SkeletonList(maxWidth: BodyPartsScreen.maxWidth),
        BodyPartsUnavailable(message: final message) => PlatformFailureState(
            key: BodyPartsScreen.failedKey,
            title: 'The Body part catalogue could not be read',
            message: message,
            retryKey: BodyPartsScreen.retryKey,
            onRetry: () => context.read<BodyPartsBloc>().add(const BodyPartsStarted()),
          ),
        BodyPartsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final BodyPartsLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: BodyPartsScreen.maxWidth,
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
                      Text('Body parts', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'Where on the body an injury was — one catalogue shared by '
                        'every Site, filed under the region each part belongs to.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: BodyPartsScreen.addKey,
                    onPressed: state.isMutating ? null : () => BodyPartFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Body part'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.bodyParts.isEmpty)
              PlatformEmptyState.noneExist(
                key: BodyPartsScreen.emptyKey,
                title: 'No Body parts yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.accessibility_new_outlined,
                actionLabel: isAdmin ? 'Add Body part' : null,
                actionKey: BodyPartsScreen.emptyAddKey,
                onAction: isAdmin ? () => BodyPartFormDialog.open(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final bodyPart in state.bodyParts)
                    _BodyPartRow(
                      bodyPart: bodyPart,
                      isAdmin: isAdmin,
                      isMutating: state.isMutating,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BodyPartRow extends StatelessWidget {
  const _BodyPartRow({
    required this.bodyPart,
    required this.isAdmin,
    required this.isMutating,
  });

  final BodyPart bodyPart;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: BodyPartsScreen.rowKey(bodyPart.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    bodyPart.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (!bodyPart.isActive) ...[
                  const SizedBox(width: Spacing.sm),
                  StatusChip(
                    key: BodyPartsScreen.inactiveChipKey(bodyPart.id),
                    label: 'Inactive',
                    tone: StatusTone.neutral,
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin)
            OutlinedButton(
              key: BodyPartsScreen.correctKey(bodyPart.id),
              onPressed: isMutating
                  ? null
                  : () => BodyPartFormDialog.open(context, bodyPart: bodyPart),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}
