/// Where the floor's Assessment sitting token is kept between requests (issue
/// #588, ADR-0068, slice 5; spec section 9.1).
///
/// The token is the floor sitting's authority for one running paper (the
/// `x-assessment-sitting` header), minted by `start` and good until the paper's
/// deadline plus five minutes. It lives in the **tab's session storage** and
/// nowhere else: a closed tab or a rebooted tablet loses it, and the candidate
/// identifies again with number and PIN to get the same paper under a new token.
/// A token that survived a reboot would have to live in persistent storage on a
/// shared device, which is the cost the design refuses.
///
/// A seam, for the reason [DocumentChrome] is one: the browser's storage lives
/// behind a conditional import (`package:web`), and everywhere else — the Dart
/// VM a widget test runs on — the stub keeps the tokens in memory, so a test
/// drives the same Bloc without a browser. One entry per Attempt, so a token for
/// one paper can never be read back for another.
library;

import 'assessment_sitting_store_stub.dart'
    if (dart.library.js_interop) 'assessment_sitting_store_web.dart' as impl;

abstract interface class AssessmentSittingStore {
  /// The token kept for [attemptId], or null.
  String? read(String attemptId);

  void write(String attemptId, String token);

  void clear(String attemptId);
}

/// The store this platform has: the tab's session storage on the web, memory
/// where there is no browser.
AssessmentSittingStore createAssessmentSittingStore() => impl.createAssessmentSittingStore();
