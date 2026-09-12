import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'pending_account.dart';

sealed class ApprovalQueueEvent {
  const ApprovalQueueEvent();
}

/// Load the queue: the Screen's first build, and the retry a failed load
/// offers. The same event for both, because they are the same act.
class ApprovalQueueRequested extends ApprovalQueueEvent {
  const ApprovalQueueRequested();
}

/// The administrator has already confirmed. The dialog is the Screen's job;
/// by the time this event exists the decision is made.
class ApprovalQueueRejectionConfirmed extends ApprovalQueueEvent {
  const ApprovalQueueRejectionConfirmed(this.accountId);
  final String accountId;
}

/// The administrator has chosen a role and confirmed the admission. Same
/// contract as the rejection above: the dialog decides, and the Bloc only ever
/// sees a decision already made.
///
/// [grants] is the complete Grant set the Account will hold — the server
/// replaces the whole set on every Approval — already carrying each entry's
/// level as `canWrite`. Empty is a real answer, not a missing one.
class ApprovalQueueAdmissionConfirmed extends ApprovalQueueEvent {
  const ApprovalQueueAdmissionConfirmed({
    required this.accountId,
    required this.role,
    this.grants = const [],
    this.employeeId,
  });
  final String accountId;
  final String role;
  final List<Map<String, Object?>> grants;

  /// The Employee confirmed at Approval — the suggestion, accepted or
  /// overridden, or null for no Employee at all (issue #116, ADR-0022). Sent
  /// through to [PeopleApi.admitAccount] exactly as given: null here means no
  /// `employeeId` key reaches the wire at all, not an explicit clear.
  final String? employeeId;
}

sealed class ApprovalQueueState {
  const ApprovalQueueState();
}

class ApprovalQueueLoading extends ApprovalQueueState {
  const ApprovalQueueLoading();
}

/// The queue as it last read. An empty [accounts] is not a state of its own:
/// "nobody is waiting" is a value this state can hold, not a different place
/// in the machine — and keeping it here is what lets the Screen tell it
/// apart from [ApprovalQueueUnavailable] with no extra plumbing.
class ApprovalQueueLoaded extends ApprovalQueueState {
  const ApprovalQueueLoaded({
    required this.accounts,
    this.rejectingId,
    this.admittingId,
    this.notice,
  });

  final List<PendingAccount> accounts;

  /// The row whose rejection is in flight, if any.
  final String? rejectingId;

  /// The row whose admission is in flight, if any. Kept apart from
  /// [rejectingId] rather than generalised into one "busy" field: the two acts
  /// have different affordances in the row, and the admission dialog needs to
  /// know that *its own* act is the one still running.
  final String? admittingId;

  /// What the last decision had to say for itself — the "someone else got
  /// there first" report, or a rejection or admission that failed outright.
  /// Never the failure of a *load*: that is [ApprovalQueueUnavailable].
  final String? notice;

  /// Whether any decision at all is in flight. One at a time, by design: the
  /// admission dialog is modal, so a second decision cannot be started under
  /// it.
  bool get isBusy => rejectingId != null || admittingId != null;
}

class ApprovalQueueUnavailable extends ApprovalQueueState {
  const ApprovalQueueUnavailable({required this.message});
  final String message;
}

