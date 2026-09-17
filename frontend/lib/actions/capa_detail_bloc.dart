/// One CAPA's own read (issue #209): its number, its team, what the
/// investigation says the problem is, and the Concern it is about — with the
/// Concern's Containments, Countermeasures and Preventive actions and every
/// phase each one has been round.
///
/// Route-scoped like `ActionDetailBloc`, and separate from it for the same
/// reason: the read is one record rather than the register, and a caller who
/// lands here directly (a link sent to a colleague, a refresh) never loads the
/// Site's list first.
///
/// **The chains are written through this Bloc (issue #210).** The two 5 Why
/// chains, the position of a Why in its chain, and which Why is the chain's
/// confirmed root cause all live on the CAPA this Screen is already showing, so
/// the three writes are events here rather than a second state machine beside
/// it: adding a Why, changing one (what it says, where it sits, whether it is
/// the root cause) and removing one. Each answers with the whole CAPA as it now
/// reads, so the Screen is repainted from the server's own answer rather than
/// by a second read — and the dialogs watch `isMutating`/`mutationFailure` to
/// know whether their own request landed.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'actions_api.dart';
import 'capa.dart';

sealed class CapaDetailEvent {
  const CapaDetailEvent();
}

/// Read the CAPA this address names. Its own id, carried down from the route
/// rather than read off a state, so a retry asks for the same record.
class CapaDetailStarted extends CapaDetailEvent {
  const CapaDetailStarted(this.capaId);

  final String capaId;
}

/// A Why was added to one of the two chains (issue #210), at the next position
/// of that chain.
class CapaDetailWhyAdded extends CapaDetailEvent {
  const CapaDetailWhyAdded({required this.chain, required this.statement});

  final String chain;
  final String statement;
}

/// One Why was changed: what it says, where it sits in its chain, and whether
/// it is the chain's confirmed root cause.
///
/// Each field is null when the caller did not ask for it, so a form that
/// changed one thing sends one thing — the same partial-update shape the API
/// takes.
class CapaDetailWhyChanged extends CapaDetailEvent {
  const CapaDetailWhyChanged({required this.whyId, this.statement, this.sequence, this.isRoot});

  final String whyId;
  final String? statement;

  /// The position to move the Why to within its own chain, 1-based.
  final int? sequence;

  /// Mark this Why as the chain's confirmed root cause (`true`), or clear the
  /// mark (`false`). Marking a second Why replaces the first — the chained
  /// conclusion the API keeps, not a refusal.
  final bool? isRoot;
}

/// One Why was removed from a chain (issue #210). The server renumbers what is
/// left, so the chain stays contiguous.
class CapaDetailWhyRemoved extends CapaDetailEvent {
  const CapaDetailWhyRemoved(this.whyId);

  final String whyId;
}

/// A candidate cause was recorded on the fishbone (issue #213), under one 6M
/// category. A new cause is always a `candidate`: deciding it is a separate
/// act with its own evidence.
class CapaDetailCauseAdded extends CapaDetailEvent {
  const CapaDetailCauseAdded({required this.category, required this.statement});

  /// The one 6M category the cause hangs from — which is the decision the
  /// caller made by opening the address this form sits at.
  final String category;
  final String statement;
}

/// One candidate cause was changed (issue #213): which of the six it is filed
/// under, what it says, and the verdict with the evidence for it.
///
/// Each field is null when the caller did not ask for it, so a form that
/// changed one thing sends one thing — the same partial-update shape the API
/// takes. `verdict` and `evidenceNote` normally travel together, because the
/// API refuses a decision without its evidence.
class CapaDetailCauseChanged extends CapaDetailEvent {
  const CapaDetailCauseChanged({
    required this.causeId,
    this.category,
    this.statement,
    this.verdict,
    this.evidenceNote,
  });

  final String causeId;
  final String? category;
  final String? statement;

  /// `candidate`, `confirmed` or `ruled_out`.
  final String? verdict;

  /// The evidence for `verdict`, in the caller's own words.
  final String? evidenceNote;
}

