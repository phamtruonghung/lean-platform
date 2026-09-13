/// The technician's individual identification for one action on the floor
/// surface (issue #77, ADR-0016).
///
/// It is a dialog, not a Screen: CONTEXT.md's own Screen entry says a dialog
/// inside a Screen is not a Screen. It appears for one action and disappears
/// with it — nothing here is remembered between actions, so the next person at
/// the machine is asked who they are rather than inheriting the last person's
/// identification.
///
/// The Employee number and PIN are the credential an Employee with no Account
/// presents (CONTEXT.md: most of a plant cannot sign in). Completing also asks
/// what was found, the same note the desktop path requires.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'floor_bloc.dart';

class FloorTechnicianDialog extends StatefulWidget {
  const FloorTechnicianDialog({
    super.key,
    required this.workOrderId,
    required this.workOrderNo,
    this.requireNote = false,
  });

  final String workOrderId;
  final String workOrderNo;

  /// Whether this action also records a completion note.
  final bool requireNote;

  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-technician-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-technician-pin');
  static const ValueKey<String> noteKey = ValueKey<String>('floor-technician-note');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-technician-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('floor-technician-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-technician-failure');

  @override
  State<FloorTechnicianDialog> createState() => _FloorTechnicianDialogState();
}

class _FloorTechnicianDialogState extends State<FloorTechnicianDialog> {
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _employeeNo.dispose();
    _pin.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      _employeeNo.text.trim().isNotEmpty &&
      _pin.text.trim().isNotEmpty &&
      (!widget.requireNote || _note.text.trim().isNotEmpty);

  void _submit() {
    if (!_ready || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final bloc = context.read<FloorBloc>();
    if (widget.requireNote) {
      bloc.add(
        FloorCompleteRequested(
          workOrderId: widget.workOrderId,
          note: _note.text.trim(),
          employeeNo: _employeeNo.text.trim(),
          pin: _pin.text.trim(),
        ),
      );
    } else {
      bloc.add(
        FloorStartRequested(
          workOrderId: widget.workOrderId,
          employeeNo: _employeeNo.text.trim(),
          pin: _pin.text.trim(),
        ),
      );
    }
  }

  void _onFloorChanged(BuildContext context, FloorState state) {
    if (!_awaiting || state is! FloorLoaded || state.isActing) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<FloorBloc, FloorState>(
      listener: _onFloorChanged,
      child: AlertDialog(
        title: Text(
          widget.requireNote
              ? 'Complete ${widget.workOrderNo}'
              : 'Start ${widget.workOrderNo}',
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Who is recording this? Your Employee number and PIN identify you '
                  'for this action only.',
                  style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: FloorTechnicianDialog.employeeNoKey,
                  controller: _employeeNo,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Employee number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: FloorTechnicianDialog.pinKey,
                  controller: _pin,
                  enabled: !_awaiting,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (widget.requireNote) ...[
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: FloorTechnicianDialog.noteKey,
                    controller: _note,
                    enabled: !_awaiting,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'What was found?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: FloorTechnicianDialog.failureKey,
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
            key: FloorTechnicianDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: FloorTechnicianDialog.submitKey,
            onPressed: _ready && !_awaiting ? _submit : null,
            child: Text(widget.requireNote ? 'Complete' : 'Start'),
          ),
        ],
      ),
    );
  }
}
