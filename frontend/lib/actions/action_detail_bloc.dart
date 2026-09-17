/// One Action's own read (issue #176): its number, what it is, where it was
/// raised, who owns it and when it is due — fetched by id so a bookmarked or
/// shared address works on its own.
///
/// Route-scoped like `ActionsBloc`, and deliberately separate from it: the
/// detail read is the one Action, not the register, and a caller who lands
/// here directly never loads the Site's list first.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'action.dart';
import 'actions_api.dart';

sealed class ActionDetailEvent {
  const ActionDetailEvent();
}

class ActionDetailStarted extends ActionDetailEvent {
  const ActionDetailStarted(this.actionId);
  final String actionId;
}

/// Hand this Action up to an Org Unit above it (issue #180).
class ActionEscalationRequested extends ActionDetailEvent {
  const ActionEscalationRequested({required this.actionId, required this.orgUnitId});

  final String actionId;
  final String orgUnitId;
}

/// Load the Org Units this Action may be handed up to (issue #180).
class ActionEscalationTargetsRequested extends ActionDetailEvent {
  const ActionEscalationTargetsRequested({required this.actionId});

  final String actionId;
}

/// Call this Action off (issue #179). The reason is optional, and the dialog
/// only ever sends one that was typed.
class ActionCancellationRequested extends ActionDetailEvent {
  const ActionCancellationRequested({required this.actionId, this.reason});

  final String actionId;
  final String? reason;
}

/// Raise a measure against this Concern (issue #178). The dialog decides the
/// kind, the title and the optional fields; the Bloc only ever sees a decision
/// already made.
class ActionMeasureRaised extends ActionDetailEvent {
  const ActionMeasureRaised({
    required this.concernId,
    required this.actionType,
    required this.title,
    this.description,
    this.orgUnitId,
    this.ownerEmployeeId,
    this.dueDate,
    this.priority,
  });

  final String concernId;
  final String actionType;
  final String title;
  final String? description;
  final String? orgUnitId;
  final String? ownerEmployeeId;
  final String? dueDate;
  final int? priority;
}

/// Complete the Action's open phase (issue #177). The dialog decides — the
/// note and, on a Check, the outcome — and the Bloc only ever sees a decision
/// already made, the same contract every other Module's forms follow.
class ActionPhaseCompletionRequested extends ActionDetailEvent {
  const ActionPhaseCompletionRequested({
    required this.actionId,
    required this.phase,
    required this.note,
    this.outcome,
  });

  final String actionId;
  final String phase;
  final String note;
  final String? outcome;
}

/// An occurrence is unlinked from this Concern (issue #208). The dialog
/// decides — the record is named in its own address and the Bloc only ever
/// sees a decision already made.
class ActionNonconformanceUnlinked extends ActionDetailEvent {
  const ActionNonconformanceUnlinked({
    required this.actionId,
    required this.nonconformanceId,
  });

  final String actionId;
  final String nonconformanceId;
}

sealed class ActionDetailState {
  const ActionDetailState();
}

class ActionDetailLoading extends ActionDetailState {
  const ActionDetailLoading();
}

class ActionDetailLoaded extends ActionDetailState {
  const ActionDetailLoaded(
    this.action, {
    this.isCompleting = false,
    this.completionFailure,
    this.isAddingMeasure = false,
    this.measureFailure,
    this.escalationTargets = const [],
    this.isLoadingEscalationTargets = false,
    this.isEscalating = false,
    this.escalationFailure,
    this.isCancelling = false,
    this.cancellationFailure,
    this.isUnlinking = false,
    this.unlinkFailure,
    this.notice,
  });

  final Action action;

  /// A phase completion is in flight. Kept on the state, not only in the
  /// dialog, so the Screen can refuse a second one.
  final bool isCompleting;

  /// Why the last completion did not land. Reported by the open dialog, which
  /// stays open so the caller can fix it rather than retype the note — and by
  /// the Screen after a refusal that has already closed it.
  final String? completionFailure;

  /// A measure is being raised against this Concern (issue #178).
  final bool isAddingMeasure;

  /// Why the last measure did not land, reported by the dialog that asked.
  final String? measureFailure;

  /// The Org Units this Action may be handed up to, and whether they are still
  /// being read. Both empty when the Action has ended: nothing is handed up
  /// once it is over.
  final List<EscalationTarget> escalationTargets;
  final bool isLoadingEscalationTargets;

  /// An escalation is in flight, and why the last one did not land.
  final bool isEscalating;
  final String? escalationFailure;

  /// A cancellation is in flight (issue #179).
  final bool isCancelling;

  /// Why the last cancellation did not land. Reported by the dialog that asked,
  /// which stays open — a refusal to call something off is nearly always "one
  /// of its measures is still open", and that is a sentence worth reading
  /// before deciding what to do next.
  final String? cancellationFailure;

