import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../auth/awaiting_approval_screen.dart';
import '../auth/sign_in_screen.dart';
import '../actions/action_detail_bloc.dart';
import '../actions/action_detail_screen.dart';
import '../actions/action.dart';
import '../actions/action_cancel_dialog.dart';
import '../actions/action_escalate_dialog.dart';
import '../actions/action_form_dialog.dart';
import '../actions/action_measure_dialog.dart';
import '../actions/action_phase_complete_dialog.dart';
import '../actions/action_unlink_nonconformance_dialog.dart';
import '../actions/actions_api.dart';
import '../actions/actions_bloc.dart';
import '../actions/actions_screen.dart';
import '../actions/capa.dart';
import '../actions/capa_cause_dialog.dart';
import '../actions/capa_detail_bloc.dart';
import '../actions/capa_detail_screen.dart';
import '../actions/capa_effectiveness_dialog.dart';
import '../actions/capa_report_screen.dart';
import '../actions/capa_why_dialog.dart';
import '../actions/capas_bloc.dart';
import '../actions/capas_screen.dart';
import '../actions/open_capa_dialog.dart';
import '../home_bloc.dart';
import '../home_screen.dart';
import '../maintenance/assets_bloc.dart';
import '../maintenance/assets_screen.dart';
import '../maintenance/downtime_bloc.dart';
import '../maintenance/downtime_screen.dart';
import '../maintenance/floor_bloc.dart';
import '../maintenance/floor_screen.dart';
import '../maintenance/job_plans_bloc.dart';
import '../maintenance/job_plans_screen.dart';
import '../maintenance/maintenance_api.dart';
import '../maintenance/meters_bloc.dart';
import '../maintenance/meters_screen.dart';
import '../maintenance/my_requests_bloc.dart';
import '../maintenance/my_requests_screen.dart';
import '../maintenance/parts_bloc.dart';
import '../maintenance/parts_screen.dart';
import '../maintenance/pm_schedules_bloc.dart';
import '../maintenance/pm_schedules_screen.dart';
import '../maintenance/requests_bloc.dart';
import '../maintenance/requests_screen.dart';
import '../maintenance/store_stock_bloc.dart';
import '../maintenance/store_stock_screen.dart';
import '../maintenance/stores_bloc.dart';
import '../maintenance/stores_screen.dart';
import '../maintenance/tier_board_bloc.dart';
import '../maintenance/tier_board_screen.dart';
import '../maintenance/work_order.dart';
import '../maintenance/work_order_assign_dialog.dart';
import '../maintenance/work_order_cancel_dialog.dart';
import '../maintenance/work_order_complete_dialog.dart';
import '../maintenance/work_order_detail_bloc.dart';
import '../maintenance/work_order_detail_screen.dart';
import '../maintenance/work_order_dialog_host.dart';
import '../maintenance/work_order_form_dialog.dart';
import '../maintenance/work_orders_bloc.dart';
import '../maintenance/work_orders_screen.dart';
import '../people/accounts_bloc.dart';
import '../people/accounts_screen.dart';
import '../people/approval_queue_bloc.dart';
import '../people/approval_queue_screen.dart';
import '../people/attendance_picker_screen.dart';
import '../people/attendance_sheet_bloc.dart';
import '../people/attendance_sheet_screen.dart';
import '../people/directory_bloc.dart';
import '../people/directory_screen.dart';
import '../people/employee_detail_bloc.dart';
import '../people/employee_detail_screen.dart';
import '../people/job_roles_bloc.dart';
import '../people/job_roles_screen.dart';
import '../people/org_unit_admin_bloc.dart';
import '../people/org_unit_picker_bloc.dart';
import '../people/org_units_screen.dart';
import '../people/skill_coverage_bloc.dart';
import '../people/skill_coverage_screen.dart';
import '../people/skills_bloc.dart';
import '../people/skills_screen.dart';
import '../people_api.dart';
import '../quality/complaint_detail_bloc.dart';
import '../quality/complaint_detail_screen.dart';
import '../quality/complaint_form_dialog.dart';
import '../quality/complaint_link_dialog.dart';
import '../quality/complaint_nonconformance_dialog.dart';
import '../quality/complaint_respond_dialog.dart';
import '../quality/complaints_bloc.dart';
import '../quality/complaints_screen.dart';
import '../quality/customers_bloc.dart';
import '../quality/customers_screen.dart';
import '../quality/supplier_ncr_detail_bloc.dart';
import '../quality/supplier_ncr_detail_screen.dart';
import '../quality/supplier_ncr_disposition_dialog.dart';
import '../quality/supplier_ncr_form_dialog.dart';
import '../quality/supplier_ncr_link_dialog.dart';
import '../quality/supplier_ncr_nonconformance_dialog.dart';
import '../quality/supplier_ncrs_bloc.dart';
import '../quality/supplier_ncrs_screen.dart';
import '../quality/suppliers_bloc.dart';
import '../quality/suppliers_screen.dart';
import '../quality/defect_codes_bloc.dart';
import '../quality/defect_codes_screen.dart';
import '../quality/nonconformance_cancel_dialog.dart';
import '../quality/nonconformance_concession_dialog.dart';
import '../quality/nonconformance_detail_bloc.dart';
import '../quality/nonconformance_detail_screen.dart';
import '../quality/nonconformance_disposition_dialog.dart';
import '../quality/nonconformance_form_dialog.dart';
import '../quality/nonconformance_link_concern_dialog.dart';
import '../quality/nonconformance_lower_severity_dialog.dart';
import '../quality/nonconformance_quantity_dialog.dart';
import '../quality/nonconformance_raise_concern_dialog.dart';
import '../quality/nonconformance_reopen_dialog.dart';
import '../quality/nonconformance_update_dialog.dart';
import '../quality/nonconformances_bloc.dart';
import '../quality/nonconformances_screen.dart';
import '../quality/products_bloc.dart';
import '../quality/products_screen.dart';
import '../quality/quality_api.dart';
import '../safety/body_parts_bloc.dart';
import '../safety/body_parts_screen.dart';
import '../safety/incident_classify_dialog.dart';
import '../safety/incident_close_dialog.dart';
import '../safety/incident_days_dialog.dart';
import '../safety/incident_detail_bloc.dart';
import '../safety/incident_detail_screen.dart';
import '../safety/incident_due_date_dialog.dart';
import '../safety/incident_form_dialog.dart';
import '../safety/incident_raise_concern_dialog.dart';
import '../safety/incident_severity_dialog.dart';
import '../safety/incident_status_dialog.dart';
import '../safety/incidents_screen.dart';
import '../safety/injury_types_bloc.dart';
import '../safety/injury_types_screen.dart';
import '../safety/observation_detail_bloc.dart';
import '../safety/observation_detail_screen.dart';
import '../safety/observation_form_dialog.dart';
import '../safety/observation_raise_action_dialog.dart';
import '../safety/observations_screen.dart';
import '../safety/safety_api.dart';
import '../safety/safety_incidents_bloc.dart';
import '../safety/safety_observations_bloc.dart';
import 'access_denied_screen.dart';
import 'account_bloc.dart';
import 'auth_gateway.dart';
import 'destinations.dart';
import 'dialog_page.dart';
import 'floor_device_gateway.dart';
import 'not_found_screen.dart';
import 'shell.dart';

abstract final class Routes {
  static const String home = '/';
  static const String signIn = '/sign-in';
  static const String awaitingApproval = '/awaiting-approval';
  static const String approvals = '/approvals';
  static const String accounts = '/accounts';
  static const String assets = '/assets';
  static const String workOrders = '/work-orders';
  static const String requests = '/requests';
  static const String myRequests = '/my-requests';
  static const String downtime = '/downtime';
  static const String pmSchedules = '/pm-schedules';
  static const String meters = '/meters';
  static const String jobPlans = '/job-plans';
  static const String parts = '/parts';
  static const String stores = '/stores';
  static const String directory = '/directory';
  static const String jobRoles = '/job-roles';
  static const String orgUnits = '/org-units';
  static const String skills = '/skills';
  static const String skillCoverage = '/skill-coverage';
  static const String attendance = '/attendance';
  static const String tierBoard = '/tier-board';

  /// The Quality Module's own Destinations (issue #203): the Product catalogue
  /// and the Defect code tree, at their own addresses so each can be linked to
  /// or bookmarked. The Module's later slices — Non-conformances, CAPAs —
  /// arrive as siblings of these, the way `${actions}/:id` sits beside
  /// [actions].
  static const String products = '/products';
  static const String defectCodes = '/defect-codes';
  /// The Non-conformance register, its record form (`/non-conformances/new`),
  /// one record's detail (`/non-conformances/:id`) and the two controls that
  /// change it after it is recorded (`/:id/quantity`, `/:id/update`) — all
  /// addressed, per ADR-0021. `new` cannot collide with the detail route
  /// because it is not an id.
  static const String nonConformances = '/non-conformances';

  /// The Safety Module's own Destinations (issue #226): the incident register,
  /// its record form (`/safety/incidents/record`, the binding design comment
  /// on #223) and one incident's detail (`/safety/incidents/:id`) — all
  /// addressed, per ADR-0019/ADR-0021. `record` cannot collide with the
  /// detail route because it is not an id.
  static const String safetyIncidents = '/safety/incidents';

  /// The Safety Module's two shared catalogues (issue #224): what an injury
  /// was, and where on the body. Filed under `/safety/` beside the incident
  /// register rather than at the Platform root the way `/products` and
  /// `/defect-codes` are — the binding design comment on #223 names both
  /// addresses, and a Module that already owns a path prefix should not
  /// scatter its catalogues outside it.
  static const String injuryTypes = '/safety/injury-types';
  static const String bodyParts = '/safety/body-parts';

  /// The Safety observation register (issue #230): the leading indicator,
  /// worst-first by severity potential. Its record form
  /// (`/safety/observations/record`) and one observation's detail
  /// (`/safety/observations/:id`) — all addressed, per ADR-0019/ADR-0021,
  /// mirroring [safetyIncidents] exactly.
  static const String safetyObservations = '/safety/observations';

  /// The Customer list (issue #214), at its own address so it can be linked to
  /// or bookmarked. Defining and correcting a Customer are dialogs over it
  /// (`CustomerFormDialog.open`), the same shape the Product catalogue's own
  /// write surface takes — a Customer carries three fields, and the list behind
  /// the dialog is the context the correction is made in.
  static const String customers = '/customers';

  /// The customer complaint register (issue #214), with the record form
  /// (`/complaints/new`), one complaint's detail (`/complaints/:id`) and the
  /// three writes a reader makes from it (`/:id/respond`,
  /// `/:id/nonconformance`, `/:id/link`) — all addressed, per ADR-0021.
  static const String complaints = '/complaints';

