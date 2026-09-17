/// The Defect code tree's own state (issue #203): the list of kinds of thing
/// found wrong that every Site shares (ADR-0005, CONTEXT.md's Defect code
/// entry), and — on this Screen — an administrator's own write surface over it
/// (`POST`/`PATCH /api/quality/defect-codes`, defect-code-routes.js).
///
/// Route-scoped, like `ProductsBloc` beside it: one Screen's own reading of the
/// server, re-read on arrival rather than restored stale. The tree's shape is
/// not held here: the API sends the codes flat, each naming its own parent, and
/// `defectCodeTree` turns that into rows at render time.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'defect_code.dart';
import 'quality_api.dart';

sealed class DefectCodesEvent {
  const DefectCodesEvent();
}

/// Load the whole catalogue, deactivated codes included. Also the retry a
/// failed load offers.
class DefectCodesStarted extends DefectCodesEvent {
  const DefectCodesStarted();
}

/// The add form has decided: a whole new Defect code, optionally beneath an
/// existing one.
class DefectCodesAddConfirmed extends DefectCodesEvent {
  const DefectCodesAddConfirmed({
    required this.code,
    required this.name,
    required this.category,
    required this.defaultSeverity,
    required this.parentId,
  });

  final String code;
  final String name;
  final String category;
  final String defaultSeverity;
  final String? parentId;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed — the same contract `ProductsCorrectionConfirmed` carries,
/// on `updateDefectCode`'s (defect-codes.js) `hasOwnProperty` idiom at the
/// other end. `parentId` rides in [changes] as a null when the code is
/// detached back to the top of the tree: a code that has been moved is not the
/// same as one that has not been touched, and only the form knows which it is.
class DefectCodesCorrectionConfirmed extends DefectCodesEvent {
  const DefectCodesCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class DefectCodesState {
  const DefectCodesState();
}

class DefectCodesLoading extends DefectCodesState {
  const DefectCodesLoading();
}

/// The catalogue as it last read. An empty [codes] is not a state of its own —
/// the same reasoning `ProductsLoaded` gives its own empty list.
class DefectCodesLoaded extends DefectCodesState {
  const DefectCodesLoaded({required this.codes, this.isMutating = false, this.mutationFailure});

  final List<DefectCode> codes;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever dialog
  /// is open, which stays open so the caller can fix the field — a duplicate
  /// code or a parent the API refuses are both things the form can be told
  /// about rather than swallowed.
  final String? mutationFailure;

  DefectCodesLoaded copyWith({
    List<DefectCode>? codes,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      DefectCodesLoaded(
        codes: codes ?? this.codes,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `ProductsLoaded.copyWith` gives its own failure.
        mutationFailure: mutationFailure,
      );
}

class DefectCodesUnavailable extends DefectCodesState {
  const DefectCodesUnavailable({required this.message});

  final String message;
}

class DefectCodesBloc extends Bloc<DefectCodesEvent, DefectCodesState> {
  DefectCodesBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const DefectCodesLoading()) {
    on<DefectCodesStarted>(_onStarted);
    on<DefectCodesAddConfirmed>(_onAddConfirmed);
    on<DefectCodesCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(DefectCodesStarted event, Emitter<DefectCodesState> emit) async {
    emit(const DefectCodesLoading());
    await _readList(emit);
  }

  // Deactivated codes included (`includeInactive: true`): this Screen's whole
  // purpose is reaching a retired code to reactivate it, and the tree a code
  // is moved within has to be complete or a row's parent would vanish from the
  // page while still being its parent.
  Future<void> _readList(Emitter<DefectCodesState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const DefectCodesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final codes = await _api.fetchDefectCodes(token, includeInactive: true);
      final settled = state;
      emit(
        settled is DefectCodesLoaded
            ? settled.copyWith(codes: codes, isMutating: false)
            : DefectCodesLoaded(codes: codes),
      );
    } on QualityApiException catch (error) {
      emit(DefectCodesUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(DefectCodesAddConfirmed event, Emitter<DefectCodesState> emit) async {
    final current = state;
    if (current is! DefectCodesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createDefectCode(
        token,
        code: event.code,
        name: event.name,
        category: event.category,
        defaultSeverity: event.defaultSeverity,
        parentId: event.parentId,
      );
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! DefectCodesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    DefectCodesCorrectionConfirmed event,
    Emitter<DefectCodesState> emit,
  ) async {
    final current = state;
    if (current is! DefectCodesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateDefectCode(token, event.id, event.changes);
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! DefectCodesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
