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
import '../actions/actions_api.dart';
import '../actions/actions_bloc.dart';
import '../actions/actions_screen.dart';
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
import '../quality/defect_codes_bloc.dart';
import '../quality/defect_codes_screen.dart';
import '../quality/nonconformance_detail_bloc.dart';
import '../quality/nonconformance_detail_screen.dart';
import '../quality/nonconformance_form_dialog.dart';
import '../quality/nonconformance_quantity_dialog.dart';
import '../quality/nonconformance_update_dialog.dart';
import '../quality/nonconformances_bloc.dart';
import '../quality/nonconformances_screen.dart';
import '../quality/products_bloc.dart';
import '../quality/products_screen.dart';
import '../quality/quality_api.dart';
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

  /// The Actions Module's own Destinations (issue #176): the action log, and
  /// one Action's detail read behind `${actions}/:id`. The raise form is
  /// addressed at `${actions}/new` (ADR-0021), which cannot collide with the
  /// detail route because `new` is not an id.
  static const String actions = '/actions';

  /// The shared floor device's own Screen (issue #77, ADR-0016). Its own
  /// address, deliberately outside the Shell and never offered as a
  /// Destination: a device is not an Account, and this surface must be
  /// reachable without signing in.
  static const String floor = '/floor';

  /// The query parameter on [signIn] carrying the address the caller
  /// originally asked for.
  static const String fromParameter = 'from';
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
                    ],
                  ),
                ],
              ),
            ],
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
