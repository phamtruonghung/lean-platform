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
///
/// **The kept mark is a plate, not a bare picture** (issue #393,
/// `docs/design-language.md` sections 1, 5 and 12). The image sits on a panel
/// whose band says what it is (`surfaceMuted`, the same band a table's labels
/// wear) and whose body is the Signature's own backdrop (`signatureBackdrop`,
/// clear in the light palette, so dark ink is not lost on a dark surface —
/// issue #366). The panel is [imagePanelHeight] tall and at most
/// [imageMeasure] wide, because a signature is read as a shape and stretching
/// one across a 720px page turns a mark into a screenshot; the three acts stay
/// where they were, under the plate, at the tap floor. A write that is refused
/// is reported in an `AppBanner` rather than as one more line of red text
/// (section 12's own surface for an outcome), and the page's title row is the
/// shared `AppPageHeader`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/signature_file_picker.dart';
import '../widgets/signature_pad.dart';
import '../widgets/skeleton_list.dart';
import 'my_signature_bloc.dart';

class MySignatureScreen extends StatelessWidget {
  const MySignatureScreen({super.key});

  static const double maxWidth = 720;

  /// The panel the kept mark is shown in: tall enough to read a signature's
  /// own flourishes, short enough not to become the page.
  static const double imagePanelHeight = 120;

  /// The widest the mark itself is drawn, however wide the panel is.
  static const double imageMeasure = 420;

  static const ValueKey<String> failureKey = ValueKey<String>('my-signature-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('my-signature-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('my-signature-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('my-signature-loading');
  static const ValueKey<String> currentKey = ValueKey<String>('my-signature-current');
  static const ValueKey<String> imageKey = ValueKey<String>('my-signature-image');
  static const ValueKey<String> imagePlateKey = ValueKey<String>('my-signature-plate');
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
    final palette = AppColors.of(context);
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
      content = const SkeletonDetail(
        key: MySignatureScreen.loadingKey,
        fieldRows: 3,
        maxWidth: MySignatureScreen.maxWidth,
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
        margin: EdgeInsets.zero,
        // The image is painted on its own backdrop inside the card's rounded
        // corner; without this the corner would be squared off by it.
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              color: palette.tableHeaderFill,
              child: Text(
                'Your Signature',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Container(
              key: MySignatureScreen.imagePlateKey,
              height: MySignatureScreen.imagePanelHeight,
              padding: const EdgeInsets.all(Spacing.md),
              // On the Signature's own backdrop, so dark ink is not lost on a
              // dark surface (issue #366); clear in the light palette.
              color: palette.signatureBackdrop,
              alignment: Alignment.centerLeft,
              // A `SizedBox` rather than a `ConstrainedBox`: the sample the mark
              // is drawn in is a fixed measure, and a `SizedBox` clamps itself to
              // the panel's own width on a narrow page (`layout_rules_test`
              // forbids a Screen stating a page frame by hand, which is what a
              // `ConstrainedBox` in a `_screen.dart` reads as).
              child: SizedBox(
                width: MySignatureScreen.imageMeasure,
                height: MySignatureScreen.imagePanelHeight - 2 * Spacing.md,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.memory(
                    state.image!,
                    key: MySignatureScreen.imageKey,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    errorBuilder: (context, error, stackTrace) => Text(
                      'This Signature could not be shown.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: palette.onSignatureBackdrop),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
              const AppPageHeader(
                title: 'My signature',
                description:
                    'Your own mark, kept once and applied wherever you would otherwise sign a sheet by hand. '
                    'Replacing it never changes a sheet you have already signed.',
              ),
              const SizedBox(height: Spacing.lg),
              content,
              if (state.writeFailure != null) ...[
                const SizedBox(height: Spacing.md),
                AppBanner(
                  key: MySignatureScreen.writeFailureKey,
                  tone: StatusTone.danger,
                  message: state.writeFailure!,
                ),
              ],
              const SizedBox(height: Spacing.lg),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    key: MySignatureScreen.uploadKey,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouchTarget.min)),
                    onPressed: canWrite ? _upload : null,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(state.image == null ? 'Upload a picture' : 'Replace with a picture'),
                  ),
                  OutlinedButton.icon(
                    key: MySignatureScreen.drawKey,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouchTarget.min)),
                    onPressed: canWrite && !_drawing ? () => setState(() => _drawing = true) : null,
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: Text(state.image == null ? 'Draw it' : 'Draw a new one'),
                  ),
                  if (state.image != null)
                    OutlinedButton.icon(
                      key: MySignatureScreen.removeKey,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouchTarget.min)),
                      onPressed: canWrite ? () => bloc.add(const MySignatureRemoved()) : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
              if (_drawing) ...[
                const SizedBox(height: Spacing.lg),
                Card(
                  key: MySignatureScreen.drawPanelKey,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Draw your Signature',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
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
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, AppTouchTarget.min),
                                ),
                                onPressed: canWrite && !_pad.isEmpty ? _saveDrawn : null,
                                child: const Text('Keep this Signature'),
                              ),
                              OutlinedButton(
                                key: MySignatureScreen.clearDrawnKey,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, AppTouchTarget.min),
                                ),
                                onPressed: _pad.isEmpty ? null : _pad.clear,
                                child: const Text('Clear'),
                              ),
                              TextButton(
                                key: MySignatureScreen.cancelDrawnKey,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, AppTouchTarget.min),
                                ),
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
