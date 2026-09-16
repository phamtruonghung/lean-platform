/// The skill catalogue (issue #89, issue #11's client half, CONTEXT.md's
/// Employee entry): every skill the plant recognises, laid over an
/// administrator's own write surface for it (`POST`/`PATCH /api/people/
/// skills`, skill-routes.js) — the same shape `JobRolesScreen` already draws
/// for the job role catalogue (issue #88).
///
/// Offered to every approved Account, the same openness `JobRolesScreen`
/// already has: `GET /api/people/skills` carries no admin or scope check of
/// its own (skill-routes.js's own header), so hiding this Screen behind a
/// role would gate a destination the route itself never refuses. Only the
/// write affordances inside it ([isAdmin]) are gated — the same shape
/// `JobRolesScreen` already uses for its own administrator-only writes.
/// "Who holds this skill" (AC5) is offered to every Account too, from each
/// row — `GET .../qualified-employees` is an open read as well
/// (skill-routes.js's own header).
///
/// **It reads like the other catalogues now (issue #189).** This Screen was
/// the older of the pair and had drifted from its own sibling: it loaded with a
/// bare `CircularProgressIndicator` where job roles showed the shared skeleton,
/// emptied with a sentence where job roles showed `PlatformEmptyState`, failed
/// with a private widget, drew its rows with no rule between them, and put
/// "Who holds this" and "Correct" *beneath* a row's text, which made every row
/// twice as tall as a job role's with the right half of it empty. It now uses
/// the three shared states, the shared `AppListCard` for its rows, the
/// Platform's page width, and the same row shape job roles uses — name on the
/// left, actions at the right-hand end of the same line.
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
import 'skill.dart';
import 'skill_form_dialog.dart';
import 'skill_qualified_employees_dialog.dart';
import 'skills_bloc.dart';

