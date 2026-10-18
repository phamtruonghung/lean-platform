/// Picks the [AuthGateway] at boot (issue #269), by asking the deployment.
///
/// `GET /api/auth/mode` answers `{"password":"local"}` when the API keeps the
/// passwords itself and `{"password":"supabase"}` otherwise. Asking at runtime
/// rather than baking a `--dart-define` into the build means one image serves
/// either deployment. Anything short of a clear `local` — unreachable API, a
/// non-200, unreadable JSON, an unknown value — falls back to Supabase, which
/// is today's path and must stay what an unanswered question gets.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_gateway.dart';
import 'local_auth_gateway.dart';

/// [supabase] does today's `Supabase.initialize(...)` and builds the
/// `SupabaseAuthGateway`; it is not called at all in local mode. [client] is
/// the raw client — the one the returned local gateway keeps for its own
/// login and logout.
Future<AuthGateway> bootstrapAuth({
  required http.Client client,
  required Future<AuthGateway> Function() supabase,
}) async {
  if (await _isLocal(client)) return LocalAuthGateway.load(client: client);
  return supabase();
}

Future<bool> _isLocal(http.Client client) async {
  try {
    final response = await client.get(Uri.parse('/api/auth/mode'));
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body);
    return body is Map<String, dynamic> && body['password'] == 'local';
  } catch (_) {
    return false;
  }
}
