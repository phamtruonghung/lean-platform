/// The document everywhere `package:web` is unavailable (the Dart VM a widget
/// test runs on): there is none, so nothing is written. See
/// `document_chrome.dart`.
library;

import 'dart:ui' show Color;

import 'document_chrome.dart';

class _NoDocumentChrome implements DocumentChrome {
  const _NoDocumentChrome();

  @override
  void setTitle(String title) {}

  @override
  void setThemeColor(Color color) {}
}

DocumentChrome createDocumentChrome() => const _NoDocumentChrome();
