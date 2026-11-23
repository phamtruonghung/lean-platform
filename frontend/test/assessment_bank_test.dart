/// The assessment Question bank (issue #588, ADR-0068, slice 2) — the wire
/// faked, the one client seam (ADR-0012, AGENTS.md §5).
///
/// What a person sees and does on `/assessments/questions`: choose a process
/// (a Site, then an Org Unit found by name), read its Questions a page at a
/// time, and — only with `PPL_ASSESSMENT_CHANGE` — add one, correct one, retire
/// one or paste a block of them. Every assertion is on rendered text, a `Key`,
/// or a request the fake wire recorded; nothing reads a Bloc.
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_bank_paste_dialog.dart';
import 'package:lean_platform/people/assessment_paste.dart';
import 'package:lean_platform/people/assessment_question_form_dialog.dart';
import 'package:lean_platform/people/assessment_questions_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _change = 'PPL_ASSESSMENT_CHANGE';

const _braiding = '11';

List<Map<String, dynamic>> _bank() => [
      assessmentQuestionJson(1, _braiding, 'Khi máy braiding dừng đột ngột, bước đầu tiên là gì?'),
      assessmentQuestionJson(
        2,
        _braiding,
        'Bobbin nào cần thay trước?',
        correctOption: 'A',
        explanation: null,
      ),
      assessmentQuestionJson(3, _braiding, 'Đèn báo nào nghĩa là dừng?', isActive: false),
      assessmentQuestionJson(4, '12', 'Một câu hỏi của công đoạn khác?'),
    ];

FakeWire _wire({
  List<String> permissions = const [_display, _change],
  String role = Roles.supervisor,
  List<Map<String, dynamic>>? questions,
  bool revealKey = true,
  int bulkStatus = 201,
  String bulkMessage = 'That paste could not be filed.',
  int? bulkLine,
  int createStatus = 201,
  String createMessage = 'That Question could not be added.',
}) =>
    FakeWire(
      role: role,
      mePermissions: permissions,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnitSearchResults: [orgUnitJson(_braiding, 'Braiding')],
      assessmentQuestions: questions ?? _bank(),
      assessmentRevealKey: revealKey,
      assessmentBulkStatus: bulkStatus,
      assessmentBulkMessage: bulkMessage,
      assessmentBulkLine: bulkLine,
      createAssessmentQuestionStatus: createStatus,
      createAssessmentQuestionMessage: createMessage,
    );

