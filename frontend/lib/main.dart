/// Platform — the Flutter Web client.
///
/// Sign-in is the Platform's own: the app posts an email and a password to
/// the API's `POST /api/auth/login`, holds the opaque session token it gets
/// back (platform/local_auth_gateway.dart), and sends it to the API as a
/// bearer token. There is no other door — issue #480 removed the hosted
/// identity-provider branch — and `GET /api/auth/mode` answering `local` is
/// now a constant. The API resolves the token to an Account; until an
/// administrator admits that Account, the awaiting-Approval Screen shows
/// rather than an error (see platform/account_bloc.dart, ADR-0012). See
/// issue #6 and README.md's Authentication section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'kpi/kpi_api.dart';
import 'maintenance/maintenance_api.dart';
import 'actions/actions_api.dart';
import 'people_api.dart';
import 'platform/floor_device_gateway.dart';
import 'platform/local_auth_gateway.dart';
import 'platform/platform_app.dart';
import 'platform/sign_out_on_unauthorized.dart';
import 'quality/quality_api.dart';
import 'production/production_api.dart';
import 'safety/safety_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, every address is `/#/sign-in` instead of `/sign-in` —
  // technically satisfies the literal ACs but defeats "send a colleague a
  // link" (issue #33's story 10). nginx.conf's `try_files` already resolves
  // deep links at the edge.
  usePathUrlStrategy();
  final rawClient = http.Client();
  final gateway = await LocalAuthGateway.load(client: rawClient);
  // Only the local session can die under an open app, so the API client signs
  // the person out when it does.
  final apiClient = SignOutOnUnauthorized(rawClient, gateway);
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
