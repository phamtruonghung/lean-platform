/// One issue's pictures: reading them, adding one, removing one (issue #419).
///
/// **One Bloc for both record kinds.** A Non-conformance's pictures and a
/// customer complaint's are the same four addresses under different paths, and
/// the section that draws them is the same section — so the state machine takes
/// the kind and the id as its own constructor arguments and the Screen builds
/// it per record, the way `ComplaintDetailBloc` is built per complaint.
///
/// **Bytes are read with the metadata.** The list endpoint returns no bytes on
/// purpose (a register of thumbnails must not be a six-megabyte JSON body), so
/// this Bloc makes one small request per picture and keeps them beside the
/// metadata. That is what lets the section — and a widget test — draw the
/// picture without a second state machine, and it is bounded: an issue holds a
/// handful of pictures, not a page of them.
///
/// **A failed upload is a failure on the page, not a lost picture.** The
/// picture is picked before the request is made, so a refusal (403, 413, a body
/// the server will not read) comes back as [IssueImagesLoaded.failure] with the
/// API's own sentence and the list unchanged — the person can choose the same
/// file again, or a different one.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'issue_image.dart';
import 'quality_api.dart';
import 'quality_photo.dart';
import '../l10n/notices.dart';

sealed class IssueImagesEvent {
  const IssueImagesEvent();
}

/// Read the pictures. Also the retry a failed read offers.
class IssueImagesStarted extends IssueImagesEvent {
  const IssueImagesStarted();
}

/// Add [photo] with [caption], which is optional. The section has already
/// picked and normalised the file; this Bloc only ever sees what is ready to
/// upload.
class IssueImagesUploadRequested extends IssueImagesEvent {
  const IssueImagesUploadRequested({required this.photo, this.caption});

  final PickedPhoto photo;
  final String? caption;
}

/// Remove one picture by its id.
class IssueImagesRemovalRequested extends IssueImagesEvent {
  const IssueImagesRemovalRequested(this.imageId);

  final String imageId;
}

/// A failure the reader has seen and dismissed (the banner's own dismiss).
class IssueImagesFailureDismissed extends IssueImagesEvent {
  const IssueImagesFailureDismissed();
}

sealed class IssueImagesState {
  const IssueImagesState();
}

class IssueImagesLoading extends IssueImagesState {
  const IssueImagesLoading();
}

class IssueImagesUnavailable extends IssueImagesState {
  const IssueImagesUnavailable({required this.message});

  final String message;
}

class IssueImagesLoaded extends IssueImagesState {
  const IssueImagesLoaded({
    required this.images,
    required this.bytes,
    this.isUploading = false,
    this.removingId,
    this.failure,
    this.addedCaption,
  });

  final List<IssueImage> images;

  /// The picture's own bytes, by image id. A picture whose bytes could not be
  /// fetched is absent rather than empty, so the tile can say so.
  final Map<String, Uint8List> bytes;

  /// A request to add a picture is in flight.
  final bool isUploading;

  /// The id of the picture being removed, while its request is in flight.
  final String? removingId;

  /// The last refusal, in the API's own words. Cleared by the next attempt or
  /// by the banner's dismiss.
  final String? failure;

  /// The caption of the picture just added, so the section can say the picture
  /// is on the record (design-language §12: an act whose effect is visible
  /// still gets one sentence when the effect is off-screen).
  final String? addedCaption;

  bool get isBusy => isUploading || removingId != null;
}

