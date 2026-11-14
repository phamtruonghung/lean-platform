/// Pictures of a Quality issue, and the Site's slide show (issue #419), driven
/// through the router against a faked wire — the seam `nonconformances_test.dart`
/// and `complaints_test.dart` already use.
///
/// What each test pins is one of the card's own criteria:
///
///   - a picture added from a Non-conformance's detail Screen, and one added
///     from a complaint's, are uploaded with the caption that was typed and
///     appear as thumbnails — and survive a reload;
///   - a refused upload leaves the section as it was and says why, in the API's
///     own words;
///   - the show advances on its own after ten seconds, stops when a person
///     steps it by hand, and starts again from the play control;
///   - a chosen issue with no picture is not a slide, and the Screen says so
///     rather than showing a blank wall;
///   - a reader who may not see the Site gets the failure, not an empty wall;
///   - the order the picker writes is the order that is sent;
///   - the register row's toggle, and the labelled switch on both detail
///     Screens, render the record's own state and send the same choice;
///   - the whole Screen survives a 700-px box at twice the text.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/quality/complaint_detail_screen.dart';
import 'package:lean_platform/quality/issue_images_section.dart';
import 'package:lean_platform/quality/nonconformance_detail_screen.dart';
import 'package:lean_platform/quality/nonconformances_screen.dart';
import 'package:lean_platform/quality/quality_photo.dart';
import 'package:lean_platform/quality/slide_show_screen.dart';
import 'package:lean_platform/widgets/app_dialog.dart';

import 'harness.dart';

FakeWire _wire({List<Map<String, dynamic>>? slideShowIssues}) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [
        defectCodeJson('41', 'DIM-OOT', 'Out of tolerance', defaultSeverity: 'major'),
      ],
      customers: [customerJson('60', 'CUST-1', 'Acme Bearings')],
      nonconformances: {
        '1': [
          nonconformanceJson(
            '701',
            'NC-HCM-2026-00001',
            severity: 'major',
            quantityAffected: 20,
            orgUnitId: '11',
            orgUnitName: 'Line 1',
          ),
        ],
      },
      complaints: {
        '1': [
          customerComplaintJson('801', 'CC-2026-00001', orgUnitId: '11', orgUnitName: 'Line 1'),
        ],
      },
    )..slideShowIssues = slideShowIssues ?? const [];

Map<String, dynamic> _slide({
  required String kind,
  required String id,
  required String number,
  String status = 'open',
  String severity = 'major',
  String? partyName,
  int? position,
  List<Map<String, dynamic>> images = const [],
  String occurredAt = '2026-11-02T06:00:00.000Z',
}) =>
    {
      'kind': kind,
      'id': id,
      'number': number,
      'status': status,
      'severity': severity,
      'occurredAt': occurredAt,
      'position': position,
      'productName': 'Gearbox',
      'orgUnitName': 'Line 1',
      'partyName': partyName,
      'images': images,
    };

Map<String, dynamic> _picture(String id, {String? caption = 'Burr on the flange'}) => {
      'id': id,
      'contentType': 'image/png',
      'width': 800,
      'height': 600,
      'bytes': onePixelPng.length,
      'caption': caption,
      'createdAt': '2026-11-02T07:00:00.000Z',
    };

/// Pumps the app at [location] on a surface tall enough to build the page's
/// lower sections: a `ListView` builds only what fits, so the pictures section
/// at the bottom of a detail Screen is simply not in the tree on a 600-px
/// surface and `find.byKey` would fail on a widget the Screen does render.
Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  required String location,
  Size size = const Size(1200, 1400),
  bool settle = true,
  double textScale = 1,
  FakeQualityPhotoPicker? picker,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
    settle: settle,
    qualityPhotoPicker: picker,
  );
}

/// Lets a load settle without waiting on the show's own clock: `pumpAndSettle`
/// would keep pumping through every ten-second tick, and the timer never stops
/// on its own.
Future<void> _settleLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

String _textOf(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Text) return widget.data!;
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .last
      .data!;
}

/// The state the labelled switch renders, read off the widget itself — the same
/// thing a person sees, not the Bloc's field.
bool _switchValue(WidgetTester tester, Finder toggle) => tester
    .widget<SwitchListTile>(find.descendant(of: toggle, matching: find.byType(SwitchListTile)))
    .value;

