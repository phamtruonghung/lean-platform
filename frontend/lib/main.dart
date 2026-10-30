/// Platform — the Flutter Web client.
///
/// Who signs a person in is asked of the deployment at boot (issue #269, see
/// platform/auth_bootstrap.dart). By default Supabase Auth is the identity
/// provider (ADR-0002): this app signs up and signs in against it directly,
/// holds the session it issues (Supabase persists that locally and restores it
/// on reload — see platform/auth_gateway.dart), and sends the session's token
/// to the API as a bearer token. When the API says it keeps the passwords
/// itself, the app signs in against the API instead
/// (platform/local_auth_gateway.dart) and sends that opaque token the same
/// way; Supabase is then never initialised. Either way the API resolves the
/// token to an Account; until an administrator admits that Account, the
/// awaiting-Approval Screen shows rather than an error (see
/// platform/account_bloc.dart, ADR-0012). See issue #6 and README.md's
/// Authentication section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'kpi/kpi_api.dart';
import 'maintenance/maintenance_api.dart';
import 'actions/actions_api.dart';
import 'people_api.dart';
import 'platform/auth_bootstrap.dart';
import 'platform/auth_gateway.dart';
import 'platform/floor_device_gateway.dart';
import 'platform/local_auth_gateway.dart';
import 'platform/platform_app.dart';
import 'platform/sign_out_on_unauthorized.dart';
import 'quality/quality_api.dart';
import 'production/production_api.dart';
import 'safety/safety_api.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, every address is `/#/sign-in` instead of `/sign-in` —
  // technically satisfies the literal ACs but defeats "send a colleague a
  // link" (issue #33's story 10). nginx.conf's `try_files` already resolves
  // deep links at the edge.
  usePathUrlStrategy();
  final rawClient = http.Client();
  final gateway = await bootstrapAuth(
    client: rawClient,
    supabase: () async {
      // supabase_flutter calls this a "publishable key" as of 2.17; it is the
      // same public, browser-safe key Supabase's dashboard still labels "anon
      // key" today, which is why supabase_config.dart keeps that name.
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
      return SupabaseAuthGateway();
    },
  );
  // Only the local session can die under an open app, so only it gets the
  // client that signs out on a 401; the Supabase path is unchanged.
  final apiClient = gateway is LocalAuthGateway
      ? SignOutOnUnauthorized(rawClient, gateway)
      : rawClient;
  runApp(
    PlatformApp(
      authGateway: gateway,
      peopleApi: PeopleApi(client: apiClient),
      maintenanceApi: MaintenanceApi(client: apiClient),
      actionsApi: ActionsApi(client: apiClient),
      qualityApi: QualityApi(client: apiClient),
      safetyApi: SafetyApi(client: apiClient),
      productionApi: ProductionApi(client: apiClient),
      kpiApi: KpiApi(client: apiClient),
      floorDeviceGateway: const ConfiguredFloorDeviceGateway(),
    ),
  );
}
