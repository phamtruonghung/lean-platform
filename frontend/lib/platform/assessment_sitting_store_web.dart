/// The tab's session storage (`package:web`, no plugin and no native code). Only
/// compiled where `dart.library.js_interop` exists; see
/// `assessment_sitting_store.dart`.
library;

import 'package:web/web.dart' as web;

import 'assessment_sitting_store.dart';

class _SessionSittingStore implements AssessmentSittingStore {
  const _SessionSittingStore();

  static String _key(String attemptId) => 'assessment-sitting:$attemptId';

  @override
  String? read(String attemptId) => web.window.sessionStorage.getItem(_key(attemptId));

  @override
  void write(String attemptId, String token) =>
      web.window.sessionStorage.setItem(_key(attemptId), token);

  @override
  void clear(String attemptId) => web.window.sessionStorage.removeItem(_key(attemptId));
}

AssessmentSittingStore createAssessmentSittingStore() => const _SessionSittingStore();
