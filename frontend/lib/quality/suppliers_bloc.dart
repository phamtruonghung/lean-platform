/// The Supplier list's own state (issue #215): the record a supplier NCR
/// belongs to, read by every approved Account and written by an administrator
/// alone (`POST`/`PATCH /api/quality/suppliers`, supplier-routes.js).
///
/// Route-scoped, like `CustomersBloc`: one Screen's own reading of the server,
/// re-read on arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'quality_api.dart';
import 'supplier.dart';

sealed class SuppliersEvent {
  const SuppliersEvent();
}

/// Load the whole list, deactivated Suppliers included: the Screen's own
/// purpose includes reaching a retired row to reactivate it.
class SuppliersStarted extends SuppliersEvent {
  const SuppliersStarted();
}

/// The form has decided: a whole new Supplier. The dialog decides, the Bloc
/// only ever sees a decision already made — `CustomersAddConfirmed`'s own
/// contract.
class SuppliersAddConfirmed extends SuppliersEvent {
  const SuppliersAddConfirmed({
    required this.code,
    required this.name,
    this.contactEmail,
  });

  final String code;
  final String name;
  final String? contactEmail;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed, on `updateSupplier`'s (suppliers.js) `hasOwnProperty`
/// idiom at the other end. `isActive` rides in [changes] too: retiring or
/// reactivating a Supplier is a correction, not a dedicated verb.
class SuppliersCorrectionConfirmed extends SuppliersEvent {
  const SuppliersCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class SuppliersState {
  const SuppliersState();
}

class SuppliersLoading extends SuppliersState {
  const SuppliersLoading();
}

/// The list as it last read. An empty [suppliers] is not a state of its own —
/// the same reasoning `CustomersLoaded` gives its own empty list.
class SuppliersLoaded extends SuppliersState {
  const SuppliersLoaded({
    required this.suppliers,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<Supplier> suppliers;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by the form, which
  /// stays open so the caller can fix the field rather than retype the whole
  /// Supplier.
  final String? mutationFailure;

  SuppliersLoaded copyWith({
    List<Supplier>? suppliers,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      SuppliersLoaded(
        suppliers: suppliers ?? this.suppliers,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `CustomersLoaded.copyWith` gives its own failure.
        mutationFailure: mutationFailure,
      );
}

class SuppliersUnavailable extends SuppliersState {
  const SuppliersUnavailable({required this.message});

  final String message;
}

class SuppliersBloc extends Bloc<SuppliersEvent, SuppliersState> {
  SuppliersBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const SuppliersLoading()) {
    on<SuppliersStarted>(_onStarted);
    on<SuppliersAddConfirmed>(_onAddConfirmed);
    on<SuppliersCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(SuppliersStarted event, Emitter<SuppliersState> emit) async {
    emit(const SuppliersLoading());
    await _readList(emit);
  }

  // Deactivated rows included (`includeInactive: true`): this Screen's whole
  // purpose is reaching a retired Supplier to reactivate them.
  Future<void> _readList(Emitter<SuppliersState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SuppliersUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final suppliers = await _api.fetchSuppliers(token, includeInactive: true);
      final settled = state;
      emit(
        settled is SuppliersLoaded
            ? settled.copyWith(suppliers: suppliers, isMutating: false)
            : SuppliersLoaded(suppliers: suppliers),
      );
    } on QualityApiException catch (error) {
      emit(SuppliersUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(SuppliersAddConfirmed event, Emitter<SuppliersState> emit) async {
    final current = state;
    if (current is! SuppliersLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createSupplier(
        token,
        code: event.code,
        name: event.name,
        contactEmail: event.contactEmail,
      );
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SuppliersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    SuppliersCorrectionConfirmed event,
    Emitter<SuppliersState> emit,
  ) async {
    final current = state;
    if (current is! SuppliersLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateSupplier(token, event.id, event.changes);
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SuppliersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
