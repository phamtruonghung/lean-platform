/// The paste a Team Leader fills a bank with (issue #588 section 12), read on
/// the client so a **Preview** can say what the paste holds — or which line is
/// wrong — before anything is sent. The server parses the same format again and
/// is the authority (assessment-questions.js's `parsePaste`); this copy only
/// gives the answer earlier, and reports codes, not sentences, so the Screen
/// can word them in the reader's language. Nothing here imports Flutter.
///
/// A block starts with `Câu hỏi:` or `Question:`, then three lines beginning
/// `A.`, `B.`, `C.` in order, exactly one prefixed `*`, then an optional
/// `Giải thích:` or `Explanation:` line. A blank line separates blocks. Line
/// numbers are 1-based over the whole text, blank lines counted.
library;

/// What was wrong with a paste.
enum AssessmentPasteProblem {
  /// Nothing but whitespace.
  empty,

  /// A block does not start with a stem label (or its text is empty).
  stem,

  /// A block has fewer than three options ([AssessmentPasteIssue.found] says
  /// how many), or one is lettered out of order.
  options,

  /// No option is marked with `*`.
  noKey,

  /// More than one option is marked with `*`.
  twoKeys,

  /// A line that belongs nowhere: a fourth option, a second explanation, or
  /// two Questions with no blank line between them.
  stray,
}

class AssessmentPasteIssue {
  const AssessmentPasteIssue(this.problem, {this.line, this.question, this.found});

  final AssessmentPasteProblem problem;

  /// The first offending line, 1-based; null only for an empty paste.
  final int? line;

  /// The 1-based ordinal of the Question the problem is in.
  final int? question;

  /// How many options a short block held.
  final int? found;
}

/// One block as the preview reports it: where it starts and which letter is
/// the key.
class AssessmentPasteBlock {
  const AssessmentPasteBlock({required this.line, required this.key});

  final int line;
  final String key;
}

class AssessmentPasteResult {
  const AssessmentPasteResult({this.blocks = const [], this.issue});

  final List<AssessmentPasteBlock> blocks;
  final AssessmentPasteIssue? issue;
}

final RegExp _label = RegExp(r'^\s*([^:]{1,40}?)\s*:\s*(.*)$');
final RegExp _option = RegExp(r'^\s*(\*)?\s*([A-Za-z])\s*\.\s*(.*)$');

// The server compares labels after NFC normalisation (assessment-questions.js's
// `matchLabel`), but macOS documents decompose Vietnamese (base letter plus
// combining marks), so a label copied from one arrives as NFD. The second entry
// of each Vietnamese pair is that decomposed spelling, so Preview agrees with
// the server instead of refusing a paste the server would file.
const List<String> _stemLabels = ['câu hỏi', 'ca\u0302u ho\u0309i', 'question'];
const List<String> _explanationLabels = ['giải thích', 'gia\u0309i thi\u0301ch', 'explanation'];

String? _labelled(String line, List<String> labels) {
  final match = _label.firstMatch(line);
  if (match == null) return null;
  if (!labels.contains(match.group(1)!.toLowerCase())) return null;
  return match.group(2)!.trim();
}

AssessmentPasteResult parseAssessmentPaste(String text) {
  final lines = text.split(RegExp(r'\r\n|\r|\n'));
  if (lines.every((line) => line.trim().isEmpty)) {
    return const AssessmentPasteResult(
      issue: AssessmentPasteIssue(AssessmentPasteProblem.empty),
    );
  }

  final blocks = <AssessmentPasteBlock>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].trim().isEmpty) {
      index += 1;
      continue;
    }
    var end = index;
    while (end < lines.length && lines[end].trim().isNotEmpty) {
      end += 1;
    }
    final ordinal = blocks.length + 1;
    final stemLine = index + 1;

    AssessmentPasteResult refuse(AssessmentPasteProblem problem, int line, {int? found}) =>
        AssessmentPasteResult(
          issue: AssessmentPasteIssue(problem, line: line, question: ordinal, found: found),
        );

    final stem = _labelled(lines[index], _stemLabels);
    if (stem == null || stem.isEmpty) return refuse(AssessmentPasteProblem.stem, stemLine);

    final marked = <String>[];
    final markedLines = <int>[];
    var found = 0;
    var cursor = index + 1;
    while (cursor < end && found < 3) {
      final match = _option.firstMatch(lines[cursor]);
      if (match == null) break;
      final letter = match.group(2)!.toUpperCase();
      if (letter != const ['A', 'B', 'C'][found] || match.group(3)!.trim().isEmpty) {
        return refuse(AssessmentPasteProblem.options, cursor + 1, found: found);
      }
      if (match.group(1) != null) {
        marked.add(letter);
        markedLines.add(cursor + 1);
      }
      found += 1;
      cursor += 1;
    }
    if (found < 3) {
      return refuse(
        AssessmentPasteProblem.options,
        cursor < end ? cursor + 1 : stemLine,
        found: found,
      );
    }
    if (marked.isEmpty) return refuse(AssessmentPasteProblem.noKey, cursor);
    if (marked.length > 1) return refuse(AssessmentPasteProblem.twoKeys, markedLines[1]);

    if (cursor < end) {
      final explanation = _labelled(lines[cursor], _explanationLabels);
      if (explanation == null || explanation.isEmpty) {
        return refuse(AssessmentPasteProblem.stray, cursor + 1);
      }
      cursor += 1;
      if (cursor < end) return refuse(AssessmentPasteProblem.stray, cursor + 1);
    }

    blocks.add(AssessmentPasteBlock(line: stemLine, key: marked.single));
    index = end;
  }
  return AssessmentPasteResult(blocks: blocks);
}
