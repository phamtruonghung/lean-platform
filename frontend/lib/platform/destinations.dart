/// The places an admitted Account can go, and which Accounts earn them.
///
/// Destinations name what a person does — the Directory, the Approval queue —
/// never the Module they belong to: nobody navigates to "People" (issue #39).
///
/// The sidebar files Destinations under group headings that *do* name the
/// Module behind them — People, Maintenance, Insights, Administration — which
/// issue #100 and ADR-0020 record as a deliberate, loud reversal of the
/// paragraph above's original rule. A group is a label and nothing more: it
/// has no address, cannot be selected, and opens nothing, so #39's real
/// concern (a Destination that opens a Module landing page) is still avoided.
/// See [DestinationGroup] and [groupDestinations].
library;

import 'package:flutter/material.dart';

import 'router.dart';

/// The role strings the API answers with, mirroring the backend's own `ROLES`
/// (`backend/src/modules/people/authorization.js`).
abstract final class Roles {
  static const String operator = 'operator';
  static const String supervisor = 'supervisor';
  static const String engineer = 'engineer';
  static const String manager = 'manager';
  static const String admin = 'admin';
}

/// The roles that earn a whole Module, named once so the sidebar and the
/// route guard cannot disagree about who is let in. Maintenance's tool-and-
/// equipment Destinations (Assets, Work orders, Triage queue) are offered to
/// supervisor, engineer, manager and administrator, and not to operator: an
/// operator's own work is raising a Request and following it, which the
/// un-gated `My requests` Destination beside them covers (#55, #72).
abstract final class ModuleRoles {
  static const Set<String> maintenance = {
    Roles.supervisor,
    Roles.engineer,
    Roles.manager,
    Roles.admin,
  };
}

/// One entry in the Shell's sidebar.
@immutable
class Destination {
  const Destination({
    required this.label,
    required this.icon,
    required this.path,
    this.roles,
    this.group,
  });

  final String label;
  final IconData icon;
  final String path;

  /// The roles that earn this destination, or null for one every admitted
  /// Account may reach.
  final Set<String>? roles;

  /// The heading this destination is filed under — one of
  /// [DestinationGroupNames]'s constants — or null to sit ungrouped above
  /// every heading, which only Home does (#100, ADR-0020). A literal string
  /// works here too, but a constant means a typo cannot silently create a
  /// heading [groupDestinations] never renders because it is not in
  /// [DestinationGroupNames.order].
  final String? group;

  bool isVisibleTo(String role) => roles == null || roles!.contains(role);

  /// Whether [location] is this destination or something beneath it.
  bool matches(String location) =>
      location == path || (path != '/' && location.startsWith('$path/'));
}

/// The Destination the Shell marks as current for [location] — the one whose own
/// path is the **most specific** match, or null when nothing matches (sign-in,
/// awaiting-Approval, the not-found Screen).
///
/// Most specific rather than every one that matches, because a Destination may
/// legitimately sit under another's address: the CAPA list is at
/// `/actions/capas` (issue #211), beneath the action log's own `/actions`, and a
/// Screen that marked every prefix would light two entries at once. The longest
/// matching path is the one the reader is actually in — the same rule the
/// address itself already follows, since a router matches the deepest route that
/// fits.
String? selectedDestinationPath(List<Destination> destinations, String location) {
  String? best;
  for (final destination in destinations) {
    if (!destination.matches(location)) continue;
    if (best == null || destination.path.length > best.length) best = destination.path;
  }
  return best;
}

/// The fixed order the sidebar's group headings render in (#100, ADR-0020).
/// Named once so the Shell and [platformDestinations] cannot disagree about
/// where a new Module's heading belongs.
abstract final class DestinationGroupNames {
  static const String people = 'People';
  static const String maintenance = 'Maintenance';
  static const String quality = 'Quality';
  static const String actions = 'Actions';
  static const String safety = 'Safety';
  static const String insights = 'Insights';
  static const String administration = 'Administration';

  static const List<String> order = [
    people,
    maintenance,
    actions,
    quality,
    safety,
    insights,
    administration,
  ];
}

/// One heading the Shell's sidebar files [Destination]s under, plus the
/// Destinations filed there — CONTEXT.md's **Destination group** entry.
///
/// A group is a label and nothing more: it has no address, cannot be
/// selected, and opens nothing (#100, ADR-0020). [name] is null only for the
/// ungrouped bucket at the top of the sidebar, which today holds Home alone
/// and renders no heading of its own.
@immutable
class DestinationGroup {
  const DestinationGroup({required this.name, required this.destinations});

