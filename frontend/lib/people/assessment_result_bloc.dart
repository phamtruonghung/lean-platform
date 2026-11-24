/// The result of one Attempt (issue #588, ADR-0068, slice 4): the two scores,
/// the verdict the server derived, and every Question with the candidate's
/// Answer, the key, the point and the explanation.
///
/// **Before the award there is no result, and that is a state, not a failure.**
/// The route answers 409 until the Attempt is `marked` (spec section 3.12), so a
/// 409 renders "awaiting marking" — plus the candidate's own Answers, which the
/// paper route still gives them — rather than an error the person cannot act on.
///
/// **The verdict is not computed here.** `passed` arrives from the server, which
/// derives it from `final_score >= pass_mark` at read and never stores it (spec
/// section 3.13). A Screen that compared the two numbers itself would be a
/// second opinion nobody asked for.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

sealed class AssessmentResultEvent {
  const AssessmentResultEvent();
}

/// Load the result. Also the retry a failed load offers.
class AssessmentResultStarted extends AssessmentResultEvent {
  const AssessmentResultStarted(this.attemptId);

  final String attemptId;
}

sealed class AssessmentResultState {
  const AssessmentResultState();
}

class AssessmentResultLoading extends AssessmentResultState {
  const AssessmentResultLoading();
}

class AssessmentResultUnavailable extends AssessmentResultState {
  const AssessmentResultUnavailable({required this.message});

  final String message;
}

/// The Attempt is not marked yet. [answers] are the candidate's own Answers when
/// the caller is the person who sat it, and empty for a reader who may not open
/// the paper.
class AssessmentResultAwaitingMarking extends AssessmentResultState {
  const AssessmentResultAwaitingMarking({required this.attempt, this.answers = const []});

  final AssessmentAttempt attempt;
  final List<AssessmentMarkedQuestion> answers;
}

class AssessmentResultLoaded extends AssessmentResultState {
  const AssessmentResultLoaded({required this.result});

  final AssessmentResult result;
}

class AssessmentResultBloc extends Bloc<AssessmentResultEvent, AssessmentResultState> {
  AssessmentResultBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.attemptId,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentResultLoading()) {
    on<AssessmentResultStarted>(_onStarted);
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  final String attemptId;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  Future<void> _onStarted(
    AssessmentResultStarted event,
    Emitter<AssessmentResultState> emit,
  ) async {
    emit(const AssessmentResultLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentResultUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final result = await _api.fetchAssessmentResult(token, event.attemptId);
      emit(AssessmentResultLoaded(result: result));
    } on PeopleApiException catch (error) {
      if (error.statusCode == 409) {
        emit(await _awaiting(token, error.message));
        return;
      }
      emit(AssessmentResultUnavailable(message: error.message));
    }
  }

  /// The 409 path: read the candidate's own paper for their Answers, and say
  /// plainly that nobody has marked it. A caller who may not open the paper (a
  /// reader of somebody else's unmarked Attempt) gets the sentence alone.
  Future<AssessmentResultState> _awaiting(String token, String message) async {
    try {
      final paper = await _api.fetchAssessmentPaper(token, attemptId);
      return AssessmentResultAwaitingMarking(
        attempt: paper.attempt,
        answers: [
          for (final question in paper.questions)
            AssessmentMarkedQuestion(
              position: question.position,
              questionText: question.questionText,
              optionA: question.optionA,
              optionB: question.optionB,
              optionC: question.optionC,
              correctOption: '',
              points: 0,
              chosenOption: question.chosenOption,
              otherText: question.otherText,
            ),
        ],
      );
    } on PeopleApiException {
      return AssessmentResultAwaitingMarking(
        attempt: AssessmentAttempt(
          id: attemptId,
          assessmentId: '',
          employeeId: '',
          attemptNo: 1,
          orgUnitId: '',
          orgUnitResolvedOn: '',
          status: attemptSubmitted,
          submittedLate: false,
          otherAnswerCount: 0,
          blankCount: 0,
        ),
      );
    }
  }
}
