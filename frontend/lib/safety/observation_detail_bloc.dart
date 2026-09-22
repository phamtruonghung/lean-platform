/// One Safety observation's own state (issue #230): the record, read by its
/// id.
///
/// Route-scoped and keyed on the id in the address, the same shape
/// `SafetyIncidentDetailBloc` keeps: go_router reuses a page when the route
/// *pattern* matches, so a second observation's address would otherwise
/// paint the first one's record (issue #183's own bug), and the router keys
/// the provider on the id for it.
///
/// Unlike `SafetyIncidentDetailBloc` there is little to write from this
/// Screen: an observation itself has no status, no event history and no
/// injury-style restriction to read around (#223 decision 9) — it is a fact,
/// read once and shown. The one write is raising an Action from it (issue
/// #231), which lives in the *Actions* Module — its own route, reached
/// through its own client entry point — so this Bloc holds `ActionsApi`
/// beside `SafetyApi`, the same shape `SafetyIncidentDetailBloc` keeps for
/// raising a Concern (issue #229). The raise keeps its own
/// `isRaisingAction`/`actionRaiseFailure`/`notice` fields rather than sharing
/// a general `isMutating`, since a refusal to raise an Action must not look
/// like a refusal to do anything else here — there is nothing else here yet.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
import '../platform/auth_gateway.dart';
import 'safety_api.dart';
import 'safety_observation.dart';

sealed class SafetyObservationDetailEvent {
  const SafetyObservationDetailEvent();
}

class SafetyObservationDetailStarted extends SafetyObservationDetailEvent {
  const SafetyObservationDetailStarted(this.id);

  final String id;
}

class SafetyObservationDetailRefreshed extends SafetyObservationDetailEvent {
  const SafetyObservationDetailRefreshed();
}

/// An Action was raised from this observation (issue #231), in the action
/// log. The dialog decides the kind, the title and the optional fields; the
/// Bloc only ever sees a decision already made — mirrors
/// `SafetyIncidentConcernRaised`.
class SafetyObservationActionRaised extends SafetyObservationDetailEvent {
  const SafetyObservationActionRaised({
    required this.actionType,
    required this.title,
    this.description,
    this.priority,
  });

  final String actionType;
  final String title;
  final String? description;
  final int? priority;
}

sealed class SafetyObservationDetailState {
  const SafetyObservationDetailState();
}

class SafetyObservationDetailLoading extends SafetyObservationDetailState {
  const SafetyObservationDetailLoading();
}

class SafetyObservationDetailUnavailable extends SafetyObservationDetailState {
  const SafetyObservationDetailUnavailable({required this.message, this.isMissing = false});

  final String message;

  /// A 404 rather than a transport or server failure — the Screen offers
  /// "back to the register" instead of "try again".
  final bool isMissing;
}

class SafetyObservationDetailLoaded extends SafetyObservationDetailState {
  const SafetyObservationDetailLoaded({
    required this.observation,
    this.isRaisingAction = false,
    this.actionRaiseFailure,
    this.notice,
  });

  final SafetyObservation observation;

  /// An Action is being raised from this observation, and why the last one
  /// did not land (issue #231). Its own pair rather than a shared
  /// `isMutating`, the same reason `SafetyIncidentDetailLoaded` keeps its own
  /// for raising a Concern.
  final bool isRaisingAction;
  final String? actionRaiseFailure;

  /// What the last Action had to say for itself — the one sentence the
  /// Screen shows once the dialog that asked has closed.
  final String? notice;

  SafetyObservationDetailLoaded copyWith({
    SafetyObservation? observation,
    bool? isRaisingAction,
    String? actionRaiseFailure,
    String? notice,
  }) =>
      SafetyObservationDetailLoaded(
        observation: observation ?? this.observation,
        isRaisingAction: isRaisingAction ?? this.isRaisingAction,
        // Always overwritten, never carried forward.
        actionRaiseFailure: actionRaiseFailure,
        notice: notice,
      );
}

