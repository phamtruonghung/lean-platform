/// The one seam between this client and Supabase Auth.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

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
