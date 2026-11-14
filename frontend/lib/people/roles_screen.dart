/// The roles editor (issue #492, ADR-0061): every role the Platform knows, the
/// permissions each carries, and an administrator's own write surface over
/// them — create a role, change what it carries, retire it.
///
/// **What this Screen is for.** The card that asked for it put the model in
/// SAP's terms: a permission is identified by a code, a role is a group of them
/// an administrator edits, and a person is put into a group. This Screen is the
/// second half of that sentence — the group and its contents. Handing one group
/// to one person is the Accounts Screen's own Roles action
/// (`AccountRolesDialog`), because that is where an administrator is already
/// looking at a person.
///
/// Administrator-only, through `ADM_ROLES_DISPLAY` on the destination and
/// `ADM_ROLES_CHANGE` on the writes — and the server refuses both for anyone
/// else, so this Screen's own gate is convenience, never the security boundary.
///
/// **A catalogue, not a register** (`docs/frontend-layout.md` §5): a list read
/// *down* — a reader finds a role by its name and then acts on it — so it is an
/// `AppListCard` of rows with the record's own controls at the far end and no
/// column-label band, the same shape `JobRolesScreen` takes.
///
/// **The role's code is shown, not hidden.** It is what an administrator types
/// into a request for access and what the server's refusal names, so the row
/// reads `Name · CODE` in the two tones §6 gives a catalogue's name and
/// identifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'app_role.dart';
import 'role_form_dialog.dart';
import 'role_permissions_dialog.dart';
import 'roles_bloc.dart';
import '../widgets/notice_text.dart';

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('roles-add');
  static const ValueKey<String> failedKey = ValueKey<String>('roles-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('roles-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('roles-empty');
  static const ValueKey<String> noticeKey = ValueKey<String>('roles-notice');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('roles-row-$id');
  static ValueKey<String> nameKey(String id) => ValueKey<String>('roles-name-$id');
  static ValueKey<String> permissionsKey(String id) => ValueKey<String>('roles-permissions-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('roles-correct-$id');
  static ValueKey<String> defaultChipKey(String id) => ValueKey<String>('roles-default-$id');
  static ValueKey<String> automaticChipKey(String id) => ValueKey<String>('roles-automatic-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('roles-inactive-$id');
  static ValueKey<String> countKey(String id) => ValueKey<String>('roles-count-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<RolesBloc>().state;

    return Scaffold(
      body: switch (state) {
        RolesLoading() => const SkeletonList(maxWidth: RolesScreen.maxWidth),
        RolesUnavailable(message: final message) => PlatformFailureState(
            key: RolesScreen.failedKey,
            title: l10n.rolesTheRolesCouldNotBeRead,
            message: message,
            retryKey: RolesScreen.retryKey,
            onRetry: () => context.read<RolesBloc>().add(const RolesStarted()),
          ),
        RolesLoaded() => _Loaded(state: state),
      },
    );
  }
}

/// The loaded view: a notice line from the last mutation, then one row per
/// role. Stateless on purpose — unlike the job role catalogue this Screen has
/// no filter box, because there are six roles and not sixty.
class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final RolesLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final notice = state.notice;

    return Center(
      child: AppPageFrame(
        maxWidth: RolesScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navRoles,
              description: l10n.rolesWhatAnAccountMayDoEachRole,
              actions: [
                FilledButton.icon(
                  key: RolesScreen.addKey,
                  onPressed: state.isMutating ? null : () => RoleFormDialog.open(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.commonAddRole),
                ),
              ],
            ),
            if (notice != null) ...[
              const SizedBox(height: Spacing.md),
              NoticeText(
                notice,
                key: RolesScreen.noticeKey,
                style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
              ),
            ],
            const SizedBox(height: Spacing.md),
            if (state.roles.isEmpty)
              PlatformEmptyState.noneExist(
                key: RolesScreen.emptyKey,
                title: l10n.rolesNoRoles,
                message: l10n.rolesNothingIsCarryingAPermissionThatShould,
                icon: Icons.admin_panel_settings_outlined,
              )
            else
              AppListCard(
                rows: [
                  for (final role in state.roles)
                    _RoleRow(role: role, isMutating: state.isMutating),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One role: its name and code, what it is (default, automatic, retired), how
/// much it carries, and the two controls that change it.
class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.role, required this.isMutating});

  final AppRole role;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);

    final line = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: role.name,
            style: AppTypography.dense(context)?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: ' · ${role.code}',
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
      key: RolesScreen.nameKey(role.id),
      // No `maxLines`/ellipsis: at twice the text in a narrow window the name
      // and its code wrap onto a second line rather than being cut off. The
      // sweep's own check ("clipped text with no way to read it") is what
      // caught this — a role's code is the string an administrator quotes in a
      // request for access, so half of it is worse than two lines.
    );

    final chips = <Widget>[
      if (role.isDefault)
        StatusChip(key: RolesScreen.defaultChipKey(role.id), label: l10n.rolesDefaultGroup, tone: StatusTone.info),
      if (role.legacyRole != null)
        StatusChip(
          key: RolesScreen.automaticChipKey(role.id),
          label: l10n.rolesAutomatic(role.legacyRole!),
          tone: StatusTone.neutral,
        ),
      if (!role.isActive)
        StatusChip(key: RolesScreen.inactiveChipKey(role.id), label: l10n.commonInactive, tone: StatusTone.neutral),
    ];

    // What the role carries and who it reaches — the two facts an administrator
    // weighs before editing it. The count is the code count, not a sentence
    // built from the labels: the editor is where the labels are read.
    final summary = Text(
      l10n.rolesReaches(role.permissionCodes.length, role.holderCount),
      key: RolesScreen.countKey(role.id),
      style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
    );

    final actions = <Widget>[
      OutlinedButton(
        key: RolesScreen.permissionsKey(role.id),
        onPressed: isMutating ? null : () => RolePermissionsDialog.open(context, role: role),
        child: Text(l10n.rolesPermissions),
      ),
      OutlinedButton(
        key: RolesScreen.correctKey(role.id),
        onPressed: isMutating ? null : () => RoleFormDialog.open(context, role: role),
        child: Text(l10n.commonCorrect),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // The box the row is handed, at the reader's text size: the controls
        // drop under the record rather than being squeezed beside it, the same
        // rule `JobRolesScreen`'s row follows.
        final stacked = constraints.maxWidth <
            AppBreakpoints.effective(context, AppBreakpoints.headerActionsWrap);
        final record = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line,
            if (chips.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Wrap(spacing: Spacing.xs, runSpacing: Spacing.xs, children: chips),
            ],
            const SizedBox(height: Spacing.xs),
            summary,
          ],
        );

        return Padding(
          key: RolesScreen.rowKey(role.id),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    record,
                    const SizedBox(height: Spacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: Spacing.xs, children: actions),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: record),
                    const SizedBox(width: Spacing.md),
                    Wrap(spacing: Spacing.xs, children: actions),
                  ],
                ),
        );
      },
    );
  }
}
