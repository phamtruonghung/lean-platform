/// The edge's security headers: what `nginx.conf` declares, and the one thing
/// the app's own files must keep true for the policy to stay strict.
///
/// Checked from the source files rather than by curling a deployment, for the
/// same reason `web_assets_test.dart` checks `web/` directly: a policy that
/// silently lost a directive, or a `location` block that quietly dropped every
/// inherited header, is a regression no other test would see — the page still
/// loads, and only a browser's console would say so.
///
/// `nginx`'s `add_header` does not merge across levels. A `location` that sets
/// any header of its own drops every header inherited from the `server` block,
/// `Cache-Control` and the CSP included. That is why the test walks the file's
/// block structure instead of grepping for a line.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `nginx.conf`'s own lines with comment lines removed. A `#` only starts a
/// comment at the start of a line in this file's style, and no value here
/// contains one, so this is exact enough to keep the block walk honest.
List<String> _code(String text) => text
    .split('\n')
    .where((line) => !RegExp(r'^\s*#').hasMatch(line))
    .where((line) => line.trim().isNotEmpty)
    .toList();

/// The value of `add_header <name> "<value>"` at `server` level, or null.
String? _serverHeader(List<String> lines, String name) {
  final pattern = RegExp('^\\s*add_header\\s+$name\\s+"([^"]*)"');
  for (final line in lines) {
    final match = pattern.firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

void main() {
  final nginx = File('nginx.conf');
  final lines = _code(nginx.readAsStringSync());

  group('nginx.conf', () {
    test('exists where the frontend image copies it from', () {
      expect(nginx.existsSync(), isTrue, reason: 'frontend/Dockerfile copies nginx.conf into the image');
    });

    test('sends HSTS with a max-age and includeSubDomains', () {
      final value = _serverHeader(lines, 'Strict-Transport-Security');
      expect(value, isNotNull, reason: 'no Strict-Transport-Security at server level');
      final maxAge = RegExp(r'max-age=(\d+)').firstMatch(value!)?.group(1);
      expect(maxAge, isNotNull, reason: 'HSTS without a max-age is not a policy');
      // At least half a year: shorter than that and a browser forgets between
      // visits, longer than a year and rolling back a TLS mistake is a wait.
      expect(int.parse(maxAge!), greaterThanOrEqualTo(15552000),
          reason: 'max-age=$maxAge is shorter than the 180 days this file argues for');
      expect(value, contains('includeSubDomains'));
      expect(value, isNot(contains('preload')),
          reason: 'preload is a submission to a vendor list, not a header to assert unasked');
    });

    test('sends a CSP that starts closed and is explicit about each allowance', () {
      final value = _serverHeader(lines, 'Content-Security-Policy');
      expect(value, isNotNull, reason: 'no Content-Security-Policy at server level');
      expect(value, startsWith("default-src 'self'"),
          reason: 'the policy does not start from a closed default');
      // The session token is in a script-readable store, so script-src is the
      // directive worth protecting: no 'unsafe-inline' and no 'unsafe-eval'.
      final scriptSrc = RegExp(r"script-src ([^;]+)").firstMatch(value!)?.group(1);
      expect(scriptSrc, isNotNull, reason: 'the policy names no script-src, so scripts fall back to default-src');
      expect(scriptSrc, contains("'self'"));
      expect(scriptSrc, isNot(contains("'unsafe-inline'")),
          reason: 'index.html must load its boot-splash listener as a file, not inline');
      expect(scriptSrc, isNot(contains("'unsafe-eval'")),
          reason: "'unsafe-eval' is not needed; 'wasm-unsafe-eval' is what canvaskit.wasm requires");
      expect(scriptSrc, contains("'wasm-unsafe-eval'"),
          reason: 'Chrome refuses to compile canvaskit.wasm without it');
      expect(value, contains("style-src 'self' 'unsafe-inline'"),
          reason: 'the engine and the boot surface both write styles at runtime');
      expect(value, contains("connect-src 'self'"),
          reason: 'the app calls /api on this same origin and nothing else');
      expect(value, contains("frame-ancestors 'self'"),
          reason: 'frame-ancestors is what a modern browser reads instead of X-Frame-Options');
      expect(value, contains("base-uri 'self'"));
      expect(value, contains("object-src 'none'"));
    });

    test('declares every header at server level and none inside a location', () {
      // Walk the blocks: depth 1 is inside `server`, depth 2 is inside a
      // `location`. `add_header` at depth 2 would drop every inherited header
      // for that location only — the failure this test exists to catch.
      var depth = 0;
      final offenders = <String>[];
      for (final line in lines) {
        final opens = line.split('{').length - 1;
        final closes = line.split('}').length - 1;
        if (RegExp(r'^\s*add_header\b').hasMatch(line) && depth > 1) {
          offenders.add(line.trim());
        }
        depth += opens - closes;
      }
      expect(depth, 0, reason: 'nginx.conf has unbalanced braces — this test cannot read it');
      expect(offenders, isEmpty,
          reason: 'add_header inside a location drops the server-level headers for that '
              'location (the file\'s own comment says so): ${offenders.join(' | ')}');
    });

    test('sends them on error responses too', () {
      // `always` is what makes a 404 or a 500 carry the header. Without it
      // nginx omits them on anything that is not 2xx/3xx, and the first
      // response a browser sees is exactly the one that matters.
      for (final name in const [
        'Strict-Transport-Security',
        'Content-Security-Policy',
        'X-Content-Type-Options',
        'X-Frame-Options',
        'Referrer-Policy',
      ]) {
        final line = lines.firstWhere(
          (l) => RegExp('^\\s*add_header\\s+$name\\b').hasMatch(l),
          orElse: () => '',
        );
        expect(line, endsWith('always;'), reason: '$name is not sent with `always`');
      }
    });
  });

  group('the app under that policy', () {
    final index = File('web/index.html').readAsStringSync();
    final markup = index.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    test('loads no inline script, which is what keeps script-src on \'self\'', () {
      final tags = RegExp(r'<script\b[^>]*>([\s\S]*?)</script>').allMatches(markup).toList();
      expect(tags, isNotEmpty, reason: 'index.html loads no script at all — this test would pass vacuously');
      for (final tag in tags) {
        final open = tag.group(0)!.substring(0, tag.group(0)!.indexOf('>'));
        expect(open, contains('src='),
            reason: 'an inline <script> is blocked by script-src \'self\': '
                '${tag.group(0)!.trim().split('\n').first}');
        expect(tag.group(1)!.trim(), isEmpty,
            reason: 'script content between the tags runs inline and would be blocked');
      }
    });

    test('loads the boot-splash listener as its own file, before the bundle', () {
      final splash = File('web/boot_splash.js');
      expect(splash.existsSync(), isTrue,
          reason: 'index.html references boot_splash.js, which `flutter build web` copies from web/');
      expect(splash.readAsStringSync(), contains("addEventListener('flutter-first-frame'"));
      expect(markup.indexOf('src="boot_splash.js"'),
          lessThan(markup.indexOf('src="flutter_bootstrap.js"')),
          reason: 'a synchronous script runs in document order; this one must precede the bundle');
    });
  });
}
