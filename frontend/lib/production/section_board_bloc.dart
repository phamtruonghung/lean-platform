/// A Section's production day as the board reads it (issue #339): every shift
/// instance with its handover, and the incoming Team Leader's acknowledgement
/// of one.
///
/// After an acknowledgement the day is read again rather than patched: the
/// latency and the exceptions are the server's to work out against its own
/// clock (`getSectionDay`), and a board that computed them itself would be a
/// second answer to the same question.
///
/// Route-scoped and keyed on the Section and the day in the address, so moving
/// to another day builds a fresh one (issue #183).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'handover.dart';
import 'production_api.dart';

sealed class SectionBoardEvent {
  const SectionBoardEvent();
}

class SectionBoardStarted extends SectionBoardEvent {
  const SectionBoardStarted({required this.orgUnitId, this.date});

  final String orgUnitId;
  final String? date;
}

class HandoverAcknowledgeConfirmed extends SectionBoardEvent {
  const HandoverAcknowledgeConfirmed({
    required this.handoverId,
    this.note,
    required this.changePointResults,
  });

  final String handoverId;
  final String? note;
  final List<Map<String, Object?>> changePointResults;
}

sealed class SectionBoardState {
  const SectionBoardState();
}

class SectionBoardLoading extends SectionBoardState {
  const SectionBoardLoading();
}

class SectionBoardUnavailable extends SectionBoardState {
  const SectionBoardUnavailable({required this.message});

  final String message;
}

class SectionBoardLoaded extends SectionBoardState {
  const SectionBoardLoaded({required this.day, this.isMutating = false, this.mutationFailure});

  final SectionDay day;
  final bool isMutating;

  /// Why the last acknowledgement did not land, reported by the dialog that
  /// made it, which stays open.
  final String? mutationFailure;

  SectionBoardLoaded copyWith({SectionDay? day, bool? isMutating, String? mutationFailure}) => SectionBoardLoaded(
        day: day ?? this.day,
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
      );
}

class SectionBoardBloc extends Bloc<SectionBoardEvent, SectionBoardState> {
  SectionBoardBloc({required ProductionApi productionApi, required AuthGateway authGateway})
      : _api = productionApi,
        _auth = authGateway,
        super(const SectionBoardLoading()) {
    on<SectionBoardStarted>(_onStarted);
    on<HandoverAcknowledgeConfirmed>(_onAcknowledgeConfirmed);
  }

  final ProductionApi _api;
  final AuthGateway _auth;

  String? _orgUnitId;
  String? _date;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(SectionBoardStarted event, Emitter<SectionBoardState> emit) async {
    _orgUnitId = event.orgUnitId;
    _date = event.date;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SectionBoardUnavailable(message: signedOutMessage));
      return;
    }
    emit(const SectionBoardLoading());
    try {
      emit(SectionBoardLoaded(day: await _api.fetchSectionDay(token, event.orgUnitId, date: event.date)));
    } on ProductionApiException catch (error) {
      emit(SectionBoardUnavailable(message: error.message));
    }
  }

  Future<void> _onAcknowledgeConfirmed(
    HandoverAcknowledgeConfirmed event,
    Emitter<SectionBoardState> emit,
  ) async {
    final current = state;
    if (current is! SectionBoardLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true));
    try {
      await _api.acknowledgeHandover(
        token,
        event.handoverId,
        note: event.note,
        changePointResults: event.changePointResults,
      );
      // The day this board shows, read again: an omitted date would be the
      // Site's today, which is not necessarily the day on screen.
      final day = await _api.fetchSectionDay(token, _orgUnitId!, date: _date ?? current.day.productionDate);
      emit(SectionBoardLoaded(day: day));
    } on ProductionApiException catch (error) {
      emit(current.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
