/// Recording, or re-assessing, an Employee holding a skill (issue #89) —
/// `PUT /api/people/employees/:id/skills/:skillId`, administrator only
/// (skill-routes.js's own header: ADR-0010's Consequences section names this
/// exact case as the one where ADR-0009's "an Employee record is not owned
/// by an Org Unit" reasoning holds unchanged, unlike the destination-scoped
/// Assignment write beside it).
///
/// One dialog for both a first assessment and a re-assessment, the same
/// "the server upserts, the client never needs to know which" shape
/// `recordEmployeeSkill`'s own header describes: [existing] null opens on the
/// skill catalogue's own dropdown (any active skill may be chosen); non-null
/// — reached from the "Re-assess" action on an already-held skill's own chip
/// — pre-fills the proficiency and expiry already on record and locks the
/// skill choice, since re-assessing this Employee against a *different*
/// skill is exactly what the "Record skill" action (opened with no
/// [existing]) is for.
///
/// A lapsed qualification is never a reason to hide the "Re-assess" action —
/// quite the opposite, since re-assessing is exactly how a lapsed
/// qualification stops being lapsed (CONTEXT.md's own Employee entry: the
/// Directory shows "the holder of a qualification", and this is the form
/// that keeps that fact current).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'assignee_candidate.dart' show HeldSkill;
import 'employee.dart';
import 'employee_detail_bloc.dart';
import 'skill.dart';

class EmployeeSkillFormDialog extends StatefulWidget {
  const EmployeeSkillFormDialog({super.key, required this.employee, required this.skills, this.existing});

  final EmployeeDetail employee;

  /// The skill catalogue this dialog's own dropdown offers — active skills
  /// only, the same "no reason to record against a retired one" rule
  /// `EmployeeAssignmentDialog`'s own job role dropdown follows for a
  /// deactivated job role.
  final List<Skill> skills;

  /// The held skill being re-assessed, or null for a first assessment
  /// against a skill newly chosen from [skills].
  final HeldSkill? existing;

  static const ValueKey<String> skillKey = ValueKey<String>('employee-skill-form-skill');
  static const ValueKey<String> proficiencyKey = ValueKey<String>('employee-skill-form-proficiency');
  static const ValueKey<String> assessedOnKey = ValueKey<String>('employee-skill-form-assessed-on');
  static const ValueKey<String> expiresOnKey = ValueKey<String>('employee-skill-form-expires-on');
  static const ValueKey<String> evidenceRefKey = ValueKey<String>('employee-skill-form-evidence-ref');
  static const ValueKey<String> noteKey = ValueKey<String>('employee-skill-form-note');
  static const ValueKey<String> submitKey = ValueKey<String>('employee-skill-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('employee-skill-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-skill-form-failure');

  /// Opens the dialog over the detail Screen — the same explicit Bloc
  /// hand-off every dialog in this Module uses, `showDialog`'s route sitting
  /// outside the route-scoped `BlocProvider<EmployeeDetailBloc>`.
  static Future<void> open(
    BuildContext context, {
    required EmployeeDetail employee,
    required List<Skill> skills,
    HeldSkill? existing,
  }) {
    final bloc = context.read<EmployeeDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<EmployeeDetailBloc>.value(
        value: bloc,
        child: EmployeeSkillFormDialog(employee: employee, skills: skills, existing: existing),
      ),
    );
  }

  @override
  State<EmployeeSkillFormDialog> createState() => _EmployeeSkillFormDialogState();
}

class _EmployeeSkillFormDialogState extends State<EmployeeSkillFormDialog> {
  late String? _skillId = widget.existing?.skillId;
  late int _proficiencyLevel = widget.existing?.proficiencyLevel ?? 1;
  final TextEditingController _assessedOn = TextEditingController();
  late final TextEditingController _expiresOn =
      TextEditingController(text: widget.existing?.expiresOn ?? '');
  final TextEditingController _evidenceRef = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  bool get _isReassessment => widget.existing != null;

  @override
  void dispose() {
    _assessedOn.dispose();
    _expiresOn.dispose();
    _evidenceRef.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _complete => _skillId != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final assessedOn = _assessedOn.text.trim();
    final expiresOn = _expiresOn.text.trim();
    final evidenceRef = _evidenceRef.text.trim();
    final note = _note.text.trim();
    context.read<EmployeeDetailBloc>().add(
          EmployeeDetailSkillRecorded(
            skillId: _skillId!,
            proficiencyLevel: _proficiencyLevel,
            assessedOn: assessedOn.isEmpty ? null : assessedOn,
            expiresOn: expiresOn.isEmpty ? null : expiresOn,
            evidenceRef: evidenceRef.isEmpty ? null : evidenceRef,
            note: note.isEmpty ? null : note,
          ),
        );
  }

  void _onDetailChanged(BuildContext context, EmployeeDetailState state) {
    if (!_awaiting || state is! EmployeeDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeSkills = [for (final skill in widget.skills) if (skill.isActive) skill];

    return BlocListener<EmployeeDetailBloc, EmployeeDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text(
          _isReassessment
              ? 'Re-assess ${widget.existing!.name} for ${widget.employee.displayName}'
              : 'Record a skill for ${widget.employee.displayName}',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: EmployeeSkillFormDialog.skillKey,
                  initialValue: _skillId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Skill', border: OutlineInputBorder()),
                  items: [
                    for (final skill in activeSkills)
                      DropdownMenuItem<String>(value: skill.id, child: Text(skill.name)),
                  ],
                  // Locked while re-assessing: a different skill is a first
                  // assessment against that skill, which the "Record skill"
                  // action (no `existing`) already covers.
                  onChanged: (_awaiting || _isReassessment)
                      ? null
                      : (value) => setState(() => _skillId = value),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<int>(
                  key: EmployeeSkillFormDialog.proficiencyKey,
                  initialValue: _proficiencyLevel,
                  decoration: const InputDecoration(
                    labelText: 'Proficiency (0–4, ILUO)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<int>(value: 0, child: Text('0 — none')),
                    DropdownMenuItem<int>(value: 1, child: Text('1')),
                    DropdownMenuItem<int>(value: 2, child: Text('2')),
                    DropdownMenuItem<int>(value: 3, child: Text('3')),
                    DropdownMenuItem<int>(value: 4, child: Text('4')),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _proficiencyLevel = value);
                        },
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeSkillFormDialog.assessedOnKey,
                  controller: _assessedOn,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Assessed on (optional)',
                    helperText: 'YYYY-MM-DD. Left blank, today is recorded.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeSkillFormDialog.expiresOnKey,
                  controller: _expiresOn,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Expires on (optional)',
                    helperText: 'YYYY-MM-DD. Left blank, never expires (or is re-derived from the '
                        'skill\'s own revalidation period).',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeSkillFormDialog.evidenceRefKey,
                  controller: _evidenceRef,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Evidence reference (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeSkillFormDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                ),
                if (_failure != null)
                  Padding(
                    key: EmployeeSkillFormDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: EmployeeSkillFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: EmployeeSkillFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
