/// The People Module's last seven Screens' geometry, measured (issue #394).
///
/// The seven Screens of UI phase 2's S8 were re-laid-out, and this file pins
/// what a reader can see of the result — the way `people_geometry_test.dart`
/// pinned #392's six, `quality_geometry_test.dart` pinned #390's and
/// `people_attendance_geometry_test.dart` pinned #393's:
///
/// - **Skills** and **Job roles** are catalogues: the record's own line at the
///   card's left inset and its control at the card's right-hand one, and the
///   control *under* the line once the card's box is narrower than
///   `AppBreakpoints.headerActionsWrap` at the reader's text size — which is
///   where a 700 window and twice the text both land.
/// - **Skill coverage** is a register read across: an `AppTableHeader` band at
///   a wide box, the numbers end-aligned under their own labels, and the
///   shortfall painted with the tone its counts carry (`StatusTone`), with a
///   legend built from the tones the rows actually paint. Below
///   `AppBreakpoints.registerTable` of box it is one card per requirement.
/// - **Training records** is a register on the same terms: the band's
///   `Answers` label and its cells share a right edge, and a row that opens the
///   record is at least `AppTouchTarget.min` tall.
/// - **The Training record** is a summary card first and sections below it, one
///   column at every window because the page names a 720 frame.
/// - **Training to confirm** is a decision surface: the facts above a hairline,
///   the answer label and its two controls below it, and the controls under the
///   label at a narrow box.
/// - **The printed form** (ADR-0044) is checked, not restyled: it still renders
///   its sheet at a 700 and a 1280 window and at twice the text.
///
/// The app is pumped through the real router with the wire faked, as the
/// Module's own tests do; nothing here reaches into a Bloc. The app's real fonts
/// are loaded first, because a register measures its columns from its own
/// content — in `flutter_test`'s placeholder font every glyph is a square, and a
/// width measured there is a property of the placeholder rather than of the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/job_roles_screen.dart';
import 'package:lean_platform/people/skill_coverage_screen.dart';
import 'package:lean_platform/people/skills_screen.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_form_screen.dart';
import 'package:lean_platform/people/training_screen.dart';
import 'package:lean_platform/people/training_to_confirm_screen.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

/// Two Sites, so the coverage Screen's Site switch is drawn; one Org Unit; two
/// skills and two job roles, one of each deactivated; three coverage
/// requirements, one of them with nobody qualified; two Training records, one a
/// draft and one sent with an answered Trainee; and one record waiting on the
/// reader to answer.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'HN', 'Ha Noi')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      skills: [
        skillJson('30', 'WELD', 'Welding'),
        skillJson('31', 'FORK', 'Forklift operation', skillCategory: 'safety', isActive: false),
      ],
      jobRoles: [
        jobRoleJson('20', 'WELD', 'Welder'),
        jobRoleJson('21', 'MILL', 'Miller', isActive: false),
      ],
      skillCoverage: {
        '1': [
          skillCoverageEntryJson('10', 'Assembly', '30', 'WELD', 'Welding'),
          skillCoverageEntryJson(
            '10',
            'Assembly',
            '31',
            'FORK',
            'Forklift operation',
            qualifiedHeadcount: 1,
            shortfall: 1,
          ),
          skillCoverageEntryJson(
            '11',
            'Line 1',
            '30',
            'WELD',
            'Welding',
            minimumQualifiedHeadcount: 3,
            shortfall: 3,
          ),
        ],
      },
      trainingRecords: [
        trainingRecordJson(
          '1',
          number: 'TR-HCM-2026-00001',
          title: 'Lockout and tagout refresher',
          trainees: [traineeJson('901', '7', 'E-7', 'Alice Nguyen')],
        ),
        trainingRecordJson(
          '2',
          number: 'TR-HCM-2026-00002',
          title: 'Forklift recertification',
          status: 'sent',
          trainees: [
            traineeJson('902', '7', 'E-7', 'Alice Nguyen', answer: 'confirmed', signatureAppliedAs: 'stored'),
          ],
        ),
      ],
      trainingToConfirm: [trainingToConfirmJson('902', id: '2', number: 'TR-HCM-2026-00002')],
    );

Future<void> _pumpAt(
  WidgetTester tester, {
  required String location,
  required double width,
  double textScale = 1,
  double height = 2000,
  bool settle = true,
  FakeWire? wire,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: (wire ?? _wire()).client,
    initialLocation: location,
    settle: settle,
  );
}

