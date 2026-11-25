/// The sitting store everywhere `package:web` is unavailable (the Dart VM a
/// widget test runs on): in memory, per instance. See
/// `assessment_sitting_store.dart`.
library;

import 'assessment_sitting_store.dart';

class _MemorySittingStore implements AssessmentSittingStore {
  final Map<String, String> _tokens = {};

  @override
  String? read(String attemptId) => _tokens[attemptId];

  @override
  void write(String attemptId, String token) => _tokens[attemptId] = token;

  @override
  void clear(String attemptId) => _tokens.remove(attemptId);
}

AssessmentSittingStore createAssessmentSittingStore() => _MemorySittingStore();
