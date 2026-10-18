/// Sign-in against this Platform's own API (issue #269), for a deployment that
/// keeps its passwords itself rather than in Supabase Auth.
///
/// The API answers `POST /api/auth/login` with an opaque token and an expiry;
/// the token is sent as a bearer token exactly where the Supabase access token
/// goes (platform/account_bloc.dart), so nothing downstream knows which
/// provider issued it. The session is kept in `shared_preferences` so a reload
/// does not sign the person out, as Supabase's own persistence does for the
/// other provider.
///
/// [currentAccessToken] is synchronous, so the stored session is read before
/// the gateway is built — see [LocalAuthGateway.load].
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_gateway.dart';

class LocalAuthGateway implements AuthGateway {
  LocalAuthGateway._(this._client, this._prefs, this._token);

  static const tokenKey = 'platform.session.token';
  static const expiresAtKey = 'platform.session.expiresAt';

  /// Reads the stored session, dropping it if it has already expired, and
  /// builds a gateway that starts out signed in or out accordingly.
  ///
  /// [client] must be the raw client, never one that signs out on a 401: a
  /// failed login is itself a 401.
  static Future<LocalAuthGateway> load({required http.Client client, DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(tokenKey);
    final expiresAt = DateTime.tryParse(prefs.getString(expiresAtKey) ?? '');
    final live = token != null && expiresAt != null && expiresAt.isAfter(now ?? DateTime.now());
    if (!live) {
      await prefs.remove(tokenKey);
      await prefs.remove(expiresAtKey);
    }
    return LocalAuthGateway._(client, prefs, live ? token : null);
  }

  final http.Client _client;
  final SharedPreferences _prefs;
  final StreamController<String?> _changes = StreamController<String?>.broadcast();
  String? _token;

  @override
  String? get currentAccessToken => _token;

  /// Honours [AuthGateway]'s contract: the current token first, then every
  /// change after it.
  @override
  Stream<String?> get accessTokenChanges async* {
    yield _token;
    yield* _changes.stream;
  }

  /// Relative on purpose, like every other API call: the reverse proxy serves
  /// the app and the API from one hostname.
  @override
  Future<void> signInWithPassword({required String email, required String password}) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('/api/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
    } catch (error) {
      throw AuthRefusal('Could not reach the API: $error');
    }

    if (response.statusCode != 200) {
      throw AuthRefusal(_messageOf(response) ?? 'Sign-in failed (${response.statusCode}).');
    }

    final String token;
    final String expiresAt;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      token = body['token'] as String;
      expiresAt = body['expiresAt'] as String;
    } catch (_) {
      throw const AuthRefusal('The API answered with something this app could not read.');
    }

    await _prefs.setString(tokenKey, token);
    await _prefs.setString(expiresAtKey, expiresAt);
    _token = token;
    _changes.add(token);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    throw const AuthRefusal('Accounts on this deployment are created by an administrator.');
  }

  @override
  Future<void> signInWithGoogle() async {
    throw const AuthRefusal('This deployment has no Google sign-in.');
  }

  /// Always succeeds locally: the logout call is best-effort (it is idempotent
  /// on the API, and an unreachable API must not leave a person stuck signed
  /// in). A gateway already signed out does nothing, so several 401s landing
  /// together post one logout.
  @override
  Future<void> signOut() async {
    final token = _token;
    if (token == null) return;
    _token = null;
    try {
      await _client.post(Uri.parse('/api/auth/logout'), headers: {'authorization': 'Bearer $token'});
    } catch (_) {
      // Signed out locally regardless.
    }
    await _prefs.remove(tokenKey);
    await _prefs.remove(expiresAtKey);
    _changes.add(null);
  }

  static String? _messageOf(http.Response response) {
    try {
      final message = (jsonDecode(response.body) as Map<String, dynamic>)['message'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}
