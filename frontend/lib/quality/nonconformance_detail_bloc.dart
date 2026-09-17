/// One Non-conformance's own state (issue #205): the record with its quantity
/// history, and the three things a caller may do to it in this slice — raise
/// its severity, record its immediate containment, and increase the affected
/// quantity.
///
/// Route-scoped and keyed on the id in the address, the same shape
/// `ActionDetailBloc` keeps: go_router reuses a page when the route *pattern*
/// matches, so a second Non-conformance's address would otherwise paint the
/// first one's record (issue #183's own bug, and the router keys the provider
/// on the id for it).
///
/// Lowering the severity is not among the events, and that is deliberate
/// rather than an omission: the API refuses it (403) in this slice because it
/// is a Quality-authority decision (ADR-0035) that issue #206 owns. The Screen
/// therefore offers only severities above the current one, rather than
/// offering a lower one and reporting a refusal the caller could not have
/// known about.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'nonconformance.dart';
import 'quality_api.dart';

sealed class NonconformanceDetailEvent {
  const NonconformanceDetailEvent();
}

class NonconformanceDetailStarted extends NonconformanceDetailEvent {
  const NonconformanceDetailStarted(this.id);

  final String id;
}

class NonconformanceDetailRefreshed extends NonconformanceDetailEvent {
  const NonconformanceDetailRefreshed();
}

/// The severity is raised.
class NonconformanceSeverityRaised extends NonconformanceDetailEvent {
  const NonconformanceSeverityRaised(this.severity);

  final String severity;
}

/// Immediate containment is recorded — which is what moves an `open` record to
/// `contained`.
class NonconformanceContainmentRecorded extends NonconformanceDetailEvent {
  const NonconformanceContainmentRecorded(this.immediateContainment);

  final String immediateContainment;
}

/// The affected quantity grew, because sorting found more.
class NonconformanceQuantityIncreased extends NonconformanceDetailEvent {
  const NonconformanceQuantityIncreased({required this.quantity, this.note});

  final num quantity;
  final String? note;
}

sealed class NonconformanceDetailState {
  const NonconformanceDetailState();
}

class NonconformanceDetailLoading extends NonconformanceDetailState {
  const NonconformanceDetailLoading();
}

/// The record could not be read at all — a transport failure, or a refusal.
class NonconformanceDetailUnavailable extends NonconformanceDetailState {
  const NonconformanceDetailUnavailable({required this.message});

  final String message;
}

/// There is no such Non-conformance (or the id is not one) — told apart from
/// an unreadable one, because "this address names nothing" is a different
/// page from "the server could not answer".
class NonconformanceDetailMissing extends NonconformanceDetailState {
  const NonconformanceDetailMissing();
}

class NonconformanceDetailLoaded extends NonconformanceDetailState {
  const NonconformanceDetailLoaded({
    required this.nonconformance,
    this.isMutating = false,
    this.mutationFailure,
  });

  final Nonconformance nonconformance;
  final bool isMutating;

  /// Why the last change did not land. Reported by whichever control made it,
  /// which stays where it was so the caller can correct the one value.
  final String? mutationFailure;

  NonconformanceDetailLoaded copyWith({
    Nonconformance? nonconformance,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      NonconformanceDetailLoaded(
        nonconformance: nonconformance ?? this.nonconformance,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
      );
}

class NonconformanceDetailBloc extends Bloc<NonconformanceDetailEvent, NonconformanceDetailState> {
  NonconformanceDetailBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const NonconformanceDetailLoading()) {
    on<NonconformanceDetailStarted>(_onStarted);
    on<NonconformanceDetailRefreshed>(_onRefreshed);
    on<NonconformanceSeverityRaised>(_onSeverityRaised);
    on<NonconformanceContainmentRecorded>(_onContainmentRecorded);
    on<NonconformanceQuantityIncreased>(_onQuantityIncreased);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  String? _id;

  Future<void> _onStarted(
    NonconformanceDetailStarted event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    _id = event.id;
    emit(const NonconformanceDetailLoading());
    await _read(emit);
  }

  Future<void> _onRefreshed(
    NonconformanceDetailRefreshed event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    if (state is! NonconformanceDetailLoaded) return;
    await _read(emit);
  }

  Future<void> _read(Emitter<NonconformanceDetailState> emit) async {
    final id = _id;
    if (id == null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const NonconformanceDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final nonconformance = await _api.fetchNonconformance(token, id);
      final settled = state;
      emit(
        settled is NonconformanceDetailLoaded
            ? settled.copyWith(nonconformance: nonconformance, isMutating: false)
            : NonconformanceDetailLoaded(nonconformance: nonconformance),
      );
    } on QualityApiException catch (error) {
      if (error.statusCode == 404) {
        emit(const NonconformanceDetailMissing());
        return;
      }
      emit(NonconformanceDetailUnavailable(message: error.message));
    }
  }

  Future<void> _onSeverityRaised(
    NonconformanceSeverityRaised event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    // The Screen only offers a raising, and this guard is the same rule said
    // again where it cannot be bypassed: a severity that is not above the one
    // on the record is refused here rather than sent to be refused.
    if (_rank(event.severity) <= _rank(current.nonconformance.severity)) return;
    await _mutate(
      emit,
      (token) => _api.updateNonconformance(
        token,
        current.nonconformance.id,
        severity: event.severity,
      ),
    );
  }

  Future<void> _onContainmentRecorded(
    NonconformanceContainmentRecorded event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (event.immediateContainment.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.updateNonconformance(
        token,
        current.nonconformance.id,
        immediateContainment: event.immediateContainment,
      ),
    );
  }

  Future<void> _onQuantityIncreased(
    NonconformanceQuantityIncreased event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (event.quantity <= current.nonconformance.quantityAffected) return;
    await _mutate(
      emit,
      (token) => _api.increaseNonconformanceQuantity(
        token,
        current.nonconformance.id,
        quantity: event.quantity,
        note: event.note,
      ),
    );
  }

  Future<void> _mutate(
    Emitter<NonconformanceDetailState> emit,
    Future<Nonconformance> Function(String token) change,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      final updated = await change(token);
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      // The whole record comes back from every write, history included, so the
      // Screen never has to patch its own copy.
      emit(settled.copyWith(nonconformance: updated, isMutating: false));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}

/// The three severities in order, worst last — the comparison that decides
/// which ones a Screen may offer and which one the Bloc will send.
int severityRank(String severity) => _rank(severity);

int _rank(String severity) => switch (severity) {
      'minor' => 1,
      'major' => 2,
      'critical' => 3,
      _ => 0,
    };
