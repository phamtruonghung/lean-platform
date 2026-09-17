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
/// Lowering the severity was not among the events in issue #205's slice, and
/// is one of them now (issue #206): the API refuses a lowering to a holder of
/// Quality authority without a note (403 and 400), so the Screen offers it
/// only where the caller holds that authority and the dialog always carries a
/// note. The same slice adds the Disposition, the Concession, the reopen and
/// the cancel — five acts, each with an address of its own (ADR-0021).
///
/// The cause, answered in the action log (issue #208), is the sixth and
/// seventh: raising a Concern from this record, and linking this record to a
/// Concern that already exists. Both are writes to the *Actions* Module — its
/// own routes, reached through its own client entry point — so this Bloc holds
/// two API clients rather than one, and each failure keeps its own field so a
/// dialog can report the one it asked for.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
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

/// A Disposition was recorded: some of the product dealt with as scrap, as
/// rework, or returned to the supplier (issue #206).
class NonconformanceDispositionRecorded extends NonconformanceDetailEvent {
  const NonconformanceDispositionRecorded({
    required this.dispositionType,
    required this.quantity,
    this.reworkMinutes,
    this.note,
  });

  final String dispositionType;
  final num quantity;
  final num? reworkMinutes;
  final String? note;
}

/// A Concession was granted: the product accepted as it is, on Quality
/// authority, under a reference and with a note (issue #206).
class NonconformanceConcessionGranted extends NonconformanceDetailEvent {
  const NonconformanceConcessionGranted({
    required this.quantity,
    required this.reference,
    required this.note,
  });

  final num quantity;
  final String reference;
  final String note;
}

/// The severity was lowered, with the note it was lowered on (issue #206).
class NonconformanceSeverityLowered extends NonconformanceDetailEvent {
  const NonconformanceSeverityLowered({required this.severity, required this.note});

  final String severity;
  final String note;
}

/// The record was reopened, with the note saying why (issue #206).
class NonconformanceReopened extends NonconformanceDetailEvent {
  const NonconformanceReopened({required this.note});

  final String note;
}

/// The record was cancelled, with the note saying why (issue #206).
class NonconformanceCancelled extends NonconformanceDetailEvent {
  const NonconformanceCancelled({required this.note});

  final String note;
}

/// A Concern was raised from this Non-conformance (issue #208), in the action
/// log. The dialog decides the title and the optional fields; the Bloc only
/// ever sees a decision already made.
class NonconformanceConcernRaised extends NonconformanceDetailEvent {
  const NonconformanceConcernRaised({
    required this.title,
    this.description,
    this.priority,
  });

  final String title;
  final String? description;
  final int? priority;
}

/// This Non-conformance was linked to a Concern that already exists (issue
/// #208) — one problem answering several occurrences stays one Concern.
class NonconformanceConcernLinked extends NonconformanceDetailEvent {
  const NonconformanceConcernLinked({required this.concernId});

  final String concernId;
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
    this.isRaisingConcern = false,
    this.concernRaiseFailure,
    this.isLinkingConcern = false,
    this.concernLinkFailure,
    this.notice,
  });

  final Nonconformance nonconformance;
  final bool isMutating;

  /// Why the last change did not land. Reported by whichever control made it,
  /// which stays where it was so the caller can correct the one value.
  final String? mutationFailure;

  /// A Concern is being raised from this record, and why the last one did not
  /// land (issue #208). Its own pair rather than `isMutating`'s, because the
  /// two dialogs watch different fields: a refusal to raise a Concern must not
  /// look like a refusal to lower a severity.
  final bool isRaisingConcern;
  final String? concernRaiseFailure;

  /// This record is being linked to an existing Concern, and why the last link
  /// did not land (issue #208).
  final bool isLinkingConcern;
  final String? concernLinkFailure;

  /// What the last Concern had to say for itself — the one sentence the Screen
  /// shows once the dialog that asked has closed.
  final String? notice;

  NonconformanceDetailLoaded copyWith({
    Nonconformance? nonconformance,
    bool? isMutating,
    String? mutationFailure,
    bool? isRaisingConcern,
    String? concernRaiseFailure,
    bool? isLinkingConcern,
    String? concernLinkFailure,
    String? notice,
  }) =>
      NonconformanceDetailLoaded(
        nonconformance: nonconformance ?? this.nonconformance,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
        isRaisingConcern: isRaisingConcern ?? this.isRaisingConcern,
        concernRaiseFailure: concernRaiseFailure,
        isLinkingConcern: isLinkingConcern ?? this.isLinkingConcern,
        concernLinkFailure: concernLinkFailure,
        notice: notice,
      );
}

class NonconformanceDetailBloc extends Bloc<NonconformanceDetailEvent, NonconformanceDetailState> {
  NonconformanceDetailBloc({
    required QualityApi qualityApi,
    required ActionsApi actionsApi,
    required AuthGateway authGateway,
  })  : _api = qualityApi,
        _actions = actionsApi,
        _auth = authGateway,
        super(const NonconformanceDetailLoading()) {
    on<NonconformanceDetailStarted>(_onStarted);
    on<NonconformanceDetailRefreshed>(_onRefreshed);
    on<NonconformanceSeverityRaised>(_onSeverityRaised);
    on<NonconformanceContainmentRecorded>(_onContainmentRecorded);
    on<NonconformanceQuantityIncreased>(_onQuantityIncreased);
    on<NonconformanceDispositionRecorded>(_onDispositionRecorded);
    on<NonconformanceConcessionGranted>(_onConcessionGranted);
    on<NonconformanceSeverityLowered>(_onSeverityLowered);
    on<NonconformanceReopened>(_onReopened);
    on<NonconformanceCancelled>(_onCancelled);
    on<NonconformanceConcernRaised>(_onConcernRaised);
    on<NonconformanceConcernLinked>(_onConcernLinked);
  }

