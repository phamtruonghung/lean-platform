/// The injury classification and who may read it (issue #224, ADR-0037), plus
/// the two catalogues it draws on — driven through the router against a faked
/// wire, the client's one seam (AGENTS.md §5): `pumpApp` with a `FakeWire`,
/// act through `WidgetTester`, assert on what renders and on the requests the
/// Screen actually sent. Never a Bloc's state.
///
/// **What the detail's three renderings prove.** The API withholds the three
/// restricted fields by leaving their keys out of the JSON, so a fixture
/// models an unauthorised reader with `injuryDetailsRestricted: true`, which
/// removes those keys rather than nulling them. The Screen then has to tell
/// three cases apart:
///
///   - the **no-injury rung** — no injury section at all, for anybody;
///   - **restricted** — the section, with one line saying so;
///   - **visible but unclassified** — the section, saying nobody has
///     classified it yet.
///
/// The last two are the pair the binding design comment on #223 insists stay
/// tellable apart: hiding the section from an unauthorised reader would
/// protect nothing (the severity rung is public, and the ladder's own CHECK
/// forbids injury details below the no-injury rung) and would cost that reader
/// the difference between "not classified yet" and "not mine to see".
///
/// **What this file deliberately does not claim.** That `description` or
/// `immediateAction` are protected. ADR-0037 names them as outside the
/// restriction, so there is no assertion here that they are hidden and no UI
/// copy implying it — a test asserting a protection that does not exist is
/// worse than no test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/safety/body_part_form_dialog.dart';
import 'package:lean_platform/safety/body_parts_screen.dart';
import 'package:lean_platform/safety/incident_classify_dialog.dart';
import 'package:lean_platform/safety/incident_detail_screen.dart';
import 'package:lean_platform/safety/injury_type_form_dialog.dart';
import 'package:lean_platform/safety/injury_types_screen.dart';
import 'package:lean_platform/widgets/empty_state.dart';

import 'harness.dart';

const List<Map<String, dynamic>> _injuryTypes = [
  {
    'id': '61',
    'code': 'FRA',
    'name': 'Fracture',
    'isActive': true,
  },
  {
    'id': '62',
    'code': 'BUR',
    'name': 'Burn',
    'isActive': true,
  },
  {
    'id': '63',
    'code': 'OLD',
    'name': 'Retired classification',
    'isActive': false,
  },
];

const List<Map<String, dynamic>> _bodyParts = [
  {
    'id': '71',
    'code': 'HAND',
    'name': 'Hand',
    'region': 'upper_limb',
    'isActive': true,
  },
  {
    'id': '72',
    'code': 'KNEE',
    'name': 'Knee',
    'region': 'lower_limb',
    'isActive': true,
  },
];

