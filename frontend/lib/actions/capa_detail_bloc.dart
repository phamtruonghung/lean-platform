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
}
