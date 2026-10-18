/// The one seam between this client and whichever identity provider the
/// deployment uses: Supabase Auth (ADR-0002) or the API's own sign-in
/// (platform/local_auth_gateway.dart, issue #269).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// A sign-in the provider refused, in words already fit to show a person.
///
/// Provider-neutral on purpose (issue #269): Supabase refusals arrive as its
/// own `AuthException` and keep their code-to-copy mapping in
/// auth/auth_error_messages.dart, while the API's own sign-in answers with a
/// `message` the screen must show verbatim, inventing no copy of its own.
class AuthRefusal implements Exception {
  const AuthRefusal(this.message);

  final String message;

  @override
  String toString() => 'AuthRefusal: $message';
}

abstract class AuthGateway {
  String? get currentAccessToken;
  Stream<String?> get accessTokenChanges;
  Future<void> signInWithPassword({required String email, required String password});
  Future<void> signUp({required String email, required String password});
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway({GoTrueClient? auth}) : _auth = auth ?? Supabase.instance.client.auth;

  final GoTrueClient _auth;

  @override
  String? get currentAccessToken => _auth.currentSession?.accessToken;

  @override
  Stream<String?> get accessTokenChanges async* {
    yield _auth.currentSession?.accessToken;
    yield* _auth.onAuthStateChange.map((event) => event.session?.accessToken);
  }

  @override
  Future<void> signInWithPassword({required String email, required String password}) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signUp({required String email, required String password}) =>
      _auth.signUp(email: email, password: password);

  @override
  Future<void> signInWithGoogle() => _auth.signInWithOAuth(OAuthProvider.google);

  @override
  Future<void> signOut() => _auth.signOut();
}
