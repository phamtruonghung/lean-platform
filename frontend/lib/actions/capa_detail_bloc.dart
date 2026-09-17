/// One CAPA's own read (issue #209): its number, its team, what the
/// investigation says the problem is, and the Concern it is about — with the
/// Concern's Containments, Countermeasures and Preventive actions and every
/// phase each one has been round.
///
/// Route-scoped like `ActionDetailBloc`, and separate from it for the same
/// reason: the read is one record rather than the register, and a caller who
/// lands here directly (a link sent to a colleague, a refresh) never loads the
/// Site's list first. There is exactly one event — this slice's Screen reads a
/// CAPA and changes nothing about it, because the team and the problem
/// description are set where they are decided: when the investigation is
/// opened.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'actions_api.dart';
import 'capa.dart';

sealed class CapaDetailEvent {
  const CapaDetailEvent();
}

/// Read the CAPA this address names. Its own id, carried down from the route
/// rather than read off a state, so a retry asks for the same record.
class CapaDetailStarted extends CapaDetailEvent {
  const CapaDetailStarted(this.capaId);

  final String capaId;
}

sealed class CapaDetailState {
  const CapaDetailState();
}

class CapaDetailLoading extends CapaDetailState {
  const CapaDetailLoading();
}

class CapaDetailLoaded extends CapaDetailState {
  const CapaDetailLoaded(this.capa);

  final Capa capa;
}

class CapaDetailUnavailable extends CapaDetailState {
  const CapaDetailUnavailable({required this.message});

  final String message;
}

class CapaDetailBloc extends Bloc<CapaDetailEvent, CapaDetailState> {
  CapaDetailBloc({required ActionsApi actionsApi, required AuthGateway authGateway})
      : _actions = actionsApi,
        _auth = authGateway,
        super(const CapaDetailLoading()) {
    on<CapaDetailStarted>(_onStarted);
  }

  final ActionsApi _actions;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(CapaDetailStarted event, Emitter<CapaDetailState> emit) async {
    emit(const CapaDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CapaDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      emit(CapaDetailLoaded(await _actions.fetchCapa(token, event.capaId)));
    } on ActionsApiException catch (error) {
      emit(CapaDetailUnavailable(message: error.message));
    }
  }
}
