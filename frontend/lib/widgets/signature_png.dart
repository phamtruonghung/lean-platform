/// The normalised Signature image (issue #317, ADR-0052): a transparent PNG
/// that fits a fixed box and stays under the server's byte ceiling.
///
/// The client does the pixel work so the server never has to (the backend
/// carries no image library): [encodeSignaturePng] scales whatever it is given
/// to fit [signatureBoxWidth] x [signatureBoxHeight], keeping its proportions
/// and its transparency, and steps the size down until the PNG fits
/// [signatureMaxBytes]. The three constants mirror
/// `backend/src/modules/people/signatures.js` (`MAX_WIDTH`, `MAX_HEIGHT`,
/// `MAX_IMAGE_BYTES`); a change to one should prompt a look at the other.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// The widest a Signature may be, in pixels.
const int signatureBoxWidth = 600;

/// The tallest a Signature may be, in pixels.
const int signatureBoxHeight = 300;

/// The most bytes a Signature PNG may be: 48 KiB.
const int signatureMaxBytes = 48 * 1024;

/// Draws [paint] onto a transparent canvas of [width] x [height] pixels and
/// encodes it as a PNG.
Future<Uint8List?> _render(
  int width,
  int height,
  void Function(ui.Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// The largest size, no bigger than the box, at which a [sourceWidth] x
/// [sourceHeight] picture fits at scale [step] of the box (1, 1/2, 1/4 ...).
ui.Size _fitted(double sourceWidth, double sourceHeight, double step) {
  final scale = [
    signatureBoxWidth * step / sourceWidth,
    signatureBoxHeight * step / sourceHeight,
  ].reduce((a, b) => a < b ? a : b);
  return ui.Size(
    (sourceWidth * scale).clamp(1, signatureBoxWidth).roundToDouble(),
    (sourceHeight * scale).clamp(1, signatureBoxHeight).roundToDouble(),
  );
}

/// Encodes a [sourceWidth] x [sourceHeight] picture, drawn by [draw] in its own
/// coordinates, as a Signature PNG: scaled to fit the box, transparent where
/// nothing is drawn, and small enough. Returns null only if every size down to
/// the smallest still does not fit, or the engine cannot encode.
Future<Uint8List?> encodeSignaturePng({
  required double sourceWidth,
  required double sourceHeight,
  required void Function(ui.Canvas canvas) draw,
}) async {
  for (final step in const [1.0, 0.5, 0.25, 0.125]) {
    final size = _fitted(sourceWidth, sourceHeight, step);
    final bytes = await _render(size.width.toInt(), size.height.toInt(), (canvas) {
      canvas.scale(size.width / sourceWidth, size.height / sourceHeight);
      draw(canvas);
    });
    if (bytes != null && bytes.length <= signatureMaxBytes) return bytes;
  }
  return null;
}

/// Normalises an uploaded picture (any format the engine decodes) into a
/// Signature PNG. Returns null when the bytes are not an image.
Future<Uint8List?> normaliseSignatureImage(Uint8List source) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(source);
  } catch (_) {
    return null;
  }
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      return await encodeSignaturePng(
        sourceWidth: image.width.toDouble(),
        sourceHeight: image.height.toDouble(),
        draw: (canvas) => canvas.drawImage(image, ui.Offset.zero, ui.Paint()),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
