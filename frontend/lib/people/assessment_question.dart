/// One Question in a process's bank (issue #588, ADR-0068) — exactly the wire
/// shape `GET /api/people/assessment-questions` sends (assessment-questions.js's
/// `toQuestion`). Codes only: nothing here is a language and nothing imports
/// Flutter.
///
/// [correctOption] and [explanation] are null, never absent, when the server
/// withheld them: the key goes only to a caller who holds the maintain code
/// and has write reach on the process. A Screen renders a null as a dash.
library;

/// The three letters an Option wears, and the only values a key can take.
const List<String> assessmentOptionLetters = ['A', 'B', 'C'];

/// A Question's own text is at least this long, mirroring the table's CHECK.
const int assessmentQuestionTextMin = 5;

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.orgUnitId,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    this.correctOption,
    this.explanation,
    this.isActive = true,
  });

  factory AssessmentQuestion.fromJson(Map<String, dynamic> json) => AssessmentQuestion(
        id: json['id'].toString(),
        orgUnitId: json['orgUnitId'].toString(),
        questionText: json['questionText'] as String,
        optionA: json['optionA'] as String,
        optionB: json['optionB'] as String,
        optionC: json['optionC'] as String,
        correctOption: json['correctOption'] as String?,
        explanation: json['explanation'] as String?,
        isActive: json['isActive'] != false,
      );

  final String id;
  final String orgUnitId;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;

  /// 'A', 'B' or 'C' — or null when the server did not reveal it.
  final String? correctOption;
  final String? explanation;
  final bool isActive;

  /// The text of the Option lettered [letter].
  String optionFor(String letter) => switch (letter) {
        'A' => optionA,
        'B' => optionB,
        _ => optionC,
      };

  Map<String, Object?> toJson() => {
        'id': id,
        'orgUnitId': orgUnitId,
        'questionText': questionText,
        'optionA': optionA,
        'optionB': optionB,
        'optionC': optionC,
        'correctOption': correctOption,
        'explanation': explanation,
        'isActive': isActive,
      };
}

/// One page of a process's bank: the rows, how many rows the filter matches
/// ([total], what paging walks) and how many Questions are active in the
/// process whatever the filter ([activeCount], what a paper's size is checked
/// against).
class AssessmentQuestionPage {
  const AssessmentQuestionPage({
    required this.questions,
    required this.total,
    required this.activeCount,
  });

  factory AssessmentQuestionPage.fromJson(Map<String, dynamic> json) => AssessmentQuestionPage(
        questions: [
          for (final row in json['questions'] as List<dynamic>)
            AssessmentQuestion.fromJson(row as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
        activeCount: (json['activeCount'] as num).toInt(),
      );

  final List<AssessmentQuestion> questions;
  final int total;
  final int activeCount;
}
