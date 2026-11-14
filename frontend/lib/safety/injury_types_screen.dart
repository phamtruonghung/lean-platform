/// The Injury type catalogue (issue #224, ADR-0005's shared catalogue): what
/// an injury *was* — a cut, a fracture, a burn — in one list shared by every
/// Site, laid over an administrator's own write surface for it (`POST`/`PATCH
/// /api/safety/injury-types`, injury-type-routes.js).
///
/// `ProductsScreen`'s shape, and for the same reasons. One difference worth
/// naming: this Screen's **Destination** is offered only to an administrator
/// (the binding design comment on #223 — "the last two filter away for a
/// non-administrator, so a line supervisor sees a two-entry Safety group and
/// an administrator sees four"), where the Quality catalogues' Destinations
/// are offered to everyone. The Screen itself is not gated, because the read
/// behind it is not: `GET /api/safety/injury-types` carries no admin and no Org
/// Unit scope of its own, and a non-administrator who follows a link here sees
/// the catalogue with no write affordances on it — the same thing they would
/// see on `/products`. Only the Destination is filtered, and only the write
/// affordances inside ([isAdmin]) are gated.
///
/// **Nothing on this Screen is restricted.** ADR-0037 restricts three
/// structured fields on a Safety *incident*, because together they are one
/// person's diagnosis; a list of the words a plant classifies injuries with
/// names nobody.
///
/// **A catalogue row is one dense line, and it is a tap target tall even
/// though nothing on it is tappable as a whole** (issue #391,
/// `docs/design-language.md` §12): [AppTouchTarget.min] of height, `dense` text
/// that discloses what it clips, and the Correct button stated at the same
/// 44 so the row cannot grow around it. The page is [AppLayout.pageWidth], so
/// the whole catalogue — name, the Inactive badge and the action — reads in one
/// glance at 700px and stays exactly that shape at 1280, where the text simply
/// has more room.
///
/// No search control, for the same reason `ProductsScreen` gives: the sweep
/// that adds one to each catalogue Screen is a different ticket.
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
import 'injury_type.dart';
import 'injury_type_form_dialog.dart';
import 'injury_types_bloc.dart';

class InjuryTypesScreen extends StatelessWidget {
  const InjuryTypesScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct an Injury type — read off
  /// `/me`'s own role, the same shape `ProductsScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): a catalogue page is the width
  /// every other catalogue is, which the binding design comment on #223 names
  /// for these two Screens explicitly.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('injury-types-add');
  static const ValueKey<String> failedKey = ValueKey<String>('injury-types-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('injury-types-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('injury-types-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('injury-types-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('injury-types-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('injury-types-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('injury-types-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<InjuryTypesBloc>().state;

    return Scaffold(
      body: switch (state) {
        InjuryTypesLoading() => const SkeletonList(maxWidth: InjuryTypesScreen.maxWidth),
        InjuryTypesUnavailable(message: final message) => PlatformFailureState(
            key: InjuryTypesScreen.failedKey,
            title: l10n.injuryTypesTheInjuryTypeCatalogueCouldNotBe,
            message: message,
            retryKey: InjuryTypesScreen.retryKey,
            onRetry: () => context.read<InjuryTypesBloc>().add(const InjuryTypesStarted()),
          ),
        InjuryTypesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final InjuryTypesLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: InjuryTypesScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navInjuryTypes,
              description:
                  l10n.injuryTypesWhatAnInjuryWasOneCatalogueShared,
              actions: [
                if (isAdmin)
                  FilledButton.icon(
                    key: InjuryTypesScreen.addKey,
                    onPressed: state.isMutating ? null : () => InjuryTypeFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.commonAddInjuryType),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.injuryTypes.isEmpty)
              PlatformEmptyState.noneExist(
                key: InjuryTypesScreen.emptyKey,
                title: l10n.injuryTypesNoInjuryTypesYet,
                message: l10n.commonNothingHasBeenDefinedInTheCatalogue,
                icon: Icons.healing_outlined,
                actionLabel: isAdmin ? l10n.commonAddInjuryType : null,
                actionKey: InjuryTypesScreen.emptyAddKey,
                onAction: isAdmin ? () => InjuryTypeFormDialog.open(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final injuryType in state.injuryTypes)
                    _InjuryTypeRow(
                      injuryType: injuryType,
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

class _InjuryTypeRow extends StatelessWidget {
  const _InjuryTypeRow({
    required this.injuryType,
    required this.isAdmin,
    required this.isMutating,
  });

  final InjuryType injuryType;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return ConstrainedBox(
      key: InjuryTypesScreen.rowKey(injuryType.id),
      constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: DisclosingText(
                      injuryType.label,
                      style: AppTypography.dense(context)?.copyWith(
                        color: injuryType.isActive ? palette.textPrimary : palette.textMuted,
                      ),
                    ),
                  ),
                  if (!injuryType.isActive) ...[
                    const SizedBox(width: Spacing.sm),
                    StatusChip(
                      key: InjuryTypesScreen.inactiveChipKey(injuryType.id),
                      label: l10n.jobPlansInactive,
                      tone: StatusTone.neutral,
                    ),
                  ],
                ],
              ),
            ),
            if (isAdmin)
              OutlinedButton(
                key: InjuryTypesScreen.correctKey(injuryType.id),
                onPressed: isMutating
                    ? null
                    : () => InjuryTypeFormDialog.open(context, injuryType: injuryType),
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
