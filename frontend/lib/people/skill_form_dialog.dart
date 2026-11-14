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
///
/// **Drawn in `AppDialog` (issue #394, ADR-0058).** Six fields is a short form,
/// so [AppDialogSize.form] (520) — the ADR's own mapping — rather than the 460
/// this file used to hand an `AlertDialog` through a `SizedBox` inside its
/// content. The shell owns the width, the pinned action row and the sheet at a
/// narrow box or a large text scale; this file owns its fields, their keys, the
/// failure's copy and the enable condition on Add/Save, all unchanged. The two
/// action keys are `AppDialog.actionKey` of this dialog's ids, the one rename
/// (#398's pattern) the PR lists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_scan_field.dart';
import 'skill.dart';
import 'skills_bloc.dart';
import '../widgets/notice_text.dart';

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

  /// The two actions, named through the dialog shell that now draws them
  /// (`AppDialog.actionKey`, ADR-0058): same accessors, the shell's key values.
  static final ValueKey<String> submitKey = AppDialog.actionKey('skill-form-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('skill-form-cancel');

  static const ValueKey<String> failureKey = ValueKey<String>('skill-form-failure');

  static const String _submitId = 'skill-form-submit';
  static const String _cancelId = 'skill-form-cancel';

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
    final l10n = AppLocalizations.of(context);
    final failure = _failure;
    return BlocListener<SkillsBloc, SkillsState>(
      listener: _onSkillsChanged,
      child: AppDialog(
        title: _isCorrection ? l10n.skillFormCorrectSkill : l10n.commonAddSkill,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: SkillFormDialog._cancelId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SkillFormDialog._submitId,
            label: _awaiting ? l10n.commonSaving : (_isCorrection ? l10n.commonSave : l10n.commonAddSkill),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppScanField(
              key: SkillFormDialog.codeKey,
              controller: _code,
              label: l10n.commonCode,
              enabled: !_awaiting,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SkillFormDialog.nameKey,
              controller: _name,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.commonName, border: OutlineInputBorder()),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              key: SkillFormDialog.categoryKey,
              initialValue: _skillCategory,
              decoration: InputDecoration(labelText: l10n.commonCategory, border: OutlineInputBorder()),
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
              title: Text(l10n.skillFormRequiresCertification),
              value: _requiresCertification,
              onChanged: _awaiting ? null : (value) => setState(() => _requiresCertification = value),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: SkillFormDialog.revalidationMonthsKey,
              controller: _revalidationMonths,
              enabled: !_awaiting,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.skillFormRevalidationPeriodInMonthsOptional,
                helperText: l10n.skillFormLeftBlankThisSkillNeverNeedsRevalidating,
                border: OutlineInputBorder(),
              ),
            ),
            if (_isCorrection) ...[
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                key: SkillFormDialog.activeKey,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.commonActive),
                value: _isActive,
                onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
              ),
            ],
            if (failure != null)
              Padding(
                key: SkillFormDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
                  failure,
                  style: AppTypography.dense(context)
                      ?.copyWith(color: AppColors.of(context).statusForeground(StatusTone.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
