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
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
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

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'parts-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the catalogue's rows renders — a different
  /// fact from [emptyKey], and the difference this ticket exists to keep:
  /// "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('parts-no-match');

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

/// The catalogue's loaded view. Stateful only because the filter box's term
/// is the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event — ADR-0012 asks for a Bloc where a Screen drives a state
/// machine, not for one per text field.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final PartsLoaded state;
  final bool isAdmin;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the catalogue to, `''` when nothing is.
  String _term = '';

  /// Whether [part] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify a Part —
  /// its part number and its description. No ranking and no fuzzy matching,
  /// the same rule the assign dialog's own filter uses (issue #187), so the
  /// Platform's two filter boxes behave alike.
  static bool _matches(Part part, String term) =>
      part.partNo.toLowerCase().contains(term) ||
      part.description.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Part> get _matchingParts {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.parts;
    return widget.state.parts.where((part) => _matches(part, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingParts;
    return Center(
      child: AppPageFrame(
        maxWidth: PartsScreen.maxWidth,
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
                if (widget.isAdmin)
                  FilledButton.icon(
                    key: PartsScreen.addKey,
                    onPressed:
                        widget.state.isAdding ? null : () => PartFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add part'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (widget.state.parts.isEmpty)
              PlatformEmptyState.noneExist(
                key: PartsScreen.emptyKey,
                title: 'No parts yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.inventory_2_outlined,
                actionLabel: widget.isAdmin ? 'Add part' : null,
                actionKey: PartsScreen.emptyAddKey,
                onAction: widget.isAdmin ? () => PartFormDialog.open(context) : null,
              )
            else ...[
              // A filter box over a catalogue with nothing in it would be a
              // control that can do nothing, so it appears with the rows —
              // and stays while a term excludes them all, because the reader
              // still has to be able to clear it.
              AppFilterField(
                name: PartsScreen.filterFieldName,
                label: 'Filter parts',
                helperText: 'By part number or description.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.state.parts.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: PartsScreen.noMatchKey,
                  title: 'No parts match',
                  message: 'Nothing in the catalogue matches "${_term.trim()}". Try a '
                      'different part number or description, or clear the filter.',
                )
              else
                // One row per part, ruled apart from its neighbours
                // (issue #189).
                AppListCard(
                  rows: [for (final part in matches) _PartRow(part: part)],
                ),
            ],
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
