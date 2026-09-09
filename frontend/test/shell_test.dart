import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/theme.dart';

/// Stand-in destinations, so these tests exercise the Shell's navigation and
/// role filtering rather than whichever destinations the Platform happens to
/// offer today.
const _directory = Destination(
  label: 'Directory',
  icon: Icons.badge_outlined,
  path: '/directory',
);
const _approvals = Destination(
  label: 'Approvals',
  icon: Icons.how_to_reg_outlined,
  path: '/approvals',
  roles: {Roles.admin},
);
const _testDestinations = [_directory, _approvals];

/// Stand-ins for the grouping tests (#100, ADR-0020): Home ungrouped, two
/// People destinations, one Maintenance destination gated to a role above
/// operator, and one Administration destination gated to admin — enough to
/// exercise every group boundary and both non-admin roles without pulling in
/// the real `platformDestinations`, which is what `_testDestinations` above
/// already avoids for the ungrouped tests.
const _groupedHome = Destination(label: 'Home', icon: Icons.home_outlined, path: '/home');
const _groupedDirectory = Destination(
  label: 'Directory',
  icon: Icons.people_outline,
  path: '/directory',
  group: DestinationGroupNames.people,
);
const _groupedJobRoles = Destination(
  label: 'Job roles',
  icon: Icons.badge_outlined,
  path: '/job-roles',
  group: DestinationGroupNames.people,
);
const _groupedAssets = Destination(
  label: 'Assets',
  icon: Icons.precision_manufacturing_outlined,
  path: '/assets',
  roles: {Roles.supervisor},
  group: DestinationGroupNames.maintenance,
);
const _groupedApprovals = Destination(
  label: 'Approvals',
  icon: Icons.how_to_reg_outlined,
  path: '/approvals',
  roles: {Roles.admin},
  group: DestinationGroupNames.administration,
);
const _groupedDestinations = [
  _groupedHome,
  _groupedDirectory,
  _groupedJobRoles,
  _groupedAssets,
  _groupedApprovals,
];

const _account = AccountActive(id: '1', email: 'a@b.c', displayName: 'A B', role: Roles.admin);

/// The Shell mounted on a real router over the stand-in destinations — the
/// same wiring `router.dart` uses, so selecting a destination really is a
/// change of address.
Widget _harness({List<Destination> destinations = _testDestinations, VoidCallback? onSignOut}) {
  final router = GoRouter(
    initialLocation: destinations.first.path,
    routes: [
      ShellRoute(
        builder: (context, state, child) => PlatformShell(
          destinations: destinations,
          currentLocation: state.uri.path,
          onDestinationSelected: (destination) => context.go(destination.path),
          account: _account,
          onSignOut: onSignOut ?? () {},
          child: child,
        ),
        routes: [
          for (final destination in destinations)
            GoRoute(
              path: destination.path,
              builder: (context, state) => Center(child: Text('${destination.label} Screen')),
            ),
        ],
      ),
    ],
  );
  return MaterialApp.router(theme: buildAppTheme(), routerConfig: router);
}

BoxDecoration? _highlightOf(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(ValueKey('nav-item-$label')),
      matching: find.byType(Container),
    ),
  );
  return container.decoration as BoxDecoration?;
}