  final QualityApi _api;

  /// The Actions Module's client, reached through its own entry point: raising
  /// a Concern from this record and linking it to one are writes to the action
  /// log, and the action log's routes are where they live (issue #208).
  final ActionsApi _actions;

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

  /// A Disposition was recorded (issue #206). The Screen only offers one where
  /// the record still has undecided quantity, and this guard is the same rule
  /// said again where it cannot be bypassed.
  Future<void> _onDispositionRecorded(
    NonconformanceDispositionRecorded event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (!current.nonconformance.acceptsDisposition) return;
    if (event.quantity <= 0) return;
    await _mutate(
      emit,
      (token) => _api.recordDisposition(
        token,
        current.nonconformance.id,
        dispositionType: event.dispositionType,
        quantity: event.quantity,
        reworkMinutes: event.reworkMinutes,
        note: event.note,
      ),
    );
  }

  /// A Concession was granted (issue #206). Whether the caller holds Quality
  /// authority is the server's question, not this Bloc's — the Screen only
  /// offers the dialog to a holder, and the API is the gate.
  Future<void> _onConcessionGranted(
    NonconformanceConcessionGranted event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (!current.nonconformance.acceptsConcession) return;
    if (event.quantity <= 0) return;
    if (event.reference.trim().isEmpty || event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.grantConcession(
        token,
        current.nonconformance.id,
        quantity: event.quantity,
        reference: event.reference,
        note: event.note,
      ),
    );
  }

  /// The severity was lowered (issue #206). Only a lowering is sent: a value
  /// that is not below the one on the record is refused here rather than sent
  /// to be refused, the mirror of `_onSeverityRaised`'s own guard.
  Future<void> _onSeverityLowered(
    NonconformanceSeverityLowered event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (!current.nonconformance.canBeLowered) return;
    if (severityRank(event.severity) >= severityRank(current.nonconformance.severity)) return;
    if (event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.lowerNonconformanceSeverity(
        token,
        current.nonconformance.id,
        severity: event.severity,
        note: event.note,
      ),
    );
  }

  /// The record was reopened (issue #206). Only a closed one can be.
  Future<void> _onReopened(
    NonconformanceReopened event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (!current.nonconformance.canBeReopened) return;
    if (event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.reopenNonconformance(
        token,
        current.nonconformance.id,
        note: event.note,
      ),
    );
  }

  /// The record was cancelled (issue #206).
  Future<void> _onCancelled(
    NonconformanceCancelled event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded) return;
    if (!current.nonconformance.canBeCancelled) return;
    if (event.note.trim().isEmpty) return;
    await _mutate(
      emit,
      (token) => _api.cancelNonconformance(
        token,
        current.nonconformance.id,
        note: event.note,
      ),
    );
  }

  /// A Concern was raised from this record (issue #208).
  ///
  /// The write is the Actions Module's, so it is `ActionsApi` that carries it
  /// and `ActionsApiException` that can refuse it. What comes back is the
  /// *Concern*, not this record, so the record is re-read afterwards: the
  /// Screen that raised it is this Non-conformance's own, and what it has to
  /// show is the Concern now named among the ones it is linked to — with the
  /// status the server just gave it rather than a client's guess.
  Future<void> _onConcernRaised(
    NonconformanceConcernRaised event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded || current.isRaisingConcern) return;
    if (event.title.trim().isEmpty) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(concernRaiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaisingConcern: true, concernRaiseFailure: null));
    try {
      final concern = await _actions.raiseConcernFromNonconformance(
        token,
        current.nonconformance.id,
        title: event.title,
        description: event.description,
        priority: event.priority,
      );
      final refreshed = await _api.fetchNonconformance(token, current.nonconformance.id);
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(
        settled.copyWith(
          nonconformance: refreshed,
          isRaisingConcern: false,
          notice: '${concern.actionNo} was raised from this Non-conformance.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(settled.copyWith(isRaisingConcern: false, concernRaiseFailure: error.message));
    } on QualityApiException catch (error) {
      // The re-read is the Quality Module's own read and can fail on its own:
      // the Concern exists either way, and saying so beats reporting the raise
      // as failed.
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(settled.copyWith(isRaisingConcern: false, concernRaiseFailure: error.message));
    }
  }

  /// This record was linked to a Concern that already exists (issue #208).
  ///
  /// The link answers with the *Concern*, so this record is re-read for the
  /// same reason the raise above re-reads it: the link is this record's own
  /// new state, and the Screen shows it among the Concerns it is part of.
  Future<void> _onConcernLinked(
    NonconformanceConcernLinked event,
    Emitter<NonconformanceDetailState> emit,
  ) async {
    final current = state;
    if (current is! NonconformanceDetailLoaded || current.isLinkingConcern) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(concernLinkFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isLinkingConcern: true, concernLinkFailure: null));
    try {
      final concern = await _actions.linkNonconformance(
        token,
        event.concernId,
        nonconformanceId: current.nonconformance.id,
      );
      final refreshed = await _api.fetchNonconformance(token, current.nonconformance.id);
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(
        settled.copyWith(
          nonconformance: refreshed,
          isLinkingConcern: false,
          notice: 'Linked to ${concern.actionNo} — one problem, several occurrences.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(settled.copyWith(isLinkingConcern: false, concernLinkFailure: error.message));
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! NonconformanceDetailLoaded) return;
      emit(settled.copyWith(isLinkingConcern: false, concernLinkFailure: error.message));
    }
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
