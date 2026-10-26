/// One Shift handover's own state (issue #339): opening or resuming the draft
/// for a Section's shift instance, the writes its six blocks make while it is
/// a draft, and submit.
///
/// **Opening reads before it writes.** The Section's day says whether the
/// shift already has a live handover; if it does, that one is read (a draft
/// resumed, or a sealed one shown as it was sealed), and only if it does not is
/// a draft opened. Opening first and reading on a 409 would work too, but would
/// make every visit to a sealed handover a refused write. A day read without a
/// date is the Site's today, so the board passes the day it was showing.
///
/// Route-scoped and keyed on the Section and shift instance in the address, for
/// the reason `ComplaintDetailBloc` is keyed on its id (issue #183).
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'handover.dart';
import 'production_api.dart';

sealed class ShiftHandoverEvent {
  const ShiftHandoverEvent();
}

class ShiftHandoverStarted extends ShiftHandoverEvent {
  const ShiftHandoverStarted({required this.orgUnitId, required this.shiftInstanceId, this.date});

  final String orgUnitId;
  final String shiftInstanceId;
  final String? date;
}

/// One Asset's Machine status line, written whole.
class MachineLineSaved extends ShiftHandoverEvent {
  const MachineLineSaved({required this.assetId, required this.line});

  final String assetId;
  final Map<String, Object?> line;
}

/// Header fields: "no change points this shift" and the handover evidence.
class HandoverHeaderSaved extends ShiftHandoverEvent {
  const HandoverHeaderSaved(this.fields);

  final Map<String, Object?> fields;
}

class ChangePointAdded extends ShiftHandoverEvent {
  const ChangePointAdded({required this.dimension, required this.description, required this.watchNote});

  final String dimension;
  final String description;
  final String watchNote;
}

class ChangePointRemoved extends ShiftHandoverEvent {
  const ChangePointRemoved(this.changePointId);

  final String changePointId;
}

class ActionDispositioned extends ShiftHandoverEvent {
  const ActionDispositioned({
    required this.actionId,
    required this.disposition,
    this.ownerEmployeeId,
    this.closureNote,
  });

  final String actionId;
  final String disposition;
  final String? ownerEmployeeId;
  final String? closureNote;
}

class ActionLinkRemoved extends ShiftHandoverEvent {
  const ActionLinkRemoved(this.linkId);

  final String linkId;
}

class HandoverSubmitted extends ShiftHandoverEvent {
  const HandoverSubmitted();
}

sealed class ShiftHandoverState {
  const ShiftHandoverState();
}

class ShiftHandoverLoading extends ShiftHandoverState {
  const ShiftHandoverLoading();
}

class ShiftHandoverUnavailable extends ShiftHandoverState {
  const ShiftHandoverUnavailable({required this.message});

  final String message;
}

class ShiftHandoverLoaded extends ShiftHandoverState {
  const ShiftHandoverLoaded({
    required this.handover,
    required this.assets,
    this.isMutating = false,
    this.mutationFailure,
    this.refusal,
  });

  final ShiftHandover handover;

  /// The Section's active Assets: one Machine status line row each.
  final List<SectionAsset> assets;

  final bool isMutating;

  /// Why the last write did not land, shown at the top of the form.
  final String? mutationFailure;

  /// Submit's named gaps, when the last submit was refused for them.
  final HandoverRefusal? refusal;

  ShiftHandoverLoaded copyWith({
    ShiftHandover? handover,
    bool? isMutating,
    String? mutationFailure,
    HandoverRefusal? refusal,
  }) =>
      ShiftHandoverLoaded(
        handover: handover ?? this.handover,
        assets: assets,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward.
        mutationFailure: mutationFailure,
        refusal: refusal,
      );
}

class ShiftHandoverBloc extends Bloc<ShiftHandoverEvent, ShiftHandoverState> {
  ShiftHandoverBloc({required ProductionApi productionApi, required AuthGateway authGateway})
      : _api = productionApi,
        _auth = authGateway,
        super(const ShiftHandoverLoading()) {
    on<ShiftHandoverStarted>(_onStarted);
    on<MachineLineSaved>(
      (event, emit) => _mutate(
        emit,
        (token, id) => _api.putMachineLine(token, id, assetId: event.assetId, line: event.line),
      ),
    );
    on<HandoverHeaderSaved>(
      (event, emit) => _mutate(emit, (token, id) => _api.updateHandover(token, id, event.fields)),
    );
    on<ChangePointAdded>(
      (event, emit) => _mutate(
        emit,
        (token, id) => _api.addChangePoint(
          token,
          id,
          dimension: event.dimension,
          description: event.description,
          watchNote: event.watchNote,
        ),
      ),
    );
    on<ChangePointRemoved>(
      (event, emit) => _mutate(emit, (token, id) => _api.deleteChangePoint(token, id, event.changePointId)),
    );
    on<ActionDispositioned>(
      (event, emit) => _mutate(
        emit,
        (token, id) => _api.linkAction(
          token,
          id,
          actionId: event.actionId,
          disposition: event.disposition,
          ownerEmployeeId: event.ownerEmployeeId,
          closureNote: event.closureNote,
        ),
      ),
    );
    on<ActionLinkRemoved>(
      (event, emit) => _mutate(emit, (token, id) => _api.unlinkAction(token, id, event.linkId)),
    );
    on<HandoverSubmitted>((event, emit) => _mutate(emit, _api.submitHandover));
  }

  final ProductionApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(ShiftHandoverStarted event, Emitter<ShiftHandoverState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ShiftHandoverUnavailable(message: signedOutMessage));
      return;
    }
    emit(const ShiftHandoverLoading());
    try {
      final day = await _api.fetchSectionDay(token, event.orgUnitId, date: event.date);
      final assets = await _api.fetchSectionAssets(token, event.orgUnitId);
      final live = day.shiftFor(event.shiftInstanceId)?.handover;
      final handover = live != null
          ? await _api.fetchHandover(token, live.id)
          : await _api.openHandover(
              token,
              orgUnitId: event.orgUnitId,
              shiftInstanceId: event.shiftInstanceId,
            );
      emit(ShiftHandoverLoaded(handover: handover, assets: assets));
    } on ProductionApiException catch (error) {
      emit(ShiftHandoverUnavailable(message: error.message));
    }
  }

  Future<void> _mutate(
    Emitter<ShiftHandoverState> emit,
    Future<ShiftHandover> Function(String token, String handoverId) write,
  ) async {
    final current = state;
    if (current is! ShiftHandoverLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage, refusal: current.refusal));
      return;
    }

    emit(current.copyWith(isMutating: true, refusal: current.refusal));
    try {
      final handover = await write(token, current.handover.id);
      emit(current.copyWith(handover: handover, isMutating: false));
    } on ProductionApiException catch (error) {
      emit(
        current.copyWith(
          isMutating: false,
          mutationFailure: error.refusal == null ? error.message : null,
          refusal: error.refusal,
        ),
      );
    }
  }
}
