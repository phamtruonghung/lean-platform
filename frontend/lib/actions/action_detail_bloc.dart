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
    String? notice,
    bool clearNotice = false,
  }) =>
      ActionDetailLoaded(
        action ?? this.action,
        isCompleting: isCompleting ?? this.isCompleting,
        isAddingMeasure: isAddingMeasure ?? this.isAddingMeasure,
        measureFailure: clearMeasureFailure ? null : (measureFailure ?? this.measureFailure),
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
