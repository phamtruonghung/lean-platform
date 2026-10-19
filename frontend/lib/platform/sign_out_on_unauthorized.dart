/// A 401 from any API call signs the client out (issue #269).
///
/// The local session's token can expire or be revoked while the app is open,
/// and every Module's client would otherwise have to notice that for itself.
/// One decorator around the shared client does it once: a 401 calls
/// [AuthGateway.signOut] and the response passes through unchanged. There is
/// no retry. Only a request that carried an `authorization` header and was not
/// a floor-device request (`x-floor-device`) can mean a dead session: a wrong
/// floor PIN is a 401 too, and so is an unknown device, and neither says
/// anything about the signed-in person. A 403 is a role refusal, not a dead session, so it does not sign
/// anyone out.
///
/// Wired only when the local gateway is selected (main.dart), leaving the
/// Supabase path exactly as it was. The gateway's own login and logout use the
/// raw client, never this one, because a failed login is itself a 401.
library;

import 'package:http/http.dart' as http;

import 'auth_gateway.dart';

class SignOutOnUnauthorized extends http.BaseClient {
  SignOutOnUnauthorized(this._inner, this._gateway);

  final http.Client _inner;
  final AuthGateway _gateway;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode == 401 && _carriesSession(request)) await _gateway.signOut();
    return response;
  }

  static bool _carriesSession(http.BaseRequest request) =>
      request.headers.containsKey('authorization') && !request.headers.containsKey('x-floor-device');

  @override
  void close() => _inner.close();
}