class SafetyObservationDetailBloc
    extends Bloc<SafetyObservationDetailEvent, SafetyObservationDetailState> {
  SafetyObservationDetailBloc({
    required SafetyApi safetyApi,
    required ActionsApi actionsApi,
    required AuthGateway authGateway,
  })  : _api = safetyApi,
        _actions = actionsApi,
        _auth = authGateway,
        super(const SafetyObservationDetailLoading()) {
    on<SafetyObservationDetailStarted>(_onStarted);
    on<SafetyObservationDetailRefreshed>(_onRefreshed);
    on<SafetyObservationActionRaised>(_onActionRaised);
  }

  final SafetyApi _api;

  /// The Actions Module's client, reached through its own entry point:
  /// raising an Action from this observation is a write to the action log,
  /// not to this Module (issue #231).
  final ActionsApi _actions;

  final AuthGateway _auth;
  String? _id;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(
    SafetyObservationDetailStarted event,
    Emitter<SafetyObservationDetailState> emit,
  ) async {
    _id = event.id;
    await _read(emit);
  }

  Future<void> _onRefreshed(
    SafetyObservationDetailRefreshed event,
    Emitter<SafetyObservationDetailState> emit,
  ) async {
    await _read(emit);
  }

  Future<void> _read(Emitter<SafetyObservationDetailState> emit) async {
    final id = _id;
    if (id == null) return;
    emit(const SafetyObservationDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SafetyObservationDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final observation = await _api.fetchSafetyObservation(token, id);
      emit(SafetyObservationDetailLoaded(observation: observation));
    } on SafetyApiException catch (error) {
      emit(
        SafetyObservationDetailUnavailable(
          message: error.message,
          isMissing: error.statusCode == 404,
        ),
      );
    }
  }

  /// An Action was raised from this observation (issue #231).
  ///
  /// The write is the Actions Module's, so it is `ActionsApi` that carries it
  /// and `ActionsApiException` that can refuse it. What comes back is the
  /// *Action*, not this observation, so the observation is re-read
  /// afterwards: the Screen that raised it is this observation's own, and
  /// what it has to show is the Action now named among the ones raised from
  /// it, with the status the server just gave it rather than a client's
  /// guess — mirrors `SafetyIncidentDetailBloc._onConcernRaised`.
  Future<void> _onActionRaised(
    SafetyObservationActionRaised event,
    Emitter<SafetyObservationDetailState> emit,
  ) async {
    final current = state;
    if (current is! SafetyObservationDetailLoaded || current.isRaisingAction) return;
    if (event.title.trim().isEmpty) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(actionRaiseFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRaisingAction: true, actionRaiseFailure: null));
    try {
      final action = await _actions.raiseActionFromSafetyObservation(
        token,
        current.observation.id,
        actionType: event.actionType,
        title: event.title,
        description: event.description,
        priority: event.priority,
      );
      final refreshed = await _api.fetchSafetyObservation(token, current.observation.id);
      final settled = state;
      if (settled is! SafetyObservationDetailLoaded) return;
      emit(
        settled.copyWith(
          observation: refreshed,
          isRaisingAction: false,
          notice: '${action.actionNo} was raised from this Safety observation.',
        ),
      );
    } on ActionsApiException catch (error) {
      final settled = state;
      if (settled is! SafetyObservationDetailLoaded) return;
      emit(settled.copyWith(isRaisingAction: false, actionRaiseFailure: error.message));
    } on SafetyApiException catch (error) {
      // The re-read is this Module's own read and can fail on its own: the
      // Action exists either way, and saying so beats reporting the raise as
      // failed.
      final settled = state;
      if (settled is! SafetyObservationDetailLoaded) return;
      emit(settled.copyWith(isRaisingAction: false, actionRaiseFailure: error.message));
    }
  }
}
