/// Platform — the Flutter Web client.
///
/// Supabase Auth is the identity provider (ADR-0002): this app signs up and
/// signs in against it directly, holds the session it issues (Supabase
/// persists that locally and restores it on reload — see
/// platform/auth_gateway.dart), and sends the session's token to the API as
/// a bearer token. The API verifies that token and resolves it to an
/// Account; until an administrator admits that Account, the
/// awaiting-Approval Screen shows rather than an error (see
/// platform/account_bloc.dart, ADR-0012). See issue #6 and README.md's
/// Authentication section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'maintenance/maintenance_api.dart';
import 'people_api.dart';
import 'platform/auth_gateway.dart';
import 'platform/platform_app.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, every address is `/#/sign-in` instead of `/sign-in` —
  // technically satisfies the literal ACs but defeats "send a colleague a
  // link" (issue #33's story 10). nginx.conf's `try_files` already resolves
  // deep links at the edge.
  usePathUrlStrategy();
  // supabase_flutter calls this a "publishable key" as of 2.17; it is the
  // same public, browser-safe key Supabase's dashboard still labels "anon
  // key" today, which is why supabase_config.dart keeps that name.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(
    PlatformApp(
      authGateway: SupabaseAuthGateway(),
      peopleApi: PeopleApi(),
      maintenanceApi: MaintenanceApi(),
    ),
  );
}
