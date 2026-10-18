/// The signed-in person changing their own password (issue #270): `PUT
/// /api/people/me/password`. Dialog-scoped and built fresh on every open — one
/// act, not a Screen's reading of the server.
///
/// An API call through [PeopleApi], not a new [AuthGateway] method: the
/// gateway owns who is signed in, and a password change leaves that exactly as
/// it was. A wrong current password is the server's 400, never a 401, so
/// nothing here (or in `SignOutOnUnauthorized`) ends the session.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import 'auth_gateway.dart';

sealed class ChangePasswordEvent {
  const ChangePasswordEvent();
}

class ChangePasswordSubmitted extends ChangePasswordEvent {
  const ChangePasswordSubmitted({required this.currentPassword, required this.newPassword});
  final String currentPassword;
  final String newPassword;
}

sealed class ChangePasswordState {
  const ChangePasswordState();
}

class ChangePasswordIdle extends ChangePasswordState {
  const ChangePasswordIdle();
}

class ChangePasswordInProgress extends ChangePasswordState {
  const ChangePasswordInProgress();
}

class ChangePasswordSucceeded extends ChangePasswordState {
  const ChangePasswordSucceeded();
}

/// [message] is the server's own words, shown as they came.
class ChangePasswordFailed extends ChangePasswordState {
  const ChangePasswordFailed(this.message);
  final String message;
}

class ChangePasswordBloc extends Bloc<ChangePasswordEvent, ChangePasswordState> {
  ChangePasswordBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const ChangePasswordIdle()) {
    on<ChangePasswordSubmitted>(_onSubmitted);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onSubmitted(
    ChangePasswordSubmitted event,
    Emitter<ChangePasswordState> emit,
  ) async {
    if (state is ChangePasswordInProgress) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ChangePasswordFailed(signedOutMessage));
      return;
    }
    emit(const ChangePasswordInProgress());
    try {
      await _api.changeOwnPassword(
        token,
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
      );
      emit(const ChangePasswordSucceeded());
    } on PeopleApiException catch (error) {
      emit(ChangePasswordFailed(error.message));
    }
  }
}
