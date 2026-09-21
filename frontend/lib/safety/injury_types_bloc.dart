/// The Injury type catalogue's own state (issue #224): the shared reference
/// data (ADR-0005) an injury classification draws on, and — on this Screen —
/// an administrator's own write surface over it (`POST`/`PATCH
/// /api/safety/injury-types`, injury-type-routes.js).
///
/// Route-scoped, like `ProductsBloc`, whose shape this mirrors event for event
/// and state for state: one Screen's own reading of the server, re-read on
/// arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'injury_type.dart';
import 'safety_api.dart';

sealed class InjuryTypesEvent {
  const InjuryTypesEvent();
}

/// Load the whole catalogue, deactivated rows included. Also the retry a
/// failed load offers.
class InjuryTypesStarted extends InjuryTypesEvent {
  const InjuryTypesStarted();
}

/// The add form has decided: a whole new Injury type. The dialog decides, the
/// Bloc only ever sees a decision already made — `ProductsAddConfirmed`'s own
/// contract.
class InjuryTypesAddConfirmed extends InjuryTypesEvent {
  const InjuryTypesAddConfirmed({required this.code, required this.name});

  final String code;
  final String name;
}

/// The correction form has decided: only the keys that actually changed, on
/// `updateInjuryType`'s (injury-types.js) `hasOwnProperty` idiom at the other
/// end. `isActive` rides in [changes] too — retiring or reactivating is a
/// correction, not a verb of its own, because there is no delete here.
class InjuryTypesCorrectionConfirmed extends InjuryTypesEvent {
  const InjuryTypesCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class InjuryTypesState {
  const InjuryTypesState();
}

class InjuryTypesLoading extends InjuryTypesState {
  const InjuryTypesLoading();
}

class InjuryTypesLoaded extends InjuryTypesState {
  const InjuryTypesLoaded({
    required this.injuryTypes,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<InjuryType> injuryTypes;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever dialog
  /// is open, which stays open so the caller can fix the field rather than
  /// retype the whole row.
  final String? mutationFailure;

  InjuryTypesLoaded copyWith({
    List<InjuryType>? injuryTypes,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      InjuryTypesLoaded(
        injuryTypes: injuryTypes ?? this.injuryTypes,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
      );
}

class InjuryTypesUnavailable extends InjuryTypesState {
  const InjuryTypesUnavailable({required this.message});

  final String message;
}

class InjuryTypesBloc extends Bloc<InjuryTypesEvent, InjuryTypesState> {
  InjuryTypesBloc({required SafetyApi safetyApi, required AuthGateway authGateway})
      : _api = safetyApi,
        _auth = authGateway,
        super(const InjuryTypesLoading()) {
    on<InjuryTypesStarted>(_onStarted);
    on<InjuryTypesAddConfirmed>(_onAddConfirmed);
    on<InjuryTypesCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final SafetyApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(InjuryTypesStarted event, Emitter<InjuryTypesState> emit) async {
    emit(const InjuryTypesLoading());
    await _readList(emit);
  }

  // Deactivated rows included: this Screen's whole purpose is reaching a
  // retired entry to reactivate it. The classify dialog reads the same
  // catalogue *without* them, which is what "excluded from the choices offered
  // to a recorder" means.
  Future<void> _readList(Emitter<InjuryTypesState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const InjuryTypesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final injuryTypes = await _api.fetchInjuryTypes(token, includeInactive: true);
      final settled = state;
      emit(
        settled is InjuryTypesLoaded
            ? settled.copyWith(injuryTypes: injuryTypes, isMutating: false)
            : InjuryTypesLoaded(injuryTypes: injuryTypes),
      );
    } on SafetyApiException catch (error) {
      emit(InjuryTypesUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(
    InjuryTypesAddConfirmed event,
    Emitter<InjuryTypesState> emit,
  ) async {
    final current = state;
    if (current is! InjuryTypesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createInjuryType(token, code: event.code, name: event.name);
      await _readList(emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! InjuryTypesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    InjuryTypesCorrectionConfirmed event,
    Emitter<InjuryTypesState> emit,
  ) async {
    final current = state;
    if (current is! InjuryTypesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateInjuryType(token, event.id, event.changes);
      await _readList(emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! InjuryTypesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
