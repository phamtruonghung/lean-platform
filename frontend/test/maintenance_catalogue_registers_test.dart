/// The catalogue registers' geometry, measured (issue #388): Assets, Parts,
/// Stores and one Store's stock.
///
/// Each is an `AppTableHeader` band and one `AppTableRow` per record at or above
/// the window its own Screen says, and the card it always had below it. This
/// pins what a reader can see: the band is 32, a row is the height its own file
/// states, a header label starts where its cells start (the edge the alignment
/// makes meaningful), a number column's cells share one right edge in tabular
/// figures, the card height does not drift, a text scale of 2 loses no control
/// and throws nothing, and the edge falls exactly where the Screen says. The app
/// is pumped through the real router with the wire faked, as
/// `work_orders_geometry_test.dart` does; nothing here reaches into a Bloc.
///
/// The app's own fonts are loaded first (`setUpAll(loadAppFonts)`), so every
/// height below is the app's rather than the placeholder font's: these registers
/// size their fixed columns from their own content, so the font is part of what
/// is measured.
///
/// **The edge windows are measured.** A register is handed a box, not the
/// window: the Shell's 260px rail comes off first, so Assets' and Stores' 700 of
/// box — the Screen's own `narrowBreakpoint`, measured by the Screen's own
/// `LayoutBuilder` — is a window of 960. Parts and Store stock measure the
/// *list's* box instead, which has also lost the frame's own width and the
/// list's `Spacing.lg` inset either side: 700 of box is a window of 992. Each
/// number below was found by pumping a window and checking which side of the
/// edge it fell on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/assets_screen.dart';
import 'package:lean_platform/maintenance/parts_screen.dart';
import 'package:lean_platform/maintenance/store_stock_screen.dart';
import 'package:lean_platform/maintenance/stores_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';
import 'register_geometry_support.dart';

final _assets = RegisterSpec(
  name: 'Assets',
  location: '/assets',
  wire: () => FakeWire(
    role: Roles.admin,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {
      '1': [
        assetJson('7', 'PRESS-1', 'Press 1', orgUnitName: 'Line 1'),
        assetJson('8', 'CONV-2', 'Infeed conveyor', orgUnitName: 'Line 2'),
      ],
    },
  ),
  rowKey: AssetsScreen.rowKey,
  ids: const ['7', '8'],
  columns: const [
    ('Name', false),
    ('Code · Type', false),
    ('Org Unit', false),
    ('Criticality', false),
    ('Actions', true),
  ],
  // Retire (44) plus `Spacing.xs` above and below.
  rowHeights: const {'7': 52, '8': 52},
  cardHeights: const {'7': 230, '8': 230},
  tableFromWindow: 960,
  primaryKey: AssetsScreen.retireKey,
);

final _parts = RegisterSpec(
  name: 'Parts',
  location: '/parts',
  wire: () => FakeWire(
    role: Roles.admin,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    parts: [
      partJson('7', 'BRG-6204', 'Bearing, 6204'),
      partJson('8', 'BLT-M8', 'Bolt, M8', uomCode: 'EA'),
    ],
  ),
  rowKey: PartsScreen.rowKey,
  ids: const ['7', '8'],
  columns: const [('Part number', false), ('Description', false), ('Unit', false)],
  // Nothing in a Part row can be pressed, so it is the 32px of a row with no target.
  rowHeights: const {'7': 32, '8': 32},
  cardHeights: const {'7': 62, '8': 62},
  tableFromWindow: 992,
  primaryKey: (_) => PartsScreen.addKey,
);

final _stores = RegisterSpec(
  name: 'Stores',
  location: '/stores',
  wire: () => FakeWire(
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    stores: {
      '1': [
        storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1'),
        storeJson('8', 'B-STORE', 'Spares cage', orgUnitName: 'Line 2'),
      ],
    },
  ),
  rowKey: StoresScreen.rowKey,
  ids: const ['7', '8'],
  columns: const [('Name', false), ('Code · Org Unit', false), ('', true)],
  // The whole row opens the Store's stock, so it is the 44px floor of a tappable row.
  rowHeights: const {'7': 44, '8': 44},
  cardHeights: const {'7': 72, '8': 72},
  tableFromWindow: 960,
  primaryKey: StoresScreen.rowKey,
);

final _stock = RegisterSpec(
  name: 'Store stock',
  location: '/stores/7',
  wire: () => FakeWire(
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    storeRows: {'7': storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1')},
    stock: {
      '7': [
        stockLevelJson('3', 'BRG-6204', 'Bearing, 6204', 14),
        stockLevelJson('4', 'BLT-M8', 'Bolt, M8', 2500),
      ],
    },
  ),
  rowKey: StoreStockScreen.rowKey,
  ids: const ['3', '4'],
  columns: const [
    ('Part number', false),
    ('Description', false),
    ('Quantity', true),
    ('Unit', false),
  ],
  // Nothing in a stock row can be pressed, so it is the 32px of a row with no target.
  rowHeights: const {'3': 32, '4': 32},
  cardHeights: const {'3': 62, '4': 62},
  tableFromWindow: 992,
  primaryKey: (_) => StoreStockScreen.storesCrumbKey,
  numericColumn: 2,
);

void main() {
  setUpAll(loadAppFonts);

  registerGeometryTests(_assets);
  registerGeometryTests(_parts);
  registerGeometryTests(_stores);
  registerGeometryTests(_stock);
}
