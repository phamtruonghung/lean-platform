/// Choosing a picture of a Quality issue from the device (issue #418).
///
/// A seam, so the Screen that offers "add picture" does not know it is running
/// in a browser: the browser's file input lives behind a conditional import
/// ([createQualityPhotoPicker]) and uses `package:web`; everywhere else — the
/// Dart VM a widget test runs on — the stub answers that no file can be chosen.
/// A test hands its own [QualityPhotoPicker] to the section instead, which is
/// how a widget test uploads a picture without a browser.
///
/// The same shape as `signature_file_picker.dart` (issue #317), deliberately:
/// one way to ask for a file in this client, not two.
library;

import 'quality_photo.dart';

import 'quality_photo_picker_stub.dart'
    if (dart.library.js_interop) 'quality_photo_picker_web.dart' as impl;

abstract class QualityPhotoPicker {
  /// Asks the person for a picture and returns it normalised to what the
  /// Platform stores (see `quality_photo.dart`), or null when they chose
  /// nothing. A file that is not a picture, or cannot be read, throws
  /// [QualityPhotoException] — the caller shows that sentence.
  Future<PickedPhoto?> pickPhoto();
}

/// The picker this platform has: the browser's file input on the web, a picker
/// that never chooses anything elsewhere.
QualityPhotoPicker createQualityPhotoPicker() => impl.createQualityPhotoPicker();
