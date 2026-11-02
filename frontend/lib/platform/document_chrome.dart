/// The browser's own chrome that this app owns: the tab's title, and the
/// `theme-color` a browser paints its address bar with (issue #399).
///
/// A seam, for the same reason [SignatureFilePicker] is one — the app must be
/// able to say "this address is called Work orders" without knowing it is
/// running in a browser. The document itself lives behind a conditional import
/// ([createDocumentChrome]) and uses `package:web`; everywhere else — the Dart
/// VM a widget test runs on — the stub does nothing, and a test hands the app
/// its own [DocumentChrome] instead (see `test/route_title_test.dart`).
///
/// **Two things, one seam, because they are one surface.** The tab title and
/// the address-bar colour are both properties of the *document*, both written
/// outside any widget, and both owned by whoever knows the route and the
/// palette: `PlatformApp`. Splitting them would mean two web-only files that
/// each re-derive how to reach the document.
///
/// **Why not Flutter's own `Title` widget for the title.** `Title` sends the
/// string to the engine, which is one more hop between "what the route is
/// called" and "what the tab says", and a widget test cannot read the result —
/// it can only read the widget's own field. Writing the document directly is
/// the thing the browser actually does, and the test can assert on exactly the
/// string the browser was told, per navigation.
library;

import 'dart:ui' show Color;

import 'document_chrome_stub.dart'
    if (dart.library.js_interop) 'document_chrome_web.dart' as impl;

/// What this app may change about the document around it. Two methods, no
/// state: the caller decides what the title and the colour should be.
abstract interface class DocumentChrome {
  /// Sets the browser tab's title to [title].
  void setTitle(String title);

  /// Sets the browser's own chrome (the address bar of an installed instance,
  /// the toolbar tint of a mobile browser) to [color] — the `theme-color` a
  /// document declares in its `<head>`.
  void setThemeColor(Color color);
}

/// The chrome this platform has: the document's own, on the web; nothing at all
/// where there is no document (the VM a widget test runs on).
DocumentChrome createDocumentChrome() => impl.createDocumentChrome();