  /// The Supplier list (issue #215), at its own address so it can be linked to
  /// or bookmarked. Defining and correcting a Supplier are dialogs over it
  /// (`SupplierFormDialog.open`), the same shape the Customer list's write
  /// surface takes — a Supplier carries the same three fields.
  static const String suppliers = '/suppliers';

  /// The supplier NCR register (issue #215), with the record form
  /// (`/supplier-ncrs/new`), one NCR's detail (`/supplier-ncrs/:id`) and the
  /// writes a reader opens from it (`/:id/disposition`, `/:id/nonconformance`,
  /// `/:id/link`) — all addressed, per ADR-0021. Closing an NCR has no address
  /// of its own: there is nothing to fill in, so the detail Screen's own button
  /// dispatches it.
  static const String supplierNcrs = '/supplier-ncrs';

  /// The Actions Module's own Destinations (issue #176): the action log, and
  /// one Action's detail read behind `${actions}/:id`. The raise form is
  /// addressed at `${actions}/new` (ADR-0021), which cannot collide with the
  /// detail route because `new` is not an id.
  static const String actions = '/actions';

  /// The CAPA list (issue #211) — every investigation on the Platform, and the
  /// effectiveness check each one is waiting on. A sibling of the Action log
  /// rather than a child of it: a CAPA has its own id space (`capas`, the
  /// baseline's own table) and its own collection. `/actions/capas` is *two*
  /// segments, which is the same shape as the Action detail route
  /// `/actions/:id` — so in `buildRouter` this list is declared **before** the
  /// Action log, or go_router would take it for an Action whose id is `capas`.
  /// (The CAPA's own detail route needs no such care: `${actions}/capas/:id` is
  /// three segments.) One CAPA's address is unchanged by this ticket.
  static const String capas = '/actions/capas';

  /// One CAPA's report (issue #212) — the whole investigation laid out as an
  /// 8D, printable from the browser. A child address of the CAPA's own
  /// (`/actions/capas/:id/report`) rather than a second collection, and routed
  /// **outside the Shell** so that printing it prints the report rather than
  /// the navigation around it — see `buildRouter`.
  static String capaReport(String capaId) => '$capas/$capaId/report';

  /// The shared floor device's own Screen (issue #77, ADR-0016). Its own
  /// address, deliberately outside the Shell and never offered as a
  /// Destination: a device is not an Account, and this surface must be
  /// reachable without signing in.
  static const String floor = '/floor';

  /// The query parameter on [signIn] carrying the address the caller
  /// originally asked for.
  static const String fromParameter = 'from';
}

/// Whether the signed-in Account holds Quality authority at an Org Unit
/// (ADR-0035) — the client's half of the server's own
/// `canAct({ quality: true })`, read off the same `/me` scope every other
/// per-record permission is (ADR-0027).
///
/// A top-level function rather than a local, because the Screen and each of
/// the four dialogs a holder of the authority may open all ask it, and they
/// are separate widgets. It is read **inside a build** and never hoisted into
/// a route's builder: a value computed once when a route first builds captures
/// the Account state as it was before `/me` answered, which is a Screen that
/// never offers the decision it should. Reading where it is used means the
/// element that shows the control is the element that rebuilds when the answer
/// changes.
bool holdsQualityAuthority(BuildContext context, String orgUnitId) {
  final account = context.watch<AccountBloc>().state;
  return account is AccountApproved &&
      account.account.orgUnitScope.canHoldQualityAt(orgUnitId);
}

/// Whether the signed-in Account holds Safety authority at an Org Unit
/// (issue #225, ADR-0039) — [holdsQualityAuthority]'s exact shape, asked of
/// the independent flag, the client's half of the server's own
/// `canAct({ safety: true })`. Issue #228's severity-change, days and close
/// dialogs each ask this before offering themselves, the same way the four
/// Quality-authority dialogs ask [holdsQualityAuthority] — read **inside a
/// build**, never hoisted into a route's builder, for the same reason.
bool holdsSafetyAuthority(BuildContext context, String orgUnitId) {
  final account = context.watch<AccountBloc>().state;
  return account is AccountApproved &&
      account.account.orgUnitScope.canHoldSafetyAt(orgUnitId);
}

/// Whether the signed-in Account may write a CAPA's 5 Why chains (issue #210) —
/// the client's half of the server's own rule, which is an **or**: edit access
/// at the CAPA's Org Unit, *or* a place on its team.
///
/// The second half is why this reads the Account's own `employeeId`
/// (`app_users.employee_id`, which an Account need not have — an administrator
/// is not necessarily an Employee) and compares it against the team the CAPA
/// carries: the team lead is on the team, and so is every member. An
/// administrator reaches everywhere through the first half, exactly as
/// `canAct` answers for them on the server.
///
/// A top-level function rather than a local, for the reason
/// [holdsQualityAuthority] above is one: the Screen and each of the three
/// dialogs a writer may open ask it, and they are separate widgets — and it is
/// read **inside a build**, never hoisted into a route's builder, so the
/// control appears the moment `/me` answers rather than never.
bool mayEditCapaChains(BuildContext context, Capa capa) {
  final account = context.watch<AccountBloc>().state;
  if (account is! AccountApproved) return false;
  if (account.account.orgUnitScope.canWriteAt(capa.orgUnitId)) return true;
  final employeeId = account.account.employeeId;
  return employeeId != null && capa.team.any((member) => member.employeeId == employeeId);
}

/// Whether this Account **is the team lead's** on the CAPA (issue #211) — the
/// second half of the rule that decides who may record an effectiveness check.
///
/// It reads the Account's own Employee link (`app_users.employee_id`, which an
/// Account need not have: an administrator is not necessarily an Employee)
/// against the lead the CAPA carries. An Account with no Employee is never the
/// team lead; an Account whose Employee is a *member* of the team is not either,
/// and a member is exactly who may record the check.
///
/// A top-level function so the Screen and the address's own refusal ask the
/// same question once, and read **inside a build** for the reason the two
/// helpers above are: the answer arrives with `/me`.
bool isCapaTeamLeadAccount(BuildContext context, Capa capa) {
  final account = context.watch<AccountBloc>().state;
  if (account is! AccountApproved) return false;
  final employeeId = account.account.employeeId;
  if (employeeId == null) return false;
  return capa.teamLead?.employeeId == employeeId;
}

/// Whether this Account may record the CAPA's effectiveness check (issue #211)
/// — the client's half of the server's own two-part gate: **Quality authority
/// at the CAPA's Org Unit**, held by somebody who is **not the team lead**.
///
/// Both halves are read off the same `/me` scope every other per-record
/// permission is (ADR-0027): `canHoldQualityAt` is the authority ADR-0035 puts
/// on a Grant, and the Employee link is what says whose Account this is. An
/// administrator passes the first half everywhere, through the same reach the
/// server's `canAct` gives them.
bool mayRecordCapaEffectiveness(BuildContext context, Capa capa) {
  if (!holdsQualityAuthority(context, capa.orgUnitId)) return false;
  return !isCapaTeamLeadAccount(context, capa);
}

