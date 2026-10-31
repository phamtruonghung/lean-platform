/// My signature (issue #317, CONTEXT.md's Signature, ADR-0052): the caller's
/// own mark - the one the Platform applies wherever they would otherwise sign
/// a sheet by hand. Shows the Signature that is kept (or says there is none),
/// and offers to replace it with a picture the person uploads or a mark they
/// draw here, and to remove it.
///
/// Offered to every approved Account: the Signature is the person's own, so
/// there is no role to gate on, and the server answers an Account linked to no
/// Employee as having none. Nothing is sent until the person chooses a picture
/// or saves a drawn mark - an untouched pad cannot be saved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/signature_file_picker.dart';
import '../widgets/signature_pad.dart';
import 'my_signature_bloc.dart';

class MySignatureScreen extends StatelessWidget {
  const MySignatureScreen({super.key});

  static const double maxWidth = 720;

  static const ValueKey<String> failureKey = ValueKey<String>('my-signature-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('my-signature-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('my-signature-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('my-signature-loading');
  static const ValueKey<String> currentKey = ValueKey<String>('my-signature-current');
  static const ValueKey<String> imageKey = ValueKey<String>('my-signature-image');
  static const ValueKey<String> uploadKey = ValueKey<String>('my-signature-upload');
  static const ValueKey<String> drawKey = ValueKey<String>('my-signature-draw');
  static const ValueKey<String> removeKey = ValueKey<String>('my-signature-remove');
  static const ValueKey<String> drawPanelKey = ValueKey<String>('my-signature-draw-panel');
  static const ValueKey<String> padKey = ValueKey<String>('my-signature-pad');
  static const ValueKey<String> saveDrawnKey = ValueKey<String>('my-signature-save-drawn');
  static const ValueKey<String> clearDrawnKey = ValueKey<String>('my-signature-clear-drawn');
  static const ValueKey<String> cancelDrawnKey = ValueKey<String>('my-signature-cancel-drawn');
  static const ValueKey<String> writeFailureKey = ValueKey<String>('my-signature-write-failure');

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MySignatureBloc>(
      create: (_) => MySignatureBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      )..add(const MySignatureStarted()),
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

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
    final bloc = context.read<MySignatureBloc>();
    final png = await context.read<SignatureFilePicker>().pickSignatureImage();
    if (png != null) bloc.add(MySignatureKept(png, 'upload'));
  }

  Future<void> _saveDrawn() async {
    final bloc = context.read<MySignatureBloc>();
    final png = await _pad.toPng(AppColors.of(context).signatureInk);
    if (png == null) return;
    bloc.add(MySignatureKept(png, 'on_screen'));
    if (!mounted) return;
    _pad.clear();
    setState(() => _drawing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<MySignatureBloc>().state;
    final bloc = context.read<MySignatureBloc>();
    final canWrite = !state.isLoading && state.failure == null && !state.isWriting;

    final Widget content;
    if (state.failure != null) {
      content = PlatformFailureState(
        key: MySignatureScreen.failureKey,
        title: 'Your Signature could not be read',
        message: state.failure!,
        retryKey: MySignatureScreen.retryKey,
        onRetry: () => bloc.add(const MySignatureStarted()),
      );
    } else if (state.isLoading) {
      content = const Center(
        key: MySignatureScreen.loadingKey,
        child: Padding(padding: EdgeInsets.all(Spacing.lg), child: CircularProgressIndicator()),
      );
    } else if (state.image == null) {
      content = const PlatformEmptyState.noneExist(
        key: MySignatureScreen.emptyKey,
        title: 'No Signature kept',
        message: 'You have not kept a Signature yet. Upload a picture of it, or draw it here.',
        icon: Icons.draw_outlined,
      );
    } else {
      content = Card(
        key: MySignatureScreen.currentKey,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Signature', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.md),
              Container(
                height: 120,
                alignment: Alignment.centerLeft,
                // On the Signature's own backdrop, so dark ink is not lost on a
                // dark surface (issue #366); clear in the light palette.
                child: ColoredBox(
                  color: AppColors.of(context).signatureBackdrop,
                  child: Image.memory(
                    state.image!,
                    key: MySignatureScreen.imageKey,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Text(
                      'This Signature could not be shown.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.of(context).onSignatureBackdrop),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: MySignatureScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Text('My signature', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'Your own mark, kept once and applied wherever you would otherwise sign a sheet by hand. '
                'Replacing it never changes a sheet you have already signed.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              content,
              if (state.writeFailure != null)
                Padding(
                  key: MySignatureScreen.writeFailureKey,
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    state.writeFailure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    key: MySignatureScreen.uploadKey,
                    onPressed: canWrite ? _upload : null,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(state.image == null ? 'Upload a picture' : 'Replace with a picture'),
                  ),
                  OutlinedButton.icon(
                    key: MySignatureScreen.drawKey,
                    onPressed: canWrite && !_drawing ? () => setState(() => _drawing = true) : null,
                    icon: const Icon(Icons.draw_outlined),
                    label: Text(state.image == null ? 'Draw it' : 'Draw a new one'),
                  ),
                  if (state.image != null)
                    OutlinedButton.icon(
                      key: MySignatureScreen.removeKey,
                      onPressed: canWrite ? () => bloc.add(const MySignatureRemoved()) : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                ],
              ),
              if (_drawing) ...[
                const SizedBox(height: Spacing.lg),
                Card(
                  key: MySignatureScreen.drawPanelKey,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Draw your Signature', style: theme.textTheme.titleMedium),
                        const SizedBox(height: Spacing.sm),
                        SignaturePad(key: MySignatureScreen.padKey, controller: _pad),
                        const SizedBox(height: Spacing.md),
                        ListenableBuilder(
                          listenable: _pad,
                          builder: (context, _) => Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: [
                              FilledButton(
                                key: MySignatureScreen.saveDrawnKey,
                                onPressed: canWrite && !_pad.isEmpty ? _saveDrawn : null,
                                child: const Text('Keep this Signature'),
                              ),
                              OutlinedButton(
                                key: MySignatureScreen.clearDrawnKey,
                                onPressed: _pad.isEmpty ? null : _pad.clear,
                                child: const Text('Clear'),
                              ),
                              TextButton(
                                key: MySignatureScreen.cancelDrawnKey,
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
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