/// A window tall enough that the whole page is built: a `ListView` builds only
/// what is near the viewport, and a test asserting on a Question further down
/// the page must not depend on the default 800x600 surface.
void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 3200);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeWire wire, {String location = Routes.assessmentQuestions}) {
  _tall(tester);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

/// Picks Braiding the way a person does: types two characters into the process
/// field, waits out its debounce, and taps the suggestion.
Future<void> _chooseBraiding(WidgetTester tester) async {
  await typeInSearchField(tester, AssessmentQuestionsScreen.processSearchKey, 'Br');
  await tester.pump();
  await tapIn(tester, find.byKey(AssessmentQuestionsScreen.processSuggestionKey(_braiding)));
}

void main() {
  testWidgets('a reader sees the Questions and the active count, and no Add or Paste button',
      (tester) async {
    final wire = _wire(permissions: const [_display], revealKey: false);
    await _open(tester, wire);
    await _chooseBraiding(tester);

    expect(find.byType(AssessmentQuestionsScreen), findsOneWidget);
    expect(find.text('Khi máy braiding dừng đột ngột, bước đầu tiên là gì?'), findsOneWidget);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(1)), findsOneWidget);
    // Two active Questions in Braiding; the retired one and the other process
    // are not counted or shown.
    expect(find.text('Active Questions: 2'), findsOneWidget);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(3)), findsNothing);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(4)), findsNothing);

    expect(find.byKey(AssessmentQuestionsScreen.addKey), findsNothing);
    expect(find.byKey(AssessmentQuestionsScreen.pasteKey), findsNothing);
    expect(find.byKey(AssessmentQuestionsScreen.editKey(1)), findsNothing);
    expect(find.byKey(AssessmentQuestionsScreen.retireKey(1)), findsNothing);
  });

  testWidgets('a key the server withheld renders a dash, never the word null', (tester) async {
    final wire = _wire(permissions: const [_display], revealKey: false);
    await _open(tester, wire);
    await _chooseBraiding(tester);

    expect(find.text('Key: —'), findsNWidgets(2));
    expect(find.text('Explanation: —'), findsNWidgets(2));
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('the key and explanation show when the server sent them', (tester) async {
    await _open(tester, _wire());
    await _chooseBraiding(tester);

    expect(find.text('Key: C'), findsOneWidget);
    expect(find.text('Key: A'), findsOneWidget);
    expect(find.text('Explanation: Dừng khẩn cấp trước.'), findsOneWidget);
  });

  testWidgets('choosing a process sends its orgUnitId', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    expect(wire.assessmentQuestionReads, isEmpty, reason: 'nothing is read before a process is chosen');

    await _chooseBraiding(tester);

    expect(wire.assessmentQuestionReads, isNotEmpty);
    final asked = Uri.parse(wire.assessmentQuestionReads.last);
    expect(asked.path, '/api/people/assessment-questions');
    expect(asked.queryParameters['orgUnitId'], _braiding);
    expect(asked.queryParameters.containsKey('includeInactive'), isFalse);
  });

  testWidgets('Include retired re-reads with includeInactive=true and shows the retired Question',
      (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(3)), findsNothing);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.includeRetiredKey));

    final asked = Uri.parse(wire.assessmentQuestionReads.last);
    expect(asked.queryParameters['includeInactive'], 'true');
    expect(asked.queryParameters['orgUnitId'], _braiding);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(3)), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    // A retired Question carries no Correct or Retire.
    expect(find.byKey(AssessmentQuestionsScreen.retireKey(3)), findsNothing);
  });

  testWidgets('paging follows total, offset and limit', (tester) async {
    final wire = _wire(questions: [
      for (var i = 1; i <= 52; i++) assessmentQuestionJson(i, _braiding, 'Câu hỏi số $i về an toàn?'),
    ]);
    await _open(tester, wire);
    await _chooseBraiding(tester);

    expect(find.text('1–50 of 52'), findsOneWidget);
    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.nextKey));
    final asked = Uri.parse(wire.assessmentQuestionReads.last);
    expect(asked.queryParameters['offset'], '50');
    expect(find.text('51–52 of 52'), findsOneWidget);
  });

  testWidgets('Add opens the form, and saving records a POST with the right body', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.addKey));
    await tester.enterText(
      find.byKey(AssessmentQuestionFormDialog.stemKey),
      'Khi nào phải đeo kính bảo hộ?',
    );
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('A')), 'Luôn luôn');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('B')), 'Không bao giờ');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('C')), 'Khi chạy máy');
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.keyChoiceKey('A')));
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.submitKey));

    expect(wire.assessmentQuestionPosts, [
      {
        'orgUnitId': _braiding,
        'questionText': 'Khi nào phải đeo kính bảo hộ?',
        'optionA': 'Luôn luôn',
        'optionB': 'Không bao giờ',
        'optionC': 'Khi chạy máy',
        'correctOption': 'A',
        'explanation': null,
      },
    ]);
    // The dialog closed and the list was re-read.
    expect(find.byKey(AssessmentQuestionFormDialog.stemKey), findsNothing);
    expect(find.text('Khi nào phải đeo kính bảo hộ?'), findsOneWidget);
    expect(find.text('Active Questions: 3'), findsOneWidget);
  });

  testWidgets('the form refuses a 4-character stem without sending', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.addKey));
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.stemKey), 'Máy?');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('A')), 'Một');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('B')), 'Hai');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('C')), 'Ba');
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.keyChoiceKey('B')));
    await tester.pumpAndSettle();

    expect(find.text('The Question needs at least 5 characters.'), findsOneWidget);
    await tester.tap(find.byKey(AssessmentQuestionFormDialog.submitKey), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(wire.assessmentQuestionPosts, isEmpty);
    expect(find.byKey(AssessmentQuestionFormDialog.stemKey), findsOneWidget);
  });

  testWidgets('the server\'s refusal of a Question is reported in the open form', (tester) async {
    final wire = _wire(
      createStatus: 409,
      createMessage: 'this Question is already in the bank as Question 1: "Khi máy braiding dừng"',
    );
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.addKey));
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.stemKey), 'Khi máy braiding dừng');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('A')), 'Một');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('B')), 'Hai');
    await tester.enterText(find.byKey(AssessmentQuestionFormDialog.optionKey('C')), 'Ba');
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.keyChoiceKey('C')));
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.submitKey));

    expect(find.byKey(AssessmentQuestionFormDialog.failureKey), findsOneWidget);
    expect(find.textContaining('already in the bank as Question 1'), findsOneWidget);
  });

  testWidgets('Correct sends the whole restatement as a PATCH', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.editKey(1)));
    await tester.enterText(
      find.byKey(AssessmentQuestionFormDialog.stemKey),
      'Khi máy braiding dừng đột ngột, việc đầu tiên là gì?',
    );
    await tapIn(tester, find.byKey(AssessmentQuestionFormDialog.submitKey));

    final (id, body) = wire.assessmentQuestionPatches.single;
    expect(id, '1');
    expect(body['questionText'], 'Khi máy braiding dừng đột ngột, việc đầu tiên là gì?');
    expect(body['optionA'], 'Mở cửa bảo vệ');
    expect(body['correctOption'], 'C');
    expect(body['explanation'], 'Dừng khẩn cấp trước.');
    expect(find.text('Khi máy braiding dừng đột ngột, việc đầu tiên là gì?'), findsOneWidget);
  });

  testWidgets('Retire asks for confirmation, then sends a DELETE', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.retireKey(2)));
    expect(find.text('Retire this Question?'), findsOneWidget);

    // Cancelling sends nothing.
    await tapIn(tester, find.byKey(AppConfirmDialog.dismissKey));
    expect(wire.assessmentQuestionRetires, isEmpty);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(2)), findsOneWidget);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.retireKey(2)));
    await tapIn(tester, find.byKey(AppConfirmDialog.confirmKey));

    expect(wire.assessmentQuestionRetires, ['2']);
    expect(wire.requests, contains('DELETE /api/people/assessment-questions/2'));
    // Re-read: the retired Question is out of the default list.
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(2)), findsNothing);
    expect(find.text('Active Questions: 1'), findsOneWidget);
  });

  testWidgets('a page emptied by a retire falls back to the last page that has rows, pager intact',
      (tester) async {
    final wire = _wire(questions: [
      for (var i = 1; i <= 51; i++) assessmentQuestionJson(i, _braiding, 'Câu hỏi số $i về an toàn?'),
    ]);
    await _open(tester, wire);
    await _chooseBraiding(tester);
    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.nextKey));
    expect(find.text('51–51 of 51'), findsOneWidget);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.retireKey(51)));
    await tapIn(tester, find.byKey(AppConfirmDialog.confirmKey));

    expect(find.byKey(AssessmentQuestionsScreen.emptyKey), findsNothing);
    expect(find.byKey(AssessmentQuestionsScreen.rowKey(50)), findsOneWidget);
    expect(find.text('1–50 of 50'), findsOneWidget);
    expect(find.byKey(AssessmentQuestionsScreen.previousKey), findsOneWidget);
    expect(find.byKey(AssessmentQuestionsScreen.nextKey), findsOneWidget);
  });

  testWidgets('a process whose first read fails shows no active count', (tester) async {
    final wire = _wire();
    wire.assessmentQuestionsStatus = 500;
    await _open(tester, wire);
    await _chooseBraiding(tester);

    expect(find.byKey(AssessmentQuestionsScreen.pageFailureKey), findsOneWidget);
    expect(find.byKey(AssessmentQuestionsScreen.activeCountKey), findsNothing);
    expect(find.textContaining('Active Questions'), findsNothing);
  });

  test('the paste Preview accepts a decomposed stem label', () {
    // A macOS document decomposes Vietnamese; the server normalises to NFC first.
    final result = parseAssessmentPaste(
      'Ca\u0302u ho\u0309i: Khi máy dừng thì làm gì?\nA. Một\nB. Hai\n*C. Ba',
    );

    expect(result.issue, isNull);
    expect(result.blocks, hasLength(1));
    expect(result.blocks.single.key, 'C');
  });

  testWidgets('Preview reports how many Questions a paste holds and each key', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.pasteKey));
    await tester.enterText(find.byKey(AssessmentBankPasteDialog.textKey), _twoBlocks);
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssessmentBankPasteDialog.previewKey));

    expect(find.text('2 questions, keys C, A'), findsOneWidget);
    expect(wire.assessmentBulkPosts, isEmpty, reason: 'a preview sends nothing');
  });

  testWidgets('Preview names the offending line before anything is sent', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.pasteKey));
    await tester.enterText(
      find.byKey(AssessmentBankPasteDialog.textKey),
      '$_twoBlocks\n\nCâu hỏi: Khối thiếu đáp án?\nA. Một\nB. Hai\nC. Ba',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssessmentBankPasteDialog.previewKey));

    expect(find.textContaining('Line 16, question 3: no option is marked with *.'), findsOneWidget);
    expect(wire.assessmentBulkPosts, isEmpty);
  });

  testWidgets('Paste sends orgUnitId and the text, and closes when it is filed', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.pasteKey));
    await tester.enterText(find.byKey(AssessmentBankPasteDialog.textKey), _twoBlocks);
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssessmentBankPasteDialog.submitKey));

    expect(wire.assessmentBulkPosts, [
      {'orgUnitId': _braiding, 'text': _twoBlocks},
    ]);
    expect(find.byKey(AssessmentBankPasteDialog.textKey), findsNothing);
  });

  testWidgets('a refused paste shows the line the server named and says nothing was written',
      (tester) async {
    final wire = _wire(
      bulkStatus: 400,
      bulkMessage: 'line 6: no option is marked *',
      bulkLine: 6,
    );
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.pasteKey));
    await tester.enterText(find.byKey(AssessmentBankPasteDialog.textKey), _twoBlocks);
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssessmentBankPasteDialog.submitKey));

    // The dialog stays open with the text, names the line, and says the bank
    // is unchanged.
    expect(find.byKey(AssessmentBankPasteDialog.textKey), findsOneWidget);
    expect(find.byKey(AssessmentBankPasteDialog.refusalLineKey), findsOneWidget);
    expect(find.text('Line 6'), findsOneWidget);
    expect(find.text('line 6: no option is marked *'), findsOneWidget);
    expect(find.text('Nothing was written. Fix that block and paste again.'), findsOneWidget);
  });

  testWidgets('a paste meeting a Question already in the bank is refused naming its stem',
      (tester) async {
    final wire = _wire(
      bulkStatus: 409,
      bulkMessage:
          'line 1: this Question is already in the bank as Question 1: "Khi máy braiding dừng đột ngột, bước đầu tiên là gì?"',
      bulkLine: 1,
    );
    await _open(tester, wire);
    await _chooseBraiding(tester);

    await tapIn(tester, find.byKey(AssessmentQuestionsScreen.pasteKey));
    await tester.enterText(find.byKey(AssessmentBankPasteDialog.textKey), _twoBlocks);
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(AssessmentBankPasteDialog.submitKey));

    expect(find.byKey(AssessmentBankPasteDialog.refusalKey), findsOneWidget);
    expect(find.textContaining('Khi máy braiding dừng đột ngột, bước đầu tiên là gì?'), findsWidgets);
    expect(find.text('Line 1'), findsOneWidget);
  });

  testWidgets('the sidebar offers Assessments to a caller holding the display code', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: _wire().client,
    );

    expect(find.text('Assessments'), findsWidgets);
  });

  testWidgets('the sidebar hides Assessments from a caller without the display code', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: _wire(permissions: const ['PPL_DIRECTORY_DISPLAY']).client,
    );

    expect(find.text('Directory'), findsWidgets);
    expect(find.text('Assessments'), findsNothing);
  });

  testWidgets('the Assessments address lands on the Question bank', (tester) async {
    await _open(tester, _wire(), location: Routes.assessments);

    expect(find.byType(AssessmentQuestionsScreen), findsOneWidget);
    expect(find.text('Question bank'), findsWidgets);
  });

  testWidgets('a caller without the display code is shown the access-denied Screen at the address',
      (tester) async {
    await _open(tester, _wire(permissions: const ['PPL_DIRECTORY_DISPLAY']));

    expect(find.byType(AssessmentQuestionsScreen), findsNothing);
    expect(find.text('Not available to you'), findsOneWidget);
  });
}

/// Two blocks, eleven lines with the blank line between; a third block pasted
/// after a further blank line starts its stem on line 13.
const String _twoBlocks = '''Câu hỏi: Khi máy braiding dừng đột ngột, bước đầu tiên là gì?
A. Mở cửa bảo vệ và kiểm tra bobbin
B. Dừng máy và gọi Team Leader
*C. Nhấn nút dừng khẩn cấp
Giải thích: Dừng khẩn cấp trước, rồi mới gọi người.

Question: Which light means stop?
*A. Red
B. Green
C. Blue
Explanation: Red always means stop.''';
