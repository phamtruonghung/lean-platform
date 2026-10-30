/// Changing a KPI Target (ADR-0055): `POST /api/kpi/targets`.
///
/// A KPI Target is never edited. A change is a new entry from the date you
/// choose, and earlier periods keep the Target they had — the dialog says so,
/// because that rule is what the plant has to understand before using it.
///
/// **Valid from is the Site's today or later.** [siteToday] is the server's
/// (the catalogue read's `review_date`, see `KpiTargetsBloc`), never Dart's
/// clock. The picker's `firstDate` is the first gate; the explicit check in
/// [_validFromRefusal] is the second, and it renders an inline message naming
/// today and disables Add.
///
/// **A blank Target is "no target from that date on"** and goes out as
/// `target: null` — the key is always present, never `''` and never omitted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import 'kpi_targets_bloc.dart';

class ChangeTargetDialog extends StatefulWidget {
  const ChangeTargetDialog({super.key, required this.siteToday});

  /// The Site's today (`YYYY-MM-DD`), as the server reported it.
  final String siteToday;

  static const ValueKey<String> grainKey = ValueKey<String>('change-target-grain');
  static const String validFromName = 'change-target-valid-from';
  static ValueKey<String> get validFromKey => AppDateField.fieldKey(validFromName);
  static const ValueKey<String> targetKey = ValueKey<String>('change-target-target');
  static const ValueKey<String> noteKey = ValueKey<String>('change-target-note');
  static const ValueKey<String> submitKey = ValueKey<String>('change-target-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('change-target-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('change-target-failure');
  static const ValueKey<String> validFromRefusalKey = ValueKey<String>('change-target-valid-from-refusal');

  static const List<String> grains = ['Daily', 'Weekly', 'Monthly'];

  static const String rule = 'A KPI Target is never edited. A change is a new entry from the date you '
      'choose, and earlier periods keep the Target they had.';

  /// Opens the form over the Targets Screen, handing the Bloc across (see
  /// `AddKpiDialog.open`).
  static Future<void> open(BuildContext context, {required String siteToday}) {
    final bloc = context.read<KpiTargetsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<KpiTargetsBloc>.value(
        value: bloc,
        child: ChangeTargetDialog(siteToday: siteToday),
      ),
    );
  }

  @override
  State<ChangeTargetDialog> createState() => _ChangeTargetDialogState();
}

class _ChangeTargetDialogState extends State<ChangeTargetDialog> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _grain = ChangeTargetDialog.grains.first;
  late String? _validFrom = widget.siteToday;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `YYYY-MM-DD` strings order the way the dates do, so the Site's today is
  /// compared as text — no clock is read.
  String? get _validFromRefusal {
    final validFrom = _validFrom;
    if (validFrom != null && validFrom.compareTo(widget.siteToday) < 0) {
      return 'A Target cannot start before today at this Site (${widget.siteToday}).';
    }
    return null;
  }

  /// The Target as a number; null when blank. Invalid text is [_targetInvalid].
  double? get _targetValue => double.tryParse(_target.text.trim());

  bool get _targetInvalid => _target.text.trim().isNotEmpty && _targetValue == null;

  bool get _complete => _validFrom != null && _validFromRefusal == null && !_targetInvalid;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final note = _note.text.trim();
    context.read<KpiTargetsBloc>().add(
          TargetAdded(
            grain: _grain,
            validFrom: _validFrom!,
            target: _targetValue,
            note: note.isEmpty ? null : note,
          ),
        );
  }

  void _onTargetsChanged(BuildContext context, KpiTargetsState state) {
    if (!_awaiting || state is! KpiTargetsLoaded || state.isMutating) return;
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
    final refusal = _validFromRefusal;
    final today = DateTime.tryParse(widget.siteToday);
    return BlocListener<KpiTargetsBloc, KpiTargetsState>(
      listener: _onTargetsChanged,
      child: AlertDialog(
        title: const Text('Change Target'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ChangeTargetDialog.rule,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: ChangeTargetDialog.grainKey,
                  initialValue: _grain,
                  decoration: const InputDecoration(labelText: 'Grain', border: OutlineInputBorder()),
                  items: [
                    for (final grain in ChangeTargetDialog.grains)
                      DropdownMenuItem<String>(value: grain, child: Text(grain)),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _grain = value);
                        },
                ),
                const SizedBox(height: Spacing.md),
                AppDateField(
                  name: ChangeTargetDialog.validFromName,
                  label: 'Valid from',
                  helperText: 'Today at this Site is ${widget.siteToday}; a Target starts today or later.',
                  value: _validFrom,
                  firstDate: today,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _validFrom = value),
                ),
                if (refusal != null)
                  Padding(
                    key: ChangeTargetDialog.validFromRefusalKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(refusal, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ChangeTargetDialog.targetKey,
                  controller: _target,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Target',
                    helperText: 'Leave blank for no target from that date on.',
                    errorText: _targetInvalid ? 'The Target must be a number, or blank for no target' : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: ChangeTargetDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                ),
                if (_failure != null)
                  Padding(
                    key: ChangeTargetDialog.failureKey,
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
            key: ChangeTargetDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ChangeTargetDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Change Target'),
          ),
        ],
      ),
    );
  }
}