void main() {
  testWidgets('a picture is added to a Non-conformance from its detail Screen', (tester) async {
    final wire = _wire();
    final picker = FakeQualityPhotoPicker(chosen: fakePickedPhoto());
    await _pump(tester, wire, location: '/non-conformances/701', picker: picker, size: const Size(1200, 2600));

    // Nothing yet: the section says a slide needs one.
    expect(find.byKey(IssueImagesSection.emptyKey), findsOneWidget);

    await tapIn(tester, find.byKey(IssueImagesSection.addKey));
    await tester.pumpAndSettle();
    expect(picker.asked, 1);

    // The caption is asked for once, on the picture's own dialog.
    await tester.enterText(
      find.byKey(IssueImagesSection.captionFieldKey),
      '  New burr on the flange  ',
    );
    await tester.tap(find.byKey(AppDialog.actionKey('quality-image-upload')));
    await tester.pumpAndSettle();

    expect(wire.uploadImageRequests, hasLength(1));
    final sent = wire.uploadImageRequests.single;
    expect(sent.$1, 'nonconformance');
    expect(sent.$2, '701');
    // Trimmed, and carried in the query string the API reads.
    expect(sent.$3, 'New burr on the flange');

    expect(find.byKey(IssueImagesSection.tileKey('1')), findsOneWidget);
    expect(find.text('New burr on the flange'), findsOneWidget);

    // And it is the record's, not the Screen's: a reload asks the API and gets
    // the same picture back.
    await _pump(tester, wire, location: '/non-conformances/701', picker: picker, size: const Size(1200, 2600));
    expect(find.byKey(IssueImagesSection.tileKey('1')), findsOneWidget);
  });

  testWidgets('a picture is added to a customer complaint from its detail Screen', (tester) async {
    final wire = _wire();
    final picker = FakeQualityPhotoPicker(chosen: fakePickedPhoto());
    await _pump(tester, wire, location: '/complaints/801', picker: picker, size: const Size(1200, 2600));

    await tapIn(tester, find.byKey(IssueImagesSection.addKey));
    await tester.pumpAndSettle();
    // No caption typed: the picture is still uploaded, with none.
    await tester.tap(find.byKey(AppDialog.actionKey('quality-image-upload')));
    await tester.pumpAndSettle();

    expect(wire.uploadImageRequests.single.$1, 'complaint');
    expect(wire.uploadImageRequests.single.$2, '801');
    expect(wire.uploadImageRequests.single.$3, isNull);
    expect(find.byKey(IssueImagesSection.tileKey('1')), findsOneWidget);
  });

  testWidgets('a refused upload leaves the section as it was and says why', (tester) async {
    final wire = _wire()..uploadImageStatus = 413;
    final picker = FakeQualityPhotoPicker(chosen: fakePickedPhoto());
    await _pump(tester, wire, location: '/non-conformances/701', picker: picker, size: const Size(1200, 2600));

    await tapIn(tester, find.byKey(IssueImagesSection.addKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppDialog.actionKey('quality-image-upload')));
    await tester.pumpAndSettle();

    expect(find.byKey(IssueImagesSection.emptyKey), findsOneWidget);
    expect(find.text(wire.uploadImageMessage), findsOneWidget);
  });

  testWidgets('a file that is not a picture is refused before anything is sent', (tester) async {
    final wire = _wire();
    final picker = FakeQualityPhotoPicker(
      refusal: const QualityPhotoException('That file is not a JPEG, PNG or WebP picture.'),
    );
    await _pump(tester, wire, location: '/non-conformances/701', picker: picker, size: const Size(1200, 2600));

    await tapIn(tester, find.byKey(IssueImagesSection.addKey));
    await tester.pumpAndSettle();

    expect(find.byKey(IssueImagesSection.pickerFailureKey), findsOneWidget);
    expect(wire.uploadImageRequests, isEmpty);
  });

  testWidgets('the show advances on its own, stops on a manual step, and resumes', (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
      _slide(
        kind: 'complaint',
        id: '801',
        number: 'CC-2026-00001',
        partyName: 'Acme Bearings',
        position: 2,
        images: [_picture('2', caption: 'Four parts that will not seat')],
      ),
    ]);
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('NC-HCM-2026-00001'), findsOneWidget);

    // Ten seconds is the card's own interval.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('CC-2026-00001'), findsOneWidget);
    // The caption under the picture is the picture's own.
    expect(_textOf(tester, SlideShowScreen.captionKey), 'Four parts that will not seat');

    // A person stepping by hand stops the clock.
    await tester.tap(find.byKey(SlideShowScreen.nextKey));
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget, reason: 'a stopped show does not advance');

    // And the play control starts it again.
    await tester.tap(find.byKey(SlideShowScreen.playKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('a chosen issue with no picture is not a slide, and the Screen says so',
      (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(kind: 'nonconformance', id: '701', number: 'NC-HCM-2026-00001', position: 1),
    ]);
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.byKey(SlideShowScreen.noPictureKey), findsOneWidget);
    expect(find.textContaining('1 chosen, none with a picture'), findsOneWidget);
    expect(find.byKey(SlideShowScreen.slideKey), findsNothing);
  });

  testWidgets('a Site with nothing chosen says so rather than showing a blank wall',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.byKey(SlideShowScreen.emptyKey), findsOneWidget);
    // It asked the Site's address, with the session's token.
    expect(wire.slideShowSiteRequests, ['1']);
  });

  testWidgets('a reader who may not see the Site gets the failure, not an empty wall',
      (tester) async {
    final wire = _wire()
      ..slideShowStatus = 403
      ..slideShowMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.byKey(SlideShowScreen.failedKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(find.byKey(SlideShowScreen.emptyKey), findsNothing);
  });

  testWidgets('the order the picker writes is the order that is sent', (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
      _slide(
        kind: 'complaint',
        id: '801',
        number: 'CC-2026-00001',
        position: 2,
        images: [_picture('2')],
      ),
    ]);
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    await tester.tap(find.byKey(SlideShowScreen.orderKey));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Move the complaint up: it becomes position 1.
    await tester.tap(find.byKey(SlideShowScreen.orderUpKey('complaint', '801')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(wire.slideShowOrderRequests, hasLength(1));
    expect(wire.slideShowOrderRequests.single, [
      {'kind': 'complaint', 'id': '801'},
      {'kind': 'nonconformance', 'id': '701'},
    ]);
  });

  testWidgets('at 700 of box and twice the text the show still draws, and nothing overflows',
      (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
    ]);
    await _pump(
      tester,
      wire,
      location: '/slide-show',
      size: const Size(700, 1000),
      textScale: 2,
      settle: false,
    );
    await _settleLoad(tester);

    expect(find.byKey(SlideShowScreen.slideKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1280 with twice the text the facts drop under the picture', (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
    ]);
    await _pump(
      tester,
      wire,
      location: '/slide-show',
      size: const Size(1280, 900),
      textScale: 2,
      settle: false,
    );
    await _settleLoad(tester);

    final picture = tester.getRect(find.byKey(SlideShowScreen.slideKey));
    final facts = tester.getRect(find.byKey(SlideShowScreen.factsKey));
    // A 1280 box at twice the text is the narrow layout: the facts go under the
    // picture, not over it. A breakpoint read off the width alone draws them on
    // top of it, which is why this measures instead of only finding the keys.
    expect(facts.top, greaterThanOrEqualTo(picture.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1280 the facts sit on the picture; at 700 they sit under it', (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
    ]);

    await _pump(
      tester,
      wire,
      location: '/slide-show',
      size: const Size(1280, 900),
      settle: false,
    );
    await _settleLoad(tester);

    final widePicture = tester.getRect(find.byKey(SlideShowScreen.slideKey));
    final wideFacts = tester.getRect(find.byKey(SlideShowScreen.factsKey));
    // The picture is the wall: wider than the 700 breakpoint by a long way.
    expect(widePicture.width, greaterThan(700));
    // The facts are laid over its bottom edge, not under it.
    expect((wideFacts.bottom - widePicture.bottom).abs(), lessThan(1.0));
    expect(wideFacts.height, lessThan(widePicture.height));

    // And on a box under the breakpoint they drop below the picture instead.
    await _pump(
      tester,
      wire,
      location: '/slide-show',
      size: const Size(700, 1000),
      settle: false,
    );
    await _settleLoad(tester);

    final narrowPicture = tester.getRect(find.byKey(SlideShowScreen.slideKey));
    final narrowFacts = tester.getRect(find.byKey(SlideShowScreen.factsKey));
    expect(narrowFacts.top, greaterThanOrEqualTo(narrowPicture.bottom - 1));
    expect(narrowFacts.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc leaves the show for the Quality register', (tester) async {
    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        position: 1,
        images: [_picture('1')],
      ),
    ]);
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);
    expect(find.byKey(SlideShowScreen.slideKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The register, and its own row: an address, not a popped page.
    expect(find.byKey(NonconformancesScreen.rowKey('701')), findsOneWidget);
  });

  testWidgets('a register row carries the slide-show toggle, and it sends the choice',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances');

    await tapIn(tester, find.byKey(NonconformancesScreen.slideShowKey('701')));
    await tester.pumpAndSettle();

    expect(wire.slideShowChoiceRequests, [('nonconformance', '701', true)]);
  });

  testWidgets('a Non-conformance detail Screen carries the slide-show switch, and it sends the choice',
      (tester) async {
    final wire = _wire();
    // The wire already has this record on the wall, so the state the switch
    // renders is the record's own rather than the model's default.
    wire.nonconformances['1']![0] = {...wire.nonconformances['1']![0], 'inSlideShow': true};
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(1200, 2600));

    final toggle = find.byKey(NonconformanceDetailScreen.slideShowKey);
    expect(_switchValue(tester, toggle), isTrue, reason: 'the wire carries inSlideShow: true');
    expect(find.text('On the slide show'), findsOneWidget);

    await tapIn(tester, toggle);

    // The same address and the same body the register row's toggle sends.
    expect(wire.slideShowChoiceRequests, [('nonconformance', '701', false)]);
    // And the Screen re-reads the record, so the switch follows the answer.
    expect(_switchValue(tester, toggle), isFalse);
    expect(find.text('Not on the slide show'), findsOneWidget);
  });

  testWidgets('a Customer complaint detail Screen carries the slide-show switch, and it sends the choice',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/801', size: const Size(1200, 2600));

    final toggle = find.byKey(ComplaintDetailScreen.slideShowKey);
    expect(_switchValue(tester, toggle), isFalse, reason: 'the wire carries no inSlideShow');

    await tapIn(tester, toggle);

    expect(wire.slideShowChoiceRequests, [('complaint', '801', true)]);
    expect(_switchValue(tester, toggle), isTrue);
    expect(find.text('On the slide show'), findsOneWidget);
  });

  testWidgets('a slide\'s status chip is a catalogue word under Vietnamese, not the wire',
      (tester) async {
    // The chip printed `issue.status` itself — the wire `slide-show.js` sends,
    // `open` / `contained` / `investigating` — which is the same code in every
    // language while the type chip beside it was translated. `SlideIssueWords`
    // `.statusLabel` reads each kind's own status set.
    SharedPreferences.setMockInitialValues({LocaleCubit.storageKey: 'vi'});

    final wire = _wire(slideShowIssues: [
      _slide(
        kind: 'nonconformance',
        id: '701',
        number: 'NC-HCM-2026-00001',
        status: 'contained',
        position: 1,
        images: [_picture('1')],
      ),
    ]);
    await _pump(tester, wire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.text('Đã khoanh vùng'), findsOneWidget);
    expect(find.text('contained'), findsNothing);

    // A complaint's status is the complaint's own set, read through the same
    // extension: `investigating` is not a Non-conformance's word.
    await tester.pumpWidget(const SizedBox.shrink());
    final complaintWire = _wire(slideShowIssues: [
      _slide(
        kind: 'complaint',
        id: '801',
        number: 'CC-2026-00001',
        status: 'investigating',
        position: 1,
        partyName: 'Acme Bearings',
        images: [_picture('2')],
      ),
    ]);
    await _pump(tester, complaintWire, location: '/slide-show', settle: false);
    await _settleLoad(tester);

    expect(find.text('Đang điều tra'), findsOneWidget);
    expect(find.text('investigating'), findsNothing);
    expect(find.text('Contained'), findsNothing);
  });
}
