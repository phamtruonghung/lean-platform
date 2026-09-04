import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../maintenance/maintenance_api.dart';
import '../people_api.dart';
import '../theme.dart';
import 'account_bloc.dart';
import 'auth_gateway.dart';
import 'router.dart';
import 'session_error_screen.dart';

class PlatformApp extends StatefulWidget {
  const PlatformApp({
    super.key,
    required this.authGateway,
    required this.peopleApi,
    required this.maintenanceApi,
    this.initialLocation,
  });

  final AuthGateway authGateway;
  final PeopleApi peopleApi;
  final MaintenanceApi maintenanceApi;

  /// Supplied only by tests; always null in production.
  final String? initialLocation;

  @override
  State<PlatformApp> createState() => _PlatformAppState();
}

class _PlatformAppState extends State<PlatformApp> {
  late final AccountBloc _accountBloc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Built exactly once: building either in build() would recreate the
    // router on every rebuild and destroy navigation history.
    _accountBloc = AccountBloc(authGateway: widget.authGateway, peopleApi: widget.peopleApi);
    _router = buildRouter(accountBloc: _accountBloc, initialLocation: widget.initialLocation);
  }

  @override
  void dispose() {
    _router.dispose();
    _accountBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthGateway>.value(value: widget.authGateway),
        // Provided so a Module's own Bloc can be built at its route, with the
        // same faked wire a widget test already substitutes here.
        RepositoryProvider<PeopleApi>.value(value: widget.peopleApi),
        RepositoryProvider<MaintenanceApi>.value(value: widget.maintenanceApi),
      ],
      child: BlocProvider<AccountBloc>.value(
        value: _accountBloc,
        child: MaterialApp.router(
          title: 'Platform',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routerConfig: _router,
          builder: (context, child) {
            final account = context.watch<AccountBloc>().state;
            // This overlay — not a `/loading` or `/error` route — is why the
            // redirect table returns null (no redirect) for both of these
            // states: the caller's real URL stays intact underneath while
            // this renders on top, and no protected route ever gets built
            // while the state is unresolved.
            return switch (account) {
              AccountResolving() =>
                const Scaffold(body: Center(child: CircularProgressIndicator())),
              AccountUnavailable(message: final message) => SessionErrorScreen(message: message),
              _ => child ?? const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}
