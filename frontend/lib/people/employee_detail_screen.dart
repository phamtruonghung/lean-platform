/// One Employee's record (issue #86, AC5): job role, Assignment history with
/// the current Assignment distinguished from past ones, and the skills held.
///
/// Read-only. Writes (edit, departure, reinstatement, Assignments, skills
/// administration) are #87/#88/#89's own tickets — nothing here offers an
/// edit affordance to anyone, a Member included (AC7): there is no such
/// control to hide by role, because none exists yet at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'assignee_candidate.dart' show HeldSkill;
import 'employee.dart';
import 'employee_detail_bloc.dart';

class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  /// Null for "my own record" — carried only so a failed load's retry asks
  /// for the same record again, rather than always falling back to `/me`.
  final String? employeeId;

  static const double maxWidth = 700;

  static const ValueKey<String> failedKey = ValueKey<String>('employee-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('employee-detail-retry');
  static const ValueKey<String> departedKey = ValueKey<String>('employee-detail-departed');
  static const ValueKey<String> noAssignmentsKey = ValueKey<String>('employee-detail-no-assignments');
  static const ValueKey<String> noSkillsKey = ValueKey<String>('employee-detail-no-skills');
  static ValueKey<String> assignmentRowKey(String id) =>
      ValueKey<String>('employee-detail-assignment-$id');
  static ValueKey<String> currentAssignmentKey(String id) =>
      ValueKey<String>('employee-detail-assignment-current-$id');
  static ValueKey<String> skillChipKey(String skillId) => ValueKey<String>('employee-detail-skill-$skillId');
  static ValueKey<String> lapsedSkillChipKey(String skillId) =>
      ValueKey<String>('employee-detail-skill-lapsed-$skillId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmployeeDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        EmployeeDetailLoading() => const Center(child: CircularProgressIndicator()),
        EmployeeDetailUnavailable(message: final message) =>
          _Failed(message: message, employeeId: employeeId),
        EmployeeDetailLoaded(employee: final employee) => _Detail(employee: employee),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.employee});

  final EmployeeDetail employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EmployeeDetailScreen.maxWidth),
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
                      Text(employee.displayName, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        employee.jobRoleName == null
                            ? employee.employeeNo
                            : '${employee.employeeNo} · ${employee.jobRoleName}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (!employee.isActive)
                  Chip(
                    key: EmployeeDetailScreen.departedKey,
                    label: const Text('Departed'),
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle:
                        theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xl),
            Text('Assignment history', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (employee.assignments.isEmpty)
              Text(
                'No Assignment has been recorded.',
                key: EmployeeDetailScreen.noAssignmentsKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final assignment in employee.assignments) _AssignmentRow(assignment: assignment),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
            Text('Skills', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (employee.qualifications.isEmpty)
              Text(
                'No qualifications recorded.',
                key: EmployeeDetailScreen.noSkillsKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [for (final skill in employee.qualifications) _SkillChip(skill: skill)],
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.assignment});

  final EmployeeAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: EmployeeDetailScreen.assignmentRowKey(assignment.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        assignment.jobRoleName == null
                            ? assignment.orgUnitName
                            : '${assignment.orgUnitName} · ${assignment.jobRoleName}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (assignment.isCurrent) ...[
                      const SizedBox(width: Spacing.sm),
                      Chip(
                        key: EmployeeDetailScreen.currentAssignmentKey(assignment.id),
                        label: const Text('Current'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        labelStyle: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                      ),
                    ],
                  ],
                ),
                Text(
                  assignment.effectiveTo == null
                      ? 'From ${assignment.effectiveFrom}'
                      : '${assignment.effectiveFrom} – ${assignment.effectiveTo}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A held skill, drawn exactly the way `WorkOrderAssignDialog` already draws
/// one (issue #62) — same chip shape, same "· Lapsed" suffix and error-tinted
/// background, same `KeyedSubtree` wrapping only the lapsed case, so a test
/// can assert "distinguished from current" by key rather than by colour. A
/// lapsed qualification is shown, never left out (AC6): nothing here is
/// evaluative, the same discipline ADR-0018 records for that dialog.
class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.skill});

  final HeldSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Chip(
      key: EmployeeDetailScreen.skillChipKey(skill.skillId),
      label: Text(skill.isLapsed ? '${skill.name} · Lapsed' : skill.name),
      backgroundColor: skill.isLapsed ? theme.colorScheme.errorContainer : null,
      visualDensity: VisualDensity.compact,
    );
    return skill.isLapsed
        ? KeyedSubtree(key: EmployeeDetailScreen.lapsedSkillChipKey(skill.skillId), child: chip)
        : chip;
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.employeeId});

  final String message;
  final String? employeeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: EmployeeDetailScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('This record could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: EmployeeDetailScreen.retryKey,
                onPressed: () => context
                    .read<EmployeeDetailBloc>()
                    .add(EmployeeDetailRequested(employeeId: employeeId)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
