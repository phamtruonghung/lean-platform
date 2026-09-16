/// The Defect code tree (issue #203, ADR-0005's shared catalogue, CONTEXT.md's
/// Defect code entry): the kinds of thing found wrong, in one list shared by
/// every Site and maintained by an administrator, laid over an
/// administrator's own write surface for it (`POST`/`PATCH
/// /api/quality/defect-codes`, defect-code-routes.js).
///
/// Offered to every approved Account, the same openness `ProductsScreen` and
/// `JobRolesScreen` already have: `GET /api/quality/defect-codes` carries no
/// admin and no Org Unit scope of its own. Only the write affordances inside
/// it ([isAdmin]) are gated.
///
/// The tree is rendered from the flat list the API sends — each code names its
/// own parent — by indenting a code beneath its parent and saying whose child
/// it is, rather than by a tree widget with disclosure arrows. Two reasons: a
/// Non-conformance names a *leaf*, so the whole shape is worth seeing at once
/// rather than one branch at a time; and the row's own parent name survives the
/// row being read out of context (a print-out, a screenshot), which indentation
/// alone does not. Unlike `OrgUnitsScreen` there is no read of children on
/// demand: the catalogue is read in full in one request because it is small and
/// shared.
///
/// No search control, deliberately, for the same reason `ProductsScreen` gives:
/// the sweep that adds one to each catalogue Screen is a different ticket.
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
import 'defect_code.dart';
import 'defect_code_form_dialog.dart';
import 'defect_codes_bloc.dart';

class DefectCodesScreen extends StatelessWidget {
  const DefectCodesScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct a Defect code — read off
  /// `/me`'s own role, the same shape `ProductsScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189).
  static const double maxWidth = AppLayout.pageWidth;

  /// The indent one level of the tree adds, inside a row's own padding. The
  /// Org Units tree spends `Spacing.lg` per depth too, so the two trees read at
  /// the same rhythm.
  static const double indentPerDepth = Spacing.lg;

  static const ValueKey<String> addKey = ValueKey<String>('defect-codes-add');
  static const ValueKey<String> failedKey = ValueKey<String>('defect-codes-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('defect-codes-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('defect-codes-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('defect-codes-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('defect-codes-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('defect-codes-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) =>
      ValueKey<String>('defect-codes-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DefectCodesBloc>().state;

    return Scaffold(
      body: switch (state) {
        DefectCodesLoading() => const SkeletonList(maxWidth: DefectCodesScreen.maxWidth),
        DefectCodesUnavailable(message: final message) => PlatformFailureState(
            key: DefectCodesScreen.failedKey,
            title: 'The Defect code catalogue could not be read',
            message: message,
            retryKey: DefectCodesScreen.retryKey,
            onRetry: () => context.read<DefectCodesBloc>().add(const DefectCodesStarted()),
          ),
        DefectCodesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final DefectCodesLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = defectCodeTree(state.codes);

    return Center(
      child: AppPageFrame(
        maxWidth: DefectCodesScreen.maxWidth,
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
                      Text('Defect codes', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'The kinds of thing found wrong — one list shared by every '
                        'Site, and the severity each starts a Non-conformance at.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: DefectCodesScreen.addKey,
                    onPressed: state.isMutating ? null : () => DefectCodeFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Defect code'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (rows.isEmpty)
              PlatformEmptyState.noneExist(
                key: DefectCodesScreen.emptyKey,
                title: 'No Defect codes yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.rule_outlined,
                actionLabel: isAdmin ? 'Add Defect code' : null,
                actionKey: DefectCodesScreen.emptyAddKey,
                onAction: isAdmin ? () => DefectCodeFormDialog.open(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final row in rows)
                    _DefectCodeRow(row: row, isAdmin: isAdmin, isMutating: state.isMutating),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DefectCodeRow extends StatelessWidget {
  const _DefectCodeRow({required this.row, required this.isAdmin, required this.isMutating});

  final DefectCodeRow row;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = row.code;

    return Padding(
      key: DefectCodesScreen.rowKey(code.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            // The tree's own indentation, one step per level beneath a parent.
            child: Padding(
              padding: EdgeInsets.only(left: row.depth * DefectCodesScreen.indentPerDepth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${code.name} · ${code.code}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (!code.isActive) ...[
                        const SizedBox(width: Spacing.sm),
                        StatusChip(
                          key: DefectCodesScreen.inactiveChipKey(code.id),
                          label: 'Inactive',
                          tone: StatusTone.neutral,
                        ),
                      ],
                    ],
                  ),
                  // Where it sits and what it carries: the parent by name
                  // (indentation alone says nothing once a row is read on its
                  // own), the category it is grouped under (CONTEXT.md keeps
                  // that distinct from the code itself), and the severity a
                  // Non-conformance recorded against it starts at.
                  Text(
                    '${row.parentName == null ? 'Top level' : 'Under ${row.parentName}'} · '
                    '${DefectCategory.label(code.category)} · '
                    'starts at ${DefectSeverity.label(code.defaultSeverity)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (isAdmin)
            OutlinedButton(
              key: DefectCodesScreen.correctKey(code.id),
              onPressed: isMutating ? null : () => DefectCodeFormDialog.open(context, defectCode: code),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}
