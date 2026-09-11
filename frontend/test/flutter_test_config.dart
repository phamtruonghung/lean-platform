import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Picked up automatically by `flutter test` for every test file in this
/// directory (and below).
///
/// A tap that derives an offset which does not hit test on its own target is
/// a bug, not a warning — the default compact reporter hides it, and the
/// test then fails later with an unrelated-looking "found 0 widgets", which
/// is exactly what happened before `tapIn`/`pickDate` existed (issue #126):
/// the assignment dialog's effective-date field sits exactly on its scroll
/// viewport's clip boundary on the 800x600 test surface, so a bare
/// `tester.tap` missed it by a pixel and the resulting failure pointed
/// nowhere near the real cause. Making the warning fatal turns that class of
/// mistake into an immediate, readable failure at the tap site instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
