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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'skill.dart';
import 'skill_form_dialog.dart';
import 'skill_qualified_employees_dialog.dart';
import 'skills_bloc.dart';

class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key, required this.isAdmin});

  /// Whether this caller may add or correct a skill — read off `/me`'s own
  /// role, the same shape `JobRolesScreen.isAdmin` follows.
  final bool isAdmin;

  static const double maxWidth = 760;

  static const ValueKey<String> addKey = ValueKey<String>('skills-add');
  static const ValueKey<String> failedKey = ValueKey<String>('skills-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('skills-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('skills-empty');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('skills-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('skills-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('skills-inactive-$id');
  static ValueKey<String> whoHoldsKey(String id) => ValueKey<String>('skills-who-holds-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SkillsBloc>().state;

    return Scaffold(
      body: switch (state) {
        SkillsLoading() => const Center(child: CircularProgressIndicator()),
        SkillsUnavailable(message: final message) => _Failed(message: message),
        SkillsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final SkillsLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SkillsScreen.maxWidth),
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
                if (isAdmin)
                  FilledButton.icon(
                    key: SkillsScreen.addKey,
                    onPressed: state.isMutating ? null : () => SkillFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add skill'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.skills.isEmpty)
              Text(
                'No skill has been defined yet.',
                key: SkillsScreen.emptyKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final skill in state.skills)
                      _SkillRow(skill: skill, isAdmin: isAdmin, isMutating: state.isMutating),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '${skill.name} · ${skill.code} · ${skill.skillCategory}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (!skill.isActive) ...[
                const SizedBox(width: Spacing.sm),
                Chip(
                  key: SkillsScreen.inactiveChipKey(skill.id),
                  label: const Text('Inactive'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.errorContainer,
                  labelStyle:
                      theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ],
            ],
          ),
          const SizedBox(height: Spacing.xs),
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

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: SkillsScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The skill catalogue could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: SkillsScreen.retryKey,
                onPressed: () => context.read<SkillsBloc>().add(const SkillsStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
