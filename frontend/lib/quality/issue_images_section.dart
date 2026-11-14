/// The pictures of one Quality issue, on its detail Screen (issue #419).
///
/// One section, used by both record kinds: the Non-conformance's Screen and the
/// complaint's Screen each build an [IssueImagesBloc] for their own record and
/// hand it here. What the section does is the same for both — thumbnails, an
/// optional caption under each, "Add picture", and a remove per picture — which
/// is the whole reason it is a section rather than two copies of a grid.
///
/// **Choosing the file is a seam, not a browser call.** [picker] is injected so
/// a widget test can upload a picture on the Dart VM, where no file input
/// exists; the real Screen passes nothing and gets
/// `createQualityPhotoPicker()`. That is the same shape the Directory's
/// Signature upload uses (`signature_file_picker.dart`), and it is what makes
/// "the thumbnail appears after upload, and survives a reload" a widget test
/// rather than a claim.
///
/// **The caption is asked once, after the file is chosen**, in the dialog the
/// person's picture is about to appear on: choosing a photo and then hunting
/// for a field to caption it in is two things to find. It is optional, in the
/// plant's own words, and the server's own ceiling (280 characters) is the
/// field's limit so a too-long caption is refused where it was typed rather
/// than by the API after the upload.
library;

import '../l10n/app_localizations.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_dialog.dart';
import '../widgets/failure_state.dart';
import 'issue_image.dart';
import 'issue_images_bloc.dart';
import 'quality_photo.dart';
import 'quality_photo_picker.dart';

class IssueImagesSection extends StatefulWidget {
  const IssueImagesSection({
    super.key,
    required this.bloc,
    required this.canWrite,
    this.picker,
  });

  final IssueImagesBloc bloc;

  /// Whether the caller may add and remove pictures. A reader who may see the
  /// record but holds no write Grant sees the pictures and no controls — the
  /// same asymmetry the register's row actions follow.
  final bool canWrite;

  /// The file chooser. Null takes the platform's own.
  final QualityPhotoPicker? picker;

  static final ValueKey<String> addKey = ValueKey<String>('quality-image-add');
  static final ValueKey<String> emptyKey = ValueKey<String>('quality-image-empty');
  static final ValueKey<String> captionFieldKey = ValueKey<String>('quality-image-caption');
  static final ValueKey<String> pickerFailureKey = ValueKey<String>('quality-image-picker-failure');
  static final ValueKey<String> captionId = ValueKey<String>('quality-image-caption-id');
  static final ValueKey<String> uploadId = ValueKey<String>('quality-image-upload-id');
  static final ValueKey<String> cancelId = ValueKey<String>('quality-image-cancel-id');

  static ValueKey<String> tileKey(String imageId) =>
      ValueKey<String>('quality-image-tile-$imageId');
  static ValueKey<String> removeKey(String imageId) =>
      ValueKey<String>('quality-image-remove-$imageId');

  @override
  State<IssueImagesSection> createState() => _IssueImagesSectionState();
}

class _IssueImagesSectionState extends State<IssueImagesSection> {
  /// A refusal that never reached the API: the file was not a picture, or could
  /// not be read or scaled. Shown in the section rather than in a snack (§12).
  String? _pickerFailure;

  Future<void> _add() async {
    final picker = widget.picker ?? createQualityPhotoPicker();
    setState(() => _pickerFailure = null);
    final PickedPhoto? photo;
    try {
      photo = await picker.pickPhoto();
    } on QualityPhotoException catch (error) {
      if (mounted) setState(() => _pickerFailure = error.message);
      return;
    }
    if (photo == null || !mounted) return;

    final caption = await showDialog<String?>(
      context: context,
      builder: (context) => _CaptionDialog(photo: photo!),
    );
    if (caption == null || !mounted) return;
    widget.bloc.add(
      IssueImagesUploadRequested(photo: photo, caption: caption.isEmpty ? null : caption),
    );
  }

