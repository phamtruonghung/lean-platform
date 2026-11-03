/// The files a browser reads *before* Flutter runs: the manifest, the icons and
/// `index.html`'s own head and boot surface (issue #399, #400).
///
/// These are checked from the app's own copy of `web/` — the same directory
/// `flutter build web` copies into the bundle — rather than by curling a
/// deployment, so a regression fails here instead of in production. The colours
/// are compared against `theme.dart`'s own tokens: an icon or a manifest that
/// names a colour the palette does not is a second brand, and this is what stops
/// one appearing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';

/// [color] as the `#rrggbb` these files write, derived from the token rather
/// than repeated as a literal. Upper case, which is how `index.html` and
/// `manifest.json` spell it.
String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The width and height a PNG declares in its own IHDR, read from the bytes.
/// Enough to prove the file is a real picture of the size the manifest claims —
/// a 200 with a page in it (what nginx's `try_files` returned while these files
/// were absent) can never satisfy this.
({int width, int height}) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(24), reason: '${file.path} is too short to be a PNG');
  // PNG signature: 89 50 4E 47 0D 0A 1A 0A, then the IHDR chunk's length and
  // type, so width starts at byte 16 and height at byte 20, both big-endian.
  expect(bytes.sublist(0, 8), <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: '${file.path} does not start with the PNG signature');
  int at(int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  return (width: at(16), height: at(20));
}

