/// Turning a chosen file into a picture this Platform will store (issue #418).
///
/// **The client does the pixel work, because the backend carries no image
/// library.** That is the division of labour ADR-0052 already recorded for a
/// Signature (`signature_png.dart`'s own header says it in as many words), and
/// this file is the same trade for a photograph: the browser decodes what the
/// person chose, scales it so its longest edge is at most [imageMaxEdge], and
/// hands over bytes the server will accept. The server does not trust that
/// work — it reads the picture's own header and refuses anything over the
/// bound — so this is convenience done where the decoder already is, not the
/// only line of defence.
///
/// **Nothing is re-encoded unless it has to be.** A picture already inside the
/// bounds is uploaded exactly as it arrived, which keeps a camera's JPEG a JPEG
/// (a re-encode to PNG, which is the only output `dart:ui` can produce, would
/// turn a 900 KB photo into four megabytes of lossless pixels for no gain). A
/// picture that is too big is scaled and re-encoded to PNG, stepping the size
/// down until it fits [imageMaxBytes] — the same ladder
/// `signature_png.dart` climbs, with a photograph's numbers.
///
/// The file's format is sniffed from its first bytes rather than taken from the
/// browser's own guess: the server refuses a body whose `Content-Type` does not
/// match its contents, and a `.jpg` that is really a PNG would otherwise be a
/// 400 the person could do nothing about.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'issue_image.dart';

/// A picture that is ready to upload.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String contentType;
  final int width;
  final int height;
}

/// Why a chosen file cannot be used, in a sentence the person can act on.
class QualityPhotoException implements Exception {
  const QualityPhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The format of [bytes], from its magic number, or null for anything this
/// Platform does not store.
String? sniffImageType(Uint8List bytes) {
  if (bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return 'image/jpeg';
  }
  if (bytes.length > 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

Future<ui.Image> _decode(Uint8List bytes, {int? width, int? height}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
    allowUpscaling: false,
  );
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Scales [bytes] so its longest edge is at most [imageMaxEdge] and its weight
/// at most [imageMaxBytes], and returns what to upload.
///
/// Throws [QualityPhotoException] for a file that is not one of the three
/// formats or that cannot be decoded at all — the one case a caller has to show
/// rather than retry.
Future<PickedPhoto> normaliseQualityPhoto(Uint8List bytes) async {
  final contentType = sniffImageType(bytes);
  if (contentType == null) {
    throw const QualityPhotoException('That file is not a JPEG, PNG or WebP picture.');
  }

  final ui.Image original;
  try {
    original = await _decode(bytes);
  } catch (_) {
    throw const QualityPhotoException('That picture could not be read. Try another file.');
  }

  try {
    final longEdge = original.width > original.height ? original.width : original.height;
    if (longEdge <= imageMaxEdge && bytes.length <= imageMaxBytes) {
      return PickedPhoto(
        bytes: bytes,
        contentType: contentType,
        width: original.width,
        height: original.height,
      );
    }

    // The largest size that fits the box, then smaller steps until the encoded
    // PNG fits the byte ceiling. A photograph's PNG is several times its JPEG,
    // so the first attempt is often still too heavy.
    var width = original.width;
    var height = original.height;
    if (longEdge > imageMaxEdge) {
      final scale = imageMaxEdge / longEdge;
      width = (original.width * scale).round().clamp(1, imageMaxEdge);
      height = (original.height * scale).round().clamp(1, imageMaxEdge);
    }

    for (final step in const [1.0, 0.8, 0.6, 0.45, 0.32]) {
      final targetWidth = (width * step).round().clamp(1, imageMaxEdge);
      final targetHeight = (height * step).round().clamp(1, imageMaxEdge);
      final resized = await _decode(bytes, width: targetWidth, height: targetHeight);
      try {
        final data = await resized.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;
        final encoded = data.buffer.asUint8List();
        if (encoded.length <= imageMaxBytes) {
          return PickedPhoto(
            bytes: encoded,
            contentType: 'image/png',
            width: resized.width,
            height: resized.height,
          );
        }
      } finally {
        resized.dispose();
      }
    }
  } finally {
    original.dispose();
  }

  throw const QualityPhotoException(
    'That picture could not be made small enough to upload. Try a smaller one.',
  );
}
