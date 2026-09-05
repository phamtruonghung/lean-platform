import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:lean_platform/auth/auth_error_messages.dart';

void main() {
  group('authErrorMessage', () {
    test('email_address_invalid says delivery failed, not that the address is malformed', () {
      final error = AuthException(
        'Email address "hung@gmail.com" is invalid',
        code: 'email_address_invalid',
      );

      expect(
        authErrorMessage(error),
        "We couldn't send a confirmation to that address. Check it, or ask an "
        'administrator to add you.',
      );
    });

    test('over_email_send_rate_limit says try again in an hour', () {
      final error = AuthException('email rate limit exceeded', code: 'over_email_send_rate_limit');

      expect(
        authErrorMessage(error),
        'Too many sign-up attempts have been made. Try again in an hour.',
      );
    });

    test('user_already_exists says sign in instead', () {
      final error = AuthException('User already registered', code: 'user_already_exists');

      expect(
        authErrorMessage(error),
        'An Account with that email already exists. Sign in instead.',
      );
    });

    test('email_exists says sign in instead', () {
      final error = AuthException('Email already in use', code: 'email_exists');

      expect(
        authErrorMessage(error),
        'An Account with that email already exists. Sign in instead.',
      );
    });

    test('weak_password asks for a stronger one', () {
      final error = AuthException('Password should be at least 6 characters', code: 'weak_password');

      expect(
        authErrorMessage(error),
        'That password is too weak. Use a longer password with a mix of letters and numbers.',
      );
    });

    test('invalid_credentials says the email or password is wrong', () {
      final error = AuthException('Invalid login credentials', code: 'invalid_credentials');

      expect(
        authErrorMessage(error),
        'That email or password is not right. Check them and try again.',
      );
    });

    test('an unmapped code falls back to the raw message', () {
      final error = AuthException('Something GoTrue-specific and new', code: 'some_new_code');

      expect(authErrorMessage(error), 'Something GoTrue-specific and new');
    });

    test('a null code falls back to the raw message', () {
      const error = AuthException('No code on this one');

      expect(authErrorMessage(error), 'No code on this one');
    });
  });
}
