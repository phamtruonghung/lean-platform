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
/// is on the row (`BodyPart.label` carries it) rather than only in the form,
/// because it is what a reader scans by.
///
/// **A catalogue row is one dense line and [AppTouchTarget.min] tall** (issue
/// #391, `docs/design-language.md` §12): `dense` for the part, `floor` for its
/// region, the Inactive badge only where it applies, and the Correct button
/// stated at 44 so the row cannot grow around it. At [AppLayout.pageWidth] the
/// whole catalogue reads at 700px and keeps the same shape at 1280.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'body_part.dart';
import 'body_part_form_dialog.dart';
import 'body_parts_bloc.dart';
import '../l10n/vocabulary.dart';

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
    final l10n = AppLocalizations.of(context);
    final state = context.watch<BodyPartsBloc>().state;

    return Scaffold(
      body: switch (state) {
        BodyPartsLoading() => const SkeletonList(maxWidth: BodyPartsScreen.maxWidth),
        BodyPartsUnavailable(message: final message) => PlatformFailureState(
            key: BodyPartsScreen.failedKey,
            title: l10n.bodyPartsTheBodyPartCatalogueCouldNotBe,
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: BodyPartsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navBodyParts,
              description:
                  l10n.bodyPartsWhereOnTheBodyAnInjuryWas,
              actions: [
                if (isAdmin)
                  FilledButton.icon(
                    key: BodyPartsScreen.addKey,
                    onPressed: state.isMutating ? null : () => BodyPartFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.commonAddBodyPart),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.bodyParts.isEmpty)
              PlatformEmptyState.noneExist(
                key: BodyPartsScreen.emptyKey,
                title: l10n.bodyPartsNoBodyPartsYet,
                message: l10n.commonNothingHasBeenDefinedInTheCatalogue,
                icon: Icons.accessibility_new_outlined,
                actionLabel: isAdmin ? l10n.commonAddBodyPart : null,
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
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return ConstrainedBox(
      key: BodyPartsScreen.rowKey(bodyPart.id),
      constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    // The label already carries the code and the region it is
                    // filed under (`BodyPart.label`) — the region is what a
                    // reader scans by, so it is on the row rather than only in
                    // the form.
                    child: DisclosingText(
                      bodyPart.label(l10n),
                      style: AppTypography.dense(context)?.copyWith(
                        color: bodyPart.isActive ? palette.textPrimary : palette.textMuted,
                      ),
                    ),
                  ),
                  if (!bodyPart.isActive) ...[
                    const SizedBox(width: Spacing.sm),
                    StatusChip(
                      key: BodyPartsScreen.inactiveChipKey(bodyPart.id),
                      label: l10n.jobPlansInactive,
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
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: Text(l10n.commonCorrect),
              ),
          ],
        ),
      ),
    );
  }
}
