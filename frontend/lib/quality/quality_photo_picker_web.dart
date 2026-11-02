/// The browser's file input, for choosing a picture of a Quality issue
/// (`package:web`, no plugin and no native code). Only compiled where
/// `dart.library.js_interop` exists; see `quality_photo_picker.dart`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'quality_photo.dart';
import 'quality_photo_picker.dart';

class _BrowserPhotoPicker implements QualityPhotoPicker {
  const _BrowserPhotoPicker();

  @override
  Future<PickedPhoto?> pickPhoto() async {
    final chosen = Completer<web.File?>();
    // `accept` on the input is the first filter, and `normaliseQualityPhoto`
    // is the second: a file picker on a desktop will happily offer anything
    // when the person types a path.
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = 'image/jpeg,image/png,image/webp';
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
    return normaliseQualityPhoto(buffer.toDart.asUint8List());
  }
}

QualityPhotoPicker createQualityPhotoPicker() => const _BrowserPhotoPicker();