  Future<void> _remove(IssueImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: AppLocalizations.of(context).issueImagesRemoveThisPicture,
        description:
            AppLocalizations.of(context).issueImagesThePictureIsTakenOffTheRecord,
        confirmLabel: AppLocalizations.of(context).commonRemove,
        dismissLabel: 'Keep it',
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.bloc.add(IssueImagesRemovalRequested(image.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<IssueImagesBloc, IssueImagesState>(
      bloc: widget.bloc,
      builder: (context, state) {
        final trailing = widget.canWrite
            ? TextButton.icon(
                key: IssueImagesSection.addKey,
                onPressed: state is IssueImagesLoaded && state.isBusy ? null : _add,
                icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                label: Text(l10n.issueImagesAddPicture),
              )
            : null;

        return AppDetailSection(
          title: l10n.issueImagesPictures,
          trailing: trailing,
          children: [
            if (state is IssueImagesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: LinearProgressIndicator(),
              ),
            if (state is IssueImagesUnavailable)
              PlatformFailureState(
                title: l10n.issueImagesThePicturesCouldNotBeRead,
                message: state.message,
                onRetry: _retry,
              ),
            if (state is IssueImagesLoaded) ..._loaded(context, state),
          ],
        );
      },
    );
  }

  void _retry() => widget.bloc.add(const IssueImagesStarted());

  List<Widget> _loaded(BuildContext context, IssueImagesLoaded state) {
    final l10n = AppLocalizations.of(context);
    return [
      if (_pickerFailure != null)
        Padding(
          key: IssueImagesSection.pickerFailureKey,
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: AppBanner(
            tone: StatusTone.danger,
            message: _pickerFailure!,
            onDismiss: () => setState(() => _pickerFailure = null),
          ),
        ),
      if (state.failure != null)
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: AppBanner(
            tone: StatusTone.danger,
            message: state.failure!,
            onDismiss: () => widget.bloc.add(const IssueImagesFailureDismissed()),
          ),
        ),
      if (state.isUploading)
        const Padding(
          padding: EdgeInsets.only(bottom: Spacing.md),
          child: LinearProgressIndicator(),
        ),
      if (state.images.isEmpty)
        Text(
          key: IssueImagesSection.emptyKey,
          l10n.issueImagesNoPictureYetASlideNeedsAt,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.of(context).textMuted,
              ),
        )
      else
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            for (final image in state.images)
              _ImageTile(
                key: IssueImagesSection.tileKey(image.id),
                image: image,
                bytes: state.bytes[image.id],
                onRemove: widget.canWrite && !state.isBusy && state.removingId == null
                    ? () => _remove(image)
                    : null,
                removing: state.removingId == image.id,
              ),
          ],
        ),
    ];
  }
}

/// One picture: the image, its caption, and the removal.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    super.key,
    required this.image,
    required this.bytes,
    required this.onRemove,
    required this.removing,
  });

  final IssueImage image;
  final Uint8List? bytes;
  final VoidCallback? onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: bytes == null
                      ? ColoredBox(
                          color: palette.surfaceMuted,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: palette.textMuted,
                              semanticLabel: l10n.commonThePictureCouldNotBeLoaded,
                            ),
                          ),
                        )
                      : Image.memory(
                          bytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          semanticLabel: image.caption ?? l10n.issueImagesAPictureOfTheIssue,
                        ),
                ),
                if (onRemove != null || removing)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: palette.card,
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: IssueImagesSection.removeKey(image.id),
                        tooltip: l10n.issueImagesRemoveThisPicture2,
                        onPressed: removing ? null : onRemove,
                        icon: removing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            image.caption ?? image.sizeLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: image.caption == null ? palette.textMuted : null,
                ),
          ),
        ],
      ),
    );
  }
}

/// The one question a picture is uploaded with: what to say about it.
class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog({required this.photo});

  final PickedPhoto photo;

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.issueImagesAddThisPicture,
      description: l10n.issueImagesTheCaptionIsWhatTheSlideSays,
      actions: [
        AppDialogAction(
          id: 'quality-image-cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'quality-image-upload',
          label: l10n.issueImagesAddIt,
          onPressed: _upload,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.memory(widget.photo.bytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: IssueImagesSection.captionFieldKey,
            controller: _controller,
            maxLength: imageMaxCaptionLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.issueImagesCaptionOptional,
              hintText: l10n.issueImagesBurrOnTheFlangeNearTheLocating,
            ),
            onSubmitted: (_) => _upload(),
          ),
        ],
      ),
    );
  }

  void _upload() => Navigator.of(context).pop(_controller.text.trim());
}