GoRouter buildRouter({required AccountBloc accountBloc, String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: GoRouterRefreshStream(accountBloc.stream),
    redirect: (context, state) => accountRedirect(accountBloc.state, state),
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.awaitingApproval,
        builder: (context, state) {
          final account = context.watch<AccountBloc>().state;
          // Sealed-state type narrowing, not a per-Screen access check: the
          // redirect below has already decided nobody else reaches here.
          return account is AccountAwaitingApproval
              ? AwaitingApprovalScreen(email: account.email)
              : const SizedBox.shrink();
        },
      ),
      // The floor surface (issue #77, ADR-0016). A sibling of the Shell, not a
      // child of it and not an entry in its sidebar: a shared device is not an
      // Account, so this Screen is reached at its own address without signing
      // in. `accountRedirect` returns null for it unconditionally, for the same
      // reason. It builds its own Bloc from the device credential rather than
      // from `AccountBloc`, and its body is the whole Screen — no sidebar, no
      // account footer.
      GoRoute(
        path: Routes.floor,
        builder: (context, state) => BlocProvider<FloorBloc>(
          create: (context) => FloorBloc(
            maintenanceApi: context.read<MaintenanceApi>(),
            floorDeviceGateway: context.read<FloorDeviceGateway>(),
          )..add(const FloorStarted()),
          child: const FloorScreen(),
        ),
      ),
      // The CAPA report (issue #212) — the whole investigation laid out as an
      // 8D at its own address, printable from the browser.
      //
      // **Outside the Shell, deliberately, and it is the ticket's own point.**
      // A `ShellRoute` wraps every child in `PlatformShell`, so a report
      // declared inside the CAPA's own `ShellRoute` below would carry the
      // sidebar, the brand header and the account footer onto every printed
      // page. Sign-in and awaiting-Approval are siblings of the Shell for the
      // same reason, and so is the floor surface; `accountRedirect` is what
      // decides who reaches the address, not the Shell's chrome.
      //
      // A sibling `GoRoute` rather than a child of the CAPA's own detail route,
      // and it could not have been matched by one: `/actions/capas/:id/report`
      // is four segments, and the routes inside the Shell declare no `:id`
      // child that could take it (unlike `/actions/capas`, which the Action
      // detail route *would* take for an Action whose id is `capas` — see the
      // CAPA list's own note below). It is declared here, before the Shell,
      // because that is where the addresses reached without chrome live.
      //
      // No gate of its own either: reading a CAPA is a platform-wide read for
      // every active Account (ADR-0009, and `/api/actions/capas/:id` asks
      // nothing more), so a report that refused a reader would be a second,
      // stricter rule for one record's own Screen.
      GoRoute(
        path: '${Routes.actions}/capas/:id/report',
        builder: (context, state) {
          final account = context.watch<AccountBloc>().state;
          // Sealed-state type narrowing, not a per-Screen access check — the
          // same line the Shell's own builder takes: `accountRedirect` has
          // already decided that nobody but an admitted Account reaches an
          // address like this, and a caller on their way to sign-in must not
          // see a refusal flash first.
          if (account is! AccountApproved) return const SizedBox.shrink();
          final capaId = state.pathParameters['id']!;
          return BlocProvider<CapaDetailBloc>(
            // Keyed on the CAPA this report is of, for the reason the CAPA's
            // own Screen keys its Bloc: go_router reuses a route's page when
            // the route *pattern* matches, so moving from one report to another
            // without a new key would repaint the first investigation's report
            // under the second one's address.
            key: ValueKey<String>('capa-report-$capaId'),
            create: (context) => CapaDetailBloc(
              actionsApi: context.read<ActionsApi>(),
              authGateway: context.read<AuthGateway>(),
            )..add(CapaDetailStarted(capaId)),
            child: CapaReportScreen(capaId: capaId),
          );
        },
      ),
      // Everything an admitted Account can reach sits inside the Shell.
      // Sign-in and awaiting-Approval are siblings of it, not children, so
      // they render outside the sidebar; the not-found Screen comes from
      // `errorBuilder`, which is outside it too.
      ShellRoute(
        builder: (context, state, child) {
          final account = context.watch<AccountBloc>().state;
          // Sealed-state type narrowing, not a per-Screen access check: the
          // redirect below has already decided nobody else reaches here.
          if (account is! AccountApproved) return const SizedBox.shrink();
          return PlatformShell(
            destinations: destinationsFor(role: account.account.role),
            currentLocation: state.uri.path,
            // By address, not by swapping a widget: the browser's history and
            // back button work because navigation is a real route change.
            onDestinationSelected: (destination) => context.go(destination.path),
            account: account.account,
            // Ends the session Supabase issued — the refresh token is
            // revoked server-side and the locally persisted session is
            // cleared, which is what "signing out ends the session" means:
            // a reload after this shows the sign-in screen again, not a
            // restored session. Dispatched through AccountBloc, not called on
            // Supabase directly (issue #38): the Bloc is the only place the
            // session is resolved, so it must also be the only place it ends.
            onSignOut: () => context.read<AccountBloc>().add(const AccountSignOutRequested()),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<HomeBloc>(
                // Scoped to this route, not to the app the way AccountBloc is
                // — the same reasoning every other route-scoped Bloc here
                // already carries (`ApprovalQueueBloc`, `WorkOrdersBloc`):
                // Home is one Screen's own reading of the server, re-read on
                // arrival rather than restored stale.
                create: (context) => HomeBloc(
                  peopleApi: context.read<PeopleApi>(),
                  maintenanceApi: context.read<MaintenanceApi>(),
                  // What is assigned to the caller is read from the action log
                  // (ActionsApi), the same reads its own register makes.
                  actionsApi: context.read<ActionsApi>(),
                  authGateway: context.read<AuthGateway>(),
                  accountRole: account.account.role,
                  accountOrgUnitScope: account.account.orgUnitScope,
                )..add(const HomeStarted()),
                child: HomeScreen(account: account.account),
              );
            },
          ),
          // Offered to every approved Account (AC1) — unlike every other
          // route below, there is no per-Screen role check here at all:
          // ADR-0009 is exactly the decision that the Directory is not a
          // secret, and `destinationsFor` (destinations.dart) already offers
          // it to every role by leaving `roles` unset.
          GoRoute(
            path: Routes.directory,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<DirectoryBloc>(
                create: (context) => DirectoryBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const DirectoryStarted()),
                // The four write routes are `requireAdmin`, not Org-Unit-scoped
                // (ADR-0009) — issue #87 — so this is a role check, the same
                // shape `account.account.role != Roles.admin` already gates
                // the Approvals/Accounts routes below with, just offered
                // in-Screen here rather than as a whole-Screen refusal, since
                // the Directory itself stays open to every role.
                child: DirectoryScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // One Employee's record, reached from a Directory row
          // (`/directory/:id`) or from "My record" (`/directory/me`) — the
          // literal segment `me` is not a real Employee id, but Employee ids
          // are opaque strings to this router either way, so `EmployeeDetail
          // Screen`/`EmployeeDetailBloc` are what tell the two apart (null
          // employeeId means "my own record"), the same trick directory-
          // routes.js's own GET /employees/me plays against GET
          // /employees/:id on the server.
          GoRoute(
            path: '${Routes.directory}/:id',
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              final rawId = state.pathParameters['id'];
              final employeeId = rawId == null || rawId == 'me' ? null : rawId;
              return BlocProvider<EmployeeDetailBloc>(
                create: (context) => EmployeeDetailBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(EmployeeDetailRequested(employeeId: employeeId)),
                child: EmployeeDetailScreen(
                  employeeId: employeeId,
                  isAdmin: account.account.role == Roles.admin,
                  // Not a role check (issue #88, ADR-0010): the assign route
                  // sits behind write scope on the destination Org Unit, so
                  // this offers the action to any caller who can write
                  // *somewhere* — the same coarse signal
                  // `Routes.workOrders`'s own `canAssignWorkOrder` already
                  // reads off `orgUnitScope` below.
                  canAssign: account.account.orgUnitScope.canWriteSomewhere,
                ),
              );
            },
          ),
          // The Attendance picker (issue #249) — chooses an Org Unit and a
          // production day, then opens one of that day's shift instances'
          // sheets. Offered to every approved Account, the same openness
          // `Routes.directory`/`Routes.jobRoles` above already have: reading
          // a sheet needs only visibility of the Site (issue #249's own
          // criterion), which the server decides per shift instance, so a
          // role check here would gate a door the route itself opens wider.
          GoRoute(
            path: Routes.attendance,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return const AttendancePickerScreen();
            },
          ),
          // The shift's attendance sheet itself (issue #249), reached from
          // the picker above or linked to directly. [canRecord] is the same
          // coarse "can write somewhere" signal `Routes.directory`'s own
          // `canAssign` reads off `orgUnitScope` just above — the server is
          // the real per-Org-Unit gate either way (403
          // `OUTSIDE_GRANTED_ORG_UNITS`).
          GoRoute(
            path: '${Routes.attendance}/:shiftInstanceId',
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              final shiftInstanceId = state.pathParameters['shiftInstanceId']!;
              return BlocProvider<AttendanceSheetBloc>(
                create: (context) => AttendanceSheetBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(AttendanceSheetRequested(shiftInstanceId)),
                child: AttendanceSheetScreen(
                  shiftInstanceId: shiftInstanceId,
                  canRecord: account.account.orgUnitScope.canWriteSomewhere,
                ),
              );
            },
          ),
          // The job role catalogue (issue #88, ADR-0005's shared catalogue).
          // Offered to every approved Account, unlike Approvals/Assets/Work
          // orders/Accounts below: `GET /job-roles` carries no admin or scope
          // check at all (job-role-routes.js's own header), the same
          // openness `Routes.directory` above already has and for the same
          // reason (ADR-0009's "a plant directory is not a secret" applies
          // just as well to reference data everyone needs to read). Only the
          // write affordances inside `JobRolesScreen` are gated to `isAdmin`.
          GoRoute(
            path: Routes.jobRoles,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<JobRolesBloc>(
                create: (context) => JobRolesBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const JobRolesStarted()),
                child: JobRolesScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // Sites and the Org Unit tree (issue #90). Offered to every approved
          // Account, the same openness `Routes.jobRoles`/`Routes.skills` above
          // already have: neither `GET /sites` nor `GET .../org-units` carries
          // a role check of its own (ADR-0009). Only the write affordances
          // inside `OrgUnitsScreen` are gated — creating a root Org Unit to
          // `isAdmin` (ADR-0008), everything else to the server's own scope
          // check. Two Blocs, deliberately: `OrgUnitPickerBloc` for the tree
          // itself, unchanged from what the Approval flow's own picker already
          // uses; `OrgUnitAdminBloc` for every write and the search/import
          // queries that Bloc was never built to hold (`org_units_screen.dart`'s
          // own header has the fuller reasoning).
          GoRoute(
            path: Routes.orgUnits,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return MultiBlocProvider(
                providers: [
                  BlocProvider<OrgUnitPickerBloc>(
                    create: (context) => OrgUnitPickerBloc(
                      peopleApi: context.read<PeopleApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(const OrgUnitPickerStarted()),
                  ),
                  BlocProvider<OrgUnitAdminBloc>(
                    create: (context) => OrgUnitAdminBloc(
                      peopleApi: context.read<PeopleApi>(),
                      authGateway: context.read<AuthGateway>(),
                    ),
                  ),
                ],
                child: OrgUnitsScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // The skill catalogue (issue #89). Offered to every approved
          // Account, the same openness `Routes.jobRoles` above already has
          // and for the same reason: `GET /skills` carries no admin or scope
          // check of its own (skill-routes.js's own header). Only the write
          // affordances inside `SkillsScreen` are gated to `isAdmin`.
          GoRoute(
            path: Routes.skills,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<SkillsBloc>(
                create: (context) => SkillsBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SkillsStarted()),
                child: SkillsScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // The Quality Module's two catalogues (issue #203): the Products the
          // plant makes and the Defect codes a Non-conformance is recorded
          // against, both shared by every Site (ADR-0005). Offered to every
          // approved Account, the same openness `Routes.jobRoles` and
          // `Routes.skills` above already have and for the same reason: neither
          // read carries an admin or scope check of its own
          // (product-routes.js/defect-code-routes.js). Only the write
          // affordances inside each Screen are gated to `isAdmin`.
          GoRoute(
            path: Routes.products,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<ProductsBloc>(
                create: (context) => ProductsBloc(
                  qualityApi: context.read<QualityApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const ProductsStarted()),
                child: ProductsScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          GoRoute(
            path: Routes.defectCodes,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<DefectCodesBloc>(
                create: (context) => DefectCodesBloc(
                  qualityApi: context.read<QualityApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const DefectCodesStarted()),
                child: DefectCodesScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // The Customer list and the customer complaint register (issue #214),
          // the Module's two remaining Destinations. The list is a catalogue
          // read like the two above it (any approved Account, only its writes
          // the administrator's), so it takes the same shape; the complaint
          // register needs a `ShellRoute` of its own for the reason the
          // Non-conformance register does — `ComplaintsBloc` is created exactly
          // once and shared by the register, the record form's own address and
          // the detail Screen.
          //
          // Both guards are the whole Module rather than a role set: the
          // Customer list is a shared catalogue (ADR-0005) and the register is
          // a Site-wide read for every admitted Account, while both write
          // surfaces are gated by the server on the Grant that reaches the
          // record's own Org Unit (and, for a Customer, on the administrator
          // role). An operator is offered both Destinations exactly as a
          // manager is.
          GoRoute(
            path: Routes.customers,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<CustomersBloc>(
                create: (context) => CustomersBloc(
                  qualityApi: context.read<QualityApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const CustomersStarted()),
                child: CustomersScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<ComplaintsBloc>(
                create: (context) => ComplaintsBloc(
                  qualityApi: context.read<QualityApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const ComplaintsStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.complaints,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const ComplaintsScreen();
                },
                routes: [
                  // `/complaints/new` — the record form, addressed rather than
                  // popped (ADR-0021), and `new` cannot collide with the detail
                  // route below because it is not an id.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final register = context.watch<ComplaintsBloc>().state;
                          final siteId =
                              register is ComplaintsLoaded ? register.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: ComplaintsScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          // The chooser inside the form browses People's tree
                          // through the same Bloc the Non-conformance form uses,
                          // scoped to this dialog and opened on the Site on
                          // screen.
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: ComplaintFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/complaints/:id` and its three addresses — a `ShellRoute` of
              // its own so `ComplaintDetailBloc` is created exactly once and
              // shared by the Screen and the three dialogs beside it, and
              // **keyed on the id in the address**: go_router reuses a route's
              // page when the *pattern* matches, so moving from one complaint
              // to another would otherwise leave this Bloc — and the Screen
              // reading it — holding the record before (issue #183's own bug).
              ShellRoute(
                builder: (context, state, child) {
                  final complaintId = state.pathParameters['id']!;
                  return BlocProvider<ComplaintDetailBloc>(
                    key: ValueKey<String>(complaintId),
                    create: (context) => ComplaintDetailBloc(
                      qualityApi: context.read<QualityApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(ComplaintDetailStarted(complaintId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it: a relative `:id`
                    // here resolves against the Module shell and matches
                    // `/:id`, not `/complaints/:id`.
                    path: '${Routes.complaints}/:id',
                    builder: (context, state) => ComplaintDetailScreen(
                      complaintId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/complaints/:id/respond` — closing it with the
                      // response the customer was given.
                      GoRoute(
                        path: 'respond',
                        pageBuilder: (context, state) {
                          final detail = context.watch<ComplaintDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! ComplaintDetailLoaded) {
                                return const AlertDialog(
                                  key: ComplaintRespondDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return ComplaintRespondDialog(complaint: detail.complaint);
                            },
                          );
                        },
                      ),
                      // `/complaints/:id/nonconformance` — recording the
                      // Non-conformance that controls the complained-of product.
                      GoRoute(
                        path: 'nonconformance',
                        pageBuilder: (context, state) {
                          final detail = context.watch<ComplaintDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! ComplaintDetailLoaded) {
                                return const AlertDialog(
                                  key: ComplaintNonconformanceDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return ComplaintNonconformanceDialog(complaint: detail.complaint);
                            },
                          );
                        },
                      ),
                      // `/complaints/:id/link` — linking one that exists.
                      GoRoute(
                        path: 'link',
                        pageBuilder: (context, state) {
                          final detail = context.watch<ComplaintDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! ComplaintDetailLoaded) {
                                return const AlertDialog(
                                  key: ComplaintLinkDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return ComplaintLinkDialog(complaint: detail.complaint);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // The Supplier list and the supplier NCR register (issue #215), the
          // Module's two remaining Destinations and the same pair the Customer
          // slice above files. The list is a catalogue read like the two above
          // it (any approved Account, only its writes the administrator's), so
          // it takes the same shape; the NCR register needs a `ShellRoute` of
          // its own for the reason the complaint register does —
          // `SupplierNcrsBloc` is created exactly once and shared by the
          // register, the record form's own address and the detail Screen.
          GoRoute(
            path: Routes.suppliers,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<SuppliersBloc>(
                create: (context) => SuppliersBloc(
                  qualityApi: context.read<QualityApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SuppliersStarted()),
                child: SuppliersScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<SupplierNcrsBloc>(
                create: (context) => SupplierNcrsBloc(
                  qualityApi: context.read<QualityApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SupplierNcrsStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.supplierNcrs,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const SupplierNcrsScreen();
                },
                routes: [
                  // `/supplier-ncrs/new` — the record form, addressed rather
                  // than popped (ADR-0021), and `new` cannot collide with the
                  // detail route below because it is not an id.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final register = context.watch<SupplierNcrsBloc>().state;
                          final siteId =
                              register is SupplierNcrsLoaded ? register.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: SupplierNcrsScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          // The chooser inside the form browses People's tree
                          // through the same Bloc the complaint form uses,
                          // scoped to this dialog and opened on the Site on
                          // screen.
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: SupplierNcrFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/supplier-ncrs/:id` and its four addresses — a `ShellRoute` of
              // its own so `SupplierNcrDetailBloc` is created exactly once and
              // shared by the Screen and the four dialogs beside it, and
              // **keyed on the id in the address**: go_router reuses a route's
              // page when the *pattern* matches, so moving from one NCR to
              // another would otherwise leave this Bloc — and the Screen
              // reading it — holding the record before (issue #183's own bug).
              ShellRoute(
                builder: (context, state, child) {
                  final supplierNcrId = state.pathParameters['id']!;
                  return BlocProvider<SupplierNcrDetailBloc>(
                    key: ValueKey<String>(supplierNcrId),
                    create: (context) => SupplierNcrDetailBloc(
                      qualityApi: context.read<QualityApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(SupplierNcrDetailStarted(supplierNcrId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it: a relative `:id`
                    // here resolves against the Module shell and matches
                    // `/:id`, not `/supplier-ncrs/:id`.
                    path: '${Routes.supplierNcrs}/:id',
                    builder: (context, state) => SupplierNcrDetailScreen(
                      supplierNcrId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/supplier-ncrs/:id/disposition` — the Supplier's
                      // disposition and what was recovered.
                      GoRoute(
                        path: 'disposition',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SupplierNcrDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SupplierNcrDetailLoaded) {
                                return const AlertDialog(
                                  key: SupplierNcrDispositionDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SupplierNcrDispositionDialog(
                                supplierNcr: detail.supplierNcr,
                              );
                            },
                          );
                        },
                      ),
                      // `/supplier-ncrs/:id/nonconformance` — recording the
                      // Non-conformance that controls the received lot.
                      GoRoute(
                        path: 'nonconformance',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SupplierNcrDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SupplierNcrDetailLoaded) {
                                return const AlertDialog(
                                  key: SupplierNcrNonconformanceDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SupplierNcrNonconformanceDialog(
                                supplierNcr: detail.supplierNcr,
                              );
                            },
                          );
                        },
                      ),
                      // `/supplier-ncrs/:id/link` — linking one that exists.
                      GoRoute(
                        path: 'link',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SupplierNcrDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SupplierNcrDetailLoaded) {
                                return const AlertDialog(
                                  key: SupplierNcrLinkDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SupplierNcrLinkDialog(
                                supplierNcr: detail.supplierNcr,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Non-conformances (issue #205) — a `ShellRoute` of its own, for the
          // same reason Work orders and Actions have one: `NonconformancesBloc`
          // is created exactly once and shared by the register and the record
          // form's own address below (a child `GoRoute`'s page is a *sibling*
          // of its parent's, so a Bloc provided inside the register's builder
          // would not be visible to the form).
          //
          // The guard is the whole Module rather than a role set: the register
          // is a Site-wide read for every admitted Account — "anyone who can
          // see the Site can find and read it" is the ticket's own sentence —
          // and recording needs only a write Grant reaching the Org Unit the
          // product was found at. The server is the real gate on both. An
          // operator is offered this Destination exactly as a manager is.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<NonconformancesBloc>(
                create: (context) => NonconformancesBloc(
                  qualityApi: context.read<QualityApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const NonconformancesStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.nonConformances,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const NonconformancesScreen();
                },
                routes: [
                  // `/non-conformances/new` — the record form, addressed
                  // rather than popped (ADR-0021): a refresh lands on the
                  // register with the form open, and `new` cannot collide with
                  // the detail route below because it is not an id.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final register = context.watch<NonconformancesBloc>().state;
                          final siteId =
                              register is NonconformancesLoaded ? register.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: NonconformancesScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          // The chooser inside the form browses People's tree
                          // through the same Bloc the Asset form uses, scoped
                          // to this dialog and opened on the Site on screen.
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: NonconformanceFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/non-conformances/:id` and its own two addresses — a
              // `ShellRoute` of its own so `NonconformanceDetailBloc` is created
              // exactly once and shared by the Screen and the two dialogs
              // beside it, and **keyed on the id in the address**: go_router
              // reuses a route's page when the *pattern* matches, so moving
              // from one Non-conformance to another would otherwise leave this
              // Bloc — and the Screen reading it — holding the record before
              // (issue #183's own bug, fixed the same way for Actions).
              ShellRoute(
                builder: (context, state, child) {
                  final nonconformanceId = state.pathParameters['id']!;
                  return BlocProvider<NonconformanceDetailBloc>(
                    key: ValueKey<String>(nonconformanceId),
                    create: (context) => NonconformanceDetailBloc(
                      qualityApi: context.read<QualityApi>(),
                      // Raising a Concern from this record and linking it to
                      // one are writes to the action log (issue #208), so this
                      // Bloc holds the Actions Module's client too — reached
                      // through its own entry point.
                      actionsApi: context.read<ActionsApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(NonconformanceDetailStarted(nonconformanceId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it: a relative `:id`
                    // here resolves against the Module shell and matches
                    // `/:id`, not `/non-conformances/:id`.
                    path: '${Routes.nonConformances}/:id',
                    builder: (context, state) => NonconformanceDetailScreen(
                      nonconformanceId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/non-conformances/:id/quantity` — increasing the
                      // affected quantity. Nested under the record's own route
                      // rather than sitting beside it, the same choice the
                      // Action phase dialog makes: a sibling address would pop
                      // the caller back to the register with the record they
                      // were reading gone.
                      GoRoute(
                        path: 'quantity',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceQuantityDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceQuantityDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/update` — raising the severity
                      // and recording the immediate containment that makes the
                      // record contained.
                      GoRoute(
                        path: 'update',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceUpdateDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceUpdateDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/disposition` — dealing with
                      // some of the product (issue #206): scrap, rework with
                      // its minutes, or back to the supplier.
                      GoRoute(
                        path: 'disposition',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceDispositionDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceDispositionDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/concession` — accepting the
                      // product as it is, which needs Quality authority.
                      GoRoute(
                        path: 'concession',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceConcessionDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              // The dialog is reachable by address, so it says
                              // why rather than rendering a control the caller
                              // may not use — the server refuses it either way
                              // (ADR-0021's three outcomes). The authority
                              // itself is read inside the dialog, where it is
                              // also read in a build rather than frozen here.
                              return NonconformanceConcessionDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/lower-severity` — the
                      // correction issue #205 refused a recorder.
                      GoRoute(
                        path: 'lower-severity',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceLowerSeverityDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceLowerSeverityDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/reopen` — putting a closed
                      // record back on the log, with a note.
                      GoRoute(
                        path: 'reopen',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceReopenDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceReopenDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/cancel` — cancelling a record
                      // made in error, with a note.
                      GoRoute(
                        path: 'cancel',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceCancelDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceCancelDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/raise-concern` — raising a
                      // Concern from this record in the action log (issue
                      // #208). Addressed for the same reason every other
                      // transition is (ADR-0021): a refresh lands on the
                      // record with the form open, and the write itself is the
                      // Actions Module's route reached through its own client
                      // entry point.
                      GoRoute(
                        path: 'raise-concern',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceRaiseConcernDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceRaiseConcernDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                      // `/non-conformances/:id/link-concern` — linking this
                      // record to a Concern that already exists, so one
                      // problem answering several occurrences stays one
                      // Concern (issue #208).
                      GoRoute(
                        path: 'link-concern',
                        pageBuilder: (context, state) {
                          final detail = context.watch<NonconformanceDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! NonconformanceDetailLoaded) {
                                return const AlertDialog(
                                  key: NonconformanceLinkConcernDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return NonconformanceLinkConcernDialog(
                                nonconformance: detail.nonconformance,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Safety incidents (issue #226) — a `ShellRoute` of its own, for the
          // same reason Non-conformances has one: `SafetyIncidentsBloc` is
          // created exactly once and shared by the register and the record
          // form's own address below (a child `GoRoute`'s page is a *sibling*
          // of its parent's, so a Bloc provided inside the register's builder
          // would not be visible to the form).
          //
          // The guard is the whole Module rather than a role set: the register
          // is a Site-wide read for every admitted Account, and recording
          // needs only a write Grant reaching the Org Unit it occurred at, or
          // the administrator role — both of which the server decides. An
          // operator is offered this Destination exactly as a manager is.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<SafetyIncidentsBloc>(
                create: (context) => SafetyIncidentsBloc(
                  safetyApi: context.read<SafetyApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SafetyIncidentsStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.safetyIncidents,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const SafetyIncidentsScreen();
                },
                routes: [
                  // `/safety/incidents/record` — the record form, addressed
                  // rather than popped (ADR-0021, the binding design comment
                  // on #223): a refresh lands on the register with the form
                  // open, and `record` cannot collide with the detail route
                  // below because it is not an id.
                  GoRoute(
                    path: 'record',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final register = context.watch<SafetyIncidentsBloc>().state;
                          final siteId =
                              register is SafetyIncidentsLoaded ? register.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: SafetyIncidentsScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          // The chooser inside the form browses People's tree
                          // through the same Bloc the Non-conformance form
                          // uses, scoped to this dialog and opened on the
                          // Site on screen.
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: SafetyIncidentFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/safety/incidents/:id` — a `ShellRoute` of its own so
              // `SafetyIncidentDetailBloc` is created exactly once, and
              // **keyed on the id in the address**: go_router reuses a
              // route's page when the *pattern* matches, so moving from one
              // incident to another would otherwise leave this Bloc — and the
              // Screen reading it — holding the record before (issue #183's
              // own bug, fixed the same way for Non-conformances).
              ShellRoute(
                builder: (context, state, child) {
                  final incidentId = state.pathParameters['id']!;
                  return BlocProvider<SafetyIncidentDetailBloc>(
                    key: ValueKey<String>(incidentId),
                    create: (context) => SafetyIncidentDetailBloc(
                      safetyApi: context.read<SafetyApi>(),
                      // Raising a Concern from this incident is a write to
                      // the action log (issue #229), so this Bloc holds the
                      // Actions Module's client too — reached through its
                      // own entry point.
                      actionsApi: context.read<ActionsApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(SafetyIncidentDetailStarted(incidentId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it: a relative `:id`
                    // here resolves against the Module shell and matches
                    // `/:id`, not `/safety/incidents/:id`.
                    path: '${Routes.safetyIncidents}/:id',
                    builder: (context, state) => SafetyIncidentDetailScreen(
                      incidentId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/safety/incidents/:id/due-date` — setting or
                      // changing the investigation due date (issue #228).
                      // Needs only an edit Grant, so it is always offered.
                      GoRoute(
                        path: 'due-date',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentDueDateDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentDueDateDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/status` — the ordinary ladder
                      // move: open -> investigating -> actions_pending (issue
                      // #228). Closing is its own address below.
                      GoRoute(
                        path: 'status',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentStatusDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentStatusDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/classify` — the injury
                      // classification (issue #224, ADR-0037): who was hurt,
                      // what the injury was, where on the body. Needs Safety
                      // authority, asked inside the dialog where it is read in
                      // a build rather than frozen here.
                      GoRoute(
                        path: 'classify',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentClassifyDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentClassifyDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/severity` — correcting the
                      // severity level (issue #228, #223 decision 5). Needs
                      // Safety authority, asked inside the dialog where it is
                      // also read in a build rather than frozen here.
                      GoRoute(
                        path: 'severity',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentSeverityDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentSeverityDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/days` — recording the days the
                      // injury cost (issue #228). Needs Safety authority.
                      GoRoute(
                        path: 'days',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentDaysDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentDaysDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/close` — closing (issue #228,
                      // #223 decision 4). Needs Safety authority, a note, and
                      // the days settled above the no-injury rung; never
                      // refused for an open Concern.
                      GoRoute(
                        path: 'close',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentCloseDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentCloseDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                      // `/safety/incidents/:id/raise-concern` — raising a
                      // Concern from this incident in the action log (issue
                      // #229). Addressed for the same reason every other
                      // transition is (ADR-0021): a refresh lands on the
                      // record with the form open, and the write itself is
                      // the Actions Module's route reached through its own
                      // client entry point. Anyone who can see the Site may
                      // raise one — a Grant is not asked here or by the
                      // server (#198's Concern rule).
                      GoRoute(
                        path: 'raise-concern',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyIncidentDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyIncidentDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyIncidentRaiseConcernDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyIncidentRaiseConcernDialog(incident: detail.incident);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Safety observations (issue #230) — a `ShellRoute` of its own, the
          // same reason the incident register above has one:
          // `SafetyObservationsBloc` is created exactly once and shared by
          // the register and the record form's own address below.
          //
          // The guard is the whole Module rather than a role set, the same
          // reasoning the incident register's own comment gives: the register
          // is a Site-wide read for every admitted Account, and recording
          // needs only a write Grant reaching the Org Unit it was observed
          // at, or the administrator role — both of which the server
          // decides.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<SafetyObservationsBloc>(
                create: (context) => SafetyObservationsBloc(
                  safetyApi: context.read<SafetyApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SafetyObservationsStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.safetyObservations,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const SafetyObservationsScreen();
                },
                routes: [
                  // `/safety/observations/record` — the record form,
                  // addressed rather than popped (ADR-0021), mirroring
                  // `/safety/incidents/record` exactly.
                  GoRoute(
                    path: 'record',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final register = context.watch<SafetyObservationsBloc>().state;
                          final siteId =
                              register is SafetyObservationsLoaded ? register.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: SafetyObservationsScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: SafetyObservationFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/safety/observations/:id` — a `ShellRoute` of its own so
              // `SafetyObservationDetailBloc` is created exactly once and
              // **keyed on the id in the address**, the same fix issue #183
              // gave the incident detail route above.
              ShellRoute(
                builder: (context, state, child) {
                  final observationId = state.pathParameters['id']!;
                  return BlocProvider<SafetyObservationDetailBloc>(
                    key: ValueKey<String>(observationId),
                    create: (context) => SafetyObservationDetailBloc(
                      safetyApi: context.read<SafetyApi>(),
                      // Raising an Action from this observation is a write to
                      // the action log (issue #231), so this Bloc holds the
                      // Actions Module's client too — reached through its own
                      // entry point.
                      actionsApi: context.read<ActionsApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(SafetyObservationDetailStarted(observationId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it — the same
                    // reasoning the incident detail route above gives.
                    path: '${Routes.safetyObservations}/:id',
                    builder: (context, state) => SafetyObservationDetailScreen(
                      observationId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/safety/observations/:id/raise-action` — raising an
                      // Action from this observation in the action log (issue
                      // #231). Addressed for the same reason every other
                      // transition is (ADR-0021): a refresh lands on the
                      // record with the form open, and the write itself is
                      // the Actions Module's route reached through its own
                      // client entry point. Anyone who can see the Site may
                      // raise one — a Grant is not asked here or by the
                      // server (#231's own acceptance criterion).
                      GoRoute(
                        path: 'raise-action',
                        pageBuilder: (context, state) {
                          final detail = context.watch<SafetyObservationDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              if (detail is! SafetyObservationDetailLoaded) {
                                return const AlertDialog(
                                  key: SafetyObservationRaiseActionDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              return SafetyObservationRaiseActionDialog(
                                observation: detail.observation,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // The Safety Module's two catalogues (issue #224): the Injury types
          // and Body parts an injury classification draws on, both shared by
          // every Site (ADR-0005). Not role-gated here, the same shape
          // `Routes.products` and `Routes.defectCodes` take: neither read
          // carries an admin or scope check of its own
          // (injury-type-routes.js/body-part-routes.js), so a Screen-level
          // refusal would close a door the route itself opens. What IS
          // administrator-only is the **Destination** (the binding design
          // comment on #223 — "the last two filter away for a
          // non-administrator"), and the write affordances inside each Screen.
          GoRoute(
            path: Routes.injuryTypes,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<InjuryTypesBloc>(
                create: (context) => InjuryTypesBloc(
                  safetyApi: context.read<SafetyApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const InjuryTypesStarted()),
                child: InjuryTypesScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          GoRoute(
            path: Routes.bodyParts,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<BodyPartsBloc>(
                create: (context) => BodyPartsBloc(
                  safetyApi: context.read<SafetyApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const BodyPartsStarted()),
                child: BodyPartsScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          // A Site's skill coverage (issue #89, AC6) — administrator only,
          // and deliberately a per-Screen access check here rather than only
          // an omission from the sidebar: `GET .../skill-coverage` is
          // narrower than every other Site-shaped read in this Module
          // (skill-routes.js's own header), the same reasoning
          // `Routes.approvals`/`Routes.accounts` below already carry into
          // this router.
          GoRoute(
            path: Routes.skillCoverage,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved || account.account.role != Roles.admin) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<SkillCoverageBloc>(
                create: (context) => SkillCoverageBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const SkillCoverageStarted()),
                child: const SkillCoverageScreen(),
              );
            },
          ),
          // The tier board (issue #76). Offered to every approved Account —
          // unlike the Maintenance and administrator routes around it, there is
          // no per-Screen role check here at all: the board's read is Site-wide
          // and carries no Grant filter (ADR-0009), and `destinationsFor`
          // already offers it to every role by leaving `roles` unset.
          GoRoute(
            path: Routes.tierBoard,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<TierBoardBloc>(
                create: (context) => TierBoardBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const TierBoardStarted()),
                child: const TierBoardScreen(),
              );
            },
          ),
          // The CAPA list (issue #211) — every investigation on the Platform,
          // with the effectiveness check each one is waiting on. A `ShellRoute`
          // of its own so `CapasBloc` is created once and shared by the list and
          // by the Org Unit filter dialog over it.
          //
          // **Declared before the Actions `ShellRoute` below, and that ordering
          // is load-bearing.** go_router matches in declaration order, and
          // `/actions/capas` is the same two segments as `/actions/:id` — so a
          // list declared after the log would be taken for an Action whose id is
          // `capas` and read `/api/actions/capas` as one Action's detail. The
          // CAPA's own detail route needs no such care: `/actions/capas/:id` is
          // three segments, and the Action detail route has no `:id` child that
          // could match it.
          //
          // Offered to every approved Account, like the log it sits beside: a
          // CAPA list is a platform-wide read (ADR-0009), and the one gate in
          // this slice that is per-record — who may record an effectiveness
          // check — is asked on the check's own address, inside the dialog.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<CapasBloc>(
                create: (context) => CapasBloc(
                  actionsApi: context.read<ActionsApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const CapasStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.capas,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const CapasScreen();
                },
              ),
            ],
          ),
          // Actions (issue #176) — a `ShellRoute` of its own, for the same
          // reason Work orders has one: `ActionsBloc` is created exactly once
          // and shared by the register and the raise form's own address below
          // (a child `GoRoute`'s page is a *sibling* of its parent's, so a Bloc
          // provided inside the register's builder would not be visible to it).
          //
          // The guard is the whole Module rather than a role set: the log is a
          // Site-wide read for every admitted Account, and raising needs only a
          // read Grant reaching the Org Unit a concern is about (ADR-0032). An
          // operator is offered this Destination exactly as a manager is.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const AccessDeniedScreen();
              return BlocProvider<ActionsBloc>(
                create: (context) => ActionsBloc(
                  actionsApi: context.read<ActionsApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const ActionsStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.actions,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return const ActionsScreen();
                },
                routes: [
                  // `/actions/new` — the raise form, addressed rather than
                  // popped (ADR-0021): a refresh lands on the register with the
                  // form open, and `new` cannot collide with the detail route
                  // below because it is not an id.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          final actionsState = context.watch<ActionsBloc>().state;
                          final siteId =
                              actionsState is ActionsLoaded ? actionsState.siteId : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: ActionsScreen.formLoadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          // The chooser inside the form browses People's tree
                          // through the same Bloc the Asset form uses, scoped to
                          // this dialog and opened on the Site on screen.
                          return BlocProvider<OrgUnitPickerBloc>(
                            create: (context) => OrgUnitPickerBloc(
                              peopleApi: context.read<PeopleApi>(),
                              authGateway: context.read<AuthGateway>(),
                              initialSiteId: siteId,
                            )..add(const OrgUnitPickerStarted()),
                            child: ActionFormDialog(siteId: siteId),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              // `/actions/:id` and its own transition address — a
              // `ShellRoute` of its own so `ActionDetailBloc` is created
              // exactly once and shared by the Screen and the phase dialog
              // beside it (a child `GoRoute`'s page is a *sibling* of its
              // parent's, so a Bloc provided inside the detail route's
              // builder would not be visible to the dialog).
              ShellRoute(
                builder: (context, state, child) {
                  final actionId = state.pathParameters['id']!;
                  return BlocProvider<ActionDetailBloc>(
                    // Keyed by the Action in the address, and that is the whole
                    // point: go_router reuses a route's page when the *pattern*
                    // matches, so moving from one Action to another — a Concern
                    // to a measure of it, most of all — updated the page in
                    // place and left this Bloc (and the Screen reading it)
                    // holding the Action before. Tapping a measure therefore
                    // looked like nothing happened, which is exactly what the
                    // deployed stack's reader found (issue #183). A new key is
                    // a new bloc, a new Screen State, and a read of the Action
                    // the address actually names.
                    key: ValueKey<String>(actionId),
                    create: (context) => ActionDetailBloc(
                      actionsApi: context.read<ActionsApi>(),
                      authGateway: context.read<AuthGateway>(),
                    )..add(ActionDetailStarted(actionId)),
                    child: child,
                  );
                },
                routes: [
                  GoRoute(
                    // Absolute, because this route is a *sibling* of the
                    // register's rather than a child of it (see the note
                    // above): a relative `:id` here resolves against the Module
                    // shell and matches `/:id`, not `/actions/:id`.
                    path: '${Routes.actions}/:id',
                    builder: (context, state) => ActionDetailScreen(
                      actionId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // `/actions/:id/phases/:phase/complete` — completing
                      // the open phase, addressed rather than popped
                      // (ADR-0021), and **nested under the Action's own
                      // route** rather than sitting beside it as the Work
                      // orders' transition dialogs do. That is a deliberate
                      // difference: those dialogs belong to the *list*,
                      // which stays on screen beneath them, while this one
                      // belongs to one Action's detail read — a sibling
                      // address would pop the caller back to the register
                      // with the Action they were reading gone. The host
                      // refuses the address when the Action is no longer
                      // waiting on the phase it names, which is the
                      // client's half of the server's own 409.
                      GoRoute(
                        path: 'phases/:phase/complete',
                        pageBuilder: (context, state) => DialogPage<void>(
                          key: state.pageKey,
                          builder: (dialogContext) => ActionPhaseCompleteDialogHost(
                            phase: state.pathParameters['phase']!,
                          ),
                        ),
                      ),
                      // `/actions/:id/measures/:measureType/new` — raising
                      // a measure against this Concern (issue #178). Its
                      // kind comes off the address and is checked against
                      // the three the server accepts, so a mistyped one is
                      // refused by name rather than sent to be refused.
                      // `/actions/:id/escalate` — handing it up (issue
                      // #180), addressed for the same reasons the other
                      // two dialogs are.
                      GoRoute(
                        path: 'escalate',
                        pageBuilder: (context, state) => DialogPage<void>(
                          key: state.pageKey,
                          builder: (dialogContext) => const ActionEscalateDialogHost(),
                        ),
                      ),
                      // `/actions/:id/capa` — opening a CAPA on this Concern
                      // (issue #209, ADR-0034). Nested under the Action's own
                      // route for the same reason its cancel and phase dialogs
                      // are: this belongs to one Concern's detail read, and a
                      // sibling address would pop the caller back to the
                      // register with the Concern they were reading gone. The
                      // dialog reads the Concern off the Bloc and collects the
                      // team and the problem description; the authority the act
                      // needs is read inside it, in a build.
                      GoRoute(
                        path: 'capa',
                        pageBuilder: (context, state) => DialogPage<void>(
                          key: state.pageKey,
                          builder: (dialogContext) {
                            final current = context.watch<ActionDetailBloc>().state;
                            if (current is! ActionDetailLoaded) {
                              return const AlertDialog(
                                key: OpenCapaDialog.loadingKey,
                                content: SizedBox(
                                  height: 80,
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                              );
                            }
                            return OpenCapaDialog(concern: current.action);
                          },
                        ),
                      ),
                      // `/actions/:id/cancel` — calling it off (issue
                      // #179), addressed rather than popped and nested
                      // under the Action for the same reason the phase
                      // dialog is.
                      GoRoute(
                        path: 'cancel',
                        pageBuilder: (context, state) => DialogPage<void>(
                          key: state.pageKey,
                          builder: (dialogContext) => const ActionCancelDialogHost(),
                        ),
                      ),
                      // `/actions/:id/nonconformances/:nonconformanceId/unlink`
                      // — taking an occurrence back out of this Concern (issue
                      // #208). Addressed for the same reason the other three
                      // dialogs are, and it names *both* ends of the link it
                      // is about, so the address is the whole request.
                      GoRoute(
                        path: 'nonconformances/:nonconformanceId/unlink',
                        pageBuilder: (context, state) => DialogPage<void>(
                          key: state.pageKey,
                          builder: (dialogContext) => ActionUnlinkNonconformanceDialogHost(
                            nonconformanceId: state.pathParameters['nonconformanceId']!,
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'measures/:measureType/new',
                        pageBuilder: (context, state) {
                          final detail = context.watch<ActionDetailBloc>().state;
                          return DialogPage<void>(
                            key: state.pageKey,
                            builder: (dialogContext) {
                              final current = context.watch<ActionDetailBloc>().state;
                              if (current is! ActionDetailLoaded || detail is! ActionDetailLoaded) {
                                return const AlertDialog(
                                  key: ActionMeasureDialog.loadingKey,
                                  content: SizedBox(
                                    height: 80,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                );
                              }
                              final measureType = state.pathParameters['measureType']!;
                              if (!actionMeasureTypeOrder.contains(measureType)) {
                                return AlertDialog(
                                  key: ActionMeasureDialog.unknownKindKey,
                                  title: const Text('That is not a measure'),
                                  content: const Text(
                                    'A measure is a containment, a countermeasure or a '
                                    'preventive action.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => context.pop(),
                                      child: const Text('Back to the Action'),
                                    ),
                                  ],
                                );
                              }
                              // The chooser inside the form browses People's
                              // tree, scoped to this dialog, on the Site the
                              // Concern already sits in.
                              return BlocProvider<OrgUnitPickerBloc>(
                                create: (context) => OrgUnitPickerBloc(
                                  peopleApi: context.read<PeopleApi>(),
                                  authGateway: context.read<AuthGateway>(),
                                  initialSiteId: current.action.siteId,
                                )..add(const OrgUnitPickerStarted()),
                                child: ActionMeasureDialog(
                                  concern: current.action,
                                  measureType: measureType,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // `/actions/capas/:id` — one CAPA's own Screen (issue #209). A
          // *sibling* of the Action detail route rather than a child of
          // it: a CAPA has its own id space (`capas`, the baseline's own
          // table) and its own Screen, and nesting it under the Concern
          // would leave the Concern's page mounted underneath it. The
          // address cannot be swallowed by `/actions/:id`: Express and
          // go_router both match a path a segment at a time, so a
          // three-segment path is never a two-segment one, and `capas` is
          // not an id.
          //
          // Keyed on the CAPA in the address, for the reason every other
          // detail route here is (issue #183): go_router reuses a route's
          // page when the *pattern* matches, so moving from one CAPA to
          // another would otherwise leave this Bloc — and the Screen
          // reading it — holding the investigation before.
          //
          // It is a `ShellRoute` of its own for the reason the Action detail
          // route is one (issue #210): a child `GoRoute`'s page is a
          // *sibling* of its parent's, so the three chain dialogs — add a
          // Why, revise one, remove one — would not see a `BlocProvider`
          // created inside the detail route's own builder. Providing it here
          // creates one `CapaDetailBloc` for the Screen and every dialog
          // over it, which is what makes a write from a dialog repaint the
          // chains behind it.
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              final capaId = state.pathParameters['id']!;
              return BlocProvider<CapaDetailBloc>(
                key: ValueKey<String>('capa-$capaId'),
                create: (context) => CapaDetailBloc(
                  actionsApi: context.read<ActionsApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(CapaDetailStarted(capaId)),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: '${Routes.actions}/capas/:id',
                builder: (context, state) =>
                    CapaDetailScreen(capaId: state.pathParameters['id']!),
                routes: [
                  // `${Routes.actions}/capas/:id/whys/:chain/new` — adding a
                  // Why to one of the two chains (issue #210). Nested under
                  // the CAPA's own route so it shares the Bloc above and a
                  // write repaints the chains behind it, exactly as the
                  // Action's own measure dialog is nested under its Action.
                  GoRoute(
                    path: 'whys/:chain/new',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) =>
                          CapaWhyDialog(chain: state.pathParameters['chain']!),
                    ),
                  ),
                  // `.../whys/:chain/:whyId/edit` — revising one. It names
                  // both the chain and the Why, so the address is the whole
                  // request: a Why that is not in that chain is refused
                  // rather than quietly edited.
                  GoRoute(
                    path: 'whys/:chain/:whyId/edit',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaWhyEditDialog(
                        chain: state.pathParameters['chain']!,
                        whyId: state.pathParameters['whyId']!,
                      ),
                    ),
                  ),
                  // `.../whys/:chain/:whyId/remove` — taking one out of the
                  // chain, with the confirmation that says so.
                  GoRoute(
                    path: 'whys/:chain/:whyId/remove',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaWhyRemoveDialog(
                        chain: state.pathParameters['chain']!,
                        whyId: state.pathParameters['whyId']!,
                      ),
                    ),
                  ),
                  // The fishbone (issue #213): five addresses, one per thing a
                  // team does to the candidate causes — record one under a 6M
                  // category, revise it, decide it with the evidence, remove
                  // it, and start a chain from one the evidence confirmed.
                  // Nested under the CAPA's own route for the reason the three
                  // chain dialogs above are: they share the `CapaDetailBloc`,
                  // so a write repaints the fishbone behind the form.
                  //
                  // The category is in the address, because which of the six a
                  // cause hangs from is the decision the caller made by opening
                  // it — the same argument `/whys/:chain/new` makes for the
                  // chain. `causes` is a literal segment where the three chain
                  // addresses have `whys`, so no route here can be swallowed by
                  // another.
                  GoRoute(
                    path: 'causes/:category/new',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) =>
                          CapaCauseDialog(category: state.pathParameters['category']!),
                    ),
                  ),
                  GoRoute(
                    path: 'causes/:category/:causeId/edit',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaCauseEditDialog(
                        category: state.pathParameters['category']!,
                        causeId: state.pathParameters['causeId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'causes/:category/:causeId/verdict',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaCauseVerdictDialog(
                        category: state.pathParameters['category']!,
                        causeId: state.pathParameters['causeId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'causes/:category/:causeId/remove',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaCauseRemoveDialog(
                        category: state.pathParameters['category']!,
                        causeId: state.pathParameters['causeId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'causes/:category/:causeId/why',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => CapaWhyFromCauseDialog(
                        category: state.pathParameters['category']!,
                        causeId: state.pathParameters['causeId']!,
                      ),
                    ),
                  ),
                  // `.../capas/:id/effectiveness` — recording the check that
                  // closes the investigation or sends its Concern round again
                  // (issue #211). Nested under the CAPA's own route so it shares
                  // the `CapaDetailBloc` above, and its answer repaints the
                  // Screen behind it, exactly as the three chain dialogs do.
                  //
                  // No gate in this builder, deliberately: unlike a chain write,
                  // this act is not a question the *router* can answer from a
                  // value it already has — the rule is "Quality authority at
                  // this CAPA's Org Unit, held by somebody who is not its team
                  // lead", and the answer belongs with the record. The dialog
                  // asks it against the CAPA it has read, and says which half
                  // refused.
                  GoRoute(
                    path: 'effectiveness',
                    pageBuilder: (context, state) => DialogPage<void>(
                      key: state.pageKey,
                      builder: (dialogContext) => const CapaEffectivenessDialog(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: Routes.approvals,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              // Unlike the sealed-state narrowing above, this *is* a per-Screen
              // access check: the redirect table decides who is admitted, not
              // what each role earns once admitted. Leaving the destination out
              // of the sidebar hides the door; this is what locks it, for a
              // caller who types the address.
              if (account is! AccountApproved || account.account.role != Roles.admin) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<ApprovalQueueBloc>(
                // Scoped to this route, not to the app the way AccountBloc is:
                // the queue is one Screen's reading of the server, and it
                // should be re-read on arrival rather than restored stale.
                create: (context) => ApprovalQueueBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const ApprovalQueueRequested()),
                child: const ApprovalQueueScreen(),
              );
            },
          ),
          GoRoute(
            path: Routes.assets,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              // The same per-Screen access check the two administrator Screens
              // make, against a Module's role set rather than a single role:
              // leaving the destination out of the sidebar hides the door,
              // this locks it for a caller who types the address.
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<AssetsBloc>(
                create: (context) => AssetsBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const AssetsStarted()),
                child: AssetsScreen(
                  // A caller with no write Grant anywhere is offered no way to
                  // add: the server would refuse it, so the interface does not
                  // invite it (#55, story 39). An administrator reaches
                  // everywhere by role and holds no Grant rows at all, which is
                  // exactly what `everywhere` means (issue #43).
                  canPlaceAnAsset: account.account.orgUnitScope.everywhere ||
                      account.account.orgUnitScope.grants.any((grant) => grant.canWrite),
                  // Per-row, unlike `canPlaceAnAsset` above (issue #173): a
                  // write Grant on one Org Unit says nothing about an Asset
                  // sitting at another. The same `canWriteAt` mechanism
                  // `canAssignWorkOrder` already uses below.
                  canCorrectAsset: account.account.orgUnitScope.canWriteAt,
                ),
              );
            },
          ),
          // The parts catalogue and the stores that hold parts (issue #80).
          // Both offered to the same Maintenance role set as Assets and Work
          // orders — reading them is open server-side, but the destination is
          // a product decision about who does maintenance's own work. Adding a
          // Part is administrator-only inside the Screen; receiving is offered
          // to a caller holding a write Grant somewhere, and the server is the
          // real gate.
          GoRoute(
            path: Routes.parts,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<PartsBloc>(
                create: (context) => PartsBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const PartsStarted()),
                child: PartsScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          GoRoute(
            path: Routes.stores,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<StoresBloc>(
                create: (context) => StoresBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const StoresStarted()),
                child: const StoresScreen(),
              );
            },
          ),
          // One store's stock, reached from the stores list above. The same
          // role guard; receiving is gated on the coarse write-Grant signal,
          // the same rule Assets applies to its own add button.
          GoRoute(
            path: '${Routes.stores}/:id',
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              final storeId = state.pathParameters['id']!;
              return BlocProvider<StoreStockBloc>(
                create: (context) => StoreStockBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  authGateway: context.read<AuthGateway>(),
                  storeId: storeId,
                )..add(const StoreStockStarted()),
                child: StoreStockScreen(canReceive: account.account.orgUnitScope.canWriteSomewhere),
              );
            },
          ),
          // Work orders (issue #104) — a `ShellRoute` of its own, nested
          // inside the outer one above, so `WorkOrdersBloc` is created
          // exactly once and shared by the list (`Routes.workOrders`) and
          // its four dialog addresses below. A child `GoRoute`'s own page is
          // a *sibling* of its parent's page in the Navigator, not a
          // descendant — a `BlocProvider` created only inside the list
          // route's own `builder` would not be visible to a dialog route
          // sitting beside it, which is why the Bloc is hoisted to this
          // `ShellRoute` instead (see `WorkOrdersScreen`'s own header for the
          // dialog-versus-Screen rule this addressability answers).
          ShellRoute(
            builder: (context, state, child) {
              final account = context.watch<AccountBloc>().state;
              // The same per-Screen access check `Routes.assets` makes,
              // against the same Module role set: leaving the destination out
              // of the sidebar hides the door, this locks it for a caller who
              // types the address — for the list or for any of its four
              // dialog addresses below.
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<WorkOrdersBloc>(
                create: (context) => WorkOrdersBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const WorkOrdersStarted()),
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: Routes.workOrders,
                builder: (context, state) {
                  final account = context.watch<AccountBloc>().state;
                  if (account is! AccountApproved) return const SizedBox.shrink();
                  return WorkOrdersScreen(
                    // Same rule `Routes.assets` applies to its own "Add an
                    // Asset" button: a caller with no write Grant anywhere is
                    // offered no way to raise, since the server would refuse
                    // it anyway (#55, story 39).
                    canRaiseWorkOrder: account.account.orgUnitScope.canWriteSomewhere,
                    // The per-Org-Unit write check (issue #62): may this
                    // caller write at the Org Unit a given Work order sits at?
                    // `canWriteAt` reads the same `/me` scope — each Grant's
                    // whole reach, issue #110/ADR-0027 — that HomeBloc's
                    // awaiting-assignment count reads, so the affordance and
                    // the count can never disagree about what is in scope. The
                    // server is the real gate (403).
                    canAssignWorkOrder: account.account.orgUnitScope.canWriteAt,
                    // Same coarse signal again, same reason (issue #63): a
                    // separate flag from canAssignWorkOrder rather than
                    // reusing it, since each affordance carries its own
                    // justification in this codebase and #77 will want to
                    // move these two apart.
                    canWorkWorkOrder: account.account.orgUnitScope.canWriteSomewhere,
                  );
                },
                routes: [
                  // `/work-orders/new` — the raise form (#104, Decision B:
                  // a creation against one Work order gets its own address).
                  // `'new'` cannot collide with the transition routes below,
                  // the same trick `${Routes.directory}/me` already plays
                  // against `${Routes.directory}/:id`.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) {
                          if (account is! AccountApproved) return const SizedBox.shrink();
                          if (!account.account.orgUnitScope.canWriteSomewhere) {
                            return AlertDialog(
                              key: WorkOrderDialogHost.notAvailableKey,
                              title: const Text('You cannot do that here'),
                              content: const Text(
                                'You do not hold a write Grant anywhere at this Site.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => dialogContext.pop(),
                                  child: const Text('Back to the list'),
                                ),
                              ],
                            );
                          }
                          final workOrdersState = context.watch<WorkOrdersBloc>().state;
                          final siteId = workOrdersState is WorkOrdersLoaded
                              ? workOrdersState.siteId
                              : null;
                          if (siteId == null) {
                            return const AlertDialog(
                              key: WorkOrderDialogHost.loadingKey,
                              content: SizedBox(
                                height: 80,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          return WorkOrderFormDialog(siteId: siteId);
                        },
                      );
                    },
                  ),
                  // `/work-orders/:id/assign` — Assign/Reassign is offered
                  // regardless of status (`_RowActions`'s own reasoning), so
                  // no status guard here, only the coarse permission one.
                  GoRoute(
                    path: ':id/assign',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      final workOrderId = state.pathParameters['id']!;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) => WorkOrderDialogHost(
                          workOrderId: workOrderId,
                          permitted:
                              account is AccountApproved && account.account.orgUnitScope.canWriteSomewhere,
                          builder: (workOrder) => WorkOrderAssignDialog(workOrder: workOrder),
                        ),
                      );
                    },
                  ),
                  // `/work-orders/:id/complete` — offered only while the row
                  // is `in_progress` (ADR-0019's own state machine).
                  GoRoute(
                    path: ':id/complete',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      final workOrderId = state.pathParameters['id']!;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) => WorkOrderDialogHost(
                          workOrderId: workOrderId,
                          permitted:
                              account is AccountApproved && account.account.orgUnitScope.canWriteSomewhere,
                          permittedForStatus: offersComplete,
                          builder: (workOrder) => WorkOrderCompleteDialog(workOrder: workOrder),
                        ),
                      );
                    },
                  ),
                  // `/work-orders/:id/cancel` — offered while the row is
                  // `approved` or `in_progress` (ADR-0019's own state
                  // machine).
                  GoRoute(
                    path: ':id/cancel',
                    pageBuilder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      final workOrderId = state.pathParameters['id']!;
                      return DialogPage<void>(
                        key: state.pageKey,
                        builder: (dialogContext) => WorkOrderDialogHost(
                          workOrderId: workOrderId,
                          permitted:
                              account is AccountApproved && account.account.orgUnitScope.canWriteSomewhere,
                          permittedForStatus: offersCancel,
                          builder: (workOrder) => WorkOrderCancelDialog(workOrder: workOrder),
                        ),
                      );
                    },
                  ),
                  // `/work-orders/:id` — the Work order detail read (issue
                  // #74), a Screen of its own rather than a dialog because it
                  // fetches the Work order and its copied tasks from
                  // `GET /work-orders/:id`, which the Site-wide list
                  // deliberately does not carry. Declared after the literal
                  // `new` and the `:id/action` routes so none of them is
                  // shadowed; a malformed or unknown id resolves to a failure
                  // state with a retry on the Screen itself.
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final account = context.watch<AccountBloc>().state;
                      if (account is! AccountApproved) return const SizedBox.shrink();
                      final workOrderId = state.pathParameters['id']!;
                      return BlocProvider<WorkOrderDetailBloc>(
                        create: (context) => WorkOrderDetailBloc(
                          maintenanceApi: context.read<MaintenanceApi>(),
                          authGateway: context.read<AuthGateway>(),
                          workOrderId: workOrderId,
                        )..add(const WorkOrderDetailStarted()),
                        child: WorkOrderDetailScreen(
                          workOrderId: workOrderId,
                          // Same coarse signal the list's own writable
                          // affordances use: a caller with no write Grant
                          // anywhere is offered no booking button, since the
                          // server would refuse it anyway; likewise (issue #79)
                          // a task that names a meter offers a reading action
                          // to a caller who could write one, and the server is
                          // the real gate.
                          canBook: account.account.orgUnitScope.canWriteSomewhere,
                          canRecord: account.account.orgUnitScope.canWriteSomewhere,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // The Requests this caller raised (issue #72), plus the raise form
          // it opens. Offered to every approved Account — raising needs only a
          // read Grant reaching the Asset's Org Unit, so this is the
          // operator-facing Destination that earns them the Module. There is
          // no per-Screen role check here at all; the raise affordance inside
          // is gated on the caller holding a Grant somewhere, and the server
          // is the real gate.
          GoRoute(
            path: Routes.myRequests,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved) return const SizedBox.shrink();
              return BlocProvider<MyRequestsBloc>(
                create: (context) => MyRequestsBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const MyRequestsStarted()),
                child: MyRequestsScreen(
                  // The same rule the server applies: raising asks a question
                  // and needs only a read Grant reaching the Asset's Org Unit
                  // (`write: false`), so this reads the everywhere-first
                  // `canReadSomewhere` rather than `canWriteSomewhere`.
                  canRaiseRequest: account.account.orgUnitScope.canReadSomewhere,
                ),
              );
            },
          ),
          // The triage queue (issue #72) is maintenance's own work, gated to
          // the same Module role set Assets and Work orders use. The same
          // per-Screen access check they make: leaving the destination out of
          // the sidebar hides the door, this locks it for a caller who types
          // the address.
          GoRoute(
            path: Routes.requests,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<RequestsBloc>(
                create: (context) => RequestsBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const RequestsStarted()),
                child: RequestsScreen(canTriage: account.account.orgUnitScope.canWriteSomewhere),
              );
            },
          ),
          // Downtime (issue #73) is maintenance's own work, gated to the same
          // Module role set Assets, Work orders and the Triage queue use. The
          // same per-Screen access check they make: leaving the destination out
          // of the sidebar hides the door, this locks it for a caller who types
          // the address. Reporting a Breakdown, closing a stop and classifying
          // one all need a write Grant, so the report button and the row
          // actions read the same coarse `canWriteSomewhere` signal.
          GoRoute(
            path: Routes.downtime,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<DowntimeBloc>(
                create: (context) => DowntimeBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const DowntimeStarted()),
                child: DowntimeScreen(canAct: account.account.orgUnitScope.canWriteSomewhere),
              );
            },
          ),
          // PM schedules (issue #74) are maintenance's own work, gated to the
          // same Module role set Assets, Work orders and the Triage queue use.
          // The same per-Screen access check they make: leaving the destination
          // out of the sidebar hides the door, this locks it for a caller who
          // types the address. Creating a schedule and toggling one both need a
          // write Grant, so the create button and the row toggle read the same
          // coarse `canWriteSomewhere` signal.
          GoRoute(
            path: Routes.pmSchedules,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<PmSchedulesBloc>(
                create: (context) => PmSchedulesBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const PmSchedulesStarted()),
                child: PmSchedulesScreen(canAct: account.account.orgUnitScope.canWriteSomewhere),
              );
            },
          ),
          // Meters (issue #79) follow the same Module role set as the rest of
          // maintenance: a supervisor, engineer, manager or administrator
          // defines a meter and records readings. Only a cumulative meter can
          // drive a PM schedule, and the server is the real gate; the create
          // and record affordances read the coarse `canWriteSomewhere` signal.
          GoRoute(
            path: Routes.meters,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<MetersBloc>(
                create: (context) => MetersBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const MetersStarted()),
                child: MetersScreen(canAct: account.account.orgUnitScope.canWriteSomewhere),
              );
            },
          ),
          // Job plans (issue #74) is the administrator-managed catalogue. Its
          // Destination is administrator-only, but the route admits the same
          // maintenance role set as the other Maintenance reads: the server's
          // GET /job-plans is open to any approved Account, and only the write
          // affordances inside the Screen are gated (to `isAdmin`). A caller
          // outside the Module still gets AccessDeniedScreen for typing the
          // address.
          GoRoute(
            path: Routes.jobPlans,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              if (account is! AccountApproved ||
                  !ModuleRoles.maintenance.contains(account.account.role)) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<JobPlansBloc>(
                create: (context) => JobPlansBloc(
                  maintenanceApi: context.read<MaintenanceApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const JobPlansStarted()),
                child: JobPlansScreen(isAdmin: account.account.role == Roles.admin),
              );
            },
          ),
          GoRoute(
            path: Routes.accounts,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              // The same per-Screen access check the Approval queue makes, for
              // the same reason: leaving the destination out of the sidebar
              // hides the door, this locks it for a caller who types the
              // address.
              if (account is! AccountApproved || account.account.role != Roles.admin) {
                return const AccessDeniedScreen();
              }
              return BlocProvider<AccountsBloc>(
                create: (context) => AccountsBloc(
                  peopleApi: context.read<PeopleApi>(),
                  authGateway: context.read<AuthGateway>(),
                )..add(const AccountsRequested()),
                child: AccountsScreen(selfAccountId: account.account.id),
              );
            },
          ),
        ],
      ),
    ],
  );
}

@visibleForTesting
String? accountRedirect(AccountState account, GoRouterState state) {
  final location = state.matchedLocation;
  // The floor surface is a device's own address, not an Account's: it must be
  // reachable whether or not anybody is signed in, and an approved Account
  // landing on it must not be redirected back to the Shell either. This is the
  // one place the router says so (issue #77).
  if (location == Routes.floor) return null;
  final atSignIn = location == Routes.signIn;
  final atAwaiting = location == Routes.awaitingApproval;

  switch (account) {
    case AccountResolving():
    case AccountUnavailable():
      // Rendered by the MaterialApp.router `builder` overlay instead — the
      // caller's real address stays intact underneath while it shows.
      return null;

    case AccountSignedOut():
      if (atSignIn) return null;
      return Uri(
        path: Routes.signIn,
        queryParameters: {Routes.fromParameter: state.uri.toString()},
      ).toString();

    case AccountAwaitingApproval():
      return atAwaiting ? null : Routes.awaitingApproval;

    case AccountApproved():
      if (!atSignIn && !atAwaiting) return null;
      // Considered addition beyond the issue's literal ACs: after signing
      // in, the current location genuinely is `/sign-in?from=...`, so
      // something has to move an approved caller off it to deliver them to
      // the address they originally asked for.
      final from = state.uri.queryParameters[Routes.fromParameter];
      // Open-redirect guard: `from` comes off a caller-controlled URL, so
      // only accept a same-origin path (single leading slash, not `//...`).
      if (from == null || !from.startsWith('/') || from.startsWith('//')) return Routes.home;
      final target = Uri.parse(from).path;
      // Redirect-loop guard: don't send an approved caller back to
      // sign-in/awaiting-approval even if that's what `from` points at.
      if (target == Routes.signIn || target == Routes.awaitingApproval) return Routes.home;
      return from;
  }
}

/// Turns the Bloc's state stream into the [Listenable] go_router refreshes on.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
