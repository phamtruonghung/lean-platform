/// An administrator's door to an Employee's Signature (issue #320, CONTEXT.md's
/// Signature, ADR-0052), opened from the Employee's own page. It is for an
/// Employee who cannot set their own - one who holds no Account. It shows the
/// Signature that is kept, who set it and whether it was set for the Employee
/// or by them, and offers to replace it with a picture or a drawn mark, or to
/// remove it. Once the Employee holds an Account the server refuses (409) and
/// the dialog shows that refusal in the Module's own words with only Close.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/signature_file_picker.dart';
import '../widgets/signature_pad.dart';
import 'employee.dart';
import 'employee_signature_bloc.dart';

class EmployeeSignatureDialog extends StatelessWidget {
  const EmployeeSignatureDialog({super.key, required this.employee});

  final EmployeeDetail employee;

  static const ValueKey<String> failureKey = ValueKey<String>('employee-signature-failure');
  static const ValueKey<String> emptyKey = ValueKey<String>('employee-signature-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('employee-signature-loading');
  static const ValueKey<String> currentKey = ValueKey<String>('employee-signature-current');
  static const ValueKey<String> imageKey = ValueKey<String>('employee-signature-image');
  static const ValueKey<String> setByKey = ValueKey<String>('employee-signature-set-by');
  static const ValueKey<String> uploadKey = ValueKey<String>('employee-signature-upload');
  static const ValueKey<String> drawKey = ValueKey<String>('employee-signature-draw');
  static const ValueKey<String> removeKey = ValueKey<String>('employee-signature-remove');
  static const ValueKey<String> closeKey = ValueKey<String>('employee-signature-close');
  static const ValueKey<String> padKey = ValueKey<String>('employee-signature-pad');
  static const ValueKey<String> saveDrawnKey = ValueKey<String>('employee-signature-save-drawn');
  static const ValueKey<String> clearDrawnKey = ValueKey<String>('employee-signature-clear-drawn');
  static const ValueKey<String> cancelDrawnKey = ValueKey<String>('employee-signature-cancel-drawn');
  static const ValueKey<String> writeFailureKey = ValueKey<String>('employee-signature-write-failure');
  static const ValueKey<String> refusalKey = ValueKey<String>('employee-signature-refusal');

  static Future<void> open(BuildContext context, EmployeeDetail employee) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmployeeSignatureDialog(employee: employee),
      );

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EmployeeSignatureBloc>(
      create: (_) => EmployeeSignatureBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
        employeeId: employee.id,
      )..add(const EmployeeSignatureStarted()),
      child: _Body(employee: employee),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.employee});

  final EmployeeDetail employee;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final SignaturePadController _pad = SignaturePadController();
  bool _drawing = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final bloc = context.read<EmployeeSignatureBloc>();
    final png = await context.read<SignatureFilePicker>().pickSignatureImage();
    if (png != null) bloc.add(EmployeeSignatureKept(png, 'upload'));
  }

  Future<void> _saveDrawn() async {
    final bloc = context.read<EmployeeSignatureBloc>();
    final png = await _pad.toPng();
    if (png == null) return;
    bloc.add(EmployeeSignatureKept(png, 'on_screen'));
    if (!mounted) return;
    _pad.clear();
    setState(() => _drawing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<EmployeeSignatureBloc>().state;
    final bloc = context.read<EmployeeSignatureBloc>();
    final signature = state.signature;
    final canWrite = !state.isLoading && state.failure == null && !state.isWriting && state.refusal == null;

    final Widget content;
    if (state.failure != null) {
      content = Text(
        state.failure!,
        key: EmployeeSignatureDialog.failureKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    } else if (state.isLoading) {
      content = const Center(
        key: EmployeeSignatureDialog.loadingKey,
        child: Padding(padding: EdgeInsets.all(Spacing.lg), child: CircularProgressIndicator()),
      );
    } else if (signature == null) {
      content = Text(
        'No Signature is kept for ${widget.employee.displayName}. Upload a picture of it, or draw it here.',
        key: EmployeeSignatureDialog.emptyKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
      );
    } else {
      final who = signature.setByName ?? 'an Account that no longer exists';
      content = Column(
        key: EmployeeSignatureDialog.currentKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            alignment: Alignment.centerLeft,
            child: Image.memory(
              signature.image,
              key: EmployeeSignatureDialog.imageKey,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Text(
                'This Signature could not be shown.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            signature.setForEmployee
                ? 'Set for ${widget.employee.displayName} by $who'
                : 'Set by ${widget.employee.displayName}',
            key: EmployeeSignatureDialog.setByKey,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Signature of ${widget.employee.displayName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              if (state.refusal != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    state.refusal!,
                    key: EmployeeSignatureDialog.refusalKey,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (state.writeFailure != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    state.writeFailure!,
                    key: EmployeeSignatureDialog.writeFailureKey,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (state.refusal == null && state.failure == null) ...[
                const SizedBox(height: Spacing.md),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    FilledButton.icon(
                      key: EmployeeSignatureDialog.uploadKey,
                      onPressed: canWrite ? _upload : null,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(signature == null ? 'Upload a picture' : 'Replace with a picture'),
                    ),
                    OutlinedButton.icon(
                      key: EmployeeSignatureDialog.drawKey,
                      onPressed: canWrite && !_drawing ? () => setState(() => _drawing = true) : null,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(signature == null ? 'Draw it' : 'Draw a new one'),
                    ),
                    if (signature != null)
                      OutlinedButton.icon(
                        key: EmployeeSignatureDialog.removeKey,
                        onPressed: canWrite ? () => bloc.add(const EmployeeSignatureRemoved()) : null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ],
              if (_drawing && state.refusal == null) ...[
                const SizedBox(height: Spacing.md),
                SignaturePad(key: EmployeeSignatureDialog.padKey, controller: _pad),
                const SizedBox(height: Spacing.sm),
                ListenableBuilder(
                  listenable: _pad,
                  builder: (context, _) => Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [
                      FilledButton(
                        key: EmployeeSignatureDialog.saveDrawnKey,
                        onPressed: canWrite && !_pad.isEmpty ? _saveDrawn : null,
                        child: const Text('Keep this Signature'),
                      ),
                      OutlinedButton(
                        key: EmployeeSignatureDialog.clearDrawnKey,
                        onPressed: _pad.isEmpty ? null : _pad.clear,
                        child: const Text('Clear'),
                      ),
                      TextButton(
                        key: EmployeeSignatureDialog.cancelDrawnKey,
                        onPressed: () {
                          _pad.clear();
                          setState(() => _drawing = false);
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: EmployeeSignatureDialog.closeKey,
          onPressed: state.isWriting ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