void _useNarrowWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(600, 800);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the sidebar carries every destination it is given, and the brand',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    for (final destination in _testDestinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
  });

  testWidgets('selecting a destination navigates by address and swaps the Screen',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('Directory Screen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-item-Approvals')));
    await tester.pumpAndSettle();

    expect(find.text('Approvals Screen'), findsOneWidget);
    expect(find.text('Directory Screen'), findsNothing);
    // The sidebar is the same one: it did not rebuild from scratch around a
    // new Screen.
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);

    // The address really changed, which is what puts the destination in the
    // browser's history and makes its back button work — the history itself
    // belongs to go_router's browser integration, not to the Shell.
    final router = GoRouter.of(tester.element(find.byKey(PlatformShell.sidebarKey)));
    expect(router.state.uri.path, '/approvals');
  });

  testWidgets('the current destination is marked and the others are not', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final scheme = buildAppTheme().colorScheme;
    expect(_highlightOf(tester, 'Directory')?.color, scheme.primaryContainer);
    expect(_highlightOf(tester, 'Approvals')?.color, isNull);

    await tester.tap(find.byKey(const ValueKey('nav-item-Approvals')));
    await tester.pumpAndSettle();

    expect(_highlightOf(tester, 'Approvals')?.color, scheme.primaryContainer);
    expect(_highlightOf(tester, 'Directory')?.color, isNull);
  });

  testWidgets('the destination list shrinks for a role that earns fewer', (tester) async {
    await tester.pumpWidget(
      _harness(
        destinations: destinationsFor(role: Roles.operator, destinations: _testDestinations),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Approvals'), findsNothing);
  });

  testWidgets('the footer names the signed-in Account and signs it out', (tester) async {
    var signedOut = 0;
    await tester.pumpWidget(_harness(onSignOut: () => signedOut++));
    await tester.pumpAndSettle();

    expect(find.text('A B'), findsOneWidget);
    expect(find.text('a@b.c'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(signedOut, 1);
  });

  testWidgets('a wide window gets the expanded sidebar with labels', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(PlatformShell.sidebarKey)).width,
      PlatformShell.expandedWidth,
    );
    expect(find.text('Approvals'), findsOneWidget);
  });

  testWidgets('below the breakpoint the sidebar collapses to an icon rail with tooltips',
      (tester) async {
    _useNarrowWindow(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(PlatformShell.sidebarKey)).width,
      PlatformShell.collapsedWidth,
    );
    for (final destination in _testDestinations) {
      expect(find.text(destination.label), findsNothing);
      expect(find.byTooltip(destination.label), findsOneWidget);
    }
    expect(find.byTooltip('Sign out'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-item-Approvals')));
    await tester.pumpAndSettle();
    expect(find.text('Approvals Screen'), findsOneWidget);
  });

  // Grouping (#100, ADR-0020): the sidebar files destinations under headings
  // rather than one flat column. `_groupedDestinations` stands in for the
  // real `platformDestinations` so these tests exercise the Shell's own
  // grouping and role-filtering behaviour rather than today's real list.

  testWidgets('the groups render in order, with each destination under its own heading',
      (tester) async {
    await tester.pumpWidget(_harness(destinations: _groupedDestinations));
    await tester.pumpAndSettle();

    double dyOf(Finder finder) => tester.getTopLeft(finder).dy;
    final positions = <String, double>{
      'Home': dyOf(find.byKey(const ValueKey('nav-item-Home'))),
      'PEOPLE': dyOf(find.text('PEOPLE')),
      'Directory': dyOf(find.byKey(const ValueKey('nav-item-Directory'))),
      'Job roles': dyOf(find.byKey(const ValueKey('nav-item-Job roles'))),
      'MAINTENANCE': dyOf(find.text('MAINTENANCE')),
      'Assets': dyOf(find.byKey(const ValueKey('nav-item-Assets'))),
      'ADMINISTRATION': dyOf(find.text('ADMINISTRATION')),
      'Approvals': dyOf(find.byKey(const ValueKey('nav-item-Approvals'))),
    };
    final orderedByPosition = positions.keys.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));

    // The heading text is uppercased (rule 5's visual weight), and each
    // destination sits directly beneath the heading its `group` names —
    // this single top-to-bottom ordering proves both at once.
    expect(orderedByPosition, [
      'Home',
      'PEOPLE',
      'Directory',
      'Job roles',
      'MAINTENANCE',
      'Assets',
      'ADMINISTRATION',
      'Approvals',
    ]);
  });

  testWidgets('a role that earns fewer destinations sees fewer groups', (tester) async {
    final operatorDestinations = destinationsFor(
      role: Roles.operator,
      destinations: _groupedDestinations,
    );
    await tester.pumpWidget(_harness(destinations: operatorDestinations));
    await tester.pumpAndSettle();

    // Operator earns Home and the People destinations (no `roles` set on
    // either), but not Assets (supervisor-and-above) or Approvals
    // (admin-only) — so only People's heading survives.
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsNothing);
    expect(find.text('ADMINISTRATION'), findsNothing);
  });

  testWidgets('a group whose destinations are all filtered away renders no heading',
      (tester) async {
    final supervisorDestinations = destinationsFor(
      role: Roles.supervisor,
      destinations: _groupedDestinations,
    );
    await tester.pumpWidget(_harness(destinations: supervisorDestinations));
    await tester.pumpAndSettle();

    // A supervisor earns People and Maintenance (Assets), but Administration
    // held only the admin-only Approvals — every one of its destinations was
    // filtered away, so its heading must not render at all, not even empty.
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(find.text('ADMINISTRATION'), findsNothing);
  });

  testWidgets('the rail below the breakpoint renders no headings, only a hairline per boundary',
      (tester) async {
    _useNarrowWindow(tester);
    await tester.pumpWidget(_harness(destinations: _groupedDestinations));
    await tester.pumpAndSettle();

    expect(find.text('PEOPLE'), findsNothing);
    expect(find.text('MAINTENANCE'), findsNothing);
    expect(find.text('ADMINISTRATION'), findsNothing);

    // Three group boundaries (Home|People, People|Maintenance,
    // Maintenance|Administration) plus the account footer's own divider.
    expect(find.byType(Divider), findsNWidgets(4));

    for (final destination in _groupedDestinations) {
      expect(find.byTooltip(destination.label), findsOneWidget);
    }
  });

  testWidgets('the current destination is still marked after grouping', (tester) async {
    await tester.pumpWidget(_harness(destinations: _groupedDestinations));
    await tester.pumpAndSettle();

    final scheme = buildAppTheme().colorScheme;
    expect(_highlightOf(tester, 'Home')?.color, scheme.primaryContainer);
    expect(_highlightOf(tester, 'Directory')?.color, isNull);

    await tester.tap(find.byKey(const ValueKey('nav-item-Directory')));
    await tester.pumpAndSettle();

    expect(_highlightOf(tester, 'Directory')?.color, scheme.primaryContainer);
    expect(_highlightOf(tester, 'Home')?.color, isNull);
  });

  testWidgets('selecting a grouped destination still navigates by address', (tester) async {
    await tester.pumpWidget(_harness(destinations: _groupedDestinations));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-item-Assets')));
    await tester.pumpAndSettle();

    expect(find.text('Assets Screen'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byKey(PlatformShell.sidebarKey)));
    expect(router.state.uri.path, '/assets');
  });
}