class IssueImagesBloc extends Bloc<IssueImagesEvent, IssueImagesState> {
  IssueImagesBloc({
    required QualityApi qualityApi,
    required AuthGateway authGateway,
    required this.kind,
    required this.issueId,
  })  : _api = qualityApi,
        _auth = authGateway,
        super(const IssueImagesLoading()) {
    on<IssueImagesStarted>(_onStarted);
    on<IssueImagesUploadRequested>(_onUploadRequested);
    on<IssueImagesRemovalRequested>(_onRemovalRequested);
    on<IssueImagesFailureDismissed>(_onFailureDismissed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  /// [IssueKind.nonconformance] or [IssueKind.complaint].
  final String kind;

  /// The record the pictures belong to.
  final String issueId;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  Future<void> _onStarted(IssueImagesStarted event, Emitter<IssueImagesState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const IssueImagesUnavailable(message: signedOutMessage));
      return;
    }
    final current = state;
    // A refresh after an upload keeps the picture on screen while the list is
    // re-read; a first read shows the skeleton.
    if (current is! IssueImagesLoaded) emit(const IssueImagesLoading());
    try {
      emit(await _read(token, previous: current is IssueImagesLoaded ? current : null));
    } on QualityApiException catch (error) {
      if (current is IssueImagesLoaded) {
        emit(IssueImagesLoaded(
          images: current.images,
          bytes: current.bytes,
          failure: error.message,
        ));
      } else {
        emit(IssueImagesUnavailable(message: error.message));
      }
    }
  }

  Future<void> _onUploadRequested(
    IssueImagesUploadRequested event,
    Emitter<IssueImagesState> emit,
  ) async {
    final current = state;
    if (current is! IssueImagesLoaded || current.isBusy) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(IssueImagesLoaded(
        images: current.images,
        bytes: current.bytes,
        failure: signedOutMessage,
      ));
      return;
    }

    emit(IssueImagesLoaded(
      images: current.images,
      bytes: current.bytes,
      isUploading: true,
    ));
    try {
      final added = await _api.uploadIssueImage(
        token,
        kind,
        issueId,
        bytes: event.photo.bytes,
        contentType: event.photo.contentType,
        caption: event.caption,
      );
      final settled = await _read(token);
      emit(IssueImagesLoaded(
        images: settled.images,
        bytes: settled.bytes,
        addedCaption: added.caption,
      ));
    } on QualityApiException catch (error) {
      emit(IssueImagesLoaded(
        images: current.images,
        bytes: current.bytes,
        failure: error.message,
      ));
    }
  }

  Future<void> _onRemovalRequested(
    IssueImagesRemovalRequested event,
    Emitter<IssueImagesState> emit,
  ) async {
    final current = state;
    if (current is! IssueImagesLoaded || current.isBusy) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(IssueImagesLoaded(
        images: current.images,
        bytes: current.bytes,
        failure: signedOutMessage,
      ));
      return;
    }

    emit(IssueImagesLoaded(
      images: current.images,
      bytes: current.bytes,
      removingId: event.imageId,
    ));
    try {
      await _api.deleteIssueImage(token, kind, issueId, event.imageId);
      final settled = await _read(token);
      emit(IssueImagesLoaded(images: settled.images, bytes: settled.bytes));
    } on QualityApiException catch (error) {
      emit(IssueImagesLoaded(
        images: current.images,
        bytes: current.bytes,
        failure: error.message,
      ));
    }
  }

  void _onFailureDismissed(IssueImagesFailureDismissed event, Emitter<IssueImagesState> emit) {
    final current = state;
    if (current is! IssueImagesLoaded) return;
    emit(IssueImagesLoaded(images: current.images, bytes: current.bytes));
  }

  /// The list and its bytes, read together. A picture whose bytes fail does not
  /// sink the list: the metadata is still true, and the tile says the picture
  /// could not be loaded.
  Future<IssueImagesLoaded> _read(String token, {IssueImagesLoaded? previous}) async {
    final images = await _api.fetchIssueImages(token, kind, issueId);
    final bytes = <String, Uint8List>{
      // Anything already read and still present is not re-fetched.
      if (previous != null)
        for (final image in images)
          if (previous.bytes.containsKey(image.id)) image.id: previous.bytes[image.id]!,
    };
    await Future.wait([
      for (final image in images)
        if (!bytes.containsKey(image.id))
          () async {
            try {
              bytes[image.id] = await _api.fetchIssueImageBytes(token, kind, issueId, image.id);
            } on QualityApiException {
              // Absent rather than empty: the tile says the picture could not be
              // loaded, and the rest of the section still draws.
            }
          }(),
    ]);
    return IssueImagesLoaded(
      images: images,
      bytes: bytes,
      isUploading: false,
    );
  }
}