  /// An occurrence is being unlinked from this Concern, and why the last
  /// unlink did not land (issue #208). Its own pair because the one refusal
  /// this act has — the Non-conformance the Concern was raised from cannot be
  /// unlinked — is a sentence worth reading beside the button that asked.
  final bool isUnlinking;
  final String? unlinkFailure;

  /// What the last completion had to say for itself.
  final String? notice;

  ActionDetailLoaded copyWith({
    Action? action,
    bool? isCompleting,
    String? completionFailure,
    bool clearCompletionFailure = false,
    bool? isAddingMeasure,
    String? measureFailure,
    bool clearMeasureFailure = false,
    List<EscalationTarget>? escalationTargets,
    bool? isLoadingEscalationTargets,
    bool? isEscalating,
    String? escalationFailure,
    bool clearEscalationFailure = false,
    bool? isCancelling,
    String? cancellationFailure,
    bool clearCancellationFailure = false,
    bool? isUnlinking,
    String? unlinkFailure,
    bool clearUnlinkFailure = false,
    String? notice,
    bool clearNotice = false,
  }) =>
      ActionDetailLoaded(
        action ?? this.action,
        isCompleting: isCompleting ?? this.isCompleting,
        isAddingMeasure: isAddingMeasure ?? this.isAddingMeasure,
        measureFailure: clearMeasureFailure ? null : (measureFailure ?? this.measureFailure),
        escalationTargets: escalationTargets ?? this.escalationTargets,
        isLoadingEscalationTargets:
            isLoadingEscalationTargets ?? this.isLoadingEscalationTargets,
        isEscalating: isEscalating ?? this.isEscalating,
        escalationFailure:
            clearEscalationFailure ? null : (escalationFailure ?? this.escalationFailure),
        isCancelling: isCancelling ?? this.isCancelling,
        cancellationFailure:
            clearCancellationFailure ? null : (cancellationFailure ?? this.cancellationFailure),
        isUnlinking: isUnlinking ?? this.isUnlinking,
        unlinkFailure: clearUnlinkFailure ? null : (unlinkFailure ?? this.unlinkFailure),
        // Explicit clear flags rather than a null default: every emit would
        // otherwise wipe the reason a dialog is showing, and a caller reading
        // the Screen would never see it.
        completionFailure:
            clearCompletionFailure ? null : (completionFailure ?? this.completionFailure),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

class ActionDetailUnavailable extends ActionDetailState {
  const ActionDetailUnavailable({required this.message});
  final String message;
}

class ActionDetailBloc extends Bloc<ActionDetailEvent, ActionDetailState> {
  ActionDetailBloc({required ActionsApi actionsApi, required AuthGateway authGateway})
      : _actions = actionsApi,
        _auth = authGateway,
        super(const ActionDetailLoading()) {
    on<ActionDetailStarted>(_onStarted);
    on<ActionPhaseCompletionRequested>(_onPhaseCompletionRequested);
    on<ActionMeasureRaised>(_onMeasureRaised);
    on<ActionCancellationRequested>(_onCancellationRequested);
    on<ActionEscalationTargetsRequested>(_onEscalationTargetsRequested);
    on<ActionEscalationRequested>(_onEscalationRequested);
    on<ActionNonconformanceUnlinked>(_onNonconformanceUnlinked);
  }

  final ActionsApi _actions;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(ActionDetailStarted event, Emitter<ActionDetailState> emit) async {
    emit(const ActionDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ActionDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      emit(ActionDetailLoaded(await _actions.fetchAction(token, event.actionId)));
    } on ActionsApiException catch (error) {
      emit(ActionDetailUnavailable(message: error.message));
    }
  }

  /// Reads the Org Units above this Action's own (issue #180).
  ///
  /// A failure to read them is not a failure of the Screen: the list is what
  /// the escalate dialog needs, and saying so there beats blanking a record
  /// that is perfectly readable.
  Future<void> _onEscalationTargetsRequested(
    ActionEscalationTargetsRequested event,
    Emitter<ActionDetailState> emit,
  ) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isLoadingEscalationTargets) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(escalationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isLoadingEscalationTargets: true, clearEscalationFailure: true));
    try {
      final targets = await _actions.fetchEscalationTargets(token, event.actionId);
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          escalationTargets: targets,
          isLoadingEscalationTargets: false,
          clearEscalationFailure: true,
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(isLoadingEscalationTargets: false, escalationFailure: error.message),
      );
    }
  }

  /// Hands the Action up, and keeps what the server sends back: the row now
  /// names the Org Unit it went to, and only the server knows that name.
  Future<void> _onEscalationRequested(
    ActionEscalationRequested event,
    Emitter<ActionDetailState> emit,
  ) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isEscalating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(escalationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isEscalating: true, clearEscalationFailure: true));
    try {
      final action = await _actions.escalateAction(
        token,
        event.actionId,
        orgUnitId: event.orgUnitId,
      );
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          action: action,
          isEscalating: false,
          clearEscalationFailure: true,
          notice: '${action.actionNo} was handed up to ${action.escalatedToOrgUnitName}.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(settled.copyWith(isEscalating: false, escalationFailure: error.message));
    }
  }

  /// Calls the Action off and keeps what the server sends back, so the Screen
  /// reads `Cancelled` with the note the cancellation wrote rather than
  /// guessing at either.
  Future<void> _onCancellationRequested(
    ActionCancellationRequested event,
    Emitter<ActionDetailState> emit,
  ) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isCancelling) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(cancellationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isCancelling: true, clearCancellationFailure: true));
    try {
      final action = await _actions.cancelAction(token, event.actionId, reason: event.reason);
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          action: action,
          isCancelling: false,
          clearCancellationFailure: true,
          notice: '${action.actionNo} was called off.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(settled.copyWith(isCancelling: false, cancellationFailure: error.message));
    }
  }

  /// Raises a measure and then re-reads the Concern, because the raise answers
  /// with the *measure* — the new Action — and the Screen it was raised from
  /// shows the Concern's measures. Re-reading rather than splicing the response
  /// in is deliberate: the measures are ordered by their kind and their due
  /// date (containment first), so a client that appended its own row would put
  /// it in the wrong place until the next read.
  Future<void> _onMeasureRaised(ActionMeasureRaised event, Emitter<ActionDetailState> emit) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isAddingMeasure) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(measureFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isAddingMeasure: true, clearMeasureFailure: true));
    try {
      final measure = await _actions.raiseMeasure(
        token,
        event.concernId,
        actionType: event.actionType,
        title: event.title,
        description: event.description,
        orgUnitId: event.orgUnitId,
        ownerEmployeeId: event.ownerEmployeeId,
        dueDate: event.dueDate,
        priority: event.priority,
      );
      final refreshed = await _actions.fetchAction(token, event.concernId);
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          action: refreshed,
          isAddingMeasure: false,
          clearMeasureFailure: true,
          notice: '${measure.actionNo} answers this — a ${measure.typeLabel.toLowerCase()}.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(settled.copyWith(isAddingMeasure: false, measureFailure: error.message));
    }
  }

  /// Unlinks one occurrence from this Concern (issue #208) and keeps what the
  /// server sends back, which is the Concern with every occurrence it still
  /// answers — so the Screen reads the list the server just wrote rather than
  /// removing a row itself.
  ///
  /// A refusal is the server's own: the Non-conformance the Concern was raised
  /// from cannot be unlinked, and that sentence is what the dialog shows.
  Future<void> _onNonconformanceUnlinked(
    ActionNonconformanceUnlinked event,
    Emitter<ActionDetailState> emit,
  ) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isUnlinking) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(unlinkFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isUnlinking: true, clearUnlinkFailure: true));
    try {
      final action = await _actions.unlinkNonconformance(
        token,
        event.actionId,
        event.nonconformanceId,
      );
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          action: action,
          isUnlinking: false,
          clearUnlinkFailure: true,
          notice: 'That occurrence is no longer linked to ${action.actionNo}.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(settled.copyWith(isUnlinking: false, unlinkFailure: error.message));
    }
  }

  /// Completes a phase and keeps the Action the server sends back, so the rail
  /// shows the row that was actually written — the next phase, its owner and
  /// its date included — rather than a client's guess at the state machine.
  ///
  /// A refusal is reported twice over, on purpose: in the state, so the Screen
  /// can show it after the dialog closes, and the dialog itself is watching for
  /// the failure it asked for and stays open with the note in it.
  Future<void> _onPhaseCompletionRequested(
    ActionPhaseCompletionRequested event,
    Emitter<ActionDetailState> emit,
  ) async {
    final current = state;
    if (current is! ActionDetailLoaded || current.isCompleting) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(completionFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isCompleting: true, clearCompletionFailure: true));
    try {
      final action = await _actions.completePhase(
        token,
        event.actionId,
        event.phase,
        note: event.note,
        outcome: event.outcome,
      );
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(
        settled.copyWith(
          action: action,
          isCompleting: false,
          clearCompletionFailure: true,
          notice: action.status == 'done'
              ? '${action.actionNo} is closed — its Act named the standard that now holds it.'
              : '${action.actionNo} is waiting on its '
                  '${action.openPhase?.phaseLabel.toLowerCase() ?? 'next'} phase.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! ActionDetailLoaded) return;
      emit(settled.copyWith(isCompleting: false, completionFailure: error.message));
    }
  }
}
