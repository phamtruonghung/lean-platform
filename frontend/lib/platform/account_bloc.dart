import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import 'auth_gateway.dart';

sealed class AccountEvent {
  const AccountEvent();
}

class AccountSessionChanged extends AccountEvent {
  const AccountSessionChanged(this.accessToken);
  final String? accessToken;
}

class AccountRefreshRequested extends AccountEvent {
  const AccountRefreshRequested();
}

class AccountSignOutRequested extends AccountEvent {
  const AccountSignOutRequested();
}

sealed class AccountState {
  const AccountState();
}

class AccountSignedOut extends AccountState {
  const AccountSignedOut();
}

class AccountResolving extends AccountState {
  const AccountResolving();
}

class AccountAwaitingApproval extends AccountState {
  const AccountAwaitingApproval({required this.email});
  final String email;
}

class AccountApproved extends AccountState {
  const AccountApproved({required this.account});
  final AccountActive account;
}

class AccountUnavailable extends AccountState {
  const AccountUnavailable({required this.message});
  final String message;
}

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  AccountBloc({required AuthGateway authGateway, required PeopleApi peopleApi})
      : _auth = authGateway,
        _api = peopleApi,
        super(
          authGateway.currentAccessToken == null
              ? const AccountSignedOut()
              : const AccountResolving(),
        ) {
    on<AccountSessionChanged>(_onSessionChanged);
    on<AccountRefreshRequested>(_onRefreshRequested);
    on<AccountSignOutRequested>(_onSignOutRequested);

    _subscription = _auth.accessTokenChanges.distinct().listen(
      (token) => add(AccountSessionChanged(token)),
    );
  }

  final AuthGateway _auth;
  final PeopleApi _api;
  late final StreamSubscription<String?> _subscription;

  Future<void> _onSessionChanged(AccountSessionChanged event, Emitter<AccountState> emit) async {
    final token = event.accessToken;
    if (token == null) {
      emit(const AccountSignedOut());
      return;
    }
    await _resolve(token, emit);
  }

  Future<void> _onRefreshRequested(AccountRefreshRequested event, Emitter<AccountState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AccountSignedOut());
      return;
    }
    await _resolve(token, emit);
  }

  Future<void> _onSignOutRequested(AccountSignOutRequested event, Emitter<AccountState> emit) async {
    emit(const AccountSignedOut());
    await _auth.signOut();
  }

  Future<void> _resolve(String token, Emitter<AccountState> emit) async {
    final hadAccount = state is AccountApproved || state is AccountAwaitingApproval;
    if (!hadAccount) emit(const AccountResolving());

    try {
      final status = await _api.fetchMe(token);
      emit(
        switch (status) {
          AccountPendingApproval(email: final email) => AccountAwaitingApproval(email: email),
          final AccountActive account => AccountApproved(account: account),
        },
      );
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        emit(const AccountSignedOut());
        await _auth.signOut();
        return;
      }
      emit(AccountUnavailable(message: error.message));
    }
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