/// One candidate cause was removed from the fishbone (issue #213).
class CapaDetailCauseRemoved extends CapaDetailEvent {
  const CapaDetailCauseRemoved(this.causeId);

  final String causeId;
}

/// One of the two chains was started from a confirmed candidate cause (issue
/// #213) — the chain's first Why.
///
/// The statement is optional: what the chain starts from is the cause the
/// evidence confirmed, and its own sentence is what the server writes when the
/// caller does not phrase it differently.
class CapaDetailWhyStartedFromCause extends CapaDetailEvent {
  const CapaDetailWhyStartedFromCause({
    required this.causeId,
    required this.chain,
    this.statement,
  });

  final String causeId;

  /// `occurrence` or `escape` — the chain this Why heads.
  final String chain;
  final String? statement;
}

/// The effectiveness check was recorded (issue #211) — the verdict, with the
/// note that is its evidence.
///
/// One event for both verdicts rather than two, because they are one act with
/// two outcomes: the fields the request carries are identical, and what differs
/// is what the server does with them — close the investigation, or send the
/// Concern round again. The verifier and the time are not sent at all: they are
/// the caller's own Account and the server's clock.
class CapaDetailEffectivenessRecorded extends CapaDetailEvent {
  const CapaDetailEffectivenessRecorded({required this.outcome, required this.note});

  /// `effective` or `not_effective`, the two values the API's own set has.
  final String outcome;
  final String note;
}

sealed class CapaDetailState {
  const CapaDetailState();
}

class CapaDetailLoading extends CapaDetailState {
  const CapaDetailLoading();
}

class CapaDetailLoaded extends CapaDetailState {
  const CapaDetailLoaded(this.capa, {this.isMutating = false, this.mutationFailure, this.notice});

  final Capa capa;

  /// A write to the chains is in flight. What the dialogs watch: a dialog that
  /// asked for a change waits while this is true, then either reports the
  /// refusal or closes because the Screen behind it has the new state.
  final bool isMutating;

  /// Why the last change did not land, in the server's own words. Reported by
  /// whichever dialog made it, which stays where it was so the caller can
  /// correct the one value — the same shape `NonconformanceDetailLoaded` uses.
  final String? mutationFailure;

  /// What the last change that landed did — the one sentence the Screen shows
  /// once the dialog that asked has closed.
  final String? notice;

