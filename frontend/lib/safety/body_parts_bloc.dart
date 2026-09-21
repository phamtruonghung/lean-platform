/// The Body part catalogue's own state (issue #224): where on the body an
/// injury was, in one list shared by every Site (ADR-0005), and — on this
/// Screen — an administrator's own write surface over it (`POST`/`PATCH
/// /api/safety/body-parts`, body-part-routes.js).
///
/// `BodyPartsBloc`'s shape exactly, with one field more on the add event:
/// a Body part is filed under a region, which is a value with a known set and
/// so is chosen rather than typed (ADR-0023).
///
/// Route-scoped, like `ProductsBloc`, whose shape this mirrors event for event
/// and state for state: one Screen's own reading of the server, re-read on
/// arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'body_part.dart';
import 'safety_api.dart';

sealed class BodyPartsEvent {
  const BodyPartsEvent();
}

/// Load the whole catalogue, deactivated rows included. Also the retry a
/// failed load offers.
class BodyPartsStarted extends BodyPartsEvent {
  const BodyPartsStarted();
}

/// The add form has decided: a whole new Injury type. The dialog decides, the
/// Bloc only ever sees a decision already made — `ProductsAddConfirmed`'s own
/// contract.
class BodyPartsAddConfirmed extends BodyPartsEvent {
  const BodyPartsAddConfirmed({
    required this.code,
    required this.name,
    required this.region,
  });

  final String code;
  final String name;

  /// One of `BodyPartRegion.values` — the baseline's own CHECK, chosen from a
  /// dropdown rather than typed (ADR-0023).
  final String region;
}

/// The correction form has decided: only the keys that actually changed, on
/// `updateBodyPart`'s (body-parts.js) `hasOwnProperty` idiom at the other
/// end. A Body part's region rides in [changes] too — unlike a Product's unit
/// of measure, it IS correctable, because filing a part under the wrong
/// region is a mistake the catalogue must be able to fix. `isActive` rides in [changes] too — retiring or reactivating is a
/// correction, not a verb of its own, because there is no delete here.
class BodyPartsCorrectionConfirmed extends BodyPartsEvent {
  const BodyPartsCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class BodyPartsState {
  const BodyPartsState();
}

class BodyPartsLoading extends BodyPartsState {
  const BodyPartsLoading();
}

class BodyPartsLoaded extends BodyPartsState {
  const BodyPartsLoaded({
    required this.bodyParts,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<BodyPart> bodyParts;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever dialog
  /// is open, which stays open so the caller can fix the field rather than
  /// retype the whole row.
  final String? mutationFailure;

  BodyPartsLoaded copyWith({
    List<BodyPart>? bodyParts,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      BodyPartsLoaded(
        bodyParts: bodyParts ?? this.bodyParts,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
      );
}

class BodyPartsUnavailable extends BodyPartsState {
  const BodyPartsUnavailable({required this.message});

  final String message;
}

class BodyPartsBloc extends Bloc<BodyPartsEvent, BodyPartsState> {
  BodyPartsBloc({required SafetyApi safetyApi, required AuthGateway authGateway})
      : _api = safetyApi,
        _auth = authGateway,
        super(const BodyPartsLoading()) {
    on<BodyPartsStarted>(_onStarted);
    on<BodyPartsAddConfirmed>(_onAddConfirmed);
    on<BodyPartsCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final SafetyApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(BodyPartsStarted event, Emitter<BodyPartsState> emit) async {
    emit(const BodyPartsLoading());
    await _readList(emit);
  }

  // Deactivated rows included, for the reason `InjuryTypesBloc._readList`
  // gives: this Screen reaches a retired entry to reactivate it, and the
  // classify dialog reads the same catalogue without them.
  Future<void> _readList(Emitter<BodyPartsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const BodyPartsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final bodyParts = await _api.fetchBodyParts(token, includeInactive: true);
      final settled = state;
      emit(
        settled is BodyPartsLoaded
            ? settled.copyWith(bodyParts: bodyParts, isMutating: false)
            : BodyPartsLoaded(bodyParts: bodyParts),
      );
    } on SafetyApiException catch (error) {
      emit(BodyPartsUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(
    BodyPartsAddConfirmed event,
    Emitter<BodyPartsState> emit,
  ) async {
    final current = state;
    if (current is! BodyPartsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createBodyPart(
        token,
        code: event.code,
        name: event.name,
        region: event.region,
      );
      await _readList(emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! BodyPartsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    BodyPartsCorrectionConfirmed event,
    Emitter<BodyPartsState> emit,
  ) async {
    final current = state;
    if (current is! BodyPartsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateBodyPart(token, event.id, event.changes);
      await _readList(emit);
    } on SafetyApiException catch (error) {
      final settled = state;
      if (settled is! BodyPartsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
