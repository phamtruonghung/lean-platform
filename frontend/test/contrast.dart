/// WCAG 2.x contrast, shared by the tests that measure a palette (issue #366)
/// and the ones that measure what a widget actually rendered (issue #168).
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The relative luminance WCAG's own contrast ratio is built from.
double luminance(Color colour) {
  double channel(double value) =>
      value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b);
}

double contrastRatio(Color foreground, Color background) {
  final a = luminance(foreground);
  final b = luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// [colour] painted over the opaque [background] — an alpha colour such as a
/// hover highlight has no contrast of its own until it is composited.
Color compositeOver(Color colour, Color background) => Color.alphaBlend(colour, background);
