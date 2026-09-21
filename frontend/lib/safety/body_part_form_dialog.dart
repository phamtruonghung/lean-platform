/// Adding a Body part, and correcting one (issue #224): the shared
/// catalogue's own write surface (`POST`/`PATCH /api/safety/body-parts`,
/// body-part-routes.js, administrator only).
///
/// `InjuryTypeFormDialog`'s shape — see that file's header for the one-dialog
/// choice, the uncorrectable code and the deactivate-never-delete rule — with
/// one field more: the **region** a part is filed under.
///
/// The region is a value with a known set, so it is chosen and never typed
/// (ADR-0023), and six fixed values make it a `DropdownButtonFormField` rather
/// than a search field (`docs/frontend-layout.md`'s set-size rule). Unlike a
/// Product's unit of measure it **is** correctable: filing a part under the
/// wrong region is an ordinary mistake the catalogue must be able to fix, and
/// no record quotes a region the way a report quotes a code.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'body_part.dart';
import 'body_parts_bloc.dart';

class BodyPartFormDialog extends StatefulWidget {
  const BodyPartFormDialog({super.key, this.bodyPart});

  /// Null for Add; the row being corrected otherwise.
  final BodyPart? bodyPart;

  static const ValueKey<String> codeKey = ValueKey<String>('body-part-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('body-part-form-name');
  static const ValueKey<String> regionKey = ValueKey<String>('body-part-form-region');
  static const ValueKey<String> activeKey = ValueKey<String>('body-part-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('body-part-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('body-part-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('body-part-form-failure');

  static Future<void> open(BuildContext context, {BodyPart? bodyPart}) {
    final bloc = context.read<BodyPartsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<BodyPartsBloc>.value(
        value: bloc,
        child: BodyPartFormDialog(bodyPart: bodyPart),
      ),
    );
  }

  @override
  State<BodyPartFormDialog> createState() => _BodyPartFormDialogState();
}

class _BodyPartFormDialogState extends State<BodyPartFormDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.bodyPart?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.bodyPart?.name ?? '');
  late String _region = widget.bodyPart?.region ?? BodyPartRegion.other;
  late bool _isActive = widget.bodyPart?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.bodyPart != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty && (_isCorrection || _code.text.trim().isNotEmpty);

  Map<String, Object?> get _changes {
    final original = widget.bodyPart!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    if (_region != original.region) changes['region'] = _region;
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
      context
          .read<BodyPartsBloc>()
          .add(BodyPartsCorrectionConfirmed(id: widget.bodyPart!.id, changes: changes));
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<BodyPartsBloc>().add(
            BodyPartsAddConfirmed(
              code: _code.text.trim(),
              name: _name.text.trim(),
              region: _region,
            ),
          );
    }
  }

  void _onCatalogueChanged(BuildContext context, BodyPartsState state) {
    if (!_awaiting || state is! BodyPartsLoaded || state.isMutating) return;
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
    return BlocListener<BodyPartsBloc, BodyPartsState>(
      listener: _onCatalogueChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct Body part' : 'Add Body part'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: BodyPartFormDialog.codeKey,
                  controller: _code,
                  enabled: !_isCorrection && !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Code',
                    border: const OutlineInputBorder(),
                    helperText: _isCorrection ? "A Body part's code cannot be corrected" : null,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: BodyPartFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: BodyPartFormDialog.regionKey,
                  initialValue: _region,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Region',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final region in BodyPartRegion.values)
                      DropdownMenuItem<String>(
                        value: region,
                        child: Text(BodyPartRegion.label(region)),
                      ),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) => setState(() => _region = value ?? BodyPartRegion.other),
                ),
                if (_isCorrection) ...[
                  const SizedBox(height: Spacing.md),
                  SwitchListTile(
                    key: BodyPartFormDialog.activeKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text(
                      'A retired Body part is no longer offered while classifying, and '
                      'stays on every incident that already names it.',
                    ),
                    value: _isActive,
                    onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: BodyPartFormDialog.failureKey,
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
            key: BodyPartFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: BodyPartFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add Body part')),
          ),
        ],
      ),
    );
  }
}