  CapaDetailLoaded copyWith({
    Capa? capa,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      CapaDetailLoaded(
        capa ?? this.capa,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward: a refusal belongs to the
        // request that got it, and a notice to the change that landed.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class CapaDetailUnavailable extends CapaDetailState {
  const CapaDetailUnavailable({required this.message});

  final String message;
}

class CapaDetailBloc extends Bloc<CapaDetailEvent, CapaDetailState> {
  CapaDetailBloc({required ActionsApi actionsApi, required AuthGateway authGateway})
      : _actions = actionsApi,
        _auth = authGateway,
        super(const CapaDetailLoading()) {
    on<CapaDetailStarted>(_onStarted);
    on<CapaDetailWhyAdded>(_onWhyAdded);
    on<CapaDetailWhyChanged>(_onWhyChanged);
    on<CapaDetailWhyRemoved>(_onWhyRemoved);
    on<CapaDetailCauseAdded>(_onCauseAdded);
    on<CapaDetailCauseChanged>(_onCauseChanged);
    on<CapaDetailCauseRemoved>(_onCauseRemoved);
    on<CapaDetailWhyStartedFromCause>(_onWhyStartedFromCause);
    on<CapaDetailEffectivenessRecorded>(_onEffectivenessRecorded);
  }

  final ActionsApi _actions;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  String? _capaId;

  Future<void> _onStarted(CapaDetailStarted event, Emitter<CapaDetailState> emit) async {
    _capaId = event.capaId;
    emit(const CapaDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CapaDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      emit(CapaDetailLoaded(await _actions.fetchCapa(token, event.capaId)));
    } on ActionsApiException catch (error) {
      emit(CapaDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onWhyAdded(CapaDetailWhyAdded event, Emitter<CapaDetailState> emit) async {
    final capaId = _capaId;
    if (capaId == null) return;
    // A Why with nothing to say is not sent to be refused: the screen's own
    // submit gate is the same rule said again where it cannot be bypassed.
    if (event.statement.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _actions.addCapaWhy(
        token,
        capaId,
        chain: event.chain,
        statement: event.statement.trim(),
      ),
      notice: 'The Why was added to the chain.',
    );
  }

  Future<void> _onWhyChanged(CapaDetailWhyChanged event, Emitter<CapaDetailState> emit) async {
    final capaId = _capaId;
    if (capaId == null) return;
    if (event.statement == null && event.sequence == null && event.isRoot == null) return;
    if (event.statement != null && event.statement!.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _actions.updateCapaWhy(
        token,
        capaId,
        event.whyId,
        statement: event.statement?.trim(),
        sequence: event.sequence,
        isRoot: event.isRoot,
      ),
      notice: _changedNotice(event),
    );
  }

  Future<void> _onWhyRemoved(CapaDetailWhyRemoved event, Emitter<CapaDetailState> emit) async {
    final capaId = _capaId;
    if (capaId == null) return;
    await _mutate(
      emit,
      (token) => _actions.removeCapaWhy(token, capaId, event.whyId),
      notice: 'The Why was removed, and the chain renumbered around the gap.',
    );
  }

  /// Records a candidate cause on the fishbone (issue #213). A cause with
  /// nothing to say is not sent to be refused — the same guard the add-Why
  /// handler makes, for the same reason.
  Future<void> _onCauseAdded(CapaDetailCauseAdded event, Emitter<CapaDetailState> emit) async {
    final capaId = _capaId;
    if (capaId == null) return;
    if (!capaCauseCategoryOrder.contains(event.category)) return;
    if (event.statement.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _actions.addCapaCause(
        token,
        capaId,
        category: event.category,
        statement: event.statement.trim(),
      ),
      notice: 'The candidate cause is on the fishbone.',
    );
  }

  /// Changes one candidate cause (issue #213) and repaints the Screen from the
  /// answer.
  ///
  /// One guard is said again here rather than left to the server, because a
  /// form must not send what it knows will be refused: a cause cannot be
  /// decided without the evidence for it, and the verdict dialog's own submit
  /// gate is the same rule said where the caller can see it. Everything else —
  /// the authority, the CAPA's status, the category set — is the server's, and
  /// its refusal comes back as `mutationFailure` beside the form.
  Future<void> _onCauseChanged(
    CapaDetailCauseChanged event,
    Emitter<CapaDetailState> emit,
  ) async {
    final capaId = _capaId;
    if (capaId == null) return;
    if (event.category == null &&
        event.statement == null &&
        event.verdict == null &&
        event.evidenceNote == null) {
      return;
    }
    if (event.statement != null && event.statement!.trim().isEmpty) return;
    if (event.verdict != null && !capaCauseDecisions.contains(event.verdict)) return;
    if (event.evidenceNote != null && event.evidenceNote!.trim().isEmpty) return;

    await _mutate(
      emit,
      (token) => _actions.updateCapaCause(
        token,
        capaId,
        event.causeId,
        category: event.category,
        statement: event.statement?.trim(),
        verdict: event.verdict,
        evidenceNote: event.evidenceNote?.trim(),
      ),
      notice: _causeChangedNotice(event),
    );
  }

  /// Removes one candidate cause from the fishbone (issue #213).
  Future<void> _onCauseRemoved(CapaDetailCauseRemoved event, Emitter<CapaDetailState> emit) async {
    final capaId = _capaId;
    if (capaId == null) return;
    await _mutate(
      emit,
      (token) => _actions.removeCapaCause(token, capaId, event.causeId),
      notice: 'The cause was removed from the fishbone.',
    );
  }

  /// Starts one of the two chains from a confirmed candidate cause (issue
  /// #213) — the chain's first Why, whose statement is the cause's own unless
  /// the caller phrased it differently.
  ///
  /// The two rules that make this act possible at all are the server's to
  /// refuse (the cause must be confirmed, the chain must not have started);
  /// what this handler declines to send is only what the form already knows is
  /// empty, which is a statement of nothing.
  Future<void> _onWhyStartedFromCause(
    CapaDetailWhyStartedFromCause event,
    Emitter<CapaDetailState> emit,
  ) async {
    final capaId = _capaId;
    if (capaId == null) return;
    if (!capaChainOrder.contains(event.chain)) return;
    if (event.statement != null && event.statement!.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _actions.startCapaWhyFromCause(
        token,
        capaId,
        event.causeId,
        chain: event.chain,
        statement: event.statement?.trim(),
      ),
      notice: 'The chain was started from the confirmed cause.',
    );
  }

  /// Records the effectiveness check (issue #211) and repaints the Screen from
  /// the answer — the whole investigation, which now says either that it is
  /// closed with a verifier and a note, or that its Concern is open again in
  /// its next cycle.
  ///
  /// The two guards the server enforces are said again here because a form must
  /// not send what it knows will be refused: a note that says nothing is not
  /// sent (the dialog's own submit gate), and an outcome that is not one of the
  /// two is not sent either. Everything else — the authority, the team-lead
  /// rule, whether the Concern has closed, whether both chains concluded — is
  /// the server's to refuse, and its refusal comes back as `mutationFailure`
  /// beside the form the caller was filling in.
  Future<void> _onEffectivenessRecorded(
    CapaDetailEffectivenessRecorded event,
    Emitter<CapaDetailState> emit,
  ) async {
    final capaId = _capaId;
    if (capaId == null) return;
    if (event.note.trim().isEmpty) return;
    if (!capaEffectivenessOutcomeOrder.contains(event.outcome)) return;

    await _mutate(
      emit,
      (token) => _actions.recordEffectivenessCheck(
        token,
        capaId,
        outcome: event.outcome,
        note: event.note.trim(),
      ),
      notice: event.outcome == 'effective'
          ? 'The investigation is closed, and the fix is recorded as having held.'
          : 'The check did not hold, so the Concern is open again in its next cycle.',
    );
  }

  /// One write, one answer: the CAPA the server returned, or the reason it
  /// refused. The state is repainted from the answer rather than by a second
  /// read — every write in this slice answers with the whole investigation —
  /// and the failure is kept beside the record the Screen is still showing, so
  /// a dialog can report it without the chains disappearing.
  Future<void> _mutate(
    Emitter<CapaDetailState> emit,
    Future<Capa> Function(String token) write, {
    required String notice,
  }) async {
    final current = state;
    if (current is! CapaDetailLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CapaDetailUnavailable(message: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true));
    try {
      emit(CapaDetailLoaded(await write(token), notice: notice));
    } on ActionsApiException catch (error) {
      emit(current.copyWith(mutationFailure: error.message));
    }
  }

  /// One sentence for the change that landed. A dialog sends one field, so this
  /// normally has one thing to say; a request that carried more is announced by
  /// the strongest of them, because the Screen's notice is one sentence and
  /// "the Why was revised" is the fact a reader wants first.
  static String _changedNotice(CapaDetailWhyChanged event) {
    if (event.statement != null) return 'The Why was revised.';
    if (event.sequence != null) return 'The chain was reordered.';
    return event.isRoot == true
        ? 'That Why is the confirmed root cause of its chain.'
        : 'The confirmed root cause was cleared.';
  }

  /// One sentence for the change that landed to a candidate cause (issue #213).
  /// A verdict is the strongest thing a change can say — it is the decision the
  /// fishbone exists for — so it wins over a revision to the sentence or the
  /// category, and the evidence-only case is what is left when nothing else
  /// changed.
  static String _causeChangedNotice(CapaDetailCauseChanged event) {
    if (event.verdict == 'confirmed') return 'That cause is confirmed by its evidence.';
    if (event.verdict == 'ruled_out') return 'That cause is ruled out by its evidence.';
    if (event.verdict == 'candidate') return 'That cause is a candidate again.';
    if (event.category != null) return 'The cause was re-filed under another category.';
    if (event.statement != null) return 'The cause was revised.';
    return 'The evidence was revised.';
  }
}
