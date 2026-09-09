/// Adding a skill, and correcting one (issue #89): the shared catalogue's own
/// write surface (`POST`/`PATCH /api/people/skills`, skill-routes.js,
/// administrator only) — the same one-dialog-for-both shape
/// `JobRoleFormDialog` already draws for the job role catalogue (issue #88).
///
/// [skill] null means Add; non-null means Correct, and Correct sends only the
/// fields that actually changed — the same `hasOwnProperty` contract
/// `JobRoleFormDialog` already keeps, on `updateSkill`'s (skills.js) own end.
///
/// A skill is deactivated, never deleted (skills.js's own header) — the
/// "Active" switch, offered only while correcting an existing row, is the one
/// way this dialog ever reaches `isActive`; there is no delete anywhere on
/// this Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'skill.dart';
import 'skills_bloc.dart';

class SkillFormDialog extends StatefulWidget {
  const SkillFormDialog({super.key, this.skill});

  /// Null for Add; the row being corrected otherwise.
  final Skill? skill;

  static const ValueKey<String> codeKey = ValueKey<String>('skill-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('skill-form-name');
  static const ValueKey<String> categoryKey = ValueKey<String>('skill-form-category');
  static const ValueKey<String> requiresCertificationKey =
      ValueKey<String>('skill-form-requires-certification');
  static const ValueKey<String> revalidationMonthsKey =
      ValueKey<String>('skill-form-revalidation-months');
  static const ValueKey<String> activeKey = ValueKey<String>('skill-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('skill-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('skill-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('skill-form-failure');

  /// Opens the form over the skill catalogue. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<SkillsBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the same device every other dialog in this Module
  /// uses.
  static Future<void> open(BuildContext context, {Skill? skill}) {
    final bloc = context.read<SkillsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<SkillsBloc>.value(
        value: bloc,
        child: SkillFormDialog(skill: skill),
      ),
    );
  }

  @override
  State<SkillFormDialog> createState() => _SkillFormDialogState();
}

class _SkillFormDialogState extends State<SkillFormDialog> {
  late final TextEditingController _code = TextEditingController(text: widget.skill?.code ?? '');
  late final TextEditingController _name = TextEditingController(text: widget.skill?.name ?? '');
  late final TextEditingController _revalidationMonths =
      TextEditingController(text: widget.skill?.revalidationMonths?.toString() ?? '');
  late String _skillCategory = widget.skill?.skillCategory ?? skillCategories.first;
  late bool _requiresCertification = widget.skill?.requiresCertification ?? false;
  late bool _isActive = widget.skill?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.skill != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _revalidationMonths.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  int? get _revalidationMonthsValue {
    final text = _revalidationMonths.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — never the whole form, whatever was left untouched. Only called
  /// while correcting an existing row, where `widget.skill` is non-null.
  Map<String, Object?> get _changes {
    final original = widget.skill!;
    final changes = <String, Object?>{};
    final code = _code.text.trim();
    if (code != original.code) changes['code'] = code;
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    if (_skillCategory != original.skillCategory) changes['skillCategory'] = _skillCategory;
    if (_requiresCertification != original.requiresCertification) {
      changes['requiresCertification'] = _requiresCertification;
    }
    if (_revalidationMonthsValue != original.revalidationMonths) {
      changes['revalidationMonths'] = _revalidationMonthsValue;
    }
    if (_isActive != original.isActive) changes['isActive'] = _isActive;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    if (_isCorrection) {
      final changes = _changes;
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<SkillsBloc>().add(SkillsCorrectionConfirmed(id: widget.skill!.id, changes: changes));
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<SkillsBloc>().add(
            SkillsAddConfirmed(
              code: _code.text.trim(),
              name: _name.text.trim(),
              skillCategory: _skillCategory,
              requiresCertification: _requiresCertification,
              revalidationMonths: _revalidationMonthsValue,
            ),
          );
    }
  }

  void _onSkillsChanged(BuildContext context, SkillsState state) {
    if (!_awaiting || state is! SkillsLoaded || state.isMutating) return;
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
    return BlocListener<SkillsBloc, SkillsState>(
      listener: _onSkillsChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct skill' : 'Add skill'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: SkillFormDialog.codeKey,
                  controller: _code,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SkillFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: SkillFormDialog.categoryKey,
                  initialValue: _skillCategory,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: [
                    for (final category in skillCategories)
                      DropdownMenuItem<String>(value: category, child: Text(category)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _skillCategory = value!),
                ),
                const SizedBox(height: Spacing.md),
                SwitchListTile(
                  key: SkillFormDialog.requiresCertificationKey,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires certification'),
                  value: _requiresCertification,
                  onChanged:
                      _awaiting ? null : (value) => setState(() => _requiresCertification = value),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: SkillFormDialog.revalidationMonthsKey,
                  controller: _revalidationMonths,
                  enabled: !_awaiting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Revalidation period, in months (optional)',
                    helperText: 'Left blank, this skill never needs revalidating.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isCorrection) ...[
                  const SizedBox(height: Spacing.md),
                  SwitchListTile(
                    key: SkillFormDialog.activeKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: SkillFormDialog.failureKey,
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
            key: SkillFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SkillFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add skill')),
          ),
        ],
      ),
    );
  }
}
