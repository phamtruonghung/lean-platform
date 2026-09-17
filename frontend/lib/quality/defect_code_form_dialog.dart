/// Adding a Defect code, and correcting one (issue #203): the shared tree's own
/// write surface (`POST`/`PATCH /api/quality/defect-codes`,
/// defect-code-routes.js, administrator only).
///
/// One dialog for both, the same choice `ProductFormDialog` makes. [defectCode]
/// null means Add; non-null means Correct, and Correct sends only the fields
/// that actually changed — `updateDefectCode`'s (defect-codes.js)
/// `hasOwnProperty` idiom at the other end — with one deliberate exception: a
/// `parentId` that was cleared is sent as an explicit null, because "moved to
/// the top of the tree" and "not touched" are different acts and only this form
/// knows which one happened.
///
/// Its code is **not correctable** (defect-codes.js refuses one with a 400: a
/// code is what a Non-conformance's report and an audit finding quote), so the
/// field is shown read-only while correcting and never sent.
///
/// Three fields are choices from known sets rather than typed values (ADR-0023,
/// and the same sets the baseline's own CHECK constraints enforce):
/// [DefectCategory.values] and [DefectSeverity.values], and the code it sits
/// beneath. The parent choice lists the codes the Screen already holds, with the
/// code being edited **and everything beneath it** removed — the API refuses that
/// link as a cycle (400) and remains the authority on it, but a form that offered
/// it would be reporting a refusal the caller could not have known about
/// (`defectCodeDescendantsOf`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'defect_code.dart';
import 'defect_codes_bloc.dart';

class DefectCodeFormDialog extends StatefulWidget {
  const DefectCodeFormDialog({super.key, this.defectCode, this.codes = const []});

  /// Null for Add; the row being corrected otherwise.
  final DefectCode? defectCode;

  /// Every Defect code the Screen already read, so the parent choice offers the
  /// tree rather than asking for an id nobody remembers. Empty is legal — an
  /// Add form then offers only "no parent", and the first code defines the top
  /// of the tree.
  final List<DefectCode> codes;

  static const ValueKey<String> codeKey = ValueKey<String>('defect-code-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('defect-code-form-name');
  static const ValueKey<String> categoryKey = ValueKey<String>('defect-code-form-category');
  static const ValueKey<String> severityKey = ValueKey<String>('defect-code-form-severity');
  static const ValueKey<String> parentKey = ValueKey<String>('defect-code-form-parent');
  static const ValueKey<String> activeKey = ValueKey<String>('defect-code-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('defect-code-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('defect-code-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('defect-code-form-failure');

  /// Opens the form over the Defect code tree. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<DefectCodesBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the same device every other dialog in this
  /// Platform uses.
  static Future<void> open(BuildContext context, {DefectCode? defectCode}) {
    final bloc = context.read<DefectCodesBloc>();
    final state = bloc.state;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<DefectCodesBloc>.value(
        value: bloc,
        child: DefectCodeFormDialog(
          defectCode: defectCode,
          codes: state is DefectCodesLoaded ? state.codes : const [],
        ),
      ),
    );
  }

  @override
  State<DefectCodeFormDialog> createState() => _DefectCodeFormDialogState();
}

class _DefectCodeFormDialogState extends State<DefectCodeFormDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.defectCode?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.defectCode?.name ?? '');
  late String _category = widget.defectCode?.category ?? DefectCategory.product;
  late String _severity = widget.defectCode?.defaultSeverity ?? DefectSeverity.minor;
  late String? _parentId = widget.defectCode?.parentId;
  late bool _isActive = widget.defectCode?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.defectCode != null;

  /// The codes this form will not let itself be placed under: the code being
  /// corrected, and everything beneath it. For an Add there is nothing to
  /// exclude — a code that does not exist yet has no descendants.
  late final Set<String> _unplaceable = _isCorrection
      ? defectCodeDescendantsOf(widget.codes, widget.defectCode!.id)
      : const <String>{};

  List<DefectCode> get _parentChoices {
    final choices = [
      for (final code in widget.codes)
        if (!_unplaceable.contains(code.id)) code,
    ]..sort((a, b) => a.code.compareTo(b.code));
    return choices;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete => _name.text.trim().isNotEmpty;

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — except for a cleared parent, which is sent as an explicit null
  /// (this file's own header says why). The code is absent by construction: it
  /// is not correctable, so it is never sent.
  Map<String, Object?> get _changes {
    final original = widget.defectCode!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    if (_category != original.category) changes['category'] = _category;
    if (_severity != original.defaultSeverity) changes['defaultSeverity'] = _severity;
    if (_parentId != original.parentId) changes['parentId'] = _parentId;
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
      context.read<DefectCodesBloc>().add(
            DefectCodesCorrectionConfirmed(id: widget.defectCode!.id, changes: changes),
          );
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<DefectCodesBloc>().add(
            DefectCodesAddConfirmed(
              code: _code.text.trim(),
              name: _name.text.trim(),
              category: _category,
              defaultSeverity: _severity,
              parentId: _parentId,
            ),
          );
    }
  }

  void _onDefectCodesChanged(BuildContext context, DefectCodesState state) {
    if (!_awaiting || state is! DefectCodesLoaded || state.isMutating) return;
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
    return BlocListener<DefectCodesBloc, DefectCodesState>(
      listener: _onDefectCodesChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct Defect code' : 'Add Defect code'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: DefectCodeFormDialog.codeKey,
                  controller: _code,
                  // A code is the one field a correction cannot rewrite.
                  enabled: !_isCorrection && !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Code',
                    border: const OutlineInputBorder(),
                    helperText: _isCorrection ? 'A Defect code cannot be corrected' : null,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: DefectCodeFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: DefectCodeFormDialog.categoryKey,
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in DefectCategory.values)
                      DropdownMenuItem<String>(
                        value: category,
                        child: Text(DefectCategory.label(category)),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: DefectCodeFormDialog.severityKey,
                  initialValue: _severity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Default severity',
                    border: OutlineInputBorder(),
                    helperText: 'What a Non-conformance recorded against this code starts at',
                  ),
                  items: [
                    for (final severity in DefectSeverity.values)
                      DropdownMenuItem<String>(
                        value: severity,
                        child: Text(DefectSeverity.label(severity)),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _severity = value!),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String?>(
                  key: DefectCodeFormDialog.parentKey,
                  initialValue: _parentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Parent',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No parent — top level'),
                    ),
                    for (final code in _parentChoices)
                      DropdownMenuItem<String?>(
                        value: code.id,
                        child: Text(
                          '${code.name} (${code.code})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _parentId = value),
                ),
                if (_isCorrection) ...[
                  const SizedBox(height: Spacing.md),
                  SwitchListTile(
                    key: DefectCodeFormDialog.activeKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: DefectCodeFormDialog.failureKey,
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
            key: DefectCodeFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: DefectCodeFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add Defect code')),
          ),
        ],
      ),
    );
  }
}
