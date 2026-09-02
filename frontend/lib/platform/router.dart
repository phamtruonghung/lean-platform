import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../auth/awaiting_approval_screen.dart';
import '../auth/sign_in_screen.dart';
import '../home_screen.dart';
import 'account_bloc.dart';
import 'not_found_screen.dart';

abstract final class Routes {
  static const String home = '/';
  static const String signIn = '/sign-in';
  static const String awaitingApproval = '/awaiting-approval';

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
      GoRoute(
        path: Routes.home,
        builder: (context, state) {
          final account = context.watch<AccountBloc>().state;
          // Sealed-state type narrowing, not a per-Screen access check: the
          // redirect below has already decided nobody else reaches here.
          return account is AccountApproved
              ? HomeScreen(account: account.account)
              : const SizedBox.shrink();
        },
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
