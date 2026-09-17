/// One supplier NCR's own state (issue #215): the record, the Supplier and the
/// Product it names, the Non-conformance that controls the received material,
/// and the four writes a reader can make from it — record a Non-conformance
/// from the NCR, link one that already exists, record the Supplier's disposition
/// and what was recovered, or close it.
///
/// Route-scoped and keyed on the NCR id in the address (issue #183's own bug:
/// go_router reuses a route's page when the *pattern* matches, so without the
/// key moving from one NCR to another would leave this Bloc — and the Screen
/// reading it — holding the record before).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'nonconformance.dart';
import 'quality_api.dart';
import 'supplier_ncr.dart';

sealed class SupplierNcrDetailEvent {
  const SupplierNcrDetailEvent();
}

class SupplierNcrDetailStarted extends SupplierNcrDetailEvent {
  const SupplierNcrDetailStarted(this.id);

  final String id;
}

/// Records the Supplier's disposition and what was recovered
/// (`POST /api/quality/supplier-ncrs/:id/disposition`). The disposition comes
/// from the baseline's own five and is required by the service, which is what
/// makes a refusal here a 400 the form shows.
class SupplierNcrDispositionConfirmed extends SupplierNcrDetailEvent {
  const SupplierNcrDispositionConfirmed({
    required this.id,
    required this.disposition,
    this.costRecovered,
    this.currency,
  });

  final String id;
  final String disposition;
  final num? costRecovered;
  final String? currency;
}

/// Closes the NCR (`POST /api/quality/supplier-ncrs/:id/close`) — the one
/// transition this slice has.
class SupplierNcrCloseConfirmed extends SupplierNcrDetailEvent {
  const SupplierNcrCloseConfirmed(this.id);

  final String id;
}

/// Records the Non-conformance that controls the received lot
/// (`POST /api/quality/supplier-ncrs/:id/nonconformance`), with
/// `detection_point = incoming`.
class SupplierNcrNonconformanceConfirmed extends SupplierNcrDetailEvent {
  const SupplierNcrNonconformanceConfirmed({
    required this.id,
    this.productId,
    this.quantity,
    this.defectCodeId,
    this.immediateContainment,
  });

  final String id;

  /// Named only when the NCR carries no Product of its own: a Non-conformance
  /// has to be about one, and a lot received against a purchase order may not
  /// have been destined for one yet.
  final String? productId;

  final num? quantity;

  /// Named only when the NCR carries no Defect code of its own.
  final String? defectCodeId;

  final String? immediateContainment;
}

/// Links a Non-conformance that already exists to the NCR
/// (`POST /api/quality/supplier-ncrs/:id/link`).
class SupplierNcrLinkConfirmed extends SupplierNcrDetailEvent {
  const SupplierNcrLinkConfirmed({required this.id, required this.nonconformanceId});

  final String id;
  final String nonconformanceId;
}

sealed class SupplierNcrDetailState {
  const SupplierNcrDetailState();
}

class SupplierNcrDetailLoading extends SupplierNcrDetailState {
  const SupplierNcrDetailLoading();
}

class SupplierNcrDetailUnavailable extends SupplierNcrDetailState {
  const SupplierNcrDetailUnavailable({required this.message});

  final String message;
}

class SupplierNcrDetailLoaded extends SupplierNcrDetailState {
  const SupplierNcrDetailLoaded({
    required this.supplierNcr,
    this.isMutating = false,
    this.mutationFailure,
    this.recordedNonconformance,
  });

  final SupplierNcr supplierNcr;

  /// A write is in flight.
  final bool isMutating;

  /// Why the last write did not land. Reported by the dialog that made it,
  /// which stays open so the caller can fix what was wrong.
  final String? mutationFailure;

  /// The Non-conformance that was just recorded from this NCR, when one was: the
  /// Screen says so, because the record it created is the answer to the question
  /// the reader came with.
  final Nonconformance? recordedNonconformance;

  SupplierNcrDetailLoaded copyWith({
    SupplierNcr? supplierNcr,
    bool? isMutating,
    String? mutationFailure,
    Nonconformance? recordedNonconformance,
  }) =>
      SupplierNcrDetailLoaded(
        supplierNcr: supplierNcr ?? this.supplierNcr,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule every other
        // Loaded state in this Module gives its own failure.
        mutationFailure: mutationFailure,
        recordedNonconformance: recordedNonconformance ?? this.recordedNonconformance,
      );
}

class SupplierNcrDetailBloc extends Bloc<SupplierNcrDetailEvent, SupplierNcrDetailState> {
  SupplierNcrDetailBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const SupplierNcrDetailLoading()) {
    on<SupplierNcrDetailStarted>(_onStarted);
    on<SupplierNcrDispositionConfirmed>(_onDispositionConfirmed);
    on<SupplierNcrCloseConfirmed>(_onCloseConfirmed);
    on<SupplierNcrNonconformanceConfirmed>(_onNonconformanceConfirmed);
    on<SupplierNcrLinkConfirmed>(_onLinkConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(
    SupplierNcrDetailStarted event,
    Emitter<SupplierNcrDetailState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SupplierNcrDetailUnavailable(message: signedOutMessage));
      return;
    }
    emit(const SupplierNcrDetailLoading());
    try {
      final supplierNcr = await _api.fetchSupplierNcr(token, event.id);
      emit(SupplierNcrDetailLoaded(supplierNcr: supplierNcr));
    } on QualityApiException catch (error) {
      emit(SupplierNcrDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onDispositionConfirmed(
    SupplierNcrDispositionConfirmed event,
    Emitter<SupplierNcrDetailState> emit,
  ) async {
    final current = state;
    if (current is! SupplierNcrDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final supplierNcr = await _api.recordSupplierNcrDisposition(
        token,
        event.id,
        disposition: event.disposition,
        costRecovered: event.costRecovered,
        currency: event.currency,
      );
      emit(SupplierNcrDetailLoaded(supplierNcr: supplierNcr));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SupplierNcrDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCloseConfirmed(
    SupplierNcrCloseConfirmed event,
    Emitter<SupplierNcrDetailState> emit,
  ) async {
    final current = state;
    if (current is! SupplierNcrDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final supplierNcr = await _api.closeSupplierNcr(token, event.id);
      emit(SupplierNcrDetailLoaded(supplierNcr: supplierNcr));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SupplierNcrDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onNonconformanceConfirmed(
    SupplierNcrNonconformanceConfirmed event,
    Emitter<SupplierNcrDetailState> emit,
  ) async {
    final current = state;
    if (current is! SupplierNcrDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final (nonconformance, supplierNcr) = await _api.recordSupplierNcrNonconformance(
        token,
        event.id,
        productId: event.productId,
        quantity: event.quantity,
        defectCodeId: event.defectCodeId,
        immediateContainment: event.immediateContainment,
      );
      emit(
        SupplierNcrDetailLoaded(
          supplierNcr: supplierNcr,
          recordedNonconformance: nonconformance,
        ),
      );
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SupplierNcrDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onLinkConfirmed(
    SupplierNcrLinkConfirmed event,
    Emitter<SupplierNcrDetailState> emit,
  ) async {
    final current = state;
    if (current is! SupplierNcrDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final supplierNcr = await _api.linkSupplierNcrNonconformance(
        token,
        event.id,
        nonconformanceId: event.nonconformanceId,
      );
      emit(SupplierNcrDetailLoaded(supplierNcr: supplierNcr));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SupplierNcrDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