/// One catalogue Screen, as a test sees it.
typedef _Catalogue = ({
  String name,
  String location,
  String id,
  Key Function(String id) rowKey,
  Key Function(String id) lineKey,
  Key Function(String id) controlKey,
  Key Function(String id) lastControlKey,
});

final List<_Catalogue> _catalogues = <_Catalogue>[
  (
    name: 'Skills',
    location: Routes.skills,
    id: '30',
    rowKey: SkillsScreen.rowKey,
    lineKey: SkillsScreen.nameKey,
    controlKey: SkillsScreen.whoHoldsKey,
    lastControlKey: SkillsScreen.correctKey,
  ),
  (
    name: 'Job roles',
    location: Routes.jobRoles,
    id: '20',
    rowKey: JobRolesScreen.rowKey,
    lineKey: JobRolesScreen.nameKey,
    controlKey: JobRolesScreen.correctKey,
    lastControlKey: JobRolesScreen.correctKey,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final catalogue in _catalogues) {
    final name = catalogue.name;

    testWidgets("$name: at 1280 the line is at the card's left inset and the control at its right",
        (tester) async {
      await _pumpAt(tester, location: catalogue.location, width: 1280);

      final row = tester.getRect(find.byKey(catalogue.rowKey(catalogue.id)));
      final line = tester.getRect(find.byKey(catalogue.lineKey(catalogue.id)));
      final control = tester.getRect(find.byKey(catalogue.controlKey(catalogue.id)));
      final lastControl = tester.getRect(find.byKey(catalogue.lastControlKey(catalogue.id)));

      // One left edge and one right edge, both the row's own inset — the
      // `Wrap` this row used to be had neither.
      expect(line.left - row.left, closeTo(Spacing.lg, 1.0),
          reason: '$name: the line is not at the row inset');
      expect(row.right - lastControl.right, closeTo(Spacing.lg, 1.0),
          reason: "$name: the controls are not against the row's right edge");
      // On one line: the control's band overlaps the line's.
      expect(control.top, lessThan(line.bottom),
          reason: '$name: the control dropped under the line at 1280');
      // And every control in the row clears the Platform's tap floor.
      expect(lastControl.height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: "$name: a control is under the 44px tap floor");
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: at 700 the control drops under the line rather than squeezing it out',
        (tester) async {
      await _pumpAt(tester, location: catalogue.location, width: 700);

      final row = tester.getRect(find.byKey(catalogue.rowKey(catalogue.id)));
      final line = tester.getRect(find.byKey(catalogue.lineKey(catalogue.id)));
      final control = tester.getRect(find.byKey(catalogue.controlKey(catalogue.id)));

      expect(control.top, greaterThanOrEqualTo(line.bottom),
          reason: '$name: the control did not drop under the line at 700');
      expect(control.right, lessThanOrEqualTo(row.right - Spacing.lg + 1),
          reason: '$name: the dropped control is not inside the row');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: at 1280 with twice the text the control drops under the line',
        (tester) async {
      await _pumpAt(tester, location: catalogue.location, width: 1280, textScale: 2);

      final line = tester.getRect(find.byKey(catalogue.lineKey(catalogue.id)));
      final control = tester.getRect(find.byKey(catalogue.controlKey(catalogue.id)));

      // 560 doubled is 1120, past the 868 box a 1280 window hands the page, so
      // the two cannot share a line at twice the text (§10).
      expect(control.top, greaterThanOrEqualTo(line.bottom),
          reason: '$name: twice the text still put the control beside the line');
      expect(tester.takeException(), isNull);
    });
  }

  group('Skill coverage', () {
    const String route = Routes.skillCoverage;
    const String firstOrgUnit = '10';
    const String firstSkill = '30';

    testWidgets('at 1280 it is a register: the band is 32, and labels and cells share an edge',
        (tester) async {
      await _pumpAt(tester, location: route, width: 1280);

      expect(find.byType(AppTableHeader), findsOneWidget);
      expect(tester.getSize(find.byType(AppTableHeader)).height, AppTableHeader.height);

      // The band's first label and the first cell of every row start at the same
      // x, because both are laid out from the one stated column list.
      final label = tester.getRect(
        find.byKey(AppTableHeader.labelKey(SkillCoverageScreen.columns.first.label)),
      );
      final cell = tester.getRect(
        find.descendant(
          of: find.byKey(SkillCoverageScreen.rowKey(firstOrgUnit, firstSkill)),
          matching: find.byKey(AppTableRow.cellKey(0)),
        ),
      );
      expect(cell.left, closeTo(label.left, 1.0), reason: 'the first cell is not under its label');

      // The two count columns end at the same x as their own labels.
      for (final index in const [2, 3]) {
        final columnLabel = tester.getRect(
          find.byKey(AppTableHeader.labelKey(SkillCoverageScreen.columns[index].label)),
        );
        final countCell = tester.getRect(
          find.descendant(
            of: find.byKey(SkillCoverageScreen.rowKey(firstOrgUnit, firstSkill)),
            matching: find.byKey(AppTableRow.cellKey(index)),
          ),
        );
        expect(
          countCell.right - columnLabel.right,
          closeTo(0, 1.0),
          reason: 'column $index: the cell does not end where its label does',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 1280 the shortfall carries a tone and the legend names the tones painted',
        (tester) async {
      await _pumpAt(tester, location: route, width: 1280);

      final legend = find.byKey(SkillCoverageScreen.legendKey);
      expect(legend, findsOneWidget);
      // This Site's fixture holds one requirement with nobody qualified and one
      // that is partly met, so the legend carries exactly those two words.
      expect(find.descendant(of: legend, matching: find.text('Nobody qualified')), findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('Partly qualified')), findsOneWidget);
      // And the chip keeps the record's own words.
      expect(find.byKey(SkillCoverageScreen.shortfallKey(firstOrgUnit, firstSkill)), findsOneWidget);
      expect(find.text('Short 2'), findsOneWidget);
    });

    testWidgets('at 700 and at twice the text it is one card per requirement, and the chip is inside it',
        (tester) async {
      for (final (width, scale) in [(700.0, 1.0), (1280.0, 2.0)]) {
        await _pumpAt(tester, location: route, width: width, textScale: scale);

        expect(find.byType(AppTableHeader), findsNothing, reason: 'a band was drawn at $width x$scale');
        final card = tester.getRect(find.byKey(SkillCoverageScreen.cardKey(firstOrgUnit, firstSkill)));
        final chip = tester.getRect(find.byKey(SkillCoverageScreen.shortfallKey(firstOrgUnit, firstSkill)));
        expect(chip.right, lessThanOrEqualTo(card.right + 1),
            reason: 'the chip is outside its card at $width x$scale');
        expect(find.text('Assembly · Welding'), findsWidgets);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the loading state is bounded, so the page does not throw while a Site is read',
        (tester) async {
      // The defect S6 filed: a `SkeletonList` is itself a scroll view, and one
      // handed to this page's `ListView` with no height throws "Vertical
      // viewport was given unbounded height". The wire's gate holds the read
      // open, so the loading frame is a frame this test can actually stand in —
      // it used to throw there, before the real rows arrived.
      final gate = Completer<void>();
      final wire = _wire()..skillCoverageGate = gate;
      await _pumpAt(tester, location: route, width: 1280, wire: wire, settle: false);
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'the loading frame threw');
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(tester.getSize(find.byType(SkeletonList)).height.isFinite, isTrue,
          reason: 'the skeleton was handed an unbounded height');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppTableHeader), findsOneWidget);
    });
  });

  group('Training records', () {
    const String route = Routes.training;

    testWidgets('at 1280 it is a register: a row is 44 tall and its counts end under their label',
        (tester) async {
      await _pumpAt(tester, location: route, width: 1280);

      expect(find.byType(AppTableHeader), findsOneWidget);
      final row = find.byKey(TrainingScreen.rowKey('1'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'a row that opens a record is under the tap floor');

      // `Answers` is the register's one end-aligned count: its cell ends where
      // its label does.
      final answers = TrainingScreen.columns.indexWhere((column) => column.label == 'Answers');
      final label = tester.getRect(find.byKey(AppTableHeader.labelKey('Answers')));
      final cell = tester.getRect(
        find.descendant(of: row, matching: find.byKey(AppTableRow.cellKey(answers))),
      );
      expect(cell.right - label.right, closeTo(0, 1.0));
      expect(find.text('0 of 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 700 and at twice the text it is one card per record, carrying the same facts',
        (tester) async {
      for (final (width, scale) in [(700.0, 1.0), (1280.0, 2.0)]) {
        await _pumpAt(tester, location: route, width: width, textScale: scale);

        expect(find.byType(AppTableHeader), findsNothing, reason: 'a band was drawn at $width x$scale');
        expect(find.byKey(TrainingScreen.rowKey('1')), findsOneWidget);
        expect(find.text('TR-HCM-2026-00001 · Lockout and tagout refresher'), findsOneWidget);
        // The printed form is reachable in both shapes.
        expect(find.byKey(TrainingScreen.formKey('1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('The Training record', () {
    const String route = '/training/1';

    testWidgets('at 1280 the summary card comes first and the sections below it, one column',
        (tester) async {
      await _pumpAt(tester, location: route, width: 1280);

      final summary = tester.getRect(find.byKey(TrainingDetailScreen.summaryKey));
      final sections = find.byType(AppDetailSection);
      expect(sections, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final section = tester.getRect(sections.at(i));
        expect(section.top, greaterThan(summary.bottom), reason: 'section $i is not below the summary');
        // One column: every section is as wide as the page's own content box.
        expect(section.width, closeTo(summary.width, 1.0),
            reason: 'section $i is not the page width');
      }
      // The facts' values all share one left edge down the page.
      final trainedOn = tester.getRect(find.byKey(TrainingDetailScreen.trainedOnKey));
      final duration = tester.getRect(find.byKey(TrainingDetailScreen.durationKey));
      expect(duration.left, closeTo(trainedOn.left, 1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 700 the summary card holds and the sections still stack', (tester) async {
      await _pumpAt(tester, location: route, width: 700);

      final summary = tester.getRect(find.byKey(TrainingDetailScreen.summaryKey));
      final sections = find.byType(AppDetailSection);
      expect(sections, findsNWidgets(2));
      expect(tester.getRect(sections.at(0)).top, greaterThan(summary.bottom));
      expect(tester.getRect(sections.at(1)).top, greaterThan(tester.getRect(sections.at(0)).bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 1280 with twice the text it still holds', (tester) async {
      await _pumpAt(tester, location: route, width: 1280, textScale: 2);

      expect(find.byKey(TrainingDetailScreen.numberKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('901')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Training to confirm', () {
    const String route = '/training/to-confirm';
    const String trainee = '902';

    testWidgets('at 1280 the decision is its own band under the facts', (tester) async {
      await _pumpAt(tester, location: route, width: 1280);

      final decision = tester.getRect(find.byKey(TrainingToConfirmScreen.decisionKey(trainee)));
      final confirm = tester.getRect(find.byKey(TrainingToConfirmScreen.confirmKey(trainee)));
      final decline = tester.getRect(find.byKey(TrainingToConfirmScreen.declineKey(trainee)));

      // The two controls share one line, inside the decision band.
      expect(confirm.top, closeTo(decline.top, 1.0));
      expect(confirm.top, greaterThanOrEqualTo(decision.top));
      expect(confirm.bottom, lessThanOrEqualTo(decision.bottom + 1));
      expect(confirm.height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 700 and at twice the text the controls drop under the answer label',
        (tester) async {
      for (final (width, scale) in [(700.0, 1.0), (1280.0, 2.0)]) {
        await _pumpAt(tester, location: route, width: width, textScale: scale);

        final label = tester.getRect(find.text('Your answer'));
        final confirm = tester.getRect(find.byKey(TrainingToConfirmScreen.confirmKey(trainee)));
        expect(confirm.top, greaterThanOrEqualTo(label.bottom),
            reason: 'the controls did not drop under the label at $width x$scale');
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('The printed form', () {
    const String route = '/training/1/form';

    testWidgets('renders its own sheet at 700 and at 1280, and holds at twice the text',
        (tester) async {
      for (final (width, scale) in [(700.0, 1.0), (1280.0, 1.0), (1280.0, 2.0)]) {
        await _pumpAt(tester, location: route, width: width, textScale: scale, height: 2400);

        expect(find.byType(TrainingFormScreen), findsOneWidget);
        // The sheet's own number and its bilingual heading are what a reader
        // prints: both are still drawn, at every one of the three.
        expect(find.byKey(TrainingFormScreen.numberKey), findsOneWidget);
        expect(find.text('TR-HCM-2026-00001'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'the printed sheet threw at $width x$scale');
      }
    });
  });
}
