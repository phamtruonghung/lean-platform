/// One complaint's own state (issue #214): the record, the Customer and the
/// Product it names, the Non-conformance that controls the complained-of
/// product, and the three writes a reader can make from it — record a
/// Non-conformance from the complaint, link one that already exists, or close
/// the complaint with its response.
///
/// Route-scoped and keyed on the complaint id in the address (issue #183's own
/// bug: go_router reuses a route's page when the *pattern* matches, so without
/// the key moving from one complaint to another would leave this Bloc — and the
/// Screen reading it — holding the record before).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'customer_complaint.dart';
import 'nonconformance.dart';
import 'quality_api.dart';

sealed class ComplaintDetailEvent {
  const ComplaintDetailEvent();
}

class ComplaintDetailStarted extends ComplaintDetailEvent {
  const ComplaintDetailStarted(this.id);

  final String id;
}

/// Closes the complaint with the response the customer was given
/// (`POST /api/quality/complaints/:id/respond`). The note is required by the
/// service, which is what makes a refusal here a 400 the form shows rather than
/// a complaint closed with nothing said back.
class ComplaintRespondConfirmed extends ComplaintDetailEvent {
  const ComplaintRespondConfirmed({required this.id, required this.responseNote});

  final String id;
  final String responseNote;
}

/// Records the Non-conformance that controls the complained-of product
/// (`POST /api/quality/complaints/:id/nonconformance`), with
/// `detection_point = customer`.
class ComplaintNonconformanceConfirmed extends ComplaintDetailEvent {
  const ComplaintNonconformanceConfirmed({
    required this.id,
    this.quantity,
    this.defectCodeId,
    this.immediateContainment,
  });

  final String id;
  final num? quantity;
  final String? defectCodeId;
  final String? immediateContainment;
}

/// Links a Non-conformance that already exists to the complaint
/// (`POST /api/quality/complaints/:id/link`).
class ComplaintLinkConfirmed extends ComplaintDetailEvent {
  const ComplaintLinkConfirmed({required this.id, required this.nonconformanceId});

  final String id;
  final String nonconformanceId;
}

sealed class ComplaintDetailState {
  const ComplaintDetailState();
}

class ComplaintDetailLoading extends ComplaintDetailState {
  const ComplaintDetailLoading();
}

class ComplaintDetailUnavailable extends ComplaintDetailState {
  const ComplaintDetailUnavailable({required this.message});

  final String message;
}

class ComplaintDetailLoaded extends ComplaintDetailState {
  const ComplaintDetailLoaded({
    required this.complaint,
    this.isMutating = false,
    this.mutationFailure,
    this.recordedNonconformance,
  });

  final CustomerComplaint complaint;

  /// A write is in flight.
  final bool isMutating;

  /// Why the last write did not land. Reported by the dialog that made it,
  /// which stays open so the caller can fix what was wrong.
  final String? mutationFailure;

  /// The Non-conformance that was just recorded from this complaint, when one
  /// was: the Screen says so, because the record it created is the answer to
  /// the question the reader came with.
  final Nonconformance? recordedNonconformance;

  ComplaintDetailLoaded copyWith({
    CustomerComplaint? complaint,
    bool? isMutating,
    String? mutationFailure,
    Nonconformance? recordedNonconformance,
  }) =>
      ComplaintDetailLoaded(
        complaint: complaint ?? this.complaint,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule every other
        // Loaded state in this Module gives its own failure.
        mutationFailure: mutationFailure,
        recordedNonconformance: recordedNonconformance ?? this.recordedNonconformance,
      );
}

class ComplaintDetailBloc extends Bloc<ComplaintDetailEvent, ComplaintDetailState> {
  ComplaintDetailBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const ComplaintDetailLoading()) {
    on<ComplaintDetailStarted>(_onStarted);
    on<ComplaintRespondConfirmed>(_onRespondConfirmed);
    on<ComplaintNonconformanceConfirmed>(_onNonconformanceConfirmed);
    on<ComplaintLinkConfirmed>(_onLinkConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(
    ComplaintDetailStarted event,
    Emitter<ComplaintDetailState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ComplaintDetailUnavailable(message: signedOutMessage));
      return;
    }
    emit(const ComplaintDetailLoading());
    try {
      final complaint = await _api.fetchComplaint(token, event.id);
      emit(ComplaintDetailLoaded(complaint: complaint));
    } on QualityApiException catch (error) {
      emit(ComplaintDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onRespondConfirmed(
    ComplaintRespondConfirmed event,
    Emitter<ComplaintDetailState> emit,
  ) async {
    final current = state;
    if (current is! ComplaintDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final complaint = await _api.closeComplaint(token, event.id, responseNote: event.responseNote);
      emit(ComplaintDetailLoaded(complaint: complaint));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ComplaintDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onNonconformanceConfirmed(
    ComplaintNonconformanceConfirmed event,
    Emitter<ComplaintDetailState> emit,
  ) async {
    final current = state;
    if (current is! ComplaintDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final (nonconformance, complaint) = await _api.recordComplaintNonconformance(
        token,
        event.id,
        quantity: event.quantity,
        defectCodeId: event.defectCodeId,
        immediateContainment: event.immediateContainment,
      );
      emit(
        ComplaintDetailLoaded(
          complaint: complaint,
          recordedNonconformance: nonconformance,
        ),
      );
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ComplaintDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onLinkConfirmed(
    ComplaintLinkConfirmed event,
    Emitter<ComplaintDetailState> emit,
  ) async {
    final current = state;
    if (current is! ComplaintDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final complaint = await _api.linkComplaintNonconformance(
        token,
        event.id,
        nonconformanceId: event.nonconformanceId,
      );
      emit(ComplaintDetailLoaded(complaint: complaint));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ComplaintDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
