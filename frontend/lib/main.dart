/// Platform — the Flutter Web client.
///
/// Supabase Auth is the identity provider (ADR-0002): this app signs up and
/// signs in against it directly, holds the session it issues (Supabase
/// persists that locally and restores it on reload — see auth/auth_gate.dart),
/// and sends the session's token to the API as a bearer token. The API
/// verifies that token and resolves it to an Account; until an administrator
/// admits that Account, AuthGate shows the awaiting-Approval screen rather
/// than an error. See issue #6 and README.md's Authentication section.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'supabase_config.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // supabase_flutter calls this a "publishable key" as of 2.17; it is the
  // same public, browser-safe key Supabase's dashboard still labels "anon
  // key" today, which is why supabase_config.dart keeps that name.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const PlatformApp());
}

class PlatformApp extends StatelessWidget {
  const PlatformApp({super.key, this.httpClient});

  /// Supplied only by tests. Threaded down to PeopleApi so a widget test can
  /// stand a fake client in for the network at the wire, instead of the
  /// widget tree constructing its own client where nothing above can reach
  /// it (issue #37's own HTTP-client-injection criterion).
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platform',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AuthGate(httpClient: httpClient),
    );
  }
}
