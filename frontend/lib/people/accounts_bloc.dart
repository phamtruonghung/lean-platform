/// Everyone already dealt with: the Accounts an administrator has admitted or
/// turned away, and the two things that can still be done to one — correcting
/// its role and Grants, and deactivating or reactivating it (issue #36).
///
/// The Approval queue's own Bloc is next door and deliberately separate: that
/// one is a queue that empties, this one is a register that does not.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'managed_account.dart';

sealed class AccountsEvent {
  const AccountsEvent();
}

/// Load the register: the Screen's first build, the retry a failed load
/// offers, and the re-read a finished correction asks for. One event, because
/// they are one act.
class AccountsRequested extends AccountsEvent {
  const AccountsRequested({this.notice});

  /// Carried through the reload so a correction's own report survives it.
  final String? notice;
}

/// Deactivate or reactivate an Account. The Screen has already confirmed a
/// deactivation by the time this exists — same contract as the Approval
/// queue's rejection event.
class AccountsActiveToggled extends AccountsEvent {
  const AccountsActiveToggled({required this.accountId, required this.isActive});
  final String accountId;
  final bool isActive;
}

/// The administrator has chosen a role and a Grant set for an Account already
/// dealt with once. Same contract as the Approval queue's own admission event:
/// the dialog decides, and the Bloc only ever sees a decision already made.
///
/// [expectedApprovalStatus] is the standing this row was read with — sent as
/// the server's precondition, so a correction aimed at a row another
/// administrator has since moved comes back as a 409 rather than a silent
/// overwrite.
class AccountsCorrectionConfirmed extends AccountsEvent {
  const AccountsCorrectionConfirmed({
    required this.accountId,
    required this.role,
    required this.expectedApprovalStatus,
    this.grants = const [],
  });
  final String accountId;
  final String role;
  final String expectedApprovalStatus;
  final List<Map<String, Object?>> grants;
}

sealed class AccountsState {
  const AccountsState();
}

class AccountsLoading extends AccountsState {
  const AccountsLoading();
}

class AccountsLoaded extends AccountsState {
  const AccountsLoaded({
    required this.accounts,
    this.busyId,
    this.correctingId,
    this.correctionFailure,
    this.notice,
  });

  /// Every Account the server sent, pending ones included — the Screen decides
  /// which it shows, so a later Screen reading the same Bloc is not forced
  /// into this one's choice.
  final List<ManagedAccount> accounts;

  /// The row whose activation change is in flight, if any.
  final String? busyId;

  /// The row whose correction is in flight, if any. Kept apart from [busyId]
  /// so the correction dialog can tell that *its own* act is the one still
  /// running, exactly as the admission dialog does with `admittingId`.
  final String? correctingId;

  /// Why the last correction did not land, if it did not. The correction
  /// dialog stays open and reports this; anything else — including a 409 — is
  /// a [notice] on the Screen and closes the dialog, because the list has
  /// already been re-read and the dialog's own copy of the row is stale.
  final String? correctionFailure;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [AccountsUnavailable].
  final String? notice;

  /// Everyone an administrator has already decided about — this Screen's list.
  List<ManagedAccount> get admitted => [
        for (final account in accounts)
          if (!account.isPending) account,
      ];
}

class AccountsUnavailable extends AccountsState {
  const AccountsUnavailable({required this.message});
  final String message;
}

