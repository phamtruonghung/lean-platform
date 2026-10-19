/// The browser's file input, for choosing a picture of a Signature
/// (`package:web`, no plugin and no native code). Only compiled where
/// `dart.library.js_interop` exists; see `signature_file_picker.dart`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'signature_file_picker.dart';
import 'signature_png.dart';

class _BrowserFilePicker implements SignatureFilePicker {
  const _BrowserFilePicker();

  @override
  Future<Uint8List?> pickSignatureImage() async {
    final chosen = Completer<web.File?>();
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = 'image/*';
    input.addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        chosen.complete(files != null && files.length > 0 ? files.item(0) : null);
      }).toJS,
    );
    // Fired when the dialog is dismissed with nothing chosen.
    input.addEventListener('cancel', ((web.Event _) => chosen.complete(null)).toJS);
    input.click();

    final file = await chosen.future;
    if (file == null) return null;
    final buffer = await file.arrayBuffer().toDart;
    return normaliseSignatureImage(buffer.toDart.asUint8List());
  }
}

SignatureFilePicker createSignatureFilePicker() => const _BrowserFilePicker();