/// The wire every incident test starts from. [safety] is what the caller's own
/// Grant carries (`safetyAuthority`, ADR-0039); when it is false the caller
/// still holds a write Grant reaching Line 1, which is what recording and the
/// ordinary status move need and what makes "offered / not offered" turn on
/// the authority rather than on visibility.
///
/// Three incidents, one per rendering the detail owes #223:
///
///   - `801` — the no-injury rung. No injury section for anybody.
///   - `802` — above the rung, **classified**, and readable.
///   - `803` — above the rung, and the keys are **absent**, the way the API
///     answers a caller ADR-0037 withholds them from.
FakeWire _wire({
  bool safety = false,
  String role = Roles.supervisor,
  Map<String, dynamic>? orgUnitScope,
}) =>
    FakeWire(
      role: role,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('11', 'Line 1')],
      },
      orgUnitScope: orgUnitScope ??
          {
            'everywhere': false,
            'grants': [scopeGrantJson('11', canWrite: true, safetyAuthority: safety)],
          },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      injuryTypes: _injuryTypes,
      bodyParts: _bodyParts,
      safetyIncidents: {
        '1': [
          safetyIncidentJson(
            '801',
            'SI-HCM-2026-00001',
            incidentType: 'near_miss',
            severityLevel: 'near_miss',
            description: 'A pallet fell where nobody was standing.',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
          ),
          safetyIncidentJson(
            '802',
            'SI-HCM-2026-00002',
            severityLevel: 'medical_treatment',
            description: 'Caught between the guard and the frame.',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            employeeId: '7',
            employeeName: 'Alice Nguyen',
            injuryTypeId: '61',
            injuryTypeCode: 'FRA',
            injuryTypeName: 'Fracture',
            bodyPartId: '71',
            bodyPartCode: 'HAND',
            bodyPartName: 'Hand',
            bodyPartRegion: 'upper_limb',
          ),
          safetyIncidentJson(
            '803',
            'SI-HCM-2026-00003',
            severityLevel: 'lost_time',
            description: 'Slipped on the ramp.',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            injuryDetailsRestricted: true,
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/incidents/802',
}) async {
  // Pinned taller than the default 800x600: the detail's lower sections are
  // simply not in the tree at 600px, and `find.byKey` fails on a row a lazy
  // `ListView` has not built yet.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

Future<void> _go(WidgetTester tester, String address) async {
  final context = tester.element(find.byKey(SafetyIncidentDetailScreen.backKey));
  GoRouter.of(context).go(address);
  await tester.pumpAndSettle();
}

/// Every word rendered under [key], the key's own widget included — some of
/// the keys this file asserts on sit on a `Text` itself rather than on a box
/// around one, and `find.descendant` alone would answer the empty string for
/// those.
String _textIn(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Text) return widget.data ?? '';
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .map((text) => text.data ?? '')
      .join(' · ');
}

void main() {
  // -------------------------------------------------------------------------
  // The detail's three renderings of the injury section
  // -------------------------------------------------------------------------

  testWidgets('the no-injury rung carries no injury section at all, for anybody', (tester) async {
    // Asserted with the authority held, which is the stronger claim: it is the
    // rung that decides, not the caller.
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/801');

    expect(find.byKey(SafetyIncidentDetailScreen.injuryKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryRestrictedKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryUnclassifiedKey), findsNothing);
    // And no classify control either: there is nothing to classify, and the
    // ladder's own CHECK would refuse every answer the form could give.
    expect(find.byKey(SafetyIncidentDetailScreen.classifyKey), findsNothing);

    // The rest of the record is exactly as readable as it ever was — the
    // restriction narrows three fields and nothing else.
    expect(find.text('A pallet fell where nobody was standing.'), findsOneWidget);
  });

  testWidgets('a reader without Safety authority sees the section as a stated restriction', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/803');

    expect(find.byKey(SafetyIncidentDetailScreen.injuryKey), findsOneWidget);
    expect(
      find.byKey(SafetyIncidentDetailScreen.injuryRestrictedKey),
      findsOneWidget,
      reason: 'the section renders, saying it is restricted — never as silence',
    );
    expect(
      _textIn(tester, SafetyIncidentDetailScreen.injuryRestrictedKey),
      contains('Restricted'),
    );
    expect(
      _textIn(tester, SafetyIncidentDetailScreen.injuryRestrictedKey),
      contains('Safety authority'),
    );

    // Nothing about who or what: no value, and no name, reaches the screen.
    expect(find.byKey(SafetyIncidentDetailScreen.injuredEmployeeKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryTypeKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.bodyPartKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.classifyKey), findsNothing);

    // The public half of the record still reads: the rung, the recordable
    // flag, and the free text ADR-0037 explicitly does not protect.
    expect(find.text('Lost time'), findsWidgets);
    expect(find.text('Recordable'), findsOneWidget);
    expect(find.text('Slipped on the ramp.'), findsOneWidget);
  });

  testWidgets('a holder of Safety authority sees the injured Employee, the type and the part', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.injuryKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryRestrictedKey), findsNothing);
    expect(
      _textIn(tester, SafetyIncidentDetailScreen.injuredEmployeeKey),
      contains('Alice Nguyen'),
    );
    expect(_textIn(tester, SafetyIncidentDetailScreen.injuryTypeKey), contains('Fracture'));
    expect(_textIn(tester, SafetyIncidentDetailScreen.bodyPartKey), contains('Hand'));
    expect(_textIn(tester, SafetyIncidentDetailScreen.bodyPartKey), contains('Upper limb'));
  });

  testWidgets('"not classified yet" and "not mine to see" are two different screens', (tester) async {
    // The same rung, the same Screen, and the only difference is whether the
    // keys arrived. This is the pair hiding the section would have collapsed.
    final wire = _wire(safety: true);
    wire.safetyIncidents = {
      '1': [
        safetyIncidentJson(
          '804',
          'SI-HCM-2026-00004',
          severityLevel: 'medical_treatment',
          orgUnitId: '11',
          orgUnitName: 'Line 1',
        ),
      ],
    };
    await _pump(tester, wire, location: '/safety/incidents/804');

    expect(find.byKey(SafetyIncidentDetailScreen.injuryKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryUnclassifiedKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.injuryRestrictedKey), findsNothing);
    expect(
      _textIn(tester, SafetyIncidentDetailScreen.injuryUnclassifiedKey),
      contains('Not classified yet'),
    );
  });

  testWidgets('an administrator without Safety authority in the chain is told the same thing as anyone else', (tester) async {
    // The server decides this, and the client simply renders what arrived —
    // the point of the assertion is that no role check anywhere on the client
    // second-guesses an answer whose keys are absent into showing values it
    // does not have.
    final wire = _wire(
      role: Roles.admin,
      orgUnitScope: {'everywhere': true, 'grants': const <dynamic>[]},
    );
    await _pump(tester, wire, location: '/safety/incidents/803');

    expect(find.byKey(SafetyIncidentDetailScreen.injuryRestrictedKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.injuredEmployeeKey), findsNothing);
  });

  // -------------------------------------------------------------------------
  // The classify dialog
  // -------------------------------------------------------------------------

  testWidgets('the classify dialog is not offered without Safety authority, and its address refuses', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.classifyKey), findsNothing);

    // And the address itself, typed by hand, refuses rather than rendering a
    // form whose only answer would be a 403.
    await _go(tester, '/safety/incidents/802/classify');
    expect(find.byKey(SafetyIncidentClassifyDialog.refusedKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentClassifyDialog.submitKey), findsNothing);
    expect(wire.safetyIncidentClassifyPosts, isEmpty);
  });

  testWidgets('a holder of Safety authority classifies an injury, and only the fields it names are sent', (tester) async {
    final wire = _wire(safety: true);
    wire.safetyIncidents = {
      '1': [
        safetyIncidentJson(
          '804',
          'SI-HCM-2026-00004',
          severityLevel: 'medical_treatment',
          orgUnitId: '11',
          orgUnitName: 'Line 1',
        ),
      ],
    };
    await _pump(tester, wire, location: '/safety/incidents/804');

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.classifyKey));
    await tester.pumpAndSettle();

    // The two catalogues are read **without** the retired rows: a deactivated
    // entry is not offered as a choice.
    expect(wire.injuryTypeReads.last.containsKey('includeInactive'), isFalse);
    expect(wire.bodyPartReads.last.containsKey('includeInactive'), isFalse);

    final requestsBefore = wire.requests.length;

    await tester.enterText(
      find.byKey(SafetyIncidentClassifyDialog.injuryTypeFieldKey()),
      'Fract',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // Typing narrows the list the dialog already read and issues no request at
    // all — #190's rule, and why no endpoint here gains a `search` parameter.
    expect(wire.requests.length, requestsBefore);
    expect(find.byKey(SafetyIncidentClassifyDialog.injuryTypeSuggestionKey('61')), findsOneWidget);
    expect(find.byKey(SafetyIncidentClassifyDialog.injuryTypeSuggestionKey('62')), findsNothing);
    // The deactivated row was never fetched, so it cannot be suggested.
    expect(find.byKey(SafetyIncidentClassifyDialog.injuryTypeSuggestionKey('63')), findsNothing);

    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.injuryTypeSuggestionKey('61')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.safetyIncidentClassifyPosts, hasLength(1));
    final (id, body) = wire.safetyIncidentClassifyPosts.single;
    expect(id, '804');
    expect(body['injuryTypeId'], '61');
    // The two fields the caller said nothing about are absent from the body —
    // absent leaves a field alone, which is what lets a classification be
    // completed at three different moments.
    expect(body.containsKey('employeeId'), isFalse);
    expect(body.containsKey('bodyPartId'), isFalse);

    // And the answer renders: the record came back classified.
    expect(_textIn(tester, SafetyIncidentDetailScreen.injuryTypeKey), contains('Fracture'));
  });

  testWidgets('clearing a field sends an explicit null, which is not the same as saying nothing', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire);

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.classifyKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.clearBodyPartKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.submitKey));
    await tester.pumpAndSettle();

    final (_, body) = wire.safetyIncidentClassifyPosts.single;
    expect(body.containsKey('bodyPartId'), isTrue);
    expect(body['bodyPartId'], isNull);
    expect(body.containsKey('injuryTypeId'), isFalse);
  });

  testWidgets('the classify dialog sends nothing while it names nothing', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire);

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.classifyKey));
    await tester.pumpAndSettle();

    // The record already carries all three, but this form has asked for no
    // change — the API refuses an empty classification with a 400, so the gate
    // closes rather than sending one.
    final submit = tester.widget<FilledButton>(
      find.byKey(SafetyIncidentClassifyDialog.submitKey),
    );
    expect(submit.onPressed, isNull);
    expect(wire.safetyIncidentClassifyPosts, isEmpty);
  });

  testWidgets("a refusal from the API is reported on the dialog, which stays open", (tester) async {
    final wire = _wire(safety: true)
      ..recordSafetyIncidentActStatus = 403
      ..recordSafetyIncidentActMessage =
          "that decision needs Safety authority at this Safety incident's Org Unit";
    await _pump(tester, wire);

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.classifyKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.clearEmployeeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SafetyIncidentClassifyDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(SafetyIncidentClassifyDialog.failureKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentClassifyDialog.submitKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The Injury type catalogue
  // -------------------------------------------------------------------------

  testWidgets('the Injury type catalogue lists every row, retired ones included, and marks them', (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/injury-types');

    expect(find.byKey(InjuryTypesScreen.rowKey('61')), findsOneWidget);
    expect(find.byKey(InjuryTypesScreen.rowKey('63')), findsOneWidget);
    expect(find.byKey(InjuryTypesScreen.inactiveChipKey('63')), findsOneWidget);
    expect(find.byKey(InjuryTypesScreen.inactiveChipKey('61')), findsNothing);

    // The Screen asks for the retired rows by name, which is what makes one
    // reachable to reactivate.
    expect(wire.injuryTypeReads.last['includeInactive'], 'true');
  });

  testWidgets('an administrator adds an Injury type, and corrects one', (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/injury-types');

    await tester.tap(find.byKey(InjuryTypesScreen.addKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(InjuryTypeFormDialog.codeKey), 'AMP');
    await tester.enterText(find.byKey(InjuryTypeFormDialog.nameKey), 'Amputation');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InjuryTypeFormDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.injuryTypePosts.single, {'code': 'AMP', 'name': 'Amputation'});

    await tester.tap(find.byKey(InjuryTypesScreen.correctKey('61')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(InjuryTypeFormDialog.nameKey), 'Fracture or break');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InjuryTypeFormDialog.submitKey));
    await tester.pumpAndSettle();

    final (id, changes) = wire.injuryTypePatches.single;
    expect(id, '61');
    // Only what changed, and never the code — it is what an incident's own
    // report quotes, so a correction that rewrote it would rewrite history.
    expect(changes, {'name': 'Fracture or break'});
  });

  testWidgets('an administrator retires an Injury type through the same correction', (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/injury-types');

    await tester.tap(find.byKey(InjuryTypesScreen.correctKey('62')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InjuryTypeFormDialog.activeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InjuryTypeFormDialog.submitKey));
    await tester.pumpAndSettle();

    final (id, changes) = wire.injuryTypePatches.single;
    expect(id, '62');
    expect(changes, {'isActive': false});
  });

  testWidgets('a non-administrator reads the Injury type catalogue and is offered no write', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/injury-types');

    expect(find.byKey(InjuryTypesScreen.rowKey('61')), findsOneWidget);
    expect(find.byKey(InjuryTypesScreen.addKey), findsNothing);
    expect(find.byKey(InjuryTypesScreen.correctKey('61')), findsNothing);
  });

  test("the two catalogue Destinations are an administrator's alone", () {
    // The binding design comment on #223: "the last two filter away for a
    // non-administrator, so a line supervisor sees a two-entry Safety group
    // and an administrator sees four". The Screens themselves stay reachable
    // by address for everyone, because the reads behind them are open — only
    // the sidebar entry is filtered.
    final forSupervisor =
        destinationsFor(role: Roles.supervisor).map((d) => d.path).toSet();
    expect(forSupervisor, contains('/safety/incidents'));
    expect(forSupervisor, isNot(contains('/safety/injury-types')));
    expect(forSupervisor, isNot(contains('/safety/body-parts')));

    final forAdmin = destinationsFor(role: Roles.admin).map((d) => d.path).toSet();
    expect(forAdmin, containsAll(<String>['/safety/injury-types', '/safety/body-parts']));
  });

  testWidgets('a failed catalogue read says so and offers a retry', (tester) async {
    final wire = _wire(role: Roles.admin)..injuryTypesStatus = 500;
    await _pump(tester, wire, location: '/safety/injury-types');

    expect(find.byKey(InjuryTypesScreen.failedKey), findsOneWidget);
    expect(find.byKey(InjuryTypesScreen.retryKey), findsOneWidget);
  });

  testWidgets('an empty Injury type catalogue says nothing has been defined', (tester) async {
    final wire = _wire(role: Roles.admin)..injuryTypes = const [];
    await _pump(tester, wire, location: '/safety/injury-types');

    expect(find.byKey(InjuryTypesScreen.emptyKey), findsOneWidget);
    expect(find.byType(PlatformEmptyState), findsWidgets);
  });

  // -------------------------------------------------------------------------
  // The Body part catalogue
  // -------------------------------------------------------------------------

  testWidgets('the Body part catalogue shows each part with the region it is filed under', (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/body-parts');

    expect(_textIn(tester, BodyPartsScreen.rowKey('71')), contains('Hand'));
    expect(_textIn(tester, BodyPartsScreen.rowKey('71')), contains('Upper limb'));
    expect(_textIn(tester, BodyPartsScreen.rowKey('72')), contains('Lower limb'));
  });

  testWidgets('an administrator adds a Body part, choosing its region rather than typing it', (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/body-parts');

    await tester.tap(find.byKey(BodyPartsScreen.addKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(BodyPartFormDialog.codeKey), 'EYE');
    await tester.enterText(find.byKey(BodyPartFormDialog.nameKey), 'Eye');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(BodyPartFormDialog.regionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Head').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(BodyPartFormDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.bodyPartPosts.single, {'code': 'EYE', 'name': 'Eye', 'region': 'head'});
  });

  testWidgets("a Body part's region is correctable, and only what changed is sent", (tester) async {
    final wire = _wire(role: Roles.admin);
    await _pump(tester, wire, location: '/safety/body-parts');

    await tester.tap(find.byKey(BodyPartsScreen.correctKey('72')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BodyPartFormDialog.regionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiple').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BodyPartFormDialog.submitKey));
    await tester.pumpAndSettle();

    final (id, changes) = wire.bodyPartPatches.single;
    expect(id, '72');
    expect(changes, {'region': 'multiple'});
  });

  testWidgets('a non-administrator reads the Body part catalogue and is offered no write', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/body-parts');

    expect(find.byKey(BodyPartsScreen.rowKey('71')), findsOneWidget);
    expect(find.byKey(BodyPartsScreen.addKey), findsNothing);
    expect(find.byKey(BodyPartsScreen.correctKey('71')), findsNothing);
  });
}
