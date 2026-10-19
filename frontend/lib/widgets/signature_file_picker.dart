/// Choosing a picture of a Signature from the device (issue #317, ADR-0052).
///
/// A seam, so the Screen that offers "upload" does not know it is running in a
/// browser: the browser's file input lives behind a conditional import
/// ([createSignatureFilePicker]) and uses `package:web`; everywhere else —
/// the Dart VM a widget test runs on — the stub answers that no file can be
/// chosen. A test hands its own [SignatureFilePicker] to the app instead.
library;

import 'dart:typed_data';

import 'signature_file_picker_stub.dart'
    if (dart.library.js_interop) 'signature_file_picker_web.dart' as impl;

abstract class SignatureFilePicker {
  /// Asks the person for a picture and returns it as a normalised Signature
  /// PNG (see `signature_png.dart`), or null when they chose nothing, or what
  /// they chose is not an image this app can read.
  Future<Uint8List?> pickSignatureImage();
}

/// The picker this platform has: the browser's file input on the web, a
/// picker that never chooses anything elsewhere.
SignatureFilePicker createSignatureFilePicker() => impl.createSignatureFilePicker();