  final String? name;
  final List<Destination> destinations;
}

/// Files an already role-filtered [destinations] list (the output of
/// [destinationsFor]) under its headings, in [DestinationGroupNames.order].
///
/// Grouping is done by [DestinationGroupNames.order] rather than by list
/// order, so a group survives role filtering removing some — or all — of its
/// members without needing its remaining Destinations to stay adjacent. A
/// heading with no Destination left under it (either because
/// [platformDestinations] never gave it one, or because an Account's role
/// filtered every member away) is skipped entirely: an operator must never
/// see an empty **Administration** label (#100, ADR-0020). The Shell still
/// gates nothing itself — this only re-files what [destinationsFor] already
/// decided was visible.
List<DestinationGroup> groupDestinations(List<Destination> destinations) {
  final ungrouped = [
    for (final destination in destinations)
      if (destination.group == null) destination,
  ];
  return [
    if (ungrouped.isNotEmpty) DestinationGroup(name: null, destinations: ungrouped),
    for (final name in DestinationGroupNames.order)
      if (destinations.any((destination) => destination.group == name))
        DestinationGroup(
          name: name,
          destinations: [
            for (final destination in destinations)
              if (destination.group == name) destination,
          ],
        ),
  ];
}

// Ordered to match ADR-0020's table: Home ungrouped, then each group's
// members together, in the order the groups themselves render
// (DestinationGroupNames.order). `groupDestinations` re-files by [Destination.group]
// rather than by list position, so this ordering is not load-bearing for the
// Shell — but keeping it lines up with the table makes this list itself
// readable as the spec it implements.
const List<Destination> platformDestinations = [
  Destination(label: 'Home', icon: Icons.home_outlined, path: Routes.home),
  // Offered to every approved Account — no `roles` set, the same "everyone
  // admitted may reach this" shape Home already uses. ADR-0009 is exactly
  // the decision that a plant directory is not a secret gated by role.
  Destination(
    label: 'Directory',
    icon: Icons.people_outline,
    path: Routes.directory,
    group: DestinationGroupNames.people,
  ),
  // Also offered to every approved Account, for the same reason (issue #88):
  // `GET /job-roles` carries no admin or scope check of its own
  // (job-role-routes.js's own header), and it is what the Directory's own
  // job role filter and every Assignment's job role choice already read —
  // hiding the destination behind a role would gate a Screen the route
  // itself never refuses. Only the write affordances inside the Screen are
  // gated to an administrator.
  Destination(
    label: 'Job roles',
    icon: Icons.badge_outlined,
    path: Routes.jobRoles,
    group: DestinationGroupNames.people,
  ),
  // Also offered to every approved Account, for the same reason (issue #89):
  // `GET /skills` carries no admin or scope check of its own
  // (skill-routes.js's own header). Only the write affordances inside the
  // Screen are gated to an administrator.
  Destination(
    label: 'Skills',
    icon: Icons.verified_outlined,
    path: Routes.skills,
    group: DestinationGroupNames.people,
  ),
  // Also offered to every approved Account, for the same reason (issue #90):
  // neither `GET /sites` nor `GET .../org-units` carries an admin or scope
  // check of its own (ADR-0009's "a plant directory is not a secret" applies
  // here too). Only the write affordances inside the Screen are gated —
  // creating a root Org Unit to an administrator (ADR-0008), everything else
  // to the server's own scope check.
  Destination(
    label: 'Org Units',
    icon: Icons.account_tree_outlined,
    path: Routes.orgUnits,
    group: DestinationGroupNames.people,
  ),
  Destination(
    label: 'Assets',
    icon: Icons.precision_manufacturing_outlined,
    path: Routes.assets,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // Parts and Stores (issue #80) are maintenance's own work too — the shared
  // catalogue and the shelves a job draws from — so they follow the same
  // Module role set as Assets and Work orders. Filed under Maintenance rather
  // than a group of their own: inventory is part of this Module, not a
  // separate one (ADR-0028).
  Destination(
    label: 'Parts',
    icon: Icons.inventory_2_outlined,
    path: Routes.parts,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  Destination(
    label: 'Stores',
    icon: Icons.warehouse_outlined,
    path: Routes.stores,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  Destination(
    label: 'Work orders',
    icon: Icons.build_outlined,
    path: Routes.workOrders,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // My requests (issue #72) is offered to every approved Account — no `roles`
  // set, the same "everyone admitted may reach this" shape Home and the
  // Directory already use. Anyone on the floor may raise a Request (raising
  // needs only a read Grant reaching the Asset's Org Unit), and this is where
  // they follow what they raised through to whatever became of it. This is the
  // Destination an operator earns the Module with, and deliberately the only
  // Maintenance one they are offered.
  Destination(
    label: 'My requests',
    icon: Icons.assignment_outlined,
    path: Routes.myRequests,
    group: DestinationGroupNames.maintenance,
  ),
  // The triage queue (issue #72) is maintenance's own work — accepting,
  // declining and de-duplicating what the floor asked for — so it follows the
  // Module's role set exactly as Assets and Work orders do.
  Destination(
    label: 'Triage queue',
    icon: Icons.rule_folder_outlined,
    path: Routes.requests,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // Downtime (issue #73) is maintenance's own work too — closing and
  // classifying the stops reported on the floor, and recording a Breakdown —
  // so it follows the same Module role set as Assets, Work orders and the
  // Triage queue, and is deliberately not offered to an operator.
  Destination(
    label: 'Downtime',
    icon: Icons.warning_amber_outlined,
    path: Routes.downtime,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // PM schedules (issue #74) follow the same Module role set as the rest of
  // maintenance: a supervisor, engineer, manager or administrator attaches a
  // Job plan to an Asset and reads what comes round next. An operator does
  // not, the same as every other Maintenance Destination but My requests.
  Destination(
    label: 'PM schedules',
    icon: Icons.event_repeat_outlined,
    path: Routes.pmSchedules,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // Meters (issue #79) are the instrument a PM schedule comes due on when it
  // runs on accumulated use rather than elapsed time, so they follow the same
  // Module role set as the schedules they feed.
  Destination(
    label: 'Meters',
    icon: Icons.speed_outlined,
    path: Routes.meters,
    roles: ModuleRoles.maintenance,
    group: DestinationGroupNames.maintenance,
  ),
  // Job plans (issue #74) is the administrator-managed catalogue a PM
  // schedule is built from, so its Destination is administrator-only — unlike
  // Skills and Job roles, whose reads the server leaves open, job-plan-routes.js
  // gates the whole catalogue's write surface on the administrator role and the
  // ticket treats it as an admin catalogue. The route itself admits maintenance
  // roles to read; this hides the door from everyone else's sidebar.
  Destination(
    label: 'Job plans',
    icon: Icons.description_outlined,
    path: Routes.jobPlans,
    roles: {Roles.admin},
    group: DestinationGroupNames.maintenance,
  ),
  // The tier board (issue #76) is offered to every approved Account — no
  // `roles` set, the same "everyone admitted may reach this" shape Home, the
  // Directory and My requests already use. The board is plant-wide and its read
  // is Site-wide with no Grant filter (ADR-0009): a tier board a supervisor can
  // only half-see is not a tier board. Filed under Insights rather than
  // Maintenance because it is a read about how the plant is being run, fed by
  // whichever Module's work, not a tool Maintenance does its own work in
  // (#100, ADR-0020).
  Destination(
    label: 'Tier board',
    icon: Icons.dashboard_outlined,
    path: Routes.tierBoard,
    group: DestinationGroupNames.insights,
  ),
  // Administrator only (issue #89) — `GET .../skill-coverage` is deliberately
  // narrower than every other Site-shaped read in the People Module
  // (skill-routes.js's own header: "how the plant is being run", not "who
  // works here"), the same reasoning that keeps `Accounts` administrator-only
  // below. Filed under Insights rather than People, for the same reason: it
  // is a read about how the plant is run, not about its people (#100,
  // ADR-0020).
  Destination(
    label: 'Skill coverage',
    icon: Icons.query_stats_outlined,
    path: Routes.skillCoverage,
    roles: {Roles.admin},
    group: DestinationGroupNames.insights,
  ),
  // Actions (issue #176) — the action log, and the first Destination behind a
  // Module of its own rather than one of the three that already existed
  // (ADR-0032). Offered to every approved Account, no `roles` set, the same
  // shape Home, the Directory and My requests use: anyone on the floor may
  // raise a Concern where they found it, and raising needs only a read Grant
  // reaching that Org Unit. Filed under its own heading, between the groups
  // where work is done and the groups where the plant is read about.
  Destination(
    label: 'Action log',
    icon: Icons.assignment_turned_in_outlined,
    path: Routes.actions,
    group: DestinationGroupNames.actions,
  ),
  // The Quality Module's two catalogues (issue #203) — the first Destinations
  // behind a fourth Module of its own after People, Maintenance and Actions
  // (ADR-0032's precedent for a Module earning its own heading). Offered to
  // every approved Account, no `roles` set, the same shape Directory, Job
  // roles, Skills and My requests use: both reads carry no admin and no Org
  // Unit scope of their own (product-routes.js's and defect-code-routes.js's
  // own headers — reference data everyone needs as a set of choices, ADR-0023),
  // so hiding the doors behind a role would gate addresses the routes never
  // refuse. Only the write affordances inside each Screen are gated to
  // `isAdmin`.
  //
  // Filed under Quality's own heading between Actions and Insights. ADR-0032
  // put Actions at the boundary between the groups where work is done and the
  // groups where the plant is read about, and that position is pinned by
  // actions_test.dart; Quality is filed beside it rather than in front of it,
  // so a new Module does not displace a decision another ADR already recorded.
  // The two catalogues are what this Module owns today; its Non-conformances
  // and CAPAs arrive as their own slices and file here.
  Destination(
    label: 'Products',
    icon: Icons.category_outlined,
    path: Routes.products,
    group: DestinationGroupNames.quality,
  ),
  Destination(
    label: 'Defect codes',
    icon: Icons.rule_outlined,
    path: Routes.defectCodes,
    group: DestinationGroupNames.quality,
  ),
  // The Module's first record of real work (issue #205): what has been found
  // not to conform. Offered to every approved Account like the two catalogues
  // above it, because the register is a Site-wide read (`canSeeSite`) and
  // recording needs only a write Grant reaching the Org Unit it is recorded
  // at — both of which the server decides, so a role on this Destination would
  // gate a door the route itself opens for an operator who works on the line.
  Destination(
    label: 'Non-conformances',
    icon: Icons.fact_check_outlined,
    path: Routes.nonConformances,
    group: DestinationGroupNames.quality,
  ),
  // The CAPA list (issue #211) — the investigations a Concern has been turned
  // into, and the effectiveness check each one is waiting on. Filed here, under
  // Quality, rather than with the Action log whose Module owns the record
  // (ADR-0034 keeps a CAPA beside its Concern rather than in a screen of its
  // own): a person scanning the sidebar is looking for quality's work, and the
  // address is this Module's only because the Concern it hangs off is.
  //
  // Offered to every approved Account, the same shape the four Quality
  // Destinations above it use: the list is a platform-wide read (ADR-0009), and
  // the one gate in the slice — who may record an effectiveness check — is
  // per-record and lives on the check's own address.
  Destination(
    label: 'CAPAs',
    icon: Icons.verified_outlined,
    path: Routes.capas,
    group: DestinationGroupNames.quality,
  ),
  // The Customer list and the customer complaints (issue #214). Filed here,
  // under Quality: a complaint is a quality record — the baseline's own table
  // is in the Quality pillar and its own comment says a Customer exists "so a
  // complaint has someone to belong to" — and the addresses are this Module's.
  //
  // Offered to every approved Account, the same shape the five Quality
  // Destinations above them use. The Customer list is shared reference data
  // (ADR-0005) and the complaint register is a Site-wide read, both of which
  // the server decides, so a role here would gate doors the routes themselves
  // open for an operator. The write affordances inside each Screen are what is
  // gated, and the server is the real gate on both: the administrator role for
  // a Customer, an edit Grant reaching the Org Unit for a complaint.
  Destination(
    label: 'Customers',
    icon: Icons.handshake_outlined,
    path: Routes.customers,
    group: DestinationGroupNames.quality,
  ),
  Destination(
    label: 'Customer complaints',
    icon: Icons.support_agent_outlined,
    path: Routes.complaints,
    group: DestinationGroupNames.quality,
  ),
  // The Supplier list and the supplier NCRs (issue #215) — the same surface
  // turned outward, filed beside the Customer pair for the same reasons: a
  // supplier NCR is a quality record (the baseline's own table is in the
  // Quality pillar and its comment says a Supplier exists "so an incoming
  // non-conformance has someone to charge"), and its addresses are this
  // Module's.
  //
  // Offered to every approved Account, the same shape the seven Quality
  // Destinations above them use: the Supplier list is shared reference data
  // (ADR-0005) and the register is a Site-wide read, both of which the server
  // decides, so a role here would gate doors the routes themselves open for an
  // operator. The write affordances inside each Screen are what is gated, and
  // the server is the real gate on both: the administrator role for a Supplier,
  // an edit Grant reaching the Org Unit for a supplier NCR.
  Destination(
    label: 'Suppliers',
    icon: Icons.local_shipping_outlined,
    path: Routes.suppliers,
    group: DestinationGroupNames.quality,
  ),
  Destination(
    label: 'Supplier NCRs',
    icon: Icons.report_gmailerrorred_outlined,
    path: Routes.supplierNcrs,
    group: DestinationGroupNames.quality,
  ),
  // The Safety Module's Destinations. The binding design on #223 names a
  // four-entry group — Incidents, Observations, Injury types, Body parts —
  // and all four exist as of issue #230. A group whose Destinations all
  // filter away renders no heading at all (#100, ADR-0020's own rule), which
  // is what lets the two administrator-only entries below sit here without
  // changing what a line supervisor sees.
  //
  // Offered to every approved Account, the same shape the Quality
  // Destinations above it use: the register is a Site-wide read
  // (`canSeeSite`) and recording needs only a write Grant reaching the Org
  // Unit it occurred at, or the administrator role — both of which the
  // server decides, so a role here would gate a door the route itself opens
  // for an operator who works on the line.
  Destination(
    label: 'Incidents',
    icon: Icons.health_and_safety_outlined,
    path: Routes.safetyIncidents,
    group: DestinationGroupNames.safety,
  ),
  // The leading indicator (issue #230): what was seen before anything went
  // wrong. Offered to every approved Account, the same reasoning as
  // Incidents above — the register is Site-wide and recording needs only a
  // write Grant or the administrator role, both server-decided.
  Destination(
    label: 'Observations',
    icon: Icons.visibility_outlined,
    path: Routes.safetyObservations,
    group: DestinationGroupNames.safety,
  ),
  // The Module's two shared catalogues (issue #224): what an injury was, and
  // where on the body. **Administrator only**, and deliberately unlike the
  // Quality Module's own two catalogues above, which are offered to everyone.
  // The binding design comment on #223 settles it: "the last two filter away
  // for a non-administrator, and a group whose Destinations all filter away
  // renders no heading — so a line supervisor sees a two-entry Safety group
  // and an administrator sees four". A line supervisor never maintains these;
  // the one thing they do with an Injury type is pick it in the classify
  // dialog, which reads the catalogue for itself.
  //
  // The Screens behind these addresses are NOT gated, because the reads are
  // not (injury-type-routes.js/body-part-routes.js open them to any active
  // Account): a non-administrator who follows a link sees the catalogue with
  // no write affordances on it, exactly as they would on `/products`. Only the
  // sidebar entry is filtered.
  Destination(
    label: 'Injury types',
    icon: Icons.healing_outlined,
    path: Routes.injuryTypes,
    roles: {Roles.admin},
    group: DestinationGroupNames.safety,
  ),
  Destination(
    label: 'Body parts',
    icon: Icons.accessibility_new_outlined,
    path: Routes.bodyParts,
    roles: {Roles.admin},
    group: DestinationGroupNames.safety,
  ),
  // Approvals and Accounts administer the Platform itself — who may sign in,
  // and what they may reach — rather than the plant's workforce, so they sit
  // under Administration rather than People (#100, ADR-0020).
  Destination(
    label: 'Approvals',
    icon: Icons.how_to_reg_outlined,
    path: Routes.approvals,
    roles: {Roles.admin},
    group: DestinationGroupNames.administration,
  ),
  Destination(
    label: 'Accounts',
    icon: Icons.manage_accounts_outlined,
    path: Routes.accounts,
    roles: {Roles.admin},
    group: DestinationGroupNames.administration,
  ),
];

/// The destinations an Account holding [role] may use.
List<Destination> destinationsFor({
  required String role,
  List<Destination> destinations = platformDestinations,
}) {
  return [
    for (final destination in destinations)
      if (destination.isVisibleTo(role)) destination,
  ];
}