class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key, required this.isAdmin});

  /// Whether this caller may add or correct a skill — read off `/me`'s own
  /// role, the same shape `JobRolesScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 760 while the Directory and Org Units declared 900, which is why a
  /// catalogue page read as a narrower app than the two pages either side of
  /// it. The number now comes from [AppLayout.pageWidth].
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('skills-add');
  static const ValueKey<String> failedKey = ValueKey<String>('skills-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('skills-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('skills-empty');

  /// The empty state's own action, offered to an administrator — the same
  /// key and shape `JobRolesScreen.emptyAddKey` already has, so an empty
  /// catalogue offers the thing that would fill it (issue #189).
  static const ValueKey<String> emptyAddKey = ValueKey<String>('skills-empty-add');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('skills-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('skills-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('skills-inactive-$id');
  static ValueKey<String> whoHoldsKey(String id) => ValueKey<String>('skills-who-holds-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'skills-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the catalogue's rows renders — a different
  /// fact from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('skills-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SkillsBloc>().state;

    return Scaffold(
      body: switch (state) {
        // The shared skeleton, not the bare spinner this Screen used to show
        // (issue #189): six rows is `SkeletonList`'s own default and the same
        // placeholder `JobRolesScreen` loads behind.
        SkillsLoading() => const SkeletonList(maxWidth: SkillsScreen.maxWidth),
        SkillsUnavailable(message: final message) => PlatformFailureState(
            key: SkillsScreen.failedKey,
            title: 'The skill catalogue could not be read',
            message: message,
            retryKey: SkillsScreen.retryKey,
            onRetry: () => context.read<SkillsBloc>().add(const SkillsStarted()),
          ),
        SkillsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

/// The catalogue's loaded view. Stateful only because the filter box's term
/// is the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final SkillsLoaded state;
  final bool isAdmin;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the catalogue to, `''` when nothing is.
  String _term = '';

  /// Whether [skill] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a skill — its
  /// name, its code, and the category it is filed under. No ranking and no
  /// fuzzy matching, the same rule the assign dialog's own filter uses
  /// (issue #187).
  static bool _matches(Skill skill, String term) =>
      skill.name.toLowerCase().contains(term) ||
      skill.code.toLowerCase().contains(term) ||
      skill.skillCategory.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Skill> get _matchingSkills {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.skills;
    return widget.state.skills.where((skill) => _matches(skill, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingSkills;
    return Center(
      child: AppPageFrame(
        maxWidth: SkillsScreen.maxWidth,
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
                      Text('Skills', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What the plant qualifies an Employee to do — defined once, shared by '
                        'every Site.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (widget.isAdmin)
                  FilledButton.icon(
                    key: SkillsScreen.addKey,
                    onPressed:
                        widget.state.isMutating ? null : () => SkillFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add skill'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (widget.state.skills.isEmpty)
              // The shared empty state, with the action that would fill it
              // (issue #189) — and, since this ticket, only the one empty
              // story: a catalogue with no rows has nothing for a filter box
              // to narrow, so "no skill matches" cannot arise here.
              PlatformEmptyState.noneExist(
                key: SkillsScreen.emptyKey,
                title: 'No skills yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.school_outlined,
                actionLabel: widget.isAdmin ? 'Add skill' : null,
                actionKey: SkillsScreen.emptyAddKey,
                onAction: widget.isAdmin ? () => SkillFormDialog.open(context) : null,
              )
            else ...[
              AppFilterField(
                name: SkillsScreen.filterFieldName,
                label: 'Filter skills',
                helperText: 'By name, code or category.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.state.skills.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: SkillsScreen.noMatchKey,
                  title: 'No skills match',
                  message: 'Nothing in the catalogue matches "${_term.trim()}". Try a '
                      'different name, code or category, or clear the filter.',
                )
              else
                AppListCard(
                  rows: [
                    for (final skill in matches)
                      _SkillRow(
                        skill: skill,
                        isAdmin: widget.isAdmin,
                        isMutating: widget.state.isMutating,
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

/// One row of the catalogue: what the skill is on the left, what can be done
/// about it at the right-hand end of the same line (issue #189).
///
/// The actions used to sit *beneath* the skill's own text in a `Wrap`, which
/// made every row twice as tall as a job role's and left the right half of each
/// row empty. The actions are now the row's own second item, so they sit at the
/// right-hand end of the name's line — and, because the whole row is a `Wrap`
/// rather than a `Row`, they drop to their own line on a surface too narrow to
/// hold them beside the name instead of overflowing it. A `Row` was tried first
/// and overflowed by 77px at an 800px window, which is a supported width.
class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.isAdmin, required this.isMutating});

  final Skill skill;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: SkillsScreen.rowKey(skill.id),
      padding: const EdgeInsets.all(Spacing.md),
      // A `Wrap`, not a `Row` (issue #189): the actions sit at the right-hand
      // end of the name's own line while there is room for them and drop to
      // their own line when there is not — which is what a `Row` cannot do, and
      // at an 800px window there is genuinely not (measured: two outlined
      // buttons take ~400px, leaving 76px for the text and its `Inactive`
      // chip). Same rule the repo's own header-overflow note records: `Wrap`,
      // never a `Row` whose controls can outgrow it.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Spacing.md,
        runSpacing: Spacing.xs,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              Text(
                '${skill.name} · ${skill.code} · ${skill.skillCategory}',
                style: theme.textTheme.bodyMedium,
              ),
              if (!skill.isActive)
                StatusChip(
                  key: SkillsScreen.inactiveChipKey(skill.id),
                  label: 'Inactive',
                  tone: StatusTone.neutral,
                ),
            ],
          ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              OutlinedButton(
                key: SkillsScreen.whoHoldsKey(skill.id),
                onPressed: () => SkillQualifiedEmployeesDialog.open(context, skill),
                child: const Text('Who holds this'),
              ),
              if (isAdmin)
                OutlinedButton(
                  key: SkillsScreen.correctKey(skill.id),
                  onPressed: isMutating ? null : () => SkillFormDialog.open(context, skill: skill),
                  child: const Text('Correct'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
