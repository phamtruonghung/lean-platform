/// The browser's own document (`package:web`, no plugin and no native code).
/// Only compiled where `dart.library.js_interop` exists; see
/// `document_chrome.dart`.
library;

import 'dart:ui' show Color;

import 'package:web/web.dart' as web;

import 'document_chrome.dart';

class _BrowserDocumentChrome implements DocumentChrome {
  const _BrowserDocumentChrome();

  /// The `theme-color` meta's own address. A browser reads the first one in the
  /// `<head>`, and `index.html` declares that first one — with the light
  /// palette's canvas — so the very first paint (before Flutter boots) is not
  /// the wrong colour. Every later write rewrites that same element rather than
  /// appending a second; an element is created only when a document arrives
  /// without one.
  static const String _themeColorSelector = 'meta[name="theme-color"]';

  @override
  void setTitle(String title) => web.document.title = title;

  @override
  void setThemeColor(Color color) {
    final head = web.document.head;
    if (head == null) return;
    web.Element? meta = web.document.querySelector(_themeColorSelector);
    if (meta == null) {
      meta = web.document.createElement('meta')..setAttribute('name', 'theme-color');
      head.appendChild(meta);
    }
    meta.setAttribute('content', _cssHexOf(color));
  }
}

/// [color] as the `#rrggbb` a browser's `theme-color` expects.
///
/// The alpha is dropped deliberately: `theme-color` takes no alpha channel, and
/// every colour this app hands over — a palette's canvas — is opaque.
String _cssHexOf(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

DocumentChrome createDocumentChrome() => const _BrowserDocumentChrome();
