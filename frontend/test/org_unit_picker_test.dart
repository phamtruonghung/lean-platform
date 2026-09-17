/// Granting Org Units in an Approval (issue #42), with the wire faked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/admission_dialog.dart';
import 'package:lean_platform/people/org_unit.dart';
import 'package:lean_platform/people/org_unit_picker.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'approval_queue_test.dart' show openApprovals;
import 'harness.dart' show FakeWire, orgUnitJson, pendingJson, siteJson, tapIn;
import 'admission_test.dart' show chooseRole;

final DateTime _twoDaysAgo = DateTime.now().subtract(const Duration(days: 2, hours: 1));

/// One Site, an Area with two Lines beneath it, and one Account waiting.
FakeWire _plant() => FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly', unitType: 'area')],
        '10': [
          orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line'),
          orgUnitJson('12', 'Line 2', parentId: '10', unitType: 'line'),
        ],
      },
    );

Future<void> openDecision(WidgetTester tester, FakeWire wire) async {
  await openApprovals(tester, wire);
  await tester.tap(find.byKey(const ValueKey('approval-queue-admit-7')));
  await tester.pumpAndSettle();
}


Future<void> grant(WidgetTester tester, String id, GrantLevel level) async {
  await tapIn(tester, find.byKey(OrgUnitPicker.addKey(id)));
  await tester.tap(find.byKey(OrgUnitPicker.levelKey(id, level)).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the tree is browsed from the top of a Site, and expanding is what asks for children',
      (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);

    // The root level, and only it, was requested when the picker opened.
    expect(wire.orgUnitRequests, [('1', null)]);
    expect(find.text('Assembly'), findsOneWidget);
    expect(find.text('Line 1'), findsNothing);

    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));

    // Children asked for by parent id, once, and only now.
    expect(wire.orgUnitRequests, [('1', null), ('1', '10')]);
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Line 2'), findsOneWidget);

    // Collapsing and reopening does not ask again.
    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    expect(find.text('Line 1'), findsNothing);
    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    expect(wire.orgUnitRequests, [('1', null), ('1', '10')]);
    expect(find.text('Line 1'), findsOneWidget);
  });

  testWidgets('a root-level response whose rows carry real parents renders as entry points',
      (tester) async {
    // What a non-administrator's root-level request answers (ADR-0008): two
    // entry points several levels down, each with a real parentId this client
    // has never seen a row for. Nothing may be discarded, and nothing may be
    // nested under the other.
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [
          orgUnitJson('50', 'Line 7', parentId: '9', unitType: 'line'),
          orgUnitJson('60', 'Cell 3', parentId: '41', unitType: 'cell'),
        ],
        '50': [orgUnitJson('51', 'Cell 9', parentId: '50', unitType: 'cell')],
      },
    );
    await openDecision(tester, wire);

    // Both rendered, neither dropped.
    expect(find.text('Line 7'), findsOneWidget);
    expect(find.text('Cell 3'), findsOneWidget);

    // Both at the top level: same indent, and neither is inside the other.
    final line7 = tester.getTopLeft(find.text('Line 7'));
    final cell3 = tester.getTopLeft(find.text('Cell 3'));
    expect(line7.dx, cell3.dx, reason: 'entry points are siblings at the top of the tree');

    // And each still browses downward by its own id.
    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('50')));
    expect(wire.orgUnitRequests, [('1', null), ('1', '50')]);
    expect(find.text('Cell 9'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Cell 9')).dx, greaterThan(line7.dx));

    // The granted breadcrumb says the Site and nothing invented: this client
    // was never told what sits above an entry point.
    await grant(tester, '60', GrantLevel.view);
    expect(find.text('Ho Chi Minh'), findsWidgets);
  });

  testWidgets('an Org Unit is granted by a deliberate act that forces a level, '
      'shows as granted, cannot be added twice, and can be removed', (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);

    // Nothing granted yet.
    expect(find.byKey(OrgUnitPicker.emptyGrantedKey), findsOneWidget);
    expect(find.byKey(OrgUnitPicker.grantedBadgeKey('10')), findsNothing);

    // Opening the add control adds nothing on its own — there is no item that
    // adds without a level.
    await tapIn(tester, find.byKey(OrgUnitPicker.addKey('10')));
    expect(find.byKey(OrgUnitPicker.grantedBadgeKey('10')), findsNothing);
    expect(find.byKey(OrgUnitPicker.levelKey('10', GrantLevel.view)), findsWidgets);
    expect(find.byKey(OrgUnitPicker.levelKey('10', GrantLevel.viewAndEdit)), findsWidgets);

    await tester.tap(find.byKey(OrgUnitPicker.levelKey('10', GrantLevel.viewAndEdit)).last);
    await tester.pumpAndSettle();

    // On the right, with its level and where it sits; and marked in the tree.
    expect(find.byKey(OrgUnitPicker.removeKey('10')), findsOneWidget);
    expect(find.text('View and edit'), findsWidgets);
    expect(find.byKey(OrgUnitPicker.grantedBadgeKey('10')), findsOneWidget);
    // Already granted: the add control is gone, so it cannot be added twice.
    expect(find.byKey(OrgUnitPicker.addKey('10')), findsNothing);
    expect(find.byKey(OrgUnitPicker.emptyGrantedKey), findsNothing);

    // Removed, and offerable again.
    await tapIn(tester, find.byKey(OrgUnitPicker.removeKey('10')));
    expect(find.byKey(OrgUnitPicker.removeKey('10')), findsNothing);
    expect(find.byKey(OrgUnitPicker.grantedBadgeKey('10')), findsNothing);
    expect(find.byKey(OrgUnitPicker.addKey('10')), findsOneWidget);
    expect(find.byKey(OrgUnitPicker.emptyGrantedKey), findsOneWidget);
  });

  testWidgets('the Granted list says where each Org Unit sits, so two of the same name differ',
      (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [
          orgUnitJson('10', 'Assembly', unitType: 'area'),
          orgUnitJson('20', 'Packing', unitType: 'area'),
        ],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
        '20': [orgUnitJson('21', 'Line 1', parentId: '20', unitType: 'line')],
      },
    );
    await openDecision(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    await grant(tester, '11', GrantLevel.view);
    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('20')));
    await grant(tester, '21', GrantLevel.viewAndEdit);

    expect(find.text('Ho Chi Minh › Assembly'), findsOneWidget);
    expect(find.text('Ho Chi Minh › Packing'), findsOneWidget);
  });

  testWidgets('the Site being browsed can be changed, and one Approval spans Sites',
      (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'HAN', 'Ha Noi')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly', unitType: 'area')],
      },
    );
    await openDecision(tester, wire);

    await grant(tester, '10', GrantLevel.view);

    // A second Site, browsed from its own top.
    await tapIn(tester, find.byKey(OrgUnitPicker.siteKey));
    await tester.tap(find.text('Ha Noi').last);
    await tester.pumpAndSettle();

    expect(wire.orgUnitRequests, [('1', null), ('2', null)]);
    // The tree is the new Site's; the Granted set survived the switch.
    expect(find.byKey(OrgUnitPicker.removeKey('10')), findsOneWidget);
  });

  testWidgets('submitting sends the role and the whole Grant set, each with its level, '
      'in one request', (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    await grant(tester, '11', GrantLevel.view);
    await grant(tester, '12', GrantLevel.viewAndEdit);
    await chooseRole(tester, Roles.supervisor);

    await tapIn(tester, find.byKey(AdmissionDialog.submitKey));

    expect(wire.requests.where((r) => r.endsWith('/approval')).length, 1);
    expect(wire.approvals.length, 1);
    expect(wire.approvals.single['role'], Roles.supervisor);
    expect(wire.approvals.single['grants'], [
      {'orgUnitId': '11', 'canWrite': false, 'qualityAuthority': false},
      {'orgUnitId': '12', 'canWrite': true, 'qualityAuthority': false},
    ]);
    expect(find.text('first@b.c'), findsNothing);
    expect(find.textContaining('with 2 Org Unit Grants'), findsOneWidget);
  });

  testWidgets('an Approval with an empty Grant set is still possible', (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    expect(find.byKey(AdmissionDialog.noGrantsNoticeKey), findsOneWidget);
    await tapIn(tester, find.byKey(AdmissionDialog.submitKey));

    expect(wire.approvals.single['grants'], isEmpty);
    expect(find.textContaining('with no Org Unit Grants'), findsOneWidget);
  });

  // Issue #204, ADR-0035: Quality authority is a separate act from the level
  // a Grant is added at, so the picker gives it through its own control on the
  // Granted row and the request carries it per Grant — one carrying it at
  // View and one not carrying it at View and edit, which is the independence
  // the ticket's own criterion asks for.
  testWidgets('Quality authority is given per Grant, independently of its level, and rides the request',
      (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);

    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    await grant(tester, '11', GrantLevel.view);
    await grant(tester, '12', GrantLevel.viewAndEdit);

    // Neither Grant carries it yet, and the box is there to give it.
    expect(tester.widget<CheckboxListTile>(find.byKey(OrgUnitPicker.qualityKey('11'))).value, false);

    await tapIn(tester, find.byKey(OrgUnitPicker.qualityKey('11')));

    expect(tester.widget<CheckboxListTile>(find.byKey(OrgUnitPicker.qualityKey('11'))).value, true);
    // The tree row says so too, without a second control on the row itself.
    expect(find.text('Granted · View · Quality'), findsOneWidget);

    await chooseRole(tester, Roles.supervisor);
    await tapIn(tester, find.byKey(AdmissionDialog.submitKey));

    expect(wire.approvals.single['grants'], [
      {'orgUnitId': '11', 'canWrite': false, 'qualityAuthority': true},
      {'orgUnitId': '12', 'canWrite': true, 'qualityAuthority': false},
    ]);
  });

  // The other direction, on the same control: ticking and unticking it is how
  // an administrator both gives and takes the flag away, and taking it away
  // changes the request rather than leaving the earlier tick behind.
  testWidgets('Quality authority can be given and then taken back before submitting', (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);

    await grant(tester, '10', GrantLevel.viewAndEdit);
    await tapIn(tester, find.byKey(OrgUnitPicker.qualityKey('10')));
    expect(tester.widget<CheckboxListTile>(find.byKey(OrgUnitPicker.qualityKey('10'))).value, true);

    await tapIn(tester, find.byKey(OrgUnitPicker.qualityKey('10')));
    expect(tester.widget<CheckboxListTile>(find.byKey(OrgUnitPicker.qualityKey('10'))).value, false);
    expect(find.text('Granted · View and edit'), findsOneWidget);

    await chooseRole(tester, Roles.supervisor);
    await tapIn(tester, find.byKey(AdmissionDialog.submitKey));

    expect(wire.approvals.single['grants'], [
      {'orgUnitId': '10', 'canWrite': true, 'qualityAuthority': false},
    ]);
  });

  testWidgets('the administrator role is admitted with no picker and no Grants', (tester) async {
    final wire = _plant();
    await openDecision(tester, wire);
    await grant(tester, '10', GrantLevel.viewAndEdit);
    await chooseRole(tester, Roles.admin);

    expect(find.byType(OrgUnitPicker), findsNothing);
    await tapIn(tester, find.byKey(AdmissionDialog.submitKey));
    expect(wire.approvals.single['grants'], isEmpty);
  });

  testWidgets('a failed Sites load offers a retry that actually re-fetches', (tester) async {
    final wire = _plant()..sitesStatus = 500;
    await openDecision(tester, wire);

    expect(find.byKey(OrgUnitPicker.treeFailureKey), findsOneWidget);
    expect(find.text('Sites are unavailable.'), findsOneWidget);

    wire.sitesStatus = 200;
    await tapIn(tester, find.text('Try again'));

    expect(find.byKey(OrgUnitPicker.treeFailureKey), findsNothing);
    expect(find.text('Assembly'), findsOneWidget);
  });

  testWidgets('a failed root-level load offers a retry that re-reads the same Site',
      (tester) async {
    final wire = _plant()..orgUnitsStatus = 500;
    await openDecision(tester, wire);

    expect(find.byKey(OrgUnitPicker.treeFailureKey), findsOneWidget);
    expect(find.text('The tree is unavailable.'), findsOneWidget);

    wire.orgUnitsStatus = 200;
    await tapIn(tester, find.text('Try again'));

    expect(find.byKey(OrgUnitPicker.treeFailureKey), findsNothing);
    expect(find.text('Assembly'), findsOneWidget);
    // Retried the same Site's root level, not a different request shape.
    expect(wire.orgUnitRequests, [('1', null), ('1', null)]);
  });
}