/// Route-scoped, like `ApprovalQueueBloc` and unlike `AccountBloc`: one
/// Screen's reading of the server, re-read on arrival rather than restored
/// stale.
class AccountsBloc extends Bloc<AccountsEvent, AccountsState> {
  AccountsBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const AccountsLoading()) {
    on<AccountsRequested>(_onRequested);
    on<AccountsActiveToggled>(_onActiveToggled);
    on<AccountsCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  static const String alreadyMovedMessage =
      'Another administrator has already changed that Account. The list has been refreshed.';

  static String correctedMessage(String role, int grantCount) => grantCount == 0
      ? 'Now $role, with no Org Unit Grants.'
      : 'Now $role, with $grantCount Org Unit ${grantCount == 1 ? 'Grant' : 'Grants'}.';

  Future<void> _onRequested(AccountsRequested event, Emitter<AccountsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AccountsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final accounts = await _api.fetchAccounts(token);
      emit(AccountsLoaded(accounts: accounts, notice: event.notice));
    } on PeopleApiException catch (error) {
      emit(AccountsUnavailable(message: error.message));
    }
  }

  Future<void> _onActiveToggled(
    AccountsActiveToggled event,
    Emitter<AccountsState> emit,
  ) async {
    final current = state;
    if (current is! AccountsLoaded) return;
    // Reported, not silently dropped: a caller who can't see the row this
    // event was aimed at (a correction dialog watching a different id) has no
    // way to tell "ignored" apart from "nothing happened yet" otherwise, and
    // would be left waiting on a click that will never resolve.
    if (current.busyId != null || current.correctingId != null) {
      emit(
        AccountsLoaded(
          accounts: current.accounts,
          notice: 'Another action is already in progress. Try again in a moment.',
        ),
      );
      return;
    }

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(AccountsLoaded(accounts: current.accounts, notice: signedOutMessage));
      return;
    }

    emit(AccountsLoaded(accounts: current.accounts, busyId: event.accountId));
    try {
      await _api.setAccountActive(
        token,
        accountId: event.accountId,
        isActive: event.isActive,
      );
      // The response already says what the row became — no refetch for the
      // ordinary case, the same reasoning as the Approval queue's own writes.
      emit(
        AccountsLoaded(
          accounts: [
            for (final account in current.accounts)
              if (account.id == event.accountId)
                ManagedAccount(
                  id: account.id,
                  email: account.email,
                  displayName: account.displayName,
                  role: account.role,
                  isActive: event.isActive,
                  approvalStatus: account.approvalStatus,
                  grants: account.grants,
                )
              else
                account,
          ],
          notice: event.isActive
              ? 'That Account can sign in again.'
              : 'That Account can no longer sign in. Nothing was deleted.',
        ),
      );
    } on PeopleApiException catch (error) {
      emit(AccountsLoaded(accounts: current.accounts, notice: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    AccountsCorrectionConfirmed event,
    Emitter<AccountsState> emit,
  ) async {
    final current = state;
    if (current is! AccountsLoaded) return;
    // Reported as a correctionFailure, not silently dropped: the open dialog
    // only pops when correctingId has moved off its own id AND
    // correctionFailure is null (§listener below) — silently ignoring this
    // event instead would leave correctingId belonging to whichever OTHER
    // row is busy, which the dialog cannot distinguish from "my own
    // correction just landed", and it would wrongly close claiming success
    // for a save that never happened.
    if (current.busyId != null || current.correctingId != null) {
      emit(
        AccountsLoaded(
          accounts: current.accounts,
          correctionFailure: 'Another action is already in progress. Try again in a moment.',
        ),
      );
      return;
    }

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(AccountsLoaded(accounts: current.accounts, correctionFailure: signedOutMessage));
      return;
    }

    emit(AccountsLoaded(accounts: current.accounts, correctingId: event.accountId));
    try {
      await _api.admitAccount(
        token,
        accountId: event.accountId,
        role: event.role,
        grants: event.grants,
        expectedApprovalStatus: event.expectedApprovalStatus,
      );
      // Re-read rather than patched in place: the server owns what the Grant
      // set now is, down to the Site each Org Unit sits in, and this Screen
      // shows exactly that. One round trip, only after a correction lands.
      add(AccountsRequested(notice: correctedMessage(event.role, event.grants.length)));
    } on PeopleApiException catch (error) {
      if (error.statusCode == 409) {
        add(const AccountsRequested(notice: alreadyMovedMessage));
        return;
      }
      emit(AccountsLoaded(accounts: current.accounts, correctionFailure: error.message));
    }
  }
}
