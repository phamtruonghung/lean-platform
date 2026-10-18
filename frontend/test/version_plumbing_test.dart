// Drift guard for the build's version (issue #297). Three files have to agree
// on one define name: the Dockerfile that forwards it, the Dart reader, and
// the release workflow that supplies it. A rename in one and not the others
// would silently ship `dev`, so this test fails the build instead.
//
// It reads files outside `frontend/`, so it must run from a whole-repo
// checkout. A missing file FAILS rather than skips: a green run that checked
// nothing is worse than a red one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one place the define name lives for this test.
const _define = 'APP_VERSION';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — run from a whole-repo checkout; only frontend/ was copied?');
  }
  return file.readAsStringSync();
}

void main() {
  test('the Dockerfile, the reader and release.yml agree on the version define', () {
    final dockerfile = _read('Dockerfile');
    final reader = _read('lib/app_version.dart');
    final release = _read('../.github/workflows/release.yml');

    expect(dockerfile, contains('ARG $_define'), reason: 'Dockerfile must declare the build arg');
    expect(
      dockerfile,
      contains('--dart-define=$_define="\${$_define}"'),
      reason: 'Dockerfile must pass it to flutter build web',
    );
    expect(
      dockerfile,
      contains('"\${$_define:-dev}" > build/web/version.txt'),
      reason: 'Dockerfile must write version.txt into the bundle',
    );
    expect(
      reader,
      contains("String.fromEnvironment('$_define')"),
      reason: 'lib/app_version.dart must read the same define',
    );
    expect(
      release,
      contains("format('$_define={0}', steps.meta.outputs.tag)"),
      reason: 'release.yml must pass the computed tag as the build arg',
    );
  });
}
