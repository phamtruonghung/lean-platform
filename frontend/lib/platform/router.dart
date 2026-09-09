import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../auth/awaiting_approval_screen.dart';
import '../auth/sign_in_screen.dart';
import '../home_screen.dart';
import '../maintenance/assets_bloc.dart';
import '../maintenance/assets_screen.dart';
import '../maintenance/maintenance_api.dart';
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
import '../people_api.dart';
import 'access_denied_screen.dart';
import 'account_bloc.dart';
import 'auth_gateway.dart';
import 'destinations.dart';
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
  static const String directory = '/directory';
  static const String jobRoles = '/job-roles';

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
              return account is AccountApproved
                  ? HomeScreen(account: account.account)
                  : const SizedBox.shrink();
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
                ),
              );
            },
          ),
          GoRoute(
            path: Routes.workOrders,
            builder: (context, state) {
              final account = context.watch<AccountBloc>().state;
              // The same per-Screen access check `Routes.assets` makes,
              // against the same Module role set: leaving the destination out
              // of the sidebar hides the door, this locks it for a caller who
              // types the address.
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
                child: WorkOrdersScreen(
                  // Same rule `Routes.assets` applies to its own "Add an
                  // Asset" button: a caller with no write Grant anywhere is
                  // offered no way to raise, since the server would refuse it
                  // anyway (#55, story 39).
                  canRaiseWorkOrder: account.account.orgUnitScope.canWriteSomewhere,
                  // Same coarse signal, same reason (issue #62): `/me` reports
                  // which Org Units are granted but not their ancestry, so
                  // the client cannot tell whether a Grant *reaches* this
                  // particular Work order's Org Unit. The server is the real
                  // gate (403); this only avoids offering an action to a
                  // caller who holds no write Grant anywhere at all.
                  canAssignWorkOrder: account.account.orgUnitScope.canWriteSomewhere,
                  // Same coarse signal again, same reason (issue #63): a
                  // separate flag from canAssignWorkOrder rather than reusing
                  // it, since each affordance carries its own justification
                  // in this codebase and #77 will want to move these two
                  // apart.
                  canWorkWorkOrder: account.account.orgUnitScope.canWriteSomewhere,
                ),
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
