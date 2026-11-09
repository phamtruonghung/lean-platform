/// The one seam between this client and the API's own sign-in
/// (platform/local_auth_gateway.dart, issue #269). There is no second
/// implementation: issue #480 deleted the hosted-provider gateway along with
/// the deployment switch that chose between them.
library;

/// A sign-in the API refused, in words already fit to show a person.
///
/// The API answers a `message` and the screen shows it verbatim, inventing no
/// copy of its own.
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

  /// Refused on this deployment: an administrator creates Accounts (issue
  /// #270), so there is no self-service sign-up to reach.
  Future<void> signUp({required String email, required String password});

  /// Refused on this deployment: sign-in is an email and a password, nothing
  /// else.
  Future<void> signInWithGoogle();

  Future<void> signOut();
}