void main() {
  late Map<String, Object?> manifest;
  late String index;

  setUpAll(() {
    final manifestFile = File('web/manifest.json');
    final indexFile = File('web/index.html');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'expected to run from frontend/ with a web/ directory next to it');
    expect(indexFile.existsSync(), isTrue);
    manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    index = indexFile.readAsStringSync();
  });

  group('manifest.json', () {
    test('installs with an icon for each size and each purpose', () {
      final icons = (manifest['icons'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>();

      // A browser picks the icon it needs by size; an Android launcher picks a
      // `maskable` one to crop into its own shape. Both sizes the ask names,
      // both purposes.
      expect(icons, isNotEmpty, reason: 'the manifest installs with no icon at all');
      final declared = <String>{
        for (final icon in icons) '${icon['sizes']}/${icon['purpose']}',
      };
      expect(declared, containsAll(<String>[
        '192x192/any',
        '512x512/any',
        '192x192/maskable',
        '512x512/maskable',
      ]));
      for (final icon in icons) {
        expect(icon['type'], 'image/png', reason: '${icon['src']} is not declared a PNG');
      }
    });

    test('every icon it names is a real PNG of the size it claims', () {
      for (final icon in (manifest['icons'] as List<Object?>).cast<Map<String, Object?>>()) {
        final src = icon['src'] as String;
        final file = File('web/$src');
        expect(file.existsSync(), isTrue,
            reason: '${icon['src']} is named by the manifest and does not exist — '
                'nginx would answer 200 with index.html for it, which is how this '
                'defect looked live');

        final declaredSize = int.parse((icon['sizes'] as String).split('x').first);
        final size = _pngSize(file);
        expect(size.width, declaredSize, reason: '$src is not ${icon['sizes']} wide');
        expect(size.height, declaredSize, reason: '$src is not ${icon['sizes']} tall');
      }
    });

    test('both colours are the light palette\'s own canvas, not a second brand', () {
      // The theme the app opens on when the browser asks for neither palette,
      // and the one `background_color` is painted before Flutter boots.
      expect(manifest['background_color'], _hex(AppPalette.light.canvas));
      expect(manifest['theme_color'], _hex(AppPalette.light.canvas));
    });

    test('a landscape-capable app is not asked to rotate into portrait', () {
      expect(manifest['orientation'], isNot(startsWith('portrait')));
      expect(manifest['orientation'], anyOf('any', 'natural', 'landscape'));
    });
  });

  group('index.html', () {
    test('names the manifest, the favicon and the icon a shortcut uses', () {
      expect(index, contains('<link rel="manifest" href="manifest.json">'));
      expect(index, contains('<link rel="icon" type="image/png" href="favicon.png">'));
      expect(index, contains('<link rel="apple-touch-icon" href="icons/Icon-192.png">'));
    });

    test('the tab it draws before the app runs is the app\'s own name', () {
      expect(index, contains('<title>Platform</title>'));
    });

    test('declares the palette\'s canvas as the theme colour before Flutter boots', () {
      // `document_chrome.dart` rewrites this to whichever palette is on screen.
      // Before it runs, a first paint reads the light palette's canvas — the
      // same value the manifest declares.
      final meta = RegExp(r'<meta name="theme-color" content="(#[0-9A-Fa-f]{6})">').firstMatch(index);
      expect(meta, isNotNull, reason: 'index.html declares no theme-color');
      expect(meta!.group(1)!.toUpperCase(), _hex(AppPalette.light.canvas));
    });

    test('the favicon and the shortcut icon it links are real files', () {
      final favicon = File('web/favicon.png');
      expect(favicon.existsSync(), isTrue, reason: 'index.html links a favicon that is not there');
      final size = _pngSize(favicon);
      // Square, and big enough for a tab strip on a 2× display.
      expect(size.width, size.height);
      expect(size.width, greaterThanOrEqualTo(32));

      final shortcut = File('web/icons/Icon-192.png');
      expect(shortcut.existsSync(), isTrue);
      expect(_pngSize(shortcut).width, 192);
    });
  });

  group('boot surface (issue #400)', () {
    late String style;

    setUpAll(() {
      final block = RegExp(r'<style>([\s\S]*?)</style>').firstMatch(index);
      expect(block, isNotNull,
          reason: 'index.html draws no boot surface: there is no <style> block at all');
      style = block!.group(1)!;
    });

    test('paints the name, the sentence and a moving indicator before Flutter runs', () {
      expect(index, contains('id="boot-splash"'));
      expect(index, contains('>Platform<'), reason: 'the surface does not say whose product this is');
      expect(index, contains('One application for running several manufacturing plants.'),
          reason: 'this is the sentence sign_in_screen.dart prints — a loading surface that '
              'describes the product differently is a second voice');
      expect(index, contains('class="boot-splash__bar"'));
      expect(style, contains('@keyframes boot-splash-slide'),
          reason: 'the indicator never moves, so nothing says the wait is progressing');
    });

    test("follows the reader's palette, in the app's own tokens", () {
      final darkAt = style.indexOf('@media (prefers-color-scheme: dark)');
      expect(darkAt, greaterThan(0),
          reason: 'a reader whose palette is dark is shown the light surface first — '
              'which is the white flash this surface exists to remove');
      final light = style.substring(0, darkAt);
      final dark = style.substring(darkAt);

      final tokens = <String, ({Color light, Color dark})>{
        'boot-canvas': (light: AppPalette.light.canvas, dark: AppPalette.dark.canvas),
        'boot-ink': (light: AppPalette.light.textPrimary, dark: AppPalette.dark.textPrimary),
        'boot-muted-ink': (light: AppPalette.light.textMuted, dark: AppPalette.dark.textMuted),
        'boot-action': (light: AppPalette.light.actionPrimary, dark: AppPalette.dark.actionPrimary),
        'boot-track': (light: AppPalette.light.surfaceMuted, dark: AppPalette.dark.surfaceMuted),
      };
      tokens.forEach((name, pair) {
        expect(_cssProperty(light, name), _hex(pair.light),
            reason: '--$name in the light surface is not the palette token that names it');
        expect(_cssProperty(dark, name), _hex(pair.dark),
            reason: '--$name in the dark surface is not the palette token that names it');
      });
    });

    test('leaves nothing in the tab order', () {
      // Read the markup, not the prose: the file's own comments name these
      // elements to say they are absent.
      final markup = index.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(RegExp(r'<a[\s>]').hasMatch(markup), isFalse,
          reason: 'a link in the boot surface is a focus target the app then inherits');
      expect(markup, isNot(contains('<button')));
      expect(markup, isNot(contains('<input')));
      expect(markup, isNot(contains('tabindex')));
    });

    test('is removed from the document when the engine paints its first frame', () {
      expect(index, contains("addEventListener('flutter-first-frame'"),
          reason: 'nothing listens for the first frame, so the surface would sit over the app forever');
      expect(index, contains('removeChild(splash)'),
          reason: 'the surface must leave the document; a hidden-but-present node is the ghost');
      expect(index.indexOf('flutter-first-frame'), lessThan(index.indexOf('flutter_bootstrap.js')),
          reason: 'the listener is registered after the bootstrap script, so the signal can arrive unheard');
    });

    test('stops moving when the reader asks, and needs nothing fetched to paint', () {
      expect(style, contains('@media (prefers-reduced-motion: reduce)'),
          reason: 'the indicator animates for a reader who asked for less motion');
      expect(style, isNot(contains('url(')),
          reason: 'a background image is another request before the surface can paint');
      expect(index.indexOf('id="boot-splash"'), lessThan(index.indexOf('flutter_bootstrap.js')),
          reason: 'the surface is drawn after the bundle starts loading, so it cannot precede the wait it covers');
    });
  });
}

/// One `--custom-property` value out of a CSS fragment, spelled the way
/// `index.html` spells it (upper case).
String _cssProperty(String css, String name) {
  final match = RegExp('--$name:\\s*(#[0-9A-Fa-f]{6})').firstMatch(css);
  expect(match, isNotNull, reason: 'the boot surface declares no --$name');
  return match!.group(1)!.toUpperCase();
}
