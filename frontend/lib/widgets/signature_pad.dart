/// A drawing surface for a Signature (issue #317, ADR-0052): a person draws
/// with a finger, a stylus or a mouse, and the controller turns the strokes
/// into a normalised transparent PNG.
///
/// Built on `CustomPainter` with no drawing dependency, and reusable: a later
/// answer dialog that asks for a mark drawn on the spot holds a
/// [SignaturePadController] beside a [SignaturePad], and asks the controller
/// for [SignaturePadController.toPng] when the person is done. The pad knows
/// nothing about where the PNG goes.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'signature_png.dart';

/// The strokes drawn so far, and the PNG they make.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  /// Nothing has been drawn: an untouched pad has no Signature to send.
  bool get isEmpty => _strokes.isEmpty;

  /// The strokes, each a run of points in the pad's own coordinates.
  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  void _start(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void _extend(Offset point) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(point);
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  /// The strokes as a Signature PNG fitted to the normalised box, or null when
  /// nothing has been drawn or the engine could not encode it.
  ///
  /// [ink] is the colour the strokes are drawn in — the caller passes
  /// `AppColors.of(context).signatureInk`, which is the same in both palettes,
  /// so the exported mark does not depend on the palette it was drawn under
  /// (issue #366). A controller has no `BuildContext`, so it is handed in.
  Future<Uint8List?> toPng(Color ink) {
    if (isEmpty) return Future.value(null);
    final snapshot = [for (final stroke in _strokes) List<Offset>.of(stroke)];
    return encodeSignaturePng(
      sourceWidth: SignaturePad.width,
      sourceHeight: SignaturePad.height,
      draw: (canvas) => _paintStrokes(canvas, snapshot, ink),
    );
  }
}

const double _strokeWidth = 2.5;

Paint _inkPaint(Color ink) => Paint()
  ..color = ink
  ..style = PaintingStyle.stroke
  ..strokeWidth = _strokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _paintStrokes(ui.Canvas canvas, List<List<Offset>> strokes, Color inkColor) {
  final ink = _inkPaint(inkColor);
  for (final stroke in strokes) {
    if (stroke.length == 1) {
      // A tap is a dot.
      canvas.drawCircle(stroke.first, _strokeWidth / 2, ink..style = PaintingStyle.fill);
      ink.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, ink);
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller});

  /// The pad's size in logical pixels: half the normalised box, so the
  /// exported PNG has twice the pad's resolution.
  static const double width = 300;
  static const double height = 150;

  final SignaturePadController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Semantics(
      label: 'Signature drawing area',
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Paper, not the card: the ink is dark in both palettes (it is what
          // the exported PNG will be), so the pad it is collected on is light in
          // both too (issue #366). In the light palette this is the card's own
          // white.
          color: palette.signaturePaper,
          border: Border.all(color: palette.edge),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ClipRect(
          // A pan wins the gesture arena over the page's own scrolling, so
          // drawing on a touch screen does not scroll the Screen.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => controller._start(details.localPosition),
            onPanUpdate: (details) => controller._extend(details.localPosition),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => CustomPaint(
                size: const Size(width, height),
                painter: _StrokesPainter(
                  List.of(controller._strokes.map(List<Offset>.of)),
                  palette.signatureInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes, this.ink);

  final List<List<Offset>> strokes;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, strokes, ink);

  @override
  bool shouldRepaint(_StrokesPainter oldDelegate) => true;
}
