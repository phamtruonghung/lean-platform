/// Honest, actionable copy for the `AuthException`s Supabase Auth raises
/// during sign-up and sign-in — a pure mapping from `error.code`, kept out of
/// `sign_in_screen.dart`'s `build()` so it is unit-testable on its own
/// (issue #69).
///
/// GoTrue's own wording is written for the person configuring the project,
/// not the person trying to create an Account, and on this project's setup
/// (Supabase's built-in email service, `README.md`'s Authentication section)
/// it can be actively misleading: `email_address_invalid` means the address
/// was refused for delivery by the built-in service's team-only policy, not
/// that the address is malformed, and `over_email_send_rate_limit` counts
/// requests, not deliveries, so a couple of failed attempts can exhaust it
/// with nothing ever sent.
///
/// A code this map does not know about falls back to `error.message`
/// verbatim — a new server-side code must never be swallowed into silence.
library;

import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

const Map<String, String> _messagesByCode = {
  'email_address_invalid': "We couldn't send a confirmation to that address. "
      'Check it, or ask an administrator to add you.',
  'over_email_send_rate_limit': 'Too many sign-up attempts have been made. Try again in an hour.',
  'user_already_exists': 'An Account with that email already exists. Sign in instead.',
  'email_exists': 'An Account with that email already exists. Sign in instead.',
  'weak_password': 'That password is too weak. Use a longer password with a mix of letters and '
      'numbers.',
  'invalid_credentials': 'That email or password is not right. Check them and try again.',
};

/// The copy to show for [error] — the mapped message for a known `code`, or
/// [AuthException.message] unchanged for anything this map does not cover.
String authErrorMessage(AuthException error) => _messagesByCode[error.code] ?? error.message;
