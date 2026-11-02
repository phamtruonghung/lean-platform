/// The two Request queues as triage registers, measured (issue #388): the
/// Requests triage queue and My requests.
///
/// A queue is designed as a register like any other here: state as a chip, who
/// raised it, the raised date as a right-aligned number column, and the decision
/// visible without opening the record. Both state 960 and 900 of box because
/// their columns, not their taste, made 700 clip — so the Requests queue switches
/// at a window of 1220 and My requests at 1160 (its own number plus the Shell's
/// 260px rail), each found by pumping a window and checking which side of the
/// edge it fell on.
///
/// The fixture raises a Request on 31 October and another on 2 November on
/// purpose: the two dates have different digit counts, so their shared right edge
/// proves the column is end-aligned rather than equally wide.
///
/// The app's own fonts are loaded first (`setUpAll(loadAppFonts)`). It matters
/// most here: these two Screens size their fixed columns from their content, and
/// the placeholder font is about twice as wide, which would overflow a 900px box
/// that fits in the app's own font with room to spare.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/my_requests_screen.dart';
import 'package:lean_platform/maintenance/requests_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';
import 'register_geometry_support.dart';

/// A supervisor holding a write Grant at Org Unit 10 — the caller the triage
/// queue offers Accept to.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

List<Map<String, dynamic>> _requests() => [
      requestJson('21', 'MR-BUC-2026-00001', 'Belt is slipping',
          reportedAt: DateTime.utc(2026, 10, 31, 9)),
      requestJson('22', 'MR-BUC-2026-00002', 'Guard is loose',
          reportedAt: DateTime.utc(2026, 11, 2, 9)),
    ];

final _triage = RegisterSpec(
  name: 'Requests',
  location: '/requests',
  wire: () => FakeWire(
    role: Roles.supervisor,
    orgUnitScope: _writeGrant,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    triageRequests: {'1': _requests()},
  ),
  rowKey: RequestsScreen.rowKey,
  ids: const ['21', '22'],
  columns: const [
    ('Request', false),
    ('Summary', false),
    ('Asset', false),
    ('Raised by', false),
    ('Raised', true),
    ('Status', false),
    ('Urgency', false),
    ('Actions', true),
  ],
  // Accept (44) beside the kebab, plus `Spacing.xs` above and below.
  rowHeights: const {'21': 52, '22': 52},
  cardHeights: const {'21': 172, '22': 172},
  tableFromWindow: 1220,
  primaryKey: RequestsScreen.acceptKey,
  numericColumn: 4,
);

final _mine = RegisterSpec(
  name: 'My requests',
  location: '/my-requests',
  wire: () => FakeWire(
    role: Roles.operator,
    orgUnitScope: _writeGrant,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    myRequests: {'1': _requests()},
  ),
  rowKey: MyRequestsScreen.rowKey,
  ids: const ['21', '22'],
  columns: const [
    ('Request', false),
    ('Summary', false),
    ('Asset', false),
    ('Urgency', false),
    ('Status', false),
    ('Raised', true),
    ('Outcome', false),
  ],
  // A Request nobody has decided yet has no toggle and no button, so the row is
  // its cells' own height: the state chip (32) in `AppTableRow`'s `Spacing.xs`
  // padding either side.
  rowHeights: const {'21': 40, '22': 40},
  cardHeights: const {'21': 88, '22': 88},
  tableFromWindow: 1160,
  // No per-row control exists on a request nobody has decided, so the control a
  // reader must still reach at 2x text is the queue's own filter box.
  primaryKey: (_) => MyRequestsScreen.filterFieldKey,
  numericColumn: 5,
);

void main() {
  setUpAll(loadAppFonts);

  registerGeometryTests(_triage);
  registerGeometryTests(_mine);
}