/// Lives and dies with the Approval queue Screen, unlike `AccountBloc`: there
/// is nothing app-wide about a list one Screen reads, and a queue that
/// outlived its Screen would go stale unnoticed.
class ApprovalQueueBloc extends Bloc<ApprovalQueueEvent, ApprovalQueueState> {
  ApprovalQueueBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const ApprovalQueueLoading()) {
    on<ApprovalQueueRequested>(_onRequested);
    on<ApprovalQueueRejectionConfirmed>(_onRejectionConfirmed);
    on<ApprovalQueueAdmissionConfirmed>(_onAdmissionConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String alreadyDecidedMessage =
      'Another administrator has already dealt with that Account. The queue has been refreshed.';

  /// Confirms the outcome, and says what was actually granted: the role, and
  /// how much of the plant it was given — an admission with no Grants at all
  /// is a real outcome and should not read like a complete one.
  static String admittedMessage(String role, int grantCount) => grantCount == 0
      ? 'Admitted to the Platform as $role, with no Org Unit Grants.'
      : 'Admitted to the Platform as $role, with $grantCount Org Unit '
          '${grantCount == 1 ? 'Grant' : 'Grants'}.';

  Future<void> _onRequested(
    ApprovalQueueRequested event,
    Emitter<ApprovalQueueState> emit,
  ) async {
    emit(const ApprovalQueueLoading());
    await _load(emit);
  }

  Future<void> _onRejectionConfirmed(
    ApprovalQueueRejectionConfirmed event,
    Emitter<ApprovalQueueState> emit,
  ) async {
    final current = state;
    if (current is! ApprovalQueueLoaded || current.isBusy) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(ApprovalQueueLoaded(accounts: current.accounts, notice: signedOutMessage));
      return;
    }

    emit(ApprovalQueueLoaded(accounts: current.accounts, rejectingId: event.accountId));

    try {
      await _api.rejectPendingAccount(token, accountId: event.accountId);
      // The row is gone because this request is what removed it — no refetch
      // for the ordinary case, which would cost a round trip to learn what
      // the response already said.
      emit(
        ApprovalQueueLoaded(
          accounts: [
            for (final account in current.accounts)
              if (account.id != event.accountId) account,
          ],
        ),
      );
    } on PeopleApiException catch (error) {
      if (error.statusCode == 409) {
        // Somebody else decided first, so this list is stale by definition —
        // the whole queue is re-read rather than guessing which rows moved.
        await _load(emit, notice: alreadyDecidedMessage);
        return;
      }
      emit(ApprovalQueueLoaded(accounts: current.accounts, notice: error.message));
    }
  }

  Future<void> _onAdmissionConfirmed(
    ApprovalQueueAdmissionConfirmed event,
    Emitter<ApprovalQueueState> emit,
  ) async {
    final current = state;
    // Refuses a second decision while one is running, so a double dispatch
    // cannot become a second request even if a Screen let one through.
    if (current is! ApprovalQueueLoaded || current.isBusy) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(ApprovalQueueLoaded(accounts: current.accounts, notice: signedOutMessage));
      return;
    }

    emit(ApprovalQueueLoaded(accounts: current.accounts, admittingId: event.accountId));

    try {
      await _api.admitAccount(
        token,
        accountId: event.accountId,
        role: event.role,
        grants: event.grants,
        expectedApprovalStatus: 'pending',
        employeeId: event.employeeId,
      );
      // The row is gone because this request is what removed it — the same
      // reasoning as the rejection above: no refetch for the ordinary case.
      emit(
        ApprovalQueueLoaded(
          accounts: [
            for (final account in current.accounts)
              if (account.id != event.accountId) account,
          ],
          notice: admittedMessage(event.role, event.grants.length),
        ),
      );
    } on PeopleApiException catch (error) {
      // A 409 here is ordinarily "someone else already dealt with this row"
      // (requireApprovalStatusUnchanged, service.js) — but issue #116 gives
      // `employeeId` two 409s of its own (Departed, already linked to a
      // different Account), which `approveAccount` only ever reaches once
      // the approval-status precondition has already passed. The two never
      // collide within one call, so distinguishing by the refusal's own
      // `error.code` is exact, not a heuristic (issue #119 replaced the
      // original message-text match with this) — see `isEmployeeLinkRefusal`'s
      // own header.
      if (error.statusCode == 409 && !isEmployeeLinkRefusal(error.code)) {
        await _load(emit, notice: alreadyDecidedMessage);
        return;
      }
      emit(ApprovalQueueLoaded(accounts: current.accounts, notice: error.message));
    }
  }

  Future<void> _load(Emitter<ApprovalQueueState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ApprovalQueueUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final accounts = await _api.fetchPendingAccounts(token);
      emit(ApprovalQueueLoaded(accounts: accounts, notice: notice));
    } on PeopleApiException catch (error) {
      emit(ApprovalQueueUnavailable(message: error.message));
    }
  }
}

/// The two Employee-link refusal codes `requireLinkableEmployee` (service.js)
/// raises with its 409s — distinct from `APPROVAL_STATUS_CHANGED`, the
/// approval-status precondition's own 409 code (issue #119). `EMPLOYEE_NOT_FOUND`
/// is not one of these: `requireLinkableEmployee` answers that one 404, which
/// [ApprovalQueueBloc]'s own 409-only check below never reaches.
const _employeeDepartedCode = 'EMPLOYEE_DEPARTED';
const _employeeAlreadyLinkedCode = 'EMPLOYEE_ALREADY_LINKED';

/// Whether a 409's own code is one of the two Employee-link refusals above,
/// rather than the approval-status precondition's `APPROVAL_STATUS_CHANGED`
/// (issue #119, replacing the message-text match issue #116 originally used —
/// see this function's own history for why that was exact rather than a
/// heuristic, but still a message a reworded server string could silently
/// break). [code] is null for a 409 carrying no code at all, which this
/// treats as "not an Employee-link refusal" — every 409 requireLinkableEmployee
/// or requireApprovalStatusUnchanged raises carries one.
bool isEmployeeLinkRefusal(String? code) =>
    code == _employeeDepartedCode || code == _employeeAlreadyLinkedCode;
