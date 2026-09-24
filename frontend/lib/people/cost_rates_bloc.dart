/// The cost rate catalogue's own state (issue #252): the money the Platform
/// costs things at, and — on this Screen — an administrator's own write surface
/// over it (`POST`/`PATCH /api/people/cost-rates`, plus the revision route,
/// cost-rate-routes.js).
///
/// `JobRolesBloc`'s shape, event for event and state for state, with two
/// additions the versioned catalogue needs:
///
///   - the list of scopes a rate may be attached to is read alongside the
///     catalogue, because the form picks one rather than typing an id
///     (ADR-0023). It is read once on arrival and kept; a failed scope read
///     leaves the catalogue readable and only closes the write affordances,
///     since browsing a rate never needs it.
///   - a revision is its own event, because it is its own act: closing the old
///     period and opening a new one, in one server transaction.
///
/// Route-scoped: one Screen's own reading of the server, re-read on arrival
/// rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'cost_rate.dart';

sealed class CostRatesEvent {
  const CostRatesEvent();
}

/// Load the catalogue and the scopes a rate can be attached to. Also the retry
/// a failed load offers.
class CostRatesStarted extends CostRatesEvent {
  const CostRatesStarted();
}

/// The add form has decided: a whole new rate. The dialog decides, the Bloc
/// only ever sees a decision already made — `JobRolesAddConfirmed`'s own
/// contract. [body] is the request as the form assembled it.
class CostRatesAddConfirmed extends CostRatesEvent {
  const CostRatesAddConfirmed({required this.body});

  final Map<String, Object?> body;
}

/// The correction form has decided: only the keys that actually changed, on
/// `updateCostRate`'s (cost-rates.js) `hasOwnProperty` idiom at the other end.
/// Closing a rate rides in here too — it is setting `effectiveTo`, not a verb
/// of its own, because there is no delete in this catalogue.
class CostRatesCorrectionConfirmed extends CostRatesEvent {
  const CostRatesCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

/// The revision form has decided: a new amount from a date. This closes the row
/// it names and opens a new one; the old row stays readable and still resolves
/// for earlier dates.
class CostRatesRevisionConfirmed extends CostRatesEvent {
  const CostRatesRevisionConfirmed({required this.id, required this.body});

  final String id;
  final Map<String, Object?> body;
}

sealed class CostRatesState {
  const CostRatesState();
}

class CostRatesLoading extends CostRatesState {
  const CostRatesLoading();
}

class CostRatesLoaded extends CostRatesState {
  const CostRatesLoaded({
    required this.costRates,
    this.scopes = const [],
    this.scopesFailure,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<CostRate> costRates;

  /// Everything a rate may be scoped to. Empty with a [scopesFailure] set means
  /// the list could not be read — the form blocks submission rather than
  /// falling back to a typed id (ADR-0023 point 6).
  final List<CostRateScope> scopes;
  final String? scopesFailure;

  /// An add, a correction or a revision is in flight — one flag, not three:
  /// this Screen has one mutation at a time.
  final bool isMutating;

  /// Why the last write did not land. Reported by whichever dialog is open,
  /// which stays open so the caller can fix the field rather than retype the
  /// whole row.
  final String? mutationFailure;

  CostRatesLoaded copyWith({
    List<CostRate>? costRates,
    List<CostRateScope>? scopes,
    String? scopesFailure,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      CostRatesLoaded(
        costRates: costRates ?? this.costRates,
        scopes: scopes ?? this.scopes,
        scopesFailure: scopesFailure ?? this.scopesFailure,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
      );
}

class CostRatesUnavailable extends CostRatesState {
  const CostRatesUnavailable({required this.message});

  final String message;
}

class CostRatesBloc extends Bloc<CostRatesEvent, CostRatesState> {
  CostRatesBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const CostRatesLoading()) {
    on<CostRatesStarted>(_onStarted);
    on<CostRatesAddConfirmed>(_onAddConfirmed);
    on<CostRatesCorrectionConfirmed>(_onCorrectionConfirmed);
    on<CostRatesRevisionConfirmed>(_onRevisionConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(CostRatesStarted event, Emitter<CostRatesState> emit) async {
    emit(const CostRatesLoading());

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CostRatesUnavailable(message: signedOutMessage));
      return;
    }

    List<CostRate> costRates;
    try {
      costRates = await _api.fetchCostRates(token);
    } on PeopleApiException catch (error) {
      emit(CostRatesUnavailable(message: error.message));
      return;
    }

    // The scope list is the form's, not the page's: a failure here leaves the
    // catalogue perfectly readable and only closes the writes.
    List<CostRateScope> scopes = const [];
    String? scopesFailure;
    try {
      scopes = await _api.fetchCostRateScopes(token);
    } on PeopleApiException catch (error) {
      scopesFailure = error.message;
    }

    emit(CostRatesLoaded(costRates: costRates, scopes: scopes, scopesFailure: scopesFailure));
  }

  Future<void> _readList(Emitter<CostRatesState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CostRatesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final costRates = await _api.fetchCostRates(token);
      final settled = state;
      emit(
        settled is CostRatesLoaded
            ? settled.copyWith(costRates: costRates, isMutating: false)
            : CostRatesLoaded(costRates: costRates),
      );
    } on PeopleApiException catch (error) {
      emit(CostRatesUnavailable(message: error.message));
    }
  }

  /// Every write takes the same three steps — refuse if one is already in
  /// flight or the session has ended, send, then re-read — so they are written
  /// once here rather than three times below.
  Future<void> _write(
    Emitter<CostRatesState> emit,
    Future<void> Function(String token) send,
  ) async {
    final current = state;
    if (current is! CostRatesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await send(token);
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! CostRatesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onAddConfirmed(CostRatesAddConfirmed event, Emitter<CostRatesState> emit) =>
      _write(emit, (token) => _api.createCostRate(token, event.body));

  Future<void> _onCorrectionConfirmed(
    CostRatesCorrectionConfirmed event,
    Emitter<CostRatesState> emit,
  ) =>
      _write(emit, (token) => _api.updateCostRate(token, event.id, event.changes));

  Future<void> _onRevisionConfirmed(
    CostRatesRevisionConfirmed event,
    Emitter<CostRatesState> emit,
  ) =>
      _write(emit, (token) => _api.reviseCostRate(token, event.id, event.body));
}
